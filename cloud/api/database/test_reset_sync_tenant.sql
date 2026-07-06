-- =============================================================================
-- Miza Cloud — test_reset_sync_tenant.sql
-- Clears sync_changelog and volatile transactional data for the integration
-- test tenant. Safe to run before integration/benchmark tests (dev only).
-- =============================================================================

BEGIN;

\set ON_ERROR_STOP on

DELETE FROM sync_queue
WHERE company_id = '550e8400-e29b-41d4-a716-446655440000';

DELETE FROM sync_changelog
WHERE company_id = '550e8400-e29b-41d4-a716-446655440000';

DELETE FROM cloud_versions
WHERE company_id = '550e8400-e29b-41d4-a716-446655440000';

DELETE FROM stock_movements
WHERE company_id = '550e8400-e29b-41d4-a716-446655440000';

DELETE FROM partner_ledger
WHERE company_id = '550e8400-e29b-41d4-a716-446655440000';

DELETE FROM cash_transactions
WHERE company_id = '550e8400-e29b-41d4-a716-446655440000';

DELETE FROM invoice_payment_splits
WHERE company_id = '550e8400-e29b-41d4-a716-446655440000';

DELETE FROM sales_return_items
WHERE return_id IN (
    SELECT id FROM sales_returns
    WHERE company_id = '550e8400-e29b-41d4-a716-446655440000'
);

DELETE FROM sales_returns
WHERE company_id = '550e8400-e29b-41d4-a716-446655440000';

DELETE FROM purchase_return_items
WHERE return_id IN (
    SELECT id FROM purchase_returns
    WHERE company_id = '550e8400-e29b-41d4-a716-446655440000'
);

DELETE FROM purchase_returns
WHERE company_id = '550e8400-e29b-41d4-a716-446655440000';

DELETE FROM sales_invoice_items
WHERE invoice_id IN (
    SELECT id FROM sales_invoices
    WHERE company_id = '550e8400-e29b-41d4-a716-446655440000'
);

DELETE FROM sales_invoices
WHERE company_id = '550e8400-e29b-41d4-a716-446655440000';

DELETE FROM purchase_invoice_items
WHERE invoice_id IN (
    SELECT id FROM purchase_invoices
    WHERE company_id = '550e8400-e29b-41d4-a716-446655440000'
);

DELETE FROM purchase_invoices
WHERE company_id = '550e8400-e29b-41d4-a716-446655440000';

DELETE FROM customer_payments
WHERE company_id = '550e8400-e29b-41d4-a716-446655440000';

DELETE FROM supplier_payments
WHERE company_id = '550e8400-e29b-41d4-a716-446655440000';

DELETE FROM inventory_adjustments
WHERE company_id = '550e8400-e29b-41d4-a716-446655440000';

DELETE FROM opening_stocks
WHERE company_id = '550e8400-e29b-41d4-a716-446655440000';

-- Catalog + partner master data (volatile; re-seeded by tests).
DO $reset_catalog$
BEGIN
  IF to_regclass('public.price_list_items') IS NOT NULL THEN
    DELETE FROM price_list_items
    WHERE company_id = '550e8400-e29b-41d4-a716-446655440000';
  END IF;
  IF to_regclass('public.price_lists') IS NOT NULL THEN
    DELETE FROM price_lists
    WHERE company_id = '550e8400-e29b-41d4-a716-446655440000';
  END IF;
  IF to_regclass('public.taxes') IS NOT NULL THEN
    DELETE FROM taxes
    WHERE company_id = '550e8400-e29b-41d4-a716-446655440000';
  END IF;
  IF to_regclass('public.product_units') IS NOT NULL THEN
    DELETE FROM product_units
    WHERE company_id = '550e8400-e29b-41d4-a716-446655440000';
  END IF;
  IF to_regclass('public.product_categories') IS NOT NULL THEN
    DELETE FROM product_categories
    WHERE company_id = '550e8400-e29b-41d4-a716-446655440000';
  END IF;
END $reset_catalog$;

DELETE FROM customers
WHERE company_id = '550e8400-e29b-41d4-a716-446655440000';

DELETE FROM suppliers
WHERE company_id = '550e8400-e29b-41d4-a716-446655440000';

COMMIT;
