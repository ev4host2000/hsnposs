/// عقد تخزين آمن لبيانات جلسة Miza Cloud — قابل للاستبدال (Keystore / Keychain / …).
abstract class CloudSecureStorage {
  // --- Access Token ---

  Future<void> writeAccessToken(String value);
  Future<String?> readAccessToken();
  Future<void> deleteAccessToken();

  // --- Access token expiry (ISO-8601 UTC) ---

  Future<void> writeAccessTokenExpiresAt(String value);
  Future<String?> readAccessTokenExpiresAt();
  Future<void> deleteAccessTokenExpiresAt();

  // --- Refresh Token ---

  Future<void> writeRefreshToken(String value);
  Future<String?> readRefreshToken();
  Future<void> deleteRefreshToken();

  // --- Device ID (cloud UUID) ---

  Future<void> writeDeviceId(String value);
  Future<String?> readDeviceId();
  Future<void> deleteDeviceId();

  // --- Installation ID (نسخة cache؛ المصدر الرسمي DeviceBinding) ---

  Future<void> writeInstallationId(String value);
  Future<String?> readInstallationId();
  Future<void> deleteInstallationId();

  // --- Company ID ---

  Future<void> writeCompanyId(String value);
  Future<String?> readCompanyId();
  Future<void> deleteCompanyId();

  // --- Branch ID ---

  Future<void> writeBranchId(String value);
  Future<String?> readBranchId();
  Future<void> deleteBranchId();

  // --- User ID ---

  Future<void> writeUserId(String value);
  Future<String?> readUserId();
  Future<void> deleteUserId();

  // --- Cloud account login (email / username) ---

  Future<void> writeCloudUsername(String value);
  Future<String?> readCloudUsername();
  Future<void> deleteCloudUsername();

  /// مسح كل القيم (logout / revoke / factory reset لاحقاً).
  Future<void> clearAll();
}
