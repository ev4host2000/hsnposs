/// طلب إنهاء الجلسة على السحابة.
class LogoutRequest {
  const LogoutRequest({
    this.refreshToken,
    this.revokeAllSessions = false,
  });

  factory LogoutRequest.fromJson(Map<String, dynamic> json) {
    return LogoutRequest(
      refreshToken: _optionalString(json['refresh_token']),
      revokeAllSessions:
          json['revoke_all_sessions'] == true ||
              json['revoke_all_sessions'] == 1,
    );
  }

  final String? refreshToken;
  final bool revokeAllSessions;

  Map<String, dynamic> toJson() => {
        if (refreshToken != null) 'refresh_token': refreshToken,
        'revoke_all_sessions': revokeAllSessions,
      };

  LogoutRequest copyWith({
    String? refreshToken,
    bool? revokeAllSessions,
  }) {
    return LogoutRequest(
      refreshToken: refreshToken ?? this.refreshToken,
      revokeAllSessions: revokeAllSessions ?? this.revokeAllSessions,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LogoutRequest &&
          runtimeType == other.runtimeType &&
          refreshToken == other.refreshToken &&
          revokeAllSessions == other.revokeAllSessions;

  @override
  int get hashCode => Object.hash(refreshToken, revokeAllSessions);
}

String? _optionalString(Object? value) {
  if (value == null) return null;
  final s = value.toString().trim();
  return s.isEmpty ? null : s;
}
