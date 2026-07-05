-- =============================================================================
-- Miza Cloud — install_all.sql
-- Applies migrations 001–009 in order (not 010 cleanup)
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
