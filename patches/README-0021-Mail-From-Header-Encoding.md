# Patch 0021: From-Header RFC-2047-kodiert & konfigurierbarer Absender

## Problem

Strenge Provider (GMX, GMX.at, web.de, T-Online, 1&1/mail.com) weisen Mails mit
**Hard-Bounce GMX r0710** („Reject due to policy restrictions") ab, wenn der
Anzeigename im `From` rohe 8-bit-Umlaute enthält — das verletzt RFC 5322/2047.

`mailutil.Headers()` kodierte bisher **nur** den `Subject`; `From`/`To` liefen bloß
durch `SanitizeHeaderValue`. Betroffen war damit ausschließlich der **Massenversand**
(`member_email.go`), der den EEG-Namen als Anzeigenamen davorsetzte:

```go
from = fmt.Sprintf("%s <%s>", fromName, smtpCfg.From)  // "EEG Grünes Licht Bad Vöslau <kontakt@…>"
```

Die Direktmails (Portal-Login, App-Pairing, Rechnung, SEPA-Mandat) verwenden
`eeg.SMTPFrom` unverändert — steht dort die nackte Adresse, ist der Header unkritisch.
Deshalb kamen genau diese Mails bisher durch, während Kampagnen bouncten.

## Was der Patch baut

**1. `EncodeAddress(s)`** — sanitisiert und RFC-2047-kodiert **nur** den Anzeigenamen;
die Adresse bleibt unangetastet. Nicht parsebare Werte und solche ohne Anzeigenamen
kommen sanitisiert, aber sonst unverändert zurück. `SanitizeHeaderValue` läuft auf
**jedem** Pfad zuerst — der Header-Injection-Schutz bleibt vollständig erhalten.

**2. `ComposeFrom(configuredFrom, fallbackName)`** — der Kernwunsch:
- `configuredFrom` hat bereits einen Anzeigenamen → **wörtlich** übernommen, der
  konfigurierte Wert gewinnt, es wird **kein** zweiter Name davorgesetzt.
- `configuredFrom` ist eine nackte Adresse + `fallbackName` gesetzt → `Name <addr>`
  (bisheriges Verhalten, abwärtskompatibel).
- sonst unverändert.

**3. `Headers()`** nutzt jetzt `EncodeAddress` für `From` **und** `To`.

**4. `member_email.go`** ersetzt die Inline-`fmt.Sprintf`-Logik durch `ComposeFrom`.

Ergebnis (verifiziert, siehe Abnahme):

| `smtp_from` | Ergebnis im `From` |
|---|---|
| `kontakt@eeg-gruenlicht.at` + EEG-Name mit Umlaut | `=?utf-8?q?EEG_Gr=C3=BCnes_Licht_Bad_V=C3=B6slau?= <kontakt@eeg-gruenlicht.at>` |
| `EEG Gruenes Licht Bad Voeslau Sooss <kontakt@eeg-gruenlicht.at>` | **byte-identisch** übernommen |
| `EEG Grünes Licht <kontakt@…>` | nur der Name kodiert |
| nackte Adresse, kein Fallback-Name | unverändert |

## ⚠️ Zwei Abweichungen vom Auftrag

**1. `EncodeAddress` nutzt bewusst NICHT durchgängig `mail.Address.String()`.**
Der Vorschlag im Auftrag hätte das eigene Abnahmekriterium 3 verfehlt. Empirisch
geprüft mit Go 1.23:

```
"EEG Gruenes Licht Bad Voeslau Sooss <kontakt@eeg-gruenlicht.at>"
   -> "EEG Gruenes Licht Bad Voeslau Sooss" <kontakt@eeg-gruenlicht.at>   ← Anführungszeichen!
"kontakt@eeg-gruenlicht.at"
   -> <kontakt@eeg-gruenlicht.at>                                          ← Winkelklammern!
```

`Address.String()` quotet **jeden** Anzeigenamen und macht aus einer nackten Adresse
`<addr>`. Beides ist gültiges RFC 5322, aber es hätte (a) die geforderte
Byte-Identität gebrochen und (b) den `From` **sämtlicher** Direktmails ohne Not
umgeschrieben. Deshalb: Ein bereits unquoted zulässiger Anzeigenamen (druckbares
US-ASCII, keine RFC-5322-Specials, kein Rand-Whitespace → `isPlainDisplayName`) wird
wörtlich ausgegeben; nur wenn der Name Quoting oder Kodierung **benötigt**, übernimmt
`addr.String()`. Nackte Adressen bleiben nackt.

**2. Der `eda-worker` ruft `mailutil.Headers()` sehr wohl auf** — der Auftrag nimmt
das Gegenteil an. Belegt in `api/internal/eda/worker.go` an vier Stellen (Zeilen
1820, 1902, 1986, 2086: Fehler-, Mismatch- und Smartmeter-Benachrichtigungen). Heute
ändert sich dort nichts, weil `eeg.SMTPFrom` meist die nackte Adresse ist — sobald der
Betreiber aber den vollen `Name <addr>`-Wert einträgt, gilt er auch für diese Mails.
Der Worker ist deshalb **mitzubauen**, nicht optional. `eda/transport/mail.go`
(edanet-Gateway) baut eigene Header und bleibt wie gefordert unangetastet.

## Betroffene Dateien

| Datei | Änderung |
|---|---|
| `api/internal/mailutil/header.go` | `EncodeAddress`, `isPlainDisplayName`, `ComposeFrom`; `Headers()` kodiert `From`/`To` |
| `api/internal/mailutil/header_test.go` | 10 neue Tests (Byte-Identität, Umlaut-Kodierung, nackte Adresse, Injection, ComposeFrom-Fälle, End-to-End) |
| `api/internal/handler/member_email.go` | `sendHTMLEmail` nutzt `mailutil.ComposeFrom` |

**Keine DB-Migration**, kein neues Feld, keine UI-Änderung. `smtp_from` bleibt ein
Freitextfeld und nimmt jetzt zusätzlich die volle `Name <addr>`-Form an.

## Deploy

Reiner Code-Change. **`eegabrechnung-api` und `eegabrechnung-eda-worker` neu bauen**
(Begründung siehe Abweichung 2). Kein Web-Rebuild, keine Migration.

Danach kann der Betreiber unter „System → E-Mail Versand (Rechnungen)" im Feld
„Absender-Adresse (From)" den vollen Wert eintragen:

```
EEG Gruenes Licht Bad Voeslau Sooss <kontakt@eeg-gruenlicht.at>
```

Dieser wird ab dann in **allen** Mailtypen unverändert verwendet.

## Abnahme

Alle gegen `v2026-07-13` + Patches 0002–0021 verifiziert:

- `go test ./internal/mailutil/...` → **13/13 grün**, inklusive des unveränderten
  `TestHeadersNoInjection` (die 3-Zeilen-/CRLF-Invariante hält).
- `go build ./...` und `go vet` fehlerfrei.
- Funktionsprobe:
  ```
  From: EEG Gruenes Licht Bad Voeslau Sooss <kontakt@eeg-gruenlicht.at>
  From: =?utf-8?q?EEG_Gr=C3=BCnes_Licht_Bad_V=C3=B6slau?= <kontakt@eeg-gruenlicht.at>
  ```
  Erste Zeile byte-identisch zur Eingabe (kein Präfix, keine Kodierung), zweite mit
  kodiertem Namen vor unveränderter Adresse.
- Praxistest nach dem Deploy: Kampagne an eine GMX-Adresse senden — kein r0710-Bounce.
  `email_log` (`status='sent'`) und das Postfach gegenprüfen.
