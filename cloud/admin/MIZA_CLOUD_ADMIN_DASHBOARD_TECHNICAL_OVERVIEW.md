# Miza Cloud Admin Dashboard Technical Overview

وثيقة هندسية تصف **لوحة العمليات (Ops Admin)** الحالية لنظام Miza Cloud كما هي منفّذة في المستودع، دون اقتراحات أو إعادة تصميم.

- **مسار الواجهة:** `cloud/admin/public/`
- **عنوان التشغيل:** `https://api.mizapos.com/admin/`
- **واجهة API:** `/v1/admin/*` (ومرادفها `/admin/*`)
- **تاريخ الوصف:** 2026-07-13

---

# 1. البنية العامة

## نوع التطبيق

تطبيق ويب ثابت (Static SPA بسيط) لإدارة عمليات المنصة داخلياً. لا يستخدم إطار واجهة (لا React ولا Vue ولا Angular). التبديل بين الشاشات يتم عبر إظهار/إخفاء أقسام DOM داخل صفحة HTML واحدة.

## التقنيات المستخدمة

| الطبقة | التقنية |
|--------|---------|
| الواجهة | HTML5 + CSS3 + JavaScript (Vanilla) |
| الخطوط | IBM Plex Sans Arabic (Google Fonts) |
| التخزين المحلي | `localStorage` لمفتاح الرمز `miza_ops_token` |
| الاتصال | `fetch` مع JSON و`Authorization: Bearer` |
| الخادم | PHP ≥ 8.2، مساحة أسماء `MizaCloud\` |
| التوجيه | موجه PHP مخصص (`Router`) عبر `AdminModule` |
| قاعدة البيانات | PostgreSQL عبر PDO |
| البريد | `SmtpMailer` بإعدادات `MAIL_*` |
| النشر | Docker Compose + nginx (يخدم الملفات الثابتة ويوجّه API) |

لا يوجد `package.json` أو bundler للوحة الإدارة.

## Architecture

```
المتصفح (admin/public)
    │  GET /admin/  → index.html + admin.css + admin.js
    │  REST JSON    → /v1/admin/*
    ▼
nginx (allowlist اختياري لـ /admin/ و /v1/admin/)
    ▼
PHP API — AdminModule
    ├── AdminController
    ├── AdminService
    ├── PlatformAdminBearer + JwtService
    └── Repositories (Admin / Sync / Observability / Beta)
            ▼
        PostgreSQL + ملفات التخزين (logs, rate_limit, media)
```

## Frontend

- ملف واحد لكل من: `index.html` (الهيكل والصفحات)، `admin.js` (المنطق)، `admin.css` (التنسيق).
- التوجيه من جهة العميل: دالة `setView(name)` بدون URL router (لا hash ولا history API للمسارات).
- الحالة العامة في الذاكرة: `selectedCompanyId`, `selectedCompany`, `plansCache`, `lastWelcomeCard`.

## Backend

- الوحدة: `cloud/api/src/Modules/Admin/`
- التسجيل في الحاوية والمسارات: `AdminModule.php`
- منطق الأعمال: `AdminService.php`
- نقاط الدخول HTTP: `AdminController.php`
- مستودعات البيانات: `AdminRepository`, `AdminSyncRepository`, `AdminObservabilityRepository`, `AdminBetaRepository`
- دعم: `WelcomeCardBuilder`, `BetaApprovalEmailBuilder`, `CreateTenantValidator`, `PlatformAdminBearer`

## Authentication

1. مشغّل واحد يُعرَّف عبر متغيرات البيئة:
   - `OPS_ADMIN_EMAIL`
   - `OPS_ADMIN_PASSWORD_HASH` (bcrypt)
   - `OPS_ADMIN_ACCESS_TTL` (افتراضي 3600 ثانية)
2. `POST /v1/admin/auth/login` يتحقق من البريد وكلمة المرور بـ `password_verify`.
3. يصدر JWT عبر `JwtService::issuePlatformAdminToken` بالنوع `token_type = platform_admin` والموضوع `sub = platform_admin`.
4. الواجهة تخزّن `access_token` في `localStorage` تحت `miza_ops_token`.
5. كل طلب لاحق يرسل `Authorization: Bearer <token>`.
6. عند التحميل تستدعي الواجهة `GET /me`؛ إن فشل التحقق تُمسح الجلسة المحلية وتُعرض شاشة الدخول.

## Authorization

- نطاقات الرمز الثابتة عند الإصدار: `platform:read` و `platform:write`.
- `PlatformAdminBearer` يرفض أي رمز ليس `token_type = platform_admin`.
- عمليات القراءة تتطلب `platform:read`.
- عمليات الكتابة (إنشاء، تعديل، حذف، موافقة، رفض، إلغاء جهاز…) تتطلب `platform:write`.
- لا يوجد نظام أدوار متعدد لمشغّلي Ops في التنفيذ الحالي؛ حساب واحد من الإعدادات.

---

# 2. جميع صفحات لوحة التحكم

الوصول لجميع الصفحات بعد تسجيل الدخول: حساب Ops المُعرَّف في البيئة فقط.

## 2.1 تسجيل الدخول (`login`)

| البند | الوصف |
|-------|--------|
| **الاسم** | Miza Cloud Ops — شاشة الدخول |
| **الهدف** | مصادقة مشغّل المنصة |
| **من يصل إليها** | أي زائر لـ `/admin/` قبل وجود رمز صالح؛ بعد فشل `/me` |
| **ما تعرضه** | حقل بريد، حقل كلمة مرور، زر دخول، رسالة خطأ |
| **العمليات** | إرسال النموذج → تخزين الرمز → فتح التطبيق |
| **الاتصال** | `POST /v1/admin/auth/login` |

## 2.2 لوحة التحكم (`dashboard`)

| البند | الوصف |
|-------|--------|
| **الاسم** | لوحة التحكم |
| **الهدف** | مركز عمليات يومي: مؤشرات، طلبات Beta، إنشاء متجر، أكواد دعوة، تنبيهات |
| **من يصل إليها** | مشغّل مصادق |
| **ما تعرضه** | حالة المنصة، 8 بطاقات KPI، جدول طلبات، نماذج إنشاء، أكواد، تنبيهات، ملخص سريع |
| **العمليات** | تحديث، موافقة/رفض طلب، إنشاء متجر، إنشاء كود، نسخ بطاقة ترحيب |
| **الاتصال** | `GET /dashboard` + `GET /signup-requests?status=pending` + `GET /vouchers` + مسارات الكتابة عند الإجراءات |

## 2.3 المتاجر (`companies`)

| البند | الوصف |
|-------|--------|
| **الاسم** | المتاجر |
| **الهدف** | عرض قائمة الشركات/المتاجر والبحث فيها |
| **من يصل إليها** | مشغّل مصادق |
| **ما تعرضه** | جدول: المتجر، المالك، الخطة، الأجهزة، الحالة، زر تفاصيل |
| **العمليات** | بحث، تحديث، فتح التفاصيل |
| **الاتصال** | `GET /companies` أو `GET /companies?q=` |

## 2.4 تفاصيل المتجر (`company-detail`)

| البند | الوصف |
|-------|--------|
| **الاسم** | تفاصيل المتجر (ليست في القائمة الجانبية) |
| **الهدف** | إدارة متجر واحد: حالة، خطة، اشتراك، أجهزة، مزامنة، حذف |
| **من يصل إليها** | مشغّل مصادق عبر زر «تفاصيل» |
| **ما تعرضه** | ملخص الشركة، صحة المزامنة، جدول الأجهزة |
| **العمليات** | حفظ خطة، تعليق/تفعيل/إغلاق، تمديد، إعادة كلمة مرور، بطاقة ترحيب، إلغاء جهاز، حذف نهائي |
| **الاتصال** | `GET /companies/{id}`, `/devices`, `/sync-health` ومسارات PATCH/POST/DELETE المرتبطة |

## 2.5 المزامنة (`sync`)

| البند | الوصف |
|-------|--------|
| **الاسم** | مراقبة المزامنة |
| **الهدف** | نظرة عامة على طابور المزامنة والأخطاء والتعارضات والأجهزة الغائبة |
| **من يصل إليها** | مشغّل مصادق |
| **ما تعرضه** | 4 بطاقات KPI + 3 جداول |
| **العمليات** | تحديث؛ فتح تفاصيل متجر من جهاز غائب |
| **الاتصال** | `GET /sync/overview`, `/sync/failures?limit=30`, `/sync/conflicts?status=pending&limit=30` |

## 2.6 النظام / Observability (`observability`)

| البند | الوصف |
|-------|--------|
| **الاسم** | مراقبة النظام |
| **الهدف** | صحة البنية التحتية والتنبيهات وسجل التدقيق |
| **من يصل إليها** | مشغّل مصادق |
| **ما تعرضه** | شريط حالة، بطاقات مقاييس، تنبيهات، بنية تحتية، جدول audit |
| **العمليات** | تحديث؛ تحميل audit بفلاتر Company ID و action |
| **الاتصال** | `GET /observability/overview`, `GET /audit-logs?...` |

---

# 3. Dashboard الرئيسية

لا توجد رسوم بيانية (charts) في التنفيذ الحالي. العرض يعتمد على بطاقات رقمية وجداول ونصوص.

## البطاقات (KPI)

تُبنى عبر `kpiCard(value, label, tone)` من حقل `summary` في `GET /dashboard`:

| البطاقة | المصدر | نبرة اللون |
|---------|--------|------------|
| متاجر نشطة | `active_companies` | ok |
| طلبات معلّقة | `pending_signups` | warn إن > 0 |
| أجهزة نشطة | `active_devices` | ok |
| أجهزة غائبة | `stale_devices` | warn إن > 0 |
| اشتراكات تنتهي | `subscriptions_expiring_30d` | warn إن > 0 |
| طابور المزامنة | `pending_sync_queue` | warn إن > 0 |
| أخطاء sync | `failed_sync_queue` | danger إن > 0 |
| تعارضات | `pending_conflicts` | warn إن > 0 |

## الإحصائيات في الملخص السريع

قائمة `#dash-quick-summary`:

- إجمالي المتاجر (`total_companies`)
- أجهزة نشطة
- طلبات اليوم (عدد الطلبات المعلّقة المعروضة حالياً)
- أكواد الدعوة (عدد كل الأكواد من `/vouchers`)
- البريد التلقائي: مفعّل / غير مُعدّ (`mail.configured`)

## الرسوم البيانية

لا يوجد أي رسم بياني أو مكتبة رسوم في `admin.js` / `admin.css` / `index.html`.

## المؤشرات

- **شريط الحالة** `#dash-status-pill`: `healthy` → سليم، `degraded` → متدهور، `critical` → حرج
- **سطر التحديث** `#dash-status-line`: آخر تحديث من `data.timestamp`
- **شارة الطلبات** `#dash-pending-badge`: عدد طلبات Beta المعلّقة
- **تنبيه البريد** `#dash-mail-hint`: يظهر إذا `mail.configured === false`
- **تنبيهات المنصة** `#dash-alerts`: حتى 8 عناصر من `data.alerts` مع severity `warning` أو `critical`

منطق الحالة في الخادم: إن DB غير متصل → `critical`؛ وإلا أي تنبيه `critical` → `critical`؛ وإلا تنبيه `warning` → `degraded`؛ وإلا `healthy`.

## الأزرار والعناصر التفاعلية في Dashboard

| العنصر | الوظيفة |
|--------|---------|
| ↻ تحديث | إعادة `loadDashboard()` |
| موافقة (لكل طلب) | نافذة كلمة مرور اختيارية ثم `POST .../approve` |
| رفض (لكل طلب) | نافذة سبب الرفض ثم `POST .../reject` |
| نسخ (بطاقة ترحيب الموافقة) | نسخ `lastWelcomeCard` للحافظة |
| إنشاء المتجر | `POST /companies` ثم عرض بطاقة ترحيب |
| نسخ (بطاقة ترحيب الإنشاء) | نسخ للحافظة |
| إنشاء الكود | `POST /vouchers` ثم إعادة تحميل Dashboard |

### قسم التفعيل والانضمام

جدول أعمدة: المتجر، البريد، الخطة، الكود، التاريخ، أزرار. عند الموافقة تظهر بطاقة ترحيب نصية قابلة للنسخ.

### أدوات التفعيل السريعة

**نموذج متجر جديد:** اسم المتجر، بريد المالك، اسم المالك (اختياري)، كلمة المرور (≥8)، الخطة، زر إنشاء.

**نموذج كود دعوة:** الكود، الخطة، عدد الاستخدامات (1–1000)، ملاحظات، زر إنشاء.

### أكواد الدعوة النشطة

يعرض أول 10 أكواد: الكود، الخطة، الاستخدام `used/max`، الحالة نشط/معطّل، تاريخ الانتهاء.

---

# 4. إدارة الشركات

تُدار عبر صفحتي **المتاجر** و**تفاصيل المتجر**، وإنشاء المتجر من Dashboard.

## البيانات المعروضة (القائمة)

- اسم المتجر
- بريد المالك
- رمز الخطة (`plan_code`)
- الأجهزة: `active_devices / max_devices`
- الحالة: `active` | `suspended` | `closed` (شارات ملونة)
- زر تفاصيل

## البيانات المعروضة (التفاصيل)

- الاسم، المالك (اسم + بريد)
- الخطة والاسم وحد الأجهزة
- الحالة
- Company ID مع زر نسخ
- بطاقة صحة المزامنة (إن وُجدت): انتظار، فاشل، تعارض، غائب، آخر sync
- جدول الأجهزة (انظر القسم 6)

## عمليات الإضافة

من Dashboard عبر `POST /companies` بالجسم:

```json
{
  "store_name": "...",
  "email": "...",
  "owner_name": "...",
  "password": "...",
  "plan_code": "business"
}
```

على الخادم يُنشأ: سجل `companies`، فرع افتراضي `MAIN`، مستخدم `role=owner`، `user_branch_access`، اشتراك `company_subscriptions` بحالة `active` لمدة سنة، ثم بطاقة ترحيب نصية.

بديل الإضافة: الموافقة على طلب Beta (`POST /signup-requests/{id}/approve`) التي تستدعي نفس مسار إنشاء المستأجر.

## التعديل

| العملية | المسار | الجسم |
|---------|--------|-------|
| تغيير الخطة | `PATCH /companies/{id}/subscription` | `{ "plan_code": "..." }` |
| الحالة | `PATCH /companies/{id}/status` | `{ "status": "active\|suspended\|closed" }` |
| تمديد الاشتراك | `PATCH /companies/{id}/subscription/extend` | `{ "days": N }` (الواجهة 1–365، الخادم يقبل حتى 3650) |
| إعادة كلمة مرور المالك | `POST /companies/{id}/reset-password` | `{ "password": "..." }` |
| بطاقة ترحيب | `GET /companies/{id}/welcome-card` | — |

## الحذف

- زر «حذف المتجر نهائياً» يفتح نافذة تتطلب:
  1. كتابة اسم المتجر مطابقاً
  2. كتابة `DELETE`
- الطلب: `DELETE /companies/{id}` مع `{ "confirm_name", "confirm_delete": "delete" }`
- الخادم يحذف بيانات الشركة بترتيب جداول محدد داخل معاملة (انظر القسم 15).

## البحث

- حقل `#company-search` مع debounce 350ms
- يرسل `q` إلى `GET /companies?q=`
- البحث على: اسم الشركة (ILIKE)، بريد المالك (ILIKE)، أو مطابقة تامة لـ Company UUID

## الفلاتر

لا توجد فلاتر حالة/خطة منفصلة في واجهة القائمة الحالية؛ الفلترة الوحيدة هي البحث النصي.

---

# 5. إدارة المستخدمين

لا توجد صفحة مستقلة بعنوان «المستخدمين» في لوحة Ops.

ما يوجد فعلياً بخصوص المستخدمين:

| الجانب | السلوك الحالي |
|--------|----------------|
| إنشاء مستخدم المالك | عند إنشاء متجر أو الموافقة على Beta؛ الدور `owner` |
| عرض المالك | في قائمة المتاجر وتفاصيل المتجر (اسم + بريد) |
| إعادة كلمة المرور | من تفاصيل المتجر فقط لمستخدم المالك |
| قائمة كل مستخدمي المنصة | غير موجودة في الواجهة |
| إنشاء/تعديل/حذف مستخدمين غير المالك | غير موجودة في واجهة Ops |
| أدوار داخل المتجر (غير owner) | لا تُدار من هذه اللوحة |

مقياس `total_users` يُحسب في Observability من جدول `users` لكنه لا يُعرض في بطاقات Dashboard الرئيسية (يُرجع ضمن مقاييس `/observability/overview`).

---

# 6. إدارة الأجهزة

تظهر داخل **تفاصيل المتجر**، وجزئياً في **المزامنة** (الأجهزة الغائبة).

## العرض في تفاصيل المتجر

أعمدة الجدول: الاسم، المنصة، الإصدار، آخر ظهور، الحالة، إجراء.

- الحالة: نشط أو ملغى
- علامة «غائب» إذا الجهاز نشط و`is_stale` من sync-health (آخر ظهور أقدم من 24 ساعة)

## العمليات

- **إلغاء جهاز:** زر «إلغاء» → تأكيد → `POST /devices/{id}/revoke`
- على الخادم عند الإلغاء:
  - `devices.status = revoked` و`revoked_at = now()`
  - إبطال `device_sessions`
  - إبطال `api_tokens` ذات `subject_type = device`
  - إبطال `refresh_tokens` المرتبطة بجلسات الجهاز

لا توجد في الواجهة: إضافة جهاز، تعديل اسم، أو إعادة تفعيل جهاز ملغى.

## الأجهزة الغائبة (صفحة المزامنة)

جدول: المتجر، الجهاز، المنصة، آخر ظهور، زر تفاصيل المتجر. المصدر: `stale_devices` ضمن `/sync/overview` (حد 30 في الخدمة).

---

# 7. التراخيص

## في لوحة Ops الحالية

لا توجد شاشة أو قائمة أو API تحت `/v1/admin` لإدارة سجلات `licenses` أو `license_device_slots` مباشرة (إنشاء/تعديل/عرض تراخيص).

## في قاعدة البيانات

الجداول `licenses` و`license_device_slots` موجودة في مخطط المنصة. عند الحذف النهائي لمتجر تُحذف صفوفهما ضمن سلسلة الحذف في `AdminRepository::deleteCompanyCompletely`.

## ما يمثّل الترخيص عملياً في اللوحة

التحكم التجاري يظهر عبر **خطط الاشتراك** `subscription_plans` وحد الأجهزة `max_devices`:

| code | name (من البذرة) | max_devices |
|------|------------------|-------------|
| trial | Trial — 14 days | 2 |
| starter | Starter | 3 |
| business | Business | 10 |
| enterprise | Enterprise | 50 |
| distributor_cloud | Distributor Cloud | (حسب البذرة) |

إنشاء المتجر يضبط اشتراكاً نشطاً لسنة؛ تغيير الخطة يحدّث `plan_id` للاشتراك النشط؛ لا يُنشئ مسار Admin الحالي صف `licenses` عند الإنشاء.

---

# 8. الاشتراكات

## النموذج

- جدول الخطط: `subscription_plans`
- جدول اشتراك الشركة: `company_subscriptions` بحالات تُستخدم في الاستعلامات: `trial`, `active` (وغيرها قد توجد في المخطط)
- عند الإنشاء: `status = active`، من `now()` إلى `now() + 1 year`، `auto_renew = true`

## في الواجهة

| المكان | السلوك |
|--------|--------|
| إنشاء متجر / كود دعوة | اختيار `plan_code` من الخطط النشطة (`GET /plans`) |
| تفاصيل المتجر | قائمة خطط + «حفظ الخطة» |
| تفاصيل المتجر | حقل أيام + «تمديد» → يمدّد `current_period_end` |
| Dashboard | عداد «اشتراكات تنتهي» خلال 30 يوماً |
| تنبيهات | نوع `subscription_expiring` للشركات التي ينتهي اشتراكها خلال 30 يوماً |

## APIs

- `GET /plans`
- `PATCH /companies/{id}/subscription` — تغيير الخطة
- `PATCH /companies/{id}/subscription/extend` — تمديد بالأيام

لا توجد في الواجهة شاشة قائمة بكل الاشتراكات أو فوترة أو إلغاء تجديد تلقائي.

---

# 9. المزامنة

## كيف تتم مراقبتها

1. تبويب **المزامنة** يستدعي نظرة عامة عالمية + أخطاء + تعارضات.
2. داخل تفاصيل كل متجر يُستدعى `GET /companies/{id}/sync-health`.
3. Dashboard يعكس أعداد الطابور/الأخطاء/التعارضات/الغائبين ضمن KPI والتنبيهات.

## ما الذي يظهر (صفحة المزامنة)

**بطاقات:** طابور انتظار، فاشل، تعارض، جهاز غائب (نبرات warn/danger حسب العتبات في الواجهة).

**جدول أجهزة غائبة (+24 ساعة):** متجر، جهاز، منصة، آخر ظهور، تفاصيل.

**جدول أخطاء المزامنة:** متجر، كيان/عملية، حالة، خطأ (`error_code` أو `error_detail`)، وقت `received_at`. المصدر: صفوف `sync_queue` بحالة `rejected` أو `conflict`.

**جدول تعارضات معلّقة:** متجر، كيان/عملية، نوع التعارض `conflict_kind`، حالة، وقت. المصدر: `sync_conflicts` مع `status=pending`.

## صحة المزامنة لكل متجر

من `companySyncHealth`:

- إحصاءات `sync_queue` مجمّعة حسب الحالة
- تعارضات pending/resolved
- ملخص `sync_changelog` (آخر حدث، آخر sequence، العدد، وآخر 15 حدثاً في الاستجابة — الواجهة تعرض حالياً بطاقات العدد و«آخر sync» فقط)
- قائمة أجهزة مع علم `is_stale`

## كيف يتم عرض الأخطاء

- شارات حمراء للحالة في جداول الأخطاء
- بطاقة KPI «فاشل» / «أخطاء sync»
- تنبيه `sync_failures` في Observability/Dashboard عندما `failed_queue > 0` (severity critical)
- تنبيه تراكم الطابور عند pending ≥ 50 (warning) أو ≥ 200 (critical)
- أخطاء طلبات الواجهة تظهر كـ Toast برسالة `payload.error.message`

لا توجد في الواجهة أزرار لإعادة محاولة عنصر طابور أو حل تعارض يدوياً.

---

# 10. السجلات Logs

## 1) سجل التدقيق (Audit Logs)

- الموقع: تبويب **النظام**
- المصدر: جدول `audit_logs` عبر `GET /audit-logs`
- الأعمدة المعروضة: الوقت، المتجر، الإجراء، الكيان، IP
- الفلاتر: `company_id`، `action` (ILIKE جزئي)، `limit` (الواجهة 40)، `offset` مدعوم في API
- سطر meta: `عرض N من total`

## 2) سجلات التطبيق (Application log file)

- تُقاس في Observability عبر قراءة ذيل ملف `app.log` (JSON سطور)
- المقاييس: حجم الملف؛ عدّاد مستويات `debug` / `info` / `warning` / `error` خلال الساعة الأخيرة
- الواجهة تعرض الحجم وعدد أخطاء الساعة ضمن بطاقة البنية التحتية
- لا توجد عارض سطور log كامل داخل اللوحة

## 3) سجلات/أحداث المزامنة

- `sync_changelog`: أحداث المزامنة (تُحسب كـ `sync_events_total`)
- `sync_queue`: عناصر الطابور وحالات الفشل
- `sync_conflicts`: التعارضات

## 4) لا يوجد

سجل مخصص لنشاط مشغّل Ops (من فعل ماذا من حسابات Ops متعددة) — غير منفّذ (مذكور في خارطة المرحلة 4 كمتخطّى).

---

# 11. Monitoring

المؤشرات المعروضة في تبويب **النظام** من `GET /observability/overview`:

| المؤشر | المعنى |
|--------|--------|
| متاجر نشطة | شركات `status = active` |
| أجهزة نشطة | أجهزة نشطة وغير ملغاة |
| أحداث sync | عدد صفوف `sync_changelog` |
| سجلات audit | عدد صفوف `audit_logs` |

إضافةً إلى ذلك تُرجع API (وقد تُستخدم في التنبيهات/الحسابات): `total_companies`, `total_users`.

تنبيهات المراقبة (`listAlerts`):

| kind | الشرط | severity |
|------|--------|----------|
| `subscription_expiring` | اشتراك trial/active ينتهي خلال 30 يوماً | warning |
| `sync_queue_backlog` | pending ≥ 50 (أو ≥ 200) | warning / critical |
| `stale_devices` | أجهزة غائبة > 0 | warning |
| `sync_failures` | أخطاء طابور > 0 | critical |

---

# 12. System Health

يظهر في نفس تبويب **النظام**:

## شريط الحالة العام

`healthy` / `degraded` / `critical` مع الطابع الزمني. المنطق: DB غير متصل → critical؛ وإلا وجود تنبيهات أو تحذيرات تخزين → degraded؛ وإلا healthy.

## البنية التحتية المعروضة في الواجهة

| البند | المحتوى |
|-------|---------|
| التطبيق | الاسم، البيئة، إصدار PHP |
| قاعدة البيانات | متصل + latency_ms، أو غير متصل |
| السجلات | حجم الملف + أخطاء/ساعة |
| مسارات التخزين | لكل من `logs`, `media`, `rate_limit`: قابل للكتابة ونسبة المساحة الحرة |

## ما تحسبه API أيضاً (جزئياً أوسع من العرض)

- `database.version`, `database.database_size`
- `storage.warnings` عند مساحة حرة < 10%
- معلومات التطبيق: `api_version`, `url`

---

# 13. الإعدادات

لا توجد صفحة «إعدادات» داخل لوحة Ops.

الإعدادات ذات الصلة تُدار خارج الواجهة:

| الإعداد | الموقع |
|---------|--------|
| بريد/كلمة مرور Ops | `OPS_ADMIN_*` في `.env` عبر `config/admin.php` |
| مدة الرمز | `OPS_ADMIN_ACCESS_TTL` |
| البريد SMTP | إعدادات `MAIL_*` عبر `SmtpMailer` — تظهر فقط كمؤشر «مفعّل/غير مُعدّ» |
| تقييد IP | `cloud/deploy/nginx/admin-allowlist.conf` (حالياً `allow all;`) |
| Rate limit العام لتسجيل دخول المستأجرين | `config/rate_limit.php` |

---

# 14. الأمان

## تسجيل الدخول

- بريد + كلمة مرور مقابل hash بيئي واحد
- إن لم تُضبط بيانات Ops → استجابة 503 `Platform admin is not configured`
- بيانات خاطئة → 401
- الواجهة تحمل `noindex, nofollow`

## الصلاحيات

- نطاقات JWT: `platform:read`, `platform:write`
- لا أدوار Ops متعددة

## Sessions

- لا يوجد جدول جلسات لـ Ops
- الجلسة = JWT في `localStorage`
- زر خروج يمسح الرمز محلياً فقط (لا استدعاء revoke على الخادم لرمز المنصة)

## Tokens

- نوع المطالبات: `token_type = platform_admin`
- `sub = platform_admin`
- `jti` UUID، `iat`/`exp` حسب TTL
- التحقق عبر `JwtService::decode` ثم فحص النوع والنطاقات

## Rate Limit

- الوسيط `RateLimitMiddleware` يقيّد مسارات تسجيل دخول **المستأجر**:
  - `/auth/login`, `/v1/auth/login`
  - `/auth/login/pairing`, `/v1/auth/login/pairing`
- **لا** يدرج `/v1/admin/auth/login` ضمن المسارات المحدودة
- الإعداد الافتراضي: مفعّل، 10 محاولات / 60 ثانية، تخزين ملفات تحت `storage/rate_limit`
- Observability يراقب قرص مجلد `rate_limit` كمسار تخزين فقط

## طبقات إضافية

- nginx allowlist لـ `/admin/` و`/v1/admin/`
- رفض رموز غير `platform_admin` على مسارات الإدارة

---

# 15. قاعدة البيانات

## جداول تعتمد عليها لوحة التحكم مباشرة (قراءة/كتابة عبر مستودعات Admin)

| الجدول | الاستخدام في Ops |
|--------|------------------|
| `companies` | قائمة، تفاصيل، حالة، حذف، إنشاء |
| `users` | المالك، إعادة كلمة المرور، فحص البريد |
| `branches` | فرع افتراضي عند الإنشاء |
| `user_branch_access` | ربط المالك بالفرع |
| `devices` | قائمة، إلغاء، أجهزة غائبة |
| `device_sessions` | إبطال عند إلغاء الجهاز |
| `api_tokens` | إبطال عند إلغاء الجهاز |
| `refresh_tokens` | إبطال عند إلغاء الجهاز |
| `subscription_plans` | الخطط |
| `company_subscriptions` | الخطة، التمديد، تنبيهات الانتهاء |
| `beta_signup_requests` | طلبات Beta |
| `activation_vouchers` | أكواد الدعوة |
| `sync_queue` | نظرة عامة وأخطاء |
| `sync_conflicts` | تعارضات |
| `sync_changelog` | صحة المزامنة ومقاييس الأحداث |
| `audit_logs` | سجل التدقيق |
| `information_schema.tables` | التحقق من وجود جدول قبل الحذف |

## جداول تُحذف مع الشركة (سلسلة الحذف) دون واجهة إدارة مباشرة لها

تتضمن من بين أخرى: فواتير ومشتريات ومرتجعات ومدفوعات ومخزون وشركاء ومنتجات وضرائب وقوائم أسعار وإشعارات وإعدادات و`licenses` و`license_device_slots` و`cloud_versions` و`sync_sequence_counters` وغيرها حسب ترتيب `orderedDeletes` في `AdminRepository`.

---

# 16. APIs

كل المسارات مسجّلة تحت البادئتين `/v1/admin` و`/admin`. الواجهة تستخدم `/v1/admin` فقط.

| Method | Path | Scope | الوظيفة |
|--------|------|-------|---------|
| POST | `/auth/login` | عام | دخول Ops |
| GET | `/me` | read | هوية الجلسة |
| GET | `/dashboard` | read | نظرة Dashboard |
| GET | `/plans` | read | الخطط النشطة |
| GET | `/companies` | read | قائمة (+ `q`) |
| POST | `/companies` | write | إنشاء متجر |
| GET | `/companies/{id}` | read | تفاصيل |
| GET | `/companies/{id}/welcome-card` | read | بطاقة ترحيب |
| PATCH | `/companies/{id}/status` | write | حالة الشركة |
| DELETE | `/companies/{id}` | write | حذف نهائي |
| PATCH | `/companies/{id}/subscription` | write | تغيير الخطة |
| PATCH | `/companies/{id}/subscription/extend` | write | تمديد |
| POST | `/companies/{id}/reset-password` | write | كلمة مرور المالك |
| GET | `/companies/{id}/devices` | read | أجهزة المتجر |
| GET | `/companies/{id}/sync-health` | read | صحة المزامنة |
| GET | `/signup-requests` | read | طلبات Beta (`status`) |
| POST | `/signup-requests/{id}/approve` | write | موافقة |
| POST | `/signup-requests/{id}/reject` | write | رفض |
| GET | `/vouchers` | read | أكواد الدعوة |
| POST | `/vouchers` | write | إنشاء كود |
| GET | `/sync/overview` | read | نظرة مزامنة + stale |
| GET | `/sync/failures` | read | أخطاء (`company_id`, `limit`) |
| GET | `/sync/conflicts` | read | تعارضات (`status`, `limit`) |
| GET | `/observability/overview` | read | صحة النظام |
| GET | `/audit-logs` | read | سجل تدقيق |
| POST | `/devices/{id}/revoke` | write | إلغاء جهاز |

صيغة الاستجابة الناجحة عبر `ResponseBuilder::success` بحقل `data`؛ الأخطاء عبر `ok: false` / كائن `error`.

---

# 17. الملفات المهمة

## الواجهة

| الملف | الوظيفة |
|-------|---------|
| `cloud/admin/public/index.html` | هيكل SPA وجميع اللوحات والنوافذ |
| `cloud/admin/public/admin.js` | المنطق الكامل للعميل |
| `cloud/admin/public/admin.css` | التنسيق والمكوّنات البصرية |
| `cloud/admin/README.md` | دليل التشغيل والإعداد |
| `cloud/admin/ROADMAP.md` | مراحل الإنجاز |

## Backend Admin

| الملف | الوظيفة |
|-------|---------|
| `AdminModule.php` | تسجيل الخدمات والمسارات |
| `Controllers/AdminController.php` | طبقة HTTP |
| `Services/AdminService.php` | منطق الأعمال والمصادقة |
| `Repositories/AdminRepository.php` | شركات، أجهزة، خطط، حذف |
| `Repositories/AdminSyncRepository.php` | مزامنة |
| `Repositories/AdminObservabilityRepository.php` | مقاييس، تنبيهات، audit، صحة |
| `Repositories/AdminBetaRepository.php` | طلبات وأكواد وتمديد |
| `Support/PlatformAdminBearer.php` | استخراج والتحقق من Bearer |
| `Support/WelcomeCardBuilder.php` | نص بطاقة الترحيب |
| `Support/BetaApprovalEmailBuilder.php` | رسائل موافقة/رفض |
| `Validators/CreateTenantValidator.php` | التحقق من إنشاء متجر |

## إعداد ونشر

| الملف | الوظيفة |
|-------|---------|
| `cloud/api/config/admin.php` | إعدادات Ops |
| `cloud/api/config/rate_limit.php` | إعدادات حد المحاولات |
| `cloud/api/src/Modules/Auth/Services/JwtService.php` | إصدار JWT للمنصة |
| `cloud/api/src/Core/Middleware/RateLimitMiddleware.php` | حد محاولات دخول المستأجر |
| `cloud/deploy/nginx/admin-allowlist.conf` | السماح بـ IP |
| `scripts/gen_ops_admin_hash.ps1` | توليد hash كلمة المرور |
| `scripts/add_ops_admin_ip.ps1` | إضافة IP للقائمة |

---

# 18. مجلدات المشروع

## جذر Miza Cloud (`cloud/`)

| المجلد/العنصر | الدور |
|---------------|--------|
| `admin/` | لوحة Ops موضوع هذه الوثيقة |
| `api/` | واجهة REST الكاملة للمنصة |
| `owner/` | لوحة المالك (منفصلة عن Ops) |
| `deploy/` | nginx وملفات النشر |
| `docs/` | وثائق معمارية للمنصة |
| `database/` | وثائق معمارية لقاعدة البيانات |
| `config/`, `helpers/`, `logs/`, `middleware/`, `modules/`, `repositories/`, `routes/`, `services/`, `storage/` | مجلدات هيكل/سقالة على مستوى `cloud/` (الفارغة أو شبه الفارغة ليست مصدر لوحة Ops) |
| `docker-compose*.yml`, `Dockerfile` | تشغيل الحاويات |

## هيكل لوحة الإدارة

```
cloud/admin/
├── README.md
├── ROADMAP.md
├── MIZA_CLOUD_ADMIN_DASHBOARD_TECHNICAL_OVERVIEW.md  (هذه الوثيقة)
└── public/
    ├── index.html
    ├── admin.js
    └── admin.css
```

## هيكل وحدة Admin في API

```
cloud/api/src/Modules/Admin/
├── AdminModule.php
├── Controllers/AdminController.php
├── Services/AdminService.php
├── Repositories/
│   ├── AdminRepository.php
│   ├── AdminSyncRepository.php
│   ├── AdminObservabilityRepository.php
│   └── AdminBetaRepository.php
├── Support/
│   ├── PlatformAdminBearer.php
│   ├── WelcomeCardBuilder.php
│   └── BetaApprovalEmailBuilder.php
└── Validators/CreateTenantValidator.php
```

## وحدات API الأخرى (سياق المنصة، ليست صفحات Ops)

`Auth`, `Branches`, `Catalog`, `Companies`, `Conflicts`, `Devices`, `Health`, `Invoices`, `Media`, `Notifications`, `Owner`, `PublicApi`, `Sync`, `Users`.

---

# 19. جميع المكونات Components

لا يوجد إطار مكوّنات. المكوّنات هي أقسام HTML + دوال JS مساعدة + أصناف CSS.

## لوحات الصفحات (Views)

| المكوّن | المعرّف | الوظيفة |
|---------|---------|---------|
| شاشة الدخول | `#login-view` | مصادقة |
| الهيكل الرئيسي | `#main-view` | شريط جانبي + محتوى |
| Dashboard | `#dashboard-view` | مركز العمليات |
| المتاجر | `#companies-view` | قائمة |
| تفاصيل متجر | `#company-detail-view` | إدارة متجر |
| المزامنة | `#sync-view` | مراقبة sync |
| النظام | `#observability-view` | صحة + audit |
| نافذة حوار | `#modal` | تأكيدات ونماذج قصيرة |
| Toast | `#toast` | رسائل مؤقتة |

## مكوّنات CSS الرئيسية

`.card`, `.login-shell`, `.login-card`, `.brand-mark`, `.app-shell`, `.sidebar`, `.nav-btn`, `.view-panel`, `.dash-hero`, `.status-pill`, `.hint-banner`, `.kpi-grid`, `.kpi-card`, `.panel-card`, `.count-badge`, `.tool-card`, `.welcome-result`, `.alert-item`, `.quick-list`, `.btn` (+ variants), `.badge`, `.modern-table`, `.search-input`, `.modal*`, `.toast`, `.infra-grid`, `.danger-zone`, `.actions-row`, `.id-row`.

## دوال بناء واجهة في JS

| الدالة | الوظيفة |
|--------|---------|
| `kpiCard` | بطاقة مؤشر |
| `openModal` / `closeModal` | حوار |
| `showToast` | إشعار |
| `statusBadgeClass` | صنف شارة الحالة |
| `planOptionsHtml` | خيارات الخطط |
| `renderCompanySyncHealth` | بطاقة صحة مزامنة المتجر |
| `escapeHtml` / `formatDate` / `formatBytes` | تنسيق وعرض آمن |

---

# 20. جميع الخدمات Services

## خادم (PHP)

| الخدمة/الصنف | الوظيفة |
|--------------|---------|
| `AdminService` | كل حالات استخدام Ops Admin |
| `JwtService` | ترميز/فك JWT وإصدار رمز المنصة |
| `SmtpMailer` | إرسال بريد الموافقة/الرفض |
| `WelcomeCardBuilder` | توليد نص بطاقة الترحيب |
| `BetaApprovalEmailBuilder` | محتوى بريد الموافقة والرفض |
| `CreateTenantValidator` | تحقق مدخلات إنشاء المستأجر |
| `PlatformAdminBearer` | مصادقة Bearer للمنصة |
| `AdminRepository` | وصول بيانات الشركات/الأجهزة/الخطط |
| `AdminSyncRepository` | وصول بيانات المزامنة |
| `AdminObservabilityRepository` | مقاييس وصحة وتنبيهات وaudit |
| `AdminBetaRepository` | Beta vouchers وطلبات وتمديد |

## عميل (دوال في `admin.js` تؤدي دور الخدمات)

| الدالة | الوظيفة |
|--------|---------|
| `api` | عميل HTTP موحّد |
| `getToken` / `setToken` | إدارة الرمز |
| `bootstrap` | استعادة الجلسة |
| `loadDashboard` | تحميل Dashboard |
| `loadCompanies` / `openCompany` | المتاجر والتفاصيل |
| `loadSyncDashboard` | صفحة المزامنة |
| `loadObservability` / `loadAuditLogs` | النظام والسجلات |
| `loadPlans` | تعبئة قوائم الخطط |
| `handleApproveSignup` / `handleRejectSignup` | مراجعة Beta |
| `bindCompanyDetailActions` | ربط أزرار تفاصيل المتجر |

---

# 21. تدفق البيانات

مثال عام لعرض قائمة المتاجر:

```
PostgreSQL (companies + joins)
    → AdminRepository::listCompanies
    → AdminService::listCompanies (بعد Bearer)
    → AdminController::listCompanies
    → ResponseBuilder JSON { ok, data: { companies } }
    → nginx
    → fetch في admin.js api('/companies')
    → loadCompanies يرسم صفوف #companies-tbody
```

مثال إنشاء متجر:

```
نموذج #create-form
    → POST /companies JSON
    → CreateTenantValidator
    → AdminRepository::createTenant (transaction)
    → WelcomeCardBuilder
    → JSON فيه welcome_card
    → showCreateWelcome في الواجهة + Toast
```

مثال مراقبة الصحة:

```
قراءات DB + فحص ملفات storage/logs
    → AdminObservabilityRepository
    → AdminService::observabilityOverview يحسب status
    → الواجهة تملأ الشريط والبطاقات و#obs-infra وaudit
```

---

# 22. الصلاحيات

## على مستوى Ops (لوحة التحكم)

| الكيان | الوصف |
|--------|--------|
| حساب Ops واحد | من `OPS_ADMIN_EMAIL` |
| Scope `platform:read` | قراءة جميع موارد `/v1/admin` المحمية للقراءة |
| Scope `platform:write` | جميع عمليات التعديل في Admin |
| لا Roles Ops متعددة | المرحلة 4 في ROADMAP معلّمة متخطاة |

## على مستوى مستأجري المنصة (كما تظهر في بيانات Ops)

عند الإنشاء يُنشأ مستخدم بدور ثابت:

| Role | الاستخدام في Admin |
|------|---------------------|
| `owner` | المستخدم المرتبط بالمتجر في الاستعلامات وإعادة كلمة المرور |

لا تُعرض أو تُدار أدوار أخرى (مثل موظف/محاسب) من لوحة Ops الحالية.

حالات الشركة المستخدمة في التفويض التشغيلي للوحة: `active`, `suspended`, `closed`.

---

# 23. جميع الصفحات غير المستخدمة إن وجدت

داخل تطبيق Ops SPA لا توجد ملفات HTML/صفحات ميتة إضافية؛ كل الأقسام التالية مستخدمة:

`login`, `dashboard`, `companies`, `company-detail`, `sync`, `observability`.

ملاحظات حدود النطاق (ليست صفحات داخل `cloud/admin` لكنها منفصلة):

- لوحة المالك `cloud/owner/` — تطبيق آخر
- مسارات Public Beta signup — خارج SPA الخاصة بـ Ops

لا يوجد عنصر قائمة يشير إلى صفحة غير موجودة.

---

# 24. جميع الوظائف غير المكتملة

استناداً إلى الكود و`ROADMAP.md` للوحة Ops:

| البند | الحالة |
|-------|--------|
| مستخدمو Ops متعددون + أدوار | غير منفّذ (مرحلة 4 متخطاة) |
| 2FA لمشغّل Ops | غير منفّذ |
| Kill switch لإيقاف sync لمتجر/جهاز | غير منفّذ |
| سجل نشاط Ops المخصص | غير منفّذ |
| واجهة إدارة تراخيص `licenses` | غير موجودة |
| واجهة إدارة مستخدمين عامة | غير موجودة |
| صفحة إعدادات داخل اللوحة | غير موجودة |
| رسوم بيانية | غير موجودة |
| حل/إعادة محاولة عناصر sync من الواجهة | غير موجودة |
| إبطال رموز Ops من الخادم عند الخروج | غير موجود |
| Rate limit على `/v1/admin/auth/login` | غير مطبّق في الوسيط الحالي |

ملاحظة: قسم «لاحقاً (Phase 4+)» في `README.md` يذكر عناصر (مراقبة sync queue، audit، metrics) بينما المراحل 2 و3 في `ROADMAP.md` تعلن إنجازها — التنفيذ الحالي يحتوي تبويبي المزامنة والنظام مع audit وmetrics.

---

# 25. جميع TODO الموجودة في المشروع

داخل نطاق لوحة Ops (`cloud/admin/**` و`cloud/api/src/Modules/Admin/**`):

- **لا توجد** تعليقات `TODO` / `FIXME` / `@todo` في ملفات الوحدة أو ملفات الواجهة.

الإشارات النصية غير المكتملة تظهر في الوثائق (`ROADMAP.md` المرحلة 4 متخطاة، وقسم «لاحقاً» في `README.md`) وليست تعليقات TODO في الشيفرة.

---

# 26. جميع الميزات الموجودة فعلاً

1. تسجيل دخول Ops ببريد وكلمة مرور بيئية  
2. جلسة JWT في المتصفح مع `/me`  
3. Dashboard بمؤشرات حالة وKPI وتنبيهات  
4. مراجعة طلبات Beta (موافقة/رفض) مع بريد اختياري  
5. إنشاء متجر يدوي مع بطاقة ترحيب  
6. إنشاء وعرض أكواد دعوة (`activation_vouchers`)  
7. قائمة متاجر مع بحث  
8. تفاصيل متجر: خطة، حالة، تمديد، كلمة مرور، ترحيب، حذف  
9. قائمة أجهزة لكل متجر مع إلغاء  
10. صحة مزامنة لكل متجر  
11. تبويب مراقبة المزامنة (طابور، أخطاء، تعارضات، غائبون)  
12. تبويب النظام (مقاييس، تنبيهات، بنية تحتية، audit بفلاتر)  
13. نوافذ تأكيد للحذف والإغلاق والموافقة/الرفض  
14. Toast ونسخ إلى الحافظة  
15. دعم مسارات API المزدوجة `/v1/admin` و`/admin`  
16. إعداد نشر nginx allowlist وسكربتات hash/IP  

---

# 27. جميع الميزات التي لم يتم تنفيذها

حسب `cloud/admin/ROADMAP.md` المرحلة 4 (متخطاة) وما يغيب عن الواجهة:

1. مستخدمو Ops متعددون وأدوار  
2. المصادقة الثنائية 2FA  
3. Kill switch للمزامنة  
4. سجل نشاط Ops التفصيلي  
5. شاشة إدارة تراخيص مستقلة  
6. شاشة إدارة مستخدمين مستقلة  
7. شاشة إعدادات داخل اللوحة  
8. رسوم بيانية ومخططات زمنية  
9. أدوات إصلاح sync (retry/resolve) من الواجهة  
10. فلترة قائمة المتاجر حسب الحالة/الخطة  
11. إدارة تعطيل/تعديل أكواد الدعوة من الواجهة (العرض والإنشاء فقط)  

---

# 28. قائمة بجميع Routes

## توجيه الواجهة (views)

| View id | عنصر DOM |
|---------|----------|
| `login` | `#login-view` |
| `dashboard` | `#dashboard-view` |
| `companies` | `#companies-view` |
| `company-detail` | `#company-detail-view` |
| `sync` | `#sync-view` |
| `observability` | `#observability-view` |

لا يوجد مسار URL فرعي لكل صفحة؛ العنوان الثابت هو `/admin/`.

## مسارات HTTP للإدارة

انظر الجدول الكامل في القسم 16 (26 مساراً وظيفياً × بادئتان).

مسارات نشر ثابتة ذات صلة:

- `GET /admin/` → ملفات `admin/public`
- بروكسي `/v1/admin/*` → حاوية API

---

# 29. قائمة بجميع Menus

القائمة الجانبية في `#main-view` (`.sidebar-nav`):

| الترتيب | `data-view` | التسمية العربية |
|---------|-------------|-----------------|
| 1 | `dashboard` | لوحة التحكم |
| 2 | `companies` | المتاجر |
| 3 | `sync` | المزامنة |
| 4 | `observability` | النظام |

عنصر إضافي خارج القائمة: زر **خروج** `#logout-btn`.

تفاصيل المتجر ليست عنصراً في القائمة؛ تُفتح من الجداول.

---

# 30. قائمة بجميع Widgets

«الودجات» هنا هي وحدات العرض القابلة لإعادة الاستخدام بصرياً في اللوحة:

| Widget | أين يظهر | الوظيفة |
|--------|----------|---------|
| Brand mark (`M`) | الدخول والشريط الجانبي | هوية بصرية |
| Status pill | Dashboard + النظام | حالة healthy/degraded/critical |
| Hint banner | Dashboard | تنبيه إعداد البريد |
| KPI card | Dashboard، Sync، تفاصيل sync-health، Observability | رقم + تسمية + نبرة |
| Count badge | قسم طلبات Beta | عدد معلّق |
| Panel card | أقسام المحتوى | حاوية قسم |
| Tool card | نماذج الإنشاء/الكود | نموذج أداة |
| Welcome result | بعد إنشاء/موافقة | بطاقة نصية + نسخ |
| Alerts stack | Dashboard + النظام | قائمة تنبيهات |
| Quick list | Dashboard | ملخص أزواج مفتاح/قيمة |
| Modern table | معظم الصفحات | جداول بيانات |
| Search input | المتاجر + فلاتر audit | بحث/فلترة |
| Badge | حالات شركة/جهاز/كود | تسمية حالة |
| Action group | أزرار موافقة/رفض | مجموعة أزرار صف |
| Modal | تأكيدات | حوار |
| Toast | عام | إشعار قصير |
| Infra definition list | النظام | تفاصيل بنية تحتية |
| Nav button | الشريط الجانبي | تنقل |

---

*نهاية الوثيقة — وصف للنظام الحالي فقط.*
