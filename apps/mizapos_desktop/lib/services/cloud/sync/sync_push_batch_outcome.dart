/// قواعد تمييز نتيجة دفعة الرفع — متى نعتبر الصفوف متزامنة محلياً.
abstract final class SyncPushBatchOutcome {
  /// هل يمكن تعليم كل صفوف الدفعة كـ synced بأمان؟
  static bool canMarkAllSynced({
    required int pendingCount,
    required int accepted,
    required int duplicates,
    int rejected = 0,
    String status = '',
  }) {
    if (pendingCount <= 0) return false;
    final confirmed = accepted + duplicates;
    if (rejected > 0 && confirmed < pendingCount) return false;
    if (confirmed > 0 && confirmed < pendingCount) return false;
    return confirmed > 0 || status == 'duplicate';
  }

  /// دفعة مرفوضة بالكامل (لا قبول ولا تكرار).
  static bool isFullyRejected({
    required int accepted,
    required int duplicates,
    required int rejected,
  }) {
    return rejected > 0 && accepted == 0 && duplicates == 0;
  }

  /// قبول جزئي غامض — أعد المحاولة دون تعليم الكل synced.
  static bool isAmbiguousPartial({
    required int pendingCount,
    required int accepted,
    required int duplicates,
    int rejected = 0,
  }) {
    final confirmed = accepted + duplicates;
    return confirmed > 0 && confirmed < pendingCount;
  }

  /// هل يمكن تسوية الرفض الجزئي بمعرّفات أحداث صريحة؟
  static bool canSettleByRejectedEvents({
    required int claimedCount,
    required int rejectedEventCount,
  }) {
    return claimedCount > 0 && rejectedEventCount > 0;
  }
}
