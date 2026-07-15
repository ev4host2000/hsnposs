# Miza Cloud — Client Layer

هيكل Phase 3: **طبقة سحابية منفصلة** داخل `apps/mizapos_mobile/lib/services/cloud/`.

## الهدف

عزل كل ما يخص Miza Cloud (auth، devices، sync، API) عن:

- `AccountingService` — بوابة الكتابة المحلية (لا تُعدَّل من هنا).
- UI — الشاشات تستدعي facade رفيع لاحقاً فقط.
- APIs القديمة (`field_*_api`, `remote_signup_api`) — مسار ترخيص منفصل حتى الدمج.

## هيكل المجلدات

| المجلد | الوظيفة |
|--------|---------|
| `auth/` | JWT، refresh، session |
| `devices/` | registration، `sync_devices` |
| `sync/` | Sync Engine orchestration |
| `api/` | HTTP clients |
| `models/` | DTOs |
| `repositories/` | SQLite (outbox, meta, conflicts, devices) |
| `storage/` | tokens مشفّرة |
| `utils/` | constants، helpers |

## حالة Phase 3

- **هيكل + README فقط** — لا ملفات Dart بعد.
- **لا ربط** مع `main.dart` أو `AccountingService`.

## مراجع

- `cloud/docs/SYNC_ARCHITECTURE.md`
- `cloud/database/DATABASE_ARCHITECTURE.md`
- Device Registration design (Phase 2)
- Migration v46: `sync_outbox`, `sync_meta`, `sync_conflicts`, `sync_devices`
