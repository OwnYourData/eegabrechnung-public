# Patch 0009: Manueller Eingabe-Code (8 Zeichen, Crockford-Base32)

Notfallweg, wenn die Kamera nicht geht. Der **QR bleibt unverändert** ein signiertes ES256-JWT — der Code ersetzt ihn nicht, er zeigt nur auf **denselben** Pairing-Vorgang.

## Format

8 Zeichen aus dem Crockford-Base32-Alphabet `0123456789ABCDEFGHJKMNPQRSTVWXYZ` (ohne `I`, `L`, `O`, `U` — verwechslungsarm beim Abtippen und Vorlesen). Anzeige im Portal: `K7F2-9QRM`. Die App sendet normalisiert (Großbuchstaben, ohne Bindestrich).

**32^8 ≈ 2^40** (≈ 1,1 Billionen). Acht Ziffern wären nur 10^8 ≈ 2^27 — zu wenig, weil ein Angreifer nicht *einen bestimmten* Code sucht, sondern *irgendeinen gerade gültigen*; im laufenden Betrieb sind ständig mehrere aktiv.

Erzeugt aus `crypto/rand`; die Modulo-Abbildung ist **bias-frei** (256 % 32 == 0).

## Speicherung

Migration 090 fügt `app_login_tokens.code_hash` hinzu (+ partieller Unique-Index). Gespeichert wird **ausschließlich der SHA-256-Hex** des normalisierten Codes — der Klartext lebt nur auf dem Portal-Bildschirm, nie in DB oder Logs. Gleiche TTL (180 s, `expires_at`) wie das QR-JWT; der stündliche Cleanup räumt beide zusammen weg.

Bei einer (praktisch unmöglichen) Kollision auf `code_hash` wird bis zu 5× ein neuer Code erzeugt — nie endlos.

## Auflösung durch die GrünLicht-API

`app_login_token_view` liefert jetzt **beide** Wege zum selben Vorgang:

| Spalte | Herkunft |
|---|---|
| `token_hash` | SHA-256 des QR-JWT-Tokens (`tok`-Claim) |
| `code_hash` | SHA-256 des manuellen Codes, **normalisiert** |
| `member_ref` | `members.id` |
| `expires_at` | gemeinsame TTL |

Die API akzeptiert bei `POST /app/pair/start` also entweder `{ "token": "<QR-JWT>" }` **oder** `{ "code": "K7F29QRM" }` und schlägt den passenden Hash nach. **Verzeihende Normalisierung API-seitig:** Großbuchstaben, Bindestriche/Leerzeichen entfernen, `O`→`0`, `I`/`L`→`1`.

Das SQL steht in `patches/0004-app_readonly-gruenlicht.sql` (idempotent, einfach erneut ausführen).

## Vishing-Schutz im Portal

Ein kurzer Code lässt sich am Telefon **vorlesen** — ein QR-Code nicht. Damit wird Social Engineering möglich („Lesen Sie mir Ihren Code vor und bestätigen Sie dann im Portal"). Der Bestätigungsdialog zeigt daher weiterhin den **Gerätenamen** und zusätzlich eine deutliche Warnung:

> Nur bestätigen, wenn Sie gerade **selbst** die App verbinden. Geben Sie Ihren Verbindungs-Code **niemals telefonisch weiter** — niemand von der Energiegemeinschaft wird Sie danach fragen.

## Betroffene Dateien

| Datei | Änderung |
|---|---|
| `api/internal/db/migrations/090_app_login_token_code.{up,down}.sql` | **neu** — `code_hash` + partieller Unique-Index |
| `api/internal/handler/portal_app_token.go` | Code erzeugen (`newPairingCode`), hashen, speichern, im Response ausliefern |
| `api/internal/repository/member_portal.go` | `CreateAppLoginToken` nimmt zusätzlich `codeHash` |
| `web/app/portal/dashboard/PortalDashboardClient.tsx` | Code unter dem QR (`K7F2-9QRM`) + Vishing-Warnung im Dialog |
| `patches/0004-app_readonly-gruenlicht.sql` | `code_hash` in `app_login_token_view` |

## Nicht Teil dieses Patches (GrünLicht-API)

Das **Rate-Limit auf dem Code-Weg** (5 Fehlversuche pro IP/Konto → temporäre Sperre, exponentielles Backoff, **HTTP 429**) gehört auf `POST /app/pair/start` — also in die GrünLicht-API. Die Abrechnung erzeugt und zeigt den Code nur; sie sieht die Einlöseversuche gar nicht. Ebenso die **Einmal-Nutzung**: Die Abrechnung markiert Tokens/Codes bewusst nicht als verbraucht, damit die API read-only bleiben kann.

## Verifizieren

1. Tab „App verbinden" → unter dem QR steht ein Code der Form `K7F2-9QRM` (8 Zeichen, keine `I`/`L`/`O`/`U`).
2. `SELECT token_hash, code_hash, expires_at FROM app_login_tokens ORDER BY created_at DESC LIMIT 1;` → beide Hashes 64 Hex-Zeichen, **kein Klartext**.
3. Code in der App eintippen → dasselbe Pairing wie beim Scannen; Bestätigungsdialog erscheint im Portal.
4. Nach Ablauf (180 s) erneuert sich der QR automatisch — mit **neuem** Code.
