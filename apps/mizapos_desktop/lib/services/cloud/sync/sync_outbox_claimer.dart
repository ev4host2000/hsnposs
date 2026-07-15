import 'package:sqflite/sqflite.dart';

/// Claims pending outbox rows atomically so dual sync runners cannot double-push.
///
/// Cycle-level mutual exclusion is [GlobalSyncLock] (file + short SQLite lease).
/// This claimer only serializes **row** updates inside a **short** transaction —
/// never hold an outbox claim txn across network I/O.
class SyncOutboxClaimer {
  SyncOutboxClaimer._();

  static const String syncStateInFlight = 'in_flight';
  static const Duration staleClaimTtl = Duration(minutes: 15);

  /// Marks up to [limit] pending rows as `in_flight` and returns only those
  /// successfully claimed by this caller.
  static Future<List<Map<String, Object?>>> claimPending({
    required Database db,
    required String entityType,
    required String pendingState,
    required int limit,
  }) async {
    final now = DateTime.now().toIso8601String();
    return db.transaction((txn) async {
      final rows = await txn.query(
        'sync_outbox',
        where: 'sync_state = ? AND entity_type = ?',
        whereArgs: [pendingState, entityType],
        orderBy: 'created_at ASC',
        limit: limit,
      );
      if (rows.isEmpty) return const [];

      final claimed = <Map<String, Object?>>[];
      for (final row in rows) {
        final id = (row['id'] ?? '').toString();
        if (id.isEmpty) continue;
        final updated = await txn.rawUpdate(
          'UPDATE sync_outbox SET sync_state = ?, updated_at = ? '
          'WHERE id = ? AND sync_state = ?',
          [syncStateInFlight, now, id, pendingState],
        );
        if (updated == 1) {
          claimed.add(row);
        }
      }
      return claimed;
    });
  }

  /// Returns stale `in_flight` rows to `pending` after a crash / killed worker.
  static Future<int> recoverStaleInFlight(
    Database db, {
    required String pendingState,
    Duration? olderThan,
  }) async {
    final ttl = olderThan ?? staleClaimTtl;
    final cutoff = DateTime.now().subtract(ttl).toIso8601String();
    final now = DateTime.now().toIso8601String();
    return db.rawUpdate(
      'UPDATE sync_outbox SET sync_state = ?, updated_at = ? '
      'WHERE sync_state = ? AND (updated_at IS NULL OR updated_at < ?)',
      [pendingState, now, syncStateInFlight, cutoff],
    );
  }

  /// Releases specific claimed rows back to `pending` (partial / abort / retry).
  static Future<int> releaseToPending(
    DatabaseExecutor db, {
    required List<String> outboxIds,
    required String pendingState,
  }) async {
    if (outboxIds.isEmpty) return 0;
    final now = DateTime.now().toIso8601String();
    final placeholders = List.filled(outboxIds.length, '?').join(',');
    return db.rawUpdate(
      'UPDATE sync_outbox SET sync_state = ?, updated_at = ?, last_sync_error = NULL '
      'WHERE id IN ($placeholders) AND sync_state = ?',
      [pendingState, now, ...outboxIds, syncStateInFlight],
    );
  }
}
