import 'package:mizapos_mobile/services/cloud/models/cloud_session.dart';

/// حالة المصادقة الحالية في التطبيق.
enum AuthStatus {
  /// لم يُحمَّل بعد من التخزين.
  unknown,

  /// لا access token صالح محلياً.
  unauthenticated,

  /// جلسة نشطة (token محفوظ).
  authenticated,

  /// تجديد token قيد التنفيذ.
  refreshing,
}

/// لقطة حالة auth للقراءة من UI أو Sync لاحقاً.
class AuthState {
  const AuthState({
    required this.status,
    this.session,
    this.lastErrorCode,
  });

  const AuthState.unknown() : this(status: AuthStatus.unknown);

  const AuthState.unauthenticated()
      : this(status: AuthStatus.unauthenticated);

  const AuthState.authenticated(CloudSession session)
      : this(status: AuthStatus.authenticated, session: session);

  const AuthState.refreshing(CloudSession? session)
      : this(status: AuthStatus.refreshing, session: session);

  final AuthStatus status;
  final CloudSession? session;
  final String? lastErrorCode;

  bool get isAuthenticated => status == AuthStatus.authenticated;

  bool get isLoggedIn => status == AuthStatus.authenticated;

  AuthState copyWith({
    AuthStatus? status,
    CloudSession? session,
    String? lastErrorCode,
  }) {
    return AuthState(
      status: status ?? this.status,
      session: session ?? this.session,
      lastErrorCode: lastErrorCode ?? this.lastErrorCode,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AuthState &&
          runtimeType == other.runtimeType &&
          status == other.status &&
          session == other.session &&
          lastErrorCode == other.lastErrorCode;

  @override
  int get hashCode => Object.hash(status, session, lastErrorCode);
}
