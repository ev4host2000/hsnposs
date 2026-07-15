import 'package:flutter/foundation.dart';
import 'package:mizapos_desktop/services/cloud/core/cloud_onboarding_service.dart';
import 'package:mizapos_desktop/services/cloud/sync/background/sync_bootstrap.dart';
import 'package:mizapos_desktop/services/cloud/sync/background/models/sync_status_snapshot.dart';
import 'package:mizapos_desktop/services/store_settings_ui_prefs.dart';

/// تفضيل opt-in لمزامنة Miza Cloud على سطح المكتب — يُحفظ في `store_settings.json`.
class CloudSyncController extends ChangeNotifier {
  CloudSyncController._();

  static final CloudSyncController instance = CloudSyncController._();

  bool _enabled = false;

  bool get isEnabled => _enabled;

  Future<void> loadFromDisk() async {
    final prefs = await loadStoreUiPreferences();
    await applyFromPreferences(prefs.cloudSyncEnabled);
  }

  /// يفعّل المزامنة التلقائية عندما تكون جلسة Miza Cloud جاهزة (دخول + جهاز مربوط).
  /// يُستدعى عند الإقلاع وربط الجهاز وفتح شاشة Miza Cloud — دون الحاجة لتفعيل يدوي من الإعدادات.
  Future<bool> ensureEnabledWhenCloudSessionReady() async {
    final onboarding = CloudOnboardingService();
    if (!await onboarding.isCloudSessionReady()) return false;
    if (_enabled) return true;

    await patchStoreUiPreferences(
      (current) => current.copyWith(cloudSyncEnabled: true),
    );
    await applyFromPreferences(true);
    if (kDebugMode) {
      debugPrint('CloudSyncController: auto-enabled cloud sync (session ready)');
    }
    return true;
  }

  Future<void> applyFromPreferences(bool enabled) async {
    if (_enabled == enabled) return;
    _enabled = enabled;
    notifyListeners();
    if (enabled) {
      // RC-1: await scheduler (serialized via job chain) — no fire-and-forget.
      await BackgroundSyncBootstrap.scheduler?.triggerSync(
        SyncTrigger.appResume,
        force: true,
      );
    }
  }

  Future<void> refreshBackgroundSchedule() async {
    // سطح المكتب يعتمد على SyncScheduler الدوري — لا WorkManager.
  }

  Future<void> setEnabled(bool enabled) async {
    await patchStoreUiPreferences(
      (current) => current.copyWith(cloudSyncEnabled: enabled),
    );
    await applyFromPreferences(enabled);
  }
}
