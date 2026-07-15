# Miza Cloud — REST API Contracts

> **الحالة:** تصميم معتمد — وثائق عقود فقط  
> **Base URL:** `https://api.mizapos.com/v1`  
> **التنسيق:** JSON (`application/json; charset=utf-8`)  
> **لا يحتوي:** PHP، Flutter، SQL

---

## فهرس الوثائق

| الملف | المجال |
|-------|--------|
| [00-conventions.md](./00-conventions.md) | Headers، أخطاء، pagination، scopes |
| [01-authentication.md](./01-authentication.md) | Login، refresh، logout |
| [02-devices.md](./02-devices.md) | Device registration، revoke |
| [03-companies.md](./03-companies.md) | Companies |
| [04-branches.md](./04-branches.md) | Branches |
| [05-users.md](./05-users.md) | Users |
| [06-products.md](./06-products.md) | Products + categories/units |
| [07-customers.md](./07-customers.md) | Customers |
| [08-suppliers.md](./08-suppliers.md) | Suppliers |
| [09-sales-invoices.md](./09-sales-invoices.md) | Sales invoices |
| [10-purchase-invoices.md](./10-purchase-invoices.md) | Purchase invoices |
| [11-sync-push.md](./11-sync-push.md) | Push batch |
| [12-sync-pull.md](./12-sync-pull.md) | Pull delta + versions |
| [13-conflicts.md](./13-conflicts.md) | Conflict resolution |
| [14-notifications.md](./14-notifications.md) | Notifications |

---

## شكل الاستجابة الموحّد

### نجاح

```json
{
  "ok": true,
  "data": { },
  "meta": { }
}
```

### فشل

```json
{
  "ok": false,
  "error": {
    "code": "error_code",
    "message": "Human readable message",
    "status_code": 400,
    "details": { }
  }
}
```

---

## رموز HTTP الشائعة

| Code | المعنى |
|------|--------|
| 200 | OK — قراءة أو تحديث ناجح |
| 201 | Created |
| 202 | Accepted — push في الطابور |
| 204 | No Content — حذف ناجح |
| 400 | Bad Request — validation |
| 401 | Unauthorized — token مفقود/منتهي |
| 403 | Forbidden — scope أو جهاز revoked |
| 404 | Not Found |
| 409 | Conflict — row_version / business rule |
| 422 | Unprocessable Entity |
| 429 | Too Many Requests |
| 500 | Internal Server Error |

---

## OpenAPI

ملف تجميعي (مرجعي): [openapi.yaml](./openapi.yaml) — ملخص المسارات فقط، التفاصيل في ملفات المجال.
