# 13 — Conflict Resolution

---

## GET `/sync/conflicts`

قائمة تعارضات الشركة/الجهاز.

| | |
|---|---|
| **Method** | `GET` |
| **URL** | `/v1/sync/conflicts` |
| **Authorization** | `Bearer` + scope `sync:pull` أو `invoices:read` |

### Query Parameters

| Param | الوصف |
|-------|--------|
| `status` | `pending` \| `resolved` |
| `entity_type` | فلتر |
| `device_id` | فلتر |
| `branch_id` | فلتر |
| `page`, `page_size` | pagination |

### Response Body (200)

```json
{
  "ok": true,
  "data": {
    "items": [
      {
        "id": "conf-uuid-1",
        "company_id": "550e8400-...",
        "branch_id": "660e8400-...",
        "device_id": "770e8400-...",
        "entity_type": "product",
        "entity_id": "p100e8400-...",
        "operation": "update",
        "conflict_kind": "row_version",
        "status": "pending",
        "client_row_version": 7,
        "server_row_version": 9,
        "local_payload_json": { "sale_price": 6.5 },
        "server_payload_json": { "sale_price": 7.0 },
        "changelog_sequence": 1199,
        "created_at": "2026-07-05T09:01:00.000Z"
      }
    ]
  },
  "meta": { "page": 1, "page_size": 50, "total_count": 1 }
}
```

### Success Codes: 200

---

## GET `/sync/conflicts/{conflict_id}`

| | |
|---|---|
| **Method** | `GET` |
| **URL** | `/v1/sync/conflicts/{conflict_id}` |
| **Authorization** | `Bearer` + `sync:pull` |

### Response Body (200)

```json
{
  "ok": true,
  "data": {
    "id": "conf-uuid-1",
    "conflict_kind": "row_version",
    "status": "pending",
    "resolution_options": ["server_wins", "client_wins", "merge"],
    "local_payload_json": { },
    "server_payload_json": { }
  }
}
```

### Success Codes: 200 | Errors: `not_found` 404

---

## POST `/sync/conflicts/{conflict_id}/resolve`

| | |
|---|---|
| **Method** | `POST` |
| **URL** | `/v1/sync/conflicts/{conflict_id}/resolve` |
| **Authorization** | `Bearer` + `catalog:write` أو `invoices:write` (حسب entity) |

### Request Body — Server Wins

```json
{
  "resolution": "server_wins",
  "resolved_by_user_id": "990e8400-...",
  "notes": "السعر على السحابة أحدث"
}
```

### Request Body — Client Wins (re-push)

```json
{
  "resolution": "client_wins",
  "merged_payload_json": {
    "sale_price": 6.5,
    "row_version": 10
  },
  "force": true
}
```

### Request Body — Merge

```json
{
  "resolution": "merge",
  "merged_payload_json": {
    "sale_price": 6.75,
    "name": "حليب كامل الدسم"
  }
}
```

### Response Body (200)

```json
{
  "ok": true,
  "data": {
    "conflict_id": "conf-uuid-1",
    "status": "resolved",
    "resolution": "server_wins",
    "resolved_at": "2026-07-05T09:05:00.000Z",
    "changelog_sequence": 1201,
    "device_notification": {
      "kind": "conflict_resolved",
      "entity_type": "product",
      "entity_id": "p100e8400-..."
    }
  }
}
```

### Success Codes: 200

### Error Codes

| Code | HTTP |
|------|------|
| `conflict_already_resolved` | 409 |
| `invalid_resolution` | 400 |
| `merge_validation_failed` | 422 |
| `forbidden` | 403 |

---

## POST `/sync/conflicts/resolve-bulk`

حل دفعة تعارضات (لوحة تحكم).

| | |
|---|---|
| **Method** | `POST` |
| **URL** | `/v1/sync/conflicts/resolve-bulk` |
| **Authorization** | `Bearer` + owner |

### Request Body

```json
{
  "resolution": "server_wins",
  "conflict_ids": ["conf-uuid-1", "conf-uuid-2"],
  "entity_scope": "catalog"
}
```

### Response Body (200)

```json
{
  "ok": true,
  "data": {
    "resolved": 2,
    "failed": 0
  }
}
```

### Success Codes: 200

---

## سياسات التعارض الافتراضية

| entity_scope | سياسة افتراضية |
|--------------|----------------|
| `catalog` (products, customers) | server_wins |
| `sales_invoice` | first_ack_wins + manual review |
| `stock` | server_wins + audit |

---

## Webhook / Pull notification

بعد الحل، يظهر حدث في `sync/pull` للأجهزة المتأثرة:

```json
{
  "sequence": 1201,
  "entity_type": "sync_conflict",
  "operation": "resolved",
  "payload_json": {
    "conflict_id": "conf-uuid-1",
    "resolution": "server_wins",
    "entity_type": "product",
    "entity_id": "p100e8400-..."
  }
}
```
