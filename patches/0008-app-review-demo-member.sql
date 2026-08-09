-- =====================================================================
-- Demo-Mitglied für die Apple-Beta-Review (TestFlight)
-- Einmalig ausführen, NACH dem Deployment von Patch 0008
-- (Migration 089 legt die Spalte members.is_demo an).
--
-- Idempotent: legt nur an, wenn noch kein Demo-Mitglied existiert.
-- Ein partieller Unique-Index erzwingt ohnehin: höchstens EIN is_demo = true.
-- =====================================================================
--
-- HEIMAT-EEG: die "Demo Energiegemeinschaft" (is_demo = true).
-- BEWUSST NICHT die echte "EEG Grünes Licht Bad Vöslau" (437a846f-…):
-- Der Abrechnungslauf holt die Mitglieder per `WHERE eeg_id = $1` OHNE
-- Status-Filter — ein Demo-Konto in einer echten EEG bekäme also eine
-- Rechnung (Fixgebühren). In der Demo-EEG kann es niemals in Abrechnungs-
-- läufe, Rechnungen, Lücken-Alarme oder Reminder geraten.
--
-- Folge: GET /me liefert für das Demo-Konto `community` = "Demo
-- Energiegemeinschaft" (nicht "EEG Grünes Licht Bad Vöslau"). Bewusst
-- akzeptiert — für einen Demo-Account ist das ehrlicher, und Apple prüft
-- die Funktion, nicht den Community-Namen.
-- =====================================================================

-- Vorprüfung: existiert die Demo-EEG?
SELECT id, name, is_demo FROM eegs
WHERE id = '00000000-0000-0000-0000-000000000010';

-- ---------------------------------------------------------------------
-- (1) Demo-Mitglied
-- ---------------------------------------------------------------------
INSERT INTO members (eeg_id, mitglieds_nr, name1, name2, email, business_role, status, is_demo)
SELECT '00000000-0000-0000-0000-000000000010'::uuid,
       '0000',
       'Demo',
       'Mitglied',
       'app-review@invalid.local',   -- nicht zustellbar; Demo-EEG blockt Mails ohnehin
       'privat',
       'ACTIVE',
       true
WHERE NOT EXISTS (SELECT 1 FROM members WHERE is_demo = true);

-- ---------------------------------------------------------------------
-- (2) Zwei erfundene Zählpunkte.
--     Ein Zählpunkt hat GENAU EINE Energierichtung — für role = 'Prosumer'
--     (in der Spec "Beides") braucht es daher zwei: Bezug + Einspeisung.
--     registriert_seit bleibt NULL: so greift keinerlei Datenlücken-/EDA-Logik.
-- ---------------------------------------------------------------------
INSERT INTO meter_points (member_id, eeg_id, zaehlpunkt, energierichtung, status)
SELECT m.id, m.eeg_id, v.zp, v.richtung, 'ACTIVATED'
FROM members m
CROSS JOIN (VALUES
    ('AT0030000000000000000000000000000', 'CONSUMPTION'),
    ('AT0030000000000000000000000000001', 'GENERATION')
) AS v(zp, richtung)
WHERE m.is_demo = true
  AND NOT EXISTS (
      SELECT 1 FROM meter_points mp
      WHERE mp.member_id = m.id AND mp.zaehlpunkt = v.zp
  );

-- ---------------------------------------------------------------------
-- (3) Kontrolle — genau das sieht die GrünLicht-API in app_member_view
-- ---------------------------------------------------------------------
SELECT member_ref, name, membership_no, community, community_id, role, meter_points
FROM app_readonly.app_member_view
WHERE member_ref = (SELECT id::text FROM members WHERE is_demo = true);

-- Erwartet:
--   name          = "Demo Mitglied"
--   membership_no = "0000"
--   role          = "Prosumer"
--   meter_points  = {AT0030000000000000000000000000000,AT0030000000000000000000000000001}
--   community     = "Demo Energiegemeinschaft"   (siehe Kopf-Kommentar)
--   genau 1 Zeile

-- =====================================================================
-- Rückbau nach der Review (optional — der Kill-Switch APP_REVIEW_ENABLED=false
-- reicht normalerweise; das Konto darf ruhig bestehen bleiben)
-- =====================================================================
-- DELETE FROM meter_points WHERE member_id = (SELECT id FROM members WHERE is_demo = true);
-- DELETE FROM members WHERE is_demo = true;
