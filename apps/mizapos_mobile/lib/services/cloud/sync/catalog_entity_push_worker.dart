import 'package:mizapos_mobile/services/cloud/sync/catalog_entity_sync_repository.dart';
import 'package:mizapos_mobile/services/cloud/sync/requests/catalog_push_request.dart';
import 'package:mizapos_mobile/services/cloud/sync/responses/catalog_push_response.dart';
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
      final code = response.error?.code ?? 'push_failed';
      for (final row in pending) {
        await _repository.markOutboxFailed(row.id, code);
      }
      throw CatalogSyncException(code);
    }

    final data = response.data!;
    if (data.accepted > 0 ||
        data.duplicates > 0 ||
        data.status == 'duplicate') {
      await _repository.markOutboxSynced(
        outboxIds: pending.map((e) => e.id).toList(),
        batchId: batchId,
      );
    }

    return CatalogEntityPushResult(
      pushed: data.accepted,
      duplicates: data.duplicates,
      batchId: batchId,
      response: data,
    );
  }
}

class CatalogSyncException implements Exception {
  CatalogSyncException(this.code);

  final String code;

  @override
  String toString() => 'CatalogSyncException($code)';
}
