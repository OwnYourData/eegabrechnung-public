# 0002 – Erweiterte Spalten in der Abrechnungs-Vorschau

**Bereich:** Web-Frontend (Billing)
**Patch:** `billing-preview-columns.patch`
**Betroffene Datei:** `web/components/billing-run-form.tsx`
**Art:** reine Frontend-Änderung (keine API-/DB-Änderung)
**Stand:** Juli 2026

## Zusammenfassung

Die Vorschau-Tabelle auf der Abrechnungsseite (`/eegs/[eegId]/billing`, Bereich „Abrechnung starten" → Button „Vorschau") wurde von vier auf sieben Spalten erweitert.

| vorher | nachher |
|--------|---------|
| Mitglied · Bezug kWh · Einspeisung kWh · Betrag | MitgliedsNr · Typ · Zählpunkt(e) · Name & Adresse · Bezug kWh · Einspeisung kWh · Betrag |

Ziel ist eine aussagekräftigere Kontrolle vor dem eigentlichen Abrechnungslauf: Mitgliedsnummer, Verbraucher-/Einspeiser-/Prosumer-Einordnung, die betroffenen Zählpunkte sowie Name und Straße auf einen Blick.

## Neue Spalten und ihre Herkunft

Alle Werte stammen aus dem `members`-Array, das die Billing-Seite ohnehin schon per `listMembers` lädt und an `BillingRunForm` durchreicht. Es war **keine** Änderung an der API oder am Datenmodell nötig.

| Spalte | Quelle / Ableitung |
|--------|--------------------|
| **MitgliedsNr** | `member.member_number` (Fallback `member.mitglieds_nr`) |
| **Typ** | Abgeleitet aus den Energierichtungen der Zählpunkte (`meter_points[].direction`): hat das Mitglied Bezug **und** Einspeisung → `Prosumer`; nur Einspeisung → `Einspeiser`; sonst → `Verbraucher` |
| **Zählpunkt(e)** | Alle `meter_points[].meter_id` des Mitglieds, mehrere untereinander gelistet |
| **Name & Adresse** | Anzeigename (`name1 name2`) plus **nur der Straßenname** aus `member.strasse` — ohne Hausnummer, ohne PLZ/Ort |
| **Bezug kWh** | `invoice.consumption_kwh` (unverändert) |
| **Einspeisung kWh** | `invoice.generation_kwh` (unverändert) |
| **Betrag** | `previewZahlBetrag(invoice)` (unverändert) |

Die Summenzeile („Gesamt") spannt über die vier führenden Spalten und summiert weiterhin Bezug, Einspeisung und Betrag.

### Typ-Ableitung

Die Zuordnung nutzt dieselbe Richtungslogik wie die Mitglieder-Tabelle (`web/components/member-table.tsx`), toleriert also verschiedene Schreibweisen:

- Bezug: `CONSUMPTION`, `bezug`, enthält `consume`
- Einspeisung: `GENERATION`, `einspeisung`, enthält `produc`

Damit ist der Typ strukturell (aus den Zählpunkten) bestimmt und nicht abhängig davon, ob im gewählten Zeitraum zufällig 0 kWh angefallen sind.

### Straßenname-Heuristik

Der Straßenname wird aus `strasse` extrahiert, indem alles ab dem ersten Vorkommen von „Leerzeichen + Ziffer" abgeschnitten wird:

```ts
const streetName = (strasse?: string): string =>
  (strasse ?? "").replace(/\s+\d.*$/, "").trim();
```

Beispiele:

- `Hauptstraße 12` → `Hauptstraße`
- `Wiener Straße 3a` → `Wiener Straße`
- `Dr.-Karl-Renner-Straße 7/2` → `Dr.-Karl-Renner-Straße`

**Grenzfall:** Straßen mit einer Ziffer *im Namen* (selten, z. B. „Platz 1") würden zu früh abgeschnitten. Falls solche Adressen vorkommen, muss die Regel verfeinert werden.

## Sortierung & Excel-taugliche Zahlen

- **Sortierung:** Die Zeilen sind aufsteigend nach **Mitglieds-Nr** sortiert. Vergleich über `memberNr(...).localeCompare(..., { numeric: true })` — das verträgt sowohl nullgepolsterte Nummern („0001" … „0040") als auch ungepolsterte („2" vor „10").
- **Zahlenformat für Copy&Paste nach Excel:** Die Spalten **Bezug kWh**, **Einspeisung kWh** und **Betrag** verwenden jetzt den **Komma-Dezimaltrenner** über den Helfer `num2 = (v) => v.toFixed(2).replace(".", ",")`. Ein deutsch/österreichisch eingestelltes Excel erkennt „11,25" beim Einfügen als **Zahl** — vorher wurde „11.25" als Datum („25. Nov") interpretiert. Bewusst **ohne Tausendertrennzeichen** (z. B. „1234,50"), damit die Zahlerkennung robust bleibt. Beim **Betrag** wird **kein „€" mehr** in die Zellen geschrieben (manche Excel-Konfigurationen erkennen „11,25 €" nicht als Zahl); die Einheit steht stattdessen im Spaltenkopf: **„Betrag (€)"**.
- **Eine Zeile pro Mitglied beim Excel-Paste:** Die Spalten „Zählpunkt(e)" und „Name & Adresse" werden auf **eine Zeile** gerendert — Zählpunkte kommagetrennt (`zps.join(", ")`), Name und Straße inline (`Name · Straße`) statt gestapelter `<div>`-Blöcke. Excel hatte gestapelte Block-Elemente beim Einfügen in **mehrere Zeilen** aufgeteilt; mit reinem Inline-Inhalt entspricht jede Tabellenzeile genau **einer** Excel-Zeile.

## Anwenden

Im Repo-Root:

```bash
git apply --check billing-preview-columns.patch   # Trockenlauf
git apply billing-preview-columns.patch           # anwenden
# Alternativen:
git apply --3way billing-preview-columns.patch
patch -p1 < billing-preview-columns.patch
```

Die Patch-Basis ist die committete Version von `billing-run-form.tsx`. Anschließend das Web-Image neu bauen und ausrollen:

```bash
docker compose build eegabrechnung-web && docker compose up -d eegabrechnung-web
```

## Verifikation / Test

1. EEG öffnen → **Abrechnung** → Zeitraum wählen → **Vorschau** klicken.
2. Die Vorschau-Tabelle zeigt die sieben Spalten. Stichproben:
   - Ein reiner Verbraucher zeigt Typ `Verbraucher`, Einspeisung `0.00`.
   - Ein reiner Einspeiser zeigt Typ `Einspeiser`, Bezug `0.00`.
   - Ein Mitglied mit Bezugs- **und** Einspeise-Zählpunkt zeigt Typ `Prosumer`.
   - Mitglieder mit mehreren Zählpunkten listen alle Zählpunktnummern untereinander.
   - Bei fehlender Adresse bleibt die zweite Zeile in „Name & Adresse" leer (kein Fehler).
   - Die Zeilen sind aufsteigend nach Mitglieds-Nr sortiert.
   - Zahlen erscheinen mit Komma (z. B. „11,25"); markiere Bezug/Einspeisung/Betrag, kopiere sie und füge sie in Excel ein → sie landen als Zahlen (nicht als Datum/Text).
3. Die Summenzeile stimmt weiterhin mit den Spalten Bezug/Einspeisung/Betrag überein.

Hinweis: Ein automatischer `tsc`/Build-Lauf war bei der Erstellung nicht möglich (keine `node_modules` in der Arbeitsumgebung); die Änderung wurde per Review geprüft. Der reguläre Web-Build validiert die Typen.

## Umfang / Abgrenzung

- Betrifft **nur die nicht gespeicherte Vorschau**. Die Tabelle der bereits gespeicherten Abrechnungsläufe (`RunSection` in `web/app/eegs/[eegId]/billing/page.tsx`) und der **Excel-Export** des Laufs sind **nicht** verändert.
- Mögliche Folgeschritte (nicht Teil dieses Patches): dieselben Zusatzspalten im Excel-Export und/oder in der Rechnungstabelle gespeicherter Läufe.
