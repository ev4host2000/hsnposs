/// M1 Dual-mode: Update Contract v2 flag for Taxes.
///
/// Default remains Full Entity (Migration Plan M1).
/// Enable experimentally via [taxesPatchEnabled] = true.
abstract final class TaxSyncContractConfig {
  /// When false (default): enqueue Full Entity `update` (server Adapter path).
  /// When true: enqueue native `patch` with changed_fields + base_row_version.
  static bool taxesPatchEnabled = false;

  /// Embedded Field Dictionary version shipped with this client build.
  static const String dictionaryVersion = '1.0.0';

  /// Contract marker accepted by cloud Phase C.
  static const int contractVersion = 2;

  /// Test helper — restores M1 production default.
  static void resetToM1Defaults() {
    taxesPatchEnabled = false;
  }
}
