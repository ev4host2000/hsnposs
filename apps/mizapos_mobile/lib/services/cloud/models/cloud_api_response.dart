import 'package:mizapos_mobile/services/cloud/models/cloud_error.dart';

/// غلاف استجابة JSON عام من Miza Cloud API.
class CloudApiResponse<T> {
  const CloudApiResponse({
    required this.ok,
    this.data,
    this.error,
    this.meta = const {},
  });

  factory CloudApiResponse.fromJson(
    Map<String, dynamic> json,
    T Function(Object? json) fromJsonT,
  ) {
    final rawData = json['data'];
    T? data;
    if (rawData != null) {
      data = fromJsonT(rawData);
    }

    CloudError? error;
    final rawError = json['error'];
    if (rawError is Map<String, dynamic>) {
      error = CloudError.fromJson(rawError);
    } else if (rawError is Map) {
      error = CloudError.fromJson(Map<String, dynamic>.from(rawError));
    } else if (json['code'] != null &&
        (json['ok'] == false || json['success'] == false)) {
      error = CloudError.fromJson(json);
    }

    final rawMeta = json['meta'];
    Map<String, dynamic> meta = const {};
    if (rawMeta is Map) {
      meta = Map<String, dynamic>.from(rawMeta);
    }

    final explicitOk = json['ok'];
    final ok = explicitOk == true ||
        explicitOk == 1 ||
        (explicitOk == null && error == null && rawData != null);

    return CloudApiResponse<T>(
      ok: ok,
      data: data,
      error: error,
      meta: meta,
    );
  }

  final bool ok;
  final T? data;
  final CloudError? error;
  final Map<String, dynamic> meta;

  Map<String, dynamic> toJson(Object? Function(T value) toJsonT) => {
        'ok': ok,
        if (data != null) 'data': toJsonT(data as T),
        if (error != null) 'error': error!.toJson(),
        if (meta.isNotEmpty) 'meta': meta,
      };

  CloudApiResponse<T> copyWith({
    bool? ok,
    T? data,
    CloudError? error,
    Map<String, dynamic>? meta,
  }) {
    return CloudApiResponse<T>(
      ok: ok ?? this.ok,
      data: data ?? this.data,
      error: error ?? this.error,
      meta: meta ?? this.meta,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CloudApiResponse<T> &&
          runtimeType == other.runtimeType &&
          ok == other.ok &&
          data == other.data &&
          error == other.error &&
          _mapEquals(meta, other.meta);

  @override
  int get hashCode => Object.hash(
        ok,
        data,
        error,
        _mapHash(meta),
      );
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
