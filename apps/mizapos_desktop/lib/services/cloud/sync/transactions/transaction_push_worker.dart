import 'package:mizapos_desktop/services/cloud/sync/models/sync_outbox_row.dart';
import 'package:mizapos_desktop/services/cloud/sync/requests/catalog_push_request.dart';
import 'package:mizapos_desktop/services/cloud/sync/responses/catalog_push_response.dart';
import 'package:mizapos_desktop/services/cloud/sync/sync_push_batch_outcome.dart';
import 'package:mizapos_desktop/services/cloud/sync/sync_push_partial_settler.dart';
import 'package:mizapos_desktop/services/cloud/sync/transactions/transaction_sync_exception.dart';
import 'package:mizapos_desktop/services/cloud/sync/transactions/transaction_sync_repository.dart';
import 'package:uuid/uuid.dart';

class TransactionPushResult {
  const TransactionPushResult({
    required this.pushed,
    required this.duplicates,
    required this.batchId,
    this.response,
  });

  final int pushed;
  final int duplicates;
  final String batchId;
  final CatalogPushResponse? response;
}

/// Push worker for one registered transaction document type.
class TransactionPushWorker {
  TransactionPushWorker({
    required TransactionSyncRepository repository,
    Uuid? uuid,
  })  : _repository = repository,
        _uuid = uuid ?? const Uuid();

  final TransactionSyncRepository _repository;
  final Uuid _uuid;

  TransactionSyncRepository get repository => _repository;

  Future<TransactionPushResult> run({
    required String companyId,
    required String branchId,
    required String deviceId,
    int batchLimit = 50,
  }) async {
    final pending = await _repository.fetchPending(limit: batchLimit);
    if (pending.isEmpty) {
      return const TransactionPushResult(
        pushed: 0,
        duplicates: 0,
        batchId: '',
      );
    }

    final valid = pending.where(_repository.validateOutboxRow).toList();
    final validIdSet = valid.map((e) => e.id).toSet();
    final invalid = pending.where((row) => !validIdSet.contains(row.id)).toList();
    for (final row in invalid) {
      await _repository.markOutboxFailed(row.id, 'validation_failed');
    }
    if (valid.isEmpty) {
      return const TransactionPushResult(
        pushed: 0,
        duplicates: 0,
        batchId: '',
      );
    }

    final validIds = valid.map((e) => e.id).toList();
    var settled = false;
    try {
      final batchId = _uuid.v4();
      final request = CatalogPushRequest(
        companyId: companyId,
        branchId: branchId,
        deviceId: deviceId,
        batchId: batchId,
        events: valid.map((row) => row.toPushEvent()).toList(),
      );

      final response = await _repository.pushRemote(
        request,
        idempotencyKey: batchId,
      );

      if (!response.ok || response.data == null) {
        final data = response.data;
        final code = response.error?.code ?? 'push_failed';
        if (data != null &&
            SyncPushBatchOutcome.canSettleByRejectedEvents(
              claimedCount: validIds.length,
              rejectedEventCount: data.rejectedEvents.length,
            )) {
          await SyncPushPartialSettler.settle(
            claimedIds: validIds,
            rejectedEvents: data.rejectedEvents,
            accepted: data.accepted,
            duplicates: data.duplicates,
            batchId: data.batchId.isNotEmpty ? data.batchId : batchId,
            markFailed: _repository.markOutboxFailed,
            markSynced: _repository.markOutboxSynced,
            releaseClaims: _repository.releaseOutboxClaims,
            operationByOutboxId: {
              for (final row in valid) row.id: row.operation,
            },
          );
          settled = true;
          throw TransactionSyncException(code);
        }
        await _handlePushFailure(
          rows: valid,
          code: code,
          batchId: batchId,
        );
        settled = true;
        throw TransactionSyncException(code);
      }

      final data = response.data!;
      if (SyncPushBatchOutcome.canSettleByRejectedEvents(
            claimedCount: validIds.length,
            rejectedEventCount: data.rejectedEvents.length,
          ) &&
          (data.rejected > 0 ||
              SyncPushBatchOutcome.isAmbiguousPartial(
                pendingCount: valid.length,
                accepted: data.accepted,
                duplicates: data.duplicates,
                rejected: data.rejected,
              ))) {
        await SyncPushPartialSettler.settle(
          claimedIds: validIds,
          rejectedEvents: data.rejectedEvents,
          accepted: data.accepted,
          duplicates: data.duplicates,
          batchId: batchId,
          markFailed: _repository.markOutboxFailed,
          markSynced: _repository.markOutboxSynced,
          releaseClaims: _repository.releaseOutboxClaims,
          operationByOutboxId: {
            for (final row in valid) row.id: row.operation,
          },
        );
        settled = true;
        throw TransactionSyncException('partial_reject');
      }
      if (SyncPushBatchOutcome.isAmbiguousPartial(
        pendingCount: valid.length,
        accepted: data.accepted,
        duplicates: data.duplicates,
        rejected: data.rejected,
      )) {
        await _repository.releaseOutboxClaims(validIds);
        settled = true;
        throw TransactionSyncException('push_partial');
      }
      if (SyncPushBatchOutcome.canMarkAllSynced(
        pendingCount: valid.length,
        accepted: data.accepted,
        duplicates: data.duplicates,
        rejected: data.rejected,
        status: data.status,
      )) {
        await _repository.markOutboxSynced(
          outboxIds: validIds,
          batchId: batchId,
        );
        settled = true;
      } else {
        await _repository.releaseOutboxClaims(validIds);
        settled = true;
      }

      return TransactionPushResult(
        pushed: data.accepted,
        duplicates: data.duplicates,
        batchId: batchId,
        response: data,
      );
    } on Object {
      if (!settled) {
        await _repository.releaseOutboxClaims(validIds);
      }
      rethrow;
    }
  }

  /// Create-already-exists is treated as success so a following post can retry.
  Future<void> _handlePushFailure({
    required List<SyncOutboxRow> rows,
    required String code,
    required String batchId,
  }) async {
    if (code != 'conflict') {
      for (final row in rows) {
        await _repository.markOutboxFailed(row.id, code);
      }
      return;
    }

    final createIds = <String>[];
    final leavePendingIds = <String>[];
    for (final row in rows) {
      if (row.operation == 'create') {
        createIds.add(row.id);
      } else {
        // Leave post/void/update pending so the next sync can finish without
        // showing a false "already exists" failure on those ops.
        leavePendingIds.add(row.id);
      }
    }
    if (createIds.isNotEmpty) {
      await _repository.markOutboxSynced(
        outboxIds: createIds,
        batchId: batchId,
      );
      await _repository.releaseOutboxClaims(leavePendingIds);
    } else {
      for (final row in rows) {
        await _repository.markOutboxFailed(row.id, code);
      }
    }
  }
}
