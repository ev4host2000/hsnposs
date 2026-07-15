# 07 — Customers

---

## GET `/customers`

| | |
|---|---|
| **Method** | `GET` |
| **URL** | `/v1/customers` |
| **Authorization** | `Bearer` + scope `catalog:read` |

### Query Parameters

| Param | الوصف |
|-------|--------|
| `branch_id` | فلتر |
| `q` | بحث بالاسم/الهاتف/الرقم |
| `updated_since` | delta |
| `page`, `page_size` | pagination |

### Response Body (200)

```json
{
  "ok": true,
  "data": {
    "items": [
      {
        "id": "c100e8400-e29b-41d4-a716-446655440030",
        "company_id": "550e8400-...",
        "branch_id": "660e8400-...",
        "name": "محل الأمل",
        "phone": "+970599333333",
        "address": "رام الله",
        "partner_number": "C-001",
        "credit_limit": 5000,
        "balance": 1200.5,
        "row_version": 3,
        "deleted_at": null
      }
    ]
  },
  "meta": { "page": 1, "page_size": 50, "total_count": 45 }
}
```

### Success Codes: 200

---

## GET `/customers/{customer_id}`

| | |
|---|---|
| **Method** | `GET` |
| **URL** | `/v1/customers/{customer_id}` |
| **Authorization** | `Bearer` + `catalog:read` |

### Response Body (200)

```json
{
  "ok": true,
  "data": {
    "id": "c100e8400-...",
    "name": "محل الأمل",
    "phone": "+970599333333",
    "credit_limit": 5000,
    "balance": 1200.5,
    "notes": "",
    "row_version": 3
  }
}
```

### Success Codes: 200 | Errors: `not_found` 404

---

## POST `/customers`

| | |
|---|---|
| **Method** | `POST` |
| **URL** | `/v1/customers` |
| **Authorization** | `Bearer` + `catalog:write` |

### Request Body

```json
{
  "id": "c100e8400-e29b-41d4-a716-446655440030",
  "branch_id": "660e8400-...",
  "name": "محل الأمل",
  "phone": "+970599333333",
  "address": "رام الله",
  "partner_number": "C-001",
  "credit_limit": 5000,
  "client_row_version": 1
}
```

### Response Body (201)

```json
{
  "ok": true,
  "data": {
    "id": "c100e8400-...",
    "row_version": 1
  }
}
```

### Success Codes: 201

### Error Codes: `validation_error` 400, `partner_number_duplicate` 409

---

## PATCH `/customers/{customer_id}`

### Request Body

```json
{
  "name": "محل الأمل — محدّث",
  "credit_limit": 6000,
  "row_version": 3
}
```

### Response Body (200)

```json
{
  "ok": true,
  "data": { "id": "c100e8400-...", "row_version": 4 }
}
```

### Error Codes: `conflict` 409

---

## DELETE `/customers/{customer_id}`

Soft delete.

### Response Body (200)

```json
{
  "ok": true,
  "data": { "id": "c100e8400-...", "deleted_at": "2026-07-05T09:00:00.000Z" }
}
```

### Success Codes: 200

### Error Codes: `customer_has_open_invoices` 409
