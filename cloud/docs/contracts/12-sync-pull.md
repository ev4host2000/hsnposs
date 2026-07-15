# 12 — Sync Pull

---

## GET `/sync/versions`

مقارنة إصدارات السحابة قبل pull.

| | |
|---|---|
| **Method** | `GET` |
| **URL** | `/v1/sync/versions` |
| **Authorization** | `Bearer` + scope `sync:pull` |

### Query Parameters

| Param | مطلوب | الوصف |
|-------|--------|--------|
| `company_id` | نعم | UUID |
| `branch_id` | موصى به | UUID |

### Response Body (200)

```json
{
  "ok": true,
  "data": {
    "company_id": "550e8400-...",
    "branch_id": "660e8400-...",
    "versions": {
      "catalog": { "version": 42, "last_sequence": 1200 },
      "invoices": { "version": 18, "last_sequence": 890 },
      "users": { "version": 3, "last_sequence": 45 },
      "all": { "version": 55, "last_sequence": 1250 }
    },
    "server_time": "2026-07-05T09:00:00.000Z"
  }
}
```

### Success Codes: 200

---

## GET `/sync/pull`

سحب delta من `sync_changelog`.

| | |
|---|---|
| **Method** | `GET` |
| **URL** | `/v1/sync/pull` |
| **Authorization** | `Bearer` + scope `sync:pull` |

### Query Parameters

| Param | مطلوب | الوصف |
|-------|--------|--------|
| `company_id` | نعم | UUID |
| `branch_id` | حسب scope | UUID |
| `since_sequence` | نعم* | آخر sequence محلي |
| `entity_scope` | نعم | `catalog` \| `invoices` \| `users` \| `all` |
| `limit` | لا | default 100, max 500 |
| `cursor` | لا | بديل cursor-based |

\* أو `cursor` بدلاً من `since_sequence`

### Response Body (200)

```json
{
  "ok": true,
  "data": {
    "company_id": "550e8400-...",
    "branch_id": "660e8400-...",
    "entity_scope": "catalog",
    "entries": [
      {
        "sequence": 1199,
        "entity_type": "product",
        "entity_id": "p100e8400-...",
        "operation": "update",
        "payload_json": {
          "id": "p100e8400-...",
          "name": "حليب",
          "sale_price": 7.0,
          "row_version": 8
        },
        "row_version": 8,
        "origin_device_id": "770e8400-...",
        "occurred_at": "2026-07-05T08:45:00.000Z"
      },
      {
        "sequence": 1200,
        "entity_type": "product",
        "entity_id": "p200e8400-...",
        "operation": "create",
        "payload_json": {
          "id": "p200e8400-...",
          "name": "جبنة بيضاء",
          "sale_price": 12.0
        },
        "row_version": 1,
        "origin_device_id": "aa0e8400-...",
        "occurred_at": "2026-07-05T08:50:00.000Z"
      }
    ]
  },
  "meta": {
    "since_sequence": 1198,
    "last_sequence": 1200,
    "has_more": false,
    "next_cursor": null,
    "entry_count": 2
  }
}
```

### Response Body (200) — لا تغييرات

```json
{
  "ok": true,
  "data": {
    "entries": []
  },
  "meta": {
    "since_sequence": 1200,
    "last_sequence": 1200,
    "has_more": false,
    "entry_count": 0
  }
}
```

### Success Codes: 200

### Error Codes

| Code | HTTP |
|------|------|
| `invalid_scope` | 400 |
| `branch_forbidden` | 403 |
| `since_sequence_too_old` | 410 — يتطلب full resync |

### Response Body (410)

```json
{
  "ok": false,
  "error": {
    "code": "since_sequence_too_old",
    "message": "Changelog retention exceeded; request full snapshot",
    "status_code": 410,
    "details": { "min_available_sequence": 900 }
  }
}
```

---

## GET `/sync/pull/snapshot`

لقطة كاملة لمجال (أول sync أو بعد 410).

| | |
|---|---|
| **Method** | `GET` |
| **URL** | `/v1/sync/pull/snapshot` |
| **Authorization** | `Bearer` + `sync:pull` |

### Query Parameters

`company_id`, `branch_id`, `entity_scope` (`catalog` فقط في v1)

### Response Body (200)

```json
{
  "ok": true,
  "data": {
    "entity_scope": "catalog",
    "products": [ { "id": "...", "name": "..." } ],
    "customers": [],
    "suppliers": [],
    "snapshot_sequence": 1200,
    "generated_at": "2026-07-05T09:00:00.000Z"
  }
}
```

### Success Codes: 200

### Pagination

Snapshot كبير قد يُقسّم: `page`, `page_size` لكل collection فرعية.
