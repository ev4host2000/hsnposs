# 01 — Authentication

---

## POST `/auth/login`

تسجيل دخول مستخدم وربط جلسة بجهاز مسجّل مسبقاً.

| | |
|---|---|
| **Method** | `POST` |
| **URL** | `/v1/auth/login` |
| **Authorization** | لا — عام (rate limited) |

### Headers

| Header | مطلوب |
|--------|--------|
| `Content-Type` | نعم |
| `X-Device-ID` | موصى به |
| `X-Request-ID` | موصى به |

### Request Body

```json
{
  "username": "owner@store.com",
  "password": "********",
  "company_id": "550e8400-e29b-41d4-a716-446655440000",
  "branch_id": "660e8400-e29b-41d4-a716-446655440001",
  "device_id": "770e8400-e29b-41d4-a716-446655440002",
  "installation_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
}
```

### Response Body (200)

```json
{
  "ok": true,
  "data": {
    "session_id": "880e8400-e29b-41d4-a716-446655440003",
    "device_id": "770e8400-e29b-41d4-a716-446655440002",
    "company_id": "550e8400-e29b-41d4-a716-446655440000",
    "branch_id": "660e8400-e29b-41d4-a716-446655440001",
    "user_id": "990e8400-e29b-41d4-a716-446655440004",
    "session_type": "user",
    "access_token": "eyJhbGciOiJIUzI1NiIs...",
    "refresh_token": "rt_8f3a2b1c...",
    "token_type": "Bearer",
    "expires_in": 900,
    "expires_at": "2026-07-05T09:15:00.000Z",
    "user": {
      "id": "990e8400-e29b-41d4-a716-446655440004",
      "username": "owner@store.com",
      "full_name": "أحمد محمد",
      "role": "owner"
    }
  }
}
```

### Success Codes

| Code | الحالة |
|------|--------|
| 200 | تسجيل دخول ناجح |

### Error Codes

| Code | HTTP |
|------|------|
| `invalid_credentials` | 401 |
| `account_disabled` | 403 |
| `device_revoked` | 403 |
| `company_suspended` | 403 |
| `validation_error` | 400 |

---

## POST `/auth/token/refresh`

تجديد access token (مع refresh token rotation).

| | |
|---|---|
| **Method** | `POST` |
| **URL** | `/v1/auth/token/refresh` |
| **Authorization** | لا — يعتمد على `refresh_token` في body |

### Request Body

```json
{
  "refresh_token": "rt_8f3a2b1c...",
  "installation_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "device_id": "770e8400-e29b-41d4-a716-446655440002"
}
```

### Response Body (200)

```json
{
  "ok": true,
  "data": {
    "access_token": "eyJhbGciOiJIUzI1NiIs...",
    "refresh_token": "rt_new_9d4e5f6a...",
    "token_type": "Bearer",
    "expires_in": 900,
    "expires_at": "2026-07-05T09:30:00.000Z"
  }
}
```

### Success Codes

| Code | الحالة |
|------|--------|
| 200 | تجديد ناجح |

### Error Codes

| Code | HTTP |
|------|------|
| `refresh_token_invalid` | 401 |
| `refresh_token_expired` | 401 |
| `session_compromised` | 401 — reuse مكتشف |
| `device_revoked` | 403 |

---

## POST `/auth/logout`

إبطال الجلسة الحالية.

| | |
|---|---|
| **Method** | `POST` |
| **URL** | `/v1/auth/logout` |
| **Authorization** | `Bearer` + scope `auth:session` |

### Request Body

```json
{
  "refresh_token": "rt_8f3a2b1c...",
  "revoke_all_sessions": false
}
```

### Response Body (200)

```json
{
  "ok": true,
  "data": {
    "revoked": true
  }
}
```

### Success Codes

| Code | الحالة |
|------|--------|
| 200 | logout ناجح |

### Error Codes

| Code | HTTP |
|------|------|
| `unauthorized` | 401 |

---

## GET `/auth/me`

الجلسة والمستخدم الحالي.

| | |
|---|---|
| **Method** | `GET` |
| **URL** | `/v1/auth/me` |
| **Authorization** | `Bearer` |

### Response Body (200)

```json
{
  "ok": true,
  "data": {
    "session_id": "880e8400-e29b-41d4-a716-446655440003",
    "user": { "id": "...", "role": "owner", "full_name": "..." },
    "company_id": "...",
    "branch_id": "...",
    "device_id": "...",
    "scopes": ["sync:push", "sync:pull", "catalog:write"]
  }
}
```

### Success Codes: 200

### Error Codes: `unauthorized` 401, `device_revoked` 403
