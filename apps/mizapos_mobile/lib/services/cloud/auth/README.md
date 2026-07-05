# auth/

طبقة **المصادقة والجلسات** لـ Miza Cloud — منفصلة عن UI وعن `AccountingService`.

## الغرض

- تنسيق تسجيل الدخول السحابي، تجديد JWT، وربط جلسة المستخدم بجهاز مسجّل.
- إدارة access/refresh tokens في الذاكرة والتخزين الآمن (عبر `storage/`).
- التحقق من صلاحية الجلسة قبل أي طلب sync أو API.

## ما يُوضَع هنا لاحقاً (Phase لاحقة)

- خدمات/واجهات: login، refresh، logout، session state.
- Policy: متى يُعاد التسجيل بعد revoke أو انتهاء refresh.

## ما **لا** يُوضَع هنا

- منطق SQLite المحلي للمستخدمين (`AccountingService`).
- شاشات الدخول أو حوارات التفعيل.
- تنفيذ HTTP الخام (يذهب إلى `api/`).

## تبعيات متوقعة

- `devices/` — الجهاز يجب أن يكون مسجّلاً قبل JWT فعّال للمزامنة.
- `storage/` — حفظ tokens مشفّرة.
- `models/` — DTOs للجلسة والـ tokens.
