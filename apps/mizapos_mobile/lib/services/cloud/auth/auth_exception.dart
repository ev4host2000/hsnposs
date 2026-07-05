import 'package:mizapos_mobile/services/cloud/models/cloud_error.dart';

/// استثناءات طبقة المصادقة.
class AuthException implements Exception {
  const AuthException({
    required this.code,
    required this.message,
    this.statusCode,
    this.cloudError,
    this.stackTrace,
  });

  factory AuthException.fromCloudError(CloudError error) {
    return AuthException(
      code: error.code.isNotEmpty ? error.code : 'auth_error',
      message: error.message.isNotEmpty ? error.message : error.code,
      statusCode: error.statusCode,
      cloudError: error,
    );
  }

  final String code;
  final String message;
  final int? statusCode;
  final CloudError? cloudError;
  final StackTrace? stackTrace;

  AuthException copyWith({
    String? code,
    String? message,
    int? statusCode,
    CloudError? cloudError,
    StackTrace? stackTrace,
  }) {
    return AuthException(
      code: code ?? this.code,
      message: message ?? this.message,
      statusCode: statusCode ?? this.statusCode,
      cloudError: cloudError ?? this.cloudError,
      stackTrace: stackTrace ?? this.stackTrace,
    );
  }

  @override
  String toString() {
    final buffer = StringBuffer('AuthException');
    if (statusCode != null) buffer.write(' [$statusCode]');
    buffer.write(' ($code): $message');
    return buffer.toString();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AuthException &&
          runtimeType == other.runtimeType &&
          code == other.code &&
          message == other.message &&
          statusCode == other.statusCode &&
          cloudError == other.cloudError &&
          stackTrace == other.stackTrace;

  @override
  int get hashCode =>
      Object.hash(code, message, statusCode, cloudError, stackTrace);
}
