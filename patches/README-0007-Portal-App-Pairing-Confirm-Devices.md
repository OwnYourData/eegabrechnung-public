# Patch 0007 (Phase B): Bestätigungsdialog „Gerät verbinden?" + verbundene Geräte

Baut auf Patch 0006 auf (QR ohne Personenbezug). Phase B ergänzt den **eigentlichen Schutz gegen mitgelesene QR-Codes**: Jede App-Verbindung muss vom Mitglied im Portal ausdrücklich bestätigt werden — mit Code-Abgleich.

## Sicherheitskern (B1)

Ein abfotografierter QR-Code allein reicht nach diesem Patch **nicht** mehr für eine Anmeldung. Nach dem Scan legt die GrünLicht-API eine Pairing-Anfrage an und zeigt in der App einen 6-stelligen Code. Das Portal zeigt dieselbe Anfrage und verlangt eine bewusste Bestätigung.

Drei Regeln, serverseitig durchgesetzt:

1. **Nur aus authentifizierter Portal-Sitzung.** Alle Endpunkte hängen an der bestehenden `portalAuth`-Session (`X-Portal-Session`). Ohne gültige Sitzung: `401`.
2. **`member_ref` kommt ausschließlich aus der Session** (`memberID` aus `portalAuth`) — **nie** aus dem Request. Ein Aufrufer kann also nicht fremde Mitglieder adressieren.
3. **Ownership-Prüfung vor jeder Aktion.** Vor `confirm`/`reject` (und vor dem Session-Entzug) holt das Backend die **eigenen** offenen Anfragen des eingeloggten Mitglieds und prüft, dass die übergebene ID darin vorkommt. Sonst: `403`, und die Anfrage wird **nicht** an die GrünLicht-API weitergereicht.

Damit gibt es keinen Weg, eine Bestätigung ohne Portal-Sitzung oder für ein fremdes Konto auszulösen.

## Endpunkte (Go, portalAuth-geschützt)

| Portal-Endpunkt | ruft intern auf |
|---|---|
| `GET /api/v1/public/portal/app-pairings` | `GET {API}/internal/pairings?member_ref=<Session>` |
| `POST /api/v1/public/portal/app-pairings/{id}/confirm` | `POST {API}/internal/pairings/<id>/confirm` |
| `POST /api/v1/public/portal/app-pairings/{id}/reject` | `POST {API}/internal/pairings/<id>/reject` |
| `GET /api/v1/public/portal/app-sessions` | `GET {API}/internal/sessions?member_ref=<Session>` |
| `DELETE /api/v1/public/portal/app-sessions/{id}` | `DELETE {API}/internal/sessions/<id>` |

Statuscodes werden durchgereicht: `204` = ok, `404` = unbekannt/nicht mehr offen, `410` = abgelaufen (2-Minuten-Frist), `403` = gehört nicht zu diesem Mitglied.

## Portal-UI (B1 + B2)

Im Tab „App verbinden":

- **Polling alle 2 s**, solange der QR gültig ist (Countdown > 0). Danach hört es auf — die Pairing-Anfrage lebt ohnehin nur 2 Minuten.
- **Bestätigungsdialog** (rot, prominent, oberhalb des QR): Gerätename, 6-stelliger Code, expliziter Hinweis *„Stimmt er nicht überein — oder hast du gerade gar nichts gescannt — dann bitte ablehnen"*, Buttons **Bestätigen** / **Ablehnen**.
- **Verbundene Geräte**: Liste mit Gerätename, „verbunden seit", „zuletzt verwendet" und Button **Zugriff entziehen** (wirkt sofort — die API führt opake, widerrufbare Sessions, kein JWT).

## Environment (API-Deployment)

| Variable | Wert |
|---|---|
| `GRUENLICHT_API_INTERNAL` | `http://gruenlicht-api.eegabrechnung.svc.cluster.local` (nur clusterintern) |
| `INTERNAL_SERVICE_TOKEN` | aus Secret `gruenlicht-api-secret`, Key `internal-service-token` |

Fehlt eines von beiden, antworten die Endpunkte mit `503` — das Portal zeigt dann schlicht keine Anfragen an.

Hinweis zur Vorgabe „Vergleich in konstanter Zeit": Die Abrechnung ist hier **Client** — sie *sendet* den `X-Service-Token`-Header. Der zeitkonstante Vergleich gehört auf die **verifizierende** Seite, also in die GrünLicht-API.

## Betroffene Dateien

| Datei | Änderung |
|---|---|
| `api/internal/handler/portal_app_pairing.go` | **neu** — 5 Handler, Ownership-Prüfung, HTTP-Client gegen die interne API |
| `api/cmd/server/main.go` | 5 Routen |
| `web/app/api/portal/app-pairings/route.ts` | **neu** — Proxy (GET) |
| `web/app/api/portal/app-pairings/[pairingId]/confirm/route.ts` | **neu** — Proxy (POST) |
| `web/app/api/portal/app-pairings/[pairingId]/reject/route.ts` | **neu** — Proxy (POST) |
| `web/app/api/portal/app-sessions/route.ts` | **neu** — Proxy (GET) |
| `web/app/api/portal/app-sessions/[sessionId]/route.ts` | **neu** — Proxy (DELETE) |
| `web/app/portal/dashboard/PortalDashboardClient.tsx` | Polling, Bestätigungsdialog, Geräteliste |

Betrifft **API und Web** — beide Images neu bauen.

## Abnahme

1. Portal → „App verbinden", QR mit der App scannen → innerhalb von ~2 s erscheint der Dialog mit **demselben** 6-stelligen Code wie in der App.
2. **Ohne** Bestätigung bekommt die App keine Session.
3. „Ablehnen" verhindert die Verbindung dauerhaft (`204`, Anfrage verschwindet).
4. Nach „Bestätigen" taucht das Gerät unter **Verbundene Geräte** auf.
5. „Zugriff entziehen" → Gerät verschwindet, der nächste App-Request scheitert sofort mit `401`.
6. Negativtest: Ein `confirm` mit einer fremden Pairing-ID (aus einer anderen Sitzung) muss mit **403** abgewiesen werden — und darf die GrünLicht-API gar nicht erst erreichen.
