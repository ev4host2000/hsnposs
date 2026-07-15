/// رفض حدث واحد ضمن دفعة رفع (عقد `rejected_events`).
class SyncPushRejectedEvent {
  const SyncPushRejectedEvent({
    required this.outboxId,
    required this.errorCode,
    this.message = '',
  });

  factory SyncPushRejectedEvent.fromJson(Object? json) {
    if (json is! Map) {
      return const SyncPushRejectedEvent(outboxId: '', errorCode: 'push_rejected');
    }
    final map = Map<String, dynamic>.from(json);
    final code = (map['error_code'] ?? map['code'] ?? 'push_rejected').toString();
    return SyncPushRejectedEvent(
      outboxId: (map['outbox_id'] ?? map['id'] ?? '').toString(),
      errorCode: code.trim().isEmpty ? 'push_rejected' : code,
      message: (map['message'] ?? '').toString(),
    );
  }

  final String outboxId;
  final String errorCode;
  final String message;

  static List<SyncPushRejectedEvent> listFromJson(Object? raw) {
    if (raw is! List) return const [];
    final out = <SyncPushRejectedEvent>[];
    for (final item in raw) {
      final event = SyncPushRejectedEvent.fromJson(item);
      if (event.outboxId.isNotEmpty) out.add(event);
    }
    return out;
  }
}
