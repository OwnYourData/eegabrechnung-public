# Patch 0020: QR-Code auf „App verbinden" trägt den vollständigen Universal Link

## Problem

Der QR kodierte bisher nur das **nackte JWT** (`eyJ…`). Die iPhone-Kamera zeigt dafür
lediglich einen langen Text und bietet nichts an. Da der Portal-Button auf iOS
systembedingt ausgeblendet ist (Patch 0019 — Apple öffnet Universal Links nicht von
derselben Domain), blieb iPhone-Nutzern nur der 8-stellige Code.

## Lösung

Der QR kodiert jetzt den vollständigen Link:

```
https://abrechnung.eeg-gruenlicht.at/app/pair?t=<JWT>
```

Exakt **dasselbe** signierte ES256-JWT, nur als URL verpackt. Der Kamera-Scan ist
„fremder Kontext" — iOS bietet dort zuverlässig an, die App zu öffnen. Kein
App-Update nötig: Der In-App-Scanner zieht das JWT per Regex aus beliebigem Text und
funktioniert mit beiden QR-Inhalten. Android unverändert.

Sicherheit unverändert: gleiches Token, gleiche TTL, gleiche Portal-Bestätigung.

## Wichtig: QR-Dichte (deshalb zwei Änderungen)

Der Link ist ~47 Zeichen länger als das JWT — das hebt den QR von **Version 15 auf
16–18** (85 → 97 Module). Bei der bisherigen Darstellung (`w-64` = 256 px **minus**
`p-3` Padding = 232 px nutzbar) wären das nur **2,4–2,7 px pro Modul** — unter der
komfortablen Scangrenze. Der QR wäre also *schlechter* scannbar geworden und hätte
genau den Zweck verfehlt.

Deshalb zusätzlich:

| Änderung | Wirkung |
|---|---|
| Quell-PNG `320 → 512 px` | exaktes 2:1-Downscaling auf die Anzeige → scharfe Modulkanten |
| Anzeige `w-64 h-64 → w-80 h-80` (256 → 320 px, plus `max-w-full`) | **3,05–3,48 px/Modul** statt 2,4–2,7 |

`w-80` (320 px) passt auch auf schmale iPhones (375 px Viewport ≈ 343 px verfügbar);
`max-w-full` verhindert Überlauf im Zweifel.

## Betroffene Dateien

| Datei | Änderung |
|---|---|
| `api/internal/handler/portal_app_token.go` | `appLink` einmal berechnet; QR kodiert `appLink` statt `jwtStr`; Quellbild 512 px; `app_link`-Feld nutzt dieselbe Variable |
| `web/app/portal/dashboard/PortalDashboardClient.tsx` | QR-Anzeige 256 → 320 px |

Betrifft **API und Web**, keine Migration, **kein Worker-Rebuild**.

## Abnahme

- iPhone-Kamera auf den QR halten → Banner „abrechnung.eeg-gruenlicht.at öffnen"
  bzw. das Angebot, die EEG GrünLicht App zu öffnen → Antippen öffnet die App und
  startet das Pairing.
- In-App-QR-Scanner funktioniert weiterhin (beide Plattformen).
- Android: unverändert; der „In der App öffnen"-Button bleibt.
- 8-stelliger Code unverändert.
