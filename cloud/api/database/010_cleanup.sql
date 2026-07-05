-- =============================================================================
-- Miza Cloud — 010_cleanup.sql
-- DESTRUCTIVE: drops all Miza Cloud objects — development / CI teardown only
--
--   psql -U postgres -d mizacloud -f 010_cleanup.sql
-- =============================================================================

BEGIN;

-- Views -----------------------------------------------------------------------
DROP VIEW IF EXISTS v_company_subscription_current CASCADE;
DROP VIEW IF EXISTS v_notifications_active CASCADE;
DROP VIEW IF EXISTS v_device_sessions_active CASCADE;
DROP VIEW IF EXISTS v_active_devices CASCADE;
DROP VIEW IF EXISTS v_sync_changelog_recent CASCADE;
DROP VIEW IF EXISTS v_pending_sync_conflicts CASCADE;
DROP VIEW IF EXISTS v_pending_sync_queue CASCADE;
DROP VIEW IF EXISTS v_active_users CASCADE;
DROP VIEW IF EXISTS v_active_suppliers CASCADE;
DROP VIEW IF EXISTS v_active_customers CASCADE;
DROP VIEW IF EXISTS v_active_products CASCADE;
DROP VIEW IF EXISTS v_active_branches CASCADE;
DROP VIEW IF EXISTS v_active_companies CASCADE;

-- Functions -------------------------------------------------------------------
DROP FUNCTION IF EXISTS miza_bump_cloud_version(UUID, UUID, TEXT) CASCADE;
DROP FUNCTION IF EXISTS miza_reserve_sync_sequences(UUID, INTEGER) CASCADE;
DROP FUNCTION IF EXISTS miza_next_sync_sequence(UUID) CASCADE;
DROP FUNCTION IF EXISTS miza_soft_delete(regclass, UUID, UUID) CASCADE;
DROP FUNCTION IF EXISTS miza_bump_row_version() CASCADE;
DROP FUNCTION IF EXISTS miza_touch_updated_at() CASCADE;

-- Tables (dependency-safe order) ------------------------------------------------
DROP TABLE IF EXISTS schema_migrations CASCADE;
DROP TABLE IF EXISTS sync_sequence_counters CASCADE;
DROP TABLE IF EXISTS notification_receipts CASCADE;
DROP TABLE IF EXISTS notifications CASCADE;
DROP TABLE IF EXISTS audit_logs CASCADE;
DROP TABLE IF EXISTS sync_conflicts CASCADE;
DROP TABLE IF EXISTS sync_queue CASCADE;
DROP TABLE IF EXISTS sync_changelog CASCADE;
DROP TABLE IF EXISTS cloud_versions CASCADE;
DROP TABLE IF EXISTS expenses CASCADE;
DROP TABLE IF EXISTS cash_transactions CASCADE;
DROP TABLE IF EXISTS partner_ledger CASCADE;
DROP TABLE IF EXISTS stock_movements CASCADE;
DROP TABLE IF EXISTS invoice_payment_splits CASCADE;
DROP TABLE IF EXISTS purchase_return_items CASCADE;
DROP TABLE IF EXISTS purchase_returns CASCADE;
DROP TABLE IF EXISTS sales_return_items CASCADE;
DROP TABLE IF EXISTS sales_returns CASCADE;
DROP TABLE IF EXISTS purchase_invoice_items CASCADE;
DROP TABLE IF EXISTS purchase_invoices CASCADE;
DROP TABLE IF EXISTS sales_invoice_items CASCADE;
DROP TABLE IF EXISTS sales_invoices CASCADE;
DROP TABLE IF EXISTS suppliers CASCADE;
DROP TABLE IF EXISTS customers CASCADE;
DROP TABLE IF EXISTS product_sale_units CASCADE;
DROP TABLE IF EXISTS products CASCADE;
DROP TABLE IF EXISTS product_units CASCADE;
DROP TABLE IF EXISTS product_categories CASCADE;
DROP TABLE IF EXISTS license_device_slots CASCADE;
DROP TABLE IF EXISTS licenses CASCADE;
DROP TABLE IF EXISTS company_subscriptions CASCADE;
DROP TABLE IF EXISTS subscription_plans CASCADE;
DROP TABLE IF EXISTS email_verification_tokens CASCADE;
DROP TABLE IF EXISTS password_reset_tokens CASCADE;
DROP TABLE IF EXISTS refresh_tokens CASCADE;
DROP TABLE IF EXISTS api_tokens CASCADE;
DROP TABLE IF EXISTS device_sessions CASCADE;
DROP TABLE IF EXISTS device_settings CASCADE;
DROP TABLE IF EXISTS devices CASCADE;
DROP TABLE IF EXISTS user_branch_access CASCADE;
DROP TABLE IF EXISTS users CASCADE;
DROP TABLE IF EXISTS branch_settings CASCADE;
DROP TABLE IF EXISTS organization_settings CASCADE;
DROP TABLE IF EXISTS branches CASCADE;
DROP TABLE IF EXISTS companies CASCADE;

-- Roles (optional — uncomment in dev only)
-- DROP ROLE IF EXISTS mizacloud;
-- DROP ROLE IF EXISTS mizacloud_migrate;

-- Extensions (optional — shared DB may need citext/pgcrypto)
-- DROP EXTENSION IF EXISTS citext;
-- DROP EXTENSION IF EXISTS pgcrypto;

COMMIT;
