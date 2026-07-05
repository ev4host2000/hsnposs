import 'package:mizapos_mobile/services/cloud/models/cloud_session.dart';
import 'package:mizapos_mobile/services/cloud/models/cloud_token.dart';

/// استجابة تجديد token.
class RefreshTokenResponse {
  const RefreshTokenResponse({
    required this.token,
    this.session,
  });

  factory RefreshTokenResponse.fromJson(Object? json) {
    if (json is! Map) {
      return const RefreshTokenResponse(
        token: CloudToken(accessToken: ''),
      );
    }
    final map = Map<String, dynamic>.from(json);
    final token = map['token'] is Map
        ? CloudToken.fromJson(Map<String, dynamic>.from(map['token'] as Map))
        : CloudToken.fromJson(map);
    final session = map['session'] is Map
        ? CloudSession.fromJson(
            Map<String, dynamic>.from(map['session'] as Map),
          )
        : null;
    return RefreshTokenResponse(token: token, session: session);
  }

  final CloudToken token;
  final CloudSession? session;

  Map<String, dynamic> toJson() => {
        ...token.toJson(),
        if (session != null) 'session': session!.toJson(),
      };

  RefreshTokenResponse copyWith({
    CloudToken? token,
    CloudSession? session,
  }) {
    return RefreshTokenResponse(
      token: token ?? this.token,
      session: session ?? this.session,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RefreshTokenResponse &&
          runtimeType == other.runtimeType &&
          token == other.token &&
          session == other.session;

  @override
  int get hashCode => Object.hash(token, session);
}
