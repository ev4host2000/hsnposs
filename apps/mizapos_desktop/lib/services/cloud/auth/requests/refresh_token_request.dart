/// طلب تجديد access token.
class RefreshTokenRequest {
  const RefreshTokenRequest({
    required this.refreshToken,
    this.installationId,
    this.deviceId,
  });

  factory RefreshTokenRequest.fromJson(Map<String, dynamic> json) {
    return RefreshTokenRequest(
      refreshToken: (json['refresh_token'] ?? '').toString(),
      installationId: _optionalString(json['installation_id']),
      deviceId: _optionalString(json['device_id']),
    );
  }

  final String refreshToken;
  final String? installationId;
  final String? deviceId;

  Map<String, dynamic> toJson() => {
        'refresh_token': refreshToken,
        if (installationId != null) 'installation_id': installationId,
        if (deviceId != null) 'device_id': deviceId,
      };

  RefreshTokenRequest copyWith({
    String? refreshToken,
    String? installationId,
    String? deviceId,
  }) {
    return RefreshTokenRequest(
      refreshToken: refreshToken ?? this.refreshToken,
      installationId: installationId ?? this.installationId,
      deviceId: deviceId ?? this.deviceId,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RefreshTokenRequest &&
          runtimeType == other.runtimeType &&
          refreshToken == other.refreshToken &&
          installationId == other.installationId &&
          deviceId == other.deviceId;

  @override
  int get hashCode => Object.hash(refreshToken, installationId, deviceId);
}

String? _optionalString(Object? value) {
  if (value == null) return null;
  final s = value.toString().trim();
  return s.isEmpty ? null : s;
}
