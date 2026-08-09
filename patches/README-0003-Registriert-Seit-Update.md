# Feature-/Bugfix-Patch 0003: Aktivierungsdatum (`registriert_seit`) in der Zählpunktansicht editierbar

## Problem

In der Zählpunkt-Bearbeitung (`/eegs/[eegId]/members/[memberId]/meter-points/[id]/edit`) gibt es ein Datumsfeld „Aktiv seit / registriert_seit". Das Formular sendet den Wert auch mit — aber er wurde beim Speichern **ignoriert**, sodass beim erneuten Öffnen wieder das alte Datum stand.

Zwei Ursachen im Backend:

1. **`UpdateMeterPoint`-Handler** (`api/internal/handler/meter_point.go`) übernahm `req.RegistriertSeit` gar nicht auf das zu speichernde Objekt (nur der *Create*-Handler tat das).
2. Die generische **`Update`-Query** (`api/internal/repository/meterpoint.go`) enthielt die Spalte `registriert_seit` nicht im `UPDATE`-Statement — selbst ein gesetzter Wert wäre also nicht persistiert worden.

## Was der Patch ändert

| Datei | Änderung |
|---|---|
| `api/internal/handler/meter_point.go` | Im `UpdateMeterPoint`-Handler wird `req.RegistriertSeit` (Format `YYYY-MM-DD`) geparst und auf `existing.RegistriertSeit` gesetzt (Flag `registriertSeitChanged`) — analog zum `abgemeldet_am`-Block. Nach dem Speichern wird bei geändertem Datum zusätzlich die offene Registrierungsperiode nachgezogen. Leerer Wert = unverändert. |
| `api/internal/repository/meterpoint.go` | `Update` schreibt jetzt zusätzlich `registriert_seit` (`$8`, `WHERE id=$9`); neuer Wrapper `SetPeriodStartManual`. |
| `api/internal/repository/meter_point_registration_period.go` | Neue Methode `SetOpenPeriodStart` — setzt `registriert_seit` der aktuell offenen Periode (`WHERE abgemeldet_am IS NULL`); No-op, wenn keine offen ist. |

Damit lässt sich das Aktivierungsdatum künftig direkt in der Zählpunktansicht setzen; der „seit"-Badge und die Anzeige lesen die Spalte `meter_points.registriert_seit`.

**Nur der manuelle Bearbeitungspfad** ist betroffen. Der Stammdaten-Import nutzt eine eigene Upsert-Logik, die `registriert_seit` bewusst *nicht* überschreibt (damit ein leeres/veraltetes Datum im re-importierten Sheet die Aktivierung nicht still überschreibt) — dieses Verhalten bleibt unverändert.

## Registrierungshistorie

Eine manuelle Datumsänderung zieht **beides** mit: die Spalte `meter_points.registriert_seit` (Badge/„seit"-Anzeige) **und** den Beginn der offenen Periode in `meter_point_registration_periods` (Registrierungshistorie-Timeline, Migration 077, ab Release 2026-07-05). Badge und Timeline sind danach konsistent.

Ist keine Periode offen (z. B. bereits abgemeldeter Zählpunkt), ist die Perioden-Korrektur ein No-op (`WHERE abgemeldet_am IS NULL` trifft nichts) — dann bleibt allein die Spalte maßgeblich. Reihenfolge im Handler: erst `abgemeldet_am`-Sync (Close/Reopen), dann die Perioden-Start-Korrektur, damit eine gerade wieder geöffnete Periode korrekt datiert wird.

## Anwenden

```bash
git apply --check patches/0003-meterpoint-update-registriert-seit.patch
git apply       patches/0003-meterpoint-update-registriert-seit.patch
```

Betroffen ist **nur die API** (Backend). Nach dem Anwenden das **API-Image** neu bauen und ausrollen (Web/Worker unverändert). Zusammen mit Patch 0002 (Web) deckt `git apply patches/*.patch` beide aktiven Patches ab.

## Verifizieren

1. Zählpunkt-Bearbeitung öffnen, Aktivierungsdatum ändern, speichern.
2. Seite neu laden → das neue Datum bleibt stehen (vorher sprang es zurück).
3. Der „seit"-Badge auf der Mitglieder-Detailseite zeigt das korrigierte Datum.
