import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:mizapos_desktop/services/store_settings_ui_prefs.dart';

/// سياسة الشبكة لمزامنة Miza Cloud — Wi‑Fi/Ethernet فقط عند تفعيل الإعداد.
abstract final class CloudSyncNetworkPolicy {
  static Future<bool> allowsSync() async {
    final prefs = await loadStoreUiPreferences();
    if (!prefs.cloudSyncEnabled) return false;
    if (!prefs.cloudSyncWifiOnly) return true;

    final results = await Connectivity().checkConnectivity();
    if (results.isEmpty) return false;
    return results.any(
      (r) =>
          r == ConnectivityResult.wifi || r == ConnectivityResult.ethernet,
    );
  }
}
