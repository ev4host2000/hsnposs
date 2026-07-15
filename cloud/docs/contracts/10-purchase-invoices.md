# 10 — Purchase Invoices

يشمل: `purchase_invoices`, `purchase_invoice_items`, `purchase_returns`.

---

## GET `/purchase-invoices`

| | |
|---|---|
| **Method** | `GET` |
| **URL** | `/v1/purchase-invoices` |
| **Authorization** | `Bearer` + scope `invoices:read` |

### Query Parameters

`branch_id`, `supplier_id`, `from_date`, `to_date`, `updated_since`, `page`, `page_size`

### Response Body (200)

```json
{
  "ok": true,
  "data": {
    "items": [
      {
        "id": "pi100e8400-e29b-41d4-a716-446655440060",
        "company_id": "550e8400-...",
        "branch_id": "660e8400-...",
        "invoice_number": "P-501",
        "supplier_id": "s100e8400-...",
        "supplier_name": "مورد الألبان",
        "invoice_date": "2026-07-04",
        "grand_total": 2500.0,
        "paid_amount": 0,
        "status": "posted",
        "origin_device_id": "770e8400-...",
        "row_version": 1
      }
    ]
  },
  "meta": { "page": 1, "page_size": 50, "total_count": 120 }
}
```

### Success Codes: 200

---

## GET `/purchase-invoices/{invoice_id}`

| | |
|---|---|
| **Method** | `GET` |
| **URL** | `/v1/purchase-invoices/{invoice_id}` |
| **Authorization** | `Bearer` + `invoices:read` |

### Response Body (200)

```json
{
  "ok": true,
  "data": {
    "id": "pi100e8400-...",
    "invoice_number": "P-501",
    "supplier_id": "s100e8400-...",
    "grand_total": 2500.0,
    "items": [
      {
        "id": "line-uuid",
        "product_id": "p100e8400-...",
        "quantity": 100,
        "unit_price": 25.0,
        "line_total": 2500.0
      }
    ],
    "payment_splits": [],
    "row_version": 1
  }
}
```

### Success Codes: 200

---

## POST `/purchase-invoices`

| | |
|---|---|
| **Method** | `POST` |
| **URL** | `/v1/purchase-invoices` |
| **Authorization** | `Bearer` + `invoices:write` |

### Request Body

```json
{
  "id": "pi100e8400-e29b-41d4-a716-446655440060",
  "branch_id": "660e8400-...",
  "invoice_number": "P-501",
  "supplier_id": "s100e8400-...",
  "invoice_date": "2026-07-04",
  "items": [
    {
      "id": "line-uuid",
      "product_id": "p100e8400-...",
      "quantity": 100,
      "unit_price": 25.0
    }
  ],
  "paid_amount": 0,
  "client_row_version": 1,
  "idempotency_key": "770e8400-...:pi100e8400-...:create"
}
```

### Response Body (201)

```json
{
  "ok": true,
  "data": {
    "id": "pi100e8400-...",
    "grand_total": 2500.0,
    "row_version": 1,
    "stock_movements_created": 1
  }
}
```

### Success Codes: 201

### Error Codes: `supplier_not_found` 404, `validation_error` 400, `conflict` 409

---

## PATCH `/purchase-invoices/{invoice_id}`

مسودات فقط.

### Request Body

```json
{ "paid_amount": 1000.0, "row_version": 1 }
```

### Success Codes: 200

---

## POST `/purchase-invoices/{invoice_id}/void`

### Request Body

```json
{ "reason": "wrong_supplier", "row_version": 1 }
```

### Response Body (200)

```json
{
  "ok": true,
  "data": { "id": "pi100e8400-...", "status": "voided" }
}
```

---

## POST `/purchase-returns`

| | |
|---|---|
| **Method** | `POST` |
| **URL** | `/v1/purchase-returns` |
| **Authorization** | `Bearer` + `invoices:write` |

### Request Body

```json
{
  "id": "pr-uuid",
  "original_invoice_id": "pi100e8400-...",
  "branch_id": "660e8400-...",
  "items": [
    { "product_id": "p100e8400-...", "quantity": 5, "unit_price": 25.0 }
  ]
}
```

### Response Body (201)

```json
{
  "ok": true,
  "data": { "id": "pr-uuid", "row_version": 1 }
}
```

### Success Codes: 201
