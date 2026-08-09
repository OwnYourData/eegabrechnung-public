# Patch 0010 (B3): E-Mail bei neuer Geräteverbindung — Vishing-Gegenmaßnahme

## Warum

Der manuelle 8-Zeichen-Code (Patch 0009) lässt sich am Telefon **vorlesen** — ein QR-Code nicht. Damit wird Telefonbetrug möglich: *„Hier EEG-Support, lesen Sie mir bitte den Code vor … und bestätigen Sie jetzt noch im Portal."* Das Opfer bestätigt — und genau die Schutzschicht, die wir gegen den mitgelesenen QR eingezogen haben, ist ausgehebelt.

Ein Warntext im Dialog hilft dagegen wenig; unter Zeitdruck liest den niemand. Was hilft: den Vorgang **entdeckbar und umkehrbar** machen.

## Was der Patch macht

Unmittelbar nach einem erfolgreichen `POST /internal/pairings/<id>/confirm` (HTTP 204) geht eine E-Mail an das **eingeloggte** Mitglied: Gerätename, Zeitpunkt, und der Hinweis, dem Gerät im Portal sofort den Zugriff zu entziehen, falls man es nicht selbst war — plus der Satz, dass die EEG **niemals** anruft und nach einem Code fragt.

Zusätzlich (in der Spec optional, hier umgesetzt): dieselbe Mechanik beim **Entzug** eines Geräts. Das schließt den Kreis — auch ein böswilliger Entzug wird sichtbar.

## Umsetzung (die harten Regeln)

| Regel | Umsetzung |
|---|---|
| Empfänger aus der **Portal-Session** | `members.email` via `memberRepo.GetByID(memberID)`; `memberID` kommt aus `portalAuth`. Die GrünLicht-API hat bewusst **keinen** Zugriff auf E-Mail-Adressen — das bleibt so. |
| **Kein** zusätzlicher API-Aufruf | Gerätename und Zeitpunkt stammen aus dem Pairing-Objekt, das die Ownership-Prüfung ohnehin schon geladen hat (`deviceLabel`, `requestedAt`). |
| **Fire-and-forget** | Versand in einer Goroutine. Scheitert er (SMTP down), gelingt die Bestätigung **trotzdem** — der Fehler wird nur geloggt (`slog.Warn`), nie eskaliert. |
| **Keine Geheimnisse** in der Mail | Keine Codes, keine Tokens, kein Auto-Login-Link. Nur ein Link ins Portal, wo man sich normal anmeldet. |
| Ziel des Links | Mitgliederportal → Tab „App verbinden" → **Verbundene Geräte** (dort wirkt „Zugriff entziehen" sofort). |
| Demo-Konto | Das Demo-Mitglied liegt in der Demo-EEG (`is_demo`) → **kein** Mailversand. |
| Protokollierung | Über `invoice.SendLogged` → `email_log` (`app_device_connected` / `app_device_revoked`, inkl. `member_id`). |

Zeitpunkt wird in **Europe/Vienna** formatiert (`12.07.2026, 14:03 Uhr`); ist `requestedAt` nicht parsebar, wird die aktuelle Zeit genommen.

## Betroffene Dateien

`api/internal/handler/portal_app_pairing.go` — `eegID` aus der Session festhalten, die gematchte Pairing-/Session-Zeile behalten, bei `204` `notifyDeviceEvent(...)` als Goroutine auslösen; neue Methode `notifyDeviceEvent`.

Nur **API** betroffen — kein Web-Rebuild nötig.

## Abnahme

1. Bestätigung im Portal → Mail kommt an, mit korrektem Gerätenamen und Zeit.
2. SMTP kaputt → die Bestätigung funktioniert trotzdem (204), nur ein `slog.Warn` im Log.
3. Die Mail enthält keinerlei Geheimnisse; der Link führt auf die normale Portal-Anmeldung.
4. `SELECT email_type, to_address, status FROM email_log WHERE email_type LIKE 'app_device_%' ORDER BY created_at DESC LIMIT 5;`
