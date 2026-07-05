# storage/

**تخزين آمن** لأسرار Miza Cloud — خارج SQLite.

## الغرض

- access_token / refresh_token — encrypted at rest.
- optional: last-known `device_id`, session expiry cache.
- wipe on logout, revoke, factory reset.

## ما يُوضَع هنا لاحقاً

- `CloudSecureStorage` — abstraction (Android Keystore / iOS Keychain / desktop fallback).
- migrate/clear helpers عند `AppLocalDataWiper`.

## ما **لا** يُوضَع هنا

- `installation_id` (يبقى في `.mizapos_device_id` via `DeviceBinding`).
- `sync_outbox` payloads (SQLite via `repositories/`).
- settings UI prefs (`store_settings.json`).

## أمان

- **لا** tokens في `sync_devices` أو audit logs.
- rotate: replace atomically on refresh.
