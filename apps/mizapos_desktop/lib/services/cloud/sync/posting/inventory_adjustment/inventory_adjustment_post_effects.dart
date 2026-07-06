import 'package:mizapos_desktop/services/cloud/sync/posting/inventory_adjustment/inventory_adjustment_post_ids.dart';
import 'package:mizapos_desktop/services/cloud/sync/transactions/models/transaction_aggregate.dart';

/// Inventory movement payload for post aggregate / apply.
class InventoryAdjustmentInventoryEffect {
  const InventoryAdjustmentInventoryEffect({
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

  factory InventoryAdjustmentInventoryEffect.fromJson(Map<String, dynamic> json) {
    final id = (json['movement_id'] ?? json['id'] ?? '').toString();
    return InventoryAdjustmentInventoryEffect(
      movementId: id,
      productId: (json['product_id'] ?? '').toString(),
      quantity: _asDouble(json['quantity']),
      movementType: (json['movement_type'] ?? 'in').toString(),
      referenceType:
          (json['reference_type'] ?? 'inventory_adjustment').toString(),
      referenceId: (json['reference_id'] ?? '').toString(),
      movementDate: (json['movement_date'] ?? DateTime.now().toIso8601String())
          .toString(),
      createdBy: (json['created_by_user_id'] ?? 'sync').toString(),
    );
  }
}

/// Builds and reads post effect sections from aggregates.
class InventoryAdjustmentPostEffects {
  InventoryAdjustmentPostEffects._();

  static const allowedReasons = {
    'count',
    'damage',
    'loss',
    'gain',
    'correction',
  };

  /// Reads `adjustment_reason` or legacy cloud `reason` (e.g. cycle_count → count).
  static String normalizeReason(Map<String, Object?> extra) {
    final raw = (extra['adjustment_reason'] ?? extra['reason'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    if (raw == 'cycle_count') return 'count';
    return raw;
  }

  static bool isAllowedReason(String reason) =>
      allowedReasons.contains(normalizeReason({'adjustment_reason': reason}));

  static InventoryAdjustmentInventoryEffect buildInventory({
    required String adjustmentId,
    required String productId,
    required double quantityDelta,
    required String createdBy,
    String? movementDate,
  }) {
    final when = movementDate ?? DateTime.now().toIso8601String();
    final isIncrease = quantityDelta > 0;
    return InventoryAdjustmentInventoryEffect(
      movementId: InventoryAdjustmentPostIds.stockMovementId(adjustmentId),
      productId: productId,
      quantity: quantityDelta.abs(),
      movementType: isIncrease ? 'in' : 'out',
      referenceType: 'inventory_adjustment',
      referenceId: adjustmentId,
      movementDate: when,
      createdBy: createdBy,
    );
  }

  static InventoryAdjustmentInventoryEffect? readInventory(
    TransactionAggregate aggregate,
  ) {
    final raw = _readSection(aggregate, 'inventory');
    if (raw.isEmpty) return null;
    final first = raw.first;
    if (first is! Map) return null;
    final effect = InventoryAdjustmentInventoryEffect.fromJson(
      Map<String, dynamic>.from(first),
    );
    return effect.movementId.isEmpty ? null : effect;
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
    InventoryAdjustmentInventoryEffect effect,
  ) =>
      [effect.toJson()];
}

double _asDouble(Object? value, {double fallback = 0}) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? fallback;
}
