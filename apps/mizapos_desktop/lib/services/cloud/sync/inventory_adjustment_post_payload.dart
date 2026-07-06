import 'package:mizapos_desktop/services/cloud/sync/posting/inventory_adjustment/inventory_adjustment_post_effects.dart';
import 'package:mizapos_desktop/services/cloud/sync/transactions/models/transaction_aggregate.dart';
import 'package:mizapos_desktop/services/cloud/sync/transactions/transaction_payload_serializer.dart';

Map<String, dynamic> inventoryAdjustmentPostAggregate({
  required String id,
  required String organizationId,
  required String branchId,
  required String createdBy,
  required String productId,
  required double quantityDelta,
  required String adjustmentReason,
  required List<Map<String, dynamic>> inventory,
  DateTime? adjustmentDate,
  String? notes,
  required int transactionVersion,
  required int rowVersion,
  String? postedAt,
  List<Map<String, dynamic>> lines = const [],
  String? originDeviceId,
}) {
  final metadata = <String, dynamic>{
    'payload_schema_version': 1,
    if (originDeviceId != null) 'origin_device_id': originDeviceId,
    if (postedAt != null) 'posted_at': postedAt,
    'inventory': inventory,
  };

  return {
    'header': {
      'id': id,
      'company_id': organizationId,
      'branch_id': branchId,
      'document_type': 'inventory_adjustment',
      'status': 'posted',
      'transaction_version': transactionVersion,
      'row_version': rowVersion,
      'product_id': productId,
      'quantity_delta': quantityDelta,
      'adjustment_reason': adjustmentReason,
      'adjustment_date': (adjustmentDate ?? DateTime.now()).toIso8601String(),
      if (notes != null) 'notes': notes,
      'created_by_user_id': createdBy,
      if (postedAt != null) 'posted_at': postedAt,
    },
    'lines': lines,
    'inventory': inventory,
    'metadata': metadata,
  };
}

Map<String, dynamic> inventoryAdjustmentPostPushEnvelope({
  required Map<String, dynamic> aggregateJson,
  required int clientRowVersion,
  String? idempotencyKey,
}) {
  final aggregate = MapTransactionAggregate.fromParts(
    header: Map<String, dynamic>.from(aggregateJson['header'] as Map),
    lines: (aggregateJson['lines'] as List?)
            ?.whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList() ??
        const [],
    metadata: aggregateJson['metadata'] is Map
        ? Map<String, dynamic>.from(aggregateJson['metadata'] as Map)
        : const {},
  );

  final envelope = TransactionPayloadSerializer().envelope(
    aggregate: aggregate,
    operation: 'post',
    clientRowVersion: clientRowVersion,
    idempotencyKey: idempotencyKey,
  );

  final aggregateOut = Map<String, dynamic>.from(
    envelope['aggregate'] as Map<String, dynamic>,
  );
  if (aggregateJson['inventory'] is List) {
    aggregateOut['inventory'] = aggregateJson['inventory'];
  }
  envelope['aggregate'] = aggregateOut;
  return envelope;
}

List<Map<String, dynamic>> inventoryAdjustmentInventoryJsonFromStageData(
  Map<String, Object?> stageData,
) {
  final raw = stageData['inventory_movements'];
  if (raw is List) {
    return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }
  final inventory = stageData['inventory'];
  if (inventory is InventoryAdjustmentInventoryEffect) {
    return InventoryAdjustmentPostEffects.inventoryJson(inventory);
  }
  return const [];
}
