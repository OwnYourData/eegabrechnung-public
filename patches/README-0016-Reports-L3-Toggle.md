# Patch 0016: L3-Werte in den Auswertungen ein-/ausblendbar

## Problem

Die Reports-Seite (`/eegs/[eegId]/reports`) blendet Messwerte mit Qualitätskennzeichen **L3** (fehlerhaft) aus allen Summen aus — fest verdrahtet über `AND er.quality <> 'L3'` in der Query. Ein Warnbanner weist auf vorhandene L3-Werte hin, sie erscheinen aber nirgends in den Zahlen.

## Was der Patch macht

Ein **Schalter** „L3-Werte in dieser Auswertung anzeigen" im L3-Warnbanner. Standardmäßig **aus** (bisheriges Verhalten). Eingeschaltet fließen L3-Werte in die angezeigten Summen ein.

- Der Toggle sitzt **im L3-Banner** — er erscheint also nur, wenn im Zeitraum überhaupt L3-Werte vorliegen (sonst gibt es nichts ein-/auszublenden).
- Wirkt auf **beide** Datenpfade der Reports-Seite, damit KPI-Kacheln/Diagramm und Mitglieder-Aufschlüsselung konsistent bleiben:
  - `EnergySummary` (KPIs + Chart)
  - `RawMemberEnergy` (Mitglieder-Tabelle)
- Betrifft **nur die Anzeige** im „Ausgetauscht"/Roh-Modus. Die **Abrechnung** ist unberührt — dort bleiben L3-Werte weiterhin ausgeschlossen (der Banner-Text „werden nicht abgerechnet" stimmt weiterhin).

## Umsetzung

**Backend** (`repository/report.go`): Beide Funktionen bekommen einen Parameter `includeL3 bool`. Der L3-Filter wird zu einem Template (`qf`), das entweder `AND er.quality <> 'L3'` oder leer ist. Der `l3_reading_count` (für das Banner) wird **unabhängig** davon weiter gezählt — der Banner und damit der Toggle bleiben auch bei eingeblendeten L3-Werten sichtbar.

**Handler** (`handler/report.go`): `GetEnergySummary` und `GetRawMemberEnergy` lesen `?include_l3=true` und reichen es durch.

**Frontend** (`reports/page.tsx`): State `includeL3`, hängt `&include_l3=true` an beide Fetches, ist in den Fetch-Dependencies (Umschalten lädt neu), Checkbox im L3-Banner.

Die Next-Proxys (`energy/summary`, `energy/members`) reichen die Query-String ohnehin vollständig durch — dort keine Änderung nötig.

## Betroffene Dateien

| Datei | Änderung |
|---|---|
| `api/internal/repository/report.go` | `includeL3`-Parameter + toggelbarer L3-Filter in `EnergySummary` und `RawMemberEnergy` |
| `api/internal/handler/report.go` | `include_l3`-Query-Param in beiden Handlern |
| `web/app/eegs/[eegId]/reports/page.tsx` | Toggle im L3-Banner + `include_l3` in beiden Fetches |

Betrifft **API und Web**, keine Migration, kein Worker-Rebuild.

## Abnahme

1. EEG mit L3-Werten öffnen → Reports → das amber L3-Banner zeigt jetzt eine Checkbox „L3-Werte in dieser Auswertung anzeigen".
2. Ankreuzen → KPI-Kacheln, Diagramm und Mitglieder-Tabelle steigen um die L3-Mengen; Häkchen weg → zurück auf die bereinigten Zahlen.
3. Abrechnungslauf/Rechnungen unverändert (L3 dort weiterhin ausgeschlossen).
