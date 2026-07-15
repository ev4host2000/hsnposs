# 05 — Users

---

## GET `/users`

| | |
|---|---|
| **Method** | `GET` |
| **URL** | `/v1/users` |
| **Authorization** | `Bearer` + scope `users:read` |

### Query Parameters

| Param | الوصف |
|-------|--------|
| `role` | `owner`, `cashier`, … |
| `account_status` | `active`, `disabled` |
| `include_deleted` | `true` \| `false` |
| `page`, `page_size` | pagination |

### Response Body (200)

```json
{
  "ok": true,
  "data": {
    "items": [
      {
        "id": "990e8400-e29b-41d4-a716-446655440004",
        "company_id": "550e8400-...",
        "default_branch_id": "660e8400-...",
        "username": "cashier1",
        "email": "cashier@store.com",
        "full_name": "سارة أحمد",
        "role": "cashier",
        "account_status": "active",
        "row_version": 5
      }
    ]
  },
  "meta": { "page": 1, "page_size": 50, "total_count": 8 }
}
```

### Success Codes: 200

---

## GET `/users/{user_id}`

| | |
|---|---|
| **Method** | `GET` |
| **URL** | `/v1/users/{user_id}` |
| **Authorization** | `Bearer` + `users:read` |

### Response Body (200)

```json
{
  "ok": true,
  "data": {
    "id": "990e8400-...",
    "username": "cashier1",
    "full_name": "سارة أحمد",
    "phone": "+970599222222",
    "dial_code": "+970",
    "role": "cashier",
    "account_status": "active",
    "default_branch_id": "660e8400-...",
    "last_login_at": "2026-07-05T08:00:00.000Z",
    "row_version": 5
  }
}
```

> **لا يُرجع** `password_hash` أبداً.

### Success Codes: 200 | Errors: `not_found` 404

---

## POST `/users`

| | |
|---|---|
| **Method** | `POST` |
| **URL** | `/v1/users` |
| **Authorization** | `Bearer` + `users:write` |

### Request Body

```json
{
  "id": "cc0e8400-e29b-41d4-a716-446655440010",
  "username": "cashier2",
  "password": "SecurePass123!",
  "full_name": "محمد علي",
  "email": "moh@store.com",
  "role": "cashier",
  "default_branch_id": "660e8400-...",
  "branch_ids": ["660e8400-..."]
}
```

### Response Body (201)

```json
{
  "ok": true,
  "data": {
    "id": "cc0e8400-...",
    "username": "cashier2",
    "role": "cashier",
    "account_status": "active",
    "row_version": 1
  }
}
```

### Success Codes: 201

### Error Codes: `username_taken` 409, `validation_error` 400

---

## PATCH `/users/{user_id}`

| | |
|---|---|
| **Method** | `PATCH` |
| **URL** | `/v1/users/{user_id}` |
| **Authorization** | `Bearer` + `users:write` |

### Request Body

```json
{
  "full_name": "محمد علي — محدّث",
  "role": "accountant",
  "account_status": "active",
  "row_version": 1
}
```

### Response Body (200)

```json
{
  "ok": true,
  "data": { "id": "cc0e8400-...", "row_version": 2 }
}
```

### Success Codes: 200 | Errors: `conflict` 409

---

## DELETE `/users/{user_id}`

Soft delete (`deleted_at`).

| | |
|---|---|
| **Method** | `DELETE` |
| **URL** | `/v1/users/{user_id}` |
| **Authorization** | `Bearer` + `users:write` |

### Response Body (200)

```json
{
  "ok": true,
  "data": { "id": "cc0e8400-...", "deleted_at": "2026-07-05T09:00:00.000Z" }
}
```

### Success Codes: 200

### Error Codes: `cannot_delete_owner` 403

---

## GET `/users/{user_id}/branch-access`

| | |
|---|---|
| **Method** | `GET` |
| **URL** | `/v1/users/{user_id}/branch-access` |
| **Authorization** | `Bearer` + `users:read` |

### Response Body (200)

```json
{
  "ok": true,
  "data": {
    "user_id": "cc0e8400-...",
    "branches": [
      { "branch_id": "660e8400-...", "access_level": "full" }
    ]
  }
}
```

### Success Codes: 200
