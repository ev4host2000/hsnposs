import 'package:mizapos_desktop/services/cloud/sync/posting/purchase_return/purchase_return_post_ids.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/shared/post_amounts.dart';
import 'package:mizapos_desktop/services/cloud/sync/transactions/models/transaction_aggregate.dart';

class PurchaseReturnInventoryEffect {
  const PurchaseReturnInventoryEffect({
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

  factory PurchaseReturnInventoryEffect.fromJson(Map<String, dynamic> json) {
    final id = (json['movement_id'] ?? json['id'] ?? '').toString();
    return PurchaseReturnInventoryEffect(
      movementId: id,
      productId: (json['product_id'] ?? '').toString(),
      quantity: _asDouble(json['quantity']),
      movementType: (json['movement_type'] ?? 'in').toString(),
      referenceType: (json['reference_type'] ?? 'purchase_return').toString(),
      referenceId: (json['reference_id'] ?? '').toString(),
      movementDate: (json['movement_date'] ?? DateTime.now().toIso8601String())
          .toString(),
      createdBy: (json['created_by_user_id'] ?? 'sync').toString(),
    );
  }
}

class PurchaseReturnAccountingEffect {
  const PurchaseReturnAccountingEffect({
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

  factory PurchaseReturnAccountingEffect.fromJson(Map<String, dynamic> json) {
    final id = (json['entry_id'] ?? json['id'] ?? '').toString();
    return PurchaseReturnAccountingEffect(
      entryId: id,
      partnerKind: (json['partner_kind'] ?? 'supplier').toString(),
      partnerId: (json['partner_id'] ?? '').toString(),
      entryType: (json['entry_type'] ?? '').toString(),
      referenceType: (json['reference_type'] ?? 'purchase_return').toString(),
      referenceId: (json['reference_id'] ?? '').toString(),
      amountSigned: _asDouble(json['amount_signed']),
      entryDate:
          (json['entry_date'] ?? DateTime.now().toIso8601String()).toString(),
      createdBy: (json['created_by_user_id'] ?? 'sync').toString(),
      notes: json['notes']?.toString(),
    );
  }
}

typedef PurchaseReturnPostAmounts = PostAmounts;

class PurchaseReturnPostEffects {
  PurchaseReturnPostEffects._();

  static PurchaseReturnPostAmounts computeAmounts({
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

  static List<PurchaseReturnInventoryEffect> buildInventory({
    required String returnId,
    required String organizationId,
    required String branchId,
    required List<Map<String, dynamic>> lines,
    required String createdBy,
    String? movementDate,
  }) {
    final when = movementDate ?? DateTime.now().toIso8601String();
    final effects = <PurchaseReturnInventoryEffect>[];
    for (final line in lines) {
      final lineId = (line['line_id'] ?? line['id'] ?? '').toString();
      final productId = (line['product_id'] ?? '').toString();
      final quantity = _asDouble(line['quantity']);
      if (lineId.isEmpty || productId.isEmpty || quantity <= 0) continue;
      effects.add(
        PurchaseReturnInventoryEffect(
          movementId: PurchaseReturnPostIds.stockMovementId(returnId, lineId),
          productId: productId,
          quantity: quantity,
          movementType: 'out',
          referenceType: 'purchase_return',
          referenceId: returnId,
          movementDate: when,
          createdBy: createdBy,
        ),
      );
    }
    return effects;
  }

  static List<PurchaseReturnAccountingEffect> buildAccounting({
    required String returnId,
    required String organizationId,
    required String supplierId,
    required PurchaseReturnPostAmounts amounts,
    required String createdBy,
    String? entryDate,
  }) {
    final when = entryDate ?? DateTime.now().toIso8601String();
    final total = amounts.grandTotal;
    final tax = amounts.taxAmount;
    final netPurchases = amounts.netAmount;
    return [
      PurchaseReturnAccountingEffect(
        entryId: PurchaseReturnPostIds.accountingEntryId(
          returnId,
          'cr_purchases',
        ),
        partnerKind: 'supplier',
        partnerId: PurchaseReturnPostIds.purchaseExpensePartnerId(
          organizationId,
        ),
        entryType: 'purchase_return_cr_purchases',
        referenceType: 'purchase_return',
        referenceId: returnId,
        amountSigned: -netPurchases,
        entryDate: when,
        createdBy: createdBy,
        notes: 'Cr Purchases',
      ),
      if (tax > 1e-9)
        PurchaseReturnAccountingEffect(
          entryId: PurchaseReturnPostIds.accountingEntryId(returnId, 'cr_tax'),
          partnerKind: 'supplier',
          partnerId: PurchaseReturnPostIds.taxInputPartnerId(organizationId),
          entryType: 'purchase_return_cr_tax',
          referenceType: 'purchase_return',
          referenceId: returnId,
          amountSigned: -tax,
          entryDate: when,
          createdBy: createdBy,
          notes: 'Cr Tax Input',
        ),
      PurchaseReturnAccountingEffect(
        entryId: PurchaseReturnPostIds.accountingEntryId(
          returnId,
          'dr_supplier',
        ),
        partnerKind: 'supplier',
        partnerId: supplierId,
        entryType: 'purchase_return_dr_supplier',
        referenceType: 'purchase_return',
        referenceId: returnId,
        amountSigned: total,
        entryDate: when,
        createdBy: createdBy,
        notes: 'Dr Supplier',
      ),
    ];
  }

  static List<PurchaseReturnInventoryEffect> readInventory(
    TransactionAggregate aggregate,
  ) {
    final raw = _readSection(aggregate, 'inventory');
    return raw
        .whereType<Map>()
        .map((e) => PurchaseReturnInventoryEffect.fromJson(
              Map<String, dynamic>.from(e),
            ))
        .where((e) => e.movementId.isNotEmpty)
        .toList();
  }

  static List<PurchaseReturnAccountingEffect> readAccounting(
    TransactionAggregate aggregate,
  ) {
    final raw = _readSection(aggregate, 'accounting');
    return raw
        .whereType<Map>()
        .map((e) => PurchaseReturnAccountingEffect.fromJson(
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
    List<PurchaseReturnInventoryEffect> effects,
  ) =>
      effects.map((e) => e.toJson()).toList();

  static List<Map<String, dynamic>> accountingJson(
    List<PurchaseReturnAccountingEffect> effects,
  ) =>
      effects.map((e) => e.toJson()).toList();
}

double _asDouble(Object? value, {double fallback = 0}) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? fallback;
}
