import 'package:mizapos_mobile/services/cloud/sync/transactions/transaction_pull_worker.dart';
import 'package:mizapos_mobile/services/cloud/sync/transactions/transaction_push_worker.dart';

/// Runs transaction push/pull workers in registration order.
class TransactionOrchestrator {
  TransactionOrchestrator._();

  static Future<({
    int pushed,
    int duplicates,
    String lastBatchId,
  })> runPushWorkers({
    required List<TransactionPushWorker> workers,
    required String companyId,
    required String branchId,
    required String deviceId,
    int batchLimit = 50,
  }) async {
    var totalPushed = 0;
    var totalDuplicates = 0;
    var lastBatchId = '';

    for (final worker in workers) {
      final result = await worker.run(
        companyId: companyId,
        branchId: branchId,
        deviceId: deviceId,
        batchLimit: batchLimit,
      );
      totalPushed += result.pushed;
      totalDuplicates += result.duplicates;
      if (result.batchId.isNotEmpty) lastBatchId = result.batchId;
    }

    return (
      pushed: totalPushed,
      duplicates: totalDuplicates,
      lastBatchId: lastBatchId,
    );
  }

  static Future<({
    int applied,
    int deferred,
    int entryCount,
    int maxSequence,
  })> runPullWorkers({
    required List<TransactionPullWorker> workers,
    required String companyId,
    required String branchId,
    int? limit,
  }) async {
    var totalApplied = 0;
    var totalDeferred = 0;
    var totalEntries = 0;
    var maxSequence = 0;

    for (final worker in workers) {
      final result = await worker.run(
        companyId: companyId,
        branchId: branchId,
        limit: limit,
      );
      totalApplied += result.applied;
      totalDeferred += result.deferred;
      totalEntries += result.entryCount;
      if (result.lastSequence > maxSequence) {
        maxSequence = result.lastSequence;
      }
    }

    return (
      applied: totalApplied,
      deferred: totalDeferred,
      entryCount: totalEntries,
      maxSequence: maxSequence,
    );
  }
}
