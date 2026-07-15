# 14 — Notifications

---

## GET `/notifications`

| | |
|---|---|
| **Method** | `GET` |
| **URL** | `/v1/notifications` |
| **Authorization** | `Bearer` + scope `notifications:read` |

### Query Parameters

| Param | الوصف |
|-------|--------|
| `unread_only` | `true` \| `false` |
| `kind` | `broadcast`, `device_revoked`, `conflict`, `sync_error`, … |
| `since` | ISO timestamp |
| `page`, `page_size` | pagination |

### Response Body (200)

```json
{
  "ok": true,
  "data": {
    "items": [
      {
        "id": "n-uuid-1",
        "company_id": "550e8400-...",
        "branch_id": null,
        "device_id": "770e8400-...",
        "user_id": null,
        "kind": "broadcast",
        "title": "صيانة مجدولة",
        "body": "السحابة ستتوقف 10 دقائق الليلة",
        "priority": "normal",
        "payload_json": {},
        "published_at": "2026-07-05T08:00:00.000Z",
        "expires_at": "2026-07-10T00:00:00.000Z",
        "read_at": null
      },
      {
        "id": "n-uuid-2",
        "kind": "conflict",
        "title": "تعارض في صنف",
        "body": "الصنف «حليب» يحتاج مراجعة",
        "payload_json": {
          "conflict_id": "conf-uuid-1",
          "entity_type": "product",
          "entity_id": "p100e8400-..."
        },
        "read_at": null
      }
    ]
  },
  "meta": { "page": 1, "page_size": 50, "total_count": 2, "unread_count": 2 }
}
```

### Success Codes: 200

---

## GET `/notifications/{notification_id}`

| | |
|---|---|
| **Method** | `GET` |
| **URL** | `/v1/notifications/{notification_id}` |
| **Authorization** | `Bearer` + `notifications:read` |

### Response Body (200)

```json
{
  "ok": true,
  "data": {
    "id": "n-uuid-1",
    "kind": "broadcast",
    "title": "صيانة مجدولة",
    "body": "السحابة ستتوقف 10 دقائق الليلة",
    "payload_json": {},
    "published_at": "2026-07-05T08:00:00.000Z"
  }
}
```

### Success Codes: 200 | Errors: `not_found` 404

---

## POST `/notifications/{notification_id}/read`

تعليم إشعار كمقروء.

| | |
|---|---|
| **Method** | `POST` |
| **URL** | `/v1/notifications/{notification_id}/read` |
| **Authorization** | `Bearer` + `notifications:read` |

### Request Body

```json
{
  "device_id": "770e8400-e29b-41d4-a716-446655440002"
}
```

### Response Body (200)

```json
{
  "ok": true,
  "data": {
    "notification_id": "n-uuid-1",
    "read_at": "2026-07-05T09:10:00.000Z"
  }
}
```

### Success Codes: 200

---

## POST `/notifications/read-all`

| | |
|---|---|
| **Method** | `POST` |
| **URL** | `/v1/notifications/read-all` |
| **Authorization** | `Bearer` + `notifications:read` |

### Request Body

```json
{
  "device_id": "770e8400-...",
  "before": "2026-07-05T09:00:00.000Z"
}
```

### Response Body (200)

```json
{
  "ok": true,
  "data": { "marked_read": 5 }
}
```

### Success Codes: 200

---

## POST `/notifications` (Admin)

إنشاء إشعار broadcast (لوحة تحكم فقط).

| | |
|---|---|
| **Method** | `POST` |
| **URL** | `/v1/notifications` |
| **Authorization** | `Bearer` + owner / service admin |

### Request Body

```json
{
  "kind": "broadcast",
  "title": "تحديث إلزامي",
  "body": "يرجى تحديث التطبيق إلى 1.0.38",
  "priority": "high",
  "company_id": "550e8400-...",
  "branch_id": null,
  "device_id": null,
  "expires_at": "2026-08-01T00:00:00.000Z",
  "payload_json": { "min_app_version": "1.0.38" }
}
```

### Response Body (201)

```json
{
  "ok": true,
  "data": {
    "id": "n-uuid-new",
    "published_at": "2026-07-05T09:15:00.000Z"
  }
}
```

### Success Codes: 201

### Error Codes: `forbidden` 403, `validation_error` 400

---

## GET `/notifications/unread-count`

خفيف للـ badge.

| | |
|---|---|
| **Method** | `GET` |
| **URL** | `/v1/notifications/unread-count` |
| **Authorization** | `Bearer` + `notifications:read` |

### Response Body (200)

```json
{
  "ok": true,
  "data": { "unread_count": 3 }
}
```

### Success Codes: 200
