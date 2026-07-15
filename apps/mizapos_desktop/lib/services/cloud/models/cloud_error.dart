/// خطأ domain من Miza Cloud API.
class CloudError {
  const CloudError({
    required this.code,
    this.message = '',
    this.statusCode,
    this.details = const {},
  });

  factory CloudError.fromJson(Map<String, dynamic> json) {
    final rawDetails = json['details'];
    Map<String, dynamic> details = const {};
    if (rawDetails is Map) {
      details = Map<String, dynamic>.from(rawDetails);
    }
    return CloudError(
      code: (json['code'] ?? json['error'] ?? '').toString(),
      message: (json['message'] ?? json['detail'] ?? '').toString(),
      statusCode: _optionalInt(json['status_code'] ?? json['statusCode']),
      details: details,
    );
  }

  final String code;
  final String message;
  final int? statusCode;
  final Map<String, dynamic> details;

  Map<String, dynamic> toJson() => {
        'code': code,
        'message': message,
        if (statusCode != null) 'status_code': statusCode,
        if (details.isNotEmpty) 'details': details,
      };

  CloudError copyWith({
    String? code,
    String? message,
    int? statusCode,
    Map<String, dynamic>? details,
  }) {
    return CloudError(
      code: code ?? this.code,
      message: message ?? this.message,
      statusCode: statusCode ?? this.statusCode,
      details: details ?? this.details,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CloudError &&
          runtimeType == other.runtimeType &&
          code == other.code &&
          message == other.message &&
          statusCode == other.statusCode &&
          _mapEquals(details, other.details);

  @override
  int get hashCode => Object.hash(
        code,
        message,
        statusCode,
        _mapHash(details),
      );

  @override
  String toString() =>
      statusCode == null ? '$code: $message' : '[$statusCode] $code: $message';
}

int? _optionalInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}

bool _mapEquals(Map<String, dynamic> a, Map<String, dynamic> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (final key in a.keys) {
    if (!b.containsKey(key) || a[key] != b[key]) return false;
  }
  return true;
}

int _mapHash(Map<String, dynamic> map) {
  var hash = 0;
  for (final entry in map.entries) {
    hash = Object.hash(hash, entry.key, entry.value);
  }
  return hash;
}
