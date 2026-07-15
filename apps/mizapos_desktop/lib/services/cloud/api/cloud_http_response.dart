/// استجابة HTTP مجردة — ناتج [CloudHttpClient] دون parsing JSON.
class CloudHttpResponse {
  const CloudHttpResponse({
    required this.statusCode,
    this.headers = const {},
    this.body,
    required this.isSuccess,
    this.requestId,
    this.duration = Duration.zero,
  });

  final int statusCode;
  final Map<String, String> headers;

  /// النص الخام أو بايتات (تنفيذ [download] قد يعيد `List<int>`).
  final Object? body;

  /// `true` عادةً لـ 2xx — يُحدَّد عند الإنشاء من التنفيذ.
  final bool isSuccess;

  /// معرّف تتبع من الخادم أو العميل (`X-Request-Id`).
  final String? requestId;

  /// زمن الطلب من الإرسال حتى اكتمال الاستجابة.
  final Duration duration;

  CloudHttpResponse copyWith({
    int? statusCode,
    Map<String, String>? headers,
    Object? body,
    bool? isSuccess,
    String? requestId,
    Duration? duration,
  }) {
    return CloudHttpResponse(
      statusCode: statusCode ?? this.statusCode,
      headers: headers ?? this.headers,
      body: body ?? this.body,
      isSuccess: isSuccess ?? this.isSuccess,
      requestId: requestId ?? this.requestId,
      duration: duration ?? this.duration,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CloudHttpResponse &&
          runtimeType == other.runtimeType &&
          statusCode == other.statusCode &&
          _mapEquals(headers, other.headers) &&
          body == other.body &&
          isSuccess == other.isSuccess &&
          requestId == other.requestId &&
          duration == other.duration;

  @override
  int get hashCode => Object.hash(
        statusCode,
        _mapHash(headers),
        body,
        isSuccess,
        requestId,
        duration,
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
