import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:mizapos_desktop/services/cloud/devices/device_exception.dart';
import 'package:mizapos_desktop/services/cloud/devices/device_repository.dart';
import 'package:mizapos_desktop/services/cloud/devices/requests/heartbeat_request.dart';
import 'package:mizapos_desktop/services/cloud/devices/requests/register_device_request.dart';
import 'package:mizapos_desktop/services/cloud/devices/responses/register_device_response.dart';
import 'package:mizapos_desktop/services/cloud/models/cloud_api_response.dart';
import 'package:mizapos_desktop/services/cloud/models/cloud_device.dart';
import 'package:mizapos_desktop/services/cloud/storage/cloud_secure_storage.dart';
import 'package:mizapos_desktop/services/device_binding.dart';

/// منطق تسجيل الجهاز و heartbeat.
class DeviceService {
  DeviceService({
    required DeviceRepository repository,
    required CloudSecureStorage storage,
  })  : _repository = repository,
        _storage = storage;

  final DeviceRepository _repository;
  final CloudSecureStorage _storage;

  Future<CloudDevice?> loadRegisteredDevice() =>
      _repository.loadRegisteredDeviceFromStorage();

  Future<bool> isRegistered() async {
    final id = await _repository.readDeviceId();
    return id != null && id.isNotEmpty;
  }

  Future<RegisterDeviceResponse> register({
    required String companyId,
    required String branchId,
    String? registeredByUserId,
    String? deviceName,
    String? osName,
    String? appVersion,
  }) async {
    if (companyId.trim().isEmpty || branchId.trim().isEmpty) {
      throw const DeviceException(
        code: 'validation_error',
        message: 'company_id and branch_id are required',
      );
    }

    final installationId = await DeviceBinding.readInstallationId();
    await _storage.writeInstallationId(installationId);

    final platform = DeviceBinding.readDevicePlatform();
    final fingerprint = _buildFingerprint(installationId, platform);

    final request = RegisterDeviceRequest(
      installationId: installationId,
      deviceFingerprint: fingerprint,
      platform: platform,
      deviceName: deviceName ?? _defaultDeviceName(),
      osName: osName ?? _defaultOsName(),
      companyId: companyId,
      branchId: branchId,
      appVersion: appVersion,
      registeredByUserId: registeredByUserId ?? await _storage.readUserId(),
    );

    final response = await _repository.registerRemote(request);
    return _handleRegisterResponse(response);
  }

  Future<Map<String, dynamic>> heartbeat({String? appVersion}) async {
    final response = await _repository.heartbeatRemote(
      HeartbeatRequest(appVersion: appVersion),
    );
    if (!response.ok || response.data == null) {
      throw _failureFromResponse(response, fallbackCode: 'heartbeat_failed');
    }
    return response.data!;
  }

  Future<CloudDevice> me() async {
    final response = await _repository.meRemote();
    if (!response.ok || response.data == null) {
      throw _failureFromResponse(response, fallbackCode: 'device_me_failed');
    }
    return response.data!;
  }

  Future<RegisterDeviceResponse> _handleRegisterResponse(
    CloudApiResponse<RegisterDeviceResponse> response,
  ) async {
    if (!response.ok || response.data == null) {
      throw _failureFromResponse(response, fallbackCode: 'register_failed');
    }
    final result = response.data!;
    if (result.token.accessToken.isEmpty) {
      throw const DeviceException(
        code: 'register_invalid_response',
        message: 'Register response missing access token',
      );
    }
    await _repository.persistRegistration(result);
    return result;
  }

  String _buildFingerprint(String installationId, String platform) {
    final digest = sha256.convert(utf8.encode('$installationId|$platform'));
    return 'sha256:${digest.toString()}';
  }

  String _defaultDeviceName() {
    final platform = DeviceBinding.readDevicePlatform();
    return platform == 'android' ? 'Android Device' : 'Desktop Device';
  }

  String _defaultOsName() {
    return DeviceBinding.readDevicePlatform() == 'android'
        ? 'Android'
        : 'Windows';
  }

  DeviceException _failureFromResponse(
    CloudApiResponse<dynamic> response, {
    required String fallbackCode,
  }) {
    final error = response.error;
    if (error != null) {
      return DeviceException.fromCloudError(error);
    }
    return DeviceException(
      code: fallbackCode,
      message: 'Device request failed',
    );
  }
}
