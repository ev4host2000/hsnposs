import 'package:mizapos_desktop/services/cloud/sync/background/models/sync_status_snapshot.dart';

/// تفاصيل تقدّم دورة المزامنة الحالية — للواجهة.
class SyncProgressReport {
  const SyncProgressReport({
    required this.phase,
    this.stepKey = '',
    this.stepIndex = 0,
    this.stepTotal = 1,
    this.pendingAtStart = 0,
    this.pendingRemaining = 0,
    this.unitsCompleted = 0,
  });

  final SyncRuntimeState phase;
  final String stepKey;
  final int stepIndex;
  final int stepTotal;
  final int pendingAtStart;
  final int pendingRemaining;
  final int unitsCompleted;

  /// 0.0 → 1.0 للشريط العام (الرفع = النصف الأول، التنزيل = الثاني).
  double get overallFraction {
    const phaseSpan = 0.5;
    if (phase == SyncRuntimeState.pushing) {
      if (pendingAtStart <= 0) {
        final stepFrac =
            stepTotal > 0 ? (stepIndex + 1) / stepTotal : 0.5;
        return (phaseSpan * stepFrac).clamp(0.0, 0.5);
      }
      final done = (pendingAtStart - pendingRemaining).clamp(0, pendingAtStart);
      return (phaseSpan * (done / pendingAtStart)).clamp(0.0, 0.5);
    }
    if (phase == SyncRuntimeState.pulling) {
      final stepFrac =
          stepTotal > 0 ? (stepIndex + 1) / stepTotal : 0.5;
      return (0.5 + phaseSpan * stepFrac).clamp(0.5, 1.0);
    }
    if (phase == SyncRuntimeState.waitingRetry) {
      return 0.4;
    }
    return 0.0;
  }

  SyncProgressReport copyWith({
    SyncRuntimeState? phase,
    String? stepKey,
    int? stepIndex,
    int? stepTotal,
    int? pendingAtStart,
    int? pendingRemaining,
    int? unitsCompleted,
  }) {
    return SyncProgressReport(
      phase: phase ?? this.phase,
      stepKey: stepKey ?? this.stepKey,
      stepIndex: stepIndex ?? this.stepIndex,
      stepTotal: stepTotal ?? this.stepTotal,
      pendingAtStart: pendingAtStart ?? this.pendingAtStart,
      pendingRemaining: pendingRemaining ?? this.pendingRemaining,
      unitsCompleted: unitsCompleted ?? this.unitsCompleted,
    );
  }
}
