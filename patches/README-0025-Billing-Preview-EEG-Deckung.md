# 0025 – Spalte „EEG-Deckung" in der Abrechnungs-Vorschau

**Bereich:** Web-Frontend (Billing)
**Patch:** `0025-billing-preview-eeg-deckung.patch`
**Betroffene Datei:** `web/components/billing-run-form.tsx`
**Art:** reine Frontend-Änderung (keine API-/DB-Änderung)
**Basiert auf:** Patch `0002-billing-preview-columns.patch` — **zuerst 0002 anwenden**
**Stand:** Juli 2026

## Zusammenfassung

Die Vorschau-Tabelle auf der Abrechnungsseite (`/eegs/[eegId]/billing`, „Abrechnung starten" → Button „Vorschau") bekommt als **letzte Spalte** **EEG-Deckung (%)**, hinter „Betrag (€)".

| vorher (nach 0002) | nachher |
|--------|---------|
| MitgliedsNr · Typ · Zählpunkt(e) · Name & Adresse · Bezug kWh · Einspeisung kWh · Betrag (€) | MitgliedsNr · Typ · Zählpunkt(e) · Name & Adresse · Bezug kWh · Einspeisung kWh · Betrag (€) · **EEG-Deckung (%)** |

Damit ist vor dem Abrechnungslauf auf einen Blick sichtbar, welcher Anteil des Verbrauchs eines Mitglieds im Zeitraum aus der Gemeinschaft gedeckt wurde — ein Wert, der bisher nur als EEG-weite KPI-Kachel auf der Berichte-Seite existierte.

## Definition und Datenherkunft

```
EEG-Deckung [%] = Bezug EEG / Gesamtverbrauch × 100
```

Das ist dieselbe Formel wie die KPI-Kachel „EEG-Deckung" auf `/eegs/[eegId]/reports` und wie in `ABRECHNUNG-DB-ANTWORTEN.md` dokumentiert.

Die Vorschau-Antwort der Abrechnung (`POST /billing/run` mit `preview: true`) enthält pro Rechnung nur `consumption_kwh` (= Bezug EEG). Der **Nenner fehlt dort**. Deshalb lädt die Komponente nach einem erfolgreichen Vorschau-Aufruf zusätzlich:

```
GET /api/eegs/{eegId}/energy/members?from={periodStart}&to={periodEnd}
```

Dieser Endpunkt (Backend: `ReportHandler.GetRawMemberEnergy` → `ReportRepository.RawMemberEnergy`) liefert je Mitglied aus den Rohmesswerten:

| Feld | Bedeutung |
|------|-----------|
| `consumption_kwh` | Summe `wh_self` über CONSUMPTION-Zählpunkte = **Bezug EEG** (Zähler) |
| `consumption_total_kwh` | Summe `wh_total` über CONSUMPTION-Zählpunkte = **Gesamtverbrauch** (Nenner) |

L3-Werte (fehlerhaft) sind in beiden Summen ausgeschlossen. **Keine** Änderung an API, Swagger oder Datenmodell nötig; der Endpunkt existiert bereits und wird von der Berichte-Seite genutzt.

### Warum Zähler *und* Nenner aus demselben Endpunkt

Zähler und Nenner stammen bewusst beide aus `/energy/members` und nicht aus der Vorschau-Antwort, obwohl `invoice.consumption_kwh` und `MemberStat.consumption_kwh` dieselbe Aggregation sind (`SumByMemberAndPeriod` vs. `RawMemberEnergy` — identische Formel, identischer L3-Filter). Zwei Unterschiede würden sonst zu verzerrten Quoten führen:

1. **Mitglieder mit Beitritt/Austritt im Zeitraum** rechnet die Abrechnung nur über ihren effektiven Teilzeitraum ab (`SumForMember`), der Rohabruf dagegen über den vollen Zeitraum — die Deckung wäre zu niedrig.
2. **Zeitraumgrenzen:** die Abrechnung filtert `er.ts >= start AND er.ts <= end` mit reinen Datumswerten, `/energy/members` castet über `viennaDay(...)` nach Europe/Vienna. Wegen des bekannten Zeitzonen-Versatzes in `energy_readings.ts` (Wanduhrzeit als UTC abgelegt) fallen die Fensterränder um 1–2 Stunden auseinander.

Weil beide Werte aus demselben Abruf mit demselben Fenster kommen, ist die **Quote in sich konsistent** — auch wenn der angezeigte Zähler geringfügig von der Spalte „Bezug kWh" (aus der Abrechnung) abweichen kann. Der Tooltip auf der Zelle macht das transparent: er zeigt „`<Bezug EEG>` von `<Gesamtverbrauch>` kWh Gesamtverbrauch".

## Anzeige

- **Position:** letzte Spalte, hinter „Betrag (€)". Die kaufmännischen Kernwerte (Bezug, Einspeisung, Betrag) bleiben damit als zusammenhängender Block direkt nebeneinander; die Deckung ist eine Kontrollgröße und steht am Ende. Beim Copy&Paste nach Excel lässt sie sich so auch einfach abschneiden.
- **Format:** eine Nachkommastelle, Komma-Dezimaltrenner, **kein `%`-Zeichen in der Zelle** (`63,4`). Die Einheit steht im Spaltenkopf: „EEG-Deckung (%)". Damit bleibt die von 0002 hergestellte Excel-Tauglichkeit erhalten — markieren, kopieren, in ein deutsch/österreichisch eingestelltes Excel einfügen ergibt eine **Zahl**, kein Text und kein Datum.
- **Tooltip Spaltenkopf:** „Bezug EEG / Gesamtverbrauch im Abrechnungszeitraum".
- **Tooltip je Zelle:** die beiden zugrundeliegenden kWh-Werte.
- **„—" statt eines Werts**, wenn kein Gesamtverbrauch vorliegt (reine Einspeiser, Mitglieder ohne Messdaten im Zeitraum) oder das Mitglied im Rohabruf fehlt. Division durch 0 ist ausgeschlossen (`totalKwh <= 0` → `null`).
- **Summenzeile:** Gesamtdeckung als **Summe Bezug EEG / Summe Gesamtverbrauch** über genau die Mitglieder, die in der Vorschau enthalten sind (respektiert also den Mitglieder-Filter unter „Erweiterte Optionen") — bewusst **nicht** der Mittelwert der Einzelquoten, der kleine Verbraucher überproportional gewichten würde.
- **Ladezustand:** solange der Zusatzabruf läuft, steht unter der Tabelle „EEG-Deckung wird geladen …".
- **Fehlerfall:** scheitert der Abruf, bleibt die Spalte auf „—" und es erscheint ein Hinweis in Bernstein. Die Vorschau selbst und alle übrigen Spalten sind davon **nicht** betroffen — der Zusatzabruf kann die Abrechnung nicht blockieren.

Der Zustand wird bei jedem neuen Vorschau- oder Abrechnungslauf zurückgesetzt, damit nie Werte eines alten Zeitraums stehen bleiben.

## Anwenden

Im Repo-Root, **nach** 0002:

```bash
git apply --check patches/0002-billing-preview-columns.patch
git apply       patches/0002-billing-preview-columns.patch
git apply --check patches/0025-billing-preview-eeg-deckung.patch   # Trockenlauf
git apply       patches/0025-billing-preview-eeg-deckung.patch
```

Anschließend Web-Image neu bauen und ausrollen:

```bash
docker compose build eegabrechnung-web && docker compose up -d eegabrechnung-web
```

## Verifikation / Test

Automatisch geprüft bei Erstellung des Patches:

- `tsc --noEmit` gegen `billing-run-form.tsx` (nach 0002 + 0025) mit dem projekteigenen `tsconfig.json` und den echten Abhängigkeiten aus `package-lock.json` → **fehlerfrei**.
- `git apply --check` für 0002 gegen den aktuellen Repo-Stand und für 0025 gegen den Stand nach 0002 → **beide sauber**.

Manuell zu prüfen:

1. EEG öffnen → **Abrechnung** → Zeitraum wählen → **Vorschau**.
2. Die Tabelle zeigt acht Spalten; „EEG-Deckung (%)" steht ganz rechts, hinter „Betrag (€)".
3. Ein reiner Verbraucher zeigt einen plausiblen Wert (typisch 20–80); Maus über die Zelle zeigt „x,xx von y,yy kWh Gesamtverbrauch", und x/y ergibt den angezeigten Prozentwert.
4. Ein reiner Einspeiser zeigt „—" (kein Bezugs-Zählpunkt → kein Gesamtverbrauch).
5. Die Summenzeile liegt zwischen dem kleinsten und größten Einzelwert und entspricht nicht dem arithmetischen Mittel, sondern der mengengewichteten Quote.
6. Vergleichsprobe: derselbe Zeitraum auf `/eegs/[eegId]/reports` (KPI „EEG-Deckung", Rohdaten-Modus) — der Wert dort muss der Summenzeile entsprechen, sofern in der Vorschau **alle** Mitglieder enthalten sind (kein Mitglieder-Filter, kein Abrechnungstyp-Filter).
7. Copy&Paste-Probe: Spalte markieren, in Excel einfügen → Werte landen als Zahlen.
8. Zeitraum wechseln und erneut „Vorschau" klicken → die Werte aktualisieren sich, kurzzeitig erscheint „EEG-Deckung wird geladen …".

## Umfang / Abgrenzung

- Betrifft **nur die nicht gespeicherte Vorschau**. Die Tabelle gespeicherter Abrechnungsläufe (`RunSection` in `web/app/eegs/[eegId]/billing/page.tsx`), der Excel-Export des Laufs und das Rechnungs-PDF sind **nicht** verändert.
- Der Zusatzabruf erfolgt pro Vorschau-Klick, ohne Caching. Bei EEGs mit sehr vielen Zählpunkten und langen Zeiträumen kostet das eine zusätzliche Aggregation über `energy_readings`; die Vorschau selbst wartet nicht darauf.
- Der Zeitzonen-Versatz in `energy_readings.ts` (Importer parst ohne Location) ist hier **nicht** behoben. Er verschiebt lediglich die Fensterränder um 1–2 Stunden — bei Monatszeiträumen im Promillebereich, bei sehr kurzen Zeiträumen relevanter. Der eigentliche Fix gehört in `api/internal/importer/energiedaten.go` (`time.ParseInLocation`) samt Backfill.
- Mögliche Folgeschritte (nicht Teil dieses Patches): dieselbe Spalte im Excel-Export des Laufs und in der Tabelle gespeicherter Läufe; Anzeige des Restbedarfs (Gesamtverbrauch − Bezug EEG) als eigene Spalte.
