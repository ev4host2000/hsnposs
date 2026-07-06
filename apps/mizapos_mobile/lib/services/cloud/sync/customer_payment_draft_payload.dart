import 'package:mizapos_mobile/services/cloud/sync/transactions/models/transaction_aggregate.dart';
import 'package:mizapos_mobile/services/cloud/sync/transactions/transaction_payload_serializer.dart';

Map<String, dynamic> customerPaymentDraftAggregate({
  required String id,
  required String organizationId,
  required String branchId,
  required String createdBy,
  required String customerId,
  required double amount,
  DateTime? paymentDate,
  String paymentMethod = 'cash',
  String? voucherNumber,
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
      'document_type': 'customer_payment',
      'status': status,
      'transaction_version': transactionVersion,
      'row_version': rowVersion,
      'customer_id': customerId,
      'amount': amount,
      'payment_date': (paymentDate ?? DateTime.now()).toIso8601String(),
      'payment_method': paymentMethod,
      if (voucherNumber != null) 'voucher_number': voucherNumber,
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

Map<String, dynamic> customerPaymentDraftPushEnvelope({
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
