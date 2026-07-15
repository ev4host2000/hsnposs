import 'package:sqflite/sqflite.dart';

/// كتابة آمنة لـ `sync_meta` — تتجنب UNIQUE عند السحب المتوازي.
abstract final class SyncMetaWriter {
  /// يحدّث `last_pulled_sequence` دون فقدان حقول الدفع عند التعارض.
  static Future<void> upsertLastPulledSequence(
    DatabaseExecutor txn, {
    required String organizationId,
    required String branchId,
    required String scopeKey,
    required int sequence,
  }) async {
    final now = DateTime.now().toIso8601String();
    await txn.execute(
      '''
      INSERT INTO sync_meta (
        organization_id, branch_id, scope_key,
        last_pulled_sequence, last_pushed_sequence,
        cloud_version_catalog, cloud_version_invoices, cloud_version_users,
        last_pulled_at, updated_at
      ) VALUES (?, ?, ?, ?, 0, 0, 0, 0, ?, ?)
      ON CONFLICT(organization_id, branch_id, scope_key) DO UPDATE SET
        last_pulled_sequence = excluded.last_pulled_sequence,
        last_pulled_at = excluded.last_pulled_at,
        updated_at = excluded.updated_at
      ''',
      [organizationId, branchId, scopeKey, sequence, now, now],
    );
  }

  /// يحدّث طوابع الدفع/السحب دون إعادة إنشاء صف متضارب.
  static Future<void> upsertTimestamps(
    DatabaseExecutor db, {
    required String organizationId,
    required String branchId,
    required String scopeKey,
    DateTime? lastPushedAt,
    DateTime? lastPulledAt,
  }) async {
    final now = DateTime.now().toIso8601String();
    final pushed = lastPushedAt?.toIso8601String();
    final pulled = lastPulledAt?.toIso8601String();
    await db.execute(
      '''
      INSERT INTO sync_meta (
        organization_id, branch_id, scope_key,
        last_pulled_sequence, last_pushed_sequence,
        cloud_version_catalog, cloud_version_invoices, cloud_version_users,
        last_pushed_at, last_pulled_at, updated_at
      ) VALUES (?, ?, ?, 0, 0, 0, 0, 0, ?, ?, ?)
      ON CONFLICT(organization_id, branch_id, scope_key) DO UPDATE SET
        last_pushed_at = COALESCE(excluded.last_pushed_at, sync_meta.last_pushed_at),
        last_pulled_at = COALESCE(excluded.last_pulled_at, sync_meta.last_pulled_at),
        updated_at = excluded.updated_at
      ''',
      [organizationId, branchId, scopeKey, pushed, pulled, now],
    );
  }
}
