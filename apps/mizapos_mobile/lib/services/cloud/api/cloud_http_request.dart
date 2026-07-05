import 'package:mizapos_mobile/services/cloud/api/cloud_http_method.dart';

/// وصف طلب HTTP مجرد — بدون تنفيذ شبكة.
class CloudHttpRequest {
  const CloudHttpRequest({
    required this.method,
    required this.path,
    this.headers = const {},
    this.queryParameters = const {},
    this.body,
    this.timeout,
    this.contentType,
  });

  final CloudHttpMethod method;
  final String path;
  final Map<String, String> headers;
  final Map<String, String> queryParameters;

  /// جسم الطلب — `String` (JSON)، `Map`، أو `List<int>` (ملفات لاحقاً).
  final Object? body;

  /// مهلة هذا الطلب؛ إن وُجدت تتجاوز default من [CloudConfig].
  final Duration? timeout;

  /// مثل `application/json` أو `multipart/form-data`.
  final String? contentType;

  CloudHttpRequest copyWith({
    CloudHttpMethod? method,
    String? path,
    Map<String, String>? headers,
    Map<String, String>? queryParameters,
    Object? body,
    Duration? timeout,
    String? contentType,
  }) {
    return CloudHttpRequest(
      method: method ?? this.method,
      path: path ?? this.path,
      headers: headers ?? this.headers,
      queryParameters: queryParameters ?? this.queryParameters,
      body: body ?? this.body,
      timeout: timeout ?? this.timeout,
      contentType: contentType ?? this.contentType,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CloudHttpRequest &&
          runtimeType == other.runtimeType &&
          method == other.method &&
          path == other.path &&
          _mapEquals(headers, other.headers) &&
          _mapEquals(queryParameters, other.queryParameters) &&
          body == other.body &&
          timeout == other.timeout &&
          contentType == other.contentType;

  @override
  int get hashCode => Object.hash(
        method,
        path,
        _mapHash(headers),
        _mapHash(queryParameters),
        body,
        timeout,
        contentType,
      );
}

bool _mapEquals(Map<String, String> a, Map<String, String> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (final key in a.keys) {
    if (!b.containsKey(key) || a[key] != b[key]) return false;
  }
  return true;
}

int _mapHash(Map<String, String> map) {
  var hash = 0;
  for (final entry in map.entries) {
    hash = Object.hash(hash, entry.key, entry.value);
  }
  return hash;
}
