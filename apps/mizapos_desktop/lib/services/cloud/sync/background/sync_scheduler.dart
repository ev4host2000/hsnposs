import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mizapos_desktop/services/cloud/core/cloud_sync_controller.dart';
import 'package:mizapos_desktop/services/cloud/sync/background/cloud_sync_network_policy.dart';
import 'package:mizapos_desktop/services/cloud/sync/background/models/sync_status_snapshot.dart';
import 'package:mizapos_desktop/services/cloud/sync/background/sync_connectivity_service.dart';
import 'package:mizapos_desktop/services/cloud/sync/background/sync_engine.dart';
import 'package:mizapos_desktop/services/cloud/sync/background/sync_logger.dart';
import 'package:mizapos_desktop/services/cloud/sync/background/sync_status_service.dart';

/// جدولة المزامنة التلقائية — app start/resume/connectivity/periodic/pending.
///
/// Timer / connectivity / resume triggers are serialized on [_jobChain] so they
/// never fire overlapping `triggerSync` Futures (RC-1: no races from
/// fire-and-forget).
class SyncScheduler {
  SyncScheduler({
    required SyncEngine engine,
    required SyncStatusService statusService,
    required SyncConnectivityService connectivityService,
    SyncLogger? logger,
    Duration periodicInterval = const Duration(seconds: 60),
    Duration pendingPollInterval = const Duration(seconds: 15),
  })  : _engine = engine,
        _status = statusService,
        _connectivity = connectivityService,
        _logger = logger,
        _periodicInterval = periodicInterval,
        _pendingPollInterval = pendingPollInterval;

  final SyncEngine _engine;
  final SyncStatusService _status;
  final SyncConnectivityService _connectivity;
  final SyncLogger? _logger;
  final Duration _periodicInterval;
  final Duration _pendingPollInterval;

  Timer? _periodicTimer;
  Timer? _pendingTimer;
  StreamSubscription<bool>? _connectivitySub;
  bool _started = false;
  bool _syncInFlight = false;

  /// Serializes background scheduler jobs; errors are logged, not swallowed.
  Future<void> _jobChain = Future<void>.value();

  void _scheduleJob(Future<void> Function() job) {
    _jobChain = _jobChain.then((_) async {
      try {
        await job();
      } on Object catch (error, stackTrace) {
        await _logger?.logError(
          error,
          stackTrace: stackTrace,
          phase: 'scheduler_job',
        );
      }
    });
  }

  Future<void> start() async {
    if (_started) return;
    _started = true;

    await _connectivity.start();
    _connectivitySub = _connectivity.onOnlineChanged.listen((online) {
      if (online) {
        _scheduleJob(() async {
          await triggerSync(SyncTrigger.connectivityRestored);
        });
      } else {
        _status.setRuntimeState(SyncRuntimeState.offline);
      }
    });

    _periodicTimer = Timer.periodic(_periodicInterval, (_) {
      _scheduleJob(() async {
        await triggerSync(SyncTrigger.periodic);
      });
    });

    _pendingTimer = Timer.periodic(_pendingPollInterval, (_) {
      _scheduleJob(() async {
        await _status.recoverStaleOutboxClaims();
        final pending = await _status.countPending();
        final failed = await _status.countFailed();
        final deferred = await _status.countDeferredPullActive();
        if (pending > 0 || failed > 0 || deferred > 0) {
          await triggerSync(SyncTrigger.pendingOutbox);
        }
      });
    });

    _scheduleJob(() async {
      await triggerSync(SyncTrigger.appStart);
    });
  }

  Future<void> stop() async {
    _periodicTimer?.cancel();
    _pendingTimer?.cancel();
    await _connectivitySub?.cancel();
    await _connectivity.stop();
    _periodicTimer = null;
    _pendingTimer = null;
    _connectivitySub = null;
    _started = false;
    await _jobChain;
  }

  void onAppResumed() {
    _scheduleJob(() async {
      await triggerSync(SyncTrigger.appResume);
    });
  }

  Future<SyncRunResult> triggerSync(
    SyncTrigger trigger, {
    bool force = false,
  }) async {
    if (!force && !CloudSyncController.instance.isEnabled) {
      return const SyncRunResult(
        status: SyncRunStatus.skippedNoContext,
        message: 'cloud_sync_disabled',
      );
    }

    if (!force && !await CloudSyncNetworkPolicy.allowsSync()) {
      return const SyncRunResult(
        status: SyncRunStatus.skippedOffline,
        message: 'network_policy_blocked',
      );
    }

    // Never nest sync cycles — even when force:true (manual/resume).
    // GlobalSyncLock inside SyncEngine also covers WorkManager isolates.
    if (_syncInFlight) {
      await _logger?.logCycleSkippedAlreadyRunning(
        trigger: trigger,
        reason: 'scheduler_in_flight',
        source: 'SyncScheduler',
      );
      if (kDebugMode) {
        debugPrint('SyncScheduler[$trigger]: skipped scheduler_in_flight');
      }
      return SyncRunResult.skippedSchedulerInFlight;
    }

    _syncInFlight = true;
    try {
      if (trigger == SyncTrigger.pendingOutbox) {
        final pending = await _status.countPending();
        final failed = await _status.countFailed();
        final deferred = await _status.countDeferredPullActive();
        if (pending == 0 && failed == 0 && deferred == 0) {
          return const SyncRunResult(
            status: SyncRunStatus.skippedNoContext,
            message: 'no_pending',
          );
        }
      }

      final result = await _engine.run(trigger: trigger);
      if (kDebugMode) {
        debugPrint(
          'SyncScheduler[$trigger]: ${result.status.name} '
          'message=${result.message ?? "-"} '
          'pushed=${result.pushed} pull=${result.pullApplied}',
        );
      }
      return result;
    } finally {
      _syncInFlight = false;
    }
  }

  Future<void> dispose() async {
    await stop();
    _connectivity.dispose();
  }
}
