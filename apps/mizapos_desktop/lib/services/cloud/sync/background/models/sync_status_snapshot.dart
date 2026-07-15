import 'package:mizapos_desktop/services/cloud/sync/background/models/sync_progress_report.dart';

/// لقطة حالة المزامنة — للـ Debug UI و [SyncStatusService].
class SyncStatusSnapshot {
  const SyncStatusSnapshot({
    required this.pendingCount,
    required this.syncedCount,
    required this.failedCount,
    required this.isSyncing,
    required this.retryCount,
    this.deferredPullCount = 0,
    this.lastPushAt,
    this.lastPullAt,
    this.currentState = SyncRuntimeState.idle,
    this.lastError,
    this.progress,
  });

  final int pendingCount;
  final int syncedCount;
  final int failedCount;
  final int deferredPullCount;
  final bool isSyncing;
  final int retryCount;
  final DateTime? lastPushAt;
  final DateTime? lastPullAt;
  final SyncRuntimeState currentState;
  final String? lastError;
  final SyncProgressReport? progress;

  SyncStatusSnapshot copyWith({
    int? pendingCount,
    int? syncedCount,
    int? failedCount,
    int? deferredPullCount,
    bool? isSyncing,
    int? retryCount,
    DateTime? lastPushAt,
    DateTime? lastPullAt,
    SyncRuntimeState? currentState,
    String? lastError,
    SyncProgressReport? progress,
  }) {
    return SyncStatusSnapshot(
      pendingCount: pendingCount ?? this.pendingCount,
      syncedCount: syncedCount ?? this.syncedCount,
      failedCount: failedCount ?? this.failedCount,
      deferredPullCount: deferredPullCount ?? this.deferredPullCount,
      isSyncing: isSyncing ?? this.isSyncing,
      retryCount: retryCount ?? this.retryCount,
      lastPushAt: lastPushAt ?? this.lastPushAt,
      lastPullAt: lastPullAt ?? this.lastPullAt,
      currentState: currentState ?? this.currentState,
      lastError: lastError ?? this.lastError,
      progress: progress ?? this.progress,
    );
  }
}

enum SyncRuntimeState {
  idle,
  pushing,
  pulling,
  waitingRetry,
  offline,
  timedOut,
  error,
}

enum SyncTrigger {
  appStart,
  appResume,
  connectivityRestored,
  periodic,
  pendingOutbox,
  manual,
  background,
}
