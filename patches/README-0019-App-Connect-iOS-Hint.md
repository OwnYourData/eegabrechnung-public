# Patch 0019: „App verbinden" — iOS-Hinweis statt kaputtem Button

Nachtrag zu Patch 0015. Der mobile Button „In der EEG GrünLicht App öffnen" öffnet
auf **iPhone/iPad** die App nicht: iOS führt einen Universal Link nicht in die App,
wenn er auf einer Seite **derselben Domain** angetippt wird (Portal und `/app/pair`
liegen beide auf `abrechnung.eeg-gruenlicht.at`). Der Button wirkt dort kaputt.

## Was der Patch macht

Plattformabhängig (User-Agent) im Tab „App verbinden", Zustand A:

- **Android** (`isMobile && !isIOS`): Button „In der EEG GrünLicht App öffnen" wie
  bisher (funktioniert dort — App Links haben die Einschränkung nicht).
- **iOS** (`isIOS`, iPhone/iPad/iPod): Button **ausgeblendet**, stattdessen ein
  Hinweis: „Am iPhone: Öffne die EEG GrünLicht App und tippe ‚Mit E-Mail verbinden'
  — oder gib den 8-stelligen Code unten unter ‚Code manuell eingeben' ein. (Der
  Button ‚In der App öffnen' kann die App auf dem iPhone systembedingt nicht öffnen.)"
- **QR-Code und 8-stelliger Code** bleiben auf **beiden** Plattformen sichtbar.

## Umsetzung

Neuer State `isIOS`, gesetzt im bestehenden UA-Effect
(`/iphone|ipad|ipod/i.test(navigator.userAgent)`). `isMobile` bleibt unverändert.
Die Button-Bedingung wird zu `isMobile && !isIOS`; ein `{isIOS && (…)}`-Block zeigt
den Hinweis. Rein additiv, keine Änderung an QR/Code/Restlogik.

## Betroffene Dateien

| Datei | Änderung |
|---|---|
| `web/app/portal/dashboard/PortalDashboardClient.tsx` | `isIOS`-Detection; Button nur Android; iOS-Hinweisblock |

Betrifft **nur Web**, keine API-/Migration-/Worker-Änderung → nur `web` neu bauen.

## Abnahme

- iPhone/iPad: Tab „App verbinden" zeigt **keinen** „In der App öffnen"-Button,
  sondern den Hinweis; QR + 8-stelliger Code sichtbar.
- Android: Button „In der EEG GrünLicht App öffnen" wie bisher; QR + Code sichtbar.
- Desktop: wie bisher (kein Button, kein Hinweis).
