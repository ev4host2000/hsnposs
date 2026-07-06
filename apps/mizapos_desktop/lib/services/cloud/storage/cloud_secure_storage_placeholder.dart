import 'package:mizapos_desktop/services/cloud/storage/cloud_secure_storage.dart';

/// تخزين مؤقت في الذاكرة — للتطوير وبناء الطبقات فقط.
///
/// **لا يُستخدم في الإنتاج:** البيانات تُفقد عند إغلاق التطبيق.
/// استبدله لاحقاً بتنفيذ يعتمد Keystore / Keychain / DPAPI.
class CloudSecureStoragePlaceholder implements CloudSecureStorage {
  CloudSecureStoragePlaceholder();

  final Map<String, String> _values = <String, String>{};

  static const _keyAccessToken = 'cloud.secure.access_token';
  static const _keyAccessTokenExpiresAt = 'cloud.secure.access_token_expires_at';
  static const _keyRefreshToken = 'cloud.secure.refresh_token';
  static const _keyDeviceId = 'cloud.secure.device_id';
  static const _keyInstallationId = 'cloud.secure.installation_id';
  static const _keyCompanyId = 'cloud.secure.company_id';
  static const _keyBranchId = 'cloud.secure.branch_id';
  static const _keyUserId = 'cloud.secure.user_id';

  @override
  Future<void> writeAccessToken(String value) async =>
      _write(_keyAccessToken, value);

  @override
  Future<String?> readAccessToken() async => _read(_keyAccessToken);

  @override
  Future<void> deleteAccessToken() async => _delete(_keyAccessToken);

  @override
  Future<void> writeAccessTokenExpiresAt(String value) async =>
      _write(_keyAccessTokenExpiresAt, value);

  @override
  Future<String?> readAccessTokenExpiresAt() async =>
      _read(_keyAccessTokenExpiresAt);

  @override
  Future<void> deleteAccessTokenExpiresAt() async =>
      _delete(_keyAccessTokenExpiresAt);

  @override
  Future<void> writeRefreshToken(String value) async =>
      _write(_keyRefreshToken, value);

  @override
  Future<String?> readRefreshToken() async => _read(_keyRefreshToken);

  @override
  Future<void> deleteRefreshToken() async => _delete(_keyRefreshToken);

  @override
  Future<void> writeDeviceId(String value) async =>
      _write(_keyDeviceId, value);

  @override
  Future<String?> readDeviceId() async => _read(_keyDeviceId);

  @override
  Future<void> deleteDeviceId() async => _delete(_keyDeviceId);

  @override
  Future<void> writeInstallationId(String value) async =>
      _write(_keyInstallationId, value);

  @override
  Future<String?> readInstallationId() async => _read(_keyInstallationId);

  @override
  Future<void> deleteInstallationId() async => _delete(_keyInstallationId);

  @override
  Future<void> writeCompanyId(String value) async =>
      _write(_keyCompanyId, value);

  @override
  Future<String?> readCompanyId() async => _read(_keyCompanyId);

  @override
  Future<void> deleteCompanyId() async => _delete(_keyCompanyId);

  @override
  Future<void> writeBranchId(String value) async =>
      _write(_keyBranchId, value);

  @override
  Future<String?> readBranchId() async => _read(_keyBranchId);

  @override
  Future<void> deleteBranchId() async => _delete(_keyBranchId);

  @override
  Future<void> writeUserId(String value) async => _write(_keyUserId, value);

  @override
  Future<String?> readUserId() async => _read(_keyUserId);

  @override
  Future<void> deleteUserId() async => _delete(_keyUserId);

  @override
  Future<void> clearAll() async {
    _values.clear();
  }

  Future<void> _write(String key, String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      _values.remove(key);
      return;
    }
    _values[key] = trimmed;
  }

  Future<String?> _read(String key) async {
    final value = _values[key];
    if (value == null || value.isEmpty) return null;
    return value;
  }

  Future<void> _delete(String key) async {
    _values.remove(key);
  }
}
