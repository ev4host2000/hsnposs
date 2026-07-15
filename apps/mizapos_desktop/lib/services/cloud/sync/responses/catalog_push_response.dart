import 'package:mizapos_desktop/services/cloud/sync/models/sync_push_rejected_event.dart';

/// Push response for catalog entity sync endpoints.
class CatalogPushResponse {
  const CatalogPushResponse({
    required this.batchId,
    required this.status,
    required this.accepted,
    required this.duplicates,
    this.rejected = 0,
    this.rejectedEvents = const [],
  });

  factory CatalogPushResponse.fromJson(Object? json) {
    if (json is! Map) {
      return const CatalogPushResponse(
        batchId: '',
        status: '',
        accepted: 0,
        duplicates: 0,
      );
    }
    final map = Map<String, dynamic>.from(json);
    return CatalogPushResponse(
      batchId: (map['batch_id'] ?? '').toString(),
      status: (map['status'] ?? '').toString(),
      accepted: (map['accepted'] as num?)?.toInt() ?? 0,
      duplicates: (map['duplicates'] as num?)?.toInt() ?? 0,
      rejected: (map['rejected'] as num?)?.toInt() ?? 0,
      rejectedEvents:
          SyncPushRejectedEvent.listFromJson(map['rejected_events']),
    );
  }

  final String batchId;
  final String status;
  final int accepted;
  final int duplicates;
  final int rejected;
  final List<SyncPushRejectedEvent> rejectedEvents;

  bool get ok => status == 'accepted' || status == 'duplicate';
}
