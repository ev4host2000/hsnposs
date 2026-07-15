/// زوج tokens من Miza Cloud (access + refresh اختياري).
class CloudToken {
  const CloudToken({
    required this.accessToken,
    this.refreshToken,
    this.tokenType = 'Bearer',
    this.expiresIn = 0,
    this.expiresAt,
    this.issuedAt,
  });

  factory CloudToken.fromJson(Map<String, dynamic> json) {
    return CloudToken(
      accessToken: (json['access_token'] ?? '').toString(),
      refreshToken: _optionalString(json['refresh_token']),
      tokenType: (json['token_type'] ?? 'Bearer').toString(),
      expiresIn: _asInt(json['expires_in']),
      expiresAt: _optionalString(json['expires_at']),
      issuedAt: _optionalString(json['issued_at']),
    );
  }

  final String accessToken;
  final String? refreshToken;
  final String tokenType;
  final int expiresIn;
  final String? expiresAt;
  final String? issuedAt;

  Map<String, dynamic> toJson() => {
        'access_token': accessToken,
        if (refreshToken != null) 'refresh_token': refreshToken,
        'token_type': tokenType,
        'expires_in': expiresIn,
        if (expiresAt != null) 'expires_at': expiresAt,
        if (issuedAt != null) 'issued_at': issuedAt,
      };

  CloudToken copyWith({
    String? accessToken,
    String? refreshToken,
    String? tokenType,
    int? expiresIn,
    String? expiresAt,
    String? issuedAt,
  }) {
    return CloudToken(
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
      tokenType: tokenType ?? this.tokenType,
      expiresIn: expiresIn ?? this.expiresIn,
      expiresAt: expiresAt ?? this.expiresAt,
      issuedAt: issuedAt ?? this.issuedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CloudToken &&
          runtimeType == other.runtimeType &&
          accessToken == other.accessToken &&
          refreshToken == other.refreshToken &&
          tokenType == other.tokenType &&
          expiresIn == other.expiresIn &&
          expiresAt == other.expiresAt &&
          issuedAt == other.issuedAt;

  @override
  int get hashCode => Object.hash(
        accessToken,
        refreshToken,
        tokenType,
        expiresIn,
        expiresAt,
        issuedAt,
      );
}

String? _optionalString(Object? value) {
  if (value == null) return null;
  final s = value.toString().trim();
  return s.isEmpty ? null : s;
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
