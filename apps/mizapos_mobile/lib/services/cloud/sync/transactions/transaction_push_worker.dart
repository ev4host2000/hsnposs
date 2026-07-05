import 'package:mizapos_mobile/services/cloud/sync/requests/catalog_push_request.dart';
import 'package:mizapos_mobile/services/cloud/sync/responses/catalog_push_response.dart';
import 'package:mizapos_mobile/services/cloud/sync/transactions/transaction_sync_exception.dart';
import 'package:mizapos_mobile/services/cloud/sync/transactions/transaction_sync_repository.dart';
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
    if (valid.isEmpty) {
      return const TransactionPushResult(
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
      events: valid.map((row) => row.toPushEvent()).toList(),
    );

    final response = await _repository.pushRemote(
      request,
      idempotencyKey: batchId,
    );

    if (!response.ok || response.data == null) {
      final code = response.error?.code ?? 'push_failed';
      for (final row in valid) {
        await _repository.markOutboxFailed(row.id, code);
      }
      throw TransactionSyncException(code);
    }

    final data = response.data!;
    if (data.accepted > 0 ||
        data.duplicates > 0 ||
        data.status == 'duplicate') {
      await _repository.markOutboxSynced(
        outboxIds: valid.map((e) => e.id).toList(),
        batchId: batchId,
      );
    }

    return TransactionPushResult(
      pushed: data.accepted,
      duplicates: data.duplicates,
      batchId: batchId,
      response: data,
    );
  }
}
