# 08 — Suppliers

نفس نمط Customers — `suppliers` table.

---

## GET `/suppliers`

| | |
|---|---|
| **Method** | `GET` |
| **URL** | `/v1/suppliers` |
| **Authorization** | `Bearer` + scope `catalog:read` |

### Query Parameters

`branch_id`, `q`, `updated_since`, `page`, `page_size`

### Response Body (200)

```json
{
  "ok": true,
  "data": {
    "items": [
      {
        "id": "s100e8400-e29b-41d4-a716-446655440040",
        "company_id": "550e8400-...",
        "branch_id": "660e8400-...",
        "name": "مورد الألبان",
        "phone": "+970599444444",
        "partner_number": "S-001",
        "balance": -800.0,
        "row_version": 2
      }
    ]
  },
  "meta": { "page": 1, "page_size": 50, "total_count": 12 }
}
```

### Success Codes: 200

---

## GET `/suppliers/{supplier_id}`

| | |
|---|---|
| **Method** | `GET` |
| **URL** | `/v1/suppliers/{supplier_id}` |
| **Authorization** | `Bearer` + `catalog:read` |

### Response Body (200)

```json
{
  "ok": true,
  "data": {
    "id": "s100e8400-...",
    "name": "مورد الألبان",
    "phone": "+970599444444",
    "balance": -800.0,
    "row_version": 2
  }
}
```

---

## POST `/suppliers`

| | |
|---|---|
| **Method** | `POST` |
| **URL** | `/v1/suppliers` |
| **Authorization** | `Bearer` + `catalog:write` |

### Request Body

```json
{
  "id": "s100e8400-e29b-41d4-a716-446655440040",
  "branch_id": "660e8400-...",
  "name": "مورد الألبان",
  "phone": "+970599444444",
  "partner_number": "S-001",
  "client_row_version": 1
}
```

### Response Body (201)

```json
{
  "ok": true,
  "data": { "id": "s100e8400-...", "row_version": 1 }
}
```

### Success Codes: 201

---

## PATCH `/suppliers/{supplier_id}`

### Request Body

```json
{
  "name": "مورد الألبان المحدّث",
  "row_version": 2
}
```

### Response Body (200)

```json
{
  "ok": true,
  "data": { "id": "s100e8400-...", "row_version": 3 }
}
```

### Error Codes: `conflict` 409

---

## DELETE `/suppliers/{supplier_id}`

### Response Body (200)

```json
{
  "ok": true,
  "data": { "id": "s100e8400-...", "deleted_at": "2026-07-05T09:00:00.000Z" }
}
```

### Success Codes: 200
