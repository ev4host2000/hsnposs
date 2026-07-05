-- =============================================================================
-- Miza Cloud — 012_purchase_invoice_transaction_version.sql
-- Adds transaction_version + posted_at for ADR-TX draft lifecycle on purchase_invoices
-- =============================================================================

BEGIN;

ALTER TABLE purchase_invoices
    ADD COLUMN IF NOT EXISTS transaction_version BIGINT NOT NULL DEFAULT 0;

ALTER TABLE purchase_invoices
    ADD COLUMN IF NOT EXISTS posted_at TIMESTAMPTZ;

COMMENT ON COLUMN purchase_invoices.transaction_version IS
    'Document lifecycle version (draft updates / post / cancel) — separate from row_version';

INSERT INTO schema_migrations (version, description, checksum)
VALUES (
    '012',
    'purchase_invoice transaction_version column',
    '012_purchase_invoice_transaction_version.sql'
)
ON CONFLICT (version) DO NOTHING;

COMMIT;
