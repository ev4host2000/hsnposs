import 'package:mizapos_desktop/services/cloud/sync/posting/supplier_payment/supplier_payment_post_ids.dart';
import 'package:mizapos_desktop/services/cloud/sync/transactions/models/transaction_aggregate.dart';

/// Cash transaction payload for supplier payment post aggregate / apply.
class SupplierPaymentCashEffect {
  const SupplierPaymentCashEffect({
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

  factory SupplierPaymentCashEffect.fromJson(Map<String, dynamic> json) {
    final id = (json['cash_transaction_id'] ?? json['id'] ?? '').toString();
    return SupplierPaymentCashEffect(
      cashTransactionId: id,
      transactionType: (json['transaction_type'] ?? 'out').toString(),
      amount: _asDouble(json['amount']),
      description: (json['description'] ?? '').toString(),
      referenceType: (json['reference_type'] ?? 'supplier_payment').toString(),
      referenceId: (json['reference_id'] ?? '').toString(),
      transactionDate:
          (json['transaction_date'] ?? DateTime.now().toIso8601String())
              .toString(),
      createdBy: (json['created_by_user_id'] ?? 'sync').toString(),
    );
  }
}

/// Partner ledger entry payload for supplier payment post aggregate / apply.
class SupplierPaymentAccountingEffect {
  const SupplierPaymentAccountingEffect({
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

  factory SupplierPaymentAccountingEffect.fromJson(Map<String, dynamic> json) {
    final id = (json['entry_id'] ?? json['id'] ?? '').toString();
    return SupplierPaymentAccountingEffect(
      entryId: id,
      partnerKind: (json['partner_kind'] ?? 'supplier').toString(),
      partnerId: (json['partner_id'] ?? '').toString(),
      entryType: (json['entry_type'] ?? 'supplier_payment').toString(),
      referenceType: (json['reference_type'] ?? 'supplier_payment').toString(),
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
class SupplierPaymentPostEffects {
  SupplierPaymentPostEffects._();

  static SupplierPaymentCashEffect buildCash({
    required String paymentId,
    required double amount,
    required String createdBy,
    String? description,
    String? transactionDate,
  }) {
    final when = transactionDate ?? DateTime.now().toIso8601String();
    return SupplierPaymentCashEffect(
      cashTransactionId: SupplierPaymentPostIds.cashTransactionId(paymentId),
      transactionType: 'out',
      amount: amount,
      description: description ?? 'سداد ذمة مورد',
      referenceType: 'supplier_payment',
      referenceId: paymentId,
      transactionDate: when,
      createdBy: createdBy,
    );
  }

  static SupplierPaymentAccountingEffect buildAccounting({
    required String paymentId,
    required String supplierId,
    required double amount,
    required String createdBy,
    String? entryDate,
    String? notes,
    String? voucherNumber,
  }) {
    final when = entryDate ?? DateTime.now().toIso8601String();
    return SupplierPaymentAccountingEffect(
      entryId: SupplierPaymentPostIds.accountingEntryId(paymentId),
      partnerKind: 'supplier',
      partnerId: supplierId,
      entryType: 'supplier_payment',
      referenceType: 'supplier_payment',
      referenceId: paymentId,
      amountSigned: -amount,
      entryDate: when,
      createdBy: createdBy,
      notes: notes ?? 'دفعة مورد',
      voucherNumber: voucherNumber,
    );
  }

  static SupplierPaymentCashEffect? readCash(TransactionAggregate aggregate) {
    final raw = _readSection(aggregate, 'cash');
    if (raw.isEmpty) return null;
    final first = raw.first;
    if (first is! Map) return null;
    final effect = SupplierPaymentCashEffect.fromJson(
      Map<String, dynamic>.from(first),
    );
    return effect.cashTransactionId.isEmpty ? null : effect;
  }

  static SupplierPaymentAccountingEffect? readAccounting(
    TransactionAggregate aggregate,
  ) {
    final raw = _readSection(aggregate, 'accounting');
    if (raw.isEmpty) return null;
    final first = raw.first;
    if (first is! Map) return null;
    final effect = SupplierPaymentAccountingEffect.fromJson(
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

  static List<Map<String, dynamic>> cashJson(SupplierPaymentCashEffect effect) =>
      [effect.toJson()];

  static List<Map<String, dynamic>> accountingJson(
    SupplierPaymentAccountingEffect effect,
  ) =>
      [effect.toJson()];
}

double _asDouble(Object? value, {double fallback = 0}) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? fallback;
}
