# Miza Cloud — Database

PostgreSQL 15+ DDL for `mizacloud` database.

## Apply order

**Recommended — one shot:**

```bash
cd cloud/api/database
psql -U postgres -d mizacloud -f install_all.sql
```

`install_all.sql` applies **001–017** in order (skips `010_cleanup.sql`).

**Manual steps:**

```bash
createdb -U postgres mizacloud
psql -U postgres -d mizacloud -f 001_initial_schema.sql
# ... through 009_migrations.sql
psql -U postgres -d mizacloud -f 010_catalog_taxes_price_lists.sql
# ... through 017_opening_stock_transaction_version.sql
```

## Migrations 010–017

| File | Version | Purpose |
|------|---------|---------|
| `010_catalog_taxes_price_lists.sql` | 010 | Taxes, price lists |
| `011_sales_invoice_transaction_version.sql` | 011 | SI `transaction_version` |
| `012_sales_invoice_posted_at.sql` | 012 | SI `posted_at` |
| `013_purchase_invoice_transaction_version.sql` | 013 | PI txn_version + posted_at |
| `014_return_transaction_version.sql` | 014 | Returns |
| `015_payment_transaction_version.sql` | 015 | Payments |
| `016_inventory_adjustment_transaction_version.sql` | 016 | Adjustments |
| `017_opening_stock_transaction_version.sql` | 017 | Opening stock |

> **Note (H-01 resolved):** An older duplicate file `012_purchase_invoice_transaction_version.sql` was renumbered to **013**. Fresh installs via `install_all.sql` are deterministic.

## Teardown (dev only)

```bash
psql -U postgres -d mizacloud -f 010_cleanup.sql
```

## Validate

```powershell
cd cloud/api/database
.\validate_sql.ps1
```

Use `-SkipLive` if PostgreSQL is not installed locally.

## Dev tenant seed

After migrations:

```bash
psql -U postgres -d mizacloud -f ../src/Modules/Auth/database/dev_seed.sql
```

## Reference

- Design: `cloud/database/DATABASE_ARCHITECTURE.md`
- API contracts: `cloud/docs/contracts/`
