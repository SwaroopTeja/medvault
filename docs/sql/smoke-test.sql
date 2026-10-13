-- =========================================================
-- smoke-test.sql
-- Run AFTER V1__init.sql and V2__seed_categories.sql.
-- Everything runs in one transaction and is ROLLED BACK at the end,
-- so it leaves no data behind. Any failed check stops the script.
--
-- Run with:  psql -v ON_ERROR_STOP=1 -f smoke-test.sql
-- =========================================================
\set ON_ERROR_STOP on
BEGIN;

-- ---------- helpers (temporary, vanish with the session) ----------
CREATE FUNCTION pg_temp.assert_true(cond boolean, label text) RETURNS void AS $$
BEGIN
    IF cond IS NOT TRUE THEN
        RAISE EXCEPTION 'FAIL: %', label;
    END IF;
    RAISE NOTICE 'PASS: %', label;
END $$ LANGUAGE plpgsql;

-- Runs a statement that MUST be rejected by the database.
CREATE FUNCTION pg_temp.expect_fail(stmt text, label text) RETURNS void AS $$
DECLARE rejected boolean := false;
BEGIN
    BEGIN
        EXECUTE stmt;
    EXCEPTION WHEN OTHERS THEN
        rejected := true;
    END;
    IF NOT rejected THEN
        RAISE EXCEPTION 'FAIL (was accepted, should be rejected): %', label;
    END IF;
    RAISE NOTICE 'PASS (rejected as expected): %', label;
END $$ LANGUAGE plpgsql;

-- The central authorization query from data-model.md section 7.
CREATE FUNCTION pg_temp.can_view(p_doctor uuid, p_grant uuid, p_doc uuid) RETURNS boolean AS $$
    SELECT EXISTS (
        SELECT 1
        FROM documents d
        JOIN access_grants g            ON g.patient_id = d.patient_id
        JOIN access_grant_categories gc ON gc.grant_id = g.id AND gc.category_id = d.category_id
        WHERE d.id        = p_doc
          AND g.id        = p_grant
          AND g.doctor_id = p_doctor
          AND g.status    = 'ACTIVE'
          AND g.expires_at > now()
          AND d.status    = 'READY'
    );
$$ LANGUAGE sql;

-- ---------- 1. seed data ----------
SELECT pg_temp.assert_true(
    (SELECT count(*) FROM categories) = 11,
    'V2 seeded 11 categories');

-- ---------- 2. test users ----------
INSERT INTO users (id, email, password_hash, role, status) VALUES
 ('00000000-0000-0000-0000-00000000000a', 'admin@test.com',    'x', 'ADMIN',   'ACTIVE'),
 ('00000000-0000-0000-0000-000000000001', 'patient1@test.com', 'x', 'PATIENT', 'ACTIVE'),
 ('00000000-0000-0000-0000-000000000002', 'patient2@test.com', 'x', 'PATIENT', 'ACTIVE'),
 ('00000000-0000-0000-0000-0000000000d1', 'doctor1@test.com',  'x', 'DOCTOR',  'ACTIVE'),
 ('00000000-0000-0000-0000-0000000000d2', 'doctor2@test.com',  'x', 'DOCTOR',  'ACTIVE');

INSERT INTO patient_profiles (user_id, full_name) VALUES
 ('00000000-0000-0000-0000-000000000001', 'Patient One'),
 ('00000000-0000-0000-0000-000000000002', 'Patient Two');

INSERT INTO patient_health_info (user_id, blood_group, allergies) VALUES
 ('00000000-0000-0000-0000-000000000001', 'O+', 'penicillin');

INSERT INTO doctor_profiles (user_id, full_name, registration_number, registration_council) VALUES
 ('00000000-0000-0000-0000-0000000000d1', 'Dr One', 'REG001', 'TSMC'),
 ('00000000-0000-0000-0000-0000000000d2', 'Dr Two', 'REG002', 'TSMC');

-- ---------- 3. constraints on users ----------
SELECT pg_temp.expect_fail(
    $$INSERT INTO users (email, password_hash, role, status)
      VALUES ('PATIENT1@TEST.COM', 'x', 'PATIENT', 'ACTIVE')$$,
    'duplicate email (different case) is rejected');

SELECT pg_temp.expect_fail(
    $$INSERT INTO users (email, password_hash, role, status)
      VALUES ('bad@test.com', 'x', 'SUPERUSER', 'ACTIVE')$$,
    'invalid role is rejected');

SELECT pg_temp.expect_fail(
    $$INSERT INTO patient_health_info (user_id, blood_group)
      VALUES ('00000000-0000-0000-0000-000000000002', 'Z+')$$,
    'invalid blood group is rejected');

SELECT pg_temp.expect_fail(
    $$INSERT INTO doctor_profiles (user_id, full_name, registration_number, registration_council)
      VALUES ('00000000-0000-0000-0000-00000000000a', 'Dup', 'REG001', 'TSMC')$$,
    'duplicate doctor registration number is rejected');

-- ---------- 4. documents ----------
INSERT INTO documents (id, patient_id, category_id, title, original_filename, mime_type,
                       size_bytes, storage_key, wrapped_data_key, checksum_sha256,
                       extracted_text, status)
VALUES
 -- patient1 HEART doc
 ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001',
  (SELECT id FROM categories WHERE code = 'HEART'), 'ECG report', 'ecg.pdf', 'application/pdf',
  1000, 'test/key1', '\x00', repeat('a', 64), 'ECG shows normal sinus rhythm', 'READY'),
 -- patient1 SKIN doc
 ('10000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001',
  (SELECT id FROM categories WHERE code = 'SKIN'), 'Rash visit', 'rash.pdf', 'application/pdf',
  1000, 'test/key2', '\x00', repeat('b', 64), 'Dermatology notes on eczema', 'READY'),
 -- patient2 HEART doc (belongs to someone else)
 ('10000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000002',
  (SELECT id FROM categories WHERE code = 'HEART'), 'Other patient ECG', 'ecg2.pdf', 'application/pdf',
  1000, 'test/key3', '\x00', repeat('c', 64), 'private data', 'READY');

SELECT pg_temp.assert_true(
    (SELECT search_vector IS NOT NULL FROM documents
     WHERE id = '10000000-0000-0000-0000-000000000001'),
    'search_vector trigger populated the column');

SELECT pg_temp.assert_true(
    (SELECT count(*) FROM documents
     WHERE patient_id = '00000000-0000-0000-0000-000000000001'
       AND search_vector @@ plainto_tsquery('simple', 'sinus')) = 1,
    'full-text search finds "sinus" in patient1 documents only');

SELECT pg_temp.expect_fail(
    $$INSERT INTO documents (patient_id, category_id, title, original_filename, mime_type,
                             size_bytes, storage_key, wrapped_data_key, checksum_sha256, status)
      VALUES ('00000000-0000-0000-0000-000000000001',
              (SELECT id FROM categories WHERE code = 'LAB'), 't', 'f', 'application/pdf',
              10, 'test/key4', '\x00', repeat('d', 64), 'BROKEN')$$,
    'invalid document status is rejected');

-- ---------- 5. access grants ----------
-- Active grant: doctor1 may see patient1's HEART category for 1 hour
INSERT INTO access_grants (id, patient_id, doctor_id, token_hash, status, duration_minutes,
                           claim_expires_at, activated_at, expires_at)
VALUES ('20000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001',
        '00000000-0000-0000-0000-0000000000d1', repeat('1', 64), 'ACTIVE', 60,
        now() + interval '5 minutes', now(), now() + interval '1 hour');
INSERT INTO access_grant_categories (grant_id, category_id)
VALUES ('20000000-0000-0000-0000-000000000001', (SELECT id FROM categories WHERE code = 'HEART'));

-- Expired grant (status still ACTIVE: simulates a delayed cleanup job)
INSERT INTO access_grants (id, patient_id, doctor_id, token_hash, status, duration_minutes,
                           claim_expires_at, activated_at, expires_at)
VALUES ('20000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001',
        '00000000-0000-0000-0000-0000000000d1', repeat('2', 64), 'ACTIVE', 60,
        now() - interval '2 hours', now() - interval '90 minutes', now() - interval '30 minutes');
INSERT INTO access_grant_categories (grant_id, category_id)
VALUES ('20000000-0000-0000-0000-000000000002', (SELECT id FROM categories WHERE code = 'HEART'));

SELECT pg_temp.expect_fail(
    $$INSERT INTO access_grants (patient_id, token_hash, status, duration_minutes,
                                 claim_expires_at, expires_at)
      VALUES ('00000000-0000-0000-0000-000000000001', repeat('3', 64), 'ACTIVE', 60,
              now() + interval '5 minutes', now() + interval '1 hour')$$,
    'ACTIVE grant without a doctor is rejected');

SELECT pg_temp.expect_fail(
    $$INSERT INTO access_grants (patient_id, token_hash, status, duration_minutes,
                                 total_extended_minutes, claim_expires_at)
      VALUES ('00000000-0000-0000-0000-000000000001', repeat('4', 64), 'PENDING', 10000,
              1000, now() + interval '5 minutes')$$,
    'grant over the 7-day cap is rejected');

SELECT pg_temp.expect_fail(
    $$INSERT INTO access_grants (patient_id, token_hash, status, duration_minutes, claim_expires_at)
      VALUES ('00000000-0000-0000-0000-000000000001', repeat('1', 64), 'PENDING', 30,
              now() + interval '5 minutes')$$,
    'duplicate QR token hash is rejected');

-- ---------- 6. THE central authorization check ----------
SELECT pg_temp.assert_true(
    pg_temp.can_view('00000000-0000-0000-0000-0000000000d1',
                     '20000000-0000-0000-0000-000000000001',
                     '10000000-0000-0000-0000-000000000001'),
    'AUTH: correct doctor + active grant + granted category is ALLOWED');

SELECT pg_temp.assert_true(
    NOT pg_temp.can_view('00000000-0000-0000-0000-0000000000d2',
                         '20000000-0000-0000-0000-000000000001',
                         '10000000-0000-0000-0000-000000000001'),
    'AUTH: a different doctor is DENIED');

SELECT pg_temp.assert_true(
    NOT pg_temp.can_view('00000000-0000-0000-0000-0000000000d1',
                         '20000000-0000-0000-0000-000000000001',
                         '10000000-0000-0000-0000-000000000002'),
    'AUTH: category not in the grant (SKIN) is DENIED');

SELECT pg_temp.assert_true(
    NOT pg_temp.can_view('00000000-0000-0000-0000-0000000000d1',
                         '20000000-0000-0000-0000-000000000001',
                         '10000000-0000-0000-0000-000000000003'),
    'AUTH: another patient''s document is DENIED');

SELECT pg_temp.assert_true(
    NOT pg_temp.can_view('00000000-0000-0000-0000-0000000000d1',
                         '20000000-0000-0000-0000-000000000002',
                         '10000000-0000-0000-0000-000000000001'),
    'AUTH: expired grant is DENIED even if status is still ACTIVE');

UPDATE access_grants SET status = 'REVOKED', revoked_at = now()
WHERE id = '20000000-0000-0000-0000-000000000001';

SELECT pg_temp.assert_true(
    NOT pg_temp.can_view('00000000-0000-0000-0000-0000000000d1',
                         '20000000-0000-0000-0000-000000000001',
                         '10000000-0000-0000-0000-000000000001'),
    'AUTH: revoked grant is DENIED immediately');

-- ---------- 7. audit log is append-only ----------
INSERT INTO audit_logs (actor_id, actor_role, action, subject_user_id)
VALUES ('00000000-0000-0000-0000-0000000000d1', 'DOCTOR', 'GRANT_CLAIM',
        '00000000-0000-0000-0000-000000000001');

SELECT pg_temp.expect_fail($$UPDATE audit_logs SET action = 'TAMPERED'$$,
    'audit_logs UPDATE is blocked');
SELECT pg_temp.expect_fail($$DELETE FROM audit_logs$$,
    'audit_logs DELETE is blocked');

-- ---------- 8. admin view exposes no medical data ----------
SELECT pg_temp.assert_true(
    (SELECT count(*) FROM information_schema.columns
     WHERE table_name = 'v_admin_users'
       AND column_name IN ('allergies','blood_group','chronic_conditions',
                           'extracted_text','storage_key','title')) = 0,
    'ADMIN VIEW: contains no medical or document columns');

SELECT pg_temp.assert_true(
    (SELECT count(*) FROM v_admin_users) = 5,
    'ADMIN VIEW: lists all 5 test users');

-- ---------- 9. cascade delete (right to erasure) ----------
DELETE FROM users WHERE id = '00000000-0000-0000-0000-000000000001';

SELECT pg_temp.assert_true(
    (SELECT count(*) FROM documents
     WHERE patient_id = '00000000-0000-0000-0000-000000000001') = 0
    AND (SELECT count(*) FROM access_grants
         WHERE patient_id = '00000000-0000-0000-0000-000000000001') = 0
    AND (SELECT count(*) FROM patient_health_info
         WHERE user_id = '00000000-0000-0000-0000-000000000001') = 0,
    'ERASURE: deleting a patient removes documents, grants and health info');

SELECT pg_temp.assert_true(
    (SELECT count(*) FROM audit_logs) = 1,
    'ERASURE: audit log survives patient deletion');

-- ---------- done ----------
DO $$ BEGIN RAISE NOTICE '=== ALL SMOKE TESTS PASSED ==='; END $$;

ROLLBACK;  -- leaves the database exactly as it was
