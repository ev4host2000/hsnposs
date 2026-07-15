import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:mizapos_desktop/services/cloud/sync/background/global_sync_lock.dart';
import 'package:mizapos_desktop/services/database_runtime_profile.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = await Directory.systemTemp
        .createTemp('mizapos_test_sqlite_global_sync_lock_');
    DatabaseRuntimeConfig.configureForTesting(
      profile: DatabaseRuntimeProfile.unitTest,
      directory: tempDir.path,
    );
    final dbPath = p.join(tempDir.path, 'lock_test.db');
    db = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(version: 1),
    );
    await GlobalSyncLock.ensureSchema(db);
  });

  tearDown(() async {
    await db.close();
    DatabaseRuntimeConfig.resetForTesting();
    try {
      await tempDir.delete(recursive: true);
    } on Object {
      /* ignore */
    }
  });

  test('second acquire in same isolate is rejected while first holds', () async {
    final a = await GlobalSyncLock.tryAcquire(
      db: db,
      ownerId: 'owner-a',
      trigger: 'manual',
    );
    expect(a, isNotNull);

    final b = await GlobalSyncLock.tryAcquire(
      db: db,
      ownerId: 'owner-b',
      trigger: 'background',
    );
    expect(b, isNull);
    expect(await GlobalSyncLock.isBusy(db), isTrue);

    await a!.release();
    expect(await GlobalSyncLock.isBusy(db), isFalse);

    final c = await GlobalSyncLock.tryAcquire(
      db: db,
      ownerId: 'owner-c',
      trigger: 'periodic',
    );
    expect(c, isNotNull);
    await c!.release();
  });

  test('SQLite lease uses short exclusive txns — cycle lock is file-based',
      () async {
    final handle = await GlobalSyncLock.tryAcquire(
      db: db,
      ownerId: 'owner-lease',
      trigger: 'scheduler',
    );
    expect(handle, isNotNull);

    // While lock is held, unrelated short transactions must still succeed
    // (file lock must NOT keep a multi-minute SQLite txn open).
    await db.transaction((txn) async {
      await txn.rawQuery('SELECT 1');
    });

    final rows = await db.query(GlobalSyncLock.tableName);
    expect(rows, hasLength(1));
    expect(rows.first['holder_id'], 'owner-lease');

    await handle!.release();
    final after = await db.query(GlobalSyncLock.tableName);
    expect(after, isEmpty);
  });

  test('cross-isolate: second isolate cannot acquire while first holds',
      () async {
    final lockPath = await GlobalSyncLock.lockFilePath();
    final dbPath = db.path;
    final dirPath = tempDir.path;

    final hold = await GlobalSyncLock.tryAcquire(
      db: db,
      ownerId: 'main-isolate',
      trigger: 'foreground',
    );
    expect(hold, isNotNull);

    final result = await Isolate.run(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      DatabaseRuntimeConfig.configureForTesting(
        profile: DatabaseRuntimeProfile.unitTest,
        directory: dirPath,
      );

      final childDb = await databaseFactory.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(version: 1),
      );
      try {
        await GlobalSyncLock.ensureSchema(childDb);
        final childLockPath = await GlobalSyncLock.lockFilePath();
        if (childLockPath != lockPath) {
          return 'lock_path_mismatch:$childLockPath!=$lockPath';
        }
        final child = await GlobalSyncLock.tryAcquire(
          db: childDb,
          ownerId: 'bg-isolate',
          trigger: 'background',
        );
        if (child != null) {
          await child.release();
          return 'acquired_while_busy';
        }
        return 'skipped_busy';
      } finally {
        await childDb.close();
      }
    });

    expect(result, 'skipped_busy');
    await hold!.release();

    final after = await Isolate.run(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      DatabaseRuntimeConfig.configureForTesting(
        profile: DatabaseRuntimeProfile.unitTest,
        directory: dirPath,
      );
      final childDb = await databaseFactory.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(version: 1),
      );
      try {
        final child = await GlobalSyncLock.tryAcquire(
          db: childDb,
          ownerId: 'bg-isolate-2',
          trigger: 'background',
        );
        if (child == null) return 'failed_after_release';
        await child.release();
        return 'ok';
      } finally {
        await childDb.close();
      }
    });
    expect(after, 'ok');
  });
}
