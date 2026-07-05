import 'dart:convert';

import 'package:mizapos_mobile/services/cloud/sync/background/models/sync_status_snapshot.dart';
import 'package:mizapos_mobile/services/database_service.dart';

/// سجل مزامنة مستقل عن auditLogs.
class SyncLogger {
  SyncLogger({
    DatabaseService? databaseService,
    Future<Map<String, Object?>> Function()? contextProvider,
    int maxRows = maxLogRows,
  })  : _databaseService = databaseService ?? DatabaseService(),
        _contextProvider = contextProvider,
        _maxRows = maxRows;

  final DatabaseService _databaseService;
  final Future<Map<String, Object?>> Function()? _contextProvider;
  final int _maxRows;

  static const int maxLogRows = 10000;

  static const String pushStarted = 'push_started';
  static const String pushFinished = 'push_finished';
  static const String pullStarted = 'pull_started';
  static const String pullFinished = 'pull_finished';
  static const String retry = 'retry';
  static const String error = 'error';

  Future<void> log(
    String eventType, {
    String message = '',
    Map<String, Object?> details = const {},
  }) async {
    final db = await _databaseService.database;
    final merged = await _mergeDetails(details);
    await db.insert('sync_logs', {
      'event_type': eventType,
      'message': message,
      'details_json': merged.isEmpty ? null : jsonEncode(merged),
      'created_at': DateTime.now().toIso8601String(),
    });
    await _rotateLogs(db);
  }

  Future<Map<String, Object?>> _mergeDetails(
    Map<String, Object?> details,
  ) async {
    final merged = <String, Object?>{...details};
    final provider = _contextProvider;
    if (provider != null) {
      final ctx = await provider();
      for (final entry in ctx.entries) {
        merged.putIfAbsent(entry.key, () => entry.value);
      }
    }
    merged.removeWhere((_, value) => value == null);
    return merged;
  }

  Future<void> _rotateLogs(dynamic db) async {
    final countRows = await db.rawQuery('SELECT COUNT(*) AS c FROM sync_logs');
    final count = (countRows.first['c'] as int?) ?? 0;
    if (count <= _maxRows) return;
    final excess = count - _maxRows;
    await db.rawDelete(
      'DELETE FROM sync_logs WHERE id IN ('
      'SELECT id FROM sync_logs ORDER BY created_at ASC LIMIT ?'
      ')',
      [excess],
    );
  }

  Future<void> logPushStarted({SyncTrigger? trigger, int? pending}) {
    return log(
      pushStarted,
      message: 'Push started',
      details: {
        if (trigger != null) 'trigger': trigger.name,
        if (pending != null) 'pending': pending,
      },
    );
  }

  Future<void> logPushFinished({
    required int batches,
    required int pushed,
    SyncTrigger? trigger,
    String? batchId,
    String? requestId,
  }) {
    return log(
      pushFinished,
      message: 'Push finished',
      details: {
        'batches': batches,
        'pushed': pushed,
        if (trigger != null) 'trigger': trigger.name,
        if (batchId != null && batchId.isNotEmpty) 'batch_id': batchId,
        if (requestId != null && requestId.isNotEmpty) 'request_id': requestId,
      },
    );
  }

  Future<void> logPullStarted({SyncTrigger? trigger, String? requestId}) {
    return log(
      pullStarted,
      message: 'Pull started',
      details: {
        if (trigger != null) 'trigger': trigger.name,
        if (requestId != null && requestId.isNotEmpty) 'request_id': requestId,
      },
    );
  }

  Future<void> logPullFinished({
    required int applied,
    SyncTrigger? trigger,
    String? requestId,
  }) {
    return log(
      pullFinished,
      message: 'Pull finished',
      details: {
        'applied': applied,
        if (trigger != null) 'trigger': trigger.name,
        if (requestId != null && requestId.isNotEmpty) 'request_id': requestId,
      },
    );
  }

  Future<void> logRetry({
    required int attempt,
    required String phase,
    Object? cause,
    String? requestId,
  }) {
    return log(
      retry,
      message: 'Retry $attempt ($phase)',
      details: {
        'attempt': attempt,
        'phase': phase,
        if (cause != null) 'cause': cause.toString(),
        if (requestId != null && requestId.isNotEmpty) 'request_id': requestId,
      },
    );
  }

  Future<void> logError(
    Object err, {
    String? phase,
    String? requestId,
  }) {
    return log(
      error,
      message: err.toString(),
      details: {
        if (phase != null) 'phase': phase,
        if (requestId != null && requestId.isNotEmpty) 'request_id': requestId,
      },
    );
  }

  Future<List<Map<String, Object?>>> recentLogs({int limit = 50}) async {
    final db = await _databaseService.database;
    return db.query(
      'sync_logs',
      orderBy: 'created_at DESC',
      limit: limit,
    );
  }
}
