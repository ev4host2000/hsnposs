# core/

**النواة المشتركة** لطبقة Miza Cloud — تجميع نقاط الدخول، التسجيل (composition)، والسياسات العامة.

## الغرض

- ربط `CloudConfig` + `CloudHttpClient` + `CloudSecureStorage` في مكان واحد.
- توفير facade رفيع (`CloudModule` / `CloudRuntime`) لبقية التطبيق — لاحقاً.
- سياسات مشتركة: retry، correlation id، logging guards حسب `environment`.

## ما يُوضَع هنا لاحقاً

- تسجيل التبعيات (بدون Singleton عالمي — instance يُمرَّر من `main` أو provider).
- `CloudBootstrap` — تهيئة بعد `DatabaseService` وقبل Sync Engine.
- decorators على `CloudHttpClient` (auth header injection، request id).

## ما **لا** يُوضَع هنا

- منطق sync (`sync/`).
- endpoints محددة (`api/auth_api`, `sync_api` — ملفات لاحقة).
- SQLite (`repositories/`).
- UI أو شاشات.

## تبعيات

```
core/
  ├── config/     CloudConfig
  ├── api/        CloudHttpClient (impl)
  ├── storage/    CloudSecureStorage
  ├── auth/       session
  ├── devices/    registration
  └── sync/       engine
```

## حالة المرحلة الحالية

**README فقط** — لا ملفات Dart بعد.
