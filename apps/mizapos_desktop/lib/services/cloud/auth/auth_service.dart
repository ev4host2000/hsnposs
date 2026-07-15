import 'package:mizapos_desktop/services/cloud/auth/auth_exception.dart';
import 'package:mizapos_desktop/services/cloud/auth/auth_repository.dart';
import 'package:mizapos_desktop/services/cloud/auth/auth_state.dart';
import 'package:mizapos_desktop/services/cloud/auth/requests/login_request.dart';
import 'package:mizapos_desktop/services/cloud/auth/requests/logout_request.dart';
import 'package:mizapos_desktop/services/cloud/auth/responses/login_response.dart';
import 'package:mizapos_desktop/services/cloud/auth/responses/refresh_token_response.dart';
import 'package:mizapos_desktop/services/cloud/config/cloud_config.dart';
import 'package:mizapos_desktop/services/cloud/models/cloud_api_response.dart';

/// منطق use-cases للمصادقة — بين [AuthManager] و [AuthRepository].
class AuthService {
  AuthService({
    required AuthRepository repository,
    CloudConfig? config,
  })  : _repository = repository,
        _config = config;

  final AuthRepository _repository;
  final CloudConfig? _config;

  CloudConfig? get config => _config;

  Future<AuthState> loadState() => _repository.loadAuthStateFromStorage();

  Future<bool> isLoggedIn() => _repository.hasAccessToken();

  Future<AuthState> login(LoginRequest request) async {
    _validateLoginRequest(request);
    final response = await _repository.loginRemote(request);
    return _handleLoginResponse(response);
  }

  Future<AuthState> loginPairing(LoginRequest request) async {
    _validateLoginRequest(request);
    final response = await _repository.loginPairingRemote(request);
    return _handleLoginResponse(response);
  }

  Future<AuthState> refreshToken() async {
    final refreshRequest = await _repository.buildRefreshRequest();
    if (refreshRequest == null) {
      throw const AuthException(
        code: 'refresh_token_missing',
        message: 'No refresh token available',
      );
    }

    final response = await _repository.refreshTokenRemote(refreshRequest);
    return _handleRefreshResponse(response);
  }

  Future<AuthState> logout({LogoutRequest? request}) async {
    final logoutRequest = request ?? await _repository.buildLogoutRequest();
    try {
      final response = await _repository.logoutRemote(logoutRequest);
      if (!response.ok) {
        final error = response.error;
        if (error != null) {
          throw AuthException.fromCloudError(error);
        }
      }
    } on AuthException {
      rethrow;
    } on Object {
      // مسح محلي حتى عند فشل الشبكة.
    } finally {
      await _repository.clearCredentials();
    }
    return const AuthState.unauthenticated();
  }

  Future<AuthState> _handleLoginResponse(
    CloudApiResponse<LoginResponse> response,
  ) async {
    if (!response.ok || response.data == null) {
      throw _failureFromResponse(response, fallbackCode: 'login_failed');
    }
    final login = response.data!;
    final token = login.session.token;
    if (token == null || token.accessToken.isEmpty) {
      throw const AuthException(
        code: 'login_invalid_response',
        message: 'Login response missing access token',
      );
    }
    await _repository.persistLoginSession(login);
    return AuthState.authenticated(login.session);
  }

  Future<AuthState> _handleRefreshResponse(
    CloudApiResponse<RefreshTokenResponse> response,
  ) async {
    if (!response.ok || response.data == null) {
      throw _failureFromResponse(response, fallbackCode: 'refresh_failed');
    }
    final refresh = response.data!;
    if (refresh.token.accessToken.isEmpty) {
      throw const AuthException(
        code: 'refresh_invalid_response',
        message: 'Refresh response missing access token',
      );
    }
    await _repository.persistRefreshResult(refresh);
    final session = refresh.session ??
        (await _repository.loadAuthStateFromStorage()).session;
    if (session == null) {
      throw const AuthException(
        code: 'refresh_session_missing',
        message: 'Could not rebuild session after refresh',
      );
    }
    final merged = session.token != null
        ? session
        : session.copyWith(token: refresh.token);
    return AuthState.authenticated(merged);
  }

  void _validateLoginRequest(LoginRequest request) {
    if (request.username.trim().isEmpty) {
      throw const AuthException(
        code: 'username_required',
        message: 'Username is required',
      );
    }
    if (request.password.isEmpty) {
      throw const AuthException(
        code: 'password_required',
        message: 'Password is required',
      );
    }
  }

  Future<AuthState> clearLocalSession() async {
    await _repository.clearCredentials();
    return const AuthState.unauthenticated();
  }

  Future<void> requestPasswordReset({required String email}) async {
    final trimmed = email.trim();
    if (trimmed.isEmpty || !trimmed.contains('@')) {
      throw const AuthException(
        code: 'validation_error',
        message: 'Valid email is required',
      );
    }
    await _repository.requestPasswordReset(email: trimmed);
  }

  AuthException _failureFromResponse(
    CloudApiResponse<dynamic> response, {
    required String fallbackCode,
  }) {
    final error = response.error;
    if (error != null) {
      return AuthException.fromCloudError(error);
    }
    return AuthException(
      code: fallbackCode,
      message: 'Authentication request failed',
    );
  }
}
