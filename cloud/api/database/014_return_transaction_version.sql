-- =============================================================================
-- Miza Cloud — 014_return_transaction_version.sql
-- Adds transaction_version + posted_at for ADR-TX draft lifecycle on returns
-- =============================================================================

BEGIN;

ALTER TABLE sales_returns
    ADD COLUMN IF NOT EXISTS transaction_version BIGINT NOT NULL DEFAULT 0;

ALTER TABLE sales_returns
    ADD COLUMN IF NOT EXISTS posted_at TIMESTAMPTZ;

COMMENT ON COLUMN sales_returns.transaction_version IS
    'Document lifecycle version (draft updates / post / cancel) — separate from row_version';

ALTER TABLE purchase_returns
    ADD COLUMN IF NOT EXISTS transaction_version BIGINT NOT NULL DEFAULT 0;

ALTER TABLE purchase_returns
    ADD COLUMN IF NOT EXISTS posted_at TIMESTAMPTZ;

COMMENT ON COLUMN purchase_returns.transaction_version IS
    'Document lifecycle version (draft updates / post / cancel) — separate from row_version';

INSERT INTO schema_migrations (version, description, checksum)
VALUES (
    '014',
    'sales_return and purchase_return transaction_version columns',
    '014_return_transaction_version.sql'
)
ON CONFLICT (version) DO NOTHING;

COMMIT;
