-- =========================================================
-- V1__init.sql  MedVault initial schema
-- =========================================================

-- ---------- USERS ----------
CREATE TABLE users (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email               VARCHAR(255) NOT NULL,
    password_hash       VARCHAR(255) NOT NULL,
    role                VARCHAR(20)  NOT NULL,
    status              VARCHAR(30)  NOT NULL,
    mfa_enabled         BOOLEAN      NOT NULL DEFAULT FALSE,
    mfa_secret_enc      TEXT,
    failed_login_count  INT          NOT NULL DEFAULT 0,
    locked_until        TIMESTAMPTZ,
    last_login_at       TIMESTAMPTZ,
    created_at          TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT chk_users_role   CHECK (role IN ('ADMIN','DOCTOR','PATIENT')),
    CONSTRAINT chk_users_status CHECK (status IN ('ACTIVE','PENDING_VERIFICATION','SUSPENDED','DEACTIVATED'))
);
CREATE UNIQUE INDEX uq_users_email_lower ON users (lower(email));
CREATE INDEX idx_users_role_status ON users (role, status);

-- ---------- PATIENT IDENTITY (admin-visible) ----------
CREATE TABLE patient_profiles (
    user_id        UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    full_name      VARCHAR(150) NOT NULL,
    date_of_birth  DATE,
    gender         VARCHAR(20),
    phone          VARCHAR(20),
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------- PATIENT MEDICAL INFO (admin must NEVER read) ----------
CREATE TABLE patient_health_info (
    user_id                  UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    blood_group              VARCHAR(5),
    allergies                TEXT,
    chronic_conditions       TEXT,
    emergency_contact_name   VARCHAR(150),
    emergency_contact_phone  VARCHAR(20),
    updated_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT chk_blood_group CHECK (blood_group IS NULL OR
        blood_group IN ('A+','A-','B+','B-','AB+','AB-','O+','O-'))
);

-- ---------- DOCTOR PROFILE ----------
CREATE TABLE doctor_profiles (
    user_id               UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    full_name             VARCHAR(150) NOT NULL,
    registration_number   VARCHAR(50)  NOT NULL,
    registration_council  VARCHAR(100) NOT NULL,
    specialization        VARCHAR(100),
    license_document_key  VARCHAR(500),
    verification_status   VARCHAR(10) NOT NULL DEFAULT 'PENDING',
    rejection_reason      VARCHAR(500),
    verified_by           UUID,
    verified_at           TIMESTAMPTZ,
    created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT chk_doctor_verification CHECK (verification_status IN ('PENDING','APPROVED','REJECTED')),
    CONSTRAINT uq_doctor_registration UNIQUE (registration_council, registration_number)
);

-- ---------- CATEGORIES ----------
CREATE TABLE categories (
    id          SMALLINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code        VARCHAR(30)  NOT NULL UNIQUE,
    label       VARCHAR(100) NOT NULL,
    keywords    JSONB        NOT NULL DEFAULT '[]'::jsonb,
    sort_order  INT          NOT NULL DEFAULT 0,
    active      BOOLEAN      NOT NULL DEFAULT TRUE
);

-- ---------- DOCUMENTS ----------
CREATE TABLE documents (
    id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    patient_id         UUID     NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    category_id        SMALLINT NOT NULL REFERENCES categories(id),
    title              VARCHAR(200) NOT NULL,
    visit_date         DATE,
    doctor_name        VARCHAR(150),
    hospital_name      VARCHAR(150),
    original_filename  VARCHAR(255) NOT NULL,
    mime_type          VARCHAR(100) NOT NULL,
    size_bytes         BIGINT NOT NULL,
    storage_key        VARCHAR(500) NOT NULL UNIQUE,
    wrapped_data_key   BYTEA NOT NULL,
    key_version        INT NOT NULL DEFAULT 1,
    checksum_sha256    CHAR(64) NOT NULL,
    extracted_text     TEXT,
    search_vector      TSVECTOR,
    ocr_confidence     NUMERIC(4,3),
    classified_by      VARCHAR(10),
    status             VARCHAR(15) NOT NULL DEFAULT 'PROCESSING',
    failure_reason     VARCHAR(255),
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT chk_doc_status CHECK (status IN ('PROCESSING','READY','FAILED')),
    CONSTRAINT chk_doc_classified_by CHECK (classified_by IS NULL OR classified_by IN ('RULES','ML','USER')),
    CONSTRAINT chk_doc_confidence CHECK (ocr_confidence IS NULL OR (ocr_confidence >= 0 AND ocr_confidence <= 1)),
    CONSTRAINT chk_doc_size CHECK (size_bytes > 0)
);
CREATE INDEX idx_documents_patient_category ON documents (patient_id, category_id);
CREATE INDEX idx_documents_patient_visit    ON documents (patient_id, visit_date DESC NULLS LAST);
CREATE INDEX idx_documents_search           ON documents USING GIN (search_vector);

CREATE FUNCTION documents_search_vector_update() RETURNS trigger AS $$
BEGIN
    NEW.search_vector :=
        setweight(to_tsvector('simple', coalesce(NEW.title, '')), 'A') ||
        setweight(to_tsvector('simple', coalesce(NEW.extracted_text, '')), 'B');
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_documents_search_vector
    BEFORE INSERT OR UPDATE OF title, extracted_text ON documents
    FOR EACH ROW EXECUTE FUNCTION documents_search_vector_update();

-- ---------- ACCESS GRANTS ----------
CREATE TABLE access_grants (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    patient_id              UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    doctor_id               UUID REFERENCES users(id) ON DELETE SET NULL,
    token_hash              CHAR(64) NOT NULL UNIQUE,
    status                  VARCHAR(10) NOT NULL DEFAULT 'PENDING',
    duration_minutes        INT NOT NULL,
    total_extended_minutes  INT NOT NULL DEFAULT 0,
    claim_expires_at        TIMESTAMPTZ NOT NULL,
    activated_at            TIMESTAMPTZ,
    expires_at              TIMESTAMPTZ,
    revoked_at              TIMESTAMPTZ,
    revoked_by              UUID,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT chk_grant_status CHECK (status IN ('PENDING','ACTIVE','EXPIRED','REVOKED')),
    CONSTRAINT chk_grant_duration CHECK (duration_minutes > 0),
    CONSTRAINT chk_grant_total_cap CHECK (duration_minutes + total_extended_minutes <= 10080),
    CONSTRAINT chk_grant_active_fields CHECK (
        status <> 'ACTIVE' OR (doctor_id IS NOT NULL AND activated_at IS NOT NULL AND expires_at IS NOT NULL)
    )
);
CREATE INDEX idx_grants_patient_status ON access_grants (patient_id, status);
CREATE INDEX idx_grants_doctor_status  ON access_grants (doctor_id, status);
CREATE INDEX idx_grants_expiry         ON access_grants (expires_at) WHERE status = 'ACTIVE';
CREATE INDEX idx_grants_pending_claim  ON access_grants (claim_expires_at) WHERE status = 'PENDING';

CREATE TABLE access_grant_categories (
    grant_id     UUID     NOT NULL REFERENCES access_grants(id) ON DELETE CASCADE,
    category_id  SMALLINT NOT NULL REFERENCES categories(id),
    PRIMARY KEY (grant_id, category_id)
);

-- ---------- AUTH SUPPORT ----------
CREATE TABLE refresh_tokens (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id      UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash   CHAR(64) NOT NULL UNIQUE,
    family_id    UUID NOT NULL,
    expires_at   TIMESTAMPTZ NOT NULL,
    revoked_at   TIMESTAMPTZ,
    replaced_by  UUID,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_refresh_user   ON refresh_tokens (user_id);
CREATE INDEX idx_refresh_family ON refresh_tokens (family_id);

-- ---------- NOTIFICATIONS ----------
CREATE TABLE notifications (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    type        VARCHAR(40) NOT NULL,
    payload     JSONB NOT NULL DEFAULT '{}'::jsonb,
    read_at     TIMESTAMPTZ,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_notifications_user_unread ON notifications (user_id, created_at DESC) WHERE read_at IS NULL;

-- ---------- AUDIT LOG (append-only, no FKs on purpose) ----------
CREATE TABLE audit_logs (
    id               BIGSERIAL PRIMARY KEY,
    actor_id         UUID,
    actor_role       VARCHAR(20),
    action           VARCHAR(50) NOT NULL,
    target_type      VARCHAR(30),
    target_id        UUID,
    subject_user_id  UUID,
    grant_id         UUID,
    ip               VARCHAR(45),
    user_agent       VARCHAR(255),
    metadata         JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_audit_subject ON audit_logs (subject_user_id, created_at DESC);
CREATE INDEX idx_audit_actor   ON audit_logs (actor_id, created_at DESC);
CREATE INDEX idx_audit_grant   ON audit_logs (grant_id);
CREATE INDEX idx_audit_action  ON audit_logs (action, created_at DESC);

CREATE FUNCTION prevent_audit_mutation() RETURNS trigger AS $$
BEGIN
    RAISE EXCEPTION 'audit_logs is append-only';
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_audit_no_update_delete
    BEFORE UPDATE OR DELETE ON audit_logs
    FOR EACH ROW EXECUTE FUNCTION prevent_audit_mutation();

-- ---------- ADMIN VIEW (the ONLY thing the admin module may read) ----------
CREATE VIEW v_admin_users AS
SELECT
    u.id,
    u.email,
    u.role,
    u.status,
    u.mfa_enabled,
    u.last_login_at,
    u.created_at,
    COALESCE(p.full_name, d.full_name) AS full_name,
    d.registration_number,
    d.registration_council,
    d.specialization,
    d.verification_status
FROM users u
LEFT JOIN patient_profiles p ON p.user_id = u.id
LEFT JOIN doctor_profiles  d ON d.user_id = u.id;

-- ---------- OPTIONAL: emergency card (post-MVP) ----------
CREATE TABLE emergency_cards (
    patient_id  UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    token_hash  CHAR(64) NOT NULL UNIQUE,
    enabled     BOOLEAN NOT NULL DEFAULT FALSE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
