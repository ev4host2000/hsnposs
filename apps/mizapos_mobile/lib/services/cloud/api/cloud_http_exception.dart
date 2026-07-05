/// فشل نقل HTTP — يُرمى من تنفيذ [CloudHttpClient] عند خطأ شبكة أو HTTP غير متوقع.
class CloudHttpException implements Exception {
  const CloudHttpException({
    required this.message,
    this.statusCode,
    this.errorCode,
    this.requestId,
    this.stackTrace,
  });

  final int? statusCode;
  final String message;
  final String? errorCode;
  final String? requestId;
  final StackTrace? stackTrace;

  CloudHttpException copyWith({
    int? statusCode,
    String? message,
    String? errorCode,
    String? requestId,
    StackTrace? stackTrace,
  }) {
    return CloudHttpException(
      statusCode: statusCode ?? this.statusCode,
      message: message ?? this.message,
      errorCode: errorCode ?? this.errorCode,
      requestId: requestId ?? this.requestId,
      stackTrace: stackTrace ?? this.stackTrace,
    );
  }

  @override
  String toString() {
    final buffer = StringBuffer('CloudHttpException');
    if (statusCode != null) buffer.write(' [$statusCode]');
    if (errorCode != null && errorCode!.isNotEmpty) {
      buffer.write(' ($errorCode)');
    }
    buffer.write(': $message');
    if (requestId != null && requestId!.isNotEmpty) {
      buffer.write(' (requestId: $requestId)');
    }
    return buffer.toString();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CloudHttpException &&
          runtimeType == other.runtimeType &&
          statusCode == other.statusCode &&
          message == other.message &&
          errorCode == other.errorCode &&
          requestId == other.requestId &&
          stackTrace == other.stackTrace;

  @override
  int get hashCode => Object.hash(
        statusCode,
        message,
        errorCode,
        requestId,
        stackTrace,
      );
}
