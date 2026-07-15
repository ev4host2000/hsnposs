import 'dart:convert';

import 'package:mizapos_desktop/services/cloud/sync/models/sync_changelog_entry.dart';
import 'package:sqflite/sqflite.dart';

/// Persists product pull entries deferred until category/unit masters exist.
class SyncDeferredPullStore {
  SyncDeferredPullStore();

  static const String tableName = 'sync_deferred_pull';
  static const String reasonMissingCategory = 'missing_category';
  static const String reasonMissingUnit = 'missing_unit';
  static const String reasonAwaitingDependency = 'awaiting_dependency';


  Future<void> upsert({
    required DatabaseExecutor txn,
    required String organizationId,
    required String branchId,
    required String scopeKey,
    required SyncChangelogEntry entry,
    required String reason,
  }) async {
    final now = DateTime.now().toIso8601String();
    await txn.insert(
      tableName,
      {
        'id': entry.entityId,
        'organization_id': organizationId,
        'branch_id': branchId,
        'scope_key': scopeKey,
        'sequence': entry.sequence,
        'entity_type': entry.entityType,
        'entity_id': entry.entityId,
        'entry_json': jsonEncode(entry.toJson()),
        'reason': reason,
        'created_at': now,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<SyncChangelogEntry>> listForScope({
    required DatabaseExecutor txn,
    required String organizationId,
    required String branchId,
    required String scopeKey,
  }) async {
    final rows = await txn.query(
      tableName,
      where: 'organization_id = ? AND branch_id = ? AND scope_key = ?',
      whereArgs: [organizationId, branchId, scopeKey],
      orderBy: 'sequence ASC',
    );
    return rows.map(_rowToEntry).toList();
  }

  Future<void> remove({
    required DatabaseExecutor txn,
    required String entityId,
  }) async {
    await txn.delete(
      tableName,
      where: 'id = ?',
      whereArgs: [entityId],
    );
  }

  SyncChangelogEntry _rowToEntry(Map<String, Object?> row) {
    final raw = row['entry_json'];
    if (raw is String && raw.isNotEmpty) {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return SyncChangelogEntry.fromJson(decoded);
      }
      if (decoded is Map) {
        return SyncChangelogEntry.fromJson(Map<String, dynamic>.from(decoded));
      }
    }
    return SyncChangelogEntry(
      sequence: (row['sequence'] as int?) ?? 0,
      entityType: (row['entity_type'] ?? '').toString(),
      entityId: (row['entity_id'] ?? '').toString(),
      operation: 'update',
      payloadJson: const {},
      rowVersion: 1,
    );
  }
}
