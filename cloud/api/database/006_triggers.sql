-- =============================================================================
-- Miza Cloud — 006_triggers.sql
-- updated_at / row_version triggers on syncable and audit tables
-- =============================================================================

BEGIN;

-- Tables with updated_at only (no row_version bump logic beyond touch)
CREATE TRIGGER trg_companies_touch_updated_at
    BEFORE UPDATE ON companies
    FOR EACH ROW EXECUTE PROCEDURE miza_touch_updated_at();

CREATE TRIGGER trg_branches_touch_updated_at
    BEFORE UPDATE ON branches
    FOR EACH ROW EXECUTE PROCEDURE miza_touch_updated_at();

CREATE TRIGGER trg_organization_settings_touch_updated_at
    BEFORE UPDATE ON organization_settings
    FOR EACH ROW EXECUTE PROCEDURE miza_touch_updated_at();

CREATE TRIGGER trg_branch_settings_touch_updated_at
    BEFORE UPDATE ON branch_settings
    FOR EACH ROW EXECUTE PROCEDURE miza_touch_updated_at();

CREATE TRIGGER trg_device_settings_touch_updated_at
    BEFORE UPDATE ON device_settings
    FOR EACH ROW EXECUTE PROCEDURE miza_touch_updated_at();

CREATE TRIGGER trg_company_subscriptions_touch_updated_at
    BEFORE UPDATE ON company_subscriptions
    FOR EACH ROW EXECUTE PROCEDURE miza_touch_updated_at();

CREATE TRIGGER trg_licenses_touch_updated_at
    BEFORE UPDATE ON licenses
    FOR EACH ROW EXECUTE PROCEDURE miza_touch_updated_at();

CREATE TRIGGER trg_sync_conflicts_touch_updated_at
    BEFORE UPDATE ON sync_conflicts
    FOR EACH ROW EXECUTE PROCEDURE miza_touch_updated_at();

-- Syncable master data & transactions: bump row_version + updated_at
CREATE TRIGGER trg_users_bump_row_version
    BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE PROCEDURE miza_bump_row_version();

CREATE TRIGGER trg_product_categories_bump_row_version
    BEFORE UPDATE ON product_categories
    FOR EACH ROW EXECUTE PROCEDURE miza_bump_row_version();

CREATE TRIGGER trg_product_units_bump_row_version
    BEFORE UPDATE ON product_units
    FOR EACH ROW EXECUTE PROCEDURE miza_bump_row_version();

CREATE TRIGGER trg_products_bump_row_version
    BEFORE UPDATE ON products
    FOR EACH ROW EXECUTE PROCEDURE miza_bump_row_version();

CREATE TRIGGER trg_product_sale_units_bump_row_version
    BEFORE UPDATE ON product_sale_units
    FOR EACH ROW EXECUTE PROCEDURE miza_bump_row_version();

CREATE TRIGGER trg_customers_bump_row_version
    BEFORE UPDATE ON customers
    FOR EACH ROW EXECUTE PROCEDURE miza_bump_row_version();

CREATE TRIGGER trg_suppliers_bump_row_version
    BEFORE UPDATE ON suppliers
    FOR EACH ROW EXECUTE PROCEDURE miza_bump_row_version();

CREATE TRIGGER trg_sales_invoices_bump_row_version
    BEFORE UPDATE ON sales_invoices
    FOR EACH ROW EXECUTE PROCEDURE miza_bump_row_version();

CREATE TRIGGER trg_sales_invoice_items_bump_row_version
    BEFORE UPDATE ON sales_invoice_items
    FOR EACH ROW EXECUTE PROCEDURE miza_bump_row_version();

CREATE TRIGGER trg_purchase_invoices_bump_row_version
    BEFORE UPDATE ON purchase_invoices
    FOR EACH ROW EXECUTE PROCEDURE miza_bump_row_version();

CREATE TRIGGER trg_purchase_invoice_items_bump_row_version
    BEFORE UPDATE ON purchase_invoice_items
    FOR EACH ROW EXECUTE PROCEDURE miza_bump_row_version();

CREATE TRIGGER trg_sales_returns_bump_row_version
    BEFORE UPDATE ON sales_returns
    FOR EACH ROW EXECUTE PROCEDURE miza_bump_row_version();

CREATE TRIGGER trg_sales_return_items_bump_row_version
    BEFORE UPDATE ON sales_return_items
    FOR EACH ROW EXECUTE PROCEDURE miza_bump_row_version();

CREATE TRIGGER trg_purchase_returns_bump_row_version
    BEFORE UPDATE ON purchase_returns
    FOR EACH ROW EXECUTE PROCEDURE miza_bump_row_version();

CREATE TRIGGER trg_purchase_return_items_bump_row_version
    BEFORE UPDATE ON purchase_return_items
    FOR EACH ROW EXECUTE PROCEDURE miza_bump_row_version();

CREATE TRIGGER trg_invoice_payment_splits_bump_row_version
    BEFORE UPDATE ON invoice_payment_splits
    FOR EACH ROW EXECUTE PROCEDURE miza_bump_row_version();

CREATE TRIGGER trg_stock_movements_bump_row_version
    BEFORE UPDATE ON stock_movements
    FOR EACH ROW EXECUTE PROCEDURE miza_bump_row_version();

CREATE TRIGGER trg_partner_ledger_bump_row_version
    BEFORE UPDATE ON partner_ledger
    FOR EACH ROW EXECUTE PROCEDURE miza_bump_row_version();

CREATE TRIGGER trg_cash_transactions_bump_row_version
    BEFORE UPDATE ON cash_transactions
    FOR EACH ROW EXECUTE PROCEDURE miza_bump_row_version();

CREATE TRIGGER trg_expenses_bump_row_version
    BEFORE UPDATE ON expenses
    FOR EACH ROW EXECUTE PROCEDURE miza_bump_row_version();

COMMIT;
