/// لقطة حالة المزامنة — للـ Debug UI و [SyncStatusService].
class SyncStatusSnapshot {
  const SyncStatusSnapshot({
    required this.pendingCount,
    required this.syncedCount,
    required this.failedCount,
    required this.isSyncing,
    required this.retryCount,
    this.lastPushAt,
    this.lastPullAt,
    this.currentState = SyncRuntimeState.idle,
    this.lastError,
  });

  final int pendingCount;
  final int syncedCount;
  final int failedCount;
  final bool isSyncing;
  final int retryCount;
  final DateTime? lastPushAt;
  final DateTime? lastPullAt;
  final SyncRuntimeState currentState;
  final String? lastError;

  SyncStatusSnapshot copyWith({
    int? pendingCount,
    int? syncedCount,
    int? failedCount,
    bool? isSyncing,
    int? retryCount,
    DateTime? lastPushAt,
    DateTime? lastPullAt,
    SyncRuntimeState? currentState,
    String? lastError,
  }) {
    return SyncStatusSnapshot(
      pendingCount: pendingCount ?? this.pendingCount,
      syncedCount: syncedCount ?? this.syncedCount,
      failedCount: failedCount ?? this.failedCount,
      isSyncing: isSyncing ?? this.isSyncing,
      retryCount: retryCount ?? this.retryCount,
      lastPushAt: lastPushAt ?? this.lastPushAt,
      lastPullAt: lastPullAt ?? this.lastPullAt,
      currentState: currentState ?? this.currentState,
      lastError: lastError ?? this.lastError,
    );
  }
}

enum SyncRuntimeState {
  idle,
  pushing,
  pulling,
  waitingRetry,
  offline,
  error,
}

enum SyncTrigger {
  appStart,
  appResume,
  connectivityRestored,
  periodic,
  pendingOutbox,
  manual,
}
