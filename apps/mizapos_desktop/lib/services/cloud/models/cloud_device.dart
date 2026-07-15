/// جهاز مسجّل على Miza Cloud — يطابق `devices` (+ `is_self` محلي اختياري).
class CloudDevice {
  const CloudDevice({
    required this.id,
    required this.companyId,
    required this.installationId,
    this.deviceFingerprint,
    this.platform = '',
    this.deviceName,
    this.osName,
    this.osUser,
    this.appVersion,
    this.status = 'active',
    this.registeredAt = '',
    this.lastSeenAt,
    this.revokedAt,
    this.registeredByUserId,
    this.rowVersion = 0,
    this.isSelf = false,
  });

  factory CloudDevice.fromJson(Map<String, dynamic> json) {
    return CloudDevice(
      id: (json['id'] ?? json['device_id'] ?? '').toString(),
      companyId: (json['company_id'] ?? '').toString(),
      installationId: (json['installation_id'] ?? '').toString(),
      deviceFingerprint: _optionalString(json['device_fingerprint']),
      platform: (json['platform'] ?? '').toString(),
      deviceName: _optionalString(json['device_name']),
      osName: _optionalString(json['os_name']),
      osUser: _optionalString(json['os_user']),
      appVersion: _optionalString(json['app_version']),
      status: (json['status'] ?? 'active').toString(),
      registeredAt: (json['registered_at'] ?? '').toString(),
      lastSeenAt: _optionalString(json['last_seen_at']),
      revokedAt: _optionalString(json['revoked_at']),
      registeredByUserId: _optionalString(json['registered_by_user_id']),
      rowVersion: _asInt(json['row_version']),
      isSelf: json['is_self'] == true || json['is_self'] == 1,
    );
  }

  final String id;
  final String companyId;
  final String installationId;
  final String? deviceFingerprint;
  final String platform;
  final String? deviceName;
  final String? osName;
  final String? osUser;
  final String? appVersion;
  final String status;
  final String registeredAt;
  final String? lastSeenAt;
  final String? revokedAt;
  final String? registeredByUserId;
  final int rowVersion;
  final bool isSelf;

  Map<String, dynamic> toJson() => {
        'id': id,
        'company_id': companyId,
        'installation_id': installationId,
        if (deviceFingerprint != null)
          'device_fingerprint': deviceFingerprint,
        'platform': platform,
        if (deviceName != null) 'device_name': deviceName,
        if (osName != null) 'os_name': osName,
        if (osUser != null) 'os_user': osUser,
        if (appVersion != null) 'app_version': appVersion,
        'status': status,
        'registered_at': registeredAt,
        if (lastSeenAt != null) 'last_seen_at': lastSeenAt,
        if (revokedAt != null) 'revoked_at': revokedAt,
        if (registeredByUserId != null)
          'registered_by_user_id': registeredByUserId,
        'row_version': rowVersion,
        'is_self': isSelf,
      };

  CloudDevice copyWith({
    String? id,
    String? companyId,
    String? installationId,
    String? deviceFingerprint,
    String? platform,
    String? deviceName,
    String? osName,
    String? osUser,
    String? appVersion,
    String? status,
    String? registeredAt,
    String? lastSeenAt,
    String? revokedAt,
    String? registeredByUserId,
    int? rowVersion,
    bool? isSelf,
  }) {
    return CloudDevice(
      id: id ?? this.id,
      companyId: companyId ?? this.companyId,
      installationId: installationId ?? this.installationId,
      deviceFingerprint: deviceFingerprint ?? this.deviceFingerprint,
      platform: platform ?? this.platform,
      deviceName: deviceName ?? this.deviceName,
      osName: osName ?? this.osName,
      osUser: osUser ?? this.osUser,
      appVersion: appVersion ?? this.appVersion,
      status: status ?? this.status,
      registeredAt: registeredAt ?? this.registeredAt,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      revokedAt: revokedAt ?? this.revokedAt,
      registeredByUserId: registeredByUserId ?? this.registeredByUserId,
      rowVersion: rowVersion ?? this.rowVersion,
      isSelf: isSelf ?? this.isSelf,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CloudDevice &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          companyId == other.companyId &&
          installationId == other.installationId &&
          deviceFingerprint == other.deviceFingerprint &&
          platform == other.platform &&
          deviceName == other.deviceName &&
          osName == other.osName &&
          osUser == other.osUser &&
          appVersion == other.appVersion &&
          status == other.status &&
          registeredAt == other.registeredAt &&
          lastSeenAt == other.lastSeenAt &&
          revokedAt == other.revokedAt &&
          registeredByUserId == other.registeredByUserId &&
          rowVersion == other.rowVersion &&
          isSelf == other.isSelf;

  @override
  int get hashCode => Object.hash(
        id,
        companyId,
        installationId,
        deviceFingerprint,
        platform,
        deviceName,
        osName,
        osUser,
        appVersion,
        status,
        registeredAt,
        lastSeenAt,
        revokedAt,
        registeredByUserId,
        rowVersion,
        isSelf,
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
