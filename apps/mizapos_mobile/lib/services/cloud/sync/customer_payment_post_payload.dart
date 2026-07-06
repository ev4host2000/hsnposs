import 'package:mizapos_mobile/services/cloud/sync/posting/customer_payment/customer_payment_post_effects.dart';
import 'package:mizapos_mobile/services/cloud/sync/transactions/models/transaction_aggregate.dart';
import 'package:mizapos_mobile/services/cloud/sync/transactions/transaction_payload_serializer.dart';

Map<String, dynamic> customerPaymentPostAggregate({
  required String id,
  required String organizationId,
  required String branchId,
  required String createdBy,
  required String customerId,
  required double amount,
  required List<Map<String, dynamic>> cash,
  required List<Map<String, dynamic>> accounting,
  DateTime? paymentDate,
  String paymentMethod = 'cash',
  String? voucherNumber,
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
    'cash': cash,
    'accounting': accounting,
  };

  return {
    'header': {
      'id': id,
      'company_id': organizationId,
      'branch_id': branchId,
      'document_type': 'customer_payment',
      'status': 'posted',
      'transaction_version': transactionVersion,
      'row_version': rowVersion,
      'customer_id': customerId,
      'amount': amount,
      'payment_date': (paymentDate ?? DateTime.now()).toIso8601String(),
      'payment_method': paymentMethod,
      if (voucherNumber != null) 'voucher_number': voucherNumber,
      if (notes != null) 'notes': notes,
      'created_by_user_id': createdBy,
      if (postedAt != null) 'posted_at': postedAt,
    },
    'lines': lines,
    'cash': cash,
    'accounting': accounting,
    'metadata': metadata,
  };
}

Map<String, dynamic> customerPaymentPostPushEnvelope({
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
  if (aggregateJson['cash'] is List) {
    aggregateOut['cash'] = aggregateJson['cash'];
  }
  if (aggregateJson['accounting'] is List) {
    aggregateOut['accounting'] = aggregateJson['accounting'];
  }
  envelope['aggregate'] = aggregateOut;
  return envelope;
}

List<Map<String, dynamic>> customerPaymentCashJsonFromStageData(
  Map<String, Object?> stageData,
) {
  final raw = stageData['cash_transactions'];
  if (raw is List) {
    return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }
  final cash = stageData['cash'];
  if (cash is CustomerPaymentCashEffect) {
    return CustomerPaymentPostEffects.cashJson(cash);
  }
  return const [];
}

List<Map<String, dynamic>> customerPaymentAccountingJsonFromStageData(
  Map<String, Object?> stageData,
) {
  final raw = stageData['journal_entries'];
  if (raw is List) {
    return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }
  final accounting = stageData['accounting'];
  if (accounting is CustomerPaymentAccountingEffect) {
    return CustomerPaymentPostEffects.accountingJson(accounting);
  }
  return const [];
}
