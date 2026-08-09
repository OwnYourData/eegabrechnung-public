# Patch 0024: „App verbinden" — iOS-Store-Link live, Android-Hinweis

Die iOS-App ist im App Store. Der Tab „App verbinden" zeigt jetzt plattformabhängig
den passenden Store-Weg; Android bekommt statt eines toten Play-Store-Links einen
Hinweis, bis Google live ist.

## Was der Patch baut

**Plattformabhängige Store-Links** (User-Agent, `isMobile`/`isIOS` aus Patch 0019):

| Plattform | Anzeige |
|---|---|
| iPhone | Button „Im App Store laden" |
| Android | Hinweis „…voraussichtlich Mitte August…" (bzw. Play-Store-Button, sobald live) |
| Desktop | App-Store-Button **und** Android-Hinweis |

Bedingungen: iOS-Button `ios_url && (isIOS || !isMobile)`, Android-Block `!isIOS`
(also alles außer iOS-Geräten). Die App ist **iPhone-only**; der Button erscheint
UA-technisch auch auf iPad (`isIOS` matcht `ipad`), was unkritisch ist — die
App-Store-Seite weist die App dort als iPhone-App aus. Das Banner nennt bewusst nur
iPhone.

**Banner korrigiert** — siehe Entscheidung unten.

Unverändert: QR-Code, 8-stelliger Code, „In der EEG GrünLicht App öffnen" (Android),
iOS-Hinweis. Die Store-Links ergänzen diese Wege nur.

## Live-Schalter = Store-URL (kein neues Feld)

Der Auftrag nennt `app_ios_live`/`app_android_live`. Statt neuer Flags nutzt der Patch
den **bereits bestehenden** Mechanismus aus Patch 0004: Die API sendet `ios_url` /
`android_url` aus den Env-Variablen `PORTAL_APP_IOS_URL` / `PORTAL_APP_ANDROID_URL`.
Vorhandene URL = „live". Das ist ohne Rebuild schaltbar und vermeidet zwei parallele
Wahrheiten (Flag + URL).

| Zustand | Env am **API**-Deployment |
|---|---|
| iOS live (jetzt) | `PORTAL_APP_IOS_URL=https://apps.apple.com/at/app/id6790113324` |
| Android noch nicht | `PORTAL_APP_ANDROID_URL` leer/ungesetzt → Hinweis erscheint |
| Android live (später) | `PORTAL_APP_ANDROID_URL=<Play-Store-Link>` → Button erscheint, Hinweis weg |

## ⚠️ Entscheidung: das „Funktion in Entwicklung"-Banner wurde geändert

Der Auftrag hat das Banner nicht erwähnt, aber es stand im direkten Widerspruch zur
Aufgabe: Es sagte „…noch nicht allgemein verfügbar… voraussichtlich **Ende August** in
den App Stores", während iPhone-Nutzer jetzt direkt darunter einen „Im App Store
laden"-Button sehen. Das hätte auf demselben Screen wie ein Bug gewirkt.

Neuer, faktentreuer Text (Box/Styling unverändert):

> **EEG GrünLicht App** — Die App ist ab sofort für iPhone im App Store verfügbar.
> Die Android-Version folgt voraussichtlich Mitte August.

Falls das Banning ganz entfallen soll, ist das der eine Hunk zum Entfernen — sag
Bescheid.

## Kleine Abweichung vom Auftragstext

Der Android-Hinweis ist auf die Sie-Anrede angepasst („wir informieren **Sie**" statt
„euch"), weil das Mitgliederportal durchgängig siezt („Scannen **Sie** diesen Code").

## Betroffene Dateien

| Datei | Änderung |
|---|---|
| `web/app/portal/dashboard/PortalDashboardClient.tsx` | plattformabhängige Store-Links + Android-Hinweis; Banner-Text |

**Nur Web**, keine API-Codeänderung, keine Migration, kein Worker.

## Deploy

Zwei Schritte, beide ohne API-Rebuild:

1. **Env am API-Deployment setzen** (die App-Token-Antwort kommt aus dem API-Prozess):
   ```zsh
   pace set env deploy/eegabrechnung-api -n eegabrechnung \
     PORTAL_APP_IOS_URL="https://apps.apple.com/at/app/id6790113324"
   ```
   `PORTAL_APP_ANDROID_URL` **nicht** setzen (leer = Hinweis).
2. **`eegabrechnung-web` neu bauen/ausrollen** (Frontend-Änderung).

Wenn Google live ist: `PORTAL_APP_ANDROID_URL=<Play-Store-Link>` am API-Deployment
setzen — der Play-Store-Button erscheint, der Hinweis verschwindet, **kein** Rebuild
nötig.

## Abnahme

Verifiziert gegen `v2026-07-13` + Patches 0002–0024 (TSX parst sauber):

- iPhone: „Im App Store laden" führt auf `apps.apple.com/at/app/id6790113324`
  (Apple leitet auf die benannte URL weiter). Kein Android-Element.
- Android: „Mitte August"-Hinweis, **kein** toter Link.
- Desktop: App-Store-Button **und** Android-Hinweis.
- Nach `PORTAL_APP_ANDROID_URL`-Setzen: Play-Store-Button statt Hinweis.
