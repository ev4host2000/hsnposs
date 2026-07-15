/// صف فاشل من `sync_outbox` لعرضه في واجهة ميزا كلاود.
class FailedOutboxDetail {
  const FailedOutboxDetail({
    required this.entityType,
    required this.operation,
    required this.entityId,
    required this.error,
    this.updatedAt,
  });

  final String entityType;
  final String operation;
  final String entityId;
  final String error;
  final DateTime? updatedAt;
}
