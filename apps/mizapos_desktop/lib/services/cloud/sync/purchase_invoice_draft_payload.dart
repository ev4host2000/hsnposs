import 'package:mizapos_desktop/services/cloud/sync/transactions/models/transaction_aggregate.dart';
import 'package:mizapos_desktop/services/cloud/sync/transactions/transaction_payload_serializer.dart';

Map<String, dynamic> purchaseInvoiceDraftAggregate({
  required String id,
  required String organizationId,
  required String branchId,
  required String createdBy,
  String? supplierId,
  DateTime? invoiceDate,
  String paymentType = 'cash',
  double lineSubtotal = 0,
  double discountAmount = 0,
  double taxPercent = 0,
  double total = 0,
  double paidAmount = 0,
  String? notes,
  int transactionVersion = 0,
  int rowVersion = 1,
  String status = 'draft',
  List<Map<String, dynamic>> lines = const [],
  String? originDeviceId,
}) {
  return MapTransactionAggregate.fromParts(
    header: {
      'id': id,
      'company_id': organizationId,
      'branch_id': branchId,
      'document_type': 'purchase_invoice',
      'status': status,
      'transaction_version': transactionVersion,
      'row_version': rowVersion,
      'supplier_id': supplierId,
      'invoice_date': (invoiceDate ?? DateTime.now()).toIso8601String(),
      'payment_type': paymentType,
      'line_subtotal': lineSubtotal,
      'discount_amount': discountAmount,
      'tax_percent': taxPercent,
      'total': total,
      'paid_amount': paidAmount,
      if (notes != null) 'notes': notes,
      'created_by_user_id': createdBy,
    },
    lines: lines,
    metadata: {
      'payload_schema_version': 1,
      if (originDeviceId != null) 'origin_device_id': originDeviceId,
    },
  ).toJson();
}

Map<String, dynamic> purchaseInvoiceDraftPushEnvelope({
  required Map<String, dynamic> aggregateJson,
  required String operation,
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

  return TransactionPayloadSerializer().envelope(
    aggregate: aggregate,
    operation: operation,
    clientRowVersion: clientRowVersion,
    idempotencyKey: idempotencyKey,
  );
}

Map<String, dynamic> purchaseInvoiceLinePayload({
  required String lineId,
  required String productId,
  required double quantity,
  required double unitCost,
  double? lineTotal,
}) {
  final total = lineTotal ?? (quantity * unitCost);
  return {
    'line_id': lineId,
    'id': lineId,
    'product_id': productId,
    'quantity': quantity,
    'unit_cost': unitCost,
    'line_total': total,
  };
}
