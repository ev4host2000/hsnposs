/// Inventory adjustment draft/post sync identifiers.
class InventoryAdjustmentSyncConstants {
  InventoryAdjustmentSyncConstants._();

  static const entityType = 'inventory_adjustment';
  static const scopeKey = 'inventory_adjustments';

  static const pushPath = '/sync/push/inventory-adjustments';
  static const pullPath = '/sync/pull/inventory-adjustments';
}
