# 09 — Sales Invoices

يشمل: `sales_invoices`, `sales_invoice_items`, `invoice_payment_splits`, `sales_returns`.

---

## GET `/sales-invoices`

| | |
|---|---|
| **Method** | `GET` |
| **URL** | `/v1/sales-invoices` |
| **Authorization** | `Bearer` + scope `invoices:read` |

### Query Parameters

| Param | الوصف |
|-------|--------|
| `branch_id` | مطلوب غالباً |
| `from_date`, `to_date` | ISO date |
| `customer_id` | فلتر |
| `updated_since` | delta |
| `page`, `page_size` | pagination |

### Response Body (200)

```json
{
  "ok": true,
  "data": {
    "items": [
      {
        "id": "si100e8400-e29b-41d4-a716-446655440050",
        "company_id": "550e8400-...",
        "branch_id": "660e8400-...",
        "invoice_number": "S-1024",
        "customer_id": "c100e8400-...",
        "customer_name": "محل الأمل",
        "invoice_date": "2026-07-05",
        "subtotal": 100.0,
        "discount_amount": 0,
        "tax_amount": 16.0,
        "grand_total": 116.0,
        "paid_amount": 116.0,
        "status": "posted",
        "origin_device_id": "770e8400-...",
        "row_version": 1,
        "created_at": "2026-07-05T09:00:00.000Z"
      }
    ]
  },
  "meta": { "page": 1, "page_size": 50, "total_count": 500 }
}
```

### Success Codes: 200

---

## GET `/sales-invoices/{invoice_id}`

| | |
|---|---|
| **Method** | `GET` |
| **URL** | `/v1/sales-invoices/{invoice_id}` |
| **Authorization** | `Bearer` + `invoices:read` |

### Response Body (200)

```json
{
  "ok": true,
  "data": {
    "id": "si100e8400-...",
    "invoice_number": "S-1024",
    "customer_id": "c100e8400-...",
    "grand_total": 116.0,
    "items": [
      {
        "id": "line-uuid-1",
        "product_id": "p100e8400-...",
        "product_name": "حليب",
        "quantity": 2,
        "unit_price": 50.0,
        "line_total": 100.0
      }
    ],
    "payment_splits": [
      { "payment_type": "cash", "amount": 116.0 }
    ],
    "row_version": 1
  }
}
```

### Success Codes: 200 | Errors: `not_found` 404

---

## POST `/sales-invoices`

إنشاء فاتورة (REST مباشر — البديل الأساسي للمزامنة: `sync/push`).

| | |
|---|---|
| **Method** | `POST` |
| **URL** | `/v1/sales-invoices` |
| **Authorization** | `Bearer` + `invoices:write` |

### Request Body

```json
{
  "id": "si100e8400-e29b-41d4-a716-446655440050",
  "branch_id": "660e8400-...",
  "invoice_number": "S-1024",
  "customer_id": "c100e8400-...",
  "invoice_date": "2026-07-05",
  "discount_amount": 0,
  "tax_percent": 16,
  "paid_amount": 116.0,
  "items": [
    {
      "id": "line-uuid-1",
      "product_id": "p100e8400-...",
      "quantity": 2,
      "unit_price": 50.0
    }
  ],
  "payment_splits": [
    { "payment_type": "cash", "amount": 116.0 }
  ],
  "client_row_version": 1,
  "idempotency_key": "770e8400-...:si100e8400-...:create"
}
```

### Response Body (201)

```json
{
  "ok": true,
  "data": {
    "id": "si100e8400-...",
    "invoice_number": "S-1024",
    "grand_total": 116.0,
    "row_version": 1,
    "stock_movements_created": 1
  }
}
```

### Success Codes: 201, 200 (idempotent)

### Error Codes

| Code | HTTP |
|------|------|
| `insufficient_stock` | 409 |
| `validation_error` | 400 |
| `conflict` | 409 |
| `customer_not_found` | 404 |

---

## PATCH `/sales-invoices/{invoice_id}`

تعديل مسودة فقط (`status=draft`).

### Request Body

```json
{
  "paid_amount": 50.0,
  "row_version": 1
}
```

### Success Codes: 200

### Error Codes: `invoice_not_editable` 409

---

## POST `/sales-invoices/{invoice_id}/void`

إلغاء فاتورة مرحّلة.

| | |
|---|---|
| **Method** | `POST` |
| **URL** | `/v1/sales-invoices/{invoice_id}/void` |
| **Authorization** | `Bearer` + `invoices:write` |

### Request Body

```json
{
  "reason": "duplicate_entry",
  "row_version": 1
}
```

### Response Body (200)

```json
{
  "ok": true,
  "data": { "id": "si100e8400-...", "status": "voided", "row_version": 2 }
}
```

---

## POST `/sales-returns`

مرتجع مبيعات.

| | |
|---|---|
| **Method** | `POST` |
| **URL** | `/v1/sales-returns` |
| **Authorization** | `Bearer` + `invoices:write` |

### Request Body

```json
{
  "id": "sr-uuid",
  "original_invoice_id": "si100e8400-...",
  "branch_id": "660e8400-...",
  "items": [
    { "product_id": "p100e8400-...", "quantity": 1, "unit_price": 50.0 }
  ],
  "client_row_version": 1
}
```

### Response Body (201)

```json
{
  "ok": true,
  "data": { "id": "sr-uuid", "row_version": 1 }
}
```

### Success Codes: 201
