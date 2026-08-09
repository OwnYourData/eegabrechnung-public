# Patch 0017: L3-Toggle auch im Mitglieder-Portal

Ergänzung zu Patch 0016 (das nur die Admin-Reports-Seite betraf). Das Mitglieder-Portal (`/portal/dashboard`, Tab „Energiedaten") hat eine **eigene** Energie-Query (`ReadingRepository.GetMemberEnergy`) mit demselben festen `AND er.quality != 'L3'`. Dieser Patch zieht den Schalter dort nach.

## Was der Patch macht

Checkbox **„Fehlerhafte Messwerte (Qualität L3) einbeziehen"** unter der Zeitraum-Auswahl im Energie-Tab des Portals. Standard **aus**. Eingeschaltet fließen L3-Werte in Chart und Tabelle ein.

## Umsetzung

**Backend** (`repository/reading.go`): `GetMemberEnergy` bekommt `includeL3 bool`. Der L3-Filter wird bei `includeL3=true` nach dem `fmt.Sprintf` per `strings.Replace(q, "er.quality != 'L3'", "TRUE", 1)` neutralisiert (`AND TRUE`) — kein Herumschieben der positionsbasierten Format-Argumente.

**Handler** (`handler/member_portal.go`): `GetEnergy` liest `?include_l3=true` und reicht es durch. Der Portal-Energy-Proxy leitet die Query-String ohnehin vollständig weiter.

**Frontend** (`PortalDashboardClient.tsx`): State `includeL3`, hängt `&include_l3=true` an den Energie-Fetch, ist in den Effect-Dependencies (Umschalten lädt neu), Checkbox unter den Zeitraum-Tabs.

## Abweichung / bewusste Entscheidung

Wie in den Admin-Reports (0016) betrifft der Toggle **nur die Anzeige**. Die Abrechnung schließt L3 weiterhin aus. Die Checkbox ist im Portal **immer** sichtbar (das Portal führt keinen L3-Zähler wie das Admin-Banner) — für Mitglieder ohne L3-Werte ändert das Umschalten schlicht nichts.

## Betroffene Dateien

| Datei | Änderung |
|---|---|
| `api/internal/repository/reading.go` | `strings`-Import; `includeL3` in `GetMemberEnergy` + toggelbarer Filter |
| `api/internal/handler/member_portal.go` | `include_l3`-Param in `GetEnergy` |
| `web/app/portal/dashboard/PortalDashboardClient.tsx` | Checkbox + `include_l3` im Energie-Fetch |

Betrifft **API und Web**, keine Migration, kein Worker-Rebuild.

## Abnahme

- Portal → Energiedaten → Checkbox „Fehlerhafte Messwerte (Qualität L3) einbeziehen" unter den Zeitraum-Tabs.
- Bei einem Mitglied mit L3-Werten: ankreuzen → Chart/Tabelle steigen um die L3-Mengen; abwählen → zurück auf bereinigt.
