import 'package:mizapos_desktop/services/cloud/sync/posting/purchase_return/purchase_return_post_effects.dart';
import 'package:mizapos_desktop/services/cloud/sync/transactions/models/transaction_aggregate.dart';
import 'package:mizapos_desktop/services/cloud/sync/transactions/transaction_payload_serializer.dart';

Map<String, dynamic> purchaseReturnPostAggregate({
  required String id,
  required String organizationId,
  required String branchId,
  required String createdBy,
  required String originalInvoiceId,
  required String supplierId,
  required List<Map<String, dynamic>> inventory,
  required List<Map<String, dynamic>> accounting,
  DateTime? returnDate,
  String refundPaymentType = 'cash',
  double lineSubtotal = 0,
  double discountAmount = 0,
  double taxPercent = 0,
  double total = 0,
  double paidAmount = 0,
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
    'accounting': accounting,
  };

  return {
    'header': {
      'id': id,
      'company_id': organizationId,
      'branch_id': branchId,
      'document_type': 'purchase_return',
      'status': 'posted',
      'transaction_version': transactionVersion,
      'row_version': rowVersion,
      'original_invoice_id': originalInvoiceId,
      'supplier_id': supplierId,
      'return_date': (returnDate ?? DateTime.now()).toIso8601String(),
      'refund_payment_type': refundPaymentType,
      'line_subtotal': lineSubtotal,
      'discount_amount': discountAmount,
      'tax_percent': taxPercent,
      'total': total,
      'paid_amount': paidAmount,
      if (notes != null) 'notes': notes,
      'created_by_user_id': createdBy,
      if (postedAt != null) 'posted_at': postedAt,
    },
    'lines': lines,
    'inventory': inventory,
    'accounting': accounting,
    'metadata': metadata,
  };
}

Map<String, dynamic> purchaseReturnPostPushEnvelope({
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
  if (aggregateJson['accounting'] is List) {
    aggregateOut['accounting'] = aggregateJson['accounting'];
  }
  envelope['aggregate'] = aggregateOut;
  return envelope;
}

List<Map<String, dynamic>> purchaseReturnLineMapsFromDb(
  List<Map<String, Object?>> rows,
) {
  return rows
      .map(
        (row) => {
          'line_id': (row['id'] ?? '').toString(),
          'product_id': (row['productId'] ?? '').toString(),
          'quantity': (row['quantity'] as num?)?.toDouble() ?? 0,
          'unit_cost': (row['unitCost'] as num?)?.toDouble() ?? 0,
          'line_total': (row['lineTotal'] as num?)?.toDouble(),
        },
      )
      .toList();
}

List<Map<String, dynamic>> purchaseReturnInventoryJsonFromStageData(
  Map<String, Object?> stageData,
) {
  final raw = stageData['inventory_movements'];
  if (raw is List) {
    return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }
  final inventory = stageData['inventory'];
  if (inventory is List) {
    return PurchaseReturnPostEffects.inventoryJson(
      inventory.whereType<PurchaseReturnInventoryEffect>().toList(),
    );
  }
  return const [];
}

List<Map<String, dynamic>> purchaseReturnAccountingJsonFromStageData(
  Map<String, Object?> stageData,
) {
  final raw = stageData['journal_entries'];
  if (raw is List) {
    return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }
  final accounting = stageData['accounting'];
  if (accounting is List) {
    return PurchaseReturnPostEffects.accountingJson(
      accounting.whereType<PurchaseReturnAccountingEffect>().toList(),
    );
  }
  return const [];
}
