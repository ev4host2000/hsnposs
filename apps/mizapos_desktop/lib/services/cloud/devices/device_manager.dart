import 'package:mizapos_desktop/services/cloud/devices/device_exception.dart';
import 'package:mizapos_desktop/services/cloud/devices/device_service.dart';
import 'package:mizapos_desktop/services/cloud/devices/responses/register_device_response.dart';
import 'package:mizapos_desktop/services/cloud/models/cloud_device.dart';

/// واجهة التطبيق لتسجيل الجهاز و heartbeat.
class DeviceManager {
  DeviceManager({required DeviceService deviceService})
      : _deviceService = deviceService;

  final DeviceService _deviceService;

  CloudDevice? _device;

  CloudDevice? get device => _device;

  Future<CloudDevice?> initialize() async {
    _device = await _deviceService.loadRegisteredDevice();
    return _device;
  }

  Future<bool> isRegistered() => _deviceService.isRegistered();

  /// تسجيل الجهاز لأول مرة — أو إعادة إصدار tokens لنفس installation_id.
  Future<RegisterDeviceResponse> register({
    required String companyId,
    required String branchId,
    String? registeredByUserId,
    String? deviceName,
    String? osName,
    String? appVersion,
  }) async {
    try {
      final result = await _deviceService.register(
        companyId: companyId,
        branchId: branchId,
        registeredByUserId: registeredByUserId,
        deviceName: deviceName,
        osName: osName,
        appVersion: appVersion,
      );
      _device = result.device;
      return result;
    } on DeviceException {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> heartbeat({String? appVersion}) {
    return _deviceService.heartbeat(appVersion: appVersion);
  }

  Future<CloudDevice> fetchMe() async {
    final device = await _deviceService.me();
    _device = device;
    return device;
  }
}
