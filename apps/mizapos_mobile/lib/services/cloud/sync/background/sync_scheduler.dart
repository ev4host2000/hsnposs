import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mizapos_mobile/services/cloud/sync/background/models/sync_status_snapshot.dart';
import 'package:mizapos_mobile/services/cloud/sync/background/sync_connectivity_service.dart';
import 'package:mizapos_mobile/services/cloud/sync/background/sync_engine.dart';
import 'package:mizapos_mobile/services/cloud/sync/background/sync_status_service.dart';

/// جدولة المزامنة التلقائية — app start/resume/connectivity/periodic/pending.
class SyncScheduler {
  SyncScheduler({
    required SyncEngine engine,
    required SyncStatusService statusService,
    required SyncConnectivityService connectivityService,
    Duration periodicInterval = const Duration(seconds: 60),
    Duration pendingPollInterval = const Duration(seconds: 15),
  })  : _engine = engine,
        _status = statusService,
        _connectivity = connectivityService,
        _periodicInterval = periodicInterval,
        _pendingPollInterval = pendingPollInterval;

  final SyncEngine _engine;
  final SyncStatusService _status;
  final SyncConnectivityService _connectivity;
  final Duration _periodicInterval;
  final Duration _pendingPollInterval;

  Timer? _periodicTimer;
  Timer? _pendingTimer;
  StreamSubscription<bool>? _connectivitySub;
  bool _started = false;
  bool _syncInFlight = false;

  Future<void> start() async {
    if (_started) return;
    _started = true;

    await _connectivity.start();
    _connectivitySub = _connectivity.onOnlineChanged.listen((online) {
      if (online) {
        unawaited(triggerSync(SyncTrigger.connectivityRestored));
      } else {
        _status.setRuntimeState(SyncRuntimeState.offline);
      }
    });

    _periodicTimer = Timer.periodic(_periodicInterval, (_) {
      unawaited(triggerSync(SyncTrigger.periodic));
    });

    _pendingTimer = Timer.periodic(_pendingPollInterval, (_) async {
      final pending = await _status.countPending();
      if (pending > 0) {
        unawaited(triggerSync(SyncTrigger.pendingOutbox));
      }
    });

    unawaited(triggerSync(SyncTrigger.appStart));
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
  }

  void onAppResumed() {
    unawaited(triggerSync(SyncTrigger.appResume));
  }

  Future<SyncRunResult> triggerSync(
    SyncTrigger trigger, {
    bool force = false,
  }) async {
    if (_syncInFlight && !force) {
      return SyncRunResult.skippedAlreadyRunning;
    }

    _syncInFlight = true;
    try {
      if (trigger == SyncTrigger.pendingOutbox) {
        final pending = await _status.countPending();
        if (pending == 0) {
          return const SyncRunResult(
            status: SyncRunStatus.skippedNoContext,
            message: 'no_pending',
          );
        }
      }

      final result = await _engine.run(trigger: trigger);
      if (kDebugMode && result.status != SyncRunStatus.skippedAlreadyRunning) {
        debugPrint(
          'SyncScheduler[$trigger]: ${result.status.name} '
          'pushed=${result.pushed} pull=${result.pullApplied}',
        );
      }
      return result;
    } finally {
      _syncInFlight = false;
    }
  }

  void dispose() {
    unawaited(stop());
    _connectivity.dispose();
  }
}
