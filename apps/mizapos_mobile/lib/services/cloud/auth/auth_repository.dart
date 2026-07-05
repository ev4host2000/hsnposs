import 'package:mizapos_mobile/services/cloud/auth/auth_state.dart';
import 'package:mizapos_mobile/services/cloud/auth/requests/login_request.dart';
import 'package:mizapos_mobile/services/cloud/auth/requests/logout_request.dart';
import 'package:mizapos_mobile/services/cloud/auth/requests/refresh_token_request.dart';
import 'package:mizapos_mobile/services/cloud/auth/responses/login_response.dart';
import 'package:mizapos_mobile/services/cloud/auth/responses/refresh_token_response.dart';
import 'package:mizapos_mobile/services/cloud/auth/auth_api.dart';
import 'package:mizapos_mobile/services/cloud/models/cloud_api_response.dart';
import 'package:mizapos_mobile/services/cloud/auth/cloud_token_lifecycle.dart';
import 'package:mizapos_mobile/services/cloud/models/cloud_session.dart';
import 'package:mizapos_mobile/services/cloud/models/cloud_token.dart';
import 'package:mizapos_mobile/services/cloud/storage/cloud_secure_storage.dart';

/// طبقة البيانات: API + [CloudSecureStorage].
class AuthRepository {
  AuthRepository({
    required AuthApi authApi,
    required CloudSecureStorage storage,
  })  : _authApi = authApi,
        _storage = storage;

  final AuthApi _authApi;
  final CloudSecureStorage _storage;

  Future<CloudApiResponse<LoginResponse>> loginRemote(
    LoginRequest request,
  ) {
    return _authApi.login(request);
  }

  Future<CloudApiResponse<RefreshTokenResponse>> refreshTokenRemote(
    RefreshTokenRequest request,
  ) {
    return _authApi.refreshToken(request);
  }

  Future<CloudApiResponse<void>> logoutRemote(LogoutRequest request) {
    return _authApi.logout(request);
  }

  Future<void> persistLoginSession(LoginResponse response) async {
    await persistSession(response.session);
  }

  Future<void> persistRefreshResult(RefreshTokenResponse response) async {
    await persistToken(response.token);
    final session = response.session;
    if (session != null) {
      await persistSession(session);
    }
  }

  Future<void> persistSession(CloudSession session) async {
    final token = session.token;
    if (token != null) {
      await persistToken(token);
    }
    if (session.deviceId.isNotEmpty) {
      await _storage.writeDeviceId(session.deviceId);
    }
    if (session.companyId.isNotEmpty) {
      await _storage.writeCompanyId(session.companyId);
    }
    if (session.branchId.isNotEmpty) {
      await _storage.writeBranchId(session.branchId);
    }
    final userId = session.userId;
    if (userId != null && userId.isNotEmpty) {
      await _storage.writeUserId(userId);
    }
  }

  Future<void> persistToken(CloudToken token) async {
    if (token.accessToken.isNotEmpty) {
      await _storage.writeAccessToken(token.accessToken);
    }
    final refresh = token.refreshToken;
    if (refresh != null && refresh.isNotEmpty) {
      await _storage.writeRefreshToken(refresh);
    }

    final expiresAt = CloudTokenLifecycle.resolveExpiresAt(token);
    if (expiresAt != null) {
      await _storage.writeAccessTokenExpiresAt(
        CloudTokenLifecycle.formatExpiresAt(expiresAt),
      );
    } else {
      await _storage.deleteAccessTokenExpiresAt();
    }
  }

  Future<void> clearCredentials() => _storage.clearAll();

  Future<String?> readAccessToken() => _storage.readAccessToken();

  Future<String?> readRefreshToken() => _storage.readRefreshToken();

  Future<AuthState> loadAuthStateFromStorage() async {
    final accessToken = await _storage.readAccessToken();
    if (accessToken == null || accessToken.isEmpty) {
      return const AuthState.unauthenticated();
    }

    final deviceId = await _storage.readDeviceId() ?? '';
    final companyId = await _storage.readCompanyId() ?? '';
    final branchId = await _storage.readBranchId() ?? '';
    final userId = await _storage.readUserId();
    final refreshToken = await _storage.readRefreshToken();

    final session = CloudSession(
      sessionId: '',
      deviceId: deviceId,
      companyId: companyId,
      branchId: branchId,
      userId: userId,
      token: CloudToken(
        accessToken: accessToken,
        refreshToken: refreshToken,
      ),
    );

    return AuthState.authenticated(session);
  }

  Future<bool> hasAccessToken() async {
    final token = await _storage.readAccessToken();
    if (token == null || token.isEmpty) return false;
    final expiresAt = CloudTokenLifecycle.parseExpiresAt(
      await _storage.readAccessTokenExpiresAt(),
    );
    return !CloudTokenLifecycle.isTokenExpired(expiresAt);
  }

  Future<RefreshTokenRequest?> buildRefreshRequest() async {
    final refreshToken = await _storage.readRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) return null;
    return RefreshTokenRequest(
      refreshToken: refreshToken,
      installationId: await _storage.readInstallationId(),
      deviceId: await _storage.readDeviceId(),
    );
  }

  Future<LogoutRequest> buildLogoutRequest({bool revokeAll = false}) async {
    return LogoutRequest(
      refreshToken: await _storage.readRefreshToken(),
      revokeAllSessions: revokeAll,
    );
  }
}
