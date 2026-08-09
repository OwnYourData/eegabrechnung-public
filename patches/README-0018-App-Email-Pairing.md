# Patch 0018: E-Mail-Pairing (Magic-Link) — Abrechnungs-seitiger Mint+Send

Der einfachste, iOS-sichere Weg, die App zu verbinden: Mitglied gibt in der App
seine E-Mail-Adresse ein → bekommt einen Verbindungs-Link per Mail → tippt ihn
**aus der Mail-App** an → App öffnet sich und ist verbunden. (Aus der Mail-App
öffnet iOS den Universal Link zuverlässig — anders als ein Tap im Portal auf
derselben Domain, siehe Patch 0015.)

## Wer macht was

`POST /api/app/pair/email` ruft die **App** an ihrer festen Basis
`https://api.eeg-gruenlicht.at/api` — der Endpoint liegt also auf der
**GrünLicht-API** (dort, wo `/app/pair/start` und `/app/pair/status/:id` schon
sind). Nur diese Abrechnungs-Seite besitzt aber den **ES256-Signaturschlüssel**,
die **E-Mail-Adressen der Mitglieder** und den **per-EEG-SMTP-Versand** (die
GrünLicht-API liest nur die read-only-Views, in denen `email` bewusst fehlt).

Deshalb die Aufteilung:

| Teil | Wo | Status |
|---|---|---|
| Öffentl. `POST /api/app/pair/email` (Rate-Limit 3/h pro E-Mail+IP, generische 200/202, kein DPoP) | GrünLicht-API | **deren Seite** |
| Token minten (`src:"email"`, 10 min) + Magic-Link-Mail senden | **Abrechnung (dieser Patch)** | ✅ |
| Auto-Confirm bei `/pair/start`, wenn Token `source='email'` | GrünLicht-API | **deren Seite** (Rück-Handover) |
| Single-Use-Entwertung des Tokens | GrünLicht-API (in ihrer DB) | **deren Seite** |

Die GrünLicht-API ruft nach ihrer Rate-Limit-/Generik-Prüfung **intern** unseren
neuen Endpoint.

## Was der Patch baut (Abrechnungs-Seite)

**1. Interner Endpoint `POST /internal/app/pair/email`** (`portal_app_email_pairing.go`)
- Auth: `X-Service-Token` (konstantzeit) == Env `INTERNAL_SERVICE_TOKEN` — **dasselbe
  Shared Secret**, das die Abrechnung schon in die Gegenrichtung nutzt
  (Portal → GrünLicht-API, Patch 0007). Nur in-cluster erreichbar, nie über das
  öffentliche Ingress.
- Body `{"email":"…"}`. Für **jedes aktive Mitglied** mit dieser Adresse
  (`FindMembersByEmail`, `status != 'INACTIVE'`) wird ein frisches QR-Format-Token
  gemintet und die Mail verschickt. Person in mehreren EEGs → eine Mail pro
  Mitgliedschaft, je über die SMTP-Konfiguration der jeweiligen EEG. **Demo-EEGs
  senden nie.**
- Antwort **immer `202 Accepted`**, egal ob eine Adresse traf — kein
  Existenz-Signal (Enumeration-Schutz + Rate-Limit liegen ohnehin auf der
  GrünLicht-API). `503` nur bei Fehlkonfiguration (kein Service-Token / kein
  Signaturschlüssel gesetzt), `401` bei falschem Service-Token, `400` bei leerem Body.

**2. Token-Kennzeichnung** — zwei Wege, damit beide Seiten es erkennen:
- **JWT-Claim** `src:"email"` (`signAppJWT` bekommt einen `src`-Parameter,
  `omitempty`). Das **QR-Token bleibt byte-identisch** (QR ruft mit `src=""` → Feld
  entfällt). Signal für die App.
- **DB-Spalte** `source='email'` auf `app_login_tokens` (Migration 091, Default
  `'qr'`), sichtbar in `app_readonly.app_login_token_view` als `source`. **Das** ist
  das serverseitige Signal für den Auto-Confirm — bei `/pair/start` sieht die
  GrünLicht-API nur den `tok`-Hash über die View, nicht die JWT-Claims.

**3. TTL & Einmal-Nutzung** — 10 Minuten (`emailPairingTTL`). Single-Use erzwingt
die GrünLicht-API in ihrer eigenen DB (wie bei QR/Kurzcode) — die Abrechnung bleibt
auf dieser DB read-only für die API. Der stündliche Cleanup (Patch 0004) räumt
abgelaufene Tokens weg.

## Sicherheit

- Identität = Besitz des Mail-Links (Magic-Link-Prinzip); der Link ging **nur** an
  die in der Abrechnung hinterlegte Adresse.
- Kein Geheimnis in der Mail außer dem kurzlebigen Einmal-Link.
- Gerätebindung (DPoP/`deviceKey`) passiert unverändert erst bei `/pair/start` auf
  der GrünLicht-API.
- Missbrauch (weitergeleitete Mail) durch 10-Min-TTL + Einmal-Nutzung begrenzt.

## Betroffene Dateien

| Datei | Änderung |
|---|---|
| `api/internal/db/migrations/091_app_login_token_source.{up,down}.sql` | **neu** — `source`-Spalte (Default `'qr'`) |
| `api/internal/handler/portal_app_email_pairing.go` | **neu** — interner Endpoint + Mailversand |
| `api/internal/handler/portal_app_token.go` | `signAppJWT` bekommt `src`-Claim (`omitempty`); QR-Aufruf `src=""` (Token unverändert) |
| `api/internal/repository/member_portal.go` | `CreateAppLoginTokenEmail` (`code_hash` NULL, `source='email'`) |
| `api/cmd/server/main.go` | Route `POST /internal/app/pair/email` |
| `patches/0004-app_readonly-gruenlicht.sql` | View `app_login_token_view` liefert jetzt zusätzlich `source` |

Betrifft **API** (+ Migration → **Worker mitbauen!**), **keine Web-Änderung**.
**Keine neuen Env-Vars** — `PORTAL_APP_QR_KID`/`PORTAL_APP_QR_PRIVKEY` und
`INTERNAL_SERVICE_TOKEN` sind bereits am API-Deployment gesetzt.

## Deploy

1. `api` **und** `eda-worker` neu bauen (die Migration 091 ist in **beide** Images
   eingebettet — der Worker crasht sonst mit „no migration found for version 91").
2. Nach dem Deploy (Migration 091 gelaufen) die aktualisierte
   `patches/0004-app_readonly-gruenlicht.sql` als DB-Superuser **erneut ausführen**
   (idempotentes DROP+CREATE) — dann liefert `app_login_token_view` die `source`-Spalte.
3. GrünLicht-Team: Auto-Confirm + Single-Use auf ihrer Seite scharf schalten
   (siehe Rück-Handover), dann `--dart-define=ENABLE_EMAIL_PAIRING=true`.

## Abnahme

- `POST /internal/app/pair/email` mit gültigem `X-Service-Token` + bekannter,
  aktiver Adresse → `202`, Mitglied erhält die Verbindungs-Mail.
- Unbekannte Adresse → **ebenfalls `202`**, keine Mail.
- Falscher/fehlender `X-Service-Token` → `401`/`503`, nie eine Mail.
- Link in der Mail am Handy antippen → App öffnet sich; nach `/pair/start` liefert
  `/pair/status/:id` direkt `confirmed` (Auto-Confirm, GrünLicht-Seite) — **ohne**
  Portal-Bestätigung.
- QR-/Kurzcode-Weg unverändert (weiterhin mit Portal-Bestätigung); QR-JWT unverändert.
