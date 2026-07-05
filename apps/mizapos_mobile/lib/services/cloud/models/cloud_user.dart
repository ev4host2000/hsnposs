/// مستخدم سحابي (موظف/مالك) — يطابق `users` في PostgreSQL (بدون password).
class CloudUser {
  const CloudUser({
    required this.id,
    required this.companyId,
    required this.defaultBranchId,
    required this.username,
    required this.fullName,
    this.email,
    this.phone,
    this.dialCode = '+970',
    this.role = '',
    this.accountStatus = 'active',
    this.emailVerifiedAt,
    this.lastLoginAt,
    this.createdAt = '',
    this.updatedAt = '',
    this.deletedAt,
    this.rowVersion = 0,
  });

  factory CloudUser.fromJson(Map<String, dynamic> json) {
    return CloudUser(
      id: (json['id'] ?? '').toString(),
      companyId: (json['company_id'] ?? '').toString(),
      defaultBranchId: (json['default_branch_id'] ?? '').toString(),
      username: (json['username'] ?? '').toString(),
      fullName: (json['full_name'] ?? '').toString(),
      email: _optionalString(json['email']),
      phone: _optionalString(json['phone']),
      dialCode: (json['dial_code'] ?? '+970').toString(),
      role: (json['role'] ?? '').toString(),
      accountStatus: (json['account_status'] ?? 'active').toString(),
      emailVerifiedAt: _optionalString(json['email_verified_at']),
      lastLoginAt: _optionalString(json['last_login_at']),
      createdAt: (json['created_at'] ?? '').toString(),
      updatedAt: (json['updated_at'] ?? '').toString(),
      deletedAt: _optionalString(json['deleted_at']),
      rowVersion: _asInt(json['row_version']),
    );
  }

  final String id;
  final String companyId;
  final String defaultBranchId;
  final String username;
  final String fullName;
  final String? email;
  final String? phone;
  final String dialCode;
  final String role;
  final String accountStatus;
  final String? emailVerifiedAt;
  final String? lastLoginAt;
  final String createdAt;
  final String updatedAt;
  final String? deletedAt;
  final int rowVersion;

  Map<String, dynamic> toJson() => {
        'id': id,
        'company_id': companyId,
        'default_branch_id': defaultBranchId,
        'username': username,
        'full_name': fullName,
        if (email != null) 'email': email,
        if (phone != null) 'phone': phone,
        'dial_code': dialCode,
        'role': role,
        'account_status': accountStatus,
        if (emailVerifiedAt != null) 'email_verified_at': emailVerifiedAt,
        if (lastLoginAt != null) 'last_login_at': lastLoginAt,
        'created_at': createdAt,
        'updated_at': updatedAt,
        if (deletedAt != null) 'deleted_at': deletedAt,
        'row_version': rowVersion,
      };

  CloudUser copyWith({
    String? id,
    String? companyId,
    String? defaultBranchId,
    String? username,
    String? fullName,
    String? email,
    String? phone,
    String? dialCode,
    String? role,
    String? accountStatus,
    String? emailVerifiedAt,
    String? lastLoginAt,
    String? createdAt,
    String? updatedAt,
    String? deletedAt,
    int? rowVersion,
  }) {
    return CloudUser(
      id: id ?? this.id,
      companyId: companyId ?? this.companyId,
      defaultBranchId: defaultBranchId ?? this.defaultBranchId,
      username: username ?? this.username,
      fullName: fullName ?? this.fullName,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      dialCode: dialCode ?? this.dialCode,
      role: role ?? this.role,
      accountStatus: accountStatus ?? this.accountStatus,
      emailVerifiedAt: emailVerifiedAt ?? this.emailVerifiedAt,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      rowVersion: rowVersion ?? this.rowVersion,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CloudUser &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          companyId == other.companyId &&
          defaultBranchId == other.defaultBranchId &&
          username == other.username &&
          fullName == other.fullName &&
          email == other.email &&
          phone == other.phone &&
          dialCode == other.dialCode &&
          role == other.role &&
          accountStatus == other.accountStatus &&
          emailVerifiedAt == other.emailVerifiedAt &&
          lastLoginAt == other.lastLoginAt &&
          createdAt == other.createdAt &&
          updatedAt == other.updatedAt &&
          deletedAt == other.deletedAt &&
          rowVersion == other.rowVersion;

  @override
  int get hashCode => Object.hash(
        id,
        companyId,
        defaultBranchId,
        username,
        fullName,
        email,
        phone,
        dialCode,
        role,
        accountStatus,
        emailVerifiedAt,
        lastLoginAt,
        createdAt,
        updatedAt,
        deletedAt,
        rowVersion,
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
