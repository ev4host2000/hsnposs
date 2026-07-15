-- =============================================================================

-- Miza Cloud — install_all.sql

-- Applies migrations 001–017 in order (not 010_cleanup)

-- =============================================================================



\ir 001_initial_schema.sql

\ir 002_indexes.sql

\ir 003_constraints.sql

\ir 004_seed_data.sql

\ir 005_functions.sql

\ir 006_triggers.sql

\ir 007_views.sql

\ir 008_permissions.sql

\ir 009_migrations.sql

\ir 010_catalog_taxes_price_lists.sql

\ir 011_sales_invoice_transaction_version.sql

\ir 012_sales_invoice_posted_at.sql

\ir 013_purchase_invoice_transaction_version.sql

\ir 014_return_transaction_version.sql

\ir 015_payment_transaction_version.sql

\ir 016_inventory_adjustment_transaction_version.sql

\ir 017_opening_stock_transaction_version.sql

\ir 018_sync_void_operation.sql

\ir 019_beta_platform.sql

\ir 020_platform_admin_tokens.sql

\ir 021_ops_audit_events.sql

