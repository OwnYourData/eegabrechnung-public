# Patch 0005: Onboarding-Erinnerungen — Abschalt-Toggle + Auto-Flip

## Problem

Das System verschickt 72h-„Beitritt abschließen"-Erinnerungen an Onboarding-Anfragen mit `status = 'eda_sent'`. Von `eda_sent` auf `active` schaltet normalerweise die EDA-Bestätigung über den Worker (`SetActiveByMeterPoint` bei ABSCHLUSS_ECON). Bei **manuell/extern im EDA-Portal bestätigten** Anmeldungen kommt diese Worker-Bestätigung nie an → die Anfrage bleibt ewig auf `eda_sent` → bereits vollwertige Mitglieder bekommen weiter Erinnerungen.

## Was der Patch macht (zwei Teile)

**1. Auto-Flip (behebt die Ursache):** Wird das Aktivierungsdatum (`registriert_seit`) manuell über die UI gesetzt/korrigiert (der Pfad aus Patch 0003), wird zusätzlich die zugehörige Onboarding-Anfrage von `eda_sent`/`converted` auf `active` geschaltet. Damit stoppen die Erinnerungen automatisch, sobald ein extern bestätigtes Mitglied lokal aktiviert wird. Best-effort — ein Fehler dabei lässt das Speichern nicht scheitern.

**2. EEG-Schalter „Onboarding-Erinnerungen senden" (an/aus):** Neuer Toggle in den EEG-Einstellungen (Tab **Onboarding**), analog zu Lücken-Alarm/Auto-Abrechnung. Default **an** (bestehendes Verhalten). Ausgeschaltet unterdrückt er **beide** 72h-Erinnerungstypen (offene `eda_sent`-Anfragen **und** abgebrochene E-Mail-Verifizierungen) für dieses EEG.

## Betroffene Dateien

| Datei | Änderung |
|---|---|
| `api/internal/db/migrations/087_onboarding_reminder_toggle.{up,down}.sql` | **neu** — `onboarding_reminder_enabled BOOLEAN NOT NULL DEFAULT true` auf `eegs` |
| `api/internal/domain/types.go` | Feld `OnboardingReminderEnabled` auf `EEG` |
| `api/internal/repository/eeg.go` | Spalte in `eegCols`/`scanEEG` + `UPDATE`-Statement (`onboarding_reminder_enabled=$65`, angehängt) |
| `api/internal/handler/eeg.go` | Request-Feld + Zuweisung im `UpdateEEG`-Handler |
| `api/internal/repository/onboarding.go` | `FindNeedingReminder` **und** `FindAbandonedEmailVerifications`: `AND e.onboarding_reminder_enabled = true` |
| `api/internal/repository/meterpoint.go` | neue Methode `MarkOnboardingActiveByMeterPoint` (UPDATE `onboarding_requests` → `active`) |
| `api/internal/handler/meter_point.go` | Auto-Flip-Aufruf nach manueller `registriert_seit`-Änderung |
| `web/app/eegs/[eegId]/settings/page.tsx` | Toggle „72h-Beitritts-Erinnerungen senden" im Onboarding-Tab + Hidden-Input + Save-Payload |

## Abhängigkeit / Reihenfolge

Der Auto-Flip-Teil baut auf **Patch 0003** auf (er ergänzt denselben `registriert_seit`-Handler-Block). Der Patch wurde gegen den Stand **07-07 + Patches 0002–0004** erzeugt; `git apply patches/*.patch` wendet 0002→0005 in der richtigen Reihenfolge an. Verifiziert: alle Patches zusammen `git apply --check` grün gegen pristine `v2026-07-07`; UPDATE-Query `$1..$65` = 65 Exec-Argumente (konsistent).

## Anwenden & Bauen

```bash
git apply --check patches/*.patch
```

Betrifft **API und Web** (+ Migration 087, läuft beim API-Start automatisch). Beide Images neu bauen und ausrollen.

## Bereits hängende Anfragen

Der Auto-Flip greift nur bei **künftigen** `registriert_seit`-Änderungen. Für die **jetzt schon** auf `eda_sent` hängenden, aber fertigen Mitglieder entweder das einmalige SQL-UPDATE ausführen (siehe Chat-Verlauf) oder den EEG-Toggle ausschalten.

## Verifizieren

1. EEG-Einstellungen → Tab **Onboarding** → Toggle „72h-Beitritts-Erinnerungen senden" sichtbar, standardmäßig an; aus-/einschalten speichert.
2. Bei ausgeschaltetem Toggle sendet der stündliche Job für dieses EEG keine Erinnerungen mehr.
3. Zählpunkt bearbeiten, `registriert_seit` setzen, speichern → die Onboarding-Anfrage des Mitglieds steht danach auf `active` (keine weiteren Erinnerungen).
