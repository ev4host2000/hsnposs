import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mizapos_desktop/services/cloud/storage/cloud_secure_storage.dart';

/// تخزين إنتاجي — Android Keystore + EncryptedSharedPreferences، Windows DPAPI.
class CloudSecureStorageProduction implements CloudSecureStorage {
  CloudSecureStorageProduction(this._storage);

  static Future<CloudSecureStorageProduction> create() async {
    const storage = FlutterSecureStorage(
      aOptions: AndroidOptions(),
      iOptions: IOSOptions(
        accessibility: KeychainAccessibility.first_unlock_this_device,
      ),
      wOptions: WindowsOptions(useBackwardCompatibility: false),
    );
    return CloudSecureStorageProduction(storage);
  }

  final FlutterSecureStorage _storage;

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
  Future<void> writeAccessToken(String value) => _write(_keyAccessToken, value);

  @override
  Future<String?> readAccessToken() => _read(_keyAccessToken);

  @override
  Future<void> deleteAccessToken() => _delete(_keyAccessToken);

  @override
  Future<void> writeAccessTokenExpiresAt(String value) =>
      _write(_keyAccessTokenExpiresAt, value);

  @override
  Future<String?> readAccessTokenExpiresAt() =>
      _read(_keyAccessTokenExpiresAt);

  @override
  Future<void> deleteAccessTokenExpiresAt() =>
      _delete(_keyAccessTokenExpiresAt);

  @override
  Future<void> writeRefreshToken(String value) =>
      _write(_keyRefreshToken, value);

  @override
  Future<String?> readRefreshToken() => _read(_keyRefreshToken);

  @override
  Future<void> deleteRefreshToken() => _delete(_keyRefreshToken);

  @override
  Future<void> writeDeviceId(String value) => _write(_keyDeviceId, value);

  @override
  Future<String?> readDeviceId() => _read(_keyDeviceId);

  @override
  Future<void> deleteDeviceId() => _delete(_keyDeviceId);

  @override
  Future<void> writeInstallationId(String value) =>
      _write(_keyInstallationId, value);

  @override
  Future<String?> readInstallationId() => _read(_keyInstallationId);

  @override
  Future<void> deleteInstallationId() => _delete(_keyInstallationId);

  @override
  Future<void> writeCompanyId(String value) => _write(_keyCompanyId, value);

  @override
  Future<String?> readCompanyId() => _read(_keyCompanyId);

  @override
  Future<void> deleteCompanyId() => _delete(_keyCompanyId);

  @override
  Future<void> writeBranchId(String value) => _write(_keyBranchId, value);

  @override
  Future<String?> readBranchId() => _read(_keyBranchId);

  @override
  Future<void> deleteBranchId() => _delete(_keyBranchId);

  @override
  Future<void> writeUserId(String value) => _write(_keyUserId, value);

  @override
  Future<String?> readUserId() => _read(_keyUserId);

  @override
  Future<void> deleteUserId() => _delete(_keyUserId);

  @override
  Future<void> writeCloudUsername(String value) =>
      _write(_keyCloudUsername, value);

  @override
  Future<String?> readCloudUsername() => _read(_keyCloudUsername);

  @override
  Future<void> deleteCloudUsername() => _delete(_keyCloudUsername);

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
      await _storage.delete(key: key);
      return;
    }
    await _storage.write(key: key, value: trimmed);
  }

  Future<String?> _read(String key) async {
    final value = await _storage.read(key: key);
    if (value == null || value.isEmpty) return null;
    return value;
  }

  Future<void> _delete(String key) async {
    await _storage.delete(key: key);
  }
}
