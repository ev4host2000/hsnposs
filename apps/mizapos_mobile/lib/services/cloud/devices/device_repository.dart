import 'package:mizapos_mobile/services/cloud/devices/device_api.dart';
import 'package:mizapos_mobile/services/cloud/devices/requests/heartbeat_request.dart';
import 'package:mizapos_mobile/services/cloud/devices/requests/register_device_request.dart';
import 'package:mizapos_mobile/services/cloud/devices/responses/register_device_response.dart';
import 'package:mizapos_mobile/services/cloud/models/cloud_api_response.dart';
import 'package:mizapos_mobile/services/cloud/models/cloud_device.dart';
import 'package:mizapos_mobile/services/cloud/models/cloud_session.dart';
import 'package:mizapos_mobile/services/cloud/models/cloud_token.dart';
import 'package:mizapos_mobile/services/cloud/storage/cloud_secure_storage.dart';

/// API + تخزين آمن للجهاز.
class DeviceRepository {
  DeviceRepository({
    required DeviceApi deviceApi,
    required CloudSecureStorage storage,
  })  : _deviceApi = deviceApi,
        _storage = storage;

  final DeviceApi _deviceApi;
  final CloudSecureStorage _storage;

  Future<CloudApiResponse<RegisterDeviceResponse>> registerRemote(
    RegisterDeviceRequest request,
  ) {
    return _deviceApi.register(request);
  }

  Future<CloudApiResponse<Map<String, dynamic>>> heartbeatRemote(
    HeartbeatRequest request,
  ) {
    return _deviceApi.heartbeat(request);
  }

  Future<CloudApiResponse<CloudDevice>> meRemote() => _deviceApi.me();

  Future<void> persistRegistration(RegisterDeviceResponse response) async {
    final device = response.device;
    if (device.id.isNotEmpty) {
      await _storage.writeDeviceId(device.id);
    }
    if (device.installationId.isNotEmpty) {
      await _storage.writeInstallationId(device.installationId);
    }
    if (device.companyId.isNotEmpty) {
      await _storage.writeCompanyId(device.companyId);
    }

    final token = response.token;
    if (token.accessToken.isNotEmpty) {
      await _storage.writeAccessToken(token.accessToken);
    }
    final refresh = token.refreshToken;
    if (refresh != null && refresh.isNotEmpty) {
      await _storage.writeRefreshToken(refresh);
    }
  }

  Future<CloudDevice?> loadRegisteredDeviceFromStorage() async {
    final deviceId = await _storage.readDeviceId();
    if (deviceId == null || deviceId.isEmpty) return null;
    return CloudDevice(
      id: deviceId,
      companyId: await _storage.readCompanyId() ?? '',
      installationId: await _storage.readInstallationId() ?? '',
      isSelf: true,
    );
  }

  Future<String?> readDeviceId() => _storage.readDeviceId();

  Future<String?> readInstallationId() => _storage.readInstallationId();

  Future<CloudSession?> buildSessionFromStorage() async {
    final device = await loadRegisteredDeviceFromStorage();
    if (device == null) return null;
    final access = await _storage.readAccessToken();
    if (access == null || access.isEmpty) return null;

    return CloudSession(
      sessionId: '',
      deviceId: device.id,
      companyId: device.companyId,
      branchId: await _storage.readBranchId() ?? '',
      userId: await _storage.readUserId(),
      sessionType: 'device',
      device: device,
      token: CloudToken(
        accessToken: access,
        refreshToken: await _storage.readRefreshToken(),
      ),
    );
  }
}
