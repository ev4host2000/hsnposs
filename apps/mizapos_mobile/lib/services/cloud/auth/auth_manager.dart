import 'package:mizapos_mobile/services/cloud/auth/auth_exception.dart';
import 'package:mizapos_mobile/services/cloud/auth/auth_service.dart';
import 'package:mizapos_mobile/services/cloud/auth/auth_state.dart';
import 'package:mizapos_mobile/services/cloud/auth/requests/login_request.dart';
import 'package:mizapos_mobile/services/cloud/auth/requests/logout_request.dart';

/// واجهة التطبيق للمصادقة — login / logout / refresh / حالة الجلسة.
class AuthManager {
  AuthManager({
    required AuthService authService,
  }) : _authService = authService;

  final AuthService _authService;

  AuthState _state = const AuthState.unknown();

  /// آخر حالة معروفة — تُحدَّث بعد كل عملية ناجحة أو فاشلة.
  AuthState get state => _state;

  /// تحميل الحالة من التخزين الآمن دون طلب شبكة.
  Future<AuthState> initialize() async {
    _state = await _authService.loadState();
    return _state;
  }

  /// هل يوجد access token محفوظ محلياً؟
  Future<bool> isLoggedIn() => _authService.isLoggedIn();

  /// تسجيل الدخول وحفظ التوكنات والسياق.
  Future<AuthState> login(LoginRequest request) async {
    try {
      _state = const AuthState(status: AuthStatus.unknown);
      _state = await _authService.login(request);
      return _state;
    } on AuthException catch (e) {
      _state = AuthState(
        status: AuthStatus.unauthenticated,
        lastErrorCode: e.code,
      );
      rethrow;
    }
  }

  /// تجديد access token باستخدام refresh token المحفوظ.
  Future<AuthState> refreshToken() async {
    final previous = _state.session;
    _state = AuthState.refreshing(previous);
    try {
      _state = await _authService.refreshToken();
      return _state;
    } on AuthException catch (e) {
      await _authService.clearLocalSession();
      _state = AuthState(
        status: AuthStatus.unauthenticated,
        lastErrorCode: e.code,
      );
      rethrow;
    }
  }

  /// إنهاء الجلسة — يمسح التوكنات محلياً دائماً.
  Future<AuthState> logout({LogoutRequest? request}) async {
    try {
      _state = await _authService.logout(request: request);
      return _state;
    } on AuthException {
      _state = const AuthState.unauthenticated();
      rethrow;
    }
  }

  /// مسح التوكنات محلياً دون استدعاء API (مثلاً بعد revoke من الخادم).
  Future<AuthState> clearLocalSession() async {
    _state = await _authService.clearLocalSession();
    return _state;
  }
}
