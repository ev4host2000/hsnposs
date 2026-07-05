import 'package:mizapos_mobile/services/cloud/sync/posting/purchase_invoice/purchase_invoice_post_ids.dart';
import 'package:mizapos_mobile/services/cloud/sync/posting/shared/post_amounts.dart';
import 'package:mizapos_mobile/services/cloud/sync/transactions/models/transaction_aggregate.dart';

class PurchaseInvoiceInventoryEffect {
  const PurchaseInvoiceInventoryEffect({
    required this.movementId,
    required this.productId,
    required this.quantity,
    required this.movementType,
    required this.referenceType,
    required this.referenceId,
    required this.movementDate,
    required this.createdBy,
  });

  final String movementId;
  final String productId;
  final double quantity;
  final String movementType;
  final String referenceType;
  final String referenceId;
  final String movementDate;
  final String createdBy;

  Map<String, dynamic> toJson() => {
        'movement_id': movementId,
        'id': movementId,
        'product_id': productId,
        'quantity': quantity,
        'movement_type': movementType,
        'reference_type': referenceType,
        'reference_id': referenceId,
        'movement_date': movementDate,
        'created_by_user_id': createdBy,
      };

  factory PurchaseInvoiceInventoryEffect.fromJson(Map<String, dynamic> json) {
    final id = (json['movement_id'] ?? json['id'] ?? '').toString();
    return PurchaseInvoiceInventoryEffect(
      movementId: id,
      productId: (json['product_id'] ?? '').toString(),
      quantity: _asDouble(json['quantity']),
      movementType: (json['movement_type'] ?? 'in').toString(),
      referenceType: (json['reference_type'] ?? 'purchase').toString(),
      referenceId: (json['reference_id'] ?? '').toString(),
      movementDate: (json['movement_date'] ?? DateTime.now().toIso8601String())
          .toString(),
      createdBy: (json['created_by_user_id'] ?? 'sync').toString(),
    );
  }
}

class PurchaseInvoiceAccountingEffect {
  const PurchaseInvoiceAccountingEffect({
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
      };

  factory PurchaseInvoiceAccountingEffect.fromJson(Map<String, dynamic> json) {
    final id = (json['entry_id'] ?? json['id'] ?? '').toString();
    return PurchaseInvoiceAccountingEffect(
      entryId: id,
      partnerKind: (json['partner_kind'] ?? 'supplier').toString(),
      partnerId: (json['partner_id'] ?? '').toString(),
      entryType: (json['entry_type'] ?? '').toString(),
      referenceType: (json['reference_type'] ?? 'purchase').toString(),
      referenceId: (json['reference_id'] ?? '').toString(),
      amountSigned: _asDouble(json['amount_signed']),
      entryDate:
          (json['entry_date'] ?? DateTime.now().toIso8601String()).toString(),
      createdBy: (json['created_by_user_id'] ?? 'sync').toString(),
      notes: json['notes']?.toString(),
    );
  }
}

typedef PurchaseInvoicePostAmounts = PostAmounts;

class PurchaseInvoicePostEffects {
  PurchaseInvoicePostEffects._();

  static PurchaseInvoicePostAmounts computeAmounts({
    required List<Map<String, dynamic>> lines,
    required double discountAmount,
    required double taxPercent,
    double? headerTotal,
  }) =>
      computePostAmounts(
        lines: lines,
        discountAmount: discountAmount,
        taxPercent: taxPercent,
        headerTotal: headerTotal,
      );

  static List<PurchaseInvoiceInventoryEffect> buildInventory({
    required String invoiceId,
    required String organizationId,
    required String branchId,
    required List<Map<String, dynamic>> lines,
    required String createdBy,
    String? movementDate,
  }) {
    final when = movementDate ?? DateTime.now().toIso8601String();
    final effects = <PurchaseInvoiceInventoryEffect>[];
    for (final line in lines) {
      final lineId = (line['line_id'] ?? line['id'] ?? '').toString();
      final productId = (line['product_id'] ?? '').toString();
      final quantity = _asDouble(line['quantity']);
      if (lineId.isEmpty || productId.isEmpty || quantity <= 0) continue;
      effects.add(
        PurchaseInvoiceInventoryEffect(
          movementId: PurchaseInvoicePostIds.stockMovementId(invoiceId, lineId),
          productId: productId,
          quantity: quantity,
          movementType: 'in',
          referenceType: 'purchase',
          referenceId: invoiceId,
          movementDate: when,
          createdBy: createdBy,
        ),
      );
    }
    return effects;
  }

  static List<PurchaseInvoiceAccountingEffect> buildAccounting({
    required String invoiceId,
    required String organizationId,
    required String supplierId,
    required PurchaseInvoicePostAmounts amounts,
    required String createdBy,
    String? entryDate,
  }) {
    final when = entryDate ?? DateTime.now().toIso8601String();
    final total = amounts.grandTotal;
    final tax = amounts.taxAmount;
    final netPurchases = amounts.netAmount;
    return [
      PurchaseInvoiceAccountingEffect(
        entryId: PurchaseInvoicePostIds.accountingEntryId(
          invoiceId,
          'dr_purchases',
        ),
        partnerKind: 'supplier',
        partnerId: PurchaseInvoicePostIds.purchaseExpensePartnerId(
          organizationId,
        ),
        entryType: 'purchase_post_dr_purchases',
        referenceType: 'purchase',
        referenceId: invoiceId,
        amountSigned: netPurchases,
        entryDate: when,
        createdBy: createdBy,
        notes: 'Dr Purchases',
      ),
      if (tax > 1e-9)
        PurchaseInvoiceAccountingEffect(
          entryId: PurchaseInvoicePostIds.accountingEntryId(invoiceId, 'dr_tax'),
          partnerKind: 'supplier',
          partnerId: PurchaseInvoicePostIds.taxInputPartnerId(organizationId),
          entryType: 'purchase_post_dr_tax',
          referenceType: 'purchase',
          referenceId: invoiceId,
          amountSigned: tax,
          entryDate: when,
          createdBy: createdBy,
          notes: 'Dr Tax Input',
        ),
      PurchaseInvoiceAccountingEffect(
        entryId: PurchaseInvoicePostIds.accountingEntryId(
          invoiceId,
          'cr_supplier',
        ),
        partnerKind: 'supplier',
        partnerId: supplierId,
        entryType: 'purchase_post_cr_supplier',
        referenceType: 'purchase',
        referenceId: invoiceId,
        amountSigned: -total,
        entryDate: when,
        createdBy: createdBy,
        notes: 'Cr Supplier',
      ),
    ];
  }

  static List<PurchaseInvoiceInventoryEffect> readInventory(
    TransactionAggregate aggregate,
  ) {
    final raw = _readSection(aggregate, 'inventory');
    return raw
        .whereType<Map>()
        .map((e) => PurchaseInvoiceInventoryEffect.fromJson(
              Map<String, dynamic>.from(e),
            ))
        .where((e) => e.movementId.isNotEmpty)
        .toList();
  }

  static List<PurchaseInvoiceAccountingEffect> readAccounting(
    TransactionAggregate aggregate,
  ) {
    final raw = _readSection(aggregate, 'accounting');
    return raw
        .whereType<Map>()
        .map((e) => PurchaseInvoiceAccountingEffect.fromJson(
              Map<String, dynamic>.from(e),
            ))
        .where((e) => e.entryId.isNotEmpty)
        .toList();
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

  static List<Map<String, dynamic>> inventoryJson(
    List<PurchaseInvoiceInventoryEffect> effects,
  ) =>
      effects.map((e) => e.toJson()).toList();

  static List<Map<String, dynamic>> accountingJson(
    List<PurchaseInvoiceAccountingEffect> effects,
  ) =>
      effects.map((e) => e.toJson()).toList();
}

double _asDouble(Object? value, {double fallback = 0}) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? fallback;
}
