# 06 — Products

يشمل: `products`, `product_categories`, `product_units`, `product_sale_units`.

---

## GET `/products`

| | |
|---|---|
| **Method** | `GET` |
| **URL** | `/v1/products` |
| **Authorization** | `Bearer` + scope `catalog:read` |

### Query Parameters

| Param | الوصف |
|-------|--------|
| `branch_id` | فلتر فرع |
| `updated_since` | ISO timestamp — delta REST |
| `q` | بحث بالاسم/باركود |
| `include_deleted` | `true` |
| `page`, `page_size` | pagination |

### Response Body (200)

```json
{
  "ok": true,
  "data": {
    "items": [
      {
        "id": "p100e8400-e29b-41d4-a716-446655440020",
        "company_id": "550e8400-...",
        "branch_id": "660e8400-...",
        "name": "حليب كامل الدسم 1ل",
        "barcode": "6281000000001",
        "sale_price": 6.5,
        "cost_price": 5.0,
        "stock_qty": 48,
        "category_id": "cat-uuid",
        "unit_name": "قطعة",
        "is_hidden": false,
        "is_service": false,
        "origin_device_id": "770e8400-...",
        "row_version": 7,
        "updated_at": "2026-07-05T08:30:00.000Z",
        "deleted_at": null
      }
    ]
  },
  "meta": { "page": 1, "page_size": 50, "total_count": 320 }
}
```

### Success Codes: 200

---

## GET `/products/{product_id}`

| | |
|---|---|
| **Method** | `GET` |
| **URL** | `/v1/products/{product_id}` |
| **Authorization** | `Bearer` + `catalog:read` |

### Response Body (200)

```json
{
  "ok": true,
  "data": {
    "id": "p100e8400-...",
    "name": "حليب كامل الدسم 1ل",
    "barcode": "6281000000001",
    "sale_price": 6.5,
    "cost_price": 5.0,
    "stock_qty": 48,
    "sale_units": [
      { "unit_name": "كرتون", "to_base_factor": 12 }
    ],
    "row_version": 7
  }
}
```

### Success Codes: 200 | Errors: `not_found` 404

---

## POST `/products`

| | |
|---|---|
| **Method** | `POST` |
| **URL** | `/v1/products` |
| **Authorization** | `Bearer` + `catalog:write` |

### Request Body

```json
{
  "id": "p100e8400-e29b-41d4-a716-446655440020",
  "branch_id": "660e8400-...",
  "name": "حليب كامل الدسم 1ل",
  "barcode": "6281000000001",
  "sale_price": 6.5,
  "cost_price": 5.0,
  "stock_qty": 48,
  "category_id": null,
  "unit_name": "قطعة",
  "client_row_version": 1
}
```

### Response Body (201)

```json
{
  "ok": true,
  "data": {
    "id": "p100e8400-...",
    "row_version": 1,
    "created_at": "2026-07-05T09:00:00.000Z"
  }
}
```

### Success Codes: 201, 200 (idempotent same id)

### Error Codes: `barcode_duplicate` 409, `validation_error` 400

---

## PATCH `/products/{product_id}`

| | |
|---|---|
| **Method** | `PATCH` |
| **URL** | `/v1/products/{product_id}` |
| **Authorization** | `Bearer` + `catalog:write` |

### Request Body

```json
{
  "sale_price": 7.0,
  "row_version": 7
}
```

### Response Body (200)

```json
{
  "ok": true,
  "data": { "id": "p100e8400-...", "row_version": 8 }
}
```

### Error Codes: `conflict` 409

---

## DELETE `/products/{product_id}`

Soft delete.

| | |
|---|---|
| **Method** | `DELETE` |
| **URL** | `/v1/products/{product_id}` |
| **Authorization** | `Bearer` + `catalog:write` |

### Response Body (200)

```json
{
  "ok": true,
  "data": { "id": "p100e8400-...", "deleted_at": "2026-07-05T09:00:00.000Z" }
}
```

---

## GET `/product-categories`

| | |
|---|---|
| **Method** | `GET` |
| **URL** | `/v1/product-categories` |
| **Authorization** | `Bearer` + `catalog:read` |

### Response Body (200)

```json
{
  "ok": true,
  "data": {
    "items": [
      { "id": "cat-uuid", "name": "ألبان", "sort_order": 1, "row_version": 1 }
    ]
  }
}
```

---

## POST `/product-categories`

### Request Body

```json
{ "id": "cat-uuid", "name": "ألبان", "sort_order": 1 }
```

### Success Codes: 201

---

## GET `/product-units`

### Response Body (200)

```json
{
  "ok": true,
  "data": { "items": [ { "id": "u-uuid", "name": "كيلو" } ] }
}
```

> المسارات `POST/PATCH/DELETE` لـ categories و units بنفس نمط `products`.
