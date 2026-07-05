-- =============================================================================
-- Miza Cloud — 012_sales_invoice_posted_at.sql
-- Adds posted_at for sales invoice post lifecycle
-- =============================================================================

BEGIN;

ALTER TABLE sales_invoices
    ADD COLUMN IF NOT EXISTS posted_at TIMESTAMPTZ;

COMMENT ON COLUMN sales_invoices.posted_at IS
    'Timestamp when invoice was posted (inventory + accounting applied)';

INSERT INTO schema_migrations (version, description, checksum)
VALUES (
    '012',
    'sales_invoice posted_at column',
    '012_sales_invoice_posted_at.sql'
)
ON CONFLICT (version) DO NOTHING;

COMMIT;
