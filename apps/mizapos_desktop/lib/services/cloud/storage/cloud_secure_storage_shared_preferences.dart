import 'package:mizapos_desktop/services/cloud/storage/cloud_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// تخزين دائم لبيانات Miza Cloud — SharedPreferences (قابل للاستبدال لاحقاً).
class CloudSecureStorageSharedPreferences implements CloudSecureStorage {
  CloudSecureStorageSharedPreferences(this._prefs);

  static Future<CloudSecureStorageSharedPreferences> create() async {
    final prefs = await SharedPreferences.getInstance();
    return CloudSecureStorageSharedPreferences(prefs);
  }

  final SharedPreferences _prefs;

  static const _keyAccessToken = 'cloud.secure.access_token';
  static const _keyAccessTokenExpiresAt = 'cloud.secure.access_token_expires_at';
  static const _keyRefreshToken = 'cloud.secure.refresh_token';
  static const _keyDeviceId = 'cloud.secure.device_id';
  static const _keyInstallationId = 'cloud.secure.installation_id';
  static const _keyCompanyId = 'cloud.secure.company_id';
  static const _keyBranchId = 'cloud.secure.branch_id';
  static const _keyUserId = 'cloud.secure.user_id';
  static const _keyCloudUsername = 'cloud.secure.cloud_username';

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
  Future<void> writeDeviceId(String value) async => _write(_keyDeviceId, value);

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
  Future<void> writeBranchId(String value) async => _write(_keyBranchId, value);

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
  Future<void> writeCloudUsername(String value) async =>
      _write(_keyCloudUsername, value);

  @override
  Future<String?> readCloudUsername() async => _read(_keyCloudUsername);

  @override
  Future<void> deleteCloudUsername() async => _delete(_keyCloudUsername);

  @override
  Future<void> clearAll() async {
    await Future.wait([
      _delete(_keyAccessToken),
      _delete(_keyAccessTokenExpiresAt),
      _delete(_keyRefreshToken),
      _delete(_keyDeviceId),
      _delete(_keyInstallationId),
      _delete(_keyCompanyId),
      _delete(_keyBranchId),
      _delete(_keyUserId),
      _delete(_keyCloudUsername),
    ]);
  }

  Future<void> _write(String key, String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      await _prefs.remove(key);
      return;
    }
    await _prefs.setString(key, trimmed);
  }

  Future<String?> _read(String key) async {
    final value = _prefs.getString(key);
    if (value == null || value.isEmpty) return null;
    return value;
  }

  Future<void> _delete(String key) async {
    await _prefs.remove(key);
  }
}
