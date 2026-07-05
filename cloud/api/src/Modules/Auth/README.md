# Auth Module

تنفيذ `cloud/docs/contracts/01-authentication.md`

## Endpoints

| Method | Path | Auth |
|--------|------|------|
| POST | `/v1/auth/login` | لا |
| POST | `/v1/auth/token/refresh` | لا (refresh_token) |
| POST | `/v1/auth/logout` | Bearer + `auth:session` |
| GET | `/v1/auth/me` | Bearer |

نسخ بدون `/v1`: `/auth/login`, …

## بيانات التطوير (بعد `dev_seed.sql`)

| الحقل | القيمة |
|-------|--------|
| username | `owner@store.com` |
| password | `MizaTest123!` |
| company_id | `550e8400-e29b-41d4-a716-446655440000` |
| branch_id | `660e8400-e29b-41d4-a716-446655440001` |
| device_id | `770e8400-e29b-41d4-a716-446655440002` |
| installation_id | `a1b2c3d4-e5f6-7890-abcd-ef1234567890` |

## Postman

Import: `postman/Miza_Cloud_Auth.postman_collection.json`

## اختبار سريع

```powershell
.\test_auth.ps1
```

## Seed

```powershell
.\database\apply_dev_seed.ps1
```

## JWT

- HS256 — `config/jwt.php` + `JWT_SECRET` في `.env`
- Access → `api_tokens` (hash SHA-256)
- Refresh → `refresh_tokens` مع rotation
- Scopes حسب الدور — `RoleScopeResolver`
