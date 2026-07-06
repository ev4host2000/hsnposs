# Miza Cloud — Sync Architecture

> **النطاق:** دورة المزامنة الكاملة — من حفظ منتج على جهاز واحد حتى ظهوره على بقية الأجهزة  
> **المبدأ:** Offline-First — SQLite محلي أولاً، PostgreSQL مرجع بعد `ack`  
> **بدون كود** — مخططات ASCII فقط

**معاملات ADR-TX (Beta 1):** راجع [ARCHITECTURE_SUMMARY.md](./ARCHITECTURE_SUMMARY.md) و [TRANSACTION_MATRIX.md](./TRANSACTION_MATRIX.md) و [PRODUCTION_AUDIT_FP4.md](./PRODUCTION_AUDIT_FP4.md).

---

## 1. نظرة عامة

```
┌─────────────┐     push      ┌─────────────┐     pull      ┌─────────────┐
│  Device A   │ ────────────► │  Miza Cloud │ ────────────► │  Device B   │
│  SQLite     │               │ PostgreSQL  │               │  SQLite     │
└─────────────┘               └─────────────┘               └─────────────┘
       │                              │                              │
       │  AccountingService           │  sync_queue                  │  SyncEngine
       │  addProduct()                │  sync_changelog              │  applyPull()
       │  _audit()                    │  cloud_versions              │  upsert local
       └──────────────────────────────┴──────────────────────────────┘
```

**القاعدة الذهبية:** التطبيق **لا يكتب** في PostgreSQL مباشرة. كل الكتابة المحلية عبر `AccountingService`؛ المزامنة عبر **Sync Engine** مستقل.

---

## 2. المكوّنات

```
┌──────────────────────────────────────────────────────────────────────────┐
│                         FLUTTER (Windows / Android)                       │
├──────────────────────────────────────────────────────────────────────────┤
│  UI Layer          inventory_screen / add_product_dialog                  │
│       │                                                                   │
│       ▼                                                                   │
│  AccountingService    addProduct() → SQLite transaction → _audit()       │
│       │                                                                   │
│       ▼                                                                   │
│  Sync Hook (post-commit)   يسجّل حدثاً في sync_outbox المحلي             │
│       │                                                                   │
│       ▼                                                                   │
│  SyncEngine            PushWorker │ PullWorker │ ConflictHandler          │
│       │                                                                   │
│       ▼                                                                   │
│  SyncApiClient         HTTPS → api.mizapos.com                             │
└──────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌──────────────────────────────────────────────────────────────────────────┐
│                         MIZA CLOUD (api.mizapos.com)                      │
├──────────────────────────────────────────────────────────────────────────┤
│  Routes → Middleware (JWT + company/branch scope)                         │
│       │                                                                   │
│       ▼                                                                   │
│  SyncService           ingest → validate → apply → changelog               │
│       │                                                                   │
│       ▼                                                                   │
│  Repositories          products, sync_queue, sync_changelog, cloud_versions│
│       │                                                                   │
│       ▼                                                                   │
│  PostgreSQL            Source of Truth بعد ack                            │
└──────────────────────────────────────────────────────────────────────────┘
```

---

## 3. السينario: إضافة منتج جديد (Device A)

### المرحلة 0 — قبل الإنترنت (Offline)

```
User taps "Save Product"
        │
        ▼
┌───────────────────┐
│ AccountingService │
│   addProduct()    │
└─────────┬─────────┘
          │
          ▼
┌─────────────────────────────────────────┐
│ SQLite TRANSACTION (Device A)           │
│  • INSERT products (id=UUID, ...)       │
│  • row_version = 1                      │
│  • INSERT auditLogs                       │
└─────────┬───────────────────────────────┘
          │
          ▼
┌─────────────────────────────────────────┐
│ Sync Hook (post-commit)                 │
│  • INSERT sync_outbox                     │
│      entity_type = product              │
│      entity_id   = same UUID            │
│      operation   = create               │
│      sync_state  = pending              │
│      payload     = snapshot JSON        │
└─────────┬───────────────────────────────┘
          │
          ▼
   UI shows product ✓
   Sync badge: "معلّق — بانتظار الاتصال"
```

**النتيجة:** المنتج **يعمل فوراً** على Device A. السحابة لا تعرف بعد.

---

### المرحلة 1 — PushWorker يكتشف اتصالاً

```
SyncEngine (background timer / connectivity listener)
        │
        │  Internet available?
        ▼
┌───────────────────┐
│  PushWorker       │
│  read sync_outbox │
│  WHERE pending    │
└─────────┬─────────┘
          │
          ▼
  Batch events (e.g. max 50)
  idempotency_key = device_id + entity_id + operation
          │
          ▼
┌───────────────────────────────────────────────────────────┐
│  POST /sync/push                                          │
│  Authorization: Bearer <access_token>                   │
│  Body: { company_id, branch_id, device_id, batch_id,     │
│          events: [{ entity_type, entity_id, operation,   │
│                      payload, client_row_version }] }     │
└─────────┬─────────────────────────────────────────────────┘
          │
          ▼
                    api.mizapos.com
```

---

### المرحلة 2 — Cloud يستقبل (sync_queue)

```
POST /sync/push
        │
        ▼
┌───────────────────┐
│ Middleware        │
│ • JWT valid?      │
│ • device active?  │
│ • branch scope OK?│
└─────────┬─────────┘
          │
          ▼
┌─────────────────────────────────────────┐
│ SyncService.ingest()                    │
│  FOR EACH event:                        │
│    INSERT sync_queue                    │
│      status = pending                   │
│      idempotency_key UNIQUE per device  │
│  (duplicate push → no-op / 200 ack)     │
└─────────┬───────────────────────────────┘
          │
          ▼
   HTTP 202 Accepted
   { batch_id, accepted: N, duplicates: M }
          │
          ▼
┌─────────────────────────────────────────┐
│ Device A: sync_outbox                   │
│   sync_state = pushed                   │
│   cloud_batch_id = ...                  │
└─────────────────────────────────────────┘
```

---

### المرحلة 3 — Cloud يطبّق على PostgreSQL

```
Background Processor (Sync Queue Worker on server)
        │
        ▼
┌─────────────────────────────────────────┐
│ SyncService.processQueue()            │
│  SELECT sync_queue WHERE pending      │
│  FOR UPDATE SKIP LOCKED               │
└─────────┬───────────────────────────────┘
          │
          ▼
┌─────────────────────────────────────────┐
│ Validate product event                  │
│  • company_id / branch_id match token   │
│  • barcode unique in branch?            │
│  • required fields present              │
│  • client_row_version vs server (if upd)│
└─────────┬───────────────────────────────┘
          │
          │  OK
          ▼
┌─────────────────────────────────────────┐
│ PostgreSQL TRANSACTION                  │
│  1. UPSERT products                       │
│       id = entity_id (same UUID)        │
│       row_version = row_version + 1     │
│       origin_device_id = Device A       │
│  2. INSERT sync_changelog               │
│       sequence = next for company       │
│       operation = create                │
│       payload_json = canonical snapshot │
│  3. UPDATE cloud_versions               │
│       entity_scope = catalog            │
│       version = version + 1             │
│  4. UPDATE sync_queue                   │
│       status = applied                  │
└─────────┬───────────────────────────────┘
          │
          ▼
   Product now authoritative on Cloud
```

**في هذه اللحظة:** PostgreSQL = Source of Truth للمنتج. Device A كان already correct (same UUID).

---

### المرحلة 4 — Device A يؤكد (ack)

```
Optional: GET /sync/push/{batch_id}/status
        │
        ▼
   { applied: N, rejected: 0, conflicts: [] }
        │
        ▼
┌─────────────────────────────────────────┐
│ Device A: sync_outbox                   │
│   sync_state = synced                   │
│   synced_at = now                       │
│  sync_meta.last_pushed_sequence = ...   │
└─────────────────────────────────────────┘

Sync badge: "متزامن ✓"
```

---

### المرحلة 5 — Device B يسحب (Pull)

```
SyncEngine on Device B (periodic / on resume / manual refresh)
        │
        ▼
┌─────────────────────────────────────────┐
│ GET /sync/versions?company&branch       │
│ → cloud_versions.catalog.version = 42   │
└─────────┬───────────────────────────────┘
          │
          │  local last_pulled_sequence = 38
          │  42 > 38 → need pull
          ▼
┌─────────────────────────────────────────┐
│ GET /sync/pull                          │
│   ?since_sequence=38                    │
│   &entity_scope=catalog                 │
│   &branch_id=...                        │
└─────────┬───────────────────────────────┘
          │
          ▼
┌─────────────────────────────────────────┐
│ Response: changelog entries 39..42      │
│  [ { sequence:39, entity:product, ...}, │
│    { sequence:40, ... },                │
│    { sequence:41, ... },                │
│    { sequence:42, entity:product NEW } ] │
└─────────┬───────────────────────────────┘
          │
          ▼
┌─────────────────────────────────────────┐
│ Device B: SyncEngine.applyPull()        │
│  FOR EACH changelog entry:              │
│    IF operation = create|update:        │
│      AccountingService.upsertProduct()    │
│        (same UUID, server row_version)  │
│    IF operation = delete:             │
│      soft delete locally                │
│  UPDATE sync_meta                       │
│    last_pulled_sequence = 42            │
└─────────┬───────────────────────────────┘
          │
          ▼
   Product visible on Device B ✓
   Inventory screen refreshes
```

---

## 4. المخطط الزمني الكامل (Timeline)

```
Time ─────────────────────────────────────────────────────────────────────►

Device A          Cloud (PG)              Device B
   │                  │                       │
   │ addProduct()     │                       │
   │─────────►SQLite  │                       │
   │ sync_outbox      │                       │
   │                  │                       │
   │    [offline OK]  │                       │
   │                  │                       │
   │ POST /sync/push  │                       │
   │─────────────────►│ sync_queue            │
   │                  │                       │
   │◄──── 202 ack ────│                       │
   │                  │                       │
   │                  │ processQueue          │
   │                  │──► products           │
   │                  │──► sync_changelog +1  │
   │                  │──► cloud_versions++   │
   │                  │                       │
   │ GET status       │                       │
   │◄── applied ──────│                       │
   │                  │                       │
   │                  │   GET /sync/pull      │
   │                  │◄──────────────────────│
   │                  │──────────────────────►│
   │                  │   changelog 39..42    │
   │                  │                       │
   │                  │              upsertProduct()
   │                  │              SQLite ✓
   │                  │                       │
   ▼                  ▼                       ▼
 DONE               DONE                    DONE
```

---

## 5. تعديل منتج (Update) — فرق عن الإنشاء

```
Device A: updateProductDetails()
        │
        ▼
  local row_version: 1 → 2
  sync_outbox: operation = update
        │
        ▼
  POST /sync/push (client_row_version = 2)
        │
        ▼
  Cloud compares:
    IF server row_version > client:
         → 409 conflict (see section 7)
    ELSE:
         → apply, row_version = 3 on server
         → changelog entry operation = update
        │
        ▼
  Device B pulls → upsert with server snapshot
```

---

## 6. حذف منتج (Soft Delete)

```
Device A: deleteProduct()
        │
        ▼
  local: deleted_at = now
  sync_outbox: operation = delete
        │
        ▼
  Cloud: products.deleted_at = now
         changelog: operation = delete (tombstone)
        │
        ▼
  Device B pull: apply tombstone
         local product hidden / deleted_at set
```

---

## 7. التعارضات (Conflict)

```
                    ┌─────────────────┐
                    │ Conflict detected│
                    └────────┬────────┘
                             │
           ┌─────────────────┼─────────────────┐
           ▼                 ▼                 ▼
    ┌─────────────┐  ┌─────────────┐  ┌─────────────┐
    │  Catalog    │  │  Invoice    │  │  Settings   │
    │  (product)  │  │  (sale)     │  │  (JSON)     │
    └──────┬──────┘  └──────┬──────┘  └──────┬──────┘
           │                │                │
           ▼                ▼                ▼
    Server row_version  UUID idempotent   Owner wins
    higher wins (LWW)   first ack wins    over device
           │                │                │
           ▼                ▼                ▼
    Pull overwrites    Reject duplicate  Server snapshot
    loser device       push (200 no-op)  pushed to all
```

**Product conflict flow:**

```
Device A: sale_price = 100, row_version = 2  (offline)
Device B: sale_price = 120, row_version = 3  (synced first to cloud)

Device A pushes update (row_version=2)
        │
        ▼
Cloud: server row_version = 3 > client 2
        │
        ▼
sync_queue.status = conflict
Response: 409 + server snapshot
        │
        ▼
Device A SyncEngine:
  • overwrite local with server (120)
  OR
  • queue for user review (policy flag)
        │
        ▼
Device A shows: "تم تحديث الصنف من السحابة"
```

---

## 8. حالات sync_outbox على الجهاز

```
                    ┌──────────┐
                    │ pending  │  ← just saved locally
                    └────┬─────┘
                         │ push sent
                         ▼
                    ┌──────────┐
                    │ pushed   │  ← ack 202, awaiting server apply
                    └────┬─────┘
                         │
            ┌────────────┼────────────┐
            ▼            ▼            ▼
       ┌─────────┐ ┌─────────┐ ┌──────────┐
       │ synced  │ │ conflict│ │ rejected │
       └─────────┘ └────┬────┘ └────┬─────┘
                          │           │
                          ▼           ▼
                     retry/pull   fix & re-push
                     server wins
```

---

## 9. حالات sync_queue على السحابة

```
  pending ──► processing ──► applied ──► (changelog written)
                  │
                  ├──► rejected (validation fail)
                  │
                  └──► conflict (row_version / business rule)
```

---

## 10. Pull strategies

```
┌─────────────────────────────────────────────────────────────┐
│ WHEN does Device pull?                                      │
├─────────────────────────────────────────────────────────────┤
│  • App resume from background                               │
│  • Periodic timer (e.g. every 5 min if online)              │
│  • After successful push batch                              │
│  • User taps "Sync now"                                     │
│  • cloud_versions changed (push notification — optional)    │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ Pull scopes (entity_scope)                                  │
├─────────────────────────────────────────────────────────────┤
│  catalog   → products, categories, customers, suppliers     │
│  users     → team users                                     │
│  invoices  → sales/purchase + stock_movements               │
│  all       → full delta (heavy — avoid on mobile often)     │
└─────────────────────────────────────────────────────────────┘
```

---

## 11. Idempotency — لماذا UUID واحد

```
Device A pushes product id = abc-123  (create)
        │
        ▼
Network timeout — Device A retries same push
        │
        ▼
Cloud: idempotency_key already seen
        │
        ▼
HTTP 200 — no duplicate row
        │
        ▼
Exactly ONE product abc-123 in PostgreSQL
        │
        ▼
Device B pulls once — gets one entry
```

---

## 12. Multi-Branch isolation

```
Company X
├── Branch 1 (products scoped)
│     Device A pushes product P1 → branch_id = 1
│     Device B (branch 1) pulls → sees P1 ✓
│     Device C (branch 2) pulls catalog scope branch 2 → no P1 ✗
│
└── Branch 2
      Device D pushes product P2 → branch_id = 2
      Only branch 2 devices see P2
```

---

## 13. End-to-end checklist (منتج واحد)

```
[ ] User saves product on Device A
[ ] SQLite commit + audit + sync_outbox pending
[ ] PushWorker sends batch to /sync/push
[ ] sync_queue row created (pending)
[ ] Queue processor validates + upserts products
[ ] sync_changelog sequence incremented
[ ] cloud_versions.catalog incremented
[ ] Device A marks outbox synced
[ ] Device B PullWorker checks versions
[ ] Device B GET /sync/pull since last sequence
[ ] Device B AccountingService upserts product
[ ] Device B UI shows new product
```

---

## 14. علاقة Sync Architecture ببقية الوثائق

```
DATABASE_ARCHITECTURE.md     ← جداول: products, sync_queue, sync_changelog, ...
        │
        ▼
SYNC_ARCHITECTURE.md (هذا)   ← دورة البيانات بين SQLite ↔ Cloud ↔ Devices
        │
        ▼
ROADMAP.md Phase 5–7         ← تنفيذ SyncEngine + Push/Pull API
```

---

*وثيقة تصميم — بدون كود تنفيذي.*
