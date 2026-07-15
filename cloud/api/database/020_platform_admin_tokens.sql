-- Miza Cloud — 020_platform_admin_tokens.sql
-- RAP-P1-02 — Server-side revocation for Ops (platform admin) JWT tokens

BEGIN;

CREATE TABLE IF NOT EXISTS platform_admin_tokens (
    id                  UUID            PRIMARY KEY,
    token_hash          TEXT            NOT NULL,
    scopes              TEXT[]          NOT NULL DEFAULT '{}',
    issued_at           TIMESTAMPTZ     NOT NULL DEFAULT now(),
    expires_at          TIMESTAMPTZ     NOT NULL,
    revoked_at          TIMESTAMPTZ
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_platform_admin_tokens_token_hash
    ON platform_admin_tokens (token_hash);

CREATE INDEX IF NOT EXISTS idx_platform_admin_tokens_active
    ON platform_admin_tokens (revoked_at, expires_at)
    WHERE revoked_at IS NULL;

COMMENT ON TABLE platform_admin_tokens IS 'Ops platform admin access tokens — hash + revocation (P1-02)';

INSERT INTO schema_migrations (version, description, checksum)
VALUES (
    '020',
    'platform_admin_tokens — Ops JWT server-side revocation',
    '020_platform_admin_tokens.sql'
)
ON CONFLICT (version) DO NOTHING;

COMMIT;
