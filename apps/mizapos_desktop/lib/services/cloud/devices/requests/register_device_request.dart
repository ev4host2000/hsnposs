/// طلب تسجيل جهاز — POST /devices/register.
class RegisterDeviceRequest {
  const RegisterDeviceRequest({
    required this.installationId,
    required this.deviceFingerprint,
    required this.platform,
    required this.deviceName,
    required this.osName,
    required this.companyId,
    required this.branchId,
    this.osUser,
    this.appVersion,
    this.registeredByUserId,
  });

  final String installationId;
  final String deviceFingerprint;
  final String platform;
  final String deviceName;
  final String osName;
  final String companyId;
  final String branchId;
  final String? osUser;
  final String? appVersion;
  final String? registeredByUserId;

  Map<String, dynamic> toJson() => {
        'installation_id': installationId,
        'device_fingerprint': deviceFingerprint,
        'platform': platform,
        'device_name': deviceName,
        'os_name': osName,
        if (osUser != null) 'os_user': osUser,
        if (appVersion != null) 'app_version': appVersion,
        'company_id': companyId,
        'branch_id': branchId,
        if (registeredByUserId != null)
          'registered_by_user_id': registeredByUserId,
      };
}
