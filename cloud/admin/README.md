# Miza Cloud — لوحة العمليات (Ops Admin)

لوحة ويب داخلية لإدارة متاجر Beta بدون SQL يدوي.

## الوصول

- **الواجهة:** `https://api.mizapos.com/admin/`
- **API:** `POST /v1/admin/auth/login` ثم مسارات محمية بـ Bearer token

## الإعداد (مرة واحدة)

1. أنشئ hash لكلمة مرور المشغّل:

```powershell
.\scripts\gen_ops_admin_hash.ps1 -Password "YourSecurePassword"
```

2. أضف إلى `cloud/.env.staging`:

```
OPS_ADMIN_EMAIL=info@mizapos.com
OPS_ADMIN_PASSWORD_HASH=$2y$10$...
OPS_ADMIN_ACCESS_TTL=3600
```

> **Docker Compose:** إذا كان الـ hash يبدأ بـ `$2y$`، ضاعِف كل `$` إلى `$$` في ملف `.env.staging` (مثال: `$$2y$$10$$...`) وإلا يُفسَّر كمتغير compose.

3. أعد تشغيل حاوية API:

```bash
docker compose -f docker-compose.staging.yml --env-file .env.staging up -d --build api nginx
```

## الميزات (MVP + المرحلة 1)

| الميزة | الوصف |
|--------|--------|
| تسجيل دخول Ops | بريد + كلمة مرور من متغيرات البيئة |
| قائمة المتاجر + **بحث** | اسم، بريد، Company ID |
| تفاصيل متجر | IDs، أجهزة، **تعديل خطة**، **تعليق/تفعيل/إغلاق**، **حذف نهائي** |
| إنشاء متجر | + **بطاقة ترحيب** قابلة للنسخ |
| إلغاء جهاز | revoke + إبطال الجلسات والرموز |
| إعادة تعيين كلمة مرور المالك | من صفحة التفاصيل |
| حذف متجر | `DELETE /companies/{id}` مع تأكيد اسم المتجر + `DELETE` |

خارطة المراحل الكاملة: [`ROADMAP.md`](ROADMAP.md)

### المرحلة 2 — المزامنة

- تبويب **المزامنة**: طابور، أخطاء، تعارضات، أجهزة غائبة
- **صحة المزامنة** في تفاصيل كل متجر + آخر 15 حدث

### المرحلة 3 — النظام

- تبويب **النظام**: حالة المنصة، تنبيهات، DB، مساحة القرص، سجلات
- **Audit log** مع فلتر Company ID و action

## لاحقاً (Phase 4+)

- مراقبة sync queue
- audit log
- metrics و alerting

## الأمان

- لا تضع كلمة المرور plain text في `.env` — استخدم `OPS_ADMIN_PASSWORD_HASH` فقط.
- اللوحة للفريق الداخلي فقط.
- **تقييد IP مفعّل (RAP-P0-03):** `/admin/` و`/v1/admin/` محصورتان بقائمة مولّدة من `ADMIN_ALLOWED_IPS`.

### تقييد IP (nginx) — نشط

يولّد Nginx قائمة السماح عند بدء الحاوية من المتغير التالي في
`cloud/.env.staging`:

```dotenv
ADMIN_SECURITY_MODE=strict
ADMIN_ALLOWED_IPS=203.0.113.10,2001:db8::10
```

- استخدم عناوين IPv4/IPv6 دقيقة، مفصولة بفاصلة.
- يضيف النظام `127.0.0.1` و`::1` تلقائياً.
- لا تستخدم CIDR أو `allow all`.
- أي IP غير مدرج يحصل على **403 Forbidden**.
- المسارات العامة (`/v1/health`, `/v1/auth`, `/owner/`, …) غير متأثرة.

لإضافة IP، أضفه إلى القائمة. للحذف، احذفه منها. بعد حفظ `.env.staging`
أعد إنشاء خدمة Nginx وحدها:

```sh
cd /opt/mizapos/cloud
docker compose -f docker-compose.staging.yml --env-file .env.staging \
  up -d --force-recreate --no-deps nginx
docker compose -f docker-compose.staging.yml --env-file .env.staging \
  exec -T nginx nginx -t
```

لا يلزم build أو إعادة نشر API أو PostgreSQL. لا يكفي `nginx -s reload`
وحده، لأن متغير البيئة يُقرأ عند إنشاء الحاوية وتشغيل مولّد القائمة.

ومن جهاز الإدارة يمكن تنفيذ الإضافة أو الإزالة مع التحقق وإعادة إنشاء Nginx:

```powershell
.\scripts\add_ops_admin_ip.ps1 -Ip 203.0.113.10
.\scripts\add_ops_admin_ip.ps1 -Ip 203.0.113.10 -Action Remove
```
