import 'package:mizapos_desktop/services/cloud/models/cloud_device.dart';
import 'package:mizapos_desktop/services/cloud/models/cloud_token.dart';
import 'package:mizapos_desktop/services/cloud/models/cloud_user.dart';

/// جلسة سحابية نشطة — يطابق `device_sessions` + سياق auth.
class CloudSession {
  const CloudSession({
    required this.sessionId,
    required this.deviceId,
    required this.companyId,
    required this.branchId,
    this.userId,
    this.sessionType = 'device',
    this.createdAt = '',
    this.lastActiveAt,
    this.expiresAt,
    this.revokedAt,
    this.token,
    this.device,
    this.user,
  });

  factory CloudSession.fromJson(Map<String, dynamic> json) {
    return CloudSession(
      sessionId: (json['session_id'] ?? json['id'] ?? '').toString(),
      deviceId: (json['device_id'] ?? '').toString(),
      companyId: (json['company_id'] ?? '').toString(),
      branchId: (json['branch_id'] ?? '').toString(),
      userId: _optionalString(json['user_id']),
      sessionType: (json['session_type'] ?? 'device').toString(),
      createdAt: (json['created_at'] ?? '').toString(),
      lastActiveAt: _optionalString(json['last_active_at']),
      expiresAt: _optionalString(json['expires_at']),
      revokedAt: _optionalString(json['revoked_at']),
      token: json['token'] is Map<String, dynamic>
          ? CloudToken.fromJson(
              Map<String, dynamic>.from(json['token'] as Map),
            )
          : _tokenFromFlatJson(json),
      device: json['device'] is Map<String, dynamic>
          ? CloudDevice.fromJson(
              Map<String, dynamic>.from(json['device'] as Map),
            )
          : null,
      user: json['user'] is Map<String, dynamic>
          ? CloudUser.fromJson(
              Map<String, dynamic>.from(json['user'] as Map),
            )
          : null,
    );
  }

  final String sessionId;
  final String deviceId;
  final String companyId;
  final String branchId;
  final String? userId;
  final String sessionType;
  final String createdAt;
  final String? lastActiveAt;
  final String? expiresAt;
  final String? revokedAt;
  final CloudToken? token;
  final CloudDevice? device;
  final CloudUser? user;

  Map<String, dynamic> toJson() => {
        'session_id': sessionId,
        'device_id': deviceId,
        'company_id': companyId,
        'branch_id': branchId,
        if (userId != null) 'user_id': userId,
        'session_type': sessionType,
        'created_at': createdAt,
        if (lastActiveAt != null) 'last_active_at': lastActiveAt,
        if (expiresAt != null) 'expires_at': expiresAt,
        if (revokedAt != null) 'revoked_at': revokedAt,
        if (token != null) 'token': token!.toJson(),
        if (device != null) 'device': device!.toJson(),
        if (user != null) 'user': user!.toJson(),
      };

  CloudSession copyWith({
    String? sessionId,
    String? deviceId,
    String? companyId,
    String? branchId,
    String? userId,
    String? sessionType,
    String? createdAt,
    String? lastActiveAt,
    String? expiresAt,
    String? revokedAt,
    CloudToken? token,
    CloudDevice? device,
    CloudUser? user,
  }) {
    return CloudSession(
      sessionId: sessionId ?? this.sessionId,
      deviceId: deviceId ?? this.deviceId,
      companyId: companyId ?? this.companyId,
      branchId: branchId ?? this.branchId,
      userId: userId ?? this.userId,
      sessionType: sessionType ?? this.sessionType,
      createdAt: createdAt ?? this.createdAt,
      lastActiveAt: lastActiveAt ?? this.lastActiveAt,
      expiresAt: expiresAt ?? this.expiresAt,
      revokedAt: revokedAt ?? this.revokedAt,
      token: token ?? this.token,
      device: device ?? this.device,
      user: user ?? this.user,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CloudSession &&
          runtimeType == other.runtimeType &&
          sessionId == other.sessionId &&
          deviceId == other.deviceId &&
          companyId == other.companyId &&
          branchId == other.branchId &&
          userId == other.userId &&
          sessionType == other.sessionType &&
          createdAt == other.createdAt &&
          lastActiveAt == other.lastActiveAt &&
          expiresAt == other.expiresAt &&
          revokedAt == other.revokedAt &&
          token == other.token &&
          device == other.device &&
          user == other.user;

  @override
  int get hashCode => Object.hash(
        sessionId,
        deviceId,
        companyId,
        branchId,
        userId,
        sessionType,
        createdAt,
        lastActiveAt,
        expiresAt,
        revokedAt,
        token,
        device,
        user,
      );
}

CloudToken? _tokenFromFlatJson(Map<String, dynamic> json) {
  final access = (json['access_token'] ?? '').toString();
  if (access.isEmpty) return null;
  return CloudToken.fromJson(json);
}

String? _optionalString(Object? value) {
  if (value == null) return null;
  final s = value.toString().trim();
  return s.isEmpty ? null : s;
}
