import 'package:flutter/foundation.dart';
import 'package:mizapos_desktop/services/cloud/api/cloud_api_auth_coordinator.dart';
import 'package:mizapos_desktop/services/cloud/api/cloud_api_client.dart';
import 'package:mizapos_desktop/services/cloud/api/cloud_http_client_io.dart';
import 'package:mizapos_desktop/services/cloud/auth/auth_api.dart';
import 'package:mizapos_desktop/services/cloud/auth/auth_manager.dart';
import 'package:mizapos_desktop/services/cloud/auth/auth_repository.dart';
import 'package:mizapos_desktop/services/cloud/auth/auth_service.dart';
import 'package:mizapos_desktop/services/cloud/config/cloud_config.dart';
import 'package:mizapos_desktop/services/cloud/devices/device_api.dart';
import 'package:mizapos_desktop/services/cloud/devices/device_manager.dart';
import 'package:mizapos_desktop/services/cloud/devices/device_repository.dart';
import 'package:mizapos_desktop/services/cloud/devices/device_service.dart';
import 'package:mizapos_desktop/services/cloud/storage/cloud_secure_storage.dart';
import 'package:mizapos_desktop/services/cloud/storage/cloud_secure_storage_production.dart';

/// نقطة دخول موحّدة لطبقة Miza Cloud — auth، devices، HTTP.
class CloudRuntime {
  CloudRuntime._({
    required this.config,
    required this.storage,
    required this.apiClient,
    required this.authManager,
    required this.deviceManager,
  });

  static CloudRuntime? _instance;

  static CloudRuntime? get instance => _instance;

  final CloudConfig config;
  final CloudSecureStorage storage;
  final CloudApiClient apiClient;
  final AuthManager authManager;
  final DeviceManager deviceManager;

  static Future<CloudRuntime> initialize({
    CloudSecureStorage? storage,
    CloudConfig? config,
  }) async {
    if (_instance != null) return _instance!;

    final resolvedStorage =
        storage ?? await CloudSecureStorageProduction.create();
    final resolvedConfig = config ?? CloudConfig.forAppRuntime();

    const httpClient = CloudHttpClientIo();
    final authCoordinator = CloudApiAuthCoordinator(
      httpClient: httpClient,
      config: resolvedConfig,
      storage: resolvedStorage,
    );

    final apiClient = CloudApiClient(
      httpClient: httpClient,
      config: resolvedConfig,
      storage: resolvedStorage,
      authCoordinator: authCoordinator,
    );

    final authService = AuthService(
      repository: AuthRepository(
        authApi: AuthApi(apiClient: apiClient, config: resolvedConfig),
        storage: resolvedStorage,
      ),
      config: resolvedConfig,
    );

    final deviceService = DeviceService(
      repository: DeviceRepository(
        deviceApi: DeviceApi(apiClient: apiClient, config: resolvedConfig),
        storage: resolvedStorage,
      ),
      storage: resolvedStorage,
    );

    _instance = CloudRuntime._(
      config: resolvedConfig,
      storage: resolvedStorage,
      apiClient: apiClient,
      authManager: AuthManager(authService: authService),
      deviceManager: DeviceManager(deviceService: deviceService),
    );

    return _instance!;
  }

  /// للاختبارات — إعادة ضبط الـ singleton.
  @visibleForTesting
  static void resetForTesting() {
    _instance = null;
  }
}
