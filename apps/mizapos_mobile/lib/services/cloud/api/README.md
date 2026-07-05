# api/

طبقة **ع clients HTTP** لـ Miza Cloud — عقود ومسارات فقط، بدون business logic.

## الغرض

- Base URL، timeouts، headers مشتركة (`Authorization`, `X-Device-Id`).
- Clients مجمّعة حسب المجال: auth، devices، sync.
- decode/encode JSON → models.
- mapping أخطاء HTTP → exceptions/domain errors.

## ما يُوضَع هنا لاحقاً

- `CloudApiClient` — wrapper على `http`.
- `AuthApi`, `DevicesApi`, `SyncApi` — paths و request/response typing.
- Retry idempotent (GET فقط) — ليس منطق sync.

## ما **لا** يُوضَع هنا

- قرارات متى نُزامِن (`sync/`).
- تخزين tokens (`storage/`).
- SQLite (`repositories/`).

## تبعيات متوقعة

- `models/` — DTOs للطلبات والاستجابات.
- `utils/` — parsing، error codes، constants.
- `auth/` — يزوّد Bearer token قبل كل call.

## مرجع

- Host: `api.mizapos.com` (أو override من config).
- لا تكرار عقود `field_*_api` القديمة — Miza Cloud API منفصل.
