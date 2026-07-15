/// M1 Dual-mode: Update Contract v2 flag for Products only.
///
/// Default remains Full Entity (Migration Plan M1).
/// Enable experimentally via [productsPatchEnabled] = true.
abstract final class ProductSyncContractConfig {
  /// When false (default): enqueue Full Entity `update` (server Adapter path).
  /// When true: enqueue native `patch` with changed_fields + base_row_version.
  static bool productsPatchEnabled = false;

  /// Embedded Field Dictionary version shipped with this client build.
  static const String dictionaryVersion = '1.0.0';

  /// Contract marker accepted by cloud Phase B.
  static const int contractVersion = 2;

  /// Test helper â€” restores M1 production default.
  static void resetToM1Defaults() {
    productsPatchEnabled = false;
  }
}
