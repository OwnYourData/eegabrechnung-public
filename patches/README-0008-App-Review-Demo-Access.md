# Patch 0008: Review-Zugang für die Apple-Beta-Review (TestFlight)

Dauerhafter Demo-Zugang, der **ausschließlich serverseitig** lebt. Die App bekommt **keinen** Demo-Modus und **keine** Backdoor — das Sicherheitsmodell (QR → Pairing → Bestätigung im Portal) bleibt unverändert. Es gibt nur ein Sonder-**Konto**, keinen Sonder-**Weg**.

## Die Review-URL

```
https://abrechnung.eeg-gruenlicht.at/portal/review?t=<APP_REVIEW_TOKEN>
```

**Abweichung von der Spec:** Sie forderte `/portal?t=…`. `/portal` ist aber eine Client-Komponente (Login-Formular); `useSearchParams` dort erzwingt in Next 16 eine Suspense-Grenze und ist eine unnötige Build-Fehlerquelle. `/portal/review` ist ein reiner Route-Handler — er löst den Token serverseitig ein, setzt das `portal_session`-Cookie und leitet ins **normale** `/portal/dashboard` um. Für den Reviewer identisch, für uns risikofrei.

## Absicherung

| Anforderung | Umsetzung |
|---|---|
| Token, 32 Byte, rotierbar | ENV `APP_REVIEW_TOKEN`; Länge < 32 → Link tot (mit Log) |
| Kill-Switch | ENV `APP_REVIEW_ENABLED` ≠ `true` → **404** |
| Konstantzeit-Vergleich | `crypto/subtle.ConstantTimeCompare` |
| Streng an ein Konto gebunden | Das Mitglied wird über `members.is_demo = true` **aus der DB** aufgelöst — nie aus dem Request. Ein partieller Unique-Index erzwingt: höchstens **ein** Demo-Konto. Kein Wechsel auf andere Mitglieder möglich. |
| Nur lesend | Middleware `DenyDemoMember` sperrt **alle** schreibenden Portal-Endpunkte für das Demo-Konto: `change-factor`, `sepa-mandate` (IBAN!), `email-change` → **403**. Pairing bestätigen/ablehnen und Geräte-Entzug bleiben erlaubt — genau die braucht der Reviewer. |
| Rate-Limit | Der Review-Einstieg hängt am bestehenden IP-Limiter (10/min/IP) |
| `noindex, nofollow` | Portal-Layout setzt `robots: { index: false, follow: false }`; die Review-Route zusätzlich `X-Robots-Tag` |
| Logging/Alert | `slog.Warn "app review link used"` (Member, IP, X-Forwarded-For, User-Agent); ungültige Tokens und blockierte Schreibversuche werden ebenfalls geloggt |

Falscher Token **und** Kill-Switch liefern beide **404** — es wird nie verraten, ob der Endpunkt existiert oder der Token nur falsch war.

## QR-Auto-Erneuerung

Der QR behält seine normale kurze Gültigkeit (180 s), erneuert sich aber **automatisch**, sobald der Countdown abläuft — der Reviewer kann nicht in einen abgelaufenen Code laufen. Gilt für alle Mitglieder (keine Demo-Sonderlogik im Frontend).

## Demo-Mitglied

Migration 089 fügt `members.is_demo` hinzu (+ partiellen Unique-Index). Der Datensatz selbst wird per `patches/0008-app-review-demo-member.sql` angelegt:

| Feld | Wert |
|---|---|
| `name` | `Demo Mitglied` (name1 „Demo", name2 „Mitglied") |
| `membership_no` | `0000` |
| EEG | **Demo Energiegemeinschaft** (`00000000-…-0010`, `is_demo=true`) |

**Bewusste Abweichung (abgestimmt):** Die Spec wollte das Konto in der **echten** EEG Bad Vöslau (`437a846f`). Das geht nicht gefahrlos: Der Abrechnungslauf holt die Mitglieder per `WHERE eeg_id = $1` — **ohne Status-Filter**. Ein Demo-Konto dort bekäme eine Rechnung (Fixgebühren!); `INACTIVE` schützt nicht. In der Demo-EEG kann es dagegen niemals in Abrechnungsläufe, Rechnungen, Lücken-Alarme oder Reminder geraten.

**Folge:** `GET /me` liefert für das Demo-Konto `community = "Demo Energiegemeinschaft"` statt „EEG Grünes Licht Bad Vöslau". Bewusst akzeptiert — für einen Demo-Account ehrlicher, und Apple prüft die Funktion, nicht den Community-Namen. Umschalten wäre eine UUID im Seed-SQL **plus** ein Guard, der `is_demo`-Mitglieder aus dem Abrechnungslauf ausschließt.

**Zwei Zählpunkte** (erfunden, `AT003…0` Bezug / `AT003…1` Einspeisung): Ein Zählpunkt hat genau *eine* Energierichtung — für `role = "Prosumer"` (in der Spec „Beides") braucht es beide. `registriert_seit` bleibt NULL, damit keinerlei Datenlücken-/EDA-Logik greift.

## `GET /me` (Aufgabe 1b) — erledigt, betrifft ALLE Mitglieder

`app_member_view` liefert jetzt `member_ref, name, membership_no, community, community_id, role, meter_points` (siehe `patches/0004-app_readonly-gruenlicht.sql`). `meter_points` ist ein **Array** (ein Mitglied kann mehrere haben), `role` wird aus den Energierichtungen abgeleitet — mit exakt den Werten, die das Portal führt: **Prosumer / Einspeiser / Verbraucher** (nicht „Beides"; und **nicht** aus `business_role`, das ist die Rechtsform). Ohne Zählpunkte ist `role` NULL — die App blendet fehlende Felder aus. `email` und `iban` bleiben draußen. **Reines SQL, kein Rebuild nötig.**

## Was die Abrechnung NICHT erfüllen kann

**„max. 30 Pairings/Tag, max. 5 aktive App-Sessions, Sessions nach 24 h widerrufen"** — Pairings und App-Sessions liegen **in der GrünLicht-API**, nicht in der Abrechnung. Die Abrechnung kann sie nur anzeigen/bestätigen, nicht limitieren. Gehört ins API-Team.

## Betroffene Dateien

| Datei | Änderung |
|---|---|
| `api/internal/db/migrations/089_member_demo_flag.{up,down}.sql` | **neu** — `members.is_demo` + partieller Unique-Index |
| `api/internal/handler/portal_app_review.go` | **neu** — `ReviewExchange` + `DenyDemoMember` |
| `api/internal/repository/member_portal.go` | `FindDemoMember`, `IsDemoMember` |
| `api/cmd/server/main.go` | Review-Route (rate-limited) + 3 Write-Guards |
| `web/app/portal/review/route.ts` | **neu** — Token einlösen, Cookie setzen, ins Dashboard |
| `web/app/portal/layout.tsx` | `noindex, nofollow` |
| `web/app/portal/dashboard/PortalDashboardClient.tsx` | QR-Auto-Erneuerung |

## Abnahme

1. `APP_REVIEW_ENABLED=false` → Link liefert **404**.
2. Auf `true` → Link meldet ohne Zugangsdaten als „Demo Mitglied" im normalen Portal an.
3. Tab „App verbinden" zeigt einen gültigen, sich selbst erneuernden QR-Code.
4. Scannen → Code in App **und** Portal → Bestätigen → App angemeldet.
5. Schreibversuch als Demo (IBAN ändern) → **403**.
6. Falscher Token → **404**.
