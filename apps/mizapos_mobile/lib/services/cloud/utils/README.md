# utils/

**أدوات مساعدة** مشتركة لطبقة `cloud/` — pure، بدون side effects.

## الغرض

- constants: API paths prefixes، header names، default timeouts.
- idempotency key builder: `device_id + entity_id + operation`.
- fingerprint hashing، clock skew helpers.
- mapping error codes سحابة → رسائل domain (ليس l10n UI).

## ما يُوضَع هنا لاحقاً

- `cloud_constants.dart` (paths only — no secrets).
- `sync_idempotency.dart`, `device_fingerprint.dart`.
- shared JSON/date helpers إن لم تكفي `utils/` الجذرية.

## ما **لا** يُوضَع هنا

- HTTP client (`api/`).
- business policies (`sync/`, `auth/`).

## تبعيات

- قد يُستورد من `utils/http_response_text.dart` في الجذر — دون نقل الملف.
