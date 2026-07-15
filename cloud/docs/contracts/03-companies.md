# 03 — Companies

---

## GET `/companies/{company_id}`

قراءة شركة المستأجر الحالي.

| | |
|---|---|
| **Method** | `GET` |
| **URL** | `/v1/companies/{company_id}` |
| **Authorization** | `Bearer` + scope `company:read` |

### Headers

`X-Company-ID` يجب أن يطابق `{company_id}` أو يُستنتج من JWT.

### Response Body (200)

```json
{
  "ok": true,
  "data": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "name": "متجر النور",
    "legal_name": "شركة النور للتجارة",
    "country_code": "PS",
    "timezone": "Asia/Gaza",
    "default_currency_code": "ILS",
    "default_locale": "ar",
    "status": "active",
    "created_at": "2025-01-01T00:00:00.000Z",
    "updated_at": "2026-07-01T12:00:00.000Z",
    "row_version": 12
  }
}
```

### Success Codes: 200

### Error Codes: `not_found` 404, `forbidden` 403

---

## PATCH `/companies/{company_id}`

تحديث بيانات الشركة (مالك فقط).

| | |
|---|---|
| **Method** | `PATCH` |
| **URL** | `/v1/companies/{company_id}` |
| **Authorization** | `Bearer` + scope `company:write` + role `owner` |

### Request Body

```json
{
  "name": "متجر النور — فرع رئيسي",
  "timezone": "Asia/Gaza",
  "default_currency_code": "ILS",
  "default_locale": "ar",
  "row_version": 12
}
```

### Response Body (200)

```json
{
  "ok": true,
  "data": {
    "id": "550e8400-...",
    "name": "متجر النور — فرع رئيسي",
    "row_version": 13,
    "updated_at": "2026-07-05T09:00:00.000Z"
  }
}
```

### Success Codes: 200

### Error Codes: `conflict` 409 (row_version), `validation_error` 400

---

## GET `/companies/{company_id}/settings`

إعدادات المؤسسة (JSONB).

| | |
|---|---|
| **Method** | `GET` |
| **URL** | `/v1/companies/{company_id}/settings` |
| **Authorization** | `Bearer` + `company:read` |

### Response Body (200)

```json
{
  "ok": true,
  "data": {
    "company_id": "550e8400-...",
    "settings": {
      "tax_percent": 16,
      "invoice_prefix": "INV-",
      "security": { "idle_lock_minutes": 5 }
    },
    "row_version": 4,
    "updated_at": "2026-06-01T00:00:00.000Z"
  }
}
```

### Success Codes: 200

---

## PUT `/companies/{company_id}/settings`

استبدال إعدادات المؤسسة.

| | |
|---|---|
| **Method** | `PUT` |
| **URL** | `/v1/companies/{company_id}/settings` |
| **Authorization** | `Bearer` + `company:write` |

### Request Body

```json
{
  "settings": {
    "tax_percent": 17
  },
  "row_version": 4
}
```

### Response Body (200)

```json
{
  "ok": true,
  "data": {
    "company_id": "550e8400-...",
    "row_version": 5,
    "updated_at": "2026-07-05T09:00:00.000Z"
  }
}
```

### Success Codes: 200

### Error Codes: `conflict` 409
