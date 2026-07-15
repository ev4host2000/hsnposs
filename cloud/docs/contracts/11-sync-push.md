# 11 — Sync Push

المسار الرئيسي لرفع أحداث offline من الأجهزة.

---

## POST `/sync/push`

| | |
|---|---|
| **Method** | `POST` |
| **URL** | `/v1/sync/push` |
| **Authorization** | `Bearer` + scope `sync:push` |

### Headers

| Header | مطلوب |
|--------|--------|
| `Authorization` | نعم |
| `X-Device-ID` | نعم |
| `X-Company-ID` | نعم |
| `X-Branch-ID` | نعم |
| `Content-Type` | نعم |
| `Idempotency-Key` | اختياري (batch-level) |

### Request Body

```json
{
  "company_id": "550e8400-e29b-41d4-a716-446655440000",
  "branch_id": "660e8400-e29b-41d4-a716-446655440001",
  "device_id": "770e8400-e29b-41d4-a716-446655440002",
  "batch_id": "batch-uuid-v4",
  "events": [
    {
      "outbox_id": "ob-uuid-1",
      "entity_type": "product",
      "entity_id": "p100e8400-e29b-41d4-a716-446655440020",
      "operation": "create",
      "payload_json": {
        "id": "p100e8400-...",
        "name": "حليب",
        "sale_price": 6.5,
        "stock_qty": 48
      },
      "client_row_version": 1,
      "idempotency_key": "770e8400-...:p100e8400-...:create",
      "occurred_at": "2026-07-05T08:55:00.000Z"
    },
    {
      "outbox_id": "ob-uuid-2",
      "entity_type": "sales_invoice",
      "entity_id": "si100e8400-...",
      "operation": "create",
      "payload_json": {
        "id": "si100e8400-...",
        "items": [],
        "grand_total": 116.0
      },
      "client_row_version": 1,
      "idempotency_key": "770e8400-...:si100e8400-...:create",
      "occurred_at": "2026-07-05T09:00:00.000Z"
    }
  ]
}
```

### Response Body (202)

```json
{
  "ok": true,
  "data": {
    "batch_id": "batch-uuid-v4",
    "status": "accepted",
    "accepted": 2,
    "duplicates": 0,
    "rejected": 0,
    "queued_at": "2026-07-05T09:00:01.000Z"
  }
}
```

### Response Body (200) — batch مكرر بالكامل

```json
{
  "ok": true,
  "data": {
    "batch_id": "batch-uuid-v4",
    "status": "duplicate",
    "accepted": 0,
    "duplicates": 2
  }
}
```

### Success Codes

| Code | الحالة |
|------|--------|
| 202 | مقبول — معالجة غير متزامنة |
| 200 | idempotent duplicate |

### Error Codes

| Code | HTTP |
|------|------|
| `validation_error` | 400 |
| `device_revoked` | 403 |
| `batch_too_large` | 400 — max 50 events |
| `partial_reject` | 422 — انظر `data.rejected_events` |

### Response Body (422) — رفض جزئي

الأحداث المقبولة تُحفظ (commit) ثم تُرجع 422 مع قائمة المرفوض فقط.

```json
{
  "ok": false,
  "error": {
    "code": "partial_reject",
    "message": "Some events rejected",
    "status_code": 422
  },
  "data": {
    "batch_id": "batch-uuid-v4",
    "status": "partial",
    "accepted": 1,
    "duplicates": 0,
    "rejected": 1,
    "rejected_events": [
      {
        "outbox_id": "ob-uuid-2",
        "error_code": "insufficient_stock",
        "message": "Product p100 stock would go negative"
      }
    ]
  }
}
```

---

## GET `/sync/push/{batch_id}`

حالة معالجة batch.

| | |
|---|---|
| **Method** | `GET` |
| **URL** | `/v1/sync/push/{batch_id}` |
| **Authorization** | `Bearer` + `sync:push` |

### Response Body (200)

```json
{
  "ok": true,
  "data": {
    "batch_id": "batch-uuid-v4",
    "status": "applied",
    "applied": 2,
    "rejected": 0,
    "conflicts": 0,
    "processed_at": "2026-07-05T09:00:05.000Z",
    "changelog_sequences": [41, 42]
  }
}
```

### Success Codes: 200

### Error Codes: `not_found` 404

---

## `entity_type` المدعومة في Push

| entity_type | operations |
|-------------|------------|
| `product` | create, update, delete |
| `customer` | create, update, delete |
| `supplier` | create, update, delete |
| `sales_invoice` | create, update, void |
| `purchase_invoice` | create, update, void |
| `sales_return` | create |
| `purchase_return` | create |
| `stock_movement` | create |
| `expense` | create, update, delete |
| `cash_transaction` | create |
