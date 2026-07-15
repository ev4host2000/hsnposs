/// M1 Dual-mode: Update Contract v2 flag for Product Units.
///
/// Default remains Full Entity (Migration Plan M1).
/// Enable experimentally via [unitsPatchEnabled] = true.
abstract final class UnitSyncContractConfig {
  /// When false (default): enqueue Full Entity `update` (server Adapter path).
  /// When true: enqueue native `patch` with changed_fields + base_row_version.
  static bool unitsPatchEnabled = false;

  /// Embedded Field Dictionary version shipped with this client build.
  static const String dictionaryVersion = '1.0.0';

  /// Contract marker accepted by cloud Phase C.
  static const int contractVersion = 2;

  /// Test helper — restores M1 production default.
  static void resetToM1Defaults() {
    unitsPatchEnabled = false;
  }
}
