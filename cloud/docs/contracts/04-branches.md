# 04 — Branches

---

## GET `/branches`

قائمة فروع الشركة.

| | |
|---|---|
| **Method** | `GET` |
| **URL** | `/v1/branches` |
| **Authorization** | `Bearer` + scope `branches:read` |

### Query Parameters

| Param | الوصف |
|-------|--------|
| `status` | `active` \| `inactive` |
| `page`, `page_size` | pagination |

### Response Body (200)

```json
{
  "ok": true,
  "data": {
    "items": [
      {
        "id": "660e8400-e29b-41d4-a716-446655440001",
        "company_id": "550e8400-...",
        "code": "MAIN",
        "name": "الفرع الرئيسي",
        "address": "رام الله",
        "phone": "+970599000000",
        "is_default": true,
        "status": "active",
        "row_version": 2
      }
    ]
  },
  "meta": { "page": 1, "page_size": 50, "total_count": 2 }
}
```

### Success Codes: 200

---

## GET `/branches/{branch_id}`

| | |
|---|---|
| **Method** | `GET` |
| **URL** | `/v1/branches/{branch_id}` |
| **Authorization** | `Bearer` + `branches:read` |

### Response Body (200)

```json
{
  "ok": true,
  "data": {
    "id": "660e8400-...",
    "company_id": "550e8400-...",
    "code": "MAIN",
    "name": "الفرع الرئيسي",
    "is_default": true,
    "status": "active",
    "created_at": "2025-01-01T00:00:00.000Z",
    "updated_at": "2026-01-01T00:00:00.000Z",
    "row_version": 2
  }
}
```

### Success Codes: 200 | Errors: `not_found` 404

---

## POST `/branches`

إنشاء فرع.

| | |
|---|---|
| **Method** | `POST` |
| **URL** | `/v1/branches` |
| **Authorization** | `Bearer` + `branches:write` + owner |

### Request Body

```json
{
  "id": "bb0e8400-e29b-41d4-a716-446655440099",
  "code": "BR2",
  "name": "فرع نابلس",
  "address": "نابلس",
  "phone": "+970599111111",
  "is_default": false
}
```

> `id` اختياري — إن وُجد من الجهاز للمزامنة idempotent.

### Response Body (201)

```json
{
  "ok": true,
  "data": {
    "id": "bb0e8400-...",
    "code": "BR2",
    "name": "فرع نابلس",
    "status": "active",
    "row_version": 1
  }
}
```

### Success Codes: 201

### Error Codes: `validation_error` 400, `conflict` 409 (code duplicate)

---

## PATCH `/branches/{branch_id}`

| | |
|---|---|
| **Method** | `PATCH` |
| **URL** | `/v1/branches/{branch_id}` |
| **Authorization** | `Bearer` + `branches:write` |

### Request Body

```json
{
  "name": "فرع نابلس — وسط البلد",
  "status": "active",
  "row_version": 1
}
```

### Response Body (200)

```json
{
  "ok": true,
  "data": { "id": "bb0e8400-...", "row_version": 2 }
}
```

### Success Codes: 200 | Errors: `conflict` 409

---

## DELETE `/branches/{branch_id}`

تعطيل فرع (soft: `status=inactive`).

| | |
|---|---|
| **Method** | `DELETE` |
| **URL** | `/v1/branches/{branch_id}` |
| **Authorization** | `Bearer` + `branches:write` + owner |

### Response Body (200)

```json
{
  "ok": true,
  "data": { "id": "bb0e8400-...", "status": "inactive", "deleted_at": null }
}
```

### Success Codes: 200

### Error Codes: `branch_has_data` 409 — لا يُحذف فرع فيه فواتير
