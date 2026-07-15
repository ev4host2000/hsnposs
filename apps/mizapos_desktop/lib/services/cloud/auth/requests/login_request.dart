/// طلب تسجيل الدخول إلى Miza Cloud.
class LoginRequest {
  const LoginRequest({
    required this.username,
    required this.password,
    this.companyId,
    this.deviceId,
    this.installationId,
    this.branchId,
  });

  factory LoginRequest.fromJson(Map<String, dynamic> json) {
    return LoginRequest(
      username: (json['username'] ?? json['email'] ?? '').toString(),
      password: (json['password'] ?? '').toString(),
      companyId: _optionalString(json['company_id']),
      deviceId: _optionalString(json['device_id']),
      installationId: _optionalString(json['installation_id']),
      branchId: _optionalString(json['branch_id']),
    );
  }

  final String username;
  final String password;
  final String? companyId;
  final String? deviceId;
  final String? installationId;
  final String? branchId;

  Map<String, dynamic> toJson() => {
        'username': username,
        'password': password,
        if (companyId != null) 'company_id': companyId,
        if (deviceId != null) 'device_id': deviceId,
        if (installationId != null) 'installation_id': installationId,
        if (branchId != null) 'branch_id': branchId,
      };

  LoginRequest copyWith({
    String? username,
    String? password,
    String? companyId,
    String? deviceId,
    String? installationId,
    String? branchId,
  }) {
    return LoginRequest(
      username: username ?? this.username,
      password: password ?? this.password,
      companyId: companyId ?? this.companyId,
      deviceId: deviceId ?? this.deviceId,
      installationId: installationId ?? this.installationId,
      branchId: branchId ?? this.branchId,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LoginRequest &&
          runtimeType == other.runtimeType &&
          username == other.username &&
          password == other.password &&
          companyId == other.companyId &&
          deviceId == other.deviceId &&
          installationId == other.installationId &&
          branchId == other.branchId;

  @override
  int get hashCode => Object.hash(
        username,
        password,
        companyId,
        deviceId,
        installationId,
        branchId,
      );
}

String? _optionalString(Object? value) {
  if (value == null) return null;
  final s = value.toString().trim();
  return s.isEmpty ? null : s;
}
