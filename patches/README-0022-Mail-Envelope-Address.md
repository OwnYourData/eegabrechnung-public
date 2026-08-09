# Patch 0022: SMTP-Envelope-Adresse vom Anzeigenamen trennen

**Hängt logisch an Patch 0021** und ist die Voraussetzung dafür, dass im Feld
`smtp_from` überhaupt ein Anzeigename gesetzt werden darf. **Erst 0022 deployen,
dann den vollen `Name <addr>`-Wert eintragen** — in der umgekehrten Reihenfolge
schlägt jeder Versand fehl.

## Problem

Patch 0021 hat den **Header**-`From` korrekt gemacht. `eeg.SMTPFrom` wird aber
zusätzlich als **SMTP-Envelope-Adresse** verwendet, und dort ist ein Anzeigename
unzulässig: `net/smtp` schreibt den Wert **roh** in `MAIL FROM:<…>` bzw.
`RCPT TO:<…>` (nur CR/LF-Prüfung, keine Adress-Extraktion). Aus
`EEG X <kontakt@…>` wird also `MAIL FROM:<EEG X <kontakt@…>>` → **SMTP 501**.

Ohne diesen Patch würde das Eintragen eines Anzeigenamens **jeden** Mailversand
über `SendLogged`, den `BulkSender` und die Onboarding-Erinnerungen brechen.

## Was der Patch baut

**`mailutil.EnvelopeAddress(s)`** — liefert die reine Adresse (`local@domain`) aus
einem Wert, der auch `Name <addr>` sein kann; Fallback auf den sanitisierten Rohwert,
wenn nichts parst. **`mailutil.EnvelopeAddresses(ss)`** mappt das über eine
Empfängerliste.

Eingesetzt an **allen** Envelope-Grenzen:

| Stelle | Änderung |
|---|---|
| `invoice/log.go` → `SendLogged` | `MAIL FROM` **und** `RCPT TO` auf die reine Adresse reduziert |
| `invoice/smtp_bulk.go` → `NewBulkSender` | `from` wird beim Anlegen reduziert (wirkt auf `client.Mail`) |
| `invoice/smtp_bulk.go` → `sendOnce` | `client.Rcpt(EnvelopeAddress(to))` |
| `handler/onboarding.go` (2×) | direkte `smtp.SendMail`-Aufrufe: Absender **und** Empfängerliste reduziert |

Weil die Reduktion **zentral in `SendLogged`** sitzt, sind damit automatisch alle
sechs Aufrufer abgedeckt, die `eeg.SMTPFrom` als *Empfänger* verwenden
(`member_portal.go` 844/962, `eda/worker.go` 1827/1909, `billing/gap_checker.go` 169,
`billing/scheduler.go` 256) — der Auftrag hatte davon drei gelistet.

Das Log-Feld `ToAddress` behält bewusst den ursprünglichen `to`-Wert: Es ist ein
Protokoll für Menschen, keine Envelope-Angabe.

## ⚠️ Zwei Lücken im Auftrag, die mitbehoben wurden

**1. Ein dritter Sendepfad fehlte in der Fundstellenliste.**
`handler/onboarding.go` verschickt die beiden 72h-Erinnerungen **nicht** über
`SendLogged`, sondern direkt:

```
onboarding.go:1524   smtp.SendMail(smtpCfg.Host, auth, smtpCfg.From, recipients, msgBytes)
onboarding.go:1602   smtp.SendMail(smtpCfg.Host, auth, smtpCfg.From, recipients, msgBytes)
```

Beide hätten mit einem Anzeigenamen SMTP-501 geliefert — und `recipients` enthält
neben dem Antragsteller auch die Admin-Adresse, also war auch `RCPT TO` betroffen.
Mitbehoben.

**2. Patch 0021 hat sieben `From:`-Header nicht erfasst.**
`onboarding.go` baut seine Header **von Hand** statt über `mailutil.Headers()`:

```
Zeilen 1009, 1190, 1266, 1350, 1506, 1583, 1968
```

Diese Mails (Admin-Benachrichtigung, Statuslink, Bestätigung, Erinnerungen) liefen
weiterhin mit rohem `smtpCfg.From` im Header. Solange dort eine nackte Adresse steht,
ist das folgenlos — trägt der Betreiber aber einen Anzeigenamen **mit Umlauten** ein,
produzieren genau diese sieben Mailtypen weiterhin den r0710-Bounce, den 0021
beseitigen sollte. Alle sieben laufen jetzt über `mailutil.EncodeAddress`.

Der Auftrag schrieb „Header-Konstruktion aus 0021 bleibt wie sie ist" — diese Vorgabe
setzt voraus, dass 0021 alle Header erfasst hat. Für `onboarding.go` traf das nicht zu.
Für nackte Adressen ist `EncodeAddress` ein No-Op, das Risiko der Ergänzung also null.

`eda/transport/mail.go` (edanet-Gateway, eigenes `EDA_SMTP_FROM`, bare/ASCII) bleibt
wie gefordert unangetastet.

## Betroffene Dateien

| Datei | Änderung |
|---|---|
| `api/internal/mailutil/header.go` | `EnvelopeAddress`, `EnvelopeAddresses` |
| `api/internal/mailutil/header_test.go` | 7 neue Tests |
| `api/internal/invoice/log.go` | Envelope-Absender + -Empfänger reduziert (Import `mailutil`) |
| `api/internal/invoice/smtp_bulk.go` | Envelope-Absender + `Rcpt` reduziert (Import `mailutil`) |
| `api/internal/handler/onboarding.go` | 2 direkte `SendMail` + 7 handgebaute `From:`-Header |

**Keine DB-Migration**, keine UI-/Feldänderung.

## Deploy & Reihenfolge

Reiner Code-Change. **`eegabrechnung-api` und `eegabrechnung-eda-worker`** neu bauen
(beide nutzen den Sendepfad; der Worker hat ein eigenes Dockerfile). Kein Web-Rebuild.

**Reihenfolge ist zwingend:** Erst 0022 ausrollen, **danach** unter „System → E-Mail
Versand (Rechnungen)" den vollen Wert eintragen:

```
EEG Gruenes Licht Bad Voeslau Sooss <kontakt@eeg-gruenlicht.at>
```

Vorher wäre der Envelope-`MAIL FROM` ungültig und der Versand bräche komplett.

## Abnahme

Verifiziert gegen `v2026-07-13` + Patches 0002–0022:

- `go test ./internal/mailutil/...` → **20/20 grün** (13 aus 0021 + 7 neue).
- `go build ./...` und `go vet` fehlerfrei.
- Invariante aus 0021 + 0022 als Test festgehalten
  (`TestHeaderKeepsNameEnvelopeStripsIt`): derselbe konfigurierte Wert liefert
  `From: EEG Gruenes Licht Bad Voeslau Sooss <kontakt@eeg-gruenlicht.at>` im **Header**
  und `kontakt@eeg-gruenlicht.at` im **Envelope**.
- Praxisprobe nach dem Deploy: vollen Wert eintragen, dann je eine Rechnungsmail
  (`SendLogged`), eine Kampagne (`BulkSender`) und eine Onboarding-Erinnerung
  auslösen — alle drei Pfade müssen zustellen, `email_log` zeigt `status='sent'`.
