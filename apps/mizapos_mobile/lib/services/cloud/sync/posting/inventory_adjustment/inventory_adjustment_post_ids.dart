import 'package:uuid/uuid.dart';

/// Deterministic UUIDs for idempotent inventory-adjustment post effects.
class InventoryAdjustmentPostIds {
  InventoryAdjustmentPostIds._();

  static const _namespace = '6ba7b810-9dad-11d1-80b4-00c04fd430cc';

  static String stockMovementId(String adjustmentId) {
    return const Uuid().v5(_namespace, 'ia:$adjustmentId:stock');
  }
}
