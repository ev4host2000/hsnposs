import 'package:mizapos_mobile/models/entities.dart';
import 'package:mizapos_mobile/services/cloud/sync/models/sync_push_event.dart';

/// صف pending من `sync_outbox`.
class SyncOutboxRow {
  const SyncOutboxRow({
    required this.id,
    required this.entityType,
    required this.organizationId,
    required this.branchId,
    required this.entityId,
    required this.operation,
    required this.payloadJson,
    required this.clientRowVersion,
    required this.idempotencyKey,
    required this.installationId,
  });

  final String id;
  final String entityType;
  final String organizationId;
  final String branchId;
  final String entityId;
  final String operation;
  final Map<String, dynamic> payloadJson;
  final int clientRowVersion;
  final String idempotencyKey;
  final String installationId;

  SyncPushEvent toPushEvent() {
    return SyncPushEvent(
      outboxId: id,
      entityType: entityType,
      entityId: entityId,
      operation: operation,
      payloadJson: payloadJson,
      clientRowVersion: clientRowVersion,
      idempotencyKey: idempotencyKey,
      occurredAt: DateTime.now().toUtc().toIso8601String(),
    );
  }
}

/// تحويل [ProductEntity] إلى payload سحابي (snake_case).
Map<String, dynamic> productEntityToCloudPayload(ProductEntity product) {
  return {
    'id': product.id,
    'company_id': product.organizationId,
    'branch_id': product.branchId,
    'name': product.name,
    'sale_price': product.salePrice,
    'cost_price': product.costPrice,
    'stock_qty': product.stockQty,
    if (product.barcode != null && product.barcode!.isNotEmpty)
      'barcode': product.barcode,
    if (product.categoryId != null && product.categoryId!.isNotEmpty)
      'category_id': product.categoryId,
    if (product.description != null && product.description!.isNotEmpty)
      'description': product.description,
    if (product.unitName != null && product.unitName!.isNotEmpty)
      'unit_name': product.unitName,
    'is_hidden': product.isHidden,
    'is_frozen': product.isFrozen,
    'is_service': product.isService,
  };
}

String buildProductIdempotencyKey({
  required String deviceId,
  required String productId,
  required String operation,
}) {
  return '$deviceId:$productId:$operation';
}
