import 'package:mizapos_mobile/services/cloud/sync/posting/customer_payment/customer_payment_post_ids.dart';
import 'package:mizapos_mobile/services/cloud/sync/transactions/models/transaction_aggregate.dart';

/// Cash transaction payload for customer payment post aggregate / apply.
class CustomerPaymentCashEffect {
  const CustomerPaymentCashEffect({
    required this.cashTransactionId,
    required this.transactionType,
    required this.amount,
    required this.description,
    required this.referenceType,
    required this.referenceId,
    required this.transactionDate,
    required this.createdBy,
  });

  final String cashTransactionId;
  final String transactionType;
  final double amount;
  final String description;
  final String referenceType;
  final String referenceId;
  final String transactionDate;
  final String createdBy;

  Map<String, dynamic> toJson() => {
        'cash_transaction_id': cashTransactionId,
        'id': cashTransactionId,
        'transaction_type': transactionType,
        'amount': amount,
        'description': description,
        'reference_type': referenceType,
        'reference_id': referenceId,
        'transaction_date': transactionDate,
        'created_by_user_id': createdBy,
      };

  factory CustomerPaymentCashEffect.fromJson(Map<String, dynamic> json) {
    final id = (json['cash_transaction_id'] ?? json['id'] ?? '').toString();
    return CustomerPaymentCashEffect(
      cashTransactionId: id,
      transactionType: (json['transaction_type'] ?? 'in').toString(),
      amount: _asDouble(json['amount']),
      description: (json['description'] ?? '').toString(),
      referenceType: (json['reference_type'] ?? 'customer_payment').toString(),
      referenceId: (json['reference_id'] ?? '').toString(),
      transactionDate:
          (json['transaction_date'] ?? DateTime.now().toIso8601String())
              .toString(),
      createdBy: (json['created_by_user_id'] ?? 'sync').toString(),
    );
  }
}

/// Partner ledger entry payload for customer payment post aggregate / apply.
class CustomerPaymentAccountingEffect {
  const CustomerPaymentAccountingEffect({
    required this.entryId,
    required this.partnerKind,
    required this.partnerId,
    required this.entryType,
    required this.referenceType,
    required this.referenceId,
    required this.amountSigned,
    required this.entryDate,
    required this.createdBy,
    this.notes,
    this.voucherNumber,
  });

  final String entryId;
  final String partnerKind;
  final String partnerId;
  final String entryType;
  final String referenceType;
  final String referenceId;
  final double amountSigned;
  final String entryDate;
  final String createdBy;
  final String? notes;
  final String? voucherNumber;

  Map<String, dynamic> toJson() => {
        'entry_id': entryId,
        'id': entryId,
        'partner_kind': partnerKind,
        'partner_id': partnerId,
        'entry_type': entryType,
        'reference_type': referenceType,
        'reference_id': referenceId,
        'amount_signed': amountSigned,
        'entry_date': entryDate,
        'created_by_user_id': createdBy,
        if (notes != null) 'notes': notes,
        if (voucherNumber != null) 'voucher_number': voucherNumber,
      };

  factory CustomerPaymentAccountingEffect.fromJson(Map<String, dynamic> json) {
    final id = (json['entry_id'] ?? json['id'] ?? '').toString();
    return CustomerPaymentAccountingEffect(
      entryId: id,
      partnerKind: (json['partner_kind'] ?? 'customer').toString(),
      partnerId: (json['partner_id'] ?? '').toString(),
      entryType: (json['entry_type'] ?? 'customer_payment').toString(),
      referenceType: (json['reference_type'] ?? 'customer_payment').toString(),
      referenceId: (json['reference_id'] ?? '').toString(),
      amountSigned: _asDouble(json['amount_signed']),
      entryDate:
          (json['entry_date'] ?? DateTime.now().toIso8601String()).toString(),
      createdBy: (json['created_by_user_id'] ?? 'sync').toString(),
      notes: json['notes']?.toString(),
      voucherNumber: json['voucher_number']?.toString(),
    );
  }
}

/// Builds and reads post effect sections from aggregates.
class CustomerPaymentPostEffects {
  CustomerPaymentPostEffects._();

  static CustomerPaymentCashEffect buildCash({
    required String paymentId,
    required double amount,
    required String createdBy,
    String? description,
    String? transactionDate,
  }) {
    final when = transactionDate ?? DateTime.now().toIso8601String();
    return CustomerPaymentCashEffect(
      cashTransactionId: CustomerPaymentPostIds.cashTransactionId(paymentId),
      transactionType: 'in',
      amount: amount,
      description: description ?? 'تسديد دين عميل',
      referenceType: 'customer_payment',
      referenceId: paymentId,
      transactionDate: when,
      createdBy: createdBy,
    );
  }

  static CustomerPaymentAccountingEffect buildAccounting({
    required String paymentId,
    required String customerId,
    required double amount,
    required String createdBy,
    String? entryDate,
    String? notes,
    String? voucherNumber,
  }) {
    final when = entryDate ?? DateTime.now().toIso8601String();
    return CustomerPaymentAccountingEffect(
      entryId: CustomerPaymentPostIds.accountingEntryId(paymentId),
      partnerKind: 'customer',
      partnerId: customerId,
      entryType: 'customer_payment',
      referenceType: 'customer_payment',
      referenceId: paymentId,
      amountSigned: -amount,
      entryDate: when,
      createdBy: createdBy,
      notes: notes ?? 'دفعة عميل',
      voucherNumber: voucherNumber,
    );
  }

  static CustomerPaymentCashEffect? readCash(TransactionAggregate aggregate) {
    final raw = _readSection(aggregate, 'cash');
    if (raw.isEmpty) return null;
    final first = raw.first;
    if (first is! Map) return null;
    final effect = CustomerPaymentCashEffect.fromJson(
      Map<String, dynamic>.from(first),
    );
    return effect.cashTransactionId.isEmpty ? null : effect;
  }

  static CustomerPaymentAccountingEffect? readAccounting(
    TransactionAggregate aggregate,
  ) {
    final raw = _readSection(aggregate, 'accounting');
    if (raw.isEmpty) return null;
    final first = raw.first;
    if (first is! Map) return null;
    final effect = CustomerPaymentAccountingEffect.fromJson(
      Map<String, dynamic>.from(first),
    );
    return effect.entryId.isEmpty ? null : effect;
  }

  static List<dynamic> _readSection(
    TransactionAggregate aggregate,
    String key,
  ) {
    if (aggregate is MapTransactionAggregate) {
      final json = aggregate.toJson();
      if (json[key] is List) return json[key] as List;
      final meta = aggregate.metadata;
      if (meta is MapTransactionMetadata && meta.extra[key] is List) {
        return meta.extra[key] as List;
      }
    }
    return const [];
  }

  static List<Map<String, dynamic>> cashJson(CustomerPaymentCashEffect effect) =>
      [effect.toJson()];

  static List<Map<String, dynamic>> accountingJson(
    CustomerPaymentAccountingEffect effect,
  ) =>
      [effect.toJson()];
}

double _asDouble(Object? value, {double fallback = 0}) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? fallback;
}
