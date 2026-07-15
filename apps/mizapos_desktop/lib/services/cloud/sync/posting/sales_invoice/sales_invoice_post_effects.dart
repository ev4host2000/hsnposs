import 'package:mizapos_desktop/services/cloud/sync/posting/sales_invoice/sales_invoice_post_ids.dart';
import 'package:mizapos_desktop/services/cloud/sync/posting/shared/post_amounts.dart';
import 'package:mizapos_desktop/services/cloud/sync/transactions/models/transaction_aggregate.dart';

/// Inventory movement payload for post aggregate / apply.
class SalesInvoiceInventoryEffect {
  const SalesInvoiceInventoryEffect({
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

  factory SalesInvoiceInventoryEffect.fromJson(Map<String, dynamic> json) {
    final id = (json['movement_id'] ?? json['id'] ?? '').toString();
    return SalesInvoiceInventoryEffect(
      movementId: id,
      productId: (json['product_id'] ?? '').toString(),
      quantity: _asDouble(json['quantity']),
      movementType: (json['movement_type'] ?? 'out').toString(),
      referenceType: (json['reference_type'] ?? 'sale').toString(),
      referenceId: (json['reference_id'] ?? '').toString(),
      movementDate: (json['movement_date'] ?? DateTime.now().toIso8601String())
          .toString(),
      createdBy: (json['created_by_user_id'] ?? 'sync').toString(),
    );
  }
}

/// Accounting entry payload for post aggregate / apply.
class SalesInvoiceAccountingEffect {
  const SalesInvoiceAccountingEffect({
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

  factory SalesInvoiceAccountingEffect.fromJson(Map<String, dynamic> json) {
    final id = (json['entry_id'] ?? json['id'] ?? '').toString();
    return SalesInvoiceAccountingEffect(
      entryId: id,
      partnerKind: (json['partner_kind'] ?? 'customer').toString(),
      partnerId: (json['partner_id'] ?? '').toString(),
      entryType: (json['entry_type'] ?? '').toString(),
      referenceType: (json['reference_type'] ?? 'sale').toString(),
      referenceId: (json['reference_id'] ?? '').toString(),
      amountSigned: _asDouble(json['amount_signed']),
      entryDate:
          (json['entry_date'] ?? DateTime.now().toIso8601String()).toString(),
      createdBy: (json['created_by_user_id'] ?? 'sync').toString(),
      notes: json['notes']?.toString(),
    );
  }
}

class SalesInvoicePostAmounts {
  const SalesInvoicePostAmounts({
    required this.lineSubtotal,
    required this.discountAmount,
    required this.taxAmount,
    required this.grandTotal,
  });

  final double lineSubtotal;
  final double discountAmount;
  final double taxAmount;
  final double grandTotal;

  double get netSales => grandTotal - taxAmount;
}

/// Builds and reads post effect sections from aggregates.
class SalesInvoicePostEffects {
  SalesInvoicePostEffects._();

  static SalesInvoicePostAmounts computeAmounts({
    required List<Map<String, dynamic>> lines,
    required double discountAmount,
    required double taxPercent,
    double? headerTotal,
  }) {
    final amounts = computePostAmounts(
      lines: lines,
      discountAmount: discountAmount,
      taxPercent: taxPercent,
      headerTotal: headerTotal,
    );
    return SalesInvoicePostAmounts(
      lineSubtotal: amounts.lineSubtotal,
      discountAmount: amounts.discountAmount,
      taxAmount: amounts.taxAmount,
      grandTotal: amounts.grandTotal,
    );
  }

  static List<SalesInvoiceInventoryEffect> buildInventory({
    required String invoiceId,
    required String organizationId,
    required String branchId,
    required List<Map<String, dynamic>> lines,
    required String createdBy,
    String? movementDate,
  }) {
    final when = movementDate ?? DateTime.now().toIso8601String();
    final effects = <SalesInvoiceInventoryEffect>[];
    for (final line in lines) {
      final lineId = (line['line_id'] ?? line['id'] ?? '').toString();
      final productId = (line['product_id'] ?? '').toString();
      final quantity = _asDouble(line['quantity']);
      if (lineId.isEmpty || productId.isEmpty || quantity <= 0) continue;
      effects.add(
        SalesInvoiceInventoryEffect(
          movementId: SalesInvoicePostIds.stockMovementId(invoiceId, lineId),
          productId: productId,
          quantity: quantity,
          movementType: 'out',
          referenceType: 'sale',
          referenceId: invoiceId,
          movementDate: when,
          createdBy: createdBy,
        ),
      );
    }
    return effects;
  }

  static List<SalesInvoiceAccountingEffect> buildAccounting({
    required String invoiceId,
    required String organizationId,
    required String customerId,
    required SalesInvoicePostAmounts amounts,
    required String createdBy,
    String? entryDate,
  }) {
    final when = entryDate ?? DateTime.now().toIso8601String();
    final total = amounts.grandTotal;
    final tax = amounts.taxAmount;
    final netSales = amounts.netSales;
    return [
      SalesInvoiceAccountingEffect(
        entryId: SalesInvoicePostIds.accountingEntryId(invoiceId, 'dr_customer'),
        partnerKind: 'customer',
        partnerId: customerId,
        entryType: 'sale_post_dr',
        referenceType: 'sale',
        referenceId: invoiceId,
        amountSigned: total,
        entryDate: when,
        createdBy: createdBy,
        notes: 'Dr Customer',
      ),
      SalesInvoiceAccountingEffect(
        entryId: SalesInvoicePostIds.accountingEntryId(invoiceId, 'cr_sales'),
        partnerKind: 'supplier',
        partnerId: SalesInvoicePostIds.salesRevenuePartnerId(organizationId),
        entryType: 'sale_post_cr_sales',
        referenceType: 'sale',
        referenceId: invoiceId,
        amountSigned: -netSales,
        entryDate: when,
        createdBy: createdBy,
        notes: 'Cr Sales',
      ),
      if (tax > 1e-9)
        SalesInvoiceAccountingEffect(
          entryId: SalesInvoicePostIds.accountingEntryId(invoiceId, 'cr_tax'),
          partnerKind: 'supplier',
          partnerId: SalesInvoicePostIds.taxPayablePartnerId(organizationId),
          entryType: 'sale_post_cr_tax',
          referenceType: 'sale',
          referenceId: invoiceId,
          amountSigned: -tax,
          entryDate: when,
          createdBy: createdBy,
          notes: 'Cr Tax',
        ),
    ];
  }

  static List<SalesInvoiceInventoryEffect> readInventory(
    TransactionAggregate aggregate,
  ) {
    final raw = _readSection(aggregate, 'inventory');
    return raw
        .whereType<Map>()
        .map((e) => SalesInvoiceInventoryEffect.fromJson(
              Map<String, dynamic>.from(e),
            ))
        .where((e) => e.movementId.isNotEmpty)
        .toList();
  }

  static List<SalesInvoiceAccountingEffect> readAccounting(
    TransactionAggregate aggregate,
  ) {
    final raw = _readSection(aggregate, 'accounting');
    return raw
        .whereType<Map>()
        .map((e) => SalesInvoiceAccountingEffect.fromJson(
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
    List<SalesInvoiceInventoryEffect> effects,
  ) =>
      effects.map((e) => e.toJson()).toList();

  static List<Map<String, dynamic>> accountingJson(
    List<SalesInvoiceAccountingEffect> effects,
  ) =>
      effects.map((e) => e.toJson()).toList();
}

double _asDouble(Object? value, {double fallback = 0}) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? fallback;
}
