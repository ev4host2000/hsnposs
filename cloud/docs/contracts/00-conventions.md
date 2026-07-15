# 00 — Conventions

## Base URL

```
https://api.mizapos.com/v1
```

التطوير: `http://127.0.0.1:8787/v1`  
Staging: `https://api-staging.mizapos.com/v1`

---

## Headers مشتركة

| Header | مطلوب | الوصف |
|--------|--------|--------|
| `Authorization` | معظم المسارات | `Bearer {access_token}` |
| `Content-Type` | POST/PUT/PATCH | `application/json; charset=utf-8` |
| `Accept` | اختياري | `application/json` |
| `Accept-Encoding` | اختياري | `gzip` |
| `User-Agent` | موصى به | `MizaPos-CloudClient/{version}` |
| `X-Request-ID` | موصى به | UUID — تتبع الطلب |
| `X-Device-ID` | معظم المسارات | UUID جهاز سحابي |
| `X-Company-ID` | معظم المسارات | UUID شركة (يجب أن يطابق JWT) |
| `X-Branch-ID` | حسب النطاق | UUID فرع نشط |

---

## Authorization Scopes (JWT claim: `scopes`)

| Scope | الوصف |
|-------|--------|
| `auth:session` | login / refresh |
| `devices:register` | تسجيل جهاز |
| `devices:read` | قائمة الأجهزة |
| `devices:admin` | revoke / activate |
| `company:read` | قراءة شركة |
| `company:write` | تعديل شركة (owner) |
| `branches:read` | قراءة فروع |
| `branches:write` | إدارة فروع |
| `users:read` | قراءة مستخدمين |
| `users:write` | إدارة مستخدمين |
| `catalog:read` | products / customers / suppliers |
| `catalog:write` | كتابة كتالوج |
| `invoices:read` | فواتير |
| `invoices:write` | إنشاء/تعديل فواتير |
| `sync:push` | POST /sync/push |
| `sync:pull` | GET /sync/pull |
| `notifications:read` | إشعارات |

**أدوار مختصرة:**

| Role | Scopes افتراضية |
|------|-----------------|
| `owner` | كل ما سبق |
| `accountant` | catalog + invoices + sync |
| `cashier` | catalog:read, invoices:write, sync |
| `distributor` | catalog:read, sync:pull (محدود) |

---

## Pagination (Offset)

Query parameters:

| Param | النوع | Default | Max |
|-------|-------|---------|-----|
| `page` | int | 1 | — |
| `page_size` | int | 50 | 200 |

Response `meta`:

```json
{
  "meta": {
    "page": 1,
    "page_size": 50,
    "total_count": 1234,
    "total_pages": 25
  }
}
```

---

## Pagination (Cursor) — Sync Pull

| Param | النوع | الوصف |
|-------|-------|--------|
| `since_sequence` | int64 | آخر sequence مُسحوب |
| `limit` | int | default 100, max 500 |
| `cursor` | string | opaque — بديل لـ since_sequence |

Response `meta`:

```json
{
  "meta": {
    "next_cursor": "eyJzZXF1ZW5jZSI6NDJ9",
    "has_more": true,
    "last_sequence": 42
  }
}
```

---

## أخطاء شائعة (`error.code`)

| Code | HTTP | المعنى |
|------|------|--------|
| `unauthorized` | 401 | token غير صالح |
| `token_expired` | 401 | انتهى access token |
| `forbidden` | 403 | scope غير كافٍ |
| `device_revoked` | 403 | جهاز معطّل |
| `company_suspended` | 403 | اشتراك موقوف |
| `not_found` | 404 | مورد غير موجود |
| `validation_error` | 400 | حقول ناقصة |
| `conflict` | 409 | row_version |
| `device_limit_reached` | 403 | حد الأجهزة |
| `installation_conflict` | 409 | installation_id مستخدم |
| `idempotency_duplicate` | 200/202 | push مكرر — no-op |
| `rate_limited` | 429 | كثرة طلبات |

---

## Idempotency (Sync Push)

- Header اختياري: `Idempotency-Key: {device_id}:{entity_id}:{operation}`
- أو حقل `idempotency_key` داخل كل حدث في body
- تكرار نفس المفتاح → `200` أو `202` مع `duplicates: 1`

---

## Timestamps

ISO 8601 UTC: `2026-07-05T09:00:00.000Z`

---

## UUID

كل `id` — UUID v4، يطابق SQLite المحلي.
