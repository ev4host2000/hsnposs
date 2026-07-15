import 'package:mizapos_desktop/services/accounting_service.dart';
import 'package:mizapos_desktop/services/cloud/api/cloud_api_auth_coordinator.dart';
import 'package:mizapos_desktop/services/cloud/auth/refresh_token_outcome.dart';
import 'package:mizapos_desktop/services/cloud/core/cloud_operation_deadline.dart';
import 'package:mizapos_desktop/services/cloud/storage/cloud_secure_storage.dart';
import 'package:mizapos_desktop/services/cloud/sync/background/global_sync_lock.dart';
import 'package:mizapos_desktop/services/cloud/sync/background/models/sync_progress_report.dart';
import 'package:mizapos_desktop/services/cloud/sync/background/models/sync_status_snapshot.dart';
import 'package:mizapos_desktop/services/cloud/sync/background/sync_connectivity_service.dart';
import 'package:mizapos_desktop/services/cloud/sync/background/sync_cycle_deadline.dart';
import 'package:mizapos_desktop/services/cloud/sync/background/sync_logger.dart';
import 'package:mizapos_desktop/services/cloud/sync/background/sync_retry_policy.dart';
import 'package:mizapos_desktop/services/cloud/sync/background/sync_status_service.dart';
import 'package:mizapos_desktop/services/cloud/sync/cloud_tenant_binder.dart';
import 'package:mizapos_desktop/services/cloud/sync/products_pull_worker.dart';
import 'package:mizapos_desktop/services/cloud/sync/products_push_worker.dart';
import 'package:mizapos_desktop/services/database_service.dart';

/// نتيجة دورة مزامنة واحدة.
class SyncRunResult {
  const SyncRunResult({
    required this.status,
    this.pushed = 0,
    this.pullApplied = 0,
    this.pullDeferred = 0,
    this.pushBatches = 0,
    this.message,
  });

  final SyncRunStatus status;
  final int pushed;
  final int pullApplied;
  final int pullDeferred;
  final int pushBatches;
  final String? message;

  static const skippedOffline =
      SyncRunResult(status: SyncRunStatus.skippedOffline);
  static const skippedNoContext =
      SyncRunResult(status: SyncRunStatus.skippedNoContext);
  static const skippedAlreadyRunning = SyncRunResult(
    status: SyncRunStatus.skippedAlreadyRunning,
    message: 'global_sync_lock_busy',
  );

  /// Same-isolate re-entrancy while this engine is already in [run].
  static const skippedLocalReentry = SyncRunResult(
    status: SyncRunStatus.skippedAlreadyRunning,
    message: 'local_isolate_reentry',
  );

  /// Scheduler still draining a previous triggerSync call.
  static const skippedSchedulerInFlight = SyncRunResult(
    status: SyncRunStatus.skippedAlreadyRunning,
    message: 'scheduler_in_flight',
  );
}

enum SyncRunStatus {
  success,
  partialSuccess,
  failed,
  skippedOffline,
  skippedNoContext,
  skippedAlreadyRunning,
}

/// ينسّق push/pull مع retry و batch loop — بدون تعديل workers.
///
/// Uses [GlobalSyncLock] so Foreground / WorkManager / Manual / Scheduler
/// cannot overlap sync cycles across isolates.
class SyncEngine {
  SyncEngine({
    required ProductsPushWorker pushWorker,
    required ProductsPullWorker pullWorker,
    required SyncStatusService statusService,
    required SyncConnectivityService connectivityService,
    required SyncLogger logger,
    required SyncContextResolver contextResolver,
    required DatabaseService databaseService,
    CloudSecureStorage? secureStorage,
    AccountingService? accountingService,
    CloudApiAuthCoordinator? authCoordinator,
    int batchSize = 50,
    Duration cycleTimeout = const Duration(minutes: 5),
  })  : _pushWorker = pushWorker,
        _pullWorker = pullWorker,
        _status = statusService,
        _connectivity = connectivityService,
        _logger = logger,
        _contextResolver = contextResolver,
        _databaseService = databaseService,
        _secureStorage = secureStorage,
        _accountingService = accountingService,
        _authCoordinator = authCoordinator,
        _batchSize = batchSize,
        _cycleTimeout = cycleTimeout;

  final ProductsPushWorker _pushWorker;
  final ProductsPullWorker _pullWorker;
  final SyncStatusService _status;
  final SyncConnectivityService _connectivity;
  final SyncLogger _logger;
  final SyncContextResolver _contextResolver;
  final DatabaseService _databaseService;
  final CloudSecureStorage? _secureStorage;
  final AccountingService? _accountingService;
  final CloudApiAuthCoordinator? _authCoordinator;
  final int _batchSize;
  final Duration _cycleTimeout;

  /// Same-isolate re-entrancy guard (fast path). Cross-isolate uses GlobalSyncLock.
  bool _running = false;

  Future<SyncRunResult> run({SyncTrigger trigger = SyncTrigger.manual}) async {
    if (_running) {
      await _logger.logCycleSkippedAlreadyRunning(
        trigger: trigger,
        reason: 'local_isolate_reentry',
      );
      return SyncRunResult.skippedLocalReentry;
    }

    final db = await _databaseService.database;
    final lockHandle = await GlobalSyncLock.tryAcquire(
      db: db,
      ownerId: GlobalSyncLock.newOwnerId(prefix: 'engine'),
      trigger: trigger.name,
    );
    if (lockHandle == null) {
      await _logger.logCycleSkippedAlreadyRunning(
        trigger: trigger,
        reason: 'global_sync_lock_busy',
      );
      return SyncRunResult.skippedAlreadyRunning;
    }

    _running = true;
    final deadline = SyncCycleDeadline(_cycleTimeout);
    SyncRunResult? result;
    try {
      final completed = await CloudOperationDeadline.run(
        deadline: deadline.expiresAt,
        action: () => _runCycle(trigger, deadline),
      );
      result = completed;
      return completed;
    } finally {
      deadline.dispose();
      _running = false;
      await lockHandle.release();
      _status.setSyncing(false);
      final timedOut =
          result?.message?.startsWith('sync_cycle_timeout:') ?? false;
      if (!timedOut) {
        _status.clearProgress();
      }
    }
  }

  Future<SyncRunResult> _runCycle(
    SyncTrigger trigger,
    SyncCycleDeadline deadline,
  ) async {
    SyncRunContext? activeContext;
    var totalPushed = 0;
    var pushBatches = 0;
    var pullApplied = 0;
    var pullDeferred = 0;
    try {
      if (!await deadline.runStep(
        'connectivity_check',
        _connectivity.refresh,
      )) {
        _status.setRuntimeState(SyncRuntimeState.offline);
        return SyncRunResult.skippedOffline;
      }

      final ctx = await deadline.runStep(
        'context_resolution',
        _contextResolver.resolve,
      );
      if (ctx == null) {
        return SyncRunResult.skippedNoContext;
      }
      activeContext = ctx;

      // RC-1: every sync cycle binds tenant + resets cursors before push/pull.
      await deadline.runStep(
        'tenant_bind',
        () => _ensureTenantBoundBeforeCycle(trigger),
      );

      await deadline.runStep('auth_refresh', () async {
        await _authCoordinator?.ensureFreshAccessToken();
      });

      _status.setSyncing(true);
      _status.setRuntimeState(SyncRuntimeState.pushing);

      final pendingBefore = await deadline.runStep(
        'push_count_pending',
        _status.countPending,
      );
      await deadline.runStep(
        'push_log_started',
        () => _logger.logPushStarted(
          trigger: trigger,
          pending: pendingBefore,
        ),
      );
      _status.setProgress(
        SyncProgressReport(
          phase: SyncRuntimeState.pushing,
          stepKey: 'push_start',
          pendingAtStart: pendingBefore,
          pendingRemaining: pendingBefore,
        ),
      );

      final batchSize = await deadline.runStep(
        'push_batch_size',
        () => _connectivity.recommendedBatchSize(
          fallback: _batchSize,
        ),
      );
      final pushOutcome = await _runPushPhase(
        ctx,
        trigger,
        deadline,
        pendingAtStart: pendingBefore,
        batchSize: batchSize,
      );
      totalPushed = pushOutcome.pushed;
      pushBatches = pushOutcome.batches;
      if (pushOutcome.pushed > 0 ||
          pushOutcome.duplicates > 0 ||
          pushBatches > 0) {
        await deadline.runStep(
          'push_record_success',
          () => _status.recordPushSuccess(DateTime.now()),
        );
      }

      _status.setRuntimeState(SyncRuntimeState.pulling);
      _status.setProgress(
        const SyncProgressReport(
          phase: SyncRuntimeState.pulling,
          stepKey: 'pull_start',
          stepIndex: 0,
          stepTotal: 1,
        ),
      );
      await deadline.runStep(
        'pull_log_started',
        () => _logger.logPullStarted(trigger: trigger),
      );
      final pullLimit = await deadline.runStep(
        'pull_page_limit',
        _connectivity.recommendedPullPageLimit,
      );
      final pullOutcome = await _runPullPhase(
        ctx,
        trigger,
        deadline,
        pageLimit: pullLimit,
      );
      pullApplied = pullOutcome.applied;
      pullDeferred = pullOutcome.deferred;
      await deadline.runStep(
        'pull_record_success',
        () => _status.recordPullSuccess(DateTime.now()),
      );

      _status.setRetryCount(0);
      _status.setRuntimeState(SyncRuntimeState.idle);
      _status.clearProgress();

      final pendingAfter = await deadline.runStep(
        'final_count_pending',
        _status.countPending,
      );
      final failedAfter = await deadline.runStep(
        'final_count_failed',
        _status.countFailed,
      );
      final deferredAfter = await deadline.runStep(
        'final_count_deferred',
        () => _status.countDeferredPull(
          organizationId: ctx.companyId,
          branchId: ctx.branchId,
        ),
      );
      final incomplete = pullDeferred > 0 ||
          deferredAfter > 0 ||
          pendingAfter > 0 ||
          failedAfter > 0;

      return SyncRunResult(
        status:
            incomplete ? SyncRunStatus.partialSuccess : SyncRunStatus.success,
        pushed: totalPushed,
        pullApplied: pullApplied,
        pullDeferred: pullDeferred > 0 ? pullDeferred : deferredAfter,
        pushBatches: pushBatches,
        message: (pullDeferred > 0 || deferredAfter > 0)
            ? 'pull_deferred:${pullDeferred > 0 ? pullDeferred : deferredAfter}'
            : (failedAfter > 0 ? 'push_failed_remaining:$failedAfter' : null),
      );
    } on SyncCycleTimeoutException catch (e, stackTrace) {
      await _logger.logCycleTimedOut(
        error: e,
        stackTrace: stackTrace,
        phase: e.phase,
        timeout: e.timeout,
        elapsed: e.elapsed,
        progressStep: _status.progress?.stepKey,
        context: _contextDetails(
          activeContext,
          trigger: trigger,
          pushed: totalPushed,
          pullApplied: pullApplied,
          pushBatches: pushBatches,
          pullDeferred: pullDeferred,
        ),
      );
      _status.setRuntimeState(
        SyncRuntimeState.timedOut,
        error: e.toString(),
      );
      return SyncRunResult(
        status: SyncRunStatus.failed,
        pushed: totalPushed,
        pullApplied: pullApplied,
        pullDeferred: pullDeferred,
        pushBatches: pushBatches,
        message: e.toString(),
      );
    } on Object catch (e, stackTrace) {
      await _logger.logError(
        e,
        stackTrace: stackTrace,
        phase: _status.runtimeState.name,
        context: _contextDetails(
          activeContext,
          trigger: trigger,
          pushed: totalPushed,
          pullApplied: pullApplied,
          pushBatches: pushBatches,
          pullDeferred: pullDeferred,
          error: e,
        ),
      );
      _status.setRuntimeState(SyncRuntimeState.error, error: e.toString());
      return SyncRunResult(
        status: SyncRunStatus.failed,
        pushed: totalPushed,
        pullApplied: pullApplied,
        pullDeferred: pullDeferred,
        pushBatches: pushBatches,
        message: e.toString(),
      );
    }
  }

  /// Ensures [CloudTenantBinder] + cursor reset run before any push/pull work.
  Future<void> _ensureTenantBoundBeforeCycle(SyncTrigger trigger) async {
    final storage = _secureStorage;
    if (storage == null) return;

    final result = await CloudTenantBinder.bindIfNeeded(
      databaseService: _databaseService,
      accountingService: _accountingService ?? AccountingService(_databaseService),
      storage: storage,
    );
    if (result.message == 'needs_remap') {
      await _logger.logError(
        StateError('tenant_bind_needs_remap'),
        phase: 'tenant_bind',
        context: {
          'trigger': trigger.name,
          'bind_message': result.message,
          'local_organization_id': result.localOrganizationId,
          'local_branch_id': result.localBranchId,
          'cloud_company_id': result.cloudCompanyId,
          'cloud_branch_id': result.cloudBranchId,
        },
      );
      throw StateError('tenant_bind_needs_remap');
    }
  }

  Future<({int pushed, int batches, int duplicates, String lastBatchId})>
      _runPushPhase(
    SyncRunContext ctx,
    SyncTrigger trigger,
    SyncCycleDeadline deadline, {
    required int pendingAtStart,
    required int batchSize,
  }) async {
    Object? lastError;
    StackTrace? lastStackTrace;
    for (var attempt = 1; attempt <= SyncRetryPolicy.maxAttempts; attempt++) {
      deadline.checkpoint('push_attempt_$attempt');
      await deadline.runStep(
        'push_recover_claims',
        _status.recoverStaleOutboxClaims,
      );
      await deadline.runStep(
        'push_reset_retryable',
        _status.resetRetryableFailedToPending,
      );
      if (attempt > 1) {
        _status.setRuntimeState(SyncRuntimeState.waitingRetry);
        _status.setRetryCount(attempt - 1);
        await deadline.runStep(
          'push_log_retry',
          () => _logger.logRetry(
            attempt: attempt - 1,
            phase: 'push',
            cause: lastError,
            causeStackTrace: lastStackTrace,
          ),
        );
        await deadline.wait(
          SyncRetryPolicy.delayForAttempt(attempt - 1),
          'push_retry_wait',
        );
        if (!await deadline.runStep(
          'push_retry_connectivity',
          _connectivity.refresh,
        )) {
          throw StateError('offline_during_retry');
        }
      }

      try {
        final outcome = await deadline.runStep(
          'push_batches',
          () => _pushAllBatches(
            ctx,
            deadline,
            pendingAtStart: pendingAtStart,
            batchSize: batchSize,
          ),
        );
        await deadline.runStep(
          'push_log_finished',
          () => _logger.logPushFinished(
            batches: outcome.batches,
            pushed: outcome.pushed,
            trigger: trigger,
            batchId: outcome.lastBatchId,
          ),
        );
        return outcome;
      } on Object catch (e, stackTrace) {
        lastError = e;
        lastStackTrace = stackTrace;
        if (e is SyncCycleTimeoutException) rethrow;
        deadline.throwIfExpired();
        await deadline.runStep(
          'push_log_error',
          () => _logger.logError(
            e,
            stackTrace: stackTrace,
            phase: 'push_attempt',
            context: _contextDetails(ctx, trigger: trigger, error: e),
          ),
        );
        if (await deadline.runStep(
          'push_auth_recovery',
          () => _tryRecoverAuth(e),
        )) {
          continue;
        }
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

  Future<({int applied, int deferred})> _runPullPhase(
    SyncRunContext ctx,
    SyncTrigger trigger,
    SyncCycleDeadline deadline, {
    int? pageLimit,
  }) async {
    Object? lastError;
    StackTrace? lastStackTrace;
    for (var attempt = 1; attempt <= SyncRetryPolicy.maxAttempts; attempt++) {
      deadline.checkpoint('pull_attempt_$attempt');
      if (attempt > 1) {
        _status.setRuntimeState(SyncRuntimeState.waitingRetry);
        _status.setRetryCount(attempt - 1);
        await deadline.runStep(
          'pull_log_retry',
          () => _logger.logRetry(
            attempt: attempt - 1,
            phase: 'pull',
            cause: lastError,
            causeStackTrace: lastStackTrace,
          ),
        );
        await deadline.wait(
          SyncRetryPolicy.delayForAttempt(attempt - 1),
          'pull_retry_wait',
        );
        if (!await deadline.runStep(
          'pull_retry_connectivity',
          _connectivity.refresh,
        )) {
          throw StateError('offline_during_retry');
        }
      }

      try {
        final result = await deadline.runStep(
          'pull_worker',
          () => _pullWorker.run(
            companyId: ctx.companyId,
            branchId: ctx.branchId,
            limit: pageLimit,
          ),
        );
        await deadline.runStep(
          'pull_log_finished',
          () => _logger.logPullFinished(
            applied: result.applied,
            trigger: trigger,
          ),
        );
        return (applied: result.applied, deferred: result.deferred);
      } on Object catch (e, stackTrace) {
        lastError = e;
        lastStackTrace = stackTrace;
        if (e is SyncCycleTimeoutException) rethrow;
        deadline.throwIfExpired();
        await deadline.runStep(
          'pull_log_error',
          () => _logger.logError(
            e,
            stackTrace: stackTrace,
            phase: 'pull_attempt',
            context: _contextDetails(ctx, trigger: trigger, error: e),
          ),
        );
        if (await deadline.runStep(
          'pull_auth_recovery',
          () => _tryRecoverAuth(e),
        )) {
          continue;
        }
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

  Future<bool> _tryRecoverAuth(Object error) async {
    if (!SyncRetryPolicy.isAuthRefreshableError(error)) return false;
    final coordinator = _authCoordinator;
    if (coordinator == null) return false;
    final outcome = await coordinator.refreshAccessToken();
    return outcome == RefreshTokenOutcome.success;
  }

  Map<String, Object?> _contextDetails(
    SyncRunContext? context, {
    SyncTrigger? trigger,
    int? pushed,
    int? pullApplied,
    int? pushBatches,
    int? pullDeferred,
    Object? error,
  }) {
    return {
      'device_id': context?.deviceId,
      'organization_id': context?.companyId,
      'branch_id': context?.branchId,
      if (trigger != null) 'trigger': trigger.name,
      if (pushed != null) 'pushed': pushed,
      if (pullApplied != null) 'pull_applied': pullApplied,
      if (pushBatches != null) 'push_batches': pushBatches,
      if (pullDeferred != null) 'pull_deferred': pullDeferred,
      if (error != null) 'error_type': error.runtimeType.toString(),
      if (error != null) 'error_message': error.toString(),
      ..._errorCodeHints(error),
    };
  }

  Map<String, Object?> _errorCodeHints(Object? error) {
    if (error == null) return const {};
    final text = error.toString();
    final hints = <String, Object?>{};
    // Prefer structured codes when exceptions expose them via toString patterns.
    final codeMatch = RegExp(r"(?:code|error)[=:][\s']*([A-Za-z0-9_\.-]+)")
        .firstMatch(text);
    if (codeMatch != null) {
      hints['error_code'] = codeMatch.group(1);
    }
    final httpMatch = RegExp(r'\b([45]\d{2})\b').firstMatch(text);
    if (httpMatch != null) {
      hints['http_status'] = int.tryParse(httpMatch.group(1)!);
    }
    return hints;
  }

  Future<({int pushed, int batches, int duplicates, String lastBatchId})>
      _pushAllBatches(
    SyncRunContext ctx,
    SyncCycleDeadline deadline, {
    required int pendingAtStart,
    required int batchSize,
  }) async {
    var totalPushed = 0;
    var totalDuplicates = 0;
    var batches = 0;
    var lastBatchId = '';

    while (true) {
      deadline.checkpoint('push_batch_${batches + 1}');
      final pending = await deadline.runStep(
        'push_batch_count_pending',
        _status.countPending,
      );
      _status.setProgress(
        SyncProgressReport(
          phase: SyncRuntimeState.pushing,
          stepKey: 'push_start',
          pendingAtStart: pendingAtStart,
          pendingRemaining: pending,
        ),
      );
      if (pending == 0) break;

      final result = await deadline.runStep(
        'push_worker_batch_${batches + 1}',
        () => _pushWorker.run(
          companyId: ctx.companyId,
          branchId: ctx.branchId,
          deviceId: ctx.deviceId,
          batchLimit: batchSize,
        ),
      );
      batches++;
      if (result.batchId.isNotEmpty) {
        lastBatchId = result.batchId;
      }

      totalPushed += result.pushed;
      totalDuplicates += result.duplicates;
      if (result.pushed == 0 &&
          result.duplicates == 0 &&
          (await deadline.runStep(
                'push_no_progress_count',
                _status.countPending,
              )) >
              0) {
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
