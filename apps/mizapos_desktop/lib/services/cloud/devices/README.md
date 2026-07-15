# devices/

طبقة **تسجيل الجهاز وإدارته** محلياً مقابل `devices` على Miza Cloud.

## الغرض

- ربط `installation_id` (من `DeviceBinding`) بـ `cloud_device_id` (UUID سحابي).
- قراءة/كتابة صف «هذا الجهاز» في جدول `sync_devices` (SQLite).
- تتبع حالة الجهاز: `active`، `revoked`، `pending_registration`.
- بناء `device_fingerprint` وmetadata (platform، app_version، os_name).

## ما يُوضَع هنا لاحقاً

- تسجيل أول مرة، re-register بعد reinstall.
- مزامنة قائمة أجهزة الشركة (للعرض في الإعدادات).
- ردود على revoke من لوحة التحكم.

## ما **لا** يُوضَع هنا

- توليد `installation_id` (يبقى في `DeviceBinding`).
- منطق Push/Pull (`sync/`).
- استدعاءات HTTP (`api/`).

## تبعيات متوقعة

- `repositories/` — CRUD على `sync_devices`.
- `auth/` — بعد التسجيل الناجح تُستلم tokens.
- `models/` — `CloudDevice`, `DeviceRegistrationResult`.
