# models/

**نماذج البيانات** (DTOs / value objects) لطبقة Miza Cloud — بدون I/O.

## الغرض

- structs immutable للـ API: tokens، device registration، sync batch، pull delta.
- enums: `SyncState`, `DeviceStatus`, `ConflictResolution`, `EntityScope`.
- parsing من/إلى JSON — pure functions أو factories.

## ما يُوضَع هنا لاحقاً

- `CloudSession`, `TokenPair`, `RegisteredDevice`.
- `SyncOutboxEntry`, `SyncMetaSnapshot`, `SyncConflict`.
- `PushBatchRequest`, `PullDeltaResponse`.

## ما **لا** يُوضَع هنا

- entities محاسبية (`models/entities.dart` في الجذر).
- استعلامات SQLite.
- Widgets أو localization.

## قاعدة

Models هنا **خاصة بالسحابة** — لا تستبدل `ProductEntity` ولا جداول POS المحلية.
