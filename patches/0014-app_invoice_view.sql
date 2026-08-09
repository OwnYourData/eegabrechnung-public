-- =====================================================================
-- app_readonly.app_invoice_view — Rechnungen für die GrünLicht-App
-- Als DB-Superuser ausführen. Ersetzt den leeren Stub der GrünLicht-Seite.
--
-- Die GrünLicht-API liest GENAU diese Spalten:
--   member_ref, invoice_id, invoice_no, period, amount_eur, issued_at, has_pdf
-- Keine Einzelpositionen, keine IBAN, keine E-Mail.
-- member_ref = members.id (UUID) als text.
-- =====================================================================

DROP VIEW IF EXISTS app_readonly.app_invoice_view;

CREATE VIEW app_readonly.app_invoice_view AS
SELECT
    i.member_id::text AS member_ref,
    i.id::text        AS invoice_id,

    -- Anzeigenummer: prefix + nullgepolsterte Nr. Gutschriften nutzen den
    -- Credit-Note-Prefix (Migration 019).
    CASE WHEN i.document_type = 'credit_note'
         THEN e.credit_note_number_prefix || lpad(i.invoice_number::text, GREATEST(e.credit_note_number_digits, 1), '0')
         ELSE e.invoice_number_prefix     || lpad(i.invoice_number::text, GREATEST(e.invoice_number_digits, 1),    '0')
    END AS invoice_no,

    -- Zeitraum, fertig formatiert (Wien-neutral, aus den date-Feldern):
    --   ganzer Monat   -> "Mai 2026"   (österr. "Jänner")
    --   ganzes Quartal -> "Q2 2026"
    --   ganzes Jahr    -> "2026"
    --   sonst          -> "01.05.2026–31.05.2026"
    CASE
      WHEN i.period_start = date_trunc('month', i.period_start)::date
       AND i.period_end   = (date_trunc('month', i.period_start) + INTERVAL '1 month' - INTERVAL '1 day')::date
        THEN (ARRAY['Jänner','Februar','März','April','Mai','Juni',
                    'Juli','August','September','Oktober','November','Dezember'])
                 [EXTRACT(MONTH FROM i.period_start)::int]
             || ' ' || EXTRACT(YEAR FROM i.period_start)::text
      WHEN i.period_start = date_trunc('quarter', i.period_start)::date
       AND i.period_end   = (date_trunc('quarter', i.period_start) + INTERVAL '3 months' - INTERVAL '1 day')::date
        THEN 'Q' || EXTRACT(QUARTER FROM i.period_start)::text || ' ' || EXTRACT(YEAR FROM i.period_start)::text
      WHEN i.period_start = date_trunc('year', i.period_start)::date
       AND i.period_end   = (date_trunc('year', i.period_start) + INTERVAL '1 year' - INTERVAL '1 day')::date
        THEN EXTRACT(YEAR FROM i.period_start)::text
      ELSE to_char(i.period_start, 'DD.MM.YYYY') || '–' || to_char(i.period_end, 'DD.MM.YYYY')
    END AS period,

    round(i.total_amount, 2) AS amount_eur,     -- Bruttobetrag (kann bei Erzeugern negativ sein)
    i.created_at::date       AS issued_at,       -- Rechnungsdatum (Erstellung); API sortiert absteigend
    (i.pdf_path <> '')       AS has_pdf
FROM public.invoices i
JOIN public.eegs      e ON e.id = i.eeg_id
WHERE i.invoice_number IS NOT NULL   -- ausgestellt (Entwürfe haben keine Nummer)
  AND i.status <> 'draft'
  AND i.status <> 'cancelled';       -- stornierte nicht in der App zeigen

GRANT SELECT ON app_readonly.app_invoice_view TO gruenlicht_ro;

-- =====================================================================
-- Kontrolle (als Superuser)
-- =====================================================================
-- \d+ app_readonly.app_invoice_view
--   -> member_ref, invoice_id, invoice_no, period, amount_eur, issued_at, has_pdf
--
-- SELECT member_ref, invoice_no, period, amount_eur, issued_at, has_pdf
-- FROM app_readonly.app_invoice_view
-- ORDER BY issued_at DESC LIMIT 10;
--
-- NEGATIVTEST als gruenlicht_ro:
--   SELECT * FROM app_readonly.app_invoice_view LIMIT 1;  -- GEHT
--   SELECT * FROM public.invoices LIMIT 1;                -- SCHEITERT (permission denied)
