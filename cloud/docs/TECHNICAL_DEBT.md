# Miza Cloud — Technical Debt Register

> Classified in Feature Pack 4 (Production Audit).  
> **Rule:** Do not implement out-of-scope features here — document only.

## Blocking (must fix before Production v1.0)

| ID | Item | Status | Notes |
|----|------|--------|-------|
| B-01 | `install_all.sql` stopped at migration 011 | **Fixed FP4** | Extended to 012–016 |
| B-02 | Fresh cloud DB missing payment/adjustment/opening tables | **Fixed FP4** | Same as B-01 |

## High (fix before or immediately after RC)

| ID | Item | Area | Notes |
|----|------|------|-------|
| H-01 | Duplicate `schema_migrations` version `012` | Cloud DB | **Fixed** — purchase renumbered to `013_purchase_invoice_transaction_version.sql` |
| H-02 | `validate_sql.ps1` / DB README stop at 009 | Cloud ops | **Fixed** — validates 010–017 + `install_all.sql` live |
| H-03 | Integration test flakiness (`sync_changelog` pollution) | Tests | Invoice/return benchmarks fail on shared dev DB; use sequence rewind + unique entity IDs |
| H-04 | `updateProductDetails(stockQty)` bypasses sync | Mobile | Direct `products.stockQty` update — not opening_stock/adjustment |
| H-05 | Desktop `lib/accounting_service.dart` not on transaction sync | Desktop | Mobile canonical; desktop still local-only for stock paths |
| H-06 | Test compile errors (`ConflictAlgorithm` import) | Tests | **Fixed FP4** in `background_sync_integration_test.dart`, `product_accounting_sync_flow_test.dart` |

## Medium (can defer post-v1.0)

| ID | Item | Area | Notes |
|----|------|------|-------|
| M-01 | `ProductsSync*` outlier vs `AbstractCatalogSyncService` | Cloud | `pushProducts`/`pullProducts` naming; no `ENTITY_TYPE` constant |
| M-02 | `CatalogPullValidator` used for transaction pull | Cloud | Misleading name; behavior OK |
| M-03 | Orphan `SyncController` / empty `SyncService` | Cloud | DI registered, no routes |
| M-04 | PG column `reason` vs mobile `adjustment_reason` | Cloud | API emits `adjustment_reason`; column still `reason` |
| M-05 | Wrong doc comments on return pipeline files | Mobile | Says "Sales-invoice" / "Purchase-invoice" in class docs |
| M-06 | `normalizePullOperation` special-case for invoices only | Cloud | `delete`→`cancel` mapping differs by entity |
| M-07 | `upsertProductByName` / Excel import stock bypass | Mobile | Bulk import adds stock without movements |
| M-08 | No master PS1 runner for all 19 sync scripts | Cloud CI | Manual per-entity execution |

## Low (future improvements)

| ID | Item | Area |
|----|------|------|
| L-01 | Manual Journal | Feature |
| L-02 | Stock Transfer | Feature |
| L-03 | Multi Warehouse | Feature |
| L-04 | Multi Currency | Feature |
| L-05 | Cost Center | Feature |
| L-06 | Bank Reconciliation | Feature |
| L-07 | Rename `CatalogPullValidator` → `SyncPullValidator` | Refactor |
| L-08 | Align `ProductsSync*` with catalog abstract base | Refactor |
| L-09 | Dedicated cloud contract docs for payments/inventory/opening | Docs |

## Out of scope (documented only)

Per product roadmap — not debt to resolve in Beta 1:

- Manual Journal, Stock Transfer, Multi Warehouse, Multi Currency, Cost Center, Bank Reconciliation
