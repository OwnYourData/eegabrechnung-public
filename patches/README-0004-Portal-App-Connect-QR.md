# Patch 0004: „App verbinden" — QR-Code ohne Personenbezug (Login-Token)

> **Konsolidiert.** Dieser Patch enthält den früheren Patch 0006 („QR ohne PII"). Der ursprüngliche 0004 signierte noch die Mitglieds-UUID in den QR (`{"user": …}`) und wurde von 0006 sofort wieder überschrieben — ein Zwischenzustand, der nie lief. Beide sind hier zu **einem** Patch zusammengefasst, der direkt den Endstand herstellt. Die Äquivalenz wurde bewiesen (Endzustand byte-identisch zum alten Zweier-Stapel). Der Bestätigungsdialog und die Geräteliste liegen weiterhin separat in **Patch 0007**.

## Was der Patch macht

Fügt dem Mitgliederportal (`/portal/dashboard`) den Reiter **„App verbinden"** hinzu: ein QR-Code, den die *EEG GrünLicht App* scannt, plus Store-Links, Countdown und ein Hinweis-Banner („Funktion in Entwicklung", App voraussichtlich Ende August).

**Der QR enthält keinerlei personenbezogene Daten.** Er trägt nur einen kurzlebigen Zufallstoken:

```json
{ "tok": "<zufallstoken>", "iat": 1783810985, "exp": 1783811165 }
```

Signiert als **ES256-JWT** mit dem bestehenden P-256-Schlüssel (did:oyd). Header: `{"alg":"ES256","typ":"JWT","kid":"<PORTAL_APP_QR_KID>"}`.

## Login-Token (Migration 088)

| Spalte | Typ |
|---|---|
| `id` | uuid PK |
| `token_hash` | text NOT NULL **UNIQUE** — SHA-256-Hex des Tokens |
| `member_id` | uuid NOT NULL → `members(id)` ON DELETE CASCADE |
| `expires_at` | timestamptz NOT NULL (+ Index) |
| `created_at` | timestamptz NOT NULL |

Beim Laden des Tabs: 32 Byte aus `crypto/rand` → `base64.RawURLEncoding` = Token; `sha256` → Hex = `token_hash`; eine Zeile mit `expires_at = now() + TTL`.

**Sicherheit:** Der Klartext-Token wird **nie** gespeichert und **nie** geloggt — er lebt ausschließlich im QR-Bild. Er wird auch **nicht** im JSON-Body des Endpoints zurückgegeben. Die Abrechnung markiert Tokens **nicht** als verbraucht; Single-Use erzwingt die GrünLicht-API in ihrer eigenen DB, damit sie auf dieser DB read-only bleiben kann.

Ein stündlicher Hintergrund-Job löscht abgelaufene Zeilen (`DELETE … WHERE expires_at < now()`).

## Konfiguration (Environment der API)

| Env-Var | Zweck |
|---|---|
| `PORTAL_APP_QR_KID` | JWT-Header `kid`, z. B. `did:oyd:…#key-doc` |
| `PORTAL_APP_QR_PRIVKEY` | ES256-Private-Key, **multibase-kodiert** |
| `PORTAL_APP_QR_TTL_SECONDS` | *(optional)* Gültigkeit in Sekunden, Default **180** |
| `PORTAL_APP_IOS_URL` / `PORTAL_APP_ANDROID_URL` | Store-Links |

Fehlt `KID` oder `PRIVKEY`, antwortet der Endpoint mit `503` und der Reiter zeigt eine Fehlermeldung.

**Key-Format:** Der Wert wird getrimmt und per Multibase-Präfix dekodiert (`z`=base58btc, `u/U`=base64url, `m/M`=base64, `f/F`=hex). Als P-256-Skalar dienen die **letzten 32 Bytes** — damit ist jeder Präfix toleriert (Standard-`p256-priv`-Varint `0x1306`, roher Skalar, **oder das OYD-Format** `[2-Byte-Codec][0x20-Längenbyte][32-Byte-Key]`).

**Signierer:** bewusst handgebaut mit `crypto/ecdsa` (R‖S, base64url) statt `golang-jwt/v5` — standardkonforme, end-to-end verifizierte Ausgabe, kein zusätzliches Risiko.

## Anzeige / UX

Ganz oben ein Hinweis-Banner (Funktion in Entwicklung). Unter dem QR ein **Countdown** (mm:ss aus `expires_in`); läuft er ab, wird der QR ausgegraut/geblurrt mit Overlay „Code abgelaufen" und Button **„Neuen Code laden"** (In-Place-Refetch, kein Seiten-Reload nötig).

## Betroffene Dateien

| Datei | Änderung |
|---|---|
| `api/internal/db/migrations/088_app_login_tokens.{up,down}.sql` | **neu** |
| `api/internal/handler/portal_app_token.go` | **neu** — Token erzeugen/hashen/speichern, ES256-JWT, QR-Rendering |
| `api/internal/repository/member_portal.go` | `CreateAppLoginToken`, `DeleteExpiredAppLoginTokens` |
| `api/cmd/server/main.go` | Route `GET /api/v1/public/portal/app-token` + stündlicher Cleanup-Job |
| `api/go.mod` / `api/go.sum` | Abhängigkeit `github.com/skip2/go-qrcode` |
| `web/app/api/portal/app-token/route.ts` | **neu** — Next-Proxy |
| `web/app/portal/dashboard/PortalDashboardClient.tsx` | Tab „App verbinden" + QR + Countdown + Store-Links |

## Read-only-DB-Zugang der GrünLicht-API

Siehe `patches/0004-app_readonly-gruenlicht.sql` — Schema `app_readonly`, zwei Views (`app_login_token_view`, `app_member_view`), Rolle `gruenlicht_ro` mit ausschließlich `SELECT` darauf. Kein `email`, kein `iban`, kein EEG-Filter (jedes Mitglied jeder Gemeinschaft soll die App verbinden können). Einmalig als Superuser ausführen; Passwort lokal mit `openssl rand -hex 32` erzeugen.

## Verifizieren

1. Tab „App verbinden" laden → genau **eine** neue Zeile in `app_login_tokens`, `token_hash` = 64 Hex-Zeichen, `expires_at ≈ now()+3 min`.
2. QR dekodieren → Payload enthält nur `tok`, `iat`, `exp`; **keine** Mitglieds-UUID.
3. `SELECT * FROM app_login_tokens` → nirgends ein Klartext-Token.
4. Negativtest `gruenlicht_ro` (siehe SQL-Datei): SELECT auf die Views geht, Rohtabellen und Schreibversuche scheitern.
