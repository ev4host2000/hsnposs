-- =============================================================================
-- Miza Cloud — 011_sales_invoice_transaction_version.sql
-- Adds transaction_version for ADR-TX draft lifecycle on sales_invoices
-- =============================================================================

BEGIN;

ALTER TABLE sales_invoices
    ADD COLUMN IF NOT EXISTS transaction_version BIGINT NOT NULL DEFAULT 0;

COMMENT ON COLUMN sales_invoices.transaction_version IS
    'Document lifecycle version (draft updates / post / cancel) — separate from row_version';

ALTER TABLE sync_changelog
    DROP CONSTRAINT IF EXISTS chk_sync_changelog_operation;

ALTER TABLE sync_changelog
    ADD CONSTRAINT chk_sync_changelog_operation
        CHECK (operation IN ('create', 'update', 'delete', 'cancel', 'post', 'resolved'));

ALTER TABLE sync_queue
    DROP CONSTRAINT IF EXISTS chk_sync_queue_operation;

ALTER TABLE sync_queue
    ADD CONSTRAINT chk_sync_queue_operation
        CHECK (operation IN ('create', 'update', 'delete', 'cancel', 'post'));

INSERT INTO schema_migrations (version, description, checksum)
VALUES (
    '011',
    'sales_invoice transaction_version column',
    '011_sales_invoice_transaction_version.sql'
)
ON CONFLICT (version) DO NOTHING;

COMMIT;
