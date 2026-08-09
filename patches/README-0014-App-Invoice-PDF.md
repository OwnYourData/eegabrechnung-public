# Patch 0014: Rechnungen in der App — View + HMAC-signierter PDF-Endpunkt

Beide Teile liegen auf der **Abrechnungs-Seite** (die Übergabe formulierte es aus API-Sicht, aber die Rohtabellen und die PDFs liegen hier).

## Teil 1 — `app_readonly.app_invoice_view`

`patches/0014-app_invoice_view.sql` ersetzt den leeren Stub durch die echte Definition. Ausgabespalten exakt wie gefordert: `member_ref`, `invoice_id`, `invoice_no`, `period`, `amount_eur`, `issued_at`, `has_pdf`.

Mapping auf das reale Schema (die Übergabe nutzte Platzhalternamen wie `invoice_no`/`amount_gross`/`issued_on`/`pdf`, die es hier nicht gibt):

| Ausgabe | Quelle |
|---|---|
| `member_ref` | `invoices.member_id::text` |
| `invoice_id` | `invoices.id::text` (identisch mit dem `:id` in der PDF-URL) |
| `invoice_no` | `eeg.invoice_number_prefix ‖ lpad(invoice_number, digits, '0')`; Gutschriften nutzen den Credit-Note-Prefix |
| `period` | aus `period_start`/`period_end` fertig formatiert: „Mai 2026" / „Q2 2026" / „2026" / Datumsspanne (österr. „Jänner"; ohne Locale-Abhängigkeit über ein Monats-Array) |
| `amount_eur` | `round(total_amount, 2)` — Brutto-Saldo (bei Erzeugern/Gutschriften ggf. negativ) |
| `issued_at` | `created_at::date` — Erstellungsdatum |
| `has_pdf` | `pdf_path <> ''` |

**Sichtbarkeitsfilter (bitte gegenlesen):** `invoice_number IS NOT NULL AND status <> 'draft' AND status <> 'cancelled'` — also nur **ausgestellte, nicht stornierte** Rechnungen. Gutschriften (`document_type='credit_note'`) sind enthalten. Falls das Mitglied auch stornierte sehen soll, `status <> 'cancelled'` entfernen.

**Bewusste Entscheidungen, die abweichen können:**
- `issued_at = created_at::date`. Es gibt kein dediziertes „Rechnungsdatum"-Feld; `created_at` ist die Erzeugung. Alternative wäre `sent_at` (Versanddatum, aber NULL bei nicht versendeten). Sagt Bescheid, falls die App das Versanddatum will.
- `period` erkennt nur *ganze* Monate/Quartale/Jahre als solche; krumme Zeiträume werden als Datumsspanne gezeigt.

Nach dem Ausführen: `GRANT` steht im Skript. Kein weiteres `USAGE` nötig.

## Teil 2 — PDF-Endpunkt (Go/chi, public, HMAC)

Neuer Handler `api/internal/handler/app_invoice_pdf.go`, Route `GET /app/invoices/{id}/pdf?exp=<unix>&sig=<hex>` (public, keine Session).

Ablauf exakt nach Vorgabe:
1. **Signatur** konstantzeit: `expected = HMAC_SHA256(INVOICE_URL_SIGNING_KEY, "<id>|<exp>")` hex/lowercase, `hmac.Equal`. `<id>` = URL-dekodierter Pfadwert (chi liefert ihn dekodiert), `<exp>` = Query-String.
2. **Ablauf**: `exp` (Unix-Sekunden) muss `>= now` sein.
3. **Ausliefern**: Rechnung per `id` laden, Datei aus `pdf_path` streamen (`Content-Type: application/pdf`, `Content-Disposition: inline`).
4. **Jeder Fehlerfall → 404** (Signatur falsch, abgelaufen, id unbekannt, kein PDF) — kein Orakel, keine 401/403.

Die Ownership-Prüfung passiert bewusst **nicht** hier: Die GrünLicht-API mintet die URL nur für eine Rechnung des eingeloggten Mitglieds (Besitzprüfung dort gegen die `member_ref`-gefilterte View). Die signierte URL ist eine kurzlebige Capability — wir prüfen nur Signatur + Ablauf.

### Routing-Weg

`abrechnung.eeg-gruenlicht.at` zeigt auf **Next.js** (nicht direkt auf die Go-API). Deshalb: Next-Route `web/app/app/invoices/[id]/pdf/route.ts` nimmt den Aufruf entgegen und reicht ihn an die Go-API (`API_INTERNAL_URL`) weiter, die Signatur/Ablauf prüft und die Datei vom Volume streamt. Next streamt die Antwort zurück. Die PDF-Dateien liegen auf dem API-Volume — die Go-API muss sie lesen, deshalb dieser Weg.

## Env / gemeinsames Geheimnis

`INVOICE_URL_SIGNING_KEY` muss auf **beiden** Seiten identisch sein.

- API-Deployment: aus Secret `gruenlicht-api-secret` (Namespace `eegabrechnung`), Key `invoice-url-signing-key`, als Env `INVOICE_URL_SIGNING_KEY`.
- Fehlt der Key, liefert der Endpunkt **404** (kein Leak, keine Fehlermeldung).

Christoph legt den Key an (`openssl rand -hex 32`) und stimmt **denselben Wert** mit dem GrünLicht-Deployment ab.

## Demo-Mitglied

**Nicht unsere Baustelle.** Das Demo-Mitglied liegt in der Demo-EEG und hat keine Rechnungen → die View liefert dafür nichts, die GrünLicht-API schaltet auf ihre synthetische Demo-Quelle um.

## Betroffene Dateien

| Datei | Änderung |
|---|---|
| `patches/0014-app_invoice_view.sql` | **neu** — echte View + GRANT |
| `api/internal/handler/app_invoice_pdf.go` | **neu** — HMAC-Handler |
| `api/cmd/server/main.go` | Handler-Konstruktion + Route `/app/invoices/{id}/pdf` |
| `web/app/app/invoices/[id]/pdf/route.ts` | **neu** — Next-Proxy |

## Abnahme

- Gültige signierte URL → richtiges PDF (öffnet im Browser).
- Manipulierte/abgelaufene Signatur → **404**.
- Unbekannte `invoice_id` → **404** (kein Orakel).
- `app_invoice_view` liefert nur ausgestellte Rechnungen des jeweiligen `member_ref`; keine IBAN/E-Mail/Positionen.
