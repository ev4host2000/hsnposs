import 'package:mizapos_desktop/services/cloud/sync/posting/sales_invoice/sales_invoice_post_effects.dart';
import 'package:mizapos_desktop/services/cloud/sync/sales_invoice_draft_payload.dart';
import 'package:mizapos_desktop/services/cloud/sync/transactions/models/transaction_aggregate.dart';
import 'package:mizapos_desktop/services/cloud/sync/transactions/transaction_payload_serializer.dart';

/// Builds post aggregate envelope with inventory[] and accounting[] per ADR.
Map<String, dynamic> salesInvoicePostAggregate({
  required String id,
  required String organizationId,
  required String branchId,
  required String createdBy,
  required String customerId,
  required List<Map<String, dynamic>> inventory,
  required List<Map<String, dynamic>> accounting,
  DateTime? invoiceDate,
  String paymentType = 'cash',
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
      'document_type': 'sales_invoice',
      'status': 'posted',
      'transaction_version': transactionVersion,
      'row_version': rowVersion,
      'customer_id': customerId,
      'invoice_date': (invoiceDate ?? DateTime.now()).toIso8601String(),
      'payment_type': paymentType,
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

Map<String, dynamic> salesInvoicePostPushEnvelope({
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
  if (aggregateJson['cash'] is List) {
    aggregateOut['cash'] = aggregateJson['cash'];
  }
  envelope['aggregate'] = aggregateOut;
  return envelope;
}

/// Merges inventory/accounting from raw envelope into a [MapTransactionAggregate].
MapTransactionAggregate salesInvoiceAggregateFromEnvelope(
  Map<String, dynamic> envelope,
) {
  final aggregateRaw = envelope['aggregate'];
  if (aggregateRaw is! Map) {
    throw FormatException('Missing aggregate in envelope');
  }
  final aggregateMap = Map<String, dynamic>.from(aggregateRaw);
  final metadata = aggregateMap['metadata'] is Map
      ? Map<String, dynamic>.from(aggregateMap['metadata'] as Map)
      : <String, dynamic>{};

  if (aggregateMap['inventory'] is List &&
      metadata['inventory'] == null) {
    metadata['inventory'] = aggregateMap['inventory'];
  }
  if (aggregateMap['accounting'] is List &&
      metadata['accounting'] == null) {
    metadata['accounting'] = aggregateMap['accounting'];
  }
  if (aggregateMap['cash'] is List && metadata['cash'] == null) {
    metadata['cash'] = aggregateMap['cash'];
  }

  return MapTransactionAggregate.fromParts(
    header: Map<String, dynamic>.from(aggregateMap['header'] as Map),
    lines: (aggregateMap['lines'] as List?)
            ?.whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList() ??
        const [],
    metadata: metadata,
  );
}

List<Map<String, dynamic>> lineMapsFromDb(
  List<Map<String, Object?>> rows,
) {
  return rows
      .map(
        (row) => salesInvoiceLinePayload(
          lineId: (row['id'] ?? '').toString(),
          productId: (row['productId'] ?? '').toString(),
          quantity: (row['quantity'] as num?)?.toDouble() ?? 0,
          unitPrice: (row['unitPrice'] as num?)?.toDouble() ?? 0,
          lineTotal: (row['lineTotal'] as num?)?.toDouble(),
        ),
      )
      .toList();
}

List<Map<String, dynamic>> inventoryJsonFromStageData(
  Map<String, Object?> stageData,
) {
  final raw = stageData['inventory_movements'];
  if (raw is List) {
    return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }
  final inventory = stageData['inventory'];
  if (inventory is List) {
    return SalesInvoicePostEffects.inventoryJson(
      inventory.whereType<SalesInvoiceInventoryEffect>().toList(),
    );
  }
  return const [];
}

List<Map<String, dynamic>> accountingJsonFromStageData(
  Map<String, Object?> stageData,
) {
  final raw = stageData['journal_entries'];
  if (raw is List) {
    return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }
  final accounting = stageData['accounting'];
  if (accounting is List) {
    return SalesInvoicePostEffects.accountingJson(
      accounting.whereType<SalesInvoiceAccountingEffect>().toList(),
    );
  }
  return const [];
}
