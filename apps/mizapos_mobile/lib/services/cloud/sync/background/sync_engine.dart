import 'package:mizapos_mobile/services/cloud/sync/background/models/sync_status_snapshot.dart';
import 'package:mizapos_mobile/services/cloud/sync/background/sync_connectivity_service.dart';
import 'package:mizapos_mobile/services/cloud/sync/background/sync_logger.dart';
import 'package:mizapos_mobile/services/cloud/sync/background/sync_retry_policy.dart';
import 'package:mizapos_mobile/services/cloud/sync/background/sync_status_service.dart';
import 'package:mizapos_mobile/services/cloud/sync/products_pull_worker.dart';
import 'package:mizapos_mobile/services/cloud/sync/products_push_worker.dart';

/// نتيجة دورة مزامنة واحدة.
class SyncRunResult {
  const SyncRunResult({
    required this.status,
    this.pushed = 0,
    this.pullApplied = 0,
    this.pushBatches = 0,
    this.message,
  });

  final SyncRunStatus status;
  final int pushed;
  final int pullApplied;
  final int pushBatches;
  final String? message;

  static const skippedOffline = SyncRunResult(status: SyncRunStatus.skippedOffline);
  static const skippedNoContext =
      SyncRunResult(status: SyncRunStatus.skippedNoContext);
  static const skippedAlreadyRunning =
      SyncRunResult(status: SyncRunStatus.skippedAlreadyRunning);
}

enum SyncRunStatus {
  success,
  partial,
  failed,
  skippedOffline,
  skippedNoContext,
  skippedAlreadyRunning,
}

/// ينسّق push/pull مع retry و batch loop — بدون تعديل workers.
class SyncEngine {
  SyncEngine({
    required ProductsPushWorker pushWorker,
    required ProductsPullWorker pullWorker,
    required SyncStatusService statusService,
    required SyncConnectivityService connectivityService,
    required SyncLogger logger,
    required SyncContextResolver contextResolver,
    int batchSize = 50,
  })  : _pushWorker = pushWorker,
        _pullWorker = pullWorker,
        _status = statusService,
        _connectivity = connectivityService,
        _logger = logger,
        _contextResolver = contextResolver,
        _batchSize = batchSize;

  final ProductsPushWorker _pushWorker;
  final ProductsPullWorker _pullWorker;
  final SyncStatusService _status;
  final SyncConnectivityService _connectivity;
  final SyncLogger _logger;
  final SyncContextResolver _contextResolver;
  final int _batchSize;

  bool _running = false;

  Future<SyncRunResult> run({SyncTrigger trigger = SyncTrigger.manual}) async {
    if (_running) return SyncRunResult.skippedAlreadyRunning;

    _running = true;
    try {
      if (!await _connectivity.refresh()) {
        _status.setRuntimeState(SyncRuntimeState.offline);
        return SyncRunResult.skippedOffline;
      }

      final ctx = await _contextResolver.resolve();
      if (ctx == null) {
        return SyncRunResult.skippedNoContext;
      }

      _status.setSyncing(true);
      _status.setRuntimeState(SyncRuntimeState.pushing);

      var totalPushed = 0;
      var pushBatches = 0;
      var pullApplied = 0;

      final pendingBefore = await _status.countPending();
      await _logger.logPushStarted(trigger: trigger, pending: pendingBefore);

      final pushOutcome = await _runPushPhase(ctx, trigger);
      totalPushed = pushOutcome.pushed;
      pushBatches = pushOutcome.batches;
      if (pushOutcome.pushed > 0 ||
          pushOutcome.duplicates > 0 ||
          pushBatches > 0) {
        await _status.recordPushSuccess(DateTime.now());
      }

      _status.setRuntimeState(SyncRuntimeState.pulling);
      await _logger.logPullStarted(trigger: trigger);
      pullApplied = await _runPullPhase(ctx, trigger);
      await _status.recordPullSuccess(DateTime.now());

      _status.setRetryCount(0);
      _status.setRuntimeState(SyncRuntimeState.idle);

      return SyncRunResult(
        status: SyncRunStatus.success,
        pushed: totalPushed,
        pullApplied: pullApplied,
        pushBatches: pushBatches,
      );
    } on Object catch (e) {
      await _logger.logError(e, phase: _status.runtimeState.name);
      _status.setRuntimeState(SyncRuntimeState.error, error: e.toString());
      return SyncRunResult(
        status: SyncRunStatus.failed,
        pushed: 0,
        pullApplied: 0,
        pushBatches: 0,
        message: e.toString(),
      );
    } finally {
      _running = false;
      _status.setSyncing(false);
    }
  }

  Future<({int pushed, int batches, int duplicates, String lastBatchId})>
      _runPushPhase(
    SyncRunContext ctx,
    SyncTrigger trigger,
  ) async {
    Object? lastError;
    for (var attempt = 1; attempt <= SyncRetryPolicy.maxAttempts; attempt++) {
      if (attempt > 1) {
        _status.setRuntimeState(SyncRuntimeState.waitingRetry);
        _status.setRetryCount(attempt - 1);
        await _logger.logRetry(
          attempt: attempt - 1,
          phase: 'push',
          cause: lastError,
        );
        await Future<void>.delayed(SyncRetryPolicy.delayForAttempt(attempt - 1));
        await _status.resetRetryableFailedToPending();
        if (!await _connectivity.refresh()) {
          throw StateError('offline_during_retry');
        }
      }

      try {
        final outcome = await _pushAllBatches(ctx);
        await _logger.logPushFinished(
          batches: outcome.batches,
          pushed: outcome.pushed,
          trigger: trigger,
          batchId: outcome.lastBatchId,
        );
        return outcome;
      } on Object catch (e) {
        lastError = e;
        if (SyncRetryPolicy.isPermanentError(e)) {
          rethrow;
        }
        if (attempt >= SyncRetryPolicy.maxAttempts) {
          rethrow;
        }
      }
    }
    throw StateError('push_retry_exhausted');
  }

  Future<int> _runPullPhase(SyncRunContext ctx, SyncTrigger trigger) async {
    Object? lastError;
    for (var attempt = 1; attempt <= SyncRetryPolicy.maxAttempts; attempt++) {
      if (attempt > 1) {
        _status.setRuntimeState(SyncRuntimeState.waitingRetry);
        _status.setRetryCount(attempt - 1);
        await _logger.logRetry(
          attempt: attempt - 1,
          phase: 'pull',
          cause: lastError,
        );
        await Future<void>.delayed(SyncRetryPolicy.delayForAttempt(attempt - 1));
        if (!await _connectivity.refresh()) {
          throw StateError('offline_during_retry');
        }
      }

      try {
        final result = await _pullWorker.run(
          companyId: ctx.companyId,
          branchId: ctx.branchId,
        );
        await _logger.logPullFinished(applied: result.applied, trigger: trigger);
        return result.applied;
      } on Object catch (e) {
        lastError = e;
        if (SyncRetryPolicy.isPermanentError(e)) {
          rethrow;
        }
        if (attempt >= SyncRetryPolicy.maxAttempts) {
          rethrow;
        }
      }
    }
    throw StateError('pull_retry_exhausted');
  }

  Future<({int pushed, int batches, int duplicates, String lastBatchId})>
      _pushAllBatches(
    SyncRunContext ctx,
  ) async {
    var totalPushed = 0;
    var totalDuplicates = 0;
    var batches = 0;
    var lastBatchId = '';

    while (true) {
      final pending = await _status.countPending();
      if (pending == 0) break;

      final result = await _pushWorker.run(
        companyId: ctx.companyId,
        branchId: ctx.branchId,
        deviceId: ctx.deviceId,
        batchLimit: _batchSize,
      );
      batches++;
      if (result.batchId.isNotEmpty) {
        lastBatchId = result.batchId;
      }

      totalPushed += result.pushed;
      totalDuplicates += result.duplicates;
      if (result.pushed == 0 &&
          result.duplicates == 0 &&
          (await _status.countPending()) > 0) {
        throw ProductsSyncException('push_no_progress');
      }

      if (result.pushed == 0 && result.duplicates == 0) break;
    }

    return (
      pushed: totalPushed,
      batches: batches,
      duplicates: totalDuplicates,
      lastBatchId: lastBatchId,
    );
  }
}
