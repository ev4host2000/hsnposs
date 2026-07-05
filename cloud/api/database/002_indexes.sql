-- =============================================================================
-- Miza Cloud — 002_indexes.sql
-- Performance indexes, partial indexes, GIN — run after 001_initial_schema.sql
-- =============================================================================

BEGIN;

-- companies -------------------------------------------------------------------
CREATE INDEX idx_companies_status_updated
    ON companies (status, updated_at DESC);

-- branches --------------------------------------------------------------------
CREATE INDEX idx_branches_company_status
    ON branches (company_id, status);

CREATE UNIQUE INDEX uq_branches_company_code
    ON branches (company_id, code);

CREATE UNIQUE INDEX uq_branches_one_default_per_company
    ON branches (company_id)
    WHERE is_default = true;

-- organization_settings -------------------------------------------------------
CREATE INDEX idx_organization_settings_gin
    ON organization_settings USING GIN (settings_json);

-- branch_settings -------------------------------------------------------------
CREATE INDEX idx_branch_settings_company
    ON branch_settings (company_id);

CREATE INDEX idx_branch_settings_gin
    ON branch_settings USING GIN (settings_json);

-- device_settings -------------------------------------------------------------
CREATE INDEX idx_device_settings_company
    ON device_settings (company_id);

-- users -----------------------------------------------------------------------
CREATE UNIQUE INDEX uq_users_company_username
    ON users (company_id, lower(username))
    WHERE deleted_at IS NULL;

CREATE UNIQUE INDEX uq_users_company_email
    ON users (company_id, lower(email::text))
    WHERE email IS NOT NULL AND deleted_at IS NULL;

CREATE INDEX idx_users_company_role_status
    ON users (company_id, role, account_status)
    WHERE deleted_at IS NULL;

CREATE INDEX idx_users_company_updated
    ON users (company_id, updated_at DESC)
    WHERE deleted_at IS NULL;

-- user_branch_access ----------------------------------------------------------
CREATE INDEX idx_user_branch_access_company
    ON user_branch_access (company_id);

CREATE INDEX idx_user_branch_access_branch
    ON user_branch_access (branch_id);

-- devices ---------------------------------------------------------------------
CREATE UNIQUE INDEX uq_devices_installation_id
    ON devices (installation_id);

CREATE INDEX idx_devices_company_status_last_seen
    ON devices (company_id, status, last_seen_at DESC);

-- device_sessions -------------------------------------------------------------
CREATE INDEX idx_device_sessions_device_active
    ON device_sessions (device_id, revoked_at, expires_at);

CREATE INDEX idx_device_sessions_company_last_active
    ON device_sessions (company_id, last_active_at DESC);

-- api_tokens ------------------------------------------------------------------
CREATE UNIQUE INDEX uq_api_tokens_token_hash
    ON api_tokens (token_hash);

CREATE INDEX idx_api_tokens_subject
    ON api_tokens (subject_type, subject_id, revoked_at);

CREATE INDEX idx_api_tokens_company_expires
    ON api_tokens (company_id, expires_at)
    WHERE revoked_at IS NULL;

-- refresh_tokens --------------------------------------------------------------
CREATE UNIQUE INDEX uq_refresh_tokens_token_hash
    ON refresh_tokens (token_hash);

CREATE INDEX idx_refresh_tokens_session
    ON refresh_tokens (device_session_id, revoked_at);

-- password_reset_tokens -------------------------------------------------------
CREATE INDEX idx_password_reset_tokens_active
    ON password_reset_tokens (user_id, expires_at)
    WHERE used_at IS NULL;

-- email_verification_tokens ---------------------------------------------------
CREATE INDEX idx_email_verification_tokens_active
    ON email_verification_tokens (user_id, expires_at)
    WHERE verified_at IS NULL;

-- subscription_plans ----------------------------------------------------------
CREATE UNIQUE INDEX uq_subscription_plans_code
    ON subscription_plans (code);

-- company_subscriptions -------------------------------------------------------
CREATE INDEX idx_company_subscriptions_company_status
    ON company_subscriptions (company_id, status);

CREATE UNIQUE INDEX uq_company_subscriptions_one_active
    ON company_subscriptions (company_id)
    WHERE status IN ('trial', 'active');

-- licenses --------------------------------------------------------------------
CREATE INDEX idx_licenses_company_type_valid
    ON licenses (company_id, license_type, valid_until);

-- license_device_slots --------------------------------------------------------
CREATE INDEX idx_license_device_slots_device
    ON license_device_slots (device_id)
    WHERE revoked_at IS NULL;

CREATE INDEX idx_license_device_slots_company
    ON license_device_slots (company_id);

-- product_categories ----------------------------------------------------------
CREATE UNIQUE INDEX uq_product_categories_name
    ON product_categories (company_id, branch_id, lower(name))
    WHERE deleted_at IS NULL;

CREATE INDEX idx_product_categories_branch_updated
    ON product_categories (company_id, branch_id, updated_at DESC)
    WHERE deleted_at IS NULL;

-- product_units ---------------------------------------------------------------
CREATE UNIQUE INDEX uq_product_units_name
    ON product_units (company_id, branch_id, lower(name))
    WHERE deleted_at IS NULL;

CREATE INDEX idx_product_units_branch_updated
    ON product_units (company_id, branch_id, updated_at DESC)
    WHERE deleted_at IS NULL;

-- products --------------------------------------------------------------------
CREATE INDEX idx_products_barcode
    ON products (company_id, branch_id, barcode)
    WHERE barcode IS NOT NULL AND deleted_at IS NULL;

CREATE INDEX idx_products_branch_updated
    ON products (company_id, branch_id, updated_at DESC)
    WHERE deleted_at IS NULL;

CREATE INDEX idx_products_branch_name
    ON products (company_id, branch_id, name)
    WHERE deleted_at IS NULL;

CREATE INDEX idx_products_category
    ON products (category_id)
    WHERE deleted_at IS NULL;

-- product_sale_units ----------------------------------------------------------
CREATE UNIQUE INDEX uq_product_sale_units_name
    ON product_sale_units (company_id, branch_id, product_id, lower(unit_name));

CREATE INDEX idx_product_sale_units_product
    ON product_sale_units (product_id);

-- customers -------------------------------------------------------------------
CREATE UNIQUE INDEX uq_customers_number
    ON customers (company_id, branch_id, customer_number)
    WHERE customer_number IS NOT NULL AND deleted_at IS NULL;

CREATE INDEX idx_customers_branch_updated
    ON customers (company_id, branch_id, updated_at DESC)
    WHERE deleted_at IS NULL;

CREATE INDEX idx_customers_branch_name
    ON customers (company_id, branch_id, name)
    WHERE deleted_at IS NULL;

-- suppliers -------------------------------------------------------------------
CREATE UNIQUE INDEX uq_suppliers_number
    ON suppliers (company_id, branch_id, supplier_number)
    WHERE supplier_number IS NOT NULL AND deleted_at IS NULL;

CREATE INDEX idx_suppliers_branch_updated
    ON suppliers (company_id, branch_id, updated_at DESC)
    WHERE deleted_at IS NULL;

CREATE INDEX idx_suppliers_branch_name
    ON suppliers (company_id, branch_id, name)
    WHERE deleted_at IS NULL;

-- sales_invoices --------------------------------------------------------------
CREATE INDEX idx_sales_invoices_branch_date
    ON sales_invoices (company_id, branch_id, invoice_date DESC)
    WHERE deleted_at IS NULL;

CREATE UNIQUE INDEX uq_sales_invoices_number
    ON sales_invoices (company_id, branch_id, invoice_number)
    WHERE invoice_number IS NOT NULL AND deleted_at IS NULL;

CREATE INDEX idx_sales_invoices_customer_date
    ON sales_invoices (customer_id, invoice_date DESC)
    WHERE deleted_at IS NULL;

CREATE INDEX idx_sales_invoices_branch_updated
    ON sales_invoices (company_id, branch_id, updated_at DESC)
    WHERE deleted_at IS NULL;

-- sales_invoice_items ---------------------------------------------------------
CREATE INDEX idx_sales_invoice_items_invoice_product
    ON sales_invoice_items (invoice_id, product_id);

CREATE INDEX idx_sales_invoice_items_product
    ON sales_invoice_items (product_id);

-- purchase_invoices -----------------------------------------------------------
CREATE INDEX idx_purchase_invoices_branch_date
    ON purchase_invoices (company_id, branch_id, invoice_date DESC)
    WHERE deleted_at IS NULL;

CREATE UNIQUE INDEX uq_purchase_invoices_number
    ON purchase_invoices (company_id, branch_id, invoice_number)
    WHERE invoice_number IS NOT NULL AND deleted_at IS NULL;

CREATE INDEX idx_purchase_invoices_supplier_date
    ON purchase_invoices (supplier_id, invoice_date DESC)
    WHERE deleted_at IS NULL;

CREATE INDEX idx_purchase_invoices_branch_updated
    ON purchase_invoices (company_id, branch_id, updated_at DESC)
    WHERE deleted_at IS NULL;

-- purchase_invoice_items ------------------------------------------------------
CREATE INDEX idx_purchase_invoice_items_invoice_product
    ON purchase_invoice_items (invoice_id, product_id);

-- sales_returns ---------------------------------------------------------------
CREATE INDEX idx_sales_returns_original_invoice
    ON sales_returns (original_invoice_id);

CREATE INDEX idx_sales_returns_branch_date
    ON sales_returns (company_id, branch_id, return_date DESC)
    WHERE deleted_at IS NULL;

CREATE UNIQUE INDEX uq_sales_returns_number
    ON sales_returns (company_id, branch_id, return_number)
    WHERE return_number IS NOT NULL AND deleted_at IS NULL;

-- sales_return_items ----------------------------------------------------------
CREATE INDEX idx_sales_return_items_return
    ON sales_return_items (return_id);

-- purchase_returns ------------------------------------------------------------
CREATE INDEX idx_purchase_returns_original_invoice
    ON purchase_returns (original_invoice_id);

CREATE INDEX idx_purchase_returns_branch_date
    ON purchase_returns (company_id, branch_id, return_date DESC)
    WHERE deleted_at IS NULL;

CREATE UNIQUE INDEX uq_purchase_returns_number
    ON purchase_returns (company_id, branch_id, return_number)
    WHERE return_number IS NOT NULL AND deleted_at IS NULL;

-- purchase_return_items -------------------------------------------------------
CREATE INDEX idx_purchase_return_items_return
    ON purchase_return_items (return_id);

-- invoice_payment_splits ------------------------------------------------------
CREATE INDEX idx_invoice_payment_splits_invoice
    ON invoice_payment_splits (invoice_kind, invoice_id);

CREATE INDEX idx_invoice_payment_splits_branch
    ON invoice_payment_splits (company_id, branch_id);

-- stock_movements -------------------------------------------------------------
CREATE INDEX idx_stock_movements_product_date
    ON stock_movements (company_id, branch_id, product_id, movement_date DESC);

CREATE INDEX idx_stock_movements_reference
    ON stock_movements (reference_type, reference_id);

-- partner_ledger --------------------------------------------------------------
CREATE INDEX idx_partner_ledger_partner_date
    ON partner_ledger (company_id, branch_id, partner_kind, partner_id, entry_date DESC);

CREATE INDEX idx_partner_ledger_reference
    ON partner_ledger (reference_type, reference_id);

-- cash_transactions -----------------------------------------------------------
CREATE INDEX idx_cash_transactions_branch_date
    ON cash_transactions (company_id, branch_id, transaction_date DESC);

CREATE INDEX idx_cash_transactions_reference
    ON cash_transactions (reference_type, reference_id);

-- expenses --------------------------------------------------------------------
CREATE INDEX idx_expenses_branch_date
    ON expenses (company_id, branch_id, expense_date DESC)
    WHERE deleted_at IS NULL;

CREATE INDEX idx_expenses_branch_updated
    ON expenses (company_id, branch_id, updated_at DESC)
    WHERE deleted_at IS NULL;

-- cloud_versions --------------------------------------------------------------
CREATE UNIQUE INDEX uq_cloud_versions_scope
    ON cloud_versions (company_id, branch_id, entity_scope) NULLS NOT DISTINCT;

CREATE INDEX idx_cloud_versions_company
    ON cloud_versions (company_id, updated_at DESC);

-- sync_changelog --------------------------------------------------------------
CREATE UNIQUE INDEX uq_sync_changelog_company_sequence
    ON sync_changelog (company_id, sequence);

CREATE INDEX idx_sync_changelog_branch_occurred
    ON sync_changelog (company_id, branch_id, occurred_at DESC);

CREATE INDEX idx_sync_changelog_entity
    ON sync_changelog (company_id, entity_type, entity_id, sequence DESC);

-- sync_queue ------------------------------------------------------------------
CREATE INDEX idx_sync_queue_pending
    ON sync_queue (status, received_at)
    WHERE status = 'pending';

CREATE UNIQUE INDEX uq_sync_queue_idempotency
    ON sync_queue (device_id, idempotency_key);

CREATE INDEX idx_sync_queue_company_batch
    ON sync_queue (company_id, batch_id);

CREATE INDEX idx_sync_queue_device_status
    ON sync_queue (device_id, status, received_at DESC);

-- sync_conflicts --------------------------------------------------------------
CREATE INDEX idx_sync_conflicts_pending
    ON sync_conflicts (company_id, status, created_at DESC)
    WHERE status = 'pending';

CREATE INDEX idx_sync_conflicts_entity
    ON sync_conflicts (company_id, entity_type, entity_id);

CREATE INDEX idx_sync_conflicts_device
    ON sync_conflicts (device_id, status);

-- notifications ---------------------------------------------------------------
CREATE INDEX idx_notifications_company_published
    ON notifications (company_id, published_at DESC);

CREATE INDEX idx_notifications_branch
    ON notifications (branch_id, published_at DESC)
    WHERE branch_id IS NOT NULL;

CREATE INDEX idx_notifications_device
    ON notifications (device_id, published_at DESC)
    WHERE device_id IS NOT NULL;

-- notification_receipts -------------------------------------------------------
CREATE UNIQUE INDEX uq_notification_receipts_device
    ON notification_receipts (notification_id, device_id)
    WHERE device_id IS NOT NULL;

CREATE UNIQUE INDEX uq_notification_receipts_user
    ON notification_receipts (notification_id, user_id)
    WHERE user_id IS NOT NULL AND device_id IS NULL;

CREATE INDEX idx_notification_receipts_notification
    ON notification_receipts (notification_id);

-- audit_logs ------------------------------------------------------------------
CREATE INDEX idx_audit_logs_company_created
    ON audit_logs (company_id, created_at DESC);

CREATE INDEX idx_audit_logs_entity
    ON audit_logs (entity_type, entity_id, created_at DESC);

COMMIT;
