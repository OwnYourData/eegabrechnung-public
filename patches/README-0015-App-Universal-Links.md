# Patch 0015: Direkt-Link Portal → App (Universal / App Links)

Öffnet ein Mitglied das Portal am Handy und tippt unter „App verbinden" auf einen Link, springt es direkt in die GrünLicht-App und das Pairing startet — ohne QR-Scan, ohne Code-Abtippen. Die App-Seite (Entitlement/Intent-Filter) ist fertig; hier kommen die zwei Verifizierungsdateien und der Portal-Link.

## Was gebaut wurde

**1. `/.well-known/apple-app-site-association` (iOS)** — `Content-Type: application/json`, HTTP 200, kein Redirect, keine Auth. Feste Werte: `appID = 39G4BK327Q.at.eeg-gruenlicht.gruenlichtApp`, `paths = ["/app/pair","/app/pair/*"]`.

**2. `/.well-known/assetlinks.json` (Android)** — `package_name = at.eeggruenlicht.gruenlicht_app`, zwei Fingerprints **aus der Umgebung** (siehe unten).

**3. Portal-Link** — auf „App verbinden" (Zustand A), **nur auf Mobilgeräten** sichtbar (UA-Erkennung), Button „In der EEG GrünLicht App öffnen" → `https://abrechnung.eeg-gruenlicht.at/app/pair?t=<JWT>`. Der Token ist **exakt dasselbe** signierte ES256-JWT wie im QR-Code — das Backend liefert es jetzt zusätzlich als fertige URL im Feld `app_link` der `app-token`-Antwort.

**4. Fallback-Seite `/app/pair`** — falls der Link doch im Browser landet (App nicht installiert / Desktop): freundlicher Hinweis, **kein** Verarbeiten des Tokens.

### Routing-Weg (wichtig)

`abrechnung.eeg-gruenlicht.at` zeigt auf **Next.js**. Next 16 behandelt Ordner mit führendem `.` (`app/.well-known/…`) unzuverlässig, deshalb: die JSON-Dateien liegen als Route-Handler unter `app/api/well-known/{aasa,assetlinks}` und werden per **Rewrite** in `next.config.mjs` auf die echten `.well-known`-Pfade gelegt. So sind Pfad **und** `Content-Type` garantiert korrekt.

## Env — Android-Fingerprints (kein Rebuild nötig)

Am **Web**-Deployment setzen (Werte von Christoph):

| Env | Quelle |
|---|---|
| `ANDROID_ASSETLINKS_SHA256_PLAY` | Play Console → App-Integrität → App-Signatur → „SHA-256-Zertifikat-Fingerprint" |
| `ANDROID_ASSETLINKS_SHA256_UPLOAD` | `keytool -list -v -keystore upload-keystore.jks -alias upload` → Zeile „SHA256:" |

Solange leer, enthält `assetlinks.json` ein leeres `sha256_cert_fingerprints`-Array (kein Crash, aber Android verifiziert den Link nicht). Route ist `force-dynamic` → Änderungen der Env greifen ohne Rebuild nach Pod-Neustart.

## ⚠️ Zwei Dinge, die ihr wissen müsst

**1. iOS: Universal Links vom EIGENEN Portal aus.** iOS öffnet einen Universal Link **nicht** in der App, wenn er auf einer Webseite **derselben Domain** angetippt wird — genau unser Fall (Portal und `/app/pair` liegen beide auf `abrechnung.eeg-gruenlicht.at`). Ein Tap auf den Portal-Button landet auf iOS deshalb voraussichtlich auf der **Fallback-Seite**, nicht in der App. Zuverlässig öffnet die App nur, wenn der Link **aus einem anderen Kontext** kommt (Kamera-App scannt den QR/Link, Nachricht, Notiz). Das ist iOS-Plattformverhalten, nicht auf unserer Seite behebbar — bitte an das App-Team: Entweder den QR den Universal-Link-URL enthalten lassen (Kamera-Scan öffnet die App direkt) oder den Portal-Button auf iOS als „mit der Kamera scannen" framen. Android (App Links) ist von dieser Einschränkung **nicht** betroffen.

**2. Die Fingerprints müssen gesetzt sein**, sonst schlägt die Android-Verifikation fehl (Aufgabe 2 / Abnahme).

## Betroffene Dateien

| Datei | Änderung |
|---|---|
| `api/internal/handler/portal_app_token.go` | Feld `app_link` in der `app-token`-Antwort |
| `web/next.config.mjs` | Rewrites für die zwei `.well-known`-Pfade |
| `web/app/api/well-known/aasa/route.ts` | **neu** — AASA-JSON |
| `web/app/api/well-known/assetlinks/route.ts` | **neu** — assetlinks-JSON (env-getrieben) |
| `web/app/app/pair/page.tsx` | **neu** — Browser-Fallback |
| `web/app/portal/dashboard/PortalDashboardClient.tsx` | mobiler „In der App öffnen"-Button in Zustand A |

Betrifft **API und Web**, keine Migration.

## Abnahme

```
curl -sI https://abrechnung.eeg-gruenlicht.at/.well-known/apple-app-site-association
  -> HTTP 200, content-type: application/json, kein Redirect
curl -s  https://abrechnung.eeg-gruenlicht.at/.well-known/assetlinks.json
  -> gültiges JSON mit beiden Fingerprints
```

- Handy mit App (aus fremdem Kontext, s. o.): Link → App öffnet, zeigt Bestätigungscode.
- Portal-Startseite/andere Links → weiterhin normal im Browser (nur `/app/pair` ruft die App).
