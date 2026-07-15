# 02 — Device Registration

---

## POST `/auth/devices/register`

تسجيل جهاز لأول مرة أو إعادة تسجيل بعد reinstall.

| | |
|---|---|
| **Method** | `POST` |
| **URL** | `/v1/auth/devices/register` |
| **Authorization** | `Bearer` (مستخدم مصادق) + scope `devices:register` |

### Headers

| Header | مطلوب |
|--------|--------|
| `Authorization` | نعم |
| `X-Company-ID` | نعم |
| `X-Branch-ID` | نعم |
| `Content-Type` | نعم |

### Request Body

```json
{
  "installation_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "device_fingerprint": "sha256:abc123...",
  "platform": "android",
  "device_name": "Samsung A54",
  "os_name": "Android 14",
  "os_user": null,
  "app_version": "1.0.37",
  "company_id": "550e8400-e29b-41d4-a716-446655440000",
  "branch_id": "660e8400-e29b-41d4-a716-446655440001",
  "registered_by_user_id": "990e8400-e29b-41d4-a716-446655440004"
}
```

### Response Body (201)

```json
{
  "ok": true,
  "data": {
    "device_id": "770e8400-e29b-41d4-a716-446655440002",
    "installation_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
    "company_id": "550e8400-e29b-41d4-a716-446655440000",
    "status": "active",
    "registered_at": "2026-07-05T08:00:00.000Z",
    "session_id": "880e8400-e29b-41d4-a716-446655440003",
    "access_token": "eyJ...",
    "refresh_token": "rt_...",
    "expires_in": 900
  }
}
```

### Success Codes

| Code | الحالة |
|------|--------|
| 201 | جهاز جديد |
| 200 | نفس `installation_id` — إعادة إصدار tokens |

### Error Codes

| Code | HTTP |
|------|------|
| `device_limit_reached` | 403 |
| `installation_conflict` | 409 |
| `device_revoked` | 403 |
| `company_suspended` | 403 |
| `forbidden` | 403 |

---

## GET `/devices`

قائمة أجهزة الشركة.

| | |
|---|---|
| **Method** | `GET` |
| **URL** | `/v1/devices` |
| **Authorization** | `Bearer` + `devices:read` أو `devices:admin` |

### Query Parameters

| Param | الوصف |
|-------|--------|
| `status` | `active` \| `revoked` |
| `page`, `page_size` | pagination |

### Response Body (200)

```json
{
  "ok": true,
  "data": {
    "items": [
      {
        "id": "770e8400-e29b-41d4-a716-446655440002",
        "installation_id": "a1b2c3d4-...",
        "platform": "android",
        "device_name": "Samsung A54",
        "status": "active",
        "registered_at": "2026-07-05T08:00:00.000Z",
        "last_seen_at": "2026-07-05T09:00:00.000Z",
        "is_self": false
      }
    ]
  },
  "meta": { "page": 1, "page_size": 50, "total_count": 3 }
}
```

### Success Codes: 200

### Error Codes: `forbidden` 403, `unauthorized` 401

---

## GET `/devices/{device_id}`

تفاصيل جهاز واحد.

| | |
|---|---|
| **Method** | `GET` |
| **URL** | `/v1/devices/{device_id}` |
| **Authorization** | `Bearer` + `devices:read` |

### Response Body (200)

```json
{
  "ok": true,
  "data": {
    "id": "770e8400-e29b-41d4-a716-446655440002",
    "company_id": "550e8400-...",
    "installation_id": "a1b2c3d4-...",
    "device_fingerprint": "sha256:...",
    "platform": "android",
    "device_name": "Samsung A54",
    "status": "active",
    "registered_at": "2026-07-05T08:00:00.000Z",
    "last_seen_at": "2026-07-05T09:00:00.000Z",
    "revoked_at": null,
    "row_version": 3
  }
}
```

### Success Codes: 200

### Error Codes: `not_found` 404

---

## POST `/devices/{device_id}/revoke`

تعطيل جهاز من لوحة التحكم.

| | |
|---|---|
| **Method** | `POST` |
| **URL** | `/v1/devices/{device_id}/revoke` |
| **Authorization** | `Bearer` + `devices:admin` (owner) |

### Request Body

```json
{
  "reason": "phone_replaced",
  "release_license_slot": true
}
```

### Response Body (200)

```json
{
  "ok": true,
  "data": {
    "device_id": "770e8400-...",
    "status": "revoked",
    "revoked_at": "2026-07-05T10:00:00.000Z",
    "sessions_revoked": 2
  }
}
```

### Success Codes: 200

### Error Codes: `not_found` 404, `forbidden` 403

---

## POST `/devices/{device_id}/activate`

إعادة تفعيل جهاز معطّل.

| | |
|---|---|
| **Method** | `POST` |
| **URL** | `/v1/devices/{device_id}/activate` |
| **Authorization** | `Bearer` + `devices:admin` |

### Request Body

```json
{
  "reason": "owner_approved"
}
```

### Response Body (200)

```json
{
  "ok": true,
  "data": {
    "device_id": "770e8400-...",
    "status": "active"
  }
}
```

### Success Codes: 200

### Error Codes: `device_limit_reached` 403, `not_found` 404

---

## POST `/devices/heartbeat`

تحديث `last_seen_at` (خفيف).

| | |
|---|---|
| **Method** | `POST` |
| **URL** | `/v1/devices/heartbeat` |
| **Authorization** | `Bearer` + `X-Device-ID` |

### Request Body

```json
{
  "app_version": "1.0.37"
}
```

### Response Body (200)

```json
{
  "ok": true,
  "data": { "last_seen_at": "2026-07-05T09:05:00.000Z" }
}
```

### Success Codes: 200

### Error Codes: `device_revoked` 403
