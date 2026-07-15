-- Miza Cloud — 019_beta_platform.sql
-- Beta signup requests + activation vouchers (Phase 5)

BEGIN;

CREATE TABLE IF NOT EXISTS beta_signup_requests (
    id                  UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    store_name          TEXT            NOT NULL,
    email               CITEXT          NOT NULL,
    owner_name          TEXT            NOT NULL,
    phone               TEXT,
    message             TEXT,
    desired_plan_code   TEXT            NOT NULL DEFAULT 'business',
    voucher_code        TEXT,
    status              TEXT            NOT NULL DEFAULT 'pending',
    rejection_reason    TEXT,
    company_id          UUID,
    reviewed_at         TIMESTAMPTZ,
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS activation_vouchers (
    id                  UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    code                TEXT            NOT NULL,
    plan_code           TEXT            NOT NULL DEFAULT 'business',
    max_uses            INTEGER         NOT NULL DEFAULT 1,
    used_count          INTEGER         NOT NULL DEFAULT 0,
    expires_at          TIMESTAMPTZ,
    is_active           BOOLEAN         NOT NULL DEFAULT true,
    notes               TEXT,
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_activation_vouchers_code_lower
    ON activation_vouchers (lower(code));

CREATE INDEX IF NOT EXISTS idx_beta_signup_requests_status_created
    ON beta_signup_requests (status, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_beta_signup_requests_email
    ON beta_signup_requests (email);

ALTER TABLE beta_signup_requests
    DROP CONSTRAINT IF EXISTS chk_beta_signup_requests_status;

ALTER TABLE beta_signup_requests
    ADD CONSTRAINT chk_beta_signup_requests_status
        CHECK (status IN ('pending', 'approved', 'rejected'));

COMMIT;
