# repositories/

**الوصول إلى SQLite** لجداول Miza Cloud المحلية — outbox, meta, conflicts, devices.

## الغرض

- عزل SQL عن Sync Engine و Device services.
- CRUD على: `sync_outbox`, `sync_meta`, `sync_conflicts`, `sync_devices`.
- transactions: insert outbox + update meta atomically (لاحقاً).

## ما يُوضَع هنا لاحقاً

- `SyncOutboxRepository` — pending batch, mark pushed/synced.
- `SyncMetaRepository` — last_pulled_sequence, cloud_versions cache.
- `SyncConflictsRepository` — pending conflicts list.
- `SyncDevicesRepository` — self device row, list org devices.

## ما **لا** يُوضَع هنا

- HTTP (`api/`).
- منطق serialize payload (`sync/` + `AccountingService`).
- migrations (`DatabaseService` — خارج هذا المجلد).

## تبعيات متوقعة

- `DatabaseService` — مصدر `sqflite` connection.
- `models/` — mapping rows ↔ DTOs.
