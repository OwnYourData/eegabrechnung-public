-- =====================================================================
-- Read-only-Zugang für die GrünLicht-API
-- Als DB-Superuser auf der Abrechnungs-DB ausführen. Idempotent.
--
-- Zwei Views:
--   app_login_token_view  -> Login (QR-Token ODER manueller Kurzcode)
--   app_member_view       -> GET /me
--
-- Grundsätze:
--   * member_ref := members.id (UUID) als text — in BEIDEN Views identisch.
--   * email und iban tauchen in KEINER View auf.
--   * Kein EEG-Filter: jedes Mitglied jeder Gemeinschaft soll die App verbinden
--     können. Der Schutz liegt in den Spalten, nicht im Filter.
--   * Die Abrechnung markiert Tokens/Codes NICHT als verbraucht — Single-Use
--     erzwingt die API in ihrer eigenen DB (damit sie read-only bleibt).
--
-- HINWEIS zur Wartung: Die Views werden bewusst per DROP + CREATE neu angelegt.
-- CREATE OR REPLACE VIEW darf Spalten nur ANHÄNGEN — nicht einfügen, umbenennen
-- oder umsortieren. Mit DROP + CREATE ist jede Änderung möglich; die GRANTs am
-- Ende des Skripts stellen die Rechte anschließend wieder her.
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS app_readonly;

DROP VIEW IF EXISTS app_readonly.app_login_token_view;
DROP VIEW IF EXISTS app_readonly.app_member_view;

-- ---------------------------------------------------------------------
-- (1) Login auflösen — zwei gleichwertige Wege zum SELBEN Vorgang:
--
--   token_hash       SHA-256 des QR-JWT-Tokens (`tok`-Claim)
--   short_code_hash  SHA-256 des manuellen 8-Zeichen-Codes (Crockford-Base32),
--                    NORMALISIERT: Großbuchstaben, ohne Bindestrich.
--                    Die API normalisiert eingehende Codes verzeihend:
--                    O -> 0, I/L -> 1, Bindestriche/Leerzeichen entfernen.
--                    Rohspalte heißt intern `code_hash`; die API liest ausschließlich
--                    den Alias `short_code_hash` (nie `code_hash`).
--   source           'qr' (QR-/Kurzcode-Login, Default) ODER 'email' (Magic-Link,
--                    der ausschließlich an die registrierte Adresse ging). Die API
--                    bestätigt NUR source='email'-Pairings automatisch bei
--                    POST /app/pair/start; QR-/Kurzcode-Tokens bleiben bei der
--                    Portal-Bestätigung. (Spalte via Migration 091.)
--
-- Beide Klartexte stehen NIE in der DB — nur ihre Hashes.
-- Gemeinsame TTL (expires_at): QR/Kurzcode 180 s, E-Mail-Link 600 s.
-- ---------------------------------------------------------------------
CREATE VIEW app_readonly.app_login_token_view AS
SELECT t.token_hash      AS token_hash,
       t.member_id::text AS member_ref,
       t.expires_at      AS expires_at,
       t.code_hash       AS short_code_hash,
       t.source          AS source
FROM public.app_login_tokens t;

-- ---------------------------------------------------------------------
-- (2) Stammdaten für GET /me.  KEIN email, KEIN iban.
--
--   meter_points  text[] — ein Mitglied kann MEHRERE Zählpunkte haben
--                 (Prosumer: Bezug + Einspeisung). Abgemeldete sind raus.
--   role          abgeleitet aus meter_points.energierichtung, mit exakt den
--                 Werten, die das Portal führt: Prosumer / Einspeiser /
--                 Verbraucher. NICHT aus business_role — das ist die Rechtsform
--                 (privat/gewerbe), nicht die Energierichtung.
--                 Ohne Zählpunkte: NULL (die App blendet fehlende Felder aus).
--
--   Mapping in der API (snake_case -> camelCase):
--     member_ref -> id, membership_no -> membershipNo,
--     community_id -> communityId, meter_points -> meterPoints
-- ---------------------------------------------------------------------
CREATE VIEW app_readonly.app_member_view AS
SELECT m.id::text                              AS member_ref,
       btrim(concat_ws(' ', m.name1, m.name2)) AS name,
       m.mitglieds_nr                          AS membership_no,
       e.name                                  AS community,
       e.id::text                              AS community_id,
       CASE
         WHEN COALESCE(zp.has_consumption, false) AND COALESCE(zp.has_generation, false) THEN 'Prosumer'
         WHEN COALESCE(zp.has_generation,  false)                                        THEN 'Einspeiser'
         WHEN COALESCE(zp.has_consumption, false)                                        THEN 'Verbraucher'
         ELSE NULL
       END                                     AS role,
       COALESCE(zp.meter_points, ARRAY[]::text[]) AS meter_points
FROM public.members m
JOIN public.eegs e ON e.id = m.eeg_id
LEFT JOIN LATERAL (
    SELECT array_agg(mp.zaehlpunkt ORDER BY mp.zaehlpunkt)  AS meter_points,
           bool_or(mp.energierichtung = 'CONSUMPTION')      AS has_consumption,
           bool_or(mp.energierichtung = 'GENERATION')       AS has_generation
    FROM public.meter_points mp
    WHERE mp.member_id = m.id
      AND mp.abgemeldet_am IS NULL
) zp ON TRUE;

-- =====================================================================
-- DB-User mit minimalen Rechten
--
-- PASSWORT: NICHT hier eintragen und NICHT committen. Lokal erzeugen mit
--     openssl rand -hex 32
-- Danach ins k8s-Secret `gruenlicht-api-secret` (Key `billing-database-url`):
--     postgresql://gruenlicht_ro:<PW>@pgcluster.db.svc.cluster.local:5432/eegabrechnung
-- =====================================================================
-- Falls die Rolle noch nicht existiert:
-- CREATE ROLE gruenlicht_ro LOGIN PASSWORD '<HIER_PASSWORT_EINSETZEN>';
ALTER ROLE gruenlicht_ro NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT;
ALTER ROLE gruenlicht_ro SET search_path = app_readonly;

REVOKE ALL ON SCHEMA public               FROM gruenlicht_ro;
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM gruenlicht_ro;

GRANT USAGE  ON SCHEMA app_readonly TO gruenlicht_ro;
GRANT SELECT ON app_readonly.app_login_token_view,
                app_readonly.app_member_view
  TO gruenlicht_ro;

-- Views laufen mit den Rechten ihres EIGENTÜMERS (Superuser). gruenlicht_ro
-- erhält SELECT nur auf die beiden Views -> Rohtabellen bleiben unerreichbar.

-- =====================================================================
-- KONTROLLE (als Superuser)
-- =====================================================================
-- \d+ app_readonly.app_login_token_view
--   -> token_hash, member_ref, expires_at, short_code_hash, source
--   (Die GrünLicht-API liest ausschließlich über Spaltennamen, nie über Position —
--    die Reihenfolge ist daher unkritisch, zusätzliche Spalten werden ignoriert.)
-- \d+ app_readonly.app_member_view
--   -> member_ref, name, membership_no, community, community_id, role, meter_points
--
-- SELECT member_ref, name, membership_no, community, role, meter_points
-- FROM app_readonly.app_member_view LIMIT 5;
--
-- =====================================================================
-- NEGATIVTEST — als gruenlicht_ro
-- =====================================================================
-- MUSS GEHEN:
--   SELECT * FROM app_readonly.app_member_view      LIMIT 3;
--   SELECT * FROM app_readonly.app_login_token_view LIMIT 1;
--
-- MUSS SCHEITERN ("permission denied"):
--   SELECT * FROM public.members          LIMIT 1;
--   SELECT * FROM public.app_login_tokens LIMIT 1;
--   SELECT * FROM public.eegs             LIMIT 1;
--   INSERT INTO public.app_login_tokens (token_hash, member_id, expires_at)
--          VALUES ('x', gen_random_uuid(), now());
--   UPDATE public.app_login_tokens SET expires_at = now();
