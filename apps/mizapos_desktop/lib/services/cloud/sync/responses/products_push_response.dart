import 'package:mizapos_desktop/services/cloud/sync/models/sync_push_rejected_event.dart';

/// استجابة POST `/sync/push/products`.
class ProductsPushResponse {
  const ProductsPushResponse({
    required this.batchId,
    required this.status,
    required this.accepted,
    required this.duplicates,
    required this.rejected,
    this.queuedAt,
    this.changelogSequences = const [],
    this.rejectedEvents = const [],
  });

  factory ProductsPushResponse.fromJson(Object? json) {
    if (json is! Map) {
      return const ProductsPushResponse(
        batchId: '',
        status: '',
        accepted: 0,
        duplicates: 0,
        rejected: 0,
      );
    }
    final map = Map<String, dynamic>.from(json);
    final rawSequences = map['changelog_sequences'];
    final sequences = <int>[];
    if (rawSequences is List) {
      for (final item in rawSequences) {
        if (item is int) {
          sequences.add(item);
        } else if (item is num) {
          sequences.add(item.toInt());
        }
      }
    }

    return ProductsPushResponse(
      batchId: (map['batch_id'] ?? '').toString(),
      status: (map['status'] ?? '').toString(),
      accepted: _asInt(map['accepted']),
      duplicates: _asInt(map['duplicates']),
      rejected: _asInt(map['rejected']),
      queuedAt: _optionalString(map['queued_at']),
      changelogSequences: sequences,
      rejectedEvents:
          SyncPushRejectedEvent.listFromJson(map['rejected_events']),
    );
  }

  final String batchId;
  final String status;
  final int accepted;
  final int duplicates;
  final int rejected;
  final String? queuedAt;
  final List<int> changelogSequences;
  final List<SyncPushRejectedEvent> rejectedEvents;
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

String? _optionalString(Object? value) {
  if (value == null) return null;
  final s = value.toString().trim();
  return s.isEmpty ? null : s;
}
