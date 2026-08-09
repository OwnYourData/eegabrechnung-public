# Patch 0023: E-Mail-Pairing-Link kürzen (roher Token statt JWT)

## ⚠️ Deploy-Reihenfolge zuerst

**Dieser Patch darf erst ausgerollt werden, NACHDEM die GrünLicht-Seite ihren
`POST /api/app/pair/start` (und das App-Link-Handling) so angepasst hat, dass er auch
einen rohen Token akzeptiert.** Vorher schlagen alle E-Mail-Pairings fehl, weil die
Gegenseite den Token nicht auflösen kann. Die Gegenseite baut abwärtskompatibel
(JWT **und** roher Token), damit bereits verschickte Links weiterlaufen — deshalb ist
die Reihenfolge „GrünLicht zuerst, dann wir" ausreichend, ein Wartungsfenster ist
nicht nötig.

## Problem

Die Verbindungs-Mail landete bei einzelnen Empfängern im Spam. Auslöser ist der
Magic-Link: Er trug den vollständigen ES256-JWT in der URL — eine sehr lange,
zufällig aussehende Zeichenkette, ein klassisches Spam-/Phishing-Merkmal.

Das eigentliche Geheimnis ist aber nur der 32-Byte-Zufallstoken, der ohnehin bereits
als SHA-256-Hash in `app_login_tokens` liegt. Die JWT-Hülle wird nur für den QR-Weg
gebraucht (dort soll die App offline verifizieren können) — im E-Mail-Weg ist sie
überflüssig.

## Was der Patch baut

Der E-Mail-Link trägt künftig den rohen `loginToken`:

```
vorher:  …/app/pair?t=eyJhbGciOiJFUzI1NiIsInR5cCI6…   Link 399 Zeichen
nachher: …/app/pair?t=AFrjoY0gm6XP0IrCBaDJz6myZcD8EqgAwIY6vc630SI   Link 91 Zeichen
```

Gemessen: Token **43** Zeichen statt JWT **351** Zeichen → der Link wird um **308
Zeichen kürzer**. Der Token enthält weder Punkte noch das `eyJ`-Präfix, sieht also
nicht mehr nach einem strukturierten Blob aus.

Zusätzlich entfällt im E-Mail-Pfad der nun tote Signatur-Code: das Lesen von
`PORTAL_APP_QR_KID`/`PORTAL_APP_QR_PRIVKEY`, die `503 "app connect not configured"`-
Bedingung und der `parseP256PrivKeyMultibase`-Aufruf. Netto **−24 / +16** Zeilen.

## Sicherheit — gleichwertig, nicht schwächer

Die Vertrauensentscheidung hing nie an der JWT-Signatur, sondern an vier Dingen, die
alle unverändert bleiben:

- **256 Bit Zufall** aus `crypto/rand` (unverändert erzeugt),
- **DB-Hash-Lookup**: Nur ein Token, dessen SHA-256 in `app_login_tokens` steht, löst
  auf — ein Angreifer kann keine Zeile anlegen,
- **Single-Use** (GrünLicht-seitig) und **10-Minuten-TTL**,
- **Zustellung ausschließlich an die registrierte Adresse** — der Postfachbesitz ist
  der Identitätsnachweis.

Eine Signatur hätte hier nichts ergänzt: Ein selbst erfundener Token scheitert am
Hash-Lookup, unabhängig davon, ob er signiert ist.

**Konsequenz, die man kennen sollte:** Der Claim `src:"email"` verschwindet aus dem
E-Mail-Pfad, weil es kein JWT mehr gibt. Das ist unkritisch, weil der maßgebliche
Auto-Confirm-Schalter die Spalte `source` in `app_readonly.app_login_token_view` ist —
die GrünLicht-API liest bei `/pair/start` ohnehin nur den `token_hash` und daraus
`source`, nicht die JWT-Claims. Falls die **App** den Claim für UX-Zwecke ausgewertet
hat, muss sie sich künftig auf die Pairing-Antwort stützen.

## Unverändert

Token-Erzeugung (`base64url(32 Byte)`, `hex(sha256(...))`,
`CreateAppLoginTokenEmail(... source='email')`), TTL, Single-Use, Enumeration-Schutz,
der `202`/`401`/`400`-Kontrakt, der **QR-/Kurzcode-Weg** (`portal_app_token.go`,
`signAppJWT` bleibt bestehen und wird weiter vom QR-Pfad aufgerufen), DB-Schema,
`app_login_token_view`, Mail-Header-Code aus 0021/0022.

## Betroffene Dateien

| Datei | Änderung |
|---|---|
| `api/internal/handler/portal_app_email_pairing.go` | Link mit rohem Token; Signaturschlüssel-Block und `signAppJWT`-Aufruf entfernt; Doc-Kommentar nachgezogen |

**Keine DB-Migration**, keine weitere Datei.

## Deploy

Reiner Code-Change. Nur **`eegabrechnung-api`** neu bauen und ausrollen — der Endpoint
läuft im API-Prozess, der `eda-worker` ist nicht betroffen (er ruft `AppPairEmail`
nicht auf). Kein Web-Rebuild.

**Erst nach der GrünLicht-Anpassung ausrollen** (siehe oben).

## Abnahme

Verifiziert gegen `v2026-07-13` + Patches 0002–0023:

- `go build ./...` und `go vet ./...` fehlerfrei — keine ungenutzten Imports oder
  Variablen nach dem Entfernen des JWT-Codes (`os`/`strings` werden weiterhin für den
  Service-Token und den URL-Aufbau gebraucht).
- Linkform gemessen: `?t=` + 43 Zeichen base64url, **kein** `eyJ`-Präfix, **keine**
  Punkte; Link 91 statt 399 Zeichen.
- `signAppJWT` wird nur noch aus `portal_app_token.go:94` (QR-Pfad) aufgerufen.
- Nach dem Deploy: Pairing-Mail auslösen und innerhalb von 10 Minuten prüfen, dass in
  `app_login_tokens` weiterhin eine Zeile mit `source='email'` entsteht — und dass das
  Antippen des Links die App verbindet.
