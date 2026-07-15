import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:mizapos_desktop/services/cloud/sync/background/global_sync_lock.dart';
import 'package:mizapos_desktop/services/cloud/sync/background/sync_engine.dart';
import 'package:mizapos_desktop/services/database_runtime_profile.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Must be top-level so [Isolate.run] does not capture the test's Database.
Future<String> p003IsolateTryAcquire({
  required String dirPath,
  required String dbPath,
  required String owner,
  required String trigger,
}) {
  return Isolate.run(() async {
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
      final handle = await GlobalSyncLock.tryAcquire(
        db: childDb,
        ownerId: owner,
        trigger: trigger,
      );
      if (handle == null) {
        return 'skipped:${SyncRunResult.skippedAlreadyRunning.message}';
      }
      await handle.release();
      return 'acquired';
    } finally {
      await childDb.close();
    }
  });
}

/// P0-03: Global Sync Lock coverage across simulated sync entry points.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Database db;
  late String dirPath;
  late String dbPath;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = await Directory.systemTemp
        .createTemp('mizapos_test_sqlite_p0_03_sync_lock_');
    dirPath = tempDir.path;
    DatabaseRuntimeConfig.configureForTesting(
      profile: DatabaseRuntimeProfile.unitTest,
      directory: dirPath,
    );
    dbPath = p.join(dirPath, 'lock_test.db');
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

  test('Manual + Background: background cannot acquire while manual holds',
      () async {
    final manual = await GlobalSyncLock.tryAcquire(
      db: db,
      ownerId: 'manual-fg',
      trigger: 'manual',
    );
    expect(manual, isNotNull);

    final background = await p003IsolateTryAcquire(
      dirPath: dirPath,
      dbPath: dbPath,
      owner: 'wm-bg',
      trigger: 'background',
    );
    expect(background, startsWith('skipped:'));
    expect(background, contains('global_sync_lock_busy'));

    await manual!.release();
  });

  test('Scheduler + Manual: second acquire rejected while first holds', () async {
    final scheduler = await GlobalSyncLock.tryAcquire(
      db: db,
      ownerId: 'scheduler',
      trigger: 'periodic',
    );
    expect(scheduler, isNotNull);

    final manual = await GlobalSyncLock.tryAcquire(
      db: db,
      ownerId: 'manual',
      trigger: 'manual',
    );
    expect(manual, isNull);
    expect(
      SyncRunResult.skippedAlreadyRunning.message,
      'global_sync_lock_busy',
    );

    await scheduler!.release();
  });

  test('WorkManager + Scheduler: cross-isolate mutual exclusion', () async {
    final wm = await GlobalSyncLock.tryAcquire(
      db: db,
      ownerId: 'workmanager',
      trigger: 'background',
    );
    expect(wm, isNotNull);

    final schedulerIso = await p003IsolateTryAcquire(
      dirPath: dirPath,
      dbPath: dbPath,
      owner: 'scheduler-iso',
      trigger: 'periodic',
    );
    expect(schedulerIso, startsWith('skipped:'));

    await wm!.release();
    final after = await p003IsolateTryAcquire(
      dirPath: dirPath,
      dbPath: dbPath,
      owner: 'scheduler-iso-2',
      trigger: 'periodic',
    );
    expect(after, 'acquired');
  });

  test('Rapid repeated tryAcquire: at most one holder', () async {
    final results = await Future.wait([
      for (var i = 0; i < 20; i++)
        GlobalSyncLock.tryAcquire(
          db: db,
          ownerId: 'burst-$i',
          trigger: i.isEven ? 'manual' : 'pendingOutbox',
        ),
    ]);

    final held = results.whereType<GlobalSyncLockHandle>().toList();
    expect(held, hasLength(1));
    expect(results.where((r) => r == null).length, 19);

    await held.single.release();
  });

  test('Cross-Isolate: two isolates blocked while main holds file lock', () async {
    final lockPath = await GlobalSyncLock.lockFilePath();
    final hold = await GlobalSyncLock.tryAcquire(
      db: db,
      ownerId: 'main',
      trigger: 'manual',
    );
    expect(hold, isNotNull);

    // Isolates probe the *file* lock only — avoid opening the same SQLite
    // connection from child isolates while the parent still holds it (Windows FFI).
    Future<bool> probeFileLock() => Isolate.run(() async {
          final file = File(lockPath);
          RandomAccessFile? raf;
          try {
            raf = await file.open(mode: FileMode.write);
            await raf.lock(FileLock.exclusive);
            await raf.unlock();
            return true; // acquired — would mean mutual exclusion failed
          } on FileSystemException {
            return false; // busy — expected while main holds
          } finally {
            await raf?.close();
          }
        });

    final probes = await Future.wait([probeFileLock(), probeFileLock()]);
    expect(probes, everyElement(isFalse));

    await hold!.release();

    final free = await Isolate.run(() async {
      final file = File(lockPath);
      RandomAccessFile? raf;
      try {
        raf = await file.open(mode: FileMode.write);
        await raf.lock(FileLock.exclusive);
        await raf.unlock();
        return true;
      } on FileSystemException {
        return false;
      } finally {
        await raf?.close();
      }
    });
    expect(free, isTrue);
  });

  test('isBusy reflects file lock across isolates', () async {
    expect(await GlobalSyncLock.isBusy(db), isFalse);
    final hold = await GlobalSyncLock.tryAcquire(
      db: db,
      ownerId: 'busy-probe',
      trigger: 'manual',
    );
    expect(hold, isNotNull);
    expect(await GlobalSyncLock.isBusy(db), isTrue);

    final busyFromChild = await Isolate.run(() async {
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
        return await GlobalSyncLock.isBusy(childDb);
      } finally {
        await childDb.close();
      }
    });
    expect(busyFromChild, isTrue);

    await hold!.release();
    expect(await GlobalSyncLock.isBusy(db), isFalse);
  });
}
