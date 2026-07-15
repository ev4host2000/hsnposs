import 'package:mizapos_desktop/services/cloud/sync/catalog_entity_sync_repository.dart';
import 'package:mizapos_desktop/services/cloud/sync/requests/catalog_push_request.dart';
import 'package:mizapos_desktop/services/cloud/sync/responses/catalog_push_response.dart';
import 'package:mizapos_desktop/services/cloud/sync/sync_push_batch_outcome.dart';
import 'package:mizapos_desktop/services/cloud/sync/sync_push_partial_settler.dart';
import 'package:uuid/uuid.dart';

class CatalogEntityPushResult {
  const CatalogEntityPushResult({
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

/// Push worker for a single catalog entity type.
class CatalogEntityPushWorker {
  CatalogEntityPushWorker({
    required CatalogEntitySyncRepository repository,
    Uuid? uuid,
  })  : _repository = repository,
        _uuid = uuid ?? const Uuid();

  final CatalogEntitySyncRepository _repository;
  final Uuid _uuid;

  String get entityType => _repository.entityType;

  Future<CatalogEntityPushResult> run({
    required String companyId,
    required String branchId,
    required String deviceId,
    int batchLimit = 50,
  }) async {
    final pending = await _repository.fetchPending(limit: batchLimit);
    if (pending.isEmpty) {
      return const CatalogEntityPushResult(
        pushed: 0,
        duplicates: 0,
        batchId: '',
      );
    }

    final claimedIds = pending.map((e) => e.id).toList();
    var settled = false;
    try {
      final batchId = _uuid.v4();
      final request = CatalogPushRequest(
        companyId: companyId,
        branchId: branchId,
        deviceId: deviceId,
        batchId: batchId,
        events: pending.map((row) => row.toPushEvent()).toList(),
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
              claimedCount: claimedIds.length,
              rejectedEventCount: data.rejectedEvents.length,
            )) {
          // Settle then continue: do not throw — pull must still run
          // (version_conflict recovery depends on pull applying cloud state).
          await SyncPushPartialSettler.settle(
            claimedIds: claimedIds,
            rejectedEvents: data.rejectedEvents,
            accepted: data.accepted,
            duplicates: data.duplicates,
            batchId: data.batchId.isNotEmpty ? data.batchId : batchId,
            markFailed: _repository.markOutboxFailed,
            markSynced: _repository.markOutboxSynced,
            releaseClaims: _repository.releaseOutboxClaims,
            operationByOutboxId: {
              for (final row in pending) row.id: row.operation,
            },
          );
          settled = true;
          return CatalogEntityPushResult(
            pushed: data.accepted,
            duplicates: data.duplicates,
            batchId: data.batchId.isNotEmpty ? data.batchId : batchId,
            response: data,
          );
        }
        for (final row in pending) {
          await _repository.markOutboxFailed(row.id, code);
        }
        settled = true;
        throw CatalogSyncException(code);
      }

      final data = response.data!;
      if (SyncPushBatchOutcome.canSettleByRejectedEvents(
            claimedCount: claimedIds.length,
            rejectedEventCount: data.rejectedEvents.length,
          ) &&
          (data.rejected > 0 ||
              SyncPushBatchOutcome.isAmbiguousPartial(
                pendingCount: pending.length,
                accepted: data.accepted,
                duplicates: data.duplicates,
                rejected: data.rejected,
              ))) {
        // Settle rejected/accepted then continue so SyncEngine can pull.
        await SyncPushPartialSettler.settle(
          claimedIds: claimedIds,
          rejectedEvents: data.rejectedEvents,
          accepted: data.accepted,
          duplicates: data.duplicates,
          batchId: batchId,
          markFailed: _repository.markOutboxFailed,
          markSynced: _repository.markOutboxSynced,
          releaseClaims: _repository.releaseOutboxClaims,
          operationByOutboxId: {
            for (final row in pending) row.id: row.operation,
          },
        );
        settled = true;
        return CatalogEntityPushResult(
          pushed: data.accepted,
          duplicates: data.duplicates,
          batchId: batchId,
          response: data,
        );
      }
      if (SyncPushBatchOutcome.isFullyRejected(
        accepted: data.accepted,
        duplicates: data.duplicates,
        rejected: data.rejected,
      )) {
        for (final row in pending) {
          await _repository.markOutboxFailed(row.id, 'push_rejected');
        }
        settled = true;
        throw CatalogSyncException('push_rejected');
      }
      if (SyncPushBatchOutcome.isAmbiguousPartial(
        pendingCount: pending.length,
        accepted: data.accepted,
        duplicates: data.duplicates,
        rejected: data.rejected,
      )) {
        await _repository.releaseOutboxClaims(claimedIds);
        settled = true;
        throw CatalogSyncException('push_partial');
      }
      if (SyncPushBatchOutcome.canMarkAllSynced(
        pendingCount: pending.length,
        accepted: data.accepted,
        duplicates: data.duplicates,
        rejected: data.rejected,
        status: data.status,
      )) {
        await _repository.markOutboxSynced(
          outboxIds: claimedIds,
          batchId: batchId,
        );
        settled = true;
      } else {
        await _repository.releaseOutboxClaims(claimedIds);
        settled = true;
      }

      return CatalogEntityPushResult(
        pushed: data.accepted,
        duplicates: data.duplicates,
        batchId: batchId,
        response: data,
      );
    } on Object {
      if (!settled) {
        await _repository.releaseOutboxClaims(claimedIds);
      }
      rethrow;
    }
  }
}

class CatalogSyncException implements Exception {
  CatalogSyncException(this.code);

  final String code;

  @override
  String toString() => 'CatalogSyncException($code)';
}
