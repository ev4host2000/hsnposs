# sync/

طبقة **Sync Engine** — orchestration للمزامنة offline-first مع Miza Cloud.

## الغرض

- تنسيق PushWorker و PullWorker و ApplyService (بدون تعديل منطق `AccountingService` من الداخل).
- قراءة/كتابة `sync_outbox`, `sync_meta`, `sync_conflicts`.
- جدولة المزامنة: connectivity، app resume، periodic timer.
- سياسات التعارض (LWW، server wins) — قرارات فقط، التطبيق عبر `AccountingService`.

## ما يُوضَع هنا لاحقاً

- `SyncEngine` — نقطة دخول واحدة.
- Outbox writer (hook post-commit).
- Conflict handler و dead-letter محلي.

## ما **لا** يُوضَع هنا

- HTTP clients (`api/`).
- JWT refresh (`auth/`).
- شاشات مؤشر حالة المزامنة (UI).

## تبعيات متوقعة

- `repositories/` — outbox, meta, conflicts.
- `api/` — `/sync/push`, `/sync/pull`, `/sync/versions`.
- `auth/` + `devices/` — tokens + `device_id` في كل batch.
- `models/` — `SyncEvent`, `SyncBatch`, `PullDelta`.

## مبدأ

**SQLite محلي أولاً** — Sync Engine لا يكتب في PostgreSQL؛ يطبّق pull عبر دوال upsert في `AccountingService`.
