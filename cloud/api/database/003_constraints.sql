-- =============================================================================
-- Miza Cloud — 003_constraints.sql
-- Foreign keys, CHECK constraints, NOT NULL business rules
-- Run after 001_initial_schema.sql and 002_indexes.sql
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- Foreign Keys — Tenancy & Settings
-- ---------------------------------------------------------------------------

ALTER TABLE branches
    ADD CONSTRAINT fk_branches_company
        FOREIGN KEY (company_id) REFERENCES companies (id) ON DELETE RESTRICT;

ALTER TABLE organization_settings
    ADD CONSTRAINT fk_organization_settings_company
        FOREIGN KEY (company_id) REFERENCES companies (id) ON DELETE CASCADE;

ALTER TABLE branch_settings
    ADD CONSTRAINT fk_branch_settings_branch
        FOREIGN KEY (branch_id) REFERENCES branches (id) ON DELETE CASCADE;

ALTER TABLE branch_settings
    ADD CONSTRAINT fk_branch_settings_company
        FOREIGN KEY (company_id) REFERENCES companies (id) ON DELETE CASCADE;

ALTER TABLE device_settings
    ADD CONSTRAINT fk_device_settings_device
        FOREIGN KEY (device_id) REFERENCES devices (id) ON DELETE CASCADE;

ALTER TABLE device_settings
    ADD CONSTRAINT fk_device_settings_company
        FOREIGN KEY (company_id) REFERENCES companies (id) ON DELETE CASCADE;

-- ---------------------------------------------------------------------------
-- Foreign Keys — Identity & Access
-- ---------------------------------------------------------------------------

ALTER TABLE users
    ADD CONSTRAINT fk_users_company
        FOREIGN KEY (company_id) REFERENCES companies (id) ON DELETE RESTRICT;

ALTER TABLE users
    ADD CONSTRAINT fk_users_default_branch
        FOREIGN KEY (default_branch_id) REFERENCES branches (id) ON DELETE RESTRICT;

ALTER TABLE organization_settings
    ADD CONSTRAINT fk_organization_settings_updated_by
        FOREIGN KEY (updated_by_user_id) REFERENCES users (id) ON DELETE SET NULL;

-- ---------------------------------------------------------------------------
-- Foreign Keys — Identity & Access (continued)
-- ---------------------------------------------------------------------------

ALTER TABLE user_branch_access
    ADD CONSTRAINT fk_user_branch_access_user
        FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE;

ALTER TABLE user_branch_access
    ADD CONSTRAINT fk_user_branch_access_branch
        FOREIGN KEY (branch_id) REFERENCES branches (id) ON DELETE CASCADE;

ALTER TABLE user_branch_access
    ADD CONSTRAINT fk_user_branch_access_company
        FOREIGN KEY (company_id) REFERENCES companies (id) ON DELETE CASCADE;

ALTER TABLE devices
    ADD CONSTRAINT fk_devices_company
        FOREIGN KEY (company_id) REFERENCES companies (id) ON DELETE RESTRICT;

ALTER TABLE devices
    ADD CONSTRAINT fk_devices_registered_by
        FOREIGN KEY (registered_by_user_id) REFERENCES users (id) ON DELETE SET NULL;

ALTER TABLE device_sessions
    ADD CONSTRAINT fk_device_sessions_device
        FOREIGN KEY (device_id) REFERENCES devices (id) ON DELETE CASCADE;

ALTER TABLE device_sessions
    ADD CONSTRAINT fk_device_sessions_company
        FOREIGN KEY (company_id) REFERENCES companies (id) ON DELETE CASCADE;

ALTER TABLE device_sessions
    ADD CONSTRAINT fk_device_sessions_branch
        FOREIGN KEY (branch_id) REFERENCES branches (id) ON DELETE RESTRICT;

ALTER TABLE device_sessions
    ADD CONSTRAINT fk_device_sessions_user
        FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE SET NULL;

ALTER TABLE api_tokens
    ADD CONSTRAINT fk_api_tokens_company
        FOREIGN KEY (company_id) REFERENCES companies (id) ON DELETE CASCADE;

ALTER TABLE api_tokens
    ADD CONSTRAINT fk_api_tokens_session
        FOREIGN KEY (device_session_id) REFERENCES device_sessions (id) ON DELETE CASCADE;

ALTER TABLE refresh_tokens
    ADD CONSTRAINT fk_refresh_tokens_session
        FOREIGN KEY (device_session_id) REFERENCES device_sessions (id) ON DELETE CASCADE;

ALTER TABLE refresh_tokens
    ADD CONSTRAINT fk_refresh_tokens_company
        FOREIGN KEY (company_id) REFERENCES companies (id) ON DELETE CASCADE;

ALTER TABLE refresh_tokens
    ADD CONSTRAINT fk_refresh_tokens_user
        FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE SET NULL;

ALTER TABLE refresh_tokens
    ADD CONSTRAINT fk_refresh_tokens_replaced_by
        FOREIGN KEY (replaced_by_id) REFERENCES refresh_tokens (id) ON DELETE SET NULL;

ALTER TABLE password_reset_tokens
    ADD CONSTRAINT fk_password_reset_tokens_user
        FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE;

ALTER TABLE password_reset_tokens
    ADD CONSTRAINT fk_password_reset_tokens_company
        FOREIGN KEY (company_id) REFERENCES companies (id) ON DELETE CASCADE;

ALTER TABLE email_verification_tokens
    ADD CONSTRAINT fk_email_verification_tokens_user
        FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE;

ALTER TABLE email_verification_tokens
    ADD CONSTRAINT fk_email_verification_tokens_company
        FOREIGN KEY (company_id) REFERENCES companies (id) ON DELETE CASCADE;

-- ---------------------------------------------------------------------------
-- Foreign Keys — Commercial
-- ---------------------------------------------------------------------------

ALTER TABLE company_subscriptions
    ADD CONSTRAINT fk_company_subscriptions_company
        FOREIGN KEY (company_id) REFERENCES companies (id) ON DELETE CASCADE;

ALTER TABLE company_subscriptions
    ADD CONSTRAINT fk_company_subscriptions_plan
        FOREIGN KEY (plan_id) REFERENCES subscription_plans (id) ON DELETE RESTRICT;

ALTER TABLE licenses
    ADD CONSTRAINT fk_licenses_company
        FOREIGN KEY (company_id) REFERENCES companies (id) ON DELETE CASCADE;

ALTER TABLE licenses
    ADD CONSTRAINT fk_licenses_subscription
        FOREIGN KEY (subscription_id) REFERENCES company_subscriptions (id) ON DELETE CASCADE;

ALTER TABLE license_device_slots
    ADD CONSTRAINT fk_license_device_slots_license
        FOREIGN KEY (license_id) REFERENCES licenses (id) ON DELETE CASCADE;

ALTER TABLE license_device_slots
    ADD CONSTRAINT fk_license_device_slots_device
        FOREIGN KEY (device_id) REFERENCES devices (id) ON DELETE CASCADE;

ALTER TABLE license_device_slots
    ADD CONSTRAINT fk_license_device_slots_company
        FOREIGN KEY (company_id) REFERENCES companies (id) ON DELETE CASCADE;

-- ---------------------------------------------------------------------------
-- Foreign Keys — Master Data
-- ---------------------------------------------------------------------------

ALTER TABLE product_categories
    ADD CONSTRAINT fk_product_categories_company
        FOREIGN KEY (company_id) REFERENCES companies (id) ON DELETE CASCADE;

ALTER TABLE product_categories
    ADD CONSTRAINT fk_product_categories_branch
        FOREIGN KEY (branch_id) REFERENCES branches (id) ON DELETE CASCADE;

ALTER TABLE product_units
    ADD CONSTRAINT fk_product_units_company
        FOREIGN KEY (company_id) REFERENCES companies (id) ON DELETE CASCADE;

ALTER TABLE product_units
    ADD CONSTRAINT fk_product_units_branch
        FOREIGN KEY (branch_id) REFERENCES branches (id) ON DELETE CASCADE;

ALTER TABLE products
    ADD CONSTRAINT fk_products_company
        FOREIGN KEY (company_id) REFERENCES companies (id) ON DELETE CASCADE;

ALTER TABLE products
    ADD CONSTRAINT fk_products_branch
        FOREIGN KEY (branch_id) REFERENCES branches (id) ON DELETE CASCADE;

ALTER TABLE products
    ADD CONSTRAINT fk_products_category
        FOREIGN KEY (category_id) REFERENCES product_categories (id) ON DELETE SET NULL;

ALTER TABLE products
    ADD CONSTRAINT fk_products_origin_device
        FOREIGN KEY (origin_device_id) REFERENCES devices (id) ON DELETE SET NULL;

ALTER TABLE product_sale_units
    ADD CONSTRAINT fk_product_sale_units_company
        FOREIGN KEY (company_id) REFERENCES companies (id) ON DELETE CASCADE;

ALTER TABLE product_sale_units
    ADD CONSTRAINT fk_product_sale_units_branch
        FOREIGN KEY (branch_id) REFERENCES branches (id) ON DELETE CASCADE;

ALTER TABLE product_sale_units
    ADD CONSTRAINT fk_product_sale_units_product
        FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE CASCADE;

ALTER TABLE customers
    ADD CONSTRAINT fk_customers_company
        FOREIGN KEY (company_id) REFERENCES companies (id) ON DELETE CASCADE;

ALTER TABLE customers
    ADD CONSTRAINT fk_customers_branch
        FOREIGN KEY (branch_id) REFERENCES branches (id) ON DELETE CASCADE;

ALTER TABLE customers
    ADD CONSTRAINT fk_customers_origin_device
        FOREIGN KEY (origin_device_id) REFERENCES devices (id) ON DELETE SET NULL;

ALTER TABLE suppliers
    ADD CONSTRAINT fk_suppliers_company
        FOREIGN KEY (company_id) REFERENCES companies (id) ON DELETE CASCADE;

ALTER TABLE suppliers
    ADD CONSTRAINT fk_suppliers_branch
        FOREIGN KEY (branch_id) REFERENCES branches (id) ON DELETE CASCADE;

ALTER TABLE suppliers
    ADD CONSTRAINT fk_suppliers_origin_device
        FOREIGN KEY (origin_device_id) REFERENCES devices (id) ON DELETE SET NULL;

-- ---------------------------------------------------------------------------
-- Foreign Keys — Transactions
-- ---------------------------------------------------------------------------

ALTER TABLE sales_invoices
    ADD CONSTRAINT fk_sales_invoices_company
        FOREIGN KEY (company_id) REFERENCES companies (id) ON DELETE CASCADE;

ALTER TABLE sales_invoices
    ADD CONSTRAINT fk_sales_invoices_branch
        FOREIGN KEY (branch_id) REFERENCES branches (id) ON DELETE CASCADE;

ALTER TABLE sales_invoices
    ADD CONSTRAINT fk_sales_invoices_customer
        FOREIGN KEY (customer_id) REFERENCES customers (id) ON DELETE SET NULL;

ALTER TABLE sales_invoices
    ADD CONSTRAINT fk_sales_invoices_created_by
        FOREIGN KEY (created_by_user_id) REFERENCES users (id) ON DELETE RESTRICT;

ALTER TABLE sales_invoices
    ADD CONSTRAINT fk_sales_invoices_origin_device
        FOREIGN KEY (origin_device_id) REFERENCES devices (id) ON DELETE RESTRICT;

ALTER TABLE sales_invoice_items
    ADD CONSTRAINT fk_sales_invoice_items_invoice
        FOREIGN KEY (invoice_id) REFERENCES sales_invoices (id) ON DELETE CASCADE;

ALTER TABLE sales_invoice_items
    ADD CONSTRAINT fk_sales_invoice_items_company
        FOREIGN KEY (company_id) REFERENCES companies (id) ON DELETE CASCADE;

ALTER TABLE sales_invoice_items
    ADD CONSTRAINT fk_sales_invoice_items_branch
        FOREIGN KEY (branch_id) REFERENCES branches (id) ON DELETE CASCADE;

ALTER TABLE sales_invoice_items
    ADD CONSTRAINT fk_sales_invoice_items_product
        FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE RESTRICT;

ALTER TABLE purchase_invoices
    ADD CONSTRAINT fk_purchase_invoices_company
        FOREIGN KEY (company_id) REFERENCES companies (id) ON DELETE CASCADE;

ALTER TABLE purchase_invoices
    ADD CONSTRAINT fk_purchase_invoices_branch
        FOREIGN KEY (branch_id) REFERENCES branches (id) ON DELETE CASCADE;

ALTER TABLE purchase_invoices
    ADD CONSTRAINT fk_purchase_invoices_supplier
        FOREIGN KEY (supplier_id) REFERENCES suppliers (id) ON DELETE SET NULL;

ALTER TABLE purchase_invoices
    ADD CONSTRAINT fk_purchase_invoices_created_by
        FOREIGN KEY (created_by_user_id) REFERENCES users (id) ON DELETE RESTRICT;

ALTER TABLE purchase_invoices
    ADD CONSTRAINT fk_purchase_invoices_origin_device
        FOREIGN KEY (origin_device_id) REFERENCES devices (id) ON DELETE RESTRICT;

ALTER TABLE purchase_invoice_items
    ADD CONSTRAINT fk_purchase_invoice_items_invoice
        FOREIGN KEY (invoice_id) REFERENCES purchase_invoices (id) ON DELETE CASCADE;

ALTER TABLE purchase_invoice_items
    ADD CONSTRAINT fk_purchase_invoice_items_company
        FOREIGN KEY (company_id) REFERENCES companies (id) ON DELETE CASCADE;

ALTER TABLE purchase_invoice_items
    ADD CONSTRAINT fk_purchase_invoice_items_branch
        FOREIGN KEY (branch_id) REFERENCES branches (id) ON DELETE CASCADE;

ALTER TABLE purchase_invoice_items
    ADD CONSTRAINT fk_purchase_invoice_items_product
        FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE RESTRICT;

ALTER TABLE sales_returns
    ADD CONSTRAINT fk_sales_returns_company
        FOREIGN KEY (company_id) REFERENCES companies (id) ON DELETE CASCADE;

ALTER TABLE sales_returns
    ADD CONSTRAINT fk_sales_returns_branch
        FOREIGN KEY (branch_id) REFERENCES branches (id) ON DELETE CASCADE;

ALTER TABLE sales_returns
    ADD CONSTRAINT fk_sales_returns_original_invoice
        FOREIGN KEY (original_invoice_id) REFERENCES sales_invoices (id) ON DELETE RESTRICT;

ALTER TABLE sales_returns
    ADD CONSTRAINT fk_sales_returns_customer
        FOREIGN KEY (customer_id) REFERENCES customers (id) ON DELETE SET NULL;

ALTER TABLE sales_returns
    ADD CONSTRAINT fk_sales_returns_created_by
        FOREIGN KEY (created_by_user_id) REFERENCES users (id) ON DELETE RESTRICT;

ALTER TABLE sales_returns
    ADD CONSTRAINT fk_sales_returns_origin_device
        FOREIGN KEY (origin_device_id) REFERENCES devices (id) ON DELETE RESTRICT;

ALTER TABLE sales_return_items
    ADD CONSTRAINT fk_sales_return_items_return
        FOREIGN KEY (return_id) REFERENCES sales_returns (id) ON DELETE CASCADE;

ALTER TABLE sales_return_items
    ADD CONSTRAINT fk_sales_return_items_company
        FOREIGN KEY (company_id) REFERENCES companies (id) ON DELETE CASCADE;

ALTER TABLE sales_return_items
    ADD CONSTRAINT fk_sales_return_items_branch
        FOREIGN KEY (branch_id) REFERENCES branches (id) ON DELETE CASCADE;

ALTER TABLE sales_return_items
    ADD CONSTRAINT fk_sales_return_items_product
        FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE RESTRICT;

ALTER TABLE sales_return_items
    ADD CONSTRAINT fk_sales_return_items_original_line
        FOREIGN KEY (original_invoice_item_id) REFERENCES sales_invoice_items (id) ON DELETE SET NULL;

ALTER TABLE purchase_returns
    ADD CONSTRAINT fk_purchase_returns_company
        FOREIGN KEY (company_id) REFERENCES companies (id) ON DELETE CASCADE;

ALTER TABLE purchase_returns
    ADD CONSTRAINT fk_purchase_returns_branch
        FOREIGN KEY (branch_id) REFERENCES branches (id) ON DELETE CASCADE;

ALTER TABLE purchase_returns
    ADD CONSTRAINT fk_purchase_returns_original_invoice
        FOREIGN KEY (original_invoice_id) REFERENCES purchase_invoices (id) ON DELETE RESTRICT;

ALTER TABLE purchase_returns
    ADD CONSTRAINT fk_purchase_returns_supplier
        FOREIGN KEY (supplier_id) REFERENCES suppliers (id) ON DELETE SET NULL;

ALTER TABLE purchase_returns
    ADD CONSTRAINT fk_purchase_returns_created_by
        FOREIGN KEY (created_by_user_id) REFERENCES users (id) ON DELETE RESTRICT;

ALTER TABLE purchase_returns
    ADD CONSTRAINT fk_purchase_returns_origin_device
        FOREIGN KEY (origin_device_id) REFERENCES devices (id) ON DELETE RESTRICT;

ALTER TABLE purchase_return_items
    ADD CONSTRAINT fk_purchase_return_items_return
        FOREIGN KEY (return_id) REFERENCES purchase_returns (id) ON DELETE CASCADE;

ALTER TABLE purchase_return_items
    ADD CONSTRAINT fk_purchase_return_items_company
        FOREIGN KEY (company_id) REFERENCES companies (id) ON DELETE CASCADE;

ALTER TABLE purchase_return_items
    ADD CONSTRAINT fk_purchase_return_items_branch
        FOREIGN KEY (branch_id) REFERENCES branches (id) ON DELETE CASCADE;

ALTER TABLE purchase_return_items
    ADD CONSTRAINT fk_purchase_return_items_product
        FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE RESTRICT;

ALTER TABLE purchase_return_items
    ADD CONSTRAINT fk_purchase_return_items_original_line
        FOREIGN KEY (original_invoice_item_id) REFERENCES purchase_invoice_items (id) ON DELETE SET NULL;

ALTER TABLE invoice_payment_splits
    ADD CONSTRAINT fk_invoice_payment_splits_company
        FOREIGN KEY (company_id) REFERENCES companies (id) ON DELETE CASCADE;

ALTER TABLE invoice_payment_splits
    ADD CONSTRAINT fk_invoice_payment_splits_branch
        FOREIGN KEY (branch_id) REFERENCES branches (id) ON DELETE CASCADE;

ALTER TABLE stock_movements
    ADD CONSTRAINT fk_stock_movements_company
        FOREIGN KEY (company_id) REFERENCES companies (id) ON DELETE CASCADE;

ALTER TABLE stock_movements
    ADD CONSTRAINT fk_stock_movements_branch
        FOREIGN KEY (branch_id) REFERENCES branches (id) ON DELETE CASCADE;

ALTER TABLE stock_movements
    ADD CONSTRAINT fk_stock_movements_product
        FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE RESTRICT;

ALTER TABLE stock_movements
    ADD CONSTRAINT fk_stock_movements_created_by
        FOREIGN KEY (created_by_user_id) REFERENCES users (id) ON DELETE RESTRICT;

ALTER TABLE stock_movements
    ADD CONSTRAINT fk_stock_movements_origin_device
        FOREIGN KEY (origin_device_id) REFERENCES devices (id) ON DELETE SET NULL;

ALTER TABLE partner_ledger
    ADD CONSTRAINT fk_partner_ledger_company
        FOREIGN KEY (company_id) REFERENCES companies (id) ON DELETE CASCADE;

ALTER TABLE partner_ledger
    ADD CONSTRAINT fk_partner_ledger_branch
        FOREIGN KEY (branch_id) REFERENCES branches (id) ON DELETE CASCADE;

ALTER TABLE partner_ledger
    ADD CONSTRAINT fk_partner_ledger_created_by
        FOREIGN KEY (created_by_user_id) REFERENCES users (id) ON DELETE RESTRICT;

ALTER TABLE cash_transactions
    ADD CONSTRAINT fk_cash_transactions_company
        FOREIGN KEY (company_id) REFERENCES companies (id) ON DELETE CASCADE;

ALTER TABLE cash_transactions
    ADD CONSTRAINT fk_cash_transactions_branch
        FOREIGN KEY (branch_id) REFERENCES branches (id) ON DELETE CASCADE;

ALTER TABLE cash_transactions
    ADD CONSTRAINT fk_cash_transactions_created_by
        FOREIGN KEY (created_by_user_id) REFERENCES users (id) ON DELETE RESTRICT;

ALTER TABLE expenses
    ADD CONSTRAINT fk_expenses_company
        FOREIGN KEY (company_id) REFERENCES companies (id) ON DELETE CASCADE;

ALTER TABLE expenses
    ADD CONSTRAINT fk_expenses_branch
        FOREIGN KEY (branch_id) REFERENCES branches (id) ON DELETE CASCADE;

ALTER TABLE expenses
    ADD CONSTRAINT fk_expenses_created_by
        FOREIGN KEY (created_by_user_id) REFERENCES users (id) ON DELETE RESTRICT;

ALTER TABLE expenses
    ADD CONSTRAINT fk_expenses_origin_device
        FOREIGN KEY (origin_device_id) REFERENCES devices (id) ON DELETE SET NULL;

-- ---------------------------------------------------------------------------
-- Foreign Keys — Sync
-- ---------------------------------------------------------------------------

ALTER TABLE cloud_versions
    ADD CONSTRAINT fk_cloud_versions_company
        FOREIGN KEY (company_id) REFERENCES companies (id) ON DELETE CASCADE;

ALTER TABLE cloud_versions
    ADD CONSTRAINT fk_cloud_versions_branch
        FOREIGN KEY (branch_id) REFERENCES branches (id) ON DELETE CASCADE;

ALTER TABLE sync_changelog
    ADD CONSTRAINT fk_sync_changelog_company
        FOREIGN KEY (company_id) REFERENCES companies (id) ON DELETE CASCADE;

ALTER TABLE sync_changelog
    ADD CONSTRAINT fk_sync_changelog_branch
        FOREIGN KEY (branch_id) REFERENCES branches (id) ON DELETE CASCADE;

ALTER TABLE sync_changelog
    ADD CONSTRAINT fk_sync_changelog_origin_device
        FOREIGN KEY (origin_device_id) REFERENCES devices (id) ON DELETE SET NULL;

ALTER TABLE sync_changelog
    ADD CONSTRAINT fk_sync_changelog_origin_user
        FOREIGN KEY (origin_user_id) REFERENCES users (id) ON DELETE SET NULL;

ALTER TABLE sync_queue
    ADD CONSTRAINT fk_sync_queue_company
        FOREIGN KEY (company_id) REFERENCES companies (id) ON DELETE CASCADE;

ALTER TABLE sync_queue
    ADD CONSTRAINT fk_sync_queue_branch
        FOREIGN KEY (branch_id) REFERENCES branches (id) ON DELETE CASCADE;

ALTER TABLE sync_queue
    ADD CONSTRAINT fk_sync_queue_device
        FOREIGN KEY (device_id) REFERENCES devices (id) ON DELETE CASCADE;

ALTER TABLE sync_conflicts
    ADD CONSTRAINT fk_sync_conflicts_company
        FOREIGN KEY (company_id) REFERENCES companies (id) ON DELETE CASCADE;

ALTER TABLE sync_conflicts
    ADD CONSTRAINT fk_sync_conflicts_branch
        FOREIGN KEY (branch_id) REFERENCES branches (id) ON DELETE CASCADE;

ALTER TABLE sync_conflicts
    ADD CONSTRAINT fk_sync_conflicts_device
        FOREIGN KEY (device_id) REFERENCES devices (id) ON DELETE CASCADE;

ALTER TABLE sync_conflicts
    ADD CONSTRAINT fk_sync_conflicts_resolved_by
        FOREIGN KEY (resolved_by_user_id) REFERENCES users (id) ON DELETE SET NULL;

ALTER TABLE sync_conflicts
    ADD CONSTRAINT fk_sync_conflicts_sync_queue
        FOREIGN KEY (sync_queue_id) REFERENCES sync_queue (id) ON DELETE SET NULL;

-- ---------------------------------------------------------------------------
-- Foreign Keys — Notifications & Audit
-- ---------------------------------------------------------------------------

ALTER TABLE notifications
    ADD CONSTRAINT fk_notifications_company
        FOREIGN KEY (company_id) REFERENCES companies (id) ON DELETE CASCADE;

ALTER TABLE notifications
    ADD CONSTRAINT fk_notifications_branch
        FOREIGN KEY (branch_id) REFERENCES branches (id) ON DELETE CASCADE;

ALTER TABLE notifications
    ADD CONSTRAINT fk_notifications_device
        FOREIGN KEY (device_id) REFERENCES devices (id) ON DELETE CASCADE;

ALTER TABLE notifications
    ADD CONSTRAINT fk_notifications_user
        FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE;

ALTER TABLE notification_receipts
    ADD CONSTRAINT fk_notification_receipts_notification
        FOREIGN KEY (notification_id) REFERENCES notifications (id) ON DELETE CASCADE;

ALTER TABLE notification_receipts
    ADD CONSTRAINT fk_notification_receipts_device
        FOREIGN KEY (device_id) REFERENCES devices (id) ON DELETE CASCADE;

ALTER TABLE notification_receipts
    ADD CONSTRAINT fk_notification_receipts_user
        FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE;

ALTER TABLE audit_logs
    ADD CONSTRAINT fk_audit_logs_company
        FOREIGN KEY (company_id) REFERENCES companies (id) ON DELETE CASCADE;

ALTER TABLE audit_logs
    ADD CONSTRAINT fk_audit_logs_branch
        FOREIGN KEY (branch_id) REFERENCES branches (id) ON DELETE SET NULL;

ALTER TABLE audit_logs
    ADD CONSTRAINT fk_audit_logs_actor_user
        FOREIGN KEY (actor_user_id) REFERENCES users (id) ON DELETE SET NULL;

ALTER TABLE audit_logs
    ADD CONSTRAINT fk_audit_logs_actor_device
        FOREIGN KEY (actor_device_id) REFERENCES devices (id) ON DELETE SET NULL;

-- ---------------------------------------------------------------------------
-- CHECK constraints — enumerated values & business rules
-- ---------------------------------------------------------------------------

ALTER TABLE companies
    ADD CONSTRAINT chk_companies_status
        CHECK (status IN ('active', 'suspended', 'closed'));

ALTER TABLE branches
    ADD CONSTRAINT chk_branches_status
        CHECK (status IN ('active', 'inactive'));

ALTER TABLE users
    ADD CONSTRAINT chk_users_role
        CHECK (role IN ('owner', 'accountant', 'cashier', 'distributor', 'admin'));

ALTER TABLE users
    ADD CONSTRAINT chk_users_account_status
        CHECK (account_status IN ('active', 'disabled'));

ALTER TABLE devices
    ADD CONSTRAINT chk_devices_platform
        CHECK (platform IN ('windows', 'android', 'ios', 'web'));

ALTER TABLE devices
    ADD CONSTRAINT chk_devices_status
        CHECK (status IN ('active', 'revoked'));

ALTER TABLE device_sessions
    ADD CONSTRAINT chk_device_sessions_type
        CHECK (session_type IN ('device', 'user'));

ALTER TABLE api_tokens
    ADD CONSTRAINT chk_api_tokens_subject_type
        CHECK (subject_type IN ('user', 'device', 'service'));

ALTER TABLE company_subscriptions
    ADD CONSTRAINT chk_company_subscriptions_status
        CHECK (status IN ('trial', 'active', 'expired', 'suspended', 'cancelled'));

ALTER TABLE stock_movements
    ADD CONSTRAINT chk_stock_movements_type
        CHECK (movement_type IN ('in', 'out', 'adjust', 'transfer'));

ALTER TABLE partner_ledger
    ADD CONSTRAINT chk_partner_ledger_kind
        CHECK (partner_kind IN ('customer', 'supplier'));

ALTER TABLE cash_transactions
    ADD CONSTRAINT chk_cash_transactions_type
        CHECK (transaction_type IN ('in', 'out'));

ALTER TABLE invoice_payment_splits
    ADD CONSTRAINT chk_invoice_payment_splits_kind
        CHECK (invoice_kind IN ('sale', 'purchase', 'sales_return', 'purchase_return'));

ALTER TABLE sync_changelog
    ADD CONSTRAINT chk_sync_changelog_operation
        CHECK (operation IN ('create', 'update', 'delete', 'resolved'));

ALTER TABLE sync_queue
    ADD CONSTRAINT chk_sync_queue_status
        CHECK (status IN ('pending', 'processing', 'applied', 'rejected', 'conflict'));

ALTER TABLE sync_queue
    ADD CONSTRAINT chk_sync_queue_operation
        CHECK (operation IN ('create', 'update', 'delete'));

ALTER TABLE sync_conflicts
    ADD CONSTRAINT chk_sync_conflicts_status
        CHECK (status IN ('pending', 'resolved'));

ALTER TABLE sync_conflicts
    ADD CONSTRAINT chk_sync_conflicts_kind
        CHECK (conflict_kind IN ('row_version', 'business_rule', 'stock_negative', 'duplicate'));

ALTER TABLE sync_conflicts
    ADD CONSTRAINT chk_sync_conflicts_resolution
        CHECK (resolution IS NULL OR resolution IN ('server_wins', 'client_wins', 'merge'));

ALTER TABLE notifications
    ADD CONSTRAINT chk_notifications_priority
        CHECK (priority IN ('low', 'normal', 'high', 'urgent'));

ALTER TABLE notification_receipts
    ADD CONSTRAINT chk_notification_receipts_target
        CHECK (device_id IS NOT NULL OR user_id IS NOT NULL);

ALTER TABLE sales_invoices
    ADD CONSTRAINT chk_sales_invoices_status
        CHECK (invoice_status IN ('draft', 'posted', 'void', 'cancelled'));

ALTER TABLE purchase_invoices
    ADD CONSTRAINT chk_purchase_invoices_status
        CHECK (invoice_status IN ('draft', 'posted', 'void', 'cancelled'));

ALTER TABLE sales_returns
    ADD CONSTRAINT chk_sales_returns_status
        CHECK (return_status IN ('draft', 'posted', 'void', 'cancelled'));

ALTER TABLE purchase_returns
    ADD CONSTRAINT chk_purchase_returns_status
        CHECK (return_status IN ('draft', 'posted', 'void', 'cancelled'));

-- Non-negative amounts where applicable
ALTER TABLE products
    ADD CONSTRAINT chk_products_stock_qty_non_negative
        CHECK (stock_qty >= 0);

ALTER TABLE sales_invoices
    ADD CONSTRAINT chk_sales_invoices_totals_non_negative
        CHECK (line_subtotal >= 0 AND discount_amount >= 0 AND total >= 0 AND paid_amount >= 0);

ALTER TABLE purchase_invoices
    ADD CONSTRAINT chk_purchase_invoices_totals_non_negative
        CHECK (line_subtotal >= 0 AND discount_amount >= 0 AND total >= 0 AND paid_amount >= 0);

COMMIT;
