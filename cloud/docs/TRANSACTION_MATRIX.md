# Miza Cloud — Transaction Matrix (Beta 1)

> آخر تحديث: Feature Pack 4 — Production Audit  
> جميع المعاملات الثمانية تستخدم `TransactionPostingPipeline` + `TransactionRegistry` + `TransactionApplyHandler` + `TransactionSyncOutboxWriter`.

## Legend

| Symbol | Meaning |
|--------|---------|
| ✓ | Implemented and tested |
| — | Not applicable (by design) |
| ○ | Partial / UI path not fully on sync |

## Matrix

| Transaction | entityType | Pipeline stages | Inventory | Accounting | UUID prefix | Push | Pull | Apply | Replay | Cloud LWW | Mobile UI | Tests |
|-------------|------------|-----------------|-----------|------------|-------------|------|------|-------|--------|-----------|-----------|-------|
| Sales Invoice | `sales_invoice` | V→I→A→INT→F | ✓ (per line) | ✓ | `si:` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | pipeline, hardening, sync, integration, benchmark |
| Purchase Invoice | `purchase_invoice` | V→I→A→INT→F | ✓ (per line) | ✓ | `pi:` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | pipeline, hardening, sync, integration, benchmark |
| Sales Return | `sales_return` | V→I→A→INT→F | ✓ (per line) | ✓ | `sr:` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | pipeline, hardening, sync, integration, benchmark |
| Purchase Return | `purchase_return` | V→I→A→INT→F | ✓ (per line) | ✓ | `pr:` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | pipeline, hardening, sync, integration, benchmark |
| Customer Payment | `customer_payment` | V→A→INT→F | — | ✓ (cash+ledger) | `cp:` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | pipeline, hardening, sync, integration, benchmark |
| Supplier Payment | `supplier_payment` | V→A→INT→F | — | ✓ (cash+ledger) | `sp:` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | pipeline, hardening, sync, integration, benchmark |
| Inventory Adjustment | `inventory_adjustment` | V→I→INT→F | ✓ (`in`/`out`) | — | `ia:` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | pipeline, hardening, sync, integration, benchmark |
| Opening Stock | `opening_stock` | V→I→INT→F | ✓ (`in` only) | — | `os:` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ (via inventory UI) | pipeline, hardening, sync, integration, benchmark |

**Stages:** V=validation, I=inventory, A=accounting, INT=integrity, F=finalize

## Pipeline families

```
Inventory-only:     validation → inventory → integrity → finalize
Invoice / Return:   validation → inventory → accounting → integrity → finalize
Payment:            validation → accounting → integrity → finalize
```

## Sync paths

| entityType | scopeKey | pushPath | pullPath |
|------------|----------|----------|----------|
| `sales_invoice` | `sales_invoices` | `/sync/push/sales-invoices` | `/sync/pull/sales-invoices` |
| `purchase_invoice` | `purchase_invoices` | `/sync/push/purchase-invoices` | `/sync/pull/purchase-invoices` |
| `sales_return` | `sales_returns` | `/sync/push/sales-returns` | `/sync/pull/sales-returns` |
| `purchase_return` | `purchase_returns` | `/sync/push/purchase-returns` | `/sync/pull/purchase-returns` |
| `customer_payment` | `customer_payments` | `/sync/push/customer-payments` | `/sync/pull/customer-payments` |
| `supplier_payment` | `supplier_payments` | `/sync/push/supplier-payments` | `/sync/pull/supplier-payments` |
| `inventory_adjustment` | `inventory_adjustments` | `/sync/push/inventory-adjustments` | `/sync/pull/inventory-adjustments` |
| `opening_stock` | `opening_stocks` | `/sync/push/opening-stocks` | `/sync/pull/opening-stocks` |

## UUID v5 namespaces

| Family | Namespace suffix | Types |
|--------|------------------|-------|
| Sales | `…430c8` | sales_invoice, sales_return |
| Purchase | `…430c9` | purchase_invoice, purchase_return |
| Customer payment | `…430ca` | customer_payment |
| Supplier payment | `…430cb` | supplier_payment |
| Inventory | `…430cc` | inventory_adjustment, opening_stock |

## Reliability patterns (all transactions)

| Pattern | Implementation |
|---------|----------------|
| Stable Outbox | `TransactionSyncOutboxWriter` with idempotency keys |
| Replay Protection | `idempotent_replay` in validation + movement existence checks |
| Optimistic Lock | `row_version` + `transaction_version` on finalize |
| Rollback | SQLite transaction abort via `PostingPipelineAbortException` |
| Exactly Once | UUID v5 deterministic effect IDs + `movementExists` guards |
| LWW | Cloud DraftLww + PostLww per entity |
| Pull Apply | `*DraftApplyHandler.applyPost` → `runPostingPipeline` |
