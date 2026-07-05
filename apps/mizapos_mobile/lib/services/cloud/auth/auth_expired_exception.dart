import 'package:mizapos_mobile/services/cloud/auth/auth_exception.dart';

/// انتهت الجلسة — refresh فشل وتم مسح التوكنات.
class AuthExpiredException extends AuthException {
  const AuthExpiredException({
    String message = 'Session expired',
    int? statusCode,
  }) : super(
          code: 'auth_expired',
          message: message,
          statusCode: statusCode ?? 401,
        );
}
