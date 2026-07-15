import 'dart:convert';

import 'package:mizapos_desktop/services/cloud/models/cloud_api_response.dart';
import 'package:mizapos_desktop/services/cloud/sync/catalog_entity_sync_api.dart';
import 'package:mizapos_desktop/services/cloud/sync/catalog_sync_constants.dart';
import 'package:mizapos_desktop/services/cloud/sync/catalog_sync_outbox_writer.dart';
import 'package:mizapos_desktop/services/cloud/sync/models/sync_changelog_entry.dart';
import 'package:mizapos_desktop/services/cloud/sync/models/sync_outbox_row.dart';
import 'package:mizapos_desktop/services/cloud/sync/requests/catalog_pull_request.dart';
import 'package:mizapos_desktop/services/cloud/sync/requests/catalog_push_request.dart';
import 'package:mizapos_desktop/services/cloud/sync/responses/catalog_pull_response.dart';
import 'package:mizapos_desktop/services/cloud/sync/responses/catalog_push_response.dart';
import 'package:mizapos_desktop/services/cloud/sync/sync_meta_writer.dart';
import 'package:mizapos_desktop/services/cloud/sync/sync_outbox_claimer.dart';
import 'package:mizapos_desktop/services/cloud/sync/sync_pull_apply.dart';
import 'package:mizapos_desktop/services/database_service.dart';
import 'package:sqflite/sqflite.dart';

typedef CatalogApplyEntry = Future<SyncPullApplyOutcome> Function(
  SyncChangelogEntry entry,
  DatabaseExecutor txn,
);

/// Shared outbox + sync_meta + remote API for a catalog master entity.
class CatalogEntitySyncRepository {
  CatalogEntitySyncRepository({
    required this.entityType,
    required this.scopeKey,
    required CatalogEntitySyncApi syncApi,
    required CatalogApplyEntry applyEntry,
    DatabaseService? databaseService,
  })  : _api = syncApi,
        _applyEntry = applyEntry,
        _db = databaseService ?? DatabaseService();

  final String entityType;
  final String scopeKey;
  final CatalogEntitySyncApi _api;
  final CatalogApplyEntry _applyEntry;
  final DatabaseService _db;

  DatabaseService get databaseService => _db;

  Future<List<SyncOutboxRow>> fetchPending({int limit = 50}) async {
    final db = await _db.database;
    final rows = await SyncOutboxClaimer.claimPending(
      db: db,
      entityType: entityType,
      pendingState: CatalogSyncConstants.syncStatePending,
      limit: limit,
    );

    return rows.map((row) => rowToOutbox(row, entityType)).toList();
  }

  Future<void> markOutboxSynced({
    required List<String> outboxIds,
    required String batchId,
  }) async {
    if (outboxIds.isEmpty) return;
    final db = await _db.database;
    final now = DateTime.now().toIso8601String();
    final placeholders = List.filled(outboxIds.length, '?').join(',');
    await db.rawUpdate(
      'UPDATE sync_outbox SET sync_state = ?, cloud_batch_id = ?, synced_at = ?, updated_at = ?, last_sync_error = NULL '
      'WHERE id IN ($placeholders)',
      [CatalogSyncConstants.syncStateSynced, batchId, now, now, ...outboxIds],
    );
  }

  Future<void> markOutboxFailed(String outboxId, String error) async {
    final db = await _db.database;
    final now = DateTime.now().toIso8601String();
    await db.update(
      'sync_outbox',
      {
        'sync_state': CatalogSyncConstants.syncStateFailed,
        'last_sync_error': error,
        'updated_at': now,
      },
      where: 'id = ?',
      whereArgs: [outboxId],
    );
  }

  Future<void> releaseOutboxClaims(List<String> outboxIds) async {
    if (outboxIds.isEmpty) return;
    final db = await _db.database;
    await SyncOutboxClaimer.releaseToPending(
      db,
      outboxIds: outboxIds,
      pendingState: CatalogSyncConstants.syncStatePending,
    );
  }

  Future<int> readLastPulledSequence({
    required String organizationId,
    required String branchId,
  }) async {
    final db = await _db.database;
    final rows = await db.query(
      'sync_meta',
      columns: const ['last_pulled_sequence'],
      where: 'organization_id = ? AND branch_id = ? AND scope_key = ?',
      whereArgs: [organizationId, branchId, scopeKey],
      limit: 1,
    );
    if (rows.isEmpty) return 0;
    return (rows.first['last_pulled_sequence'] as int?) ?? 0;
  }

  Future<void> writeLastPulledSequence({
    required String organizationId,
    required String branchId,
    required int sequence,
  }) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      await writeLastPulledSequenceTxn(
        txn,
        organizationId: organizationId,
        branchId: branchId,
        sequence: sequence,
      );
    });
  }

  Future<void> writeLastPulledSequenceTxn(
    DatabaseExecutor txn, {
    required String organizationId,
    required String branchId,
    required int sequence,
  }) {
    return SyncMetaWriter.upsertLastPulledSequence(
      txn,
      organizationId: organizationId,
      branchId: branchId,
      scopeKey: scopeKey,
      sequence: sequence,
    );
  }

  Future<CloudApiResponse<CatalogPushResponse>> pushRemote(
    CatalogPushRequest request, {
    String? idempotencyKey,
  }) {
    return _api.push(request, idempotencyKey: idempotencyKey);
  }

  Future<CloudApiResponse<CatalogPullResponse>> pullRemote(
    CatalogPullRequest request,
  ) {
    return _api.pull(request);
  }

  Future<SyncPullApplyOutcome> applyPulledEntry(
    SyncChangelogEntry entry,
    DatabaseExecutor txn,
  ) {
    return _applyEntry(entry, txn);
  }

  Future<bool> localRowExists(String table, String id) async {
    final db = await _db.database;
    final rows = await db.query(
      table,
      columns: const ['id'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<void> enqueue({
    required String operation,
    required String entityId,
    required String organizationId,
    required String branchId,
    required Map<String, dynamic> payload,
  }) {
    return CatalogSyncOutboxWriter.record(
      entityType: entityType,
      operation: operation,
      entityId: entityId,
      organizationId: organizationId,
      branchId: branchId,
      payload: payload,
      databaseService: _db,
      storage: CatalogSyncOutboxWriter.storage,
    );
  }

  static String? optionalString(Object? value) {
    if (value == null) return null;
    final s = value.toString().trim();
    return s.isEmpty ? null : s;
  }

  static double asDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static bool asBool(Object? value) {
    if (value is bool) return value;
    if (value is int) return value != 0;
    return value == true || value == 1 || value == '1' || value == 't';
  }

  static List<Map<String, dynamic>> decodeItems(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  static String encodeItems(List<Map<String, dynamic>> items) {
    return jsonEncode(items);
  }
}
