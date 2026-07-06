import 'package:uuid/uuid.dart';

/// Deterministic UUIDs for idempotent opening-stock post effects.
class OpeningStockPostIds {
  OpeningStockPostIds._();

  static const _namespace = '6ba7b810-9dad-11d1-80b4-00c04fd430cc';

  static String stockMovementId(String openingStockId) {
    return const Uuid().v5(_namespace, 'os:$openingStockId:stock');
  }
}
