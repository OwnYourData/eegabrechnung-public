> ⚠️ **OBSOLET ab Release 2026-07-05.** Upstream hat die proportionale Einspeise-Skalierung
> vollständig entfernt — die Einspeisung wird jetzt generell roh (`wh_community`) vergütet.
> Damit ist genau das Verhalten dieses Patches der neue Standard; der Patch wird nicht mehr
> benötigt und wurde stillgelegt (`patches/retired/`). Details: `releases/README-2026-07-05.md`.

# Feature-Patch: „Einspeisung ohne Anpassungsfaktor abrechnen"

Fügt unter **Abrechnung starten → Erweiterte Optionen** eine Checkbox hinzu, die die proportionale Skalierung der Einspeisevergütung abschaltet. Bei aktivierter Checkbox bekommt jeder Einspeiser exakt seine gemessene `wh_community` vergütet – die fehlende Einspeisung eines defekten Zählers wird **nicht** auf die übrigen Erzeuger umverteilt.

## Was der Patch ändert

| Datei | Änderung |
|---|---|
| `api/internal/repository/reading.go` | `SumByMemberAndPeriod` und `SumForMember` bekommen den Parameter `scaleGeneration bool`. Bei `false` entfällt der Skalierungsterm (`* total_consumer_self / total_generator_community`). |
| `api/internal/billing/billing.go` | Neues Feld `RunOptions.NoGenerationScaling`; wird an beide Repo-Aufrufe als `!opts.NoGenerationScaling` durchgereicht. `RegeneratePDF` ruft weiterhin mit Skalierung auf (unverändertes Verhalten). |
| `api/internal/handler/billing.go` | Request-Feld `no_generation_scaling` (JSON) wird eingelesen und in die `RunOptions` übernommen. |
| `web/components/billing-run-form.tsx` | Checkbox in den erweiterten Optionen; setzt `no_generation_scaling: true` im Request. |

Die Voreinstellung ist unverändert: Ohne Häkchen rechnet das System wie bisher **mit** Skalierung.

## Anwenden

Im Wurzelverzeichnis deines Klons (`eegabrechnung-public`):

```bash
git checkout -b feature/no-generation-scaling   # optional, sauberer
git apply --stat patches/0001-einspeisung-ohne-anpassungsfaktor.patch   # nur anzeigen
git apply patches/0001-einspeisung-ohne-anpassungsfaktor.patch          # anwenden
```

Falls `git apply` wegen abweichender Codebasis meckert, toleranter:

```bash
git apply --3way patches/0001-einspeisung-ohne-anpassungsfaktor.patch
```

(Der Patch wurde gegen den `main`-Stand erstellt, gegen den auch eure Images `:260606` gebaut wurden — er sollte sauber durchgehen.)

## Images neu bauen und ausrollen

Nur **API** und **Web** sind betroffen (der EDA-Worker nicht). Neuen Tag wählen:

```bash
GHCR=ghcr.io/oyd-private
TAG=260610   # neuer Tag
DOMAIN=https://abrechnung.eeg-gruenlicht.at

docker buildx build --platform linux/amd64 --push \
  -t $GHCR/eegabrechnung-api:$TAG api/

docker buildx build --platform linux/amd64 --push \
  -f ../eegabrechnung-k8s/build/web.Dockerfile \
  --build-arg NEXT_PUBLIC_API_URL=$DOMAIN \
  -t $GHCR/eegabrechnung-web:$TAG web/
```

Dann den Tag in `k8s/05-api.yaml` und `k8s/07-web.yaml` auf `260610` setzen und:

```bash
pace apply -f k8s/05-api.yaml -f k8s/07-web.yaml
pace -n eegabrechnung rollout status deploy/eegabrechnung-api
pace -n eegabrechnung rollout status deploy/eegabrechnung-web
```

(Der EDA-Worker bleibt auf seinem Tag — nicht neu ausrollen nötig.)

## Verifizieren

1. **Abrechnung → Abrechnung starten → Erweiterte Optionen** öffnen → neue Checkbox „Einspeisung ohne Anpassungsfaktor abrechnen" ist da.
2. **Gegenprobe per Vorschau** (nichts wird gespeichert): denselben Zeitraum (z.B. März–Mai) einmal **ohne** und einmal **mit** Häkchen als Vorschau rechnen.
   - Ohne Häkchen: Einspeise-kWh sind um den Faktor (~1,1088 im Mai-Beispiel) erhöht.
   - Mit Häkchen: Einspeise-kWh entsprechen exakt den gemessenen Werten (= dein Excel).
3. Optional Plausibilität in der DB: Summe `generation_kwh` aller Rechnungen mit Häkchen = Summe `wh_community` aller GENERATION-Zählpunkte.

## Fachlicher Hinweis

Die Skalierung ist die regulatorisch korrekte Abbildung des **dynamischen** Aufteilungsmodells (vergütete Einspeisung = tatsächlich von der Gemeinschaft aufgenommene Energie). Der Schalter ist für **Ausnahmefälle** gedacht (defekter Zähler), in denen die Umverteilung einzelne Mitglieder benachteiligen würde. Sobald der Netzbetreiber Ersatzwerte liefert, ist der reguläre Weg: korrigierten EDA-Export mit „Überschreiben" importieren und **ohne** Schalter abrechnen — dann ist der Faktor ohnehin ~1,0.

## Als Beitrag einreichen

Das ist ein sauber abgegrenztes Feature — ein guter Kandidat für einen Pull Request ans Upstream-Repo (`lutzerb/eegabrechnung-public`). Der Patch enthält bereits die Backend- und Frontend-Änderung; für einen PR wäre noch ein kurzer Eintrag in `docs/07-abrechnung.md` sinnvoll.
