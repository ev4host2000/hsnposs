import 'package:mizapos_desktop/services/cloud/sync/models/sync_push_event.dart';

/// POST `/sync/push/products`
class ProductsPushRequest {
  const ProductsPushRequest({
    required this.companyId,
    required this.branchId,
    required this.deviceId,
    required this.batchId,
    required this.events,
  });

  final String companyId;
  final String branchId;
  final String deviceId;
  final String batchId;
  final List<SyncPushEvent> events;

  Map<String, dynamic> toJson() => {
        'company_id': companyId,
        'branch_id': branchId,
        'device_id': deviceId,
        'batch_id': batchId,
        'events': events.map((e) => e.toJson()).toList(),
      };
}
