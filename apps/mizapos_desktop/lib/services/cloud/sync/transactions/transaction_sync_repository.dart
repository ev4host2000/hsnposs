import 'dart:convert';

import 'package:mizapos_desktop/services/cloud/models/cloud_api_response.dart';
import 'package:mizapos_desktop/services/cloud/sync/models/sync_changelog_entry.dart';
import 'package:mizapos_desktop/services/cloud/sync/models/sync_outbox_row.dart';
import 'package:mizapos_desktop/services/cloud/sync/requests/catalog_pull_request.dart';
import 'package:mizapos_desktop/services/cloud/sync/requests/catalog_push_request.dart';
import 'package:mizapos_desktop/services/cloud/sync/responses/catalog_pull_response.dart';
import 'package:mizapos_desktop/services/cloud/sync/responses/catalog_push_response.dart';
import 'package:mizapos_desktop/services/cloud/sync/sync_meta_writer.dart';
import 'package:mizapos_desktop/services/cloud/sync/sync_outbox_claimer.dart';
import 'package:mizapos_desktop/services/cloud/sync/sync_pull_apply.dart';
import 'package:mizapos_desktop/services/cloud/sync/transactions/models/transaction_type_definition.dart';
import 'package:mizapos_desktop/services/cloud/sync/transactions/transaction_operation_dispatcher.dart';
import 'package:mizapos_desktop/services/cloud/sync/transactions/transaction_sync_api.dart';
import 'package:mizapos_desktop/services/cloud/sync/transactions/transaction_sync_constants.dart';
import 'package:mizapos_desktop/services/cloud/sync/transactions/transaction_validator.dart';
import 'package:mizapos_desktop/services/database_service.dart';
import 'package:sqflite/sqflite.dart';

/// Outbox + sync_meta + remote API for one transaction document type.
class TransactionSyncRepository {
  TransactionSyncRepository({
    required TransactionTypeDefinition typeDefinition,
    required TransactionSyncApi syncApi,
    TransactionOperationDispatcher? dispatcher,
    TransactionValidator? validator,
    DatabaseService? databaseService,
  })  : type = typeDefinition,
        _api = syncApi,
        _dispatcher = dispatcher ?? TransactionOperationDispatcher(),
        _validator = validator ?? const TransactionValidator(),
        _db = databaseService ?? DatabaseService();

  final TransactionTypeDefinition type;
  final TransactionSyncApi _api;
  final TransactionOperationDispatcher _dispatcher;
  final TransactionValidator _validator;
  final DatabaseService _db;

  String get entityType => type.entityType;
  String get scopeKey => type.scopeKey;

  DatabaseService get databaseService => _db;

  Future<List<SyncOutboxRow>> fetchPending({int limit = 50}) async {
    final db = await _db.database;
    final rows = await SyncOutboxClaimer.claimPending(
      db: db,
      entityType: entityType,
      pendingState: TransactionSyncConstants.syncStatePending,
      limit: limit,
    );
    return rows.map(_rowToOutbox).toList();
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
      [
        TransactionSyncConstants.syncStateSynced,
        batchId,
        now,
        now,
        ...outboxIds,
      ],
    );
  }

  Future<void> markOutboxFailed(String outboxId, String error) async {
    final db = await _db.database;
    final now = DateTime.now().toIso8601String();
    await db.update(
      'sync_outbox',
      {
        'sync_state': TransactionSyncConstants.syncStateFailed,
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
      pendingState: TransactionSyncConstants.syncStatePending,
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
    return _dispatcher.dispatchPullApply(
      entry: entry,
      type: type,
      txn: txn,
    );
  }

  /// Validates outbox row before push (framework rules only).
  bool validateOutboxRow(SyncOutboxRow row) {
    final result = _validator.validatePushPayload(
      operation: row.operation,
      payloadJson: row.payloadJson,
      entityId: row.entityId,
      entityType: row.entityType,
      idempotencyKey: row.idempotencyKey,
      clientRowVersion: row.clientRowVersion,
    );
    return result.ok;
  }

  SyncOutboxRow _rowToOutbox(Map<String, Object?> row) {
    final rawPayload = row['payload_json'];
    Map<String, dynamic> payload = const {};
    if (rawPayload is String && rawPayload.isNotEmpty) {
      final decoded = jsonDecode(rawPayload);
      if (decoded is Map) {
        payload = Map<String, dynamic>.from(decoded);
      }
    }

    return SyncOutboxRow(
      id: (row['id'] ?? '').toString(),
      entityType: entityType,
      organizationId: (row['organization_id'] ?? '').toString(),
      branchId: (row['branch_id'] ?? '').toString(),
      entityId: (row['entity_id'] ?? '').toString(),
      operation: (row['operation'] ?? '').toString(),
      payloadJson: payload,
      clientRowVersion: (row['client_row_version'] as int?) ?? 1,
      idempotencyKey: (row['idempotency_key'] ?? '').toString(),
      installationId: (row['installation_id'] ?? '').toString(),
    );
  }
}
