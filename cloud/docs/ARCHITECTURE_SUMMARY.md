# Miza Cloud — Architecture Summary (Beta 1)

> Feature Pack 4 — complements [SYNC_ARCHITECTURE.md](./SYNC_ARCHITECTURE.md) (product/catalog flow) with **transaction** lifecycle.

## System layers

```
┌─────────────────────────────────────────────────────────────┐
│ UI (inventory, sales, purchase, customers, suppliers)        │
└───────────────────────────┬─────────────────────────────────┘
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ AccountingService — business entry points                    │
│  • create draft locally → enqueue outbox                     │
│  • postDraft → TransactionPostingPipeline                    │
└───────────────────────────┬─────────────────────────────────┘
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ Transaction Framework                                        │
│  TransactionRegistry │ TransactionApplyHandler               │
│  TransactionSyncOutboxWriter (stable outbox)                 │
│  TransactionPostingPipeline (stages)                         │
└───────────────────────────┬─────────────────────────────────┘
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ Sync Engine (BackgroundSyncBootstrap)                        │
│  PushWorker → Cloud API │ PullWorker → Apply handlers        │
└───────────────────────────┬─────────────────────────────────┘
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ Cloud PHP — LWW + changelog                                  │
│  DraftLww │ PostLww │ SyncRepositorySupport                  │
└───────────────────────────┬─────────────────────────────────┘
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ PostgreSQL — source of truth after ack                       │
└─────────────────────────────────────────────────────────────┘
```

## Transaction lifecycle

```
1. DRAFT (local)
   User action → AccountingService
   → SQLite header (+ lines if invoice)
   → sync_outbox operation=create

2. POST (local)
   postDraft() → PostingContext + Pipeline stages
   → effects (stock_movements, partner_ledger, cash_transactions)
   → finalize (status=posted, bump versions)
   → sync_outbox operation=post

3. PUSH
   PushWorker → HTTPS POST /sync/push/{entity}
   → Cloud validates → DraftLww or PostLww
   → sync_changelog sequence assigned

4. PULL (other device)
   PullWorker → GET /sync/pull/{entity}?since=sequence
   → changelog entries returned

5. APPLY
   TransactionApplyHandler
   → applyCreate/Update/Post/Cancel
   → applyPost re-runs PostingPipeline (idempotent)

6. REPLAY
   Same post aggregate re-applied
   → validation sets idempotent_replay
   → effects skipped if UUID already exists
```

## Core components

| Component | Role |
|-----------|------|
| `TransactionPostingPipeline` | Ordered stages; rollback on failure |
| `PostingContext` | aggregate + txn + stageData |
| `PostingResult` | ok / failedStageId / failureCode |
| `TransactionRegistry` | entity type → pull/push workers + apply handler |
| `TransactionApplyHandler` | Pull-side local materialization |
| `TransactionSyncOutboxWriter` | Stable idempotent outbox rows |
| UUID v5 | Deterministic effect IDs (`si:`, `ia:`, `os:`, etc.) |
| LWW | `row_version` conflict resolution on draft updates |
| Optimistic lock | Finalize updates `WHERE status=draft` |

## Outbox model

- One stable key per `(entityType, entityId, operation)`
- Operations: `create`, `update`, `post`, `cancel`
- Post outbox skipped on `idempotent_replay`

## Cloud changelog

- Monotonic `sequence` per branch scope
- Pull uses `last_pulled_sequence` in `sync_meta`
- Post/draft entries replayed in order on apply

## Transaction types

See [TRANSACTION_MATRIX.md](./TRANSACTION_MATRIX.md) for full per-type breakdown.

**Count:** 8 synced transaction types (6 accounting + 2 inventory).

## Mobile canonical path

Per workspace rules: `apps/mizapos_mobile/lib/` is the canonical mobile UI and sync implementation.

## Migrations

| Mobile SQLite | Cloud PostgreSQL |
|---------------|------------------|
| v55 (`openingStocks`) | 016 |
| v54 (`inventoryAdjustments`) | 015 |
| v53 (payments) | 014 |
| … | 011–013 (invoice/return txn version) |

Fresh install: `cloud/api/database/install_all.sql` (001–016).
