# Miza Cloud API

Backend معياري لـ `api.mizapos.com` — **هيكل فقط** في هذه المرحلة.

## المتطلبات

- PHP 8.2+
- Composer
- PostgreSQL 15+ (لاحقاً)

## التشغيل (لاحقاً)

```bash
cd cloud/api
composer install
cp .env.example .env
php -S 127.0.0.1:8787 -t public
```

## الهيكل

```
cloud/api/
├── public/index.php      # Front controller
├── bootstrap/app.php     # Application bootstrap
├── config/               # app, database, jwt, logging
├── routes/api.php        # تجميع مسارات عامة
├── src/
│   ├── Core/             # Router, Middleware, DB, HTTP, DI
│   └── Modules/          # Auth, Devices, Sync, …
├── storage/logs/
└── ARCHITECTURE.md
```

## الوثائق

- عقود REST: `cloud/docs/contracts/`
- قاعدة البيانات: `cloud/database/DATABASE_ARCHITECTURE.md`

## الحالة الحالية

- لا endpoints مُسجَّلة
- لا SQL
- لا منطق مصادقة/مزامنة
