import 'package:mizapos_desktop/services/cloud/models/cloud_session.dart';

/// استجابة تسجيل الدخول الناجح.
class LoginResponse {
  const LoginResponse({
    required this.session,
  });

  factory LoginResponse.fromJson(Object? json) {
    if (json is Map<String, dynamic>) {
      return LoginResponse(session: CloudSession.fromJson(json));
    }
    if (json is Map) {
      return LoginResponse(
        session: CloudSession.fromJson(Map<String, dynamic>.from(json)),
      );
    }
    return const LoginResponse(
      session: CloudSession(
        sessionId: '',
        deviceId: '',
        companyId: '',
        branchId: '',
      ),
    );
  }

  final CloudSession session;

  Map<String, dynamic> toJson() => session.toJson();

  LoginResponse copyWith({CloudSession? session}) {
    return LoginResponse(session: session ?? this.session);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LoginResponse &&
          runtimeType == other.runtimeType &&
          session == other.session;

  @override
  int get hashCode => session.hashCode;
}
