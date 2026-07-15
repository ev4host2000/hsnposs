import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'package:mizapos_desktop/services/database_runtime_profile.dart';

/// Cross-isolate / cross-process lock for a single sync cycle.
///
/// Design rules:
/// - **File exclusive lock** is the authority (shared by Foreground, WorkManager,
///   Manual, Scheduler). It does **not** hold a SQLite transaction open.
/// - **SQLite lease row** is short-lived metadata (heartbeat / observability).
///   Claim / heartbeat / release each use a brief `BEGIN EXCLUSIVE` txn only.
/// - Never wrap the full push/pull cycle in one SQLite transaction.
///
/// [SyncOutboxClaimer] remains defense-in-depth for row double-push.
class GlobalSyncLock {
  GlobalSyncLock._();

  static const int lockRowId = 1;
  static const String tableName = 'sync_global_lock';
  static const String lockFileName = 'global_sync.lock';

  /// Slightly above [SyncEngine] cycle timeout (5m) so live holders stay valid.
  static const Duration defaultLeaseTtl = Duration(minutes: 6);
  static const Duration heartbeatInterval = Duration(seconds: 30);

  /// Creates the lease table if missing (idempotent; no full DB version bump required).
  static Future<void> ensureSchema(DatabaseExecutor db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS $tableName (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  holder_id TEXT NOT NULL,
  trigger_name TEXT,
  acquired_at TEXT NOT NULL,
  heartbeat_at TEXT NOT NULL,
  expires_at TEXT NOT NULL
)
''');
  }

  static Future<String> lockFilePath() async {
    final dir = await DatabaseRuntimeConfig.databaseDirectory();
    final locksDir = Directory(p.join(dir, 'locks'));
    if (!locksDir.existsSync()) {
      await locksDir.create(recursive: true);
    }
    return p.join(locksDir.path, lockFileName);
  }

  /// True when another isolate/process currently holds the **file** lock.
  ///
  /// SQLite lease alone is never used to block — it is metadata/heartbeat only,
  /// so a crashed process cannot leave a permanent false-busy state.
  static Future<bool> isBusy(Database db) async {
    await ensureSchema(db);
    final path = await lockFilePath();
    final file = File(path);
    if (!await file.exists()) return false;

    RandomAccessFile? probe;
    try {
      probe = await file.open(mode: FileMode.write);
      await probe.lock(FileLock.exclusive);
      await probe.unlock();
      return false;
    } on FileSystemException {
      return true;
    } finally {
      await probe?.close();
    }
  }

  /// Attempts to acquire the global lock. Returns `null` if another isolate/process
  /// already holds it. Does **not** wait / queue.
  static Future<GlobalSyncLockHandle?> tryAcquire({
    required Database db,
    required String ownerId,
    String? trigger,
    Duration leaseTtl = defaultLeaseTtl,
  }) async {
    final trimmedOwner = ownerId.trim();
    if (trimmedOwner.isEmpty) {
      throw ArgumentError('ownerId must not be empty');
    }

    await ensureSchema(db);
    final path = await lockFilePath();
    final lockFile = File(path);
    if (!await lockFile.exists()) {
      await lockFile.create(recursive: true);
    }

    RandomAccessFile? raf;
    try {
      raf = await lockFile.open(mode: FileMode.write);
      await raf.lock(FileLock.exclusive);
    } on FileSystemException {
      await raf?.close();
      if (kDebugMode) {
        debugPrint('GlobalSyncLock: file lock busy (owner tried=$trimmedOwner)');
      }
      return null;
    }

    try {
      final now = DateTime.now().toUtc();
      final expires = now.add(leaseTtl);
      await db.transaction((txn) async {
        await txn.delete(tableName, where: 'id = ?', whereArgs: [lockRowId]);
        await txn.insert(tableName, <String, Object?>{
          'id': lockRowId,
          'holder_id': trimmedOwner,
          'trigger_name': trigger,
          'acquired_at': now.toIso8601String(),
          'heartbeat_at': now.toIso8601String(),
          'expires_at': expires.toIso8601String(),
        });
      }, exclusive: true);
    } catch (e, st) {
      try {
        await raf.unlock();
      } catch (_) {}
      await raf.close();
      if (kDebugMode) {
        debugPrint('GlobalSyncLock: SQLite lease claim failed: $e\n$st');
      }
      return null;
    }

    final handle = GlobalSyncLockHandle._(
      db: db,
      ownerId: trimmedOwner,
      trigger: trigger,
      file: raf,
      leaseTtl: leaseTtl,
    );
    handle._startHeartbeat();
    if (kDebugMode) {
      debugPrint(
        'GlobalSyncLock: acquired owner=$trimmedOwner trigger=$trigger',
      );
    }
    return handle;
  }

  static String newOwnerId({String prefix = 'sync'}) {
    final rnd = Random.secure().nextInt(1 << 32).toRadixString(16);
    return '$prefix-${IsolateIdentity.current}-$rnd';
  }
}

/// Stable-ish identity for this Dart isolate (not a platform PID).
abstract final class IsolateIdentity {
  static final String current = Isolate.current.hashCode.toRadixString(16);
}

/// Held lock — must [release] in a `finally` after the sync cycle.
class GlobalSyncLockHandle {
  GlobalSyncLockHandle._({
    required Database db,
    required this.ownerId,
    required this.trigger,
    required RandomAccessFile file,
    required Duration leaseTtl,
  })  : _db = db,
        _file = file,
        _leaseTtl = leaseTtl;

  final Database _db;
  final String ownerId;
  final String? trigger;
  final RandomAccessFile _file;
  final Duration _leaseTtl;

  Timer? _heartbeat;
  bool _released = false;

  void _startHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(GlobalSyncLock.heartbeatInterval, (_) {
      unawaited(_heartbeatOnce());
    });
  }

  Future<void> _heartbeatOnce() async {
    if (_released) return;
    try {
      final now = DateTime.now().toUtc();
      final expires = now.add(_leaseTtl);
      await _db.transaction((txn) async {
        await txn.update(
          GlobalSyncLock.tableName,
          <String, Object?>{
            'heartbeat_at': now.toIso8601String(),
            'expires_at': expires.toIso8601String(),
          },
          where: 'id = ? AND holder_id = ?',
          whereArgs: [GlobalSyncLock.lockRowId, ownerId],
        );
      }, exclusive: true);
    } on Object catch (e) {
      if (kDebugMode) {
        debugPrint('GlobalSyncLock: heartbeat failed owner=$ownerId: $e');
      }
    }
  }

  Future<void> release() async {
    if (_released) return;
    _released = true;
    _heartbeat?.cancel();
    _heartbeat = null;

    try {
      await _db.transaction((txn) async {
        await txn.delete(
          GlobalSyncLock.tableName,
          where: 'id = ? AND holder_id = ?',
          whereArgs: [GlobalSyncLock.lockRowId, ownerId],
        );
      }, exclusive: true);
    } on Object catch (e) {
      if (kDebugMode) {
        debugPrint('GlobalSyncLock: lease release failed: $e');
      }
    }

    try {
      await _file.unlock();
    } on Object catch (_) {}
    try {
      await _file.close();
    } on Object catch (_) {}

    if (kDebugMode) {
      debugPrint('GlobalSyncLock: released owner=$ownerId');
    }
  }
}
