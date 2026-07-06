import 'dart:async' show unawaited;
import 'dart:convert';
import 'dart:math';
import 'dart:io';

import 'package:mizapos_mobile/config/opening_balance_voucher_config.dart';
import 'package:mizapos_mobile/config/remote_signup_config.dart';
import 'package:mizapos_mobile/models/entities.dart';
import 'package:mizapos_mobile/models/miza_payment_types.dart';
import 'package:mizapos_mobile/models/signup_approval_mail.dart';
import 'package:mizapos_mobile/security/password_crypto.dart';
import 'package:mizapos_mobile/security/security_preferences.dart';
import 'package:mizapos_mobile/services/activation_api_contract.dart';
import 'package:mizapos_mobile/services/admin_broadcast_notice.dart';
import 'package:mizapos_mobile/services/cloud/sync/catalog_sync_constants.dart';
import 'package:mizapos_mobile/services/cloud/sync/catalog_sync_outbox_writer.dart';
import 'package:mizapos_mobile/services/cloud/sync/partners_sync_constants.dart';
import 'package:mizapos_mobile/services/cloud/sync/product_sync_outbox_writer.dart';
import 'package:mizapos_mobile/services/cloud/sync/transaction_invoice_sync_service.dart';
import 'package:mizapos_mobile/services/cloud/sync/transaction_payment_sync_service.dart';
import 'package:mizapos_mobile/services/cloud/sync/transaction_inventory_adjustment_sync_service.dart';
import 'package:mizapos_mobile/services/cloud/sync/transaction_opening_stock_sync_service.dart';
import 'package:mizapos_mobile/services/cloud/sync/transaction_return_sync_service.dart';
import 'package:mizapos_mobile/services/database_service.dart';
import 'package:mizapos_mobile/services/operational_scope_resolver.dart';
import 'package:mizapos_mobile/services/database_startup_diagnostics.dart';
import 'package:mizapos_mobile/services/device_binding.dart';
import 'package:mizapos_mobile/services/app_local_data_wiper.dart';
import 'package:mizapos_mobile/services/license_gate.dart';
import 'package:mizapos_mobile/services/remote_signup_api.dart';
import 'package:mizapos_mobile/services/team_users_sync_service.dart';
import 'package:mizapos_mobile/services/field_truck_stock_sync_service.dart';
import 'package:mizapos_mobile/services/voucher_session_manager.dart';
import 'package:mizapos_mobile/services/voucher_session_store.dart';
import 'package:mizapos_mobile/utils/app_data_paths.dart';
import 'package:mizapos_mobile/utils/debug_session_log.dart';
import 'package:mizapos_mobile/utils/device_link_code.dart';
import 'package:mizapos_mobile/utils/invoice_display_number.dart';
import 'package:mizapos_mobile/services/smtp_activation_mailer.dart';
import 'package:flutter/foundation.dart' show VoidCallback;
import 'package:intl/intl.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

String? _productExpiryDayForSql(DateTime? d) {
  if (d == null) return null;
  final y = d.year.toString().padLeft(4, '0');
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}

/// بلا قسيمة سارية: وصل حد أصناف التجربة (10) — تُطلب القسيمة.
class ProductCatalogTrialLimitException implements Exception {
  const ProductCatalogTrialLimitException();

  static const int limit = 10;
}

class AccountingService {
  AccountingService(this._databaseService);

  final DatabaseService _databaseService;

  /// يضمن اكتمال إنشاء/فتح قاعدة البيانات المحلية قبل عرض الواجهة الرئيسية.
  Future<void> ensureLocalDatabaseReady() async {
    await _databaseService.database;
  }

  Future<Map<String, Object?>> logDatabaseStartupDiagnostics() {
    return DatabaseStartupDiagnostics.log(
      databaseService: _databaseService,
      accountingService: this,
    );
  }

  /// بعد دخول القسيمة/الموظف — يُعيد محاذاة الجلسة مع مؤسسة فيها بيانات.
  Future<void> reconcileSessionOperationalScope() async {
    final s = _session;
    if (s == null) return;
    final db = await _databaseService.database;
    await OperationalScopeResolver.alignUserScopeIfEmpty(
      db: db,
      userId: s.userId,
    );
    final rows = await db.query(
      'users',
      where: 'id = ?',
      whereArgs: [s.userId],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final row = rows.first;
    final orgId = row['organizationId'] as String;
    final branchId = row['branchId'] as String;
    if (orgId == s.organizationId && branchId == s.branchId) return;
    _session = AppUserSession(
      organizationId: orgId,
      branchId: branchId,
      userId: row['id'] as String,
      role: row['role'] as String,
      username: row['username'] as String,
    );
    // #region agent log
    DebugSessionLog.write(
      location: 'accounting_service.dart:reconcileSessionOperationalScope',
      message: 'session scope realigned',
      hypothesisId: 'H2-owner-scope',
      runId: 'post-fix',
      data: {
        'organizationId': _session!.organizationId,
        'branchId': _session!.branchId,
        'role': _session!.role,
      },
    );
    // #endregion
  }
  final Uuid _uuid = const Uuid();
  final LicenseGate licenseGate = LicenseGate();

  /// تنسيق التلقائي: `[prefix]-[تسلسل]` مثل `Miza-1` أو `OB-12`.
  static RegExp _openingVoucherSeqRegex(String prefix) {
    final p = normalizeCustomerOpeningVoucherPrefix(prefix);
    return RegExp('^${RegExp.escape(p)}-(\\d+)\$');
  }

  static int _maxCustomerOpeningVoucherSeqForPrefix(
    List<Map<String, Object?>> rows,
    String prefix,
  ) {
    final re = _openingVoucherSeqRegex(prefix);
    var maxSeq = 0;
    for (final r in rows) {
      final v = (r['voucherNumber'] as String?)?.trim() ?? '';
      final m = re.firstMatch(v);
      if (m != null) {
        final n = int.tryParse(m.group(1)!) ?? 0;
        if (n > maxSeq) maxSeq = n;
      }
    }
    return maxSeq;
  }

  /// بادئة آمنة للترقيم (لا فراغات فقط؛ بدون `-` لأنه فاصل التسلسل).
  static String normalizeCustomerOpeningVoucherPrefix(String input) {
    var p = input.trim();
    p = p.replaceAll(RegExp(r'\s+'), '');
    p = p.replaceAll('-', '');
    if (p.isEmpty) p = OpeningBalanceVoucherConfig.defaultPrefix;
    return p;
  }

  /// الرقم التالي المعروض في الواجهة (قبل الحفظ) لبادئة معيّنة.
  Future<String> peekNextCustomerOpeningVoucherNumber({
    String prefix = OpeningBalanceVoucherConfig.defaultPrefix,
  }) async {
    final p = normalizeCustomerOpeningVoucherPrefix(prefix);
    final s = _mustSession();
    final db = await _databaseService.database;
    final rows = await db.query(
      'partnerLedger',
      columns: ['voucherNumber'],
      where:
          'organizationId = ? AND branchId = ? AND partnerKind = ? AND voucherNumber IS NOT NULL AND voucherNumber != ?',
      whereArgs: [s.organizationId, s.branchId, 'customer', ''],
    );
    final next = _maxCustomerOpeningVoucherSeqForPrefix(rows, p) + 1;
    return '$p-$next';
  }

  /// رقم سند عشوائي فريد لرصيد افتتاحي (`[prefix]-[6 أرقام]`).
  Future<String> generateRandomCustomerOpeningVoucherNumber({
    String prefix = OpeningBalanceVoucherConfig.defaultPrefix,
  }) async {
    final p = normalizeCustomerOpeningVoucherPrefix(prefix);
    final s = _mustSession();
    final db = await _databaseService.database;
    final rnd = Random();
    for (var attempt = 0; attempt < 48; attempt++) {
      final seq = 100000 + rnd.nextInt(900000);
      final v = '$p-$seq';
      final rows = await db.query(
        'partnerLedger',
        columns: ['id'],
        where:
            'organizationId = ? AND branchId = ? AND partnerKind = ? AND voucherNumber = ?',
        whereArgs: [s.organizationId, s.branchId, 'customer', v],
        limit: 1,
      );
      if (rows.isEmpty) return v;
    }
    return '$p-${DateTime.now().microsecondsSinceEpoch}';
  }

  Future<String> _resolveCustomerOpeningVoucherNumber(
    Transaction txn,
    String? voucherNumber, {
    String autoPrefix = OpeningBalanceVoucherConfig.defaultPrefix,
  }) async {
    final manual = voucherNumber?.trim();
    if (manual != null && manual.isNotEmpty) return manual;
    final p = normalizeCustomerOpeningVoucherPrefix(autoPrefix);
    final s = _mustSession();
    final rows = await txn.query(
      'partnerLedger',
      columns: ['voucherNumber'],
      where:
          'organizationId = ? AND branchId = ? AND partnerKind = ? AND voucherNumber IS NOT NULL AND voucherNumber != ?',
      whereArgs: [s.organizationId, s.branchId, 'customer', ''],
    );
    final next = _maxCustomerOpeningVoucherSeqForPrefix(rows, p) + 1;
    return '$p-$next';
  }

  static int _maxSupplierOpeningVoucherSeqForPrefix(
    List<Map<String, Object?>> rows,
    String prefix,
  ) {
    final p = normalizeSupplierOpeningVoucherPrefix(prefix);
    final re = RegExp('^${RegExp.escape(p)}-(\\d+)\$');
    var maxSeq = 0;
    for (final r in rows) {
      final v = (r['voucherNumber'] as String?)?.trim() ?? '';
      final m = re.firstMatch(v);
      if (m != null) {
        final n = int.tryParse(m.group(1)!) ?? 0;
        if (n > maxSeq) maxSeq = n;
      }
    }
    return maxSeq;
  }

  static String normalizeSupplierOpeningVoucherPrefix(String input) {
    var p = input.trim().replaceAll(RegExp(r'\s+'), '').replaceAll('-', '');
    if (p.isEmpty) p = OpeningBalanceVoucherConfig.defaultPrefix;
    return p;
  }

  Future<String> peekNextSupplierOpeningVoucherNumber({
    String prefix = OpeningBalanceVoucherConfig.defaultPrefix,
  }) async {
    final p = normalizeSupplierOpeningVoucherPrefix(prefix);
    final s = _mustSession();
    final db = await _databaseService.database;
    final rows = await db.query(
      'partnerLedger',
      columns: ['voucherNumber'],
      where:
          'organizationId = ? AND branchId = ? AND partnerKind = ? AND voucherNumber IS NOT NULL AND voucherNumber != ?',
      whereArgs: [s.organizationId, s.branchId, 'supplier', ''],
    );
    final next = _maxSupplierOpeningVoucherSeqForPrefix(rows, p) + 1;
    return '$p-$next';
  }

  Future<String> _resolveSupplierOpeningVoucherNumber(
    Transaction txn,
    String? voucherNumber, {
    String autoPrefix = OpeningBalanceVoucherConfig.defaultPrefix,
  }) async {
    final manual = voucherNumber?.trim();
    if (manual != null && manual.isNotEmpty) return manual;
    final p = normalizeSupplierOpeningVoucherPrefix(autoPrefix);
    final s = _mustSession();
    final rows = await txn.query(
      'partnerLedger',
      columns: ['voucherNumber'],
      where:
          'organizationId = ? AND branchId = ? AND partnerKind = ? AND voucherNumber IS NOT NULL AND voucherNumber != ?',
      whereArgs: [s.organizationId, s.branchId, 'supplier', ''],
    );
    final next = _maxSupplierOpeningVoucherSeqForPrefix(rows, p) + 1;
    return '$p-$next';
  }

  bool _subscriptionBindingMismatch = false;
  AdminBroadcastNotice? _pendingAdminBroadcastNotice;
  final List<VoidCallback> _adminBroadcastListeners = [];

  void addAdminBroadcastListener(VoidCallback listener) {
    if (!_adminBroadcastListeners.contains(listener)) {
      _adminBroadcastListeners.add(listener);
    }
  }

  void removeAdminBroadcastListener(VoidCallback listener) {
    _adminBroadcastListeners.remove(listener);
  }

  void _emitAdminBroadcastListeners() {
    for (final cb in List<VoidCallback>.from(_adminBroadcastListeners)) {
      try {
        cb();
      } catch (_) {}
    }
  }

  void _setPendingAdminBroadcastNotice(AdminBroadcastNotice? notice) {
    final prevId = _pendingAdminBroadcastNotice?.id;
    final nextId = notice?.id;
    _pendingAdminBroadcastNotice = notice;
    if (prevId != nextId) {
      _emitAdminBroadcastListeners();
    }
  }

  /// آخر مزامنة ترخيص اكتشفت اشتراكاً مسجَّلاً لجهاز/حساب آخر.
  bool get subscriptionBindingMismatch => _subscriptionBindingMismatch;

  /// إشعار جماعي من لوحة التفعيل (يُحدَّث عند [syncLicenseGate] أو [refreshAdminBroadcastNotice]).
  AdminBroadcastNotice? get pendingAdminBroadcastNotice =>
      _pendingAdminBroadcastNotice;

  Future<void> _applyBroadcastNoticeFromPull(Map<String, dynamic> pull) async {
    _setPendingAdminBroadcastNotice(null);
  }

  /// معطّل — لم يعد يُستخدم إشعار جماعي من لوحة التفعيل.
  Future<void> refreshAdminBroadcastNotice() async {
    _setPendingAdminBroadcastNotice(null);
  }

  Future<void> dismissPendingAdminBroadcastNotice() async {
    _setPendingAdminBroadcastNotice(null);
  }

  /// هوية البريد للربط مع [DeviceBinding] (البريد من القاعدة أو اسم الدخول).
  static String normalizeSubscriptionIdentity(
      String? dbEmail, String username) {
    final e = (dbEmail ?? '').trim().toLowerCase();
    if (e.isNotEmpty) return e;
    return username.trim().toLowerCase();
  }

  /// صف [users] يُنشأ من التسجيل عبر خادم الويب ولم يُكمَّل تفعيله بالرمز بعد.
  static bool rowWebActivationPending(Map<String, Object?> row) {
    final v = row['webActivationPending'];
    if (v is int) return v != 0;
    if (v is num) return v.toInt() != 0;
    return false;
  }

  /// يطابق عمود [users.subscriptionAccessSuspended] بعد المزامنة من خادم التفعيل.
  static bool rowSubscriptionAccessSuspended(Map<String, Object?> row) {
    final v = row['subscriptionAccessSuspended'];
    if (v is int) return v != 0;
    if (v is num) return v.toInt() != 0;
    return false;
  }

  /// يطابق ربط الاشتراك عبر **جزء هوية البريد** في الحمولة ليُسمح باستخدام نفس الدفع
  /// على حاسوب ويندوز وهاتف أندرويد (الجهاز يغيّر بقية الحقول).
  static bool _subscriptionBindingMatches(
      String storedBinding, String currentToken) {
    final s = storedBinding.trim();
    final c = currentToken.trim();
    if (s.isEmpty) return true;
    final ps = s.split('|');
    final pc = c.split('|');
    if (ps.length >= 5 && pc.length >= 5) {
      return ps.last == pc.last;
    }
    return s == c;
  }

  /// فواتير «منشورة» فقط (تستبعد الملغاة وظهورها في المبيعات/المشتريات).
  static String _sqlInvoicePostedAlias(String alias) =>
      "(IFNULL($alias.invoiceStatus,'posted') <> 'voided')";

  /// مبيعات محسوبة في الإيرادات والتقارير (تستبعد الملغاة وعروض الأسعار).
  static String _sqlPostedSalesRevenueAlias(String alias) =>
      "(IFNULL($alias.invoiceStatus,'posted') NOT IN ('voided','quote'))";

  static bool invoiceRowIsPriceQuote(Map<String, Object?> row) =>
      (row['invoiceStatus'] ?? 'posted').toString() == 'quote';

  static String _ledgerMovementKindCustomer(String entryType) {
    switch (entryType) {
      case 'sale_ar':
        return 'ذمة عميل / فاتورة آجل';
      case 'customer_payment':
        return 'دفعة عميل';
      case 'sale_void':
        return 'إلغاء فاتورة بيع';
      case 'sale_return':
        return 'مرتجع بيع';
      case 'partner_transfer':
        return 'تحويل ذمة';
      case 'opening_balance':
        return 'رصيد افتتاحي (له)';
      case 'sale_overpay_credit':
        return 'باقي دفع — رصيد للعميل';
      default:
        return entryType;
    }
  }

  static String _ledgerMovementKindSupplier(String entryType) {
    switch (entryType) {
      case 'purchase_ap':
        return 'ذمة مورد / فاتورة شراء آجل';
      case 'supplier_payment':
        return 'دفعة مورد';
      case 'purchase_void':
        return 'إلغاء فاتورة شراء';
      case 'purchase_return':
        return 'مرتجع شراء';
      case 'partner_transfer':
        return 'تحويل ذمة';
      case 'opening_balance':
        return 'رصيد افتتاحي مورد';
      default:
        return entryType;
    }
  }

  static String _ledgerReferenceArabic(String referenceType) {
    switch (referenceType) {
      case 'sale':
        return 'فاتورة بيع';
      case 'purchase':
        return 'فاتورة شراء';
      case 'customer_payment':
        return 'سند قبض';
      case 'supplier_payment':
        return 'سند صرف';
      case 'sale_void':
        return 'إلغاء بيع';
      case 'purchase_void':
        return 'إلغاء شراء';
      case 'sale_return':
        return 'مرتجع بيع';
      case 'purchase_return':
        return 'مرتجع شراء';
      case 'partner_transfer':
        return 'تحويل ذمة';
      case 'damage':
        return 'تالف مخزني';
      case 'opening_balance':
        return 'رصيد افتتاحي';
      default:
        return referenceType;
    }
  }

  AppUserSession? _session;

  /// عَلَم يُضبط فور انتهاء آخر استدعاء لـ [login]:
  ///   • `true` إذا تعذّر الاتصال بخادم التفعيل واكتمل الدخول محلياً.
  ///   • `false` إذا نجح فحص الخادم أو كان معطّلاً كلّياً.
  /// تستخدمه واجهة [LoginScreen] لإظهار تنبيه «دخول محليّ بدون إنترنت».
  /// لا يؤثّر على صلاحيات الجلسة — فحص كلمة المرور وقفل الترخيص يعملان
  /// محلياً بالكامل من قاعدة البيانات.
  bool _lastLoginWasOffline = false;

  bool get wasLastLoginOffline => _lastLoginWasOffline;
  DateTime _lastActivityAt = DateTime.now();
  bool _suppressIdleBump = false;
  SecurityPreferences _securityPrefs = SecurityPreferences.defaults;

  AppUserSession? get session => _session;

  SecurityPreferences get securityPreferences => _securityPrefs;

  void applySecurityPreferences(SecurityPreferences prefs) {
    _securityPrefs = prefs;
  }

  /// كلمة مرور موحّدة لفتح قفل الخمول (إن فعّلها المالك في الإعدادات).
  bool get programUnlockActive {
    final h = _securityPrefs.programUnlockPasswordHash;
    return _securityPrefs.programUnlockPasswordEnabled &&
        h != null &&
        h.trim().isNotEmpty;
  }

  bool verifyProgramUnlockPassword(String plain) {
    final h = _securityPrefs.programUnlockPasswordHash;
    if (h == null || h.trim().isEmpty) return false;
    return PasswordCrypto.verifyPlainOrHash(plain, h);
  }

  /// كلمة سر دخول المدير الحصرية (إن فعّلها المالك).
  bool get ownerLoginPasswordActive {
    final h = _securityPrefs.ownerLoginPasswordHash;
    return _securityPrefs.ownerLoginPasswordEnabled &&
        h != null &&
        h.trim().isNotEmpty;
  }

  bool verifyOwnerLoginPassword(String plain) {
    final h = _securityPrefs.ownerLoginPasswordHash;
    if (h == null || h.trim().isEmpty) return false;
    return PasswordCrypto.verifyPlainOrHash(plain, h);
  }

  Future<List<Map<String, Object?>>> listActiveUsersByRole(String role) async {
    final orgId = _session?.organizationId;
    if (orgId == null || orgId.trim().isEmpty) return [];
    final rl = role.trim().toLowerCase();
    if (rl == 'owner') {
      await ensureLocalOwnerForSubscription();
    }
    final tenant = await activeSubscriptionEmailForSync(
      localOrganizationId: orgId,
    );
    final db = await _databaseService.database;
    final args = <Object?>[orgId, rl];
    var tenantSql = '';
    if (tenant != null && tenant.contains('@')) {
      tenantSql = '''
        AND lower(trim(COALESCE(teamSubscriptionEmail, ''))) = lower(?)
      ''';
      args.add(tenant);
    }
    final rows = await db.rawQuery(
      '''
      SELECT id, username, fullName, role
      FROM users
      WHERE organizationId = ?
        AND lower(trim(role)) = ?
        AND COALESCE(accountStatus, 'active') = 'active'
        $tenantSql
      ORDER BY fullName COLLATE NOCASE, username COLLATE NOCASE
      ''',
      args,
    );
    return rows.map((e) => Map<String, Object?>.from(e)).toList();
  }

  /// يضمن وجود صف «مدير» محلي لصاحب الاشتراك عند تفعيل القسيمة على الجهاز.
  Future<bool> ensureLocalOwnerForSubscription() async {
    final db = await _databaseService.database;
    var orgId = await OperationalScopeResolver.resolveOperationalOrganizationId(
      db,
      organizationId: _session?.organizationId,
      branchId: _session?.branchId,
    );
    orgId = orgId?.trim() ?? '';
    if (orgId.isEmpty) return false;

    final ownerExists = await db.rawQuery(
      '''
      SELECT id FROM users
      WHERE organizationId = ?
        AND lower(trim(role)) = 'owner'
        AND COALESCE(accountStatus, 'active') = 'active'
      LIMIT 1
      ''',
      [orgId],
    );
    if (ownerExists.isNotEmpty) return true;

    final voucherActive = _voucherSubscriptionActiveOnDevice;
    final offline = await VoucherSessionStore().readOfflineCredentials();
    final offlineEmail = (offline['email'] ?? '').trim().toLowerCase();
    final offlineHash = (offline['pwdHash'] ?? '').trim();
    final hasOfflineCreds =
        offlineEmail.contains('@') && PasswordCrypto.looksLikeBcrypt(offlineHash);
    if (!voucherActive && !hasOfflineCreds) return false;

    String? email;
    var fullName = '';
    String? pwdHash;
    var dialCode = '+970';
    var phone = '';

    final vSess = VoucherSessionManager.instance.sessionNotifier.value;
    if (vSess != null) {
      final e = vSess.email.trim().toLowerCase();
      if (e.contains('@')) email = e;
      fullName = vSess.fullName.trim();
      if (vSess.dialCode.trim().isNotEmpty) dialCode = vSess.dialCode.trim();
      phone = vSess.phone.trim();
    }

    if (hasOfflineCreds) {
      email ??= offlineEmail;
      pwdHash ??= offlineHash;
      if (fullName.isEmpty) fullName = (offline['fullName'] ?? '').trim();
      if ((offline['dialCode'] ?? '').trim().isNotEmpty) {
        dialCode = offline['dialCode']!.trim();
      }
      if ((offline['phone'] ?? '').trim().isNotEmpty) {
        phone = offline['phone']!.trim();
      }
    }

    if (email == null || !email.contains('@')) {
      final su = await db.query(
        'signup_requests',
        columns: ['email', 'fullName'],
        where: 'organizationId = ?',
        whereArgs: [orgId],
        orderBy: 'requestedAt DESC',
        limit: 1,
      );
      if (su.isNotEmpty) {
        final em = (su.first['email'] as String?)?.trim().toLowerCase() ?? '';
        if (em.contains('@')) {
          email = em;
          fullName = fullName.isNotEmpty
              ? fullName
              : ((su.first['fullName'] as String?)?.trim() ?? '');
        }
      }
    }

    if (email == null || !email.contains('@')) return false;

    final existing = await db.rawQuery(
      '''
      SELECT id, role FROM users
      WHERE organizationId = ?
        AND (lower(trim(email)) = ? OR lower(trim(username)) = ?)
        AND lower(trim(role)) <> 'guest'
        AND COALESCE(accountStatus, 'active') = 'active'
      LIMIT 1
      ''',
      [orgId, email, email],
    );
    if (existing.isNotEmpty) {
      final role = (existing.first['role'] as String?)?.trim().toLowerCase() ?? '';
      if (role == 'owner') return true;
      return false;
    }

    final hash = pwdHash ?? offlineHash;
    if (!PasswordCrypto.looksLikeBcrypt(hash)) return false;

    final branchRows = await db.query(
      'branches',
      columns: ['id'],
      where: 'organizationId = ?',
      whereArgs: [orgId],
      orderBy: 'createdAt ASC',
      limit: 1,
    );
    if (branchRows.isEmpty) return false;
    final branchId = branchRows.first['id'] as String;
    final now = DateTime.now().toIso8601String();

    await db.insert('users', {
      'id': _uuid.v4(),
      'organizationId': orgId,
      'branchId': branchId,
      'fullName': fullName.isNotEmpty ? fullName : email,
      'username': email,
      'email': email,
      'phone': phone,
      'dialCode': dialCode,
      'password': hash,
      'role': 'owner',
      'accountStatus': 'active',
      'createdAt': now,
      'fromSignupRequestId': null,
      'webActivationPending': 0,
    });
    return true;
  }

  Duration get idleLockDuration =>
      Duration(minutes: _securityPrefs.idleLockMinutes.clamp(1, 480));

  /// يوقف عدّ نشاط الخمول (مثلًا أثناء طبقة القفل) حتى لا تُحدَّث المؤقت بالنقر فوقها.
  void setSuppressIdleBump(bool value) => _suppressIdleBump = value;

  void bumpActivity() {
    if (_suppressIdleBump) return;
    _lastActivityAt = DateTime.now();
  }

  /// بعد مزامنة الفريق قد يتغيّر معرّف المستخدم المحلي ليطابق السحابة.
  Future<void> refreshSessionFromDatabase() async {
    final s = _session;
    if (s == null || isGuestSession) return;
    final db = await _databaseService.database;
    final rows = await db.rawQuery(
      '''
      SELECT * FROM users
      WHERE organizationId = ?
        AND lower(trim(username)) = lower(trim(?))
        AND COALESCE(accountStatus, 'active') = 'active'
      LIMIT 1
      ''',
      [s.organizationId, s.username],
    );
    if (rows.isEmpty) return;
    final row = rows.first;
    final nextId = (row['id'] as String?)?.trim() ?? '';
    if (nextId.isEmpty || nextId == s.userId) return;
    _session = AppUserSession(
      organizationId: row['organizationId'] as String,
      branchId: row['branchId'] as String,
      userId: nextId,
      role: row['role'] as String,
      username: row['username'] as String,
    );
  }

  bool isIdleExceeded(Duration maxIdle) =>
      DateTime.now().difference(_lastActivityAt) > maxIdle;

  Future<void> bootstrapDefaults() async {
    final db = await _databaseService.database;
    final orgCount = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM organizations'),
        ) ??
        0;
    final hasOperationalData =
        await OperationalScopeResolver.databaseHasOperationalData(db);

    // حماية P0: لا تُنشئ مؤسسة جديدة إذا وُجدت مؤسسات أو بيانات تشغيلية.
    if (orgCount == 0 && !hasOperationalData) {
      await _insertDefaultOrganization(db);
    }

    await _databaseService.ensureGuestUserIfMissing();
    await OperationalScopeResolver.alignAllUsersWithEmptyOperationalScope(db);
    await repairBootstrapOwnerDisplayNames();
    await LicenseGate.ensureNewInstallTrialFile();
    await syncLicenseGate();
  }

  Future<void> _insertDefaultOrganization(Database db) async {
    final now = DateTime.now().toIso8601String();
    final orgId = _uuid.v4();
    final branchId = _uuid.v4();
    await db.transaction((txn) async {
      await txn.insert('organizations', {
        'id': orgId,
        'name': 'مؤسسة فلسطين',
        'createdAt': now,
      });
      await txn.insert('branches', {
        'id': branchId,
        'organizationId': orgId,
        'name': 'الفرع الرئيسي',
        'code': 'MAIN',
        'createdAt': now,
      });
    });
  }

  /// تسجيل الدخول بالبريد أو اسم المستخدم القديم (بدون حساسية لحالة الأحرف).
  ///
  /// عند تفعيل خادم التفعيل يُستدعى [RemoteSignupApi.healthCheck] أولاً
  /// (مثل مسار التسجيل عبر الويب) حتى تُجرى المزامنة لاحقاً عبر
  /// [syncLicenseGate] بعد نجاح الدخول المحلي.
  ///
  /// **دخول فريق العمل بدون إنترنت:** إذا فشل فحص الخادم بسبب انقطاع الشبكة
  /// (`RemoteSignupOfflineException`)، يتابع الدخول محلياً ضدّ قاعدة البيانات
  /// — فمستخدمو الفريق محفوظون أصلاً على هذا الجهاز مع bcrypt hash لكلمة
  /// السر. يُضبط [_lastLoginWasOffline] إلى `true` لإظهار تنبيه ملائم في
  /// الواجهة. أي خطأ آخر (مثل auth) يُرمى كما هو.
  Future<AppUserSession?> login(
    String emailOrUsername,
    String password, {
    String? expectedRole,
  }) async {
    _lastLoginWasOffline = false;
    if (RemoteSignupConfig.activationServerEnabled) {
      try {
        await RemoteSignupApi(
          baseUrl: RemoteSignupConfig.apiBaseUrl,
          sharedSecret: RemoteSignupConfig.sharedSecret,
        ).healthCheck();
      } on RemoteSignupOfflineException {
        // لا إنترنت: نتابع بالتحقّق المحلي.
        _lastLoginWasOffline = true;
      } on Object {
        // أي خطأ غير متوقع في فحص الصحة (DNS/SSL/Proxy/Firewall) — لا
        // يجب أن يمنع دخول الموظف محلياً ما دامت بياناته صحيحة على هذا الجهاز.
        _lastLoginWasOffline = true;
      }
    }
    final db = await _databaseService.database;
    final q = emailOrUsername.trim().toLowerCase();
    for (var attempt = 0; attempt < 2; attempt++) {
      final orgScope = await _loginOrganizationScope(db);
      final rows = orgScope != null && orgScope.isNotEmpty
          ? await db.rawQuery(
              '''
      SELECT * FROM users
      WHERE organizationId = ?
        AND (lower(trim(username)) = ? OR lower(trim(email)) = ?)
        AND (COALESCE(accountStatus, 'active') = 'active')
      LIMIT 1
      ''',
              [orgScope, q, q],
            )
          : await db.rawQuery(
              '''
      SELECT * FROM users
      WHERE (lower(trim(username)) = ? OR lower(trim(email)) = ?)
        AND (COALESCE(accountStatus, 'active') = 'active')
      LIMIT 1
      ''',
              [q, q],
            );
      if (rows.isEmpty) {
        if (attempt == 0) continue;
        return null;
      }
      final row = rows.first;
      final userRole = (row['role'] as String?)?.toLowerCase().trim() ?? '';
      if (userRole == 'guest') {
        return null;
      }
      if (expectedRole != null &&
          expectedRole.trim().isNotEmpty &&
          userRole != expectedRole.trim().toLowerCase()) {
        if (attempt == 0) continue;
        return null;
      }
      final storedPwd = row['password'] as String;
      final bool pwdOk;
      if (userRole == 'owner' && ownerLoginPasswordActive) {
        pwdOk = verifyOwnerLoginPassword(password);
      } else {
        pwdOk = PasswordCrypto.verifyPlainOrHash(password, storedPwd);
      }
      if (!pwdOk) {
        if (attempt == 0) continue;
        return null;
      }
      if (!await userMatchesActiveSubscriptionTenant(row)) {
        if (attempt == 0) continue;
        return null;
      }
      if (userRole != 'owner' || !ownerLoginPasswordActive) {
        if (!PasswordCrypto.looksLikeBcrypt(storedPwd)) {
          await db.update(
            'users',
            {'password': PasswordCrypto.hash(password)},
            where: 'id = ?',
            whereArgs: [row['id']],
          );
        }
      }
      _session = AppUserSession(
        organizationId: row['organizationId'] as String,
        branchId: row['branchId'] as String,
        userId: row['id'] as String,
        role: row['role'] as String,
        username: row['username'] as String,
      );
      bumpActivity();
      await reconcileSessionOperationalScope();
      await syncLicenseGate();
      if (RemoteSignupConfig.teamUsersCrossDeviceSyncEnabled) {
        try {
          await TeamUsersSyncService(accountingService: this)
              .pullToLocal(force: true);
        } on Object {
          /* لا يعطل الدخول المحلي */
        }
      }
      if (userRole == 'distributor' &&
          RemoteSignupConfig.activationServerEnabled) {
        await syncDistributorPortalAccounts();
      }
      return _session;
    }
    return null;
  }

  Future<String?> _loginOrganizationScope(Database db) async {
    final sessOrg = _session?.organizationId.trim() ?? '';
    if (sessOrg.isNotEmpty) return sessOrg;

    final vSess = VoucherSessionManager.instance.sessionNotifier.value;
    final ve = vSess?.email.trim().toLowerCase() ?? '';
    if (ve.contains('@')) {
      final owners = await db.rawQuery(
        '''
        SELECT organizationId FROM users
        WHERE lower(trim(role)) = 'owner'
          AND (
            lower(trim(COALESCE(NULLIF(email, ''), username))) = ?
            OR lower(trim(username)) = ?
          )
        ORDER BY createdAt ASC
        LIMIT 1
        ''',
        [ve, ve],
      );
      if (owners.isNotEmpty) {
        return (owners.first['organizationId'] as String?)?.trim();
      }
    }
    return null;
  }

  void _pushTeamUserToCloudFireAndForget(Map<String, Object?> row) {
    if (!RemoteSignupConfig.teamUsersCrossDeviceSyncEnabled) return;
    unawaited(() async {
      try {
        final org = (row['organizationId'] as String?)?.trim() ?? '';
        if (org.isEmpty) return;
        final creds = await resolveSubscriptionApiCredentialsForOrganization(org);
        if (creds == null) return;
        await TeamUsersSyncService(accountingService: this).pushUserRow(row);
      } on Object {
        /* اختياري — لا يؤثر على الإضافة المحلية */
      }
    }());
  }

  void _pushTeamUserDeleteToCloudFireAndForget(String userId) {
    if (!RemoteSignupConfig.teamUsersCrossDeviceSyncEnabled) return;
    unawaited(() async {
      try {
        await TeamUsersSyncService(accountingService: this)
            .pushDeleteUserId(userId);
      } on Object {
        /* اختياري */
      }
    }());
  }

  Future<AppUserSession> _finalizeSignupActivationAfterRemoteRedeem(
      RemoteRedeemSuccess redeem) async {
    final db = await _databaseService.database;
    final orgId = redeem.organizationId;
    final email = redeem.email.trim().toLowerCase();
    final branchId = await resolvePrimaryBranchId();
    if (branchId == null) {
      throw Exception('لا يوجد فرع.');
    }

    final existing = await db.rawQuery(
      '''
      SELECT * FROM users
      WHERE organizationId = ?
        AND (lower(trim(username)) = ? OR lower(trim(email)) = ?)
        AND COALESCE(accountStatus, 'active') = 'active'
        AND lower(trim(role)) <> 'guest'
      LIMIT 1
      ''',
      [orgId, email, email],
    );

    final now = DateTime.now().toIso8601String();
    late final String uid;
    late Map<String, Object?> row;

    if (existing.isEmpty) {
      uid = _uuid.v4();
      await db.insert('users', {
        'id': uid,
        'organizationId': orgId,
        'branchId': branchId,
        'fullName': redeem.fullName.trim(),
        'username': email,
        'email': email,
        'phone': redeem.phone,
        'dialCode': redeem.dialCode.trim().isEmpty ? '+970' : redeem.dialCode.trim(),
        'password': redeem.passwordHash,
        'role': 'owner',
        'accountStatus': 'active',
        'createdAt': now,
        'fromSignupRequestId': redeem.signupRequestId,
        'webActivationPending': 0,
      });
      final inserted = await db.query(
        'users',
        where: 'id = ?',
        whereArgs: [uid],
        limit: 1,
      );
      row = inserted.first;
    } else {
      row = existing.first;
      uid = row['id'] as String;
      await db.transaction((txn) async {
        await txn.rawUpdate(
          '''
          UPDATE users
          SET role = 'accountant'
          WHERE organizationId = ?
            AND lower(trim(role)) = 'owner'
            AND id != ?
          ''',
          [orgId, uid],
        );
        await txn.update(
          'users',
          {'role': 'owner'},
          where: 'id = ?',
          whereArgs: [uid],
        );
      });
      final refreshed = await db.query(
        'users',
        where: 'id = ?',
        whereArgs: [uid],
        limit: 1,
      );
      if (refreshed.isNotEmpty) row = refreshed.first;
    }

    _session = AppUserSession(
      organizationId: row['organizationId'] as String,
      branchId: row['branchId'] as String,
      userId: uid,
      role: 'owner',
      username: row['username'] as String,
    );
    bumpActivity();
    final identity = AccountingService.normalizeSubscriptionIdentity(
      row['email'] as String?,
      row['username'] as String,
    );
    final bindingPayload =
        await DeviceBinding.subscriptionBindingPayload(identity);
    final annualUntil = DateTime.now()
        .add(const Duration(days: LicenseGate.annualDays))
        .toIso8601String();
    await db.update(
      'users',
      {
        'subscriptionAnnualUntil': annualUntil,
        'subscriptionLegacyActivated': 0,
        'subscriptionDeviceBinding': bindingPayload,
        'webActivationPending': 0,
      },
      where: 'id = ?',
      whereArgs: [uid],
    );
    await syncLicenseGate();
    return _session as AppUserSession;
  }

  /// يبلّغ خادم التفعيل ببريد المشترك + المؤسسة + كود الجهاز لعرضهما تلقائياً في لوحة الويب.
  /// لا يُرمى استثناء عند فشل الشبكة.
  Future<void> pushDeviceLinkClaimToActivationServer(
    String email, {
    String? organizationId,
  }) async {
    if (!RemoteSignupConfig.activationServerEnabled) return;
    final e = email.trim().toLowerCase();
    if (!e.contains('@')) return;
    String orgId = (organizationId ?? '').trim();
    if (orgId.isEmpty) {
      final db = await _databaseService.database;
      final orgRows = await db.query('organizations', limit: 1);
      if (orgRows.isEmpty) return;
      orgId = orgRows.first['id'] as String;
    }
    final installId = await DeviceBinding.readInstallationId();
    final code = DeviceLinkCode.fromInstallationId(installId);
    if (code.isEmpty) return;
    try {
      await RemoteSignupApi(
        baseUrl: RemoteSignupConfig.apiBaseUrl,
        sharedSecret: RemoteSignupConfig.sharedSecret,
      ).claimDeviceLinkForWebAdmin(
        organizationId: orgId,
        email: e,
        deviceLinkCode: code,
      );
    } on Object {
      return;
    }
  }

  /// بعد ربط الجهاز من صفحة الويب: ندعوها بـ [rawKey] فارغ لمزامنة الاسترداد عبر [installationId].
  ///
  /// مع [activationServerEnabled]: يدعم أيضاً أكواد `MizaPos-…` القديمة إن وُجدت في الخادم.
  /// بدون خادم: جدول [signup_requests] المحلي مع [issuedActivationKey].
  ///
  /// يعيد `null` إذا لم يُطابق أي طلب معتمد.
  Future<AppUserSession?> trySessionFromSignupActivationKey(
      String rawKey) async {
    final trimmed = rawKey.trim();

    if (RemoteSignupConfig.activationServerEnabled) {
      if (trimmed.isEmpty) {
        return null;
      }
      final db = await _databaseService.database;
      final orgRows = await db.query('organizations', limit: 1);
      if (orgRows.isEmpty) {
        throw Exception('قاعدة البيانات غير مهيأة على هذا الجهاز.');
      }
      final localOrgId = orgRows.first['id'] as String;
      try {
        final installId = await DeviceBinding.readInstallationId();
        final redeem = await RemoteSignupApi(
          baseUrl: RemoteSignupConfig.apiBaseUrl,
          sharedSecret: RemoteSignupConfig.sharedSecret,
        ).redeemActivation(
          organizationId: localOrgId,
          activationCode: trimmed,
          installationId: installId,
        );
        if (redeem != null) {
          if (redeem.organizationId != localOrgId) {
            throw Exception(
              'كود التفعيل لا يخص هذه النسخة من البرنامج.',
            );
          }
          return _finalizeSignupActivationAfterRemoteRedeem(redeem);
        }
        return null;
      } on RemoteSignupOfflineException {
        rethrow;
      } on RemoteSignupApiException catch (e) {
        if (e.code == 'auth_err_activation_device_limit') {
          throw const LicenseException(LicenseGate.kCodeActivationDeviceLimit);
        }
        throw Exception(
          'تعذّر التفعيل عبر الخادم. تحقق من الخادم أو حاول لاحقاً.',
        );
      }
    }

    final compact =
        trimmed.replaceAll(RegExp(r'\s+'), '').toUpperCase();
    if (compact.isEmpty) return null;

    final db = await _databaseService.database;
    final signupRows = await db.rawQuery(
      '''
      SELECT id, organizationId, email, issuedActivationKey
      FROM signup_requests
      WHERE status = ?
        AND issuedActivationKey IS NOT NULL
        AND length(trim(issuedActivationKey)) > 0
      ORDER BY COALESCE(reviewedAt, requestedAt) DESC
      ''',
      ['approved'],
    );

    Map<String, Object?>? matchedSignup;
    for (final r in signupRows) {
      final issued = (r['issuedActivationKey'] as String?) ?? '';
      final norm =
          issued.trim().replaceAll(RegExp(r'\s+'), '').toUpperCase();
      if (norm.isNotEmpty && norm == compact) {
        matchedSignup = r;
        break;
      }
    }
    if (matchedSignup == null) return null;

    final signupRequestId = matchedSignup['id']! as String;
    final orgId = matchedSignup['organizationId']! as String;
    final email = (matchedSignup['email'] as String).trim().toLowerCase();

    final users = await db.rawQuery(
      '''
      SELECT * FROM users
      WHERE organizationId = ?
        AND (lower(trim(username)) = ? OR lower(trim(email)) = ?)
        AND COALESCE(accountStatus, 'active') = 'active'
        AND lower(trim(role)) <> 'guest'
      LIMIT 1
      ''',
      [orgId, email, email],
    );
    if (users.isEmpty) {
      throw Exception(
        'الكود مطابق لطلب مسجّل لكن لم يُعثر على حساب مرتبط. '
        'جرّب التحديث أو تواصل مع الدعم.',
      );
    }

    final row = users.first;
    final uid = row['id'] as String;
    _session = AppUserSession(
      organizationId: row['organizationId'] as String,
      branchId: row['branchId'] as String,
      userId: uid,
      role: row['role'] as String,
      username: row['username'] as String,
    );
    bumpActivity();
    final identity = AccountingService.normalizeSubscriptionIdentity(
      row['email'] as String?,
      row['username'] as String,
    );
    final bindingPayload =
        await DeviceBinding.subscriptionBindingPayload(identity);
    final annualUntil = DateTime.now()
        .add(const Duration(days: LicenseGate.annualDays))
        .toIso8601String();
    final installId = await DeviceBinding.readInstallationId();
    final nowIso = DateTime.now().toIso8601String();

    final existingSlot = await db.query(
      'activation_redeems',
      where: 'signupRequestId = ? AND installationId = ?',
      whereArgs: [signupRequestId, installId],
      limit: 1,
    );
    if (existingSlot.isNotEmpty) {
      await db.update(
        'users',
        {
          'subscriptionAnnualUntil': annualUntil,
          'subscriptionLegacyActivated': 0,
          'subscriptionDeviceBinding': bindingPayload,
          'webActivationPending': 0,
        },
        where: 'id = ?',
        whereArgs: [uid],
      );
      await syncLicenseGate();
      return _session;
    }

    final cntRows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM activation_redeems WHERE signupRequestId = ?',
      [signupRequestId],
    );
    final slotCount = (cntRows.first['c'] as int?) ?? 0;
    if (slotCount >= 2) {
      throw const LicenseException(LicenseGate.kCodeActivationDeviceLimit);
    }

    await db.transaction((txn) async {
      await txn.update(
        'users',
        {
          'subscriptionAnnualUntil': annualUntil,
          'subscriptionLegacyActivated': 0,
          'subscriptionDeviceBinding': bindingPayload,
          'webActivationPending': 0,
        },
        where: 'id = ?',
        whereArgs: [uid],
      );
      await txn.insert('activation_redeems', {
        'signupRequestId': signupRequestId,
        'installationId': installId,
        'redeemedAt': nowIso,
      });
      if (slotCount + 1 >= 2) {
        await txn.update(
          'signup_requests',
          {'issuedActivationKey': null},
          where: 'id = ?',
          whereArgs: [signupRequestId],
        );
      }
    });
    await syncLicenseGate();
    return _session;
  }

  /// جلسة تصفّح دون كلمة مرور (حدود أصناف/عمليات من [LicenseGate]).
  Future<void> enterGuestMode() async {
    final db = await _databaseService.database;
    await _databaseService.ensureGuestUserIfMissing();
    final scope = await _resolveGuestOperationalScope(db);
    final row = scope?['row'] as Map<String, Object?>?;
    if (row == null) {
      throw Exception('مستخدم الزائر غير جاهز.');
    }
    _session = AppUserSession(
      organizationId: row['organizationId'] as String,
      branchId: row['branchId'] as String,
      userId: row['id'] as String,
      role: row['role'] as String,
      username: row['username'] as String,
    );
    bumpActivity();
    // #region agent log
    DebugSessionLog.write(
      location: 'accounting_service.dart:enterGuestMode',
      message: 'guest session scope',
      hypothesisId: 'H1-org-scope',
      data: {
        'organizationId': _session!.organizationId,
        'branchId': _session!.branchId,
        'repaired': scope?['repaired'] == true,
        'productCount': scope?['productCount'],
      },
    );
    // #endregion
  }

  /// يُعيد نطاق الزائر إلى مؤسسة/فرع فيها بيانات تشغيلية إن كان نطاقه الحالي فارغاً.
  Future<Map<String, Object?>?> _resolveGuestOperationalScope(Database db) async {
    const guestId = LicenseGate.guestUserId;
    final before = await db.query(
      'users',
      where: 'id = ?',
      whereArgs: [guestId],
      limit: 1,
    );
    if (before.isEmpty) return null;
    final beforeOrg = (before.first['organizationId'] as String?)?.trim() ?? '';
    final beforeBranch = (before.first['branchId'] as String?)?.trim() ?? '';

    final repaired = await OperationalScopeResolver.alignUserScopeIfEmpty(
      db: db,
      userId: guestId,
    );

    final rows = await db.query(
      'users',
      where: 'id = ?',
      whereArgs: [guestId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final guest = Map<String, Object?>.from(rows.first);
    final orgId = (guest['organizationId'] as String?)?.trim() ?? '';
    final branchId = (guest['branchId'] as String?)?.trim() ?? '';
    final scope = orgId.isNotEmpty && branchId.isNotEmpty
        ? await OperationalScopeResolver.scopeForOrgBranch(db, orgId, branchId)
        : null;

    return {
      'row': guest,
      'repaired': repaired ||
          beforeOrg != orgId ||
          beforeBranch != branchId,
      'productCount': scope?.productCount ?? 0,
      'customerCount': scope?.customerCount ?? 0,
      'invoiceCount': scope?.invoiceCount ?? 0,
    };
  }

  void clearSession() {
    _session = null;
  }

  bool get isGuestSession => _session?.role == 'guest';

  static bool _isRealSubscriptionEmail(String email) {
    final e = email.trim().toLowerCase();
    if (!e.contains('@')) return false;
    if (e.endsWith('@legacy.mizapos') || e.endsWith('@local.mizapos')) {
      return false;
    }
    return true;
  }

  /// بريد اشتراك الجهاز/الجلسة الحالية — لا يختلط بحسابات أخرى على نفس SQLite.
  Future<String?> activeSubscriptionEmailForSync({
    String? localOrganizationId,
  }) async {
    final localOrg =
        localOrganizationId?.trim() ?? _session?.organizationId.trim() ?? '';
    final db = await _databaseService.database;

    for (final raw in <String?>[
      VoucherSessionManager.instance.sessionNotifier.value?.email,
      VoucherSessionManager.instance.statusNotifier.value.email,
    ]) {
      final e = (raw ?? '').trim().toLowerCase();
      if (!_isRealSubscriptionEmail(e)) continue;
      if (localOrg.isEmpty ||
          _voucherSubscriptionActiveOnDevice ||
          await localOrgBelongsToSubscriptionEmail(db, localOrg, e)) {
        return e;
      }
    }

    final s = _session;
    if (s == null || isGuestSession) return null;
    final org = localOrg.isNotEmpty ? localOrg : s.organizationId;

    if (s.role.trim().toLowerCase() == 'owner') {
      final rows = await db.query(
        'users',
        columns: ['email', 'username'],
        where: 'id = ? AND organizationId = ?',
        whereArgs: [s.userId, org],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      final id = normalizeSubscriptionIdentity(
        rows.first['email'] as String?,
        (rows.first['username'] as String?) ?? '',
      );
      if (_isRealSubscriptionEmail(id) &&
          await localOrgBelongsToSubscriptionEmail(db, org, id)) {
        return id;
      }
      return null;
    }

    final rows = await db.query(
      'users',
      columns: ['teamSubscriptionEmail'],
      where: 'id = ? AND organizationId = ?',
      whereArgs: [s.userId, org],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final tagged =
        (rows.first['teamSubscriptionEmail'] as String?)?.trim().toLowerCase() ??
            '';
    if (_isRealSubscriptionEmail(tagged)) return tagged;
    return null;
  }

  Future<bool> userMatchesActiveSubscriptionTenant(
    Map<String, Object?> userRow,
  ) async {
    final role = (userRow['role'] as String?)?.trim().toLowerCase() ?? '';
    if (role == 'owner' || role == 'guest') return true;
    final org = (userRow['organizationId'] as String?)?.trim() ?? '';
    final tenant = await activeSubscriptionEmailForSync(
      localOrganizationId: org,
    );
    if (tenant == null || !tenant.contains('@')) return true;
    final tagged =
        (userRow['teamSubscriptionEmail'] as String?)?.trim().toLowerCase() ??
            '';
    return tagged == tenant;
  }

  /// بريد الاشتراك/التفعيل المعتمد للمؤسسة — لا يعتمد على «أول مالك» في القائمة.
  ///
  /// لا يُعاد بريد قسيمة نشطة على الجهاز إلا إذا كانت مربوطة بهذه المؤسسة المحلية.
  Future<bool> localOrgBelongsToSubscriptionEmail(
    Database db,
    String localOrganizationId,
    String subscriptionEmail,
  ) async {
    final org = localOrganizationId.trim();
    final em = subscriptionEmail.trim().toLowerCase();
    if (org.isEmpty || !em.contains('@')) return false;

    final owner = await db.rawQuery(
      '''
      SELECT 1 FROM users
      WHERE organizationId = ?
        AND lower(trim(role)) = 'owner'
        AND (
          lower(trim(COALESCE(NULLIF(email, ''), username))) = ?
          OR lower(trim(username)) = ?
        )
      LIMIT 1
      ''',
      [org, em, em],
    );
    if (owner.isNotEmpty) return true;

    final signup = await db.rawQuery(
      '''
      SELECT 1 FROM signup_requests
      WHERE organizationId = ?
        AND lower(trim(email)) = ?
      LIMIT 1
      ''',
      [org, em],
    );
    return signup.isNotEmpty;
  }

  Future<String?> cloudOrganizationIdForSubscriptionEmail(
    Database db,
    String subscriptionEmail,
    String localOrganizationId,
  ) async {
    final em = subscriptionEmail.trim().toLowerCase();
    final localOrg = localOrganizationId.trim();
    if (em.isEmpty || localOrg.isEmpty) return null;

    final vSess = VoucherSessionManager.instance.sessionNotifier.value;
    if (vSess != null &&
        vSess.email.trim().toLowerCase() == em &&
        vSess.organizationId.trim().isNotEmpty) {
      return vSess.organizationId.trim();
    }

    final vStatus = VoucherSessionManager.instance.statusNotifier.value;
    if (vStatus.email.trim().toLowerCase() == em &&
        vStatus.organizationId.trim().isNotEmpty) {
      return vStatus.organizationId.trim();
    }

    final scopedSignup = await db.rawQuery(
      '''
      SELECT organizationId FROM signup_requests
      WHERE organizationId = ? AND lower(trim(email)) = ?
      ORDER BY requestedAt DESC
      LIMIT 1
      ''',
      [localOrg, em],
    );
    if (scopedSignup.isNotEmpty) {
      final oid = (scopedSignup.first['organizationId'] as String?)?.trim() ?? '';
      if (oid.isNotEmpty) return oid;
    }

    return localOrg;
  }

  /// بريد ومعرّف السحابة لاشتراك مؤسسة محددة — دون اختلاط قسائم أخرى على الجهاز.
  Future<({String organizationId, String email})?>
      resolveSubscriptionApiCredentialsForOrganization(
    String localOrganizationId,
  ) async {
    final localOrg = localOrganizationId.trim();
    if (localOrg.isEmpty) return null;
    final email = await activeSubscriptionEmailForSync(
      localOrganizationId: localOrg,
    );
    if (email == null || !_isRealSubscriptionEmail(email)) return null;
    final db = await _databaseService.database;
    if (!await localOrgBelongsToSubscriptionEmail(db, localOrg, email)) {
      return null;
    }
    final cloudOrg =
        await cloudOrganizationIdForSubscriptionEmail(db, email, localOrg);
    if (cloudOrg == null || cloudOrg.isEmpty) return null;
    return (organizationId: cloudOrg, email: email);
  }

  Future<String?> resolveCanonicalSubscriptionEmailForOrg(
    Database db,
    String organizationId,
  ) async {
    final voucherEmail =
        VoucherSessionManager.instance.sessionNotifier.value?.email
            .trim()
            .toLowerCase() ??
            '';
    if (_isRealSubscriptionEmail(voucherEmail) &&
        await localOrgBelongsToSubscriptionEmail(
          db,
          organizationId,
          voucherEmail,
        )) {
      return voucherEmail;
    }

    final vStatus = VoucherSessionManager.instance.statusNotifier.value;
    final statusEmail = vStatus.email.trim().toLowerCase();
    if (_isRealSubscriptionEmail(statusEmail) &&
        await localOrgBelongsToSubscriptionEmail(
          db,
          organizationId,
          statusEmail,
        )) {
      return statusEmail;
    }

    final sess = _session;
    if (sess != null &&
        sess.organizationId.trim() == organizationId.trim() &&
        sess.role.trim().toLowerCase() == 'owner') {
      final current = await db.query(
        'users',
        columns: ['email', 'username'],
        where: 'id = ? AND organizationId = ?',
        whereArgs: [sess.userId, organizationId],
        limit: 1,
      );
      if (current.isNotEmpty) {
        final id = normalizeSubscriptionIdentity(
          current.first['email'] as String?,
          (current.first['username'] as String?) ?? '',
        );
        if (_isRealSubscriptionEmail(id)) return id;
      }
    }

    final now = DateTime.now();
    final owners = await db.query(
      'users',
      columns: [
        'email',
        'username',
        'subscriptionAnnualUntil',
        'subscriptionLegacyActivated',
      ],
      where: 'organizationId = ? AND lower(trim(role)) = ?',
      whereArgs: [organizationId, 'owner'],
      orderBy: 'createdAt ASC',
    );
    for (final row in owners) {
      final au = (row['subscriptionAnnualUntil'] as String?)?.trim();
      final end =
          au != null && au.isNotEmpty ? DateTime.tryParse(au) : null;
      final legacyRaw = row['subscriptionLegacyActivated'];
      final legacy = legacyRaw is bool
          ? legacyRaw
          : (legacyRaw is int
              ? legacyRaw != 0
              : (legacyRaw is num ? legacyRaw.toInt() != 0 : false));
      final annualActive = end != null && now.isBefore(end);
      final legacyActive = legacy && end == null;
      if (!annualActive && !legacyActive) continue;
      final id = normalizeSubscriptionIdentity(
        row['email'] as String?,
        (row['username'] as String?) ?? '',
      );
      if (_isRealSubscriptionEmail(id)) return id;
    }

    for (final status in ['approved', 'pending']) {
      final su = await db.query(
        'signup_requests',
        columns: ['email'],
        where: 'organizationId = ? AND status = ?',
        whereArgs: [organizationId, status],
        orderBy: 'COALESCE(reviewedAt, requestedAt) DESC',
        limit: 1,
      );
      if (su.isEmpty) continue;
      final em = (su.first['email'] as String?)?.trim().toLowerCase() ?? '';
      if (_isRealSubscriptionEmail(em)) return em;
    }

    final anySu = await db.query(
      'signup_requests',
      columns: ['email'],
      where: 'organizationId = ?',
      whereArgs: [organizationId],
      orderBy: 'COALESCE(reviewedAt, requestedAt) DESC',
      limit: 1,
    );
    if (anySu.isNotEmpty) {
      final em = (anySu.first['email'] as String?)?.trim().toLowerCase() ?? '';
      if (_isRealSubscriptionEmail(em)) return em;
    }

    if (owners.isNotEmpty) {
      final id = normalizeSubscriptionIdentity(
        owners.first['email'] as String?,
        (owners.first['username'] as String?) ?? '',
      );
      if (_isRealSubscriptionEmail(id)) return id;
    }

    return null;
  }

  Future<void> _demoteOtherOwners(
    Database db,
    String organizationId,
    String keepOwnerUserId,
  ) async {
    await db.rawUpdate(
      '''
      UPDATE users
      SET role = 'accountant'
      WHERE organizationId = ?
        AND lower(trim(role)) = 'owner'
        AND id != ?
      ''',
      [organizationId, keepOwnerUserId],
    );
  }

  /// يجعل صاحب بريد الاشتراك/التفعيل هو المالك الوحيد في المؤسسة.
  Future<bool> alignOwnerRoleWithSubscriptionEmail(
    Database db,
    String organizationId, {
    String? subscriptionEmail,
  }) async {
    var email = subscriptionEmail?.trim().toLowerCase();
    email ??=
        await resolveCanonicalSubscriptionEmailForOrg(db, organizationId);
    if (email == null || !_isRealSubscriptionEmail(email)) {
      return false;
    }

    final users = await db.rawQuery(
      '''
      SELECT id, role, username, branchId
      FROM users
      WHERE organizationId = ?
        AND (
          lower(trim(COALESCE(NULLIF(email, ''), username))) = ?
          OR lower(trim(username)) = ?
        )
        AND COALESCE(accountStatus, 'active') = 'active'
        AND lower(trim(role)) <> 'guest'
      LIMIT 1
      ''',
      [organizationId, email, email],
    );
    if (users.isEmpty) return false;

    final target = users.first;
    final targetId = target['id']! as String;
    final wasOwner =
        (target['role'] as String?)?.trim().toLowerCase() == 'owner';

    if (!wasOwner) {
      await db.transaction((txn) async {
        await txn.rawUpdate(
          '''
          UPDATE users
          SET role = 'accountant'
          WHERE organizationId = ?
            AND lower(trim(role)) = 'owner'
            AND id != ?
          ''',
          [organizationId, targetId],
        );
        await txn.update(
          'users',
          {'role': 'owner'},
          where: 'id = ?',
          whereArgs: [targetId],
        );
      });
    } else {
      await _demoteOtherOwners(db, organizationId, targetId);
    }

    final sess = _session;
    if (sess != null &&
        sess.userId == targetId &&
        sess.organizationId == organizationId &&
        sess.role.trim().toLowerCase() != 'owner') {
      _session = AppUserSession(
        organizationId: sess.organizationId,
        branchId: sess.branchId,
        userId: sess.userId,
        role: 'owner',
        username: sess.username,
      );
    }

    if (!wasOwner) {
      final promoted = await db.query(
        'users',
        where: 'id = ?',
        whereArgs: [targetId],
        limit: 1,
      );
      if (promoted.isNotEmpty &&
          TeamUsersSyncService.isEligibleTeamUserRow(promoted.first)) {
        _pushTeamUserToCloudFireAndForget(promoted.first);
      }
      final demoted = await db.query(
        'users',
        where: 'organizationId = ? AND lower(trim(role)) = ?',
        whereArgs: [organizationId, 'accountant'],
      );
      for (final row in demoted) {
        if (TeamUsersSyncService.isEligibleTeamUserRow(row)) {
          _pushTeamUserToCloudFireAndForget(row);
        }
      }
    }

    return true;
  }

  Future<void> _assertOwnerRoleMatchesSubscriptionEmail(
    Database db,
    String organizationId,
    String email,
    String username,
  ) async {
    final canonical =
        await resolveCanonicalSubscriptionEmailForOrg(db, organizationId);
    if (canonical == null) return;
    final candidate = normalizeSubscriptionIdentity(email, username);
    if (candidate != canonical) {
      throw Exception(
        'دور المالك مربوط ببريد الاشتراك/التفعيل ($canonical) فقط.',
      );
    }
  }

  /// بريد مطابقة [license-pull] على الخادم — يفضّل بريد الاشتراك/التفعيل المعتمد.
  Future<String?> _resolveLicensePullEmail(
    Database db,
    String organizationId,
    Map<String, Object?> subscriptionIdentityRow,
  ) async {
    final canonical =
        await resolveCanonicalSubscriptionEmailForOrg(db, organizationId);
    if (canonical != null && _isRealSubscriptionEmail(canonical)) {
      return canonical;
    }

    var id = AccountingService.normalizeSubscriptionIdentity(
      subscriptionIdentityRow['email'] as String?,
      (subscriptionIdentityRow['username'] as String?) ?? '',
    );
    if (_isRealSubscriptionEmail(id)) return id;

    final su = await db.query(
      'signup_requests',
      columns: ['email'],
      where: 'organizationId = ?',
      whereArgs: [organizationId],
      orderBy: 'createdAt DESC',
      limit: 1,
    );
    if (su.isEmpty) return null;
    final em = (su.first['email'] as String?)?.trim().toLowerCase() ?? '';
    return _isRealSubscriptionEmail(em) ? em : null;
  }

  Future<String> currentUserDisplayName() async {
    final s = _mustSession();
    final db = await _databaseService.database;
    final rows = await db.query(
      'users',
      columns: ['fullName', 'username', 'role'],
      where: 'id = ?',
      whereArgs: [s.userId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return resolveStaffDisplayName(
        username: s.username,
        role: s.role,
      );
    }
    final row = rows.first;
    return resolveStaffDisplayName(
      fullName: row['fullName'] as String?,
      username: row['username'] as String?,
      role: row['role'] as String?,
    );
  }

  static const bootstrapOwnerUsername = 'owner';
  static const bootstrapOwnerDisplayName = 'المدير';

  static bool isBootstrapOwnerAccount({
    String? username,
    String? role,
  }) {
    return role?.trim().toLowerCase() == 'owner' &&
        username?.trim().toLowerCase() == bootstrapOwnerUsername;
  }

  static String resolveStaffDisplayName({
    String? fullName,
    String? username,
    String? role,
    String ownerFallback = bootstrapOwnerDisplayName,
  }) {
    final fn = fullName?.trim() ?? '';
    if (fn.isNotEmpty) return fn;
    final un = username?.trim() ?? '';
    if (isBootstrapOwnerAccount(username: un, role: role)) {
      return ownerFallback.trim().isNotEmpty
          ? ownerFallback.trim()
          : bootstrapOwnerDisplayName;
    }
    if (un.isNotEmpty) return un;
    return '';
  }

  Future<void> repairBootstrapOwnerDisplayNames() async {
    final db = await _databaseService.database;
    await db.rawUpdate(
      '''
      UPDATE users
      SET fullName = ?
      WHERE lower(trim(role)) = 'owner'
        AND lower(trim(username)) = ?
        AND (fullName IS NULL OR length(trim(fullName)) = 0)
      ''',
      [bootstrapOwnerDisplayName, bootstrapOwnerUsername],
    );
  }

  /// بريد الاشتراك لاستدعاءات API الخادم (طلبات ميدان، مزامنة ترخيص…).
  ///
  /// يطابق بريد القسيمة/التفعيل — وليس بريد موظف أو موزّع عشوائي.
  Future<String?> remoteApiSubscriptionEmail() async {
    final s = _session;
    if (s != null) {
      final tenant = await activeSubscriptionEmailForSync(
        localOrganizationId: s.organizationId,
      );
      if (tenant != null) return tenant;
      if (isGuestSession) return null;
    }

    final vSess = VoucherSessionManager.instance.sessionNotifier.value;
    if (vSess != null) {
      final ve = vSess.email.trim().toLowerCase();
      if (_isRealSubscriptionEmail(ve)) return ve;
    }

    final vStatus = VoucherSessionManager.instance.statusNotifier.value;
    final statusEmail = vStatus.email.trim().toLowerCase();
    if (_isRealSubscriptionEmail(statusEmail)) return statusEmail;

    if (s == null) return null;
    final db = await _databaseService.database;

    final canonical =
        await resolveCanonicalSubscriptionEmailForOrg(db, s.organizationId);
    if (canonical != null) return canonical;

    final rows = await db.query(
      'users',
      columns: ['email', 'username'],
      where: 'id = ?',
      whereArgs: [s.userId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _resolveLicensePullEmail(db, s.organizationId, rows.first);
  }

  /// معرّف المؤسسة على خادم الاشتراك (من القسيمة/التسجيل).
  ///
  /// على جهاز ثانٍ قد يختلف عن [AppUserSession.organizationId] المحلي
  /// الذي تُخزَّن تحته بيانات SQLite — لكنه مطلوب لطلبات API السحابية.
  Future<String?> remoteApiSubscriptionOrganizationId() async {
    final s = _session;
    if (s != null) {
      final scoped = await resolveSubscriptionApiCredentialsForOrganization(
        s.organizationId,
      );
      if (scoped != null) return scoped.organizationId;
      if (isGuestSession) return null;
    }

    final voucherSess = VoucherSessionManager.instance.sessionNotifier.value;
    final fromVoucherSess = voucherSess?.organizationId.trim() ?? '';
    if (fromVoucherSess.isNotEmpty) return fromVoucherSess;

    final vStatus = VoucherSessionManager.instance.statusNotifier.value;
    final fromStatus = vStatus.organizationId.trim();
    if (fromStatus.isNotEmpty) return fromStatus;

    final email = await remoteApiSubscriptionEmail();
    if (email != null && email.contains('@')) {
      final db = await _databaseService.database;
      final localOrg = s?.organizationId.trim() ?? '';
      if (localOrg.isNotEmpty) {
        final cloud = await cloudOrganizationIdForSubscriptionEmail(
          db,
          email,
          localOrg,
        );
        if (cloud != null && cloud.isNotEmpty) return cloud;
      }
      final su = await db.rawQuery(
        '''
        SELECT organizationId FROM signup_requests
        WHERE lower(trim(email)) = ?
        ORDER BY requestedAt DESC
        LIMIT 1
        ''',
        [email.trim().toLowerCase()],
      );
      if (su.isNotEmpty) {
        final oid = (su.first['organizationId'] as String?)?.trim() ?? '';
        if (oid.isNotEmpty) return oid;
      }
    }

    final local = s?.organizationId.trim() ?? '';
    return local.isEmpty ? null : local;
  }

  /// يطبّق من خادم التفعيل تجميداً أو تمديداً إدارياً على صفوف [users] المطابقة لهوية الاشتراك.
  /// يُعاد `true` فقط عند استلام استجابة ناجحة من [pullLicensePolicy] (لمزامنة التقرير دون إعادة إحياء اشتراك محذوف).
  Future<bool> _pullRemoteSubscriptionIntoLocal(
    Database db,
    AppUserSession s,
    Map<String, Object?> subscriptionIdentityRow,
  ) async {
    if (!RemoteSignupConfig.activationServerEnabled) return false;
    final idEmail = await _resolveLicensePullEmail(
      db,
      s.organizationId,
      subscriptionIdentityRow,
    );
    if (idEmail == null || !idEmail.contains('@')) return false;
    final remoteOrgId =
        (await remoteApiSubscriptionOrganizationId())?.trim() ?? '';
    final pullOrgId =
        remoteOrgId.isNotEmpty ? remoteOrgId : s.organizationId;
    try {
      final api = RemoteSignupApi(
        baseUrl: RemoteSignupConfig.apiBaseUrl,
        sharedSecret: RemoteSignupConfig.sharedSecret,
      );
      final installId = await DeviceBinding.readInstallationId();
      final pull = await api.pullLicensePolicy(
        organizationId: pullOrgId,
        email: idEmail,
        installationId: installId,
      );
      if (pull == null) return false;
      await _applyBroadcastNoticeFromPull(pull);
      await _persistDistributorCloudFromPull(db, s.organizationId, pull);
      // لوحة التفعيل حذفت اللقطة وطلب التسجيل بالكامل — امسح المرآة المحلية لطلبات التسجيل وارتباط المستخدمين.
      final hasLicSnap =
          pull[LicensePullResponseKeys.hasLicenseSnapshot];
      final hasSignupSrv = pull[LicensePullResponseKeys.hasSignupRequest];
      if (hasLicSnap == false && hasSignupSrv == false) {
        final pendingIds = await db.query(
          'signup_requests',
          columns: ['id'],
          where: 'organizationId = ? AND lower(trim(email)) = ?',
          whereArgs: <Object?>[s.organizationId, idEmail],
        );
        await db.delete(
          'signup_requests',
          where: 'organizationId = ? AND lower(trim(email)) = ?',
          whereArgs: <Object?>[s.organizationId, idEmail],
        );
        for (final pr in pendingIds) {
          final sid = pr['id'] as String?;
          if (sid == null || sid.isEmpty) continue;
          await db.update(
            'users',
            <String, Object?>{'fromSignupRequestId': null},
            where: 'organizationId = ? AND fromSignupRequestId = ?',
            whereArgs: <Object?>[s.organizationId, sid],
          );
        }
      }
      final suspended = activationApiReadBool(
        pull,
        LicensePullResponseKeys.accessSuspended,
      );
      final subIso = activationApiReadIsoString(
        pull,
        LicensePullResponseKeys.subscriptionAnnualUntil,
      );
      final legacyPull = activationApiReadBool(
        pull,
        LicensePullResponseKeys.legacyActivated,
      );
      const whereClause =
          'organizationId = ? AND lower(trim(COALESCE(NULLIF(email, \'\'), username))) = ?';
      final args = <Object?>[s.organizationId, idEmail];
      if (suspended) {
        await db.update(
          'users',
          <String, Object?>{
            'subscriptionAnnualUntil': null,
            'subscriptionLegacyActivated': 0,
            'subscriptionAccessSuspended': 1,
          },
          where: whereClause,
          whereArgs: args,
        );
        return true;
      }
      if (legacyPull) {
        await db.update(
          'users',
          <String, Object?>{
            'subscriptionAnnualUntil': null,
            'subscriptionLegacyActivated': 1,
            'webActivationPending': 0,
            'subscriptionAccessSuspended': 0,
          },
          where: whereClause,
          whereArgs: args,
        );
        return true;
      }
      final parsed = subIso != null && subIso.trim().isNotEmpty
          ? DateTime.tryParse(subIso.trim())
          : null;
      if (parsed != null) {
        await db.update(
          'users',
          <String, Object?>{
            'subscriptionAnnualUntil': parsed.toIso8601String(),
            'subscriptionLegacyActivated': 0,
            'webActivationPending': 0,
            'subscriptionAccessSuspended': 0,
          },
          where: whereClause,
          whereArgs: args,
        );
      } else {
        // الخادم لا يعيد تاريخاً فعّالاً (حذف لقطة، أو لا يوجد تمديد) — امسح المرآة المحلية لتطابق لوحة التفعيل.
        await db.update(
          'users',
          <String, Object?>{
            'subscriptionAnnualUntil': null,
            'subscriptionLegacyActivated': 0,
            'subscriptionAccessSuspended': 0,
          },
          where: whereClause,
          whereArgs: args,
        );
      }
      return true;
    } on Object {
      return false;
    }
  }

  static DateTime? parseLicenseDateTime(String? raw) {
    final t = raw?.trim() ?? '';
    if (t.isEmpty) return null;
    var parsed = DateTime.tryParse(t);
    if (parsed != null) return parsed;
    if (t.contains(' ') && !t.contains('T')) {
      parsed = DateTime.tryParse(t.replaceFirst(' ', 'T'));
      if (parsed != null) return parsed;
    }
    return null;
  }

  Future<void> _persistDistributorCloudFromPull(
    Database db,
    String organizationId,
    Map<String, dynamic> pull,
  ) async {
    final distUntilIso = activationApiReadIsoString(
      pull,
      LicensePullResponseKeys.distributorCloudUntil,
    );
    final maxSeats = activationApiReadNullableInt(
      pull,
      LicensePullResponseKeys.maxDistributorSeats,
    );
    final usedSeats =
        activationApiReadNullableInt(pull, LicensePullResponseKeys.usedDistributorSeats) ??
            0;
    await db.update(
      'users',
      <String, Object?>{
        'distributorCloudUntil': distUntilIso,
        'maxDistributorSeats': maxSeats,
        'usedDistributorSeats': usedSeats,
      },
      where: 'organizationId = ?',
      whereArgs: [organizationId],
    );
    _applyDistributorCloudFromPullMap(pull);
  }

  void _applyDistributorCloudFromPullMap(Map<String, dynamic> pull) {
    final untilRaw = activationApiReadIsoString(
      pull,
      LicensePullResponseKeys.distributorCloudUntil,
    );
    final until = parseLicenseDateTime(untilRaw);
    final active = activationApiReadBool(
      pull,
      LicensePullResponseKeys.distributorCloudActive,
    );
    final maxSeats = activationApiReadNullableInt(
      pull,
      LicensePullResponseKeys.maxDistributorSeats,
    );
    final usedSeats =
        activationApiReadNullableInt(pull, LicensePullResponseKeys.usedDistributorSeats) ??
            0;
    if (until != null || active) {
      licenseGate.applyDistributorCloud(
        cloudUntil: until ??
            (active ? DateTime.now().add(const Duration(days: 365)) : null),
        maxSeats: maxSeats,
        usedSeats: usedSeats,
      );
    }
  }

  void _applyDistributorCloudFromUserRow(Map<String, Object?> row) {
    final until = parseLicenseDateTime(
      (row['distributorCloudUntil'] as String?)?.trim(),
    );
    final maxRaw = row['maxDistributorSeats'];
    int? maxSeats;
    if (maxRaw != null) {
      maxSeats = maxRaw is int ? maxRaw : int.tryParse(maxRaw.toString());
    }
    final usedRaw = row['usedDistributorSeats'];
    var usedSeats = 0;
    if (usedRaw is int) {
      usedSeats = usedRaw;
    } else if (usedRaw != null) {
      usedSeats = int.tryParse(usedRaw.toString()) ?? 0;
    }
    licenseGate.applyDistributorCloud(
      cloudUntil: until,
      maxSeats: maxSeats,
      usedSeats: usedSeats,
    );
  }

  /// يقرأ حقول سحابة الموزّعين من أي صف في المؤسسة (بعد سحب الترخيص تُنسَخ لكل المستخدمين).
  Future<void> _applyOrgDistributorCloudFromDb(
    Database db,
    String organizationId,
  ) async {
    const cols = [
      'distributorCloudUntil',
      'maxDistributorSeats',
      'usedDistributorSeats',
    ];
    Map<String, Object?>? pick;
    final owners = await db.query(
      'users',
      columns: cols,
      where: 'organizationId = ? AND lower(trim(role)) = ?',
      whereArgs: [organizationId, 'owner'],
      orderBy: 'createdAt ASC',
      limit: 1,
    );
    if (owners.isNotEmpty) {
      pick = owners.first;
    }
    final untilOnPick = (pick?['distributorCloudUntil'] as String?)?.trim() ?? '';
    if (untilOnPick.isEmpty) {
      final withUntil = await db.rawQuery(
        '''
        SELECT distributorCloudUntil, maxDistributorSeats, usedDistributorSeats
        FROM users
        WHERE organizationId = ?
          AND distributorCloudUntil IS NOT NULL
          AND length(trim(distributorCloudUntil)) > 0
        ORDER BY distributorCloudUntil DESC
        LIMIT 1
        ''',
        [organizationId],
      );
      if (withUntil.isNotEmpty) {
        pick = withUntil.first;
      }
    }
    if (pick != null) {
      _applyDistributorCloudFromUserRow(pick);
    }
  }

  /// محاولة سحب سحابة الموزّعين من الخادم (بريد المالك + معرّف المؤسسة السحابي).
  Future<bool> _pullDistributorCloudLicenseIfNeeded(
    Database db,
    AppUserSession s,
  ) async {
    if (!RemoteSignupConfig.activationServerEnabled) return false;
    if (hasDistributorCloudAccess) return true;
    final pullEmail =
        await resolveCanonicalSubscriptionEmailForOrg(db, s.organizationId);
    if (pullEmail == null || !_isRealSubscriptionEmail(pullEmail)) {
      return false;
    }
    return _pullRemoteSubscriptionIntoLocal(
      db,
      s,
      <String, Object?>{
        'email': pullEmail,
        'username': pullEmail,
      },
    );
  }

  /// مزامنة صريحة لسحابة الموزّعين — للموزّع على الجوال بعد تفعيل لوحة الويب.
  Future<bool> refreshDistributorCloudLicense() async {
    final s = _session;
    if (s == null || isGuestSession) return false;
    final db = await _databaseService.database;
    await alignOwnerRoleWithSubscriptionEmail(db, s.organizationId);
    await _pullDistributorCloudLicenseIfNeeded(db, s);
    await _applyOrgDistributorCloudFromDb(db, s.organizationId);
    await _refreshSessionDistributorCloudFlag();
    return hasDistributorCloudAccess;
  }

  /// مزامنة حسابات الموزّعين وترخيص السحابة من بوابة دخول الموزّع على الجوال.
  Future<bool> syncDistributorPortalAccounts() async {
    final s = _session;
    if (s == null) return false;
    var teamPulled = false;
    var licenseOk = hasDistributorCloudAccess;

    if (RemoteSignupConfig.teamUsersCrossDeviceSyncEnabled) {
      try {
        teamPulled = await TeamUsersSyncService(accountingService: this)
            .pullToLocal(force: true);
        await refreshSessionFromDatabase();
      } on Object {
        /* لا يوقف بقية المزامنة */
      }
    }

    try {
      await syncLicenseGate();
      licenseOk = hasDistributorCloudAccess;
    } on Object {
      /* */
    }

    final db = await _databaseService.database;
    try {
      if (!licenseOk) {
        final pulled = await _pullDistributorCloudLicenseIfNeeded(db, s);
        if (pulled) licenseOk = true;
      }
      await _applyOrgDistributorCloudFromDb(db, s.organizationId);
      licenseOk = hasDistributorCloudAccess;
    } on Object {
      /* */
    }

    var truckPulled = false;
    if (RemoteSignupConfig.activationServerEnabled) {
      try {
        truckPulled = await FieldTruckStockSyncService(accountingService: this)
            .pullToLocalCache(force: true);
      } on Object {
        /* */
      }
    }

    return teamPulled || licenseOk || truckPulled;
  }

  /// سحابة الموزّعين ($50/سنة) — منفصلة عن قسيمة POS (1 حاسوب + 1 جوال).
  bool get hasDistributorCloudAccess =>
      licenseGate.hasDistributorCloudAccess(DateTime.now());

  /// تجربة منظومة الموزّعين بدون اشتراك السحابة.
  static const int distributorTrialProductLimit = 5;
  static const int distributorTrialExpenseLimit = 3;

  bool get isDistributorFieldTrialMode => !hasDistributorCloudAccess;

  /// مزامنة ميدان الموزّع من الجوال: سحابة كاملة أو تجربة للموزّع المحلي مع اشتراك POS.
  bool get canSessionUseDistributorFieldSync {
    if (_session == null || isGuestSession) return false;
    if (_effectiveRole != 'distributor') return false;
    if (hasDistributorCloudAccess && isSessionCloudDistributor) return true;
    if (!isSessionLocalDistributor) return false;
    final now = DateTime.now();
    return _voucherSubscriptionActiveOnDevice ||
        licenseGate.hasPaidCoverage(now) ||
        licenseGate.hasRegisteredOperationalAccess(now);
  }

  bool get canCreateDistributorUser => licenseGate.canAddDistributorSeat();

  bool? _sessionDistributorCloudEnabled;

  static bool parseDistributorCloudEnabled(Map<String, Object?> row) {
    final role = (row['role'] ?? '').toString().trim().toLowerCase();
    if (role != 'distributor') return false;
    final v = row['distributorCloudEnabled'];
    if (v is bool) return v;
    if (v is int) return v != 0;
    if (v is num) return v.toInt() != 0;
    return false;
  }

  /// موزّع الجلسة الحالية يعمل بسحابة الميدان (مزامنة + مقعد).
  bool get isSessionCloudDistributor =>
      _effectiveRole == 'distributor' &&
      (_sessionDistributorCloudEnabled ?? false);

  /// موزّع محلي — ضمن الاشتراك العام بدون مقعد سحابة.
  bool get isSessionLocalDistributor =>
      _effectiveRole == 'distributor' &&
      !(_sessionDistributorCloudEnabled ?? false);

  /// مزامنة الطلبات/المرتجعات/المصروفات الميدانية.
  bool get canSessionUseDistributorCloudSync =>
      hasDistributorCloudAccess && isSessionCloudDistributor;

  Future<void> _refreshSessionDistributorCloudFlag() async {
    final s = _session;
    if (s == null || _effectiveRole != 'distributor') {
      _sessionDistributorCloudEnabled = false;
      return;
    }
    final db = await _databaseService.database;
    final rows = await db.query(
      'users',
      columns: ['distributorCloudEnabled', 'role'],
      where: 'id = ? AND organizationId = ?',
      whereArgs: [s.userId, s.organizationId],
      limit: 1,
    );
    if (rows.isEmpty) {
      _sessionDistributorCloudEnabled = false;
      return;
    }
    _sessionDistributorCloudEnabled =
        parseDistributorCloudEnabled(rows.first);
  }

  Future<int> countCloudDistributorUsers() async {
    final s = _session;
    if (s == null) return 0;
    final db = await _databaseService.database;
    final n = Sqflite.firstIntValue(
      await db.rawQuery(
        '''
        SELECT COUNT(*) FROM users
        WHERE organizationId = ?
          AND lower(trim(role)) = 'distributor'
          AND COALESCE(distributorCloudEnabled, 0) = 1
        ''',
        [s.organizationId],
      ),
    );
    return n ?? 0;
  }

  Future<int> countLocalDistributorUsers() async {
    final s = _session;
    if (s == null) return 0;
    final db = await _databaseService.database;
    final n = Sqflite.firstIntValue(
      await db.rawQuery(
        '''
        SELECT COUNT(*) FROM users
        WHERE organizationId = ?
          AND lower(trim(role)) = 'distributor'
          AND COALESCE(distributorCloudEnabled, 0) = 0
        ''',
        [s.organizationId],
      ),
    );
    return n ?? 0;
  }

  /// موزّع محلي — مجاني ضمن الاشتراك العام (يُفحص الدفع عند [addUser]).
  Future<bool> canAddLocalDistributorUser() async => true;

  /// موزّع سحابة — يتطلب اشتراك سحابة + مقعد متاح.
  Future<bool> canAddCloudDistributorUser() async {
    if (!hasDistributorCloudAccess) return false;
    final max = licenseGate.maxDistributorSeats;
    if (max == null) return true;
    final cloud = await countCloudDistributorUsers();
    return cloud < max;
  }

  /// ترقية موزّع محلي → سحابة (أو إضافة سحابة جديدة).
  Future<bool> canEnableCloudForDistributor({String? excludeUserId}) async {
    if (!hasDistributorCloudAccess) return false;
    final max = licenseGate.maxDistributorSeats;
    if (max == null) return true;
    final s = _session;
    if (s == null) return false;
    final db = await _databaseService.database;
    final args = <Object?>[s.organizationId];
    var sql = '''
      SELECT COUNT(*) FROM users
      WHERE organizationId = ?
        AND lower(trim(role)) = 'distributor'
        AND COALESCE(distributorCloudEnabled, 0) = 1
    ''';
    if (excludeUserId != null && excludeUserId.isNotEmpty) {
      sql += ' AND id != ?';
      args.add(excludeUserId);
    }
    final n = Sqflite.firstIntValue(await db.rawQuery(sql, args)) ?? 0;
    return n < max;
  }

  bool _distributorCloudOperationalAccess() =>
      _effectiveRole == 'distributor' &&
      hasDistributorCloudAccess &&
      (_sessionDistributorCloudEnabled ?? false);

  /// يقرأ تجربة/جدّ الجهاز من الملف ثم يطبّق اشتراك المؤسسة من جدول [users].
  ///
  /// حقول الاشتراك (`subscriptionAnnualUntil` / `subscriptionLegacyActivated`) تُحدَّث
  /// عادةً عند **المالك** بعد الشراء. الموظفون (محاسب، كاشير، …) يشاركون نفس الاشتراك:
  /// إن لم يكن لدى المستخدم الحالي اشتراكاً فعّالاً يُستمد من صف **مالك المؤسسة**،
  /// وتُقارَن [subscriptionDeviceBinding] بهوية **مالك الاشتراك** (نفس الجهاز + بريد المالك).
  Future<void> syncLicenseGate() async {
    await licenseGate.reloadDeviceTrialState();
    licenseGate.setRegisteredPendingActivation(false);
    _subscriptionBindingMismatch = false;
    final s = _session;
    if (s == null || isGuestSession) {
      licenseGate.clearAccountSubscription();
      licenseGate.setAccountAccessSuspended(false);
      licenseGate.clearDistributorCloud();
      _sessionDistributorCloudEnabled = false;
      return;
    }
    final db = await _databaseService.database;

    await alignOwnerRoleWithSubscriptionEmail(db, s.organizationId);

    try {
    const subCols = [
      'id',
      'subscriptionAnnualUntil',
      'subscriptionLegacyActivated',
      'subscriptionDeviceBinding',
      'email',
      'username',
      'webActivationPending',
      'subscriptionAccessSuspended',
      'distributorCloudUntil',
      'maxDistributorSeats',
      'usedDistributorSeats',
    ];

    bool parseLegacyFlag(Object? lr) {
      if (lr is bool) return lr;
      if (lr is int) return lr != 0;
      if (lr is num) return lr.toInt() != 0;
      return false;
    }

    DateTime? parseAnnualEnd(Map<String, Object?> row) {
      final au = (row['subscriptionAnnualUntil'] as String?)?.trim();
      if (au == null || au.isEmpty) return null;
      return DateTime.tryParse(au);
    }

    ({DateTime? end, bool legacy, bool annualActive, bool legacyActive})
        subscriptionState(Map<String, Object?> row, DateTime now) {
      final end = parseAnnualEnd(row);
      final legacy = parseLegacyFlag(row['subscriptionLegacyActivated']);
      final annualActive = end != null && now.isBefore(end);
      final legacyActive = legacy && end == null;
      return (
        end: end,
        legacy: legacy,
        annualActive: annualActive,
        legacyActive: legacyActive,
      );
    }

    Future<Map<String, Object?>?> userSubRow(String userId) async {
      final rows = await db.query(
        'users',
        columns: subCols,
        where: 'id = ? AND organizationId = ?',
        whereArgs: [userId, s.organizationId],
        limit: 1,
      );
      return rows.isEmpty ? null : rows.first;
    }

    final now = DateTime.now();
    var subRow = await userSubRow(s.userId);
    if (subRow == null) {
      licenseGate.clearAccountSubscription();
      licenseGate.setRegisteredPendingActivation(false);
      licenseGate.setAccountAccessSuspended(false);
      return;
    }

    var st = subscriptionState(subRow, now);
    if (!(st.annualActive || st.legacyActive)) {
      final owners = await db.query(
        'users',
        columns: subCols,
        where: 'organizationId = ? AND lower(trim(role)) = ?',
        whereArgs: [s.organizationId, 'owner'],
        orderBy: 'createdAt ASC',
        limit: 1,
      );
      if (owners.isNotEmpty) {
        final or = owners.first;
        if ((or['id'] as String?) != s.userId) {
          final ot = subscriptionState(or, now);
          if (ot.annualActive || ot.legacyActive) {
            subRow = or;
            st = ot;
          }
        }
      }
    }

    final subscriptionRemotePullOk =
        await _pullRemoteSubscriptionIntoLocal(db, s, subRow);

    subRow = await userSubRow(s.userId);
    if (subRow == null) {
      licenseGate.clearAccountSubscription();
      licenseGate.setAccountAccessSuspended(false);
      return;
    }
    st = subscriptionState(subRow, now);
    if (!(st.annualActive || st.legacyActive)) {
      final owners = await db.query(
        'users',
        columns: subCols,
        where: 'organizationId = ? AND lower(trim(role)) = ?',
        whereArgs: [s.organizationId, 'owner'],
        orderBy: 'createdAt ASC',
        limit: 1,
      );
      if (owners.isNotEmpty) {
        final or = owners.first;
        if ((or['id'] as String?) != s.userId) {
          final ot = subscriptionState(or, now);
          if (ot.annualActive || ot.legacyActive) {
            subRow = or;
            st = ot;
          }
        }
      }
    }

    final r = subRow;
    if (AccountingService.rowSubscriptionAccessSuspended(r)) {
      licenseGate.setAccountAccessSuspended(true);
      licenseGate.clearAccountSubscription();
      licenseGate.setRegisteredPendingActivation(false);
      _applyDistributorCloudFromUserRow(r);
      return;
    }
    licenseGate.setAccountAccessSuspended(false);

    final end = st.end;
    final legacy = st.legacy;
    final annualActive = st.annualActive;
    final legacyActive = st.legacyActive;

    final role = s.role.trim().toLowerCase();
    final isOwner = role == 'owner';

    if (RemoteSignupConfig.activationServerEnabled &&
        isOwner &&
        AccountingService.rowWebActivationPending(r) &&
        !(annualActive || legacyActive)) {
      licenseGate.clearAccountSubscription();
      licenseGate.setRegisteredPendingActivation(true);
      return;
    }

    if (annualActive || legacyActive) {
      final bindingUserId = r['id'] as String;
      final rowUsername = (r['username'] as String?) ?? '';
      final identity = AccountingService.normalizeSubscriptionIdentity(
        r['email'] as String?,
        rowUsername,
      );
      final tokenNow =
          await DeviceBinding.subscriptionBindingPayload(identity);
      var binding = (r['subscriptionDeviceBinding'] as String?)?.trim() ?? '';

      if (binding.isEmpty) {
        await db.update(
          'users',
          {'subscriptionDeviceBinding': tokenNow},
          where: 'id = ?',
          whereArgs: [bindingUserId],
        );
        binding = tokenNow;
      }

      if (!_subscriptionBindingMatches(binding, tokenNow)) {
        _subscriptionBindingMismatch = true;
        licenseGate.clearAccountSubscription();
        return;
      }

      if (AccountingService.rowWebActivationPending(r)) {
        await db.update(
          'users',
          {'webActivationPending': 0},
          where: 'id = ?',
          whereArgs: [r['id'] as String],
        );
      }
    }

    licenseGate.applyAccountSubscription(
      annualEndAt: end,
      legacyActivated: legacy,
    );

    var paidOrGrandfather =
        annualActive || legacyActive || licenseGate.grandfatherFullAccess;
    if (_voucherSubscriptionActiveOnDevice && role != 'distributor') {
      paidOrGrandfather = true;
    }
    if (!paidOrGrandfather && !_subscriptionBindingMismatch) {
      licenseGate.setRegisteredPendingActivation(isOwner);
    } else {
      licenseGate.setRegisteredPendingActivation(false);
    }

    _applyDistributorCloudFromUserRow(r);

    final selfRows = await db.query(
      'users',
      columns: ['email'],
      where: 'id = ?',
      whereArgs: [s.userId],
      limit: 1,
    );
    final reportEmail = AccountingService.normalizeSubscriptionIdentity(
      selfRows.isEmpty ? null : selfRows.first['email'] as String?,
      s.username,
    );
    // بلا سحب ناجح قد يُرسل التقرير اشتراكاً محلياً قديماً فيعيد إنشاء اللقطة على الخادم بعد حذفها من لوحة الويب.
    if (RemoteSignupConfig.activationServerEnabled &&
        reportEmail.contains('@') &&
        subscriptionRemotePullOk) {
      final bindingPayload =
          await DeviceBinding.subscriptionBindingPayload(reportEmail);
      unawaited(
        RemoteSignupApi(
          baseUrl: RemoteSignupConfig.apiBaseUrl,
          sharedSecret: RemoteSignupConfig.sharedSecret,
        ).reportLicenseSnapshot(
          organizationId: s.organizationId,
          email: reportEmail,
          trialEndAt: null,
          subscriptionAnnualUntil: end?.toUtc().toIso8601String(),
          legacyActivated: legacy && end == null,
          subscriptionDeviceBinding: bindingPayload,
        ),
      );
    }

    if (RemoteSignupConfig.teamUsersCrossDeviceSyncEnabled) {
      unawaited(() async {
        try {
          await TeamUsersSyncService(accountingService: this).pullToLocal();
        } on Object {
          /* اختياري — لا يؤثر على الترخيص */
        }
      }());
    }
    } finally {
      if (s.role.trim().toLowerCase() == 'distributor' &&
          !hasDistributorCloudAccess) {
        await _pullDistributorCloudLicenseIfNeeded(db, s);
      }
      await _applyOrgDistributorCloudFromDb(db, s.organizationId);
      await _refreshSessionDistributorCloudFlag();
    }
  }

  /// تفعيل سنوي للمستخدم المسجّل الحالي فقط (صف [users]).
  Future<void> activateCurrentUserAnnualSubscription(DateTime validUntil) async {
    final s = _mustSession();
    if (_isGuest) {
      throw Exception(
        'التفعيل يتطلب تسجيل الدخول إلى حسابك ثم إتمام الدفع من صفحة التفعيل على الموقع.',
      );
    }
    final db = await _databaseService.database;
    final erows = await db.query(
      'users',
      columns: ['email'],
      where: 'id = ?',
      whereArgs: [s.userId],
      limit: 1,
    );
    final identity = AccountingService.normalizeSubscriptionIdentity(
      erows.isEmpty ? null : erows.first['email'] as String?,
      s.username,
    );
    await db.update(
      'users',
      {
        'subscriptionAnnualUntil': validUntil.toIso8601String(),
        'subscriptionLegacyActivated': 0,
        'subscriptionDeviceBinding':
            await DeviceBinding.subscriptionBindingPayload(identity),
        'webActivationPending': 0,
      },
      where: 'id = ?',
      whereArgs: [s.userId],
    );
    await syncLicenseGate();
  }

  /// البريد المرتبط بالحساب الحالي في [users]؛ إن كان فارغاً يُعاد [AppUserSession.username].
  Future<String?> currentUserSubscriptionEmail() async {
    final s = _session;
    if (s == null || isGuestSession) return null;
    final db = await _databaseService.database;
    final rows = await db.query(
      'users',
      columns: ['email'],
      where: 'id = ?',
      whereArgs: [s.userId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final em = (rows.first['email'] as String?)?.trim() ?? '';
    if (em.isNotEmpty) return em;
    final un = s.username.trim();
    return un.isEmpty ? null : un;
  }

  /// الاسم الظاهر في الشريط لجلسة موظف/مالك (ليست جلسة الزائر).
  ///
  /// يُفضَّل [fullName] من جدول [users]، ثم [username]، ثم اسم الجلسة.
  Future<String> displayNameForCurrentStaffSession() async {
    final s = _session;
    if (s == null || isGuestSession) {
      return '';
    }
    final db = await _databaseService.database;
    final rows = await db.query(
      'users',
      columns: ['fullName', 'username', 'role'],
      where: 'id = ?',
      whereArgs: [s.userId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return resolveStaffDisplayName(
        username: s.username,
        role: s.role,
      );
    }
    final row = rows.first;
    final resolved = resolveStaffDisplayName(
      fullName: row['fullName'] as String?,
      username: row['username'] as String?,
      role: row['role'] as String?,
    );
    return resolved.isNotEmpty ? resolved : s.username;
  }

  /// الاسم المعروض كـ«صاحب الاشتراك» من جدول المستخدمين (التسجيل / المالك)، وليس إدخالاً يدوياً.
  Future<String?> subscriptionHolderDisplayName() async {
    final db = await _databaseService.database;
    final s = _session;
    if (s != null && !isGuestSession) {
      final rows = await db.query(
        'users',
        columns: ['fullName'],
        where: 'id = ?',
        whereArgs: [s.userId],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        final fn = (rows.first['fullName'] as String?)?.trim() ?? '';
        if (fn.isNotEmpty && fn != 'زائر') return fn;
      }
      final owners = await db.query(
        'users',
        columns: ['fullName'],
        where: 'organizationId = ? AND lower(trim(role)) = ?',
        whereArgs: [s.organizationId, 'owner'],
        limit: 1,
      );
      if (owners.isNotEmpty) {
        final on = (owners.first['fullName'] as String?)?.trim() ?? '';
        if (on.isNotEmpty) return on;
      }
      return null;
    }
    final orgRows = await db.query('organizations', limit: 1);
    if (orgRows.isEmpty) return null;
    final orgId = orgRows.first['id'] as String;
    final owners = await db.query(
      'users',
      columns: ['fullName'],
      where: 'organizationId = ? AND lower(trim(role)) = ?',
      whereArgs: [orgId, 'owner'],
      limit: 1,
    );
    if (owners.isEmpty) return null;
    final on = (owners.first['fullName'] as String?)?.trim() ?? '';
    return on.isEmpty ? null : on;
  }

  static String _normalizePhoneDigits(String raw) =>
      raw.replaceAll(RegExp(r'\D'), '');

  Future<String?> _primaryBranchIdForOrganization(
    Database db,
    String organizationId,
  ) async {
    final rows = await db.query(
      'branches',
      columns: ['id'],
      where: 'organizationId = ?',
      whereArgs: [organizationId],
      orderBy: 'createdAt ASC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['id'] as String;
  }

  Future<void> _provisionSignupUserForImmediateLogin({
    required Database db,
    required String organizationId,
    required String fullName,
    required String emailLower,
    required String dialCode,
    required String phoneDigits,
    required String passwordPlain,
    bool markWebActivationPending = false,
  }) async {
    final branchId = await _primaryBranchIdForOrganization(db, organizationId);
    if (branchId == null || branchId.isEmpty) {
      throw Exception('لا يوجد فرع.');
    }
    final now = DateTime.now().toIso8601String();
    final pwdHash = PasswordCrypto.hash(passwordPlain);
    final webPen = markWebActivationPending ? 1 : 0;
    final existing = await db.rawQuery(
      '''
      SELECT id FROM users
      WHERE organizationId = ?
        AND lower(trim(email)) = ?
      LIMIT 1
      ''',
      [organizationId, emailLower],
    );
    if (existing.isNotEmpty) {
      final uid = existing.first['id'] as String;
      await db.update(
        'users',
        {
          'fullName': fullName.trim(),
          'username': emailLower,
          'email': emailLower,
          'phone': phoneDigits,
          'dialCode': dialCode.trim().isEmpty ? '+970' : dialCode.trim(),
          'password': pwdHash,
          'role': 'owner',
          'accountStatus': 'active',
          'branchId': branchId,
          'webActivationPending': webPen,
        },
        where: 'id = ?',
        whereArgs: [uid],
      );
      return;
    }
    await db.insert('users', {
      'id': _uuid.v4(),
      'organizationId': organizationId,
      'branchId': branchId,
      'fullName': fullName.trim(),
      'username': emailLower,
      'password': pwdHash,
      'role': 'owner',
      'createdAt': now,
      'email': emailLower,
      'phone': phoneDigits,
      'dialCode': dialCode.trim().isEmpty ? '+970' : dialCode.trim(),
      'accountStatus': 'active',
      'fromSignupRequestId': null,
      'webActivationPending': webPen,
    });
  }

  Future<void> _persistLocalSignupPendingMirror({
    required String organizationId,
    required String fullName,
    required String emailLower,
    required String dialCode,
    required String phoneDigits,
    required String passwordPlain,
    required int pendingRemotePush,
  }) async {
    final db = await _databaseService.database;
    final pwdHash = PasswordCrypto.hash(passwordPlain);
    final dupPending = await db.rawQuery(
      '''
      SELECT id FROM signup_requests
      WHERE organizationId = ? AND lower(trim(email)) = ? AND status = 'pending'
      LIMIT 1
      ''',
      [organizationId, emailLower],
    );
    final now = DateTime.now().toIso8601String();
    if (dupPending.isNotEmpty) {
      final existingId = dupPending.first['id'] as String;
      await db.update(
        'signup_requests',
        {
          'fullName': fullName.trim(),
          'phone': phoneDigits,
          'dialCode': dialCode.trim(),
          'password': pwdHash,
          'requestedAt': now,
          'pendingRemotePush': pendingRemotePush,
        },
        where: 'id = ?',
        whereArgs: [existingId],
      );
      return;
    }
    await db.insert('signup_requests', {
      'id': _uuid.v4(),
      'organizationId': organizationId,
      'fullName': fullName.trim(),
      'email': emailLower,
      'phone': phoneDigits,
      'dialCode': dialCode.trim(),
      'password': pwdHash,
      'requestedAt': now,
      'status': 'pending',
      'pendingRemotePush': pendingRemotePush,
    });
  }

  /// يُزامِن طلبات التسجيل المحفوظة محلياً بسبب انقطاع الشبكة ([pendingRemotePush] = 1).
  Future<int> tryFlushQueuedRemoteSignups() async {
    if (!RemoteSignupConfig.activationServerEnabled) return 0;
    final api = RemoteSignupApi(
      baseUrl: RemoteSignupConfig.apiBaseUrl,
      sharedSecret: RemoteSignupConfig.sharedSecret,
    );
    try {
      await api.healthCheck();
    } catch (_) {
      return 0;
    }
    try {
      final db = await _databaseService.database;
      final rows = await db.query(
        'signup_requests',
        where: 'pendingRemotePush = ? AND status = ?',
        whereArgs: [1, 'pending'],
        orderBy: 'requestedAt ASC',
      );
      var flushed = 0;
      for (final r in rows) {
        final hash = (r['password'] as String?) ?? '';
        if (!PasswordCrypto.looksLikeBcrypt(hash)) continue;
        try {
          await api.submitSignup(
            organizationId: r['organizationId']! as String,
            fullName: (r['fullName'] as String?) ?? '',
            email: ((r['email'] as String?) ?? '').trim().toLowerCase(),
            dialCode: (r['dialCode'] as String?) ?? '+970',
            phoneDigits: (r['phone'] as String?) ?? '',
            passwordBcryptHash: hash,
            skipHealthCheck: true,
          );
        } on RemoteSignupOfflineException {
          break;
        } on RemoteSignupApiException {
          break;
        }
        await db.delete(
          'signup_requests',
          where: 'id = ?',
          whereArgs: [r['id'] as String],
        );
        flushed++;
      }
      return flushed;
    } catch (_) {
      return 0;
    }
  }

  Future<int> countQueuedRemoteSignupRequests() async {
    if (!RemoteSignupConfig.publicSignupServerEnabled) return 0;
    try {
      final db = await _databaseService.database;
      final q = await db.rawQuery(
        '''
      SELECT COUNT(*) AS c FROM signup_requests
      WHERE pendingRemotePush = 1 AND status = 'pending'
      ''',
      );
      final n = q.first['c'];
      if (n is int) return n;
      return int.tryParse('$n') ?? 0;
    } catch (_) {
      return 0;
    }
  }

  Future<void> _sendLocalSignupWelcomeEmailIfNeeded({
    required String emailLower,
    required String fullName,
  }) async {
    if (RemoteSignupConfig.publicSignupServerEnabled) return;
    await sendSignupWelcomeEmailViaSmtp(
      recipientEmail: emailLower,
      recipientName: fullName.trim(),
    );
  }

  /// إعادة إرسال رسالة ترحيب + تأكيد البريد (خادم أو SMTP محلي).
  Future<String?> resendSignupWelcomeVerificationEmail({
    required String email,
  }) async {
    final em = email.trim().toLowerCase();
    if (em.isEmpty || !em.contains('@')) {
      return 'auth_err_email_invalid';
    }
    if (RemoteSignupConfig.publicSignupServerEnabled) {
      final db = await _databaseService.database;
      final orgRows = await db.query('organizations', limit: 1);
      if (orgRows.isEmpty) return 'auth_err_no_org';
      final orgId = orgRows.first['id'] as String;
      try {
        await RemoteSignupApi(
          baseUrl: RemoteSignupConfig.apiBaseUrl,
          sharedSecret: RemoteSignupConfig.sharedSecret,
        ).resendSignupEmailVerification(
          organizationId: orgId,
          email: em,
        );
        return null;
      } on RemoteSignupOfflineException {
        return 'auth_err_no_internet';
      } on RemoteSignupApiException catch (e) {
        return e.code;
      }
    }
    final rows = await (await _databaseService.database).rawQuery(
      '''
      SELECT fullName FROM signup_requests
      WHERE lower(trim(email)) = ?
      ORDER BY requestedAt DESC LIMIT 1
      ''',
      [em],
    );
    final name = rows.isEmpty
        ? em
        : ((rows.first['fullName'] as String?) ?? em).trim();
    final outcome = await sendSignupWelcomeEmailViaSmtp(
      recipientEmail: em,
      recipientName: name,
    );
    if (outcome is SignupWelcomeSmtpSent) return null;
    if (outcome is SignupWelcomeSmtpMissingConfig) {
      return 'auth_reset_smtp_missing';
    }
    return 'auth_err_welcome_mail_failed';
  }

  /// طلب تسجيل جديد بانتظار موافقة المالك (بدون جلسة).
  Future<String?> submitSignupRequest({
    required String fullName,
    required String email,
    required String dialCode,
    required String phoneNational,
    required String password,
  }) async {
    final db = await _databaseService.database;
    final orgRows = await db.query('organizations', limit: 1);
    if (orgRows.isEmpty) {
      return 'auth_err_no_org';
    }
    final orgId = orgRows.first['id'] as String;
    final em = email.trim().toLowerCase();
    if (em.isEmpty || !em.contains('@')) {
      return 'auth_err_email_invalid';
    }
    final phoneDigits = _normalizePhoneDigits(phoneNational);
    if (phoneDigits.length < 6) {
      return 'auth_err_phone_invalid';
    }
    final dupUser = await db.rawQuery(
      '''
      SELECT id FROM users
      WHERE organizationId = ? AND lower(trim(email)) = ?
      LIMIT 1
      ''',
      [orgId, em],
    );
    if (dupUser.isNotEmpty) {
      return 'auth_err_email_taken';
    }

    final markWebActivationPending = RemoteSignupConfig.activationServerEnabled &&
        RemoteSignupConfig.publicSignupServerEnabled;

    if (RemoteSignupConfig.publicSignupServerEnabled) {
      try {
        await RemoteSignupApi(
          baseUrl: RemoteSignupConfig.apiBaseUrl,
          sharedSecret: RemoteSignupConfig.sharedSecret,
        ).submitSignup(
          organizationId: orgId,
          fullName: fullName.trim(),
          email: em,
          dialCode: dialCode.trim(),
          phoneDigits: phoneDigits,
          password: password,
        );
        await _provisionSignupUserForImmediateLogin(
          db: db,
          organizationId: orgId,
          fullName: fullName,
          emailLower: em,
          dialCode: dialCode,
          phoneDigits: phoneDigits,
          passwordPlain: password,
          markWebActivationPending: markWebActivationPending,
        );
        return null;
      } on RemoteSignupOfflineException {
        await _persistLocalSignupPendingMirror(
          organizationId: orgId,
          fullName: fullName.trim(),
          emailLower: em,
          dialCode: dialCode.trim(),
          phoneDigits: phoneDigits,
          passwordPlain: password,
          pendingRemotePush: 1,
        );
        await _provisionSignupUserForImmediateLogin(
          db: db,
          organizationId: orgId,
          fullName: fullName,
          emailLower: em,
          dialCode: dialCode,
          phoneDigits: phoneDigits,
          passwordPlain: password,
          markWebActivationPending: markWebActivationPending,
        );
        return 'auth_ok_remote_queued';
      } on RemoteSignupApiException catch (e) {
        return e.code;
      }
    }

    await _persistLocalSignupPendingMirror(
      organizationId: orgId,
      fullName: fullName.trim(),
      emailLower: em,
      dialCode: dialCode.trim(),
      phoneDigits: phoneDigits,
      passwordPlain: password,
      pendingRemotePush: 0,
    );
    await _provisionSignupUserForImmediateLogin(
      db: db,
      organizationId: orgId,
      fullName: fullName,
      emailLower: em,
      dialCode: dialCode,
      phoneDigits: phoneDigits,
      passwordPlain: password,
      markWebActivationPending: markWebActivationPending,
    );
    await _sendLocalSignupWelcomeEmailIfNeeded(
      emailLower: em,
      fullName: fullName,
    );
    return null;
  }

  Future<List<Map<String, Object?>>> listSignupRequests() async {
    final s = _mustSession();
    if (RemoteSignupConfig.publicSignupServerEnabled) {
      return const [];
    }
    if (s.role != 'owner') {
      return const [];
    }
    final db = await _databaseService.database;
    final rows = await db.query(
      'signup_requests',
      where: 'organizationId = ? AND status = ?',
      whereArgs: [s.organizationId, 'pending'],
      orderBy: 'requestedAt DESC',
    );
    return List<Map<String, Object?>>.from(rows);
  }

  Future<SignupApprovalMailResult?> approveSignupRequest(String requestId) async {
    final s = _mustSession();
    if (s.role != 'owner') {
      throw Exception('غير مصرح.');
    }
    if (RemoteSignupConfig.publicSignupServerEnabled) {
      throw Exception(
        'الموافقة على طلبات التسجيل تتم من صفحة الويب بعد ضبط الخادم.',
      );
    }
    final db = await _databaseService.database;
    final rows = await db.query(
      'signup_requests',
      where: 'id = ? AND organizationId = ?',
      whereArgs: [requestId, s.organizationId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw Exception('الطلب غير موجود.');
    }
    final r = rows.first;
    if ((r['status'] as String?) != 'pending') {
      return null;
    }
    final email = (r['email'] as String).trim().toLowerCase();
    final displayName = (r['fullName'] as String).trim();
    final branchId = await resolvePrimaryBranchId();
    if (branchId == null) {
      throw Exception('لا يوجد فرع.');
    }
    final uid = _uuid.v4();
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      await txn.rawUpdate(
        '''
        UPDATE signup_requests
        SET issuedActivationKey = NULL
        WHERE organizationId = ?
          AND lower(trim(email)) = ?
          AND id != ?
          AND issuedActivationKey IS NOT NULL
        ''',
        [s.organizationId, email, requestId],
      );
      await txn.insert('users', {
        'id': uid,
        'organizationId': s.organizationId,
        'branchId': branchId,
        'fullName': displayName,
        'username': email,
        'email': email,
        'phone': r['phone'] as String,
        'dialCode': (r['dialCode'] as String?) ?? '+970',
        'password': r['password'] as String,
        'role': 'owner',
        'accountStatus': 'active',
        'createdAt': now,
        'fromSignupRequestId': requestId,
        'webActivationPending': 0,
      });
      await txn.update(
        'signup_requests',
        {
          'status': 'approved',
          'reviewedAt': now,
          'reviewedByUserId': s.userId,
          'issuedActivationKey': null,
        },
        where: 'id = ?',
        whereArgs: [requestId],
      );
    });
    await _audit(
        'approve', 'signup_request', requestId, 'Approved signup $email');
    return SignupApprovalMailResult(
      recipientEmail: email,
      recipientName: displayName.isNotEmpty ? displayName : email,
    );
  }

  Future<void> rejectSignupRequest(String requestId) async {
    final s = _mustSession();
    if (s.role != 'owner') {
      throw Exception('غير مصرح.');
    }
    if (RemoteSignupConfig.publicSignupServerEnabled) {
      throw Exception(
        'رفض طلبات التسجيل يتم من صفحة الويب بعد ضبط الخادم.',
      );
    }
    final db = await _databaseService.database;
    final now = DateTime.now().toIso8601String();
    final n = await db.update(
      'signup_requests',
      {
        'status': 'rejected',
        'reviewedAt': now,
        'reviewedByUserId': s.userId,
      },
      where: 'id = ? AND organizationId = ? AND status = ?',
      whereArgs: [requestId, s.organizationId, 'pending'],
    );
    if (n > 0) {
      await _audit('reject', 'signup_request', requestId, 'Rejected signup');
    }
  }

  /// إعادة تعيين كلمة المرور بعد مطابقة البريد ورقم الهاتف المخزَّن.
  Future<bool> resetPasswordWithPhoneVerification({
    required String email,
    required String dialCode,
    required String phoneNational,
    required String newPassword,
  }) async {
    final db = await _databaseService.database;
    final em = email.trim().toLowerCase();
    final digits = _normalizePhoneDigits(phoneNational);
    final dc = dialCode.trim();
    if (em.isEmpty || digits.length < 6 || newPassword.length < 4) {
      return false;
    }
    final rows = await db.rawQuery(
      '''
      SELECT id FROM users
      WHERE lower(trim(email)) = ?
        AND trim(COALESCE(dialCode, '')) = ?
        AND phone = ?
        AND (COALESCE(accountStatus, 'active') = 'active')
      LIMIT 1
      ''',
      [em, dc, digits],
    );
    if (rows.isEmpty) {
      return false;
    }
    final id = rows.first['id'] as String;
    await db.update(
      'users',
      {'password': PasswordCrypto.hash(newPassword)},
      where: 'id = ?',
      whereArgs: [id],
    );
    return true;
  }

  String _generateTemporaryPassword() {
    const chars =
        'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789@#%';
    final rnd = Random.secure();
    return List.generate(10, (_) => chars[rnd.nextInt(chars.length)]).join();
  }

  Future<String> resetPasswordByEmailAndSendTemporaryPassword({
    required String email,
  }) async {
    final db = await _databaseService.database;
    final em = email.trim().toLowerCase();
    if (em.isEmpty || !em.contains('@')) {
      return 'auth_err_email_invalid';
    }
    final rows = await db.rawQuery(
      '''
      SELECT id, fullName, email
      FROM users
      WHERE lower(trim(email)) = ?
        AND (COALESCE(accountStatus, 'active') = 'active')
        AND lower(trim(role)) <> 'guest'
      LIMIT 1
      ''',
      [em],
    );
    if (rows.isEmpty) {
      return 'auth_reset_email_not_found';
    }
    final row = rows.first;
    final uid = row['id'] as String;
    final to = (row['email'] as String?)?.trim().toLowerCase() ?? em;
    final fullName = (row['fullName'] as String?)?.trim() ?? '';
    final temporaryPassword = _generateTemporaryPassword();

    final mailResult = await sendPasswordResetTemporaryPasswordEmailViaSmtp(
      recipientEmail: to,
      recipientName: fullName,
      temporaryPassword: temporaryPassword,
    );
    if (mailResult is PasswordResetSmtpMissingConfig) {
      return 'auth_reset_smtp_missing';
    }
    if (mailResult is PasswordResetSmtpFailed) {
      return 'auth_reset_smtp_failed';
    }

    await db.update(
      'users',
      {'password': PasswordCrypto.hash(temporaryPassword)},
      where: 'id = ?',
      whereArgs: [uid],
    );
    return 'auth_reset_email_sent';
  }

  /// للتحقق عند إلغاء قفل الشاشة بعد الخمول (بدون إنهاء الجلسة).
  Future<bool> verifyCurrentUserPassword(String password) async {
    final s = _mustSession();
    final db = await _databaseService.database;
    final rows = await db.query(
      'users',
      columns: ['password'],
      where: 'id = ?',
      whereArgs: [s.userId],
      limit: 1,
    );
    if (rows.isEmpty) return false;
    final storedPwd = rows.first['password'] as String;
    final ok = PasswordCrypto.verifyPlainOrHash(password, storedPwd);
    if (ok && !PasswordCrypto.looksLikeBcrypt(storedPwd)) {
      await db.update(
        'users',
        {'password': PasswordCrypto.hash(password)},
        where: 'id = ?',
        whereArgs: [s.userId],
      );
    }
    return ok;
  }

  /// هل اشتراك القسيمة ساري على هذا الجهاز؟ (يُعامل كتفعيل كامل للعمليات المحلية).
  bool get _voucherSubscriptionActiveOnDevice {
    try {
      return VoucherSessionManager.instance.status.isActive;
    } on Object {
      return false;
    }
  }

  /// الدور الظاهر في شريط الهوية — جلسة الموظف أو مالك القسيمة المفعّلة.
  String get appBarDisplayRole {
    final s = _session;
    if (s != null && !isGuestSession) {
      return s.role.trim().toLowerCase();
    }
    if (isGuestSession && hasVoucherOnDevice) {
      return 'owner';
    }
    return 'guest';
  }

  /// هل تُعرَض لوحة الهوية كمسجّل دخول (موظف أو مشترك بقسيمة سارية)؟
  bool get isIdentityPortalSignedIn =>
      hasAuthenticatedStaffSession ||
      (isGuestSession && hasVoucherOnDevice);

  /// هل جلسة موظف نشطة بهذا الدور تحديداً؟
  bool isStaffSignedInAsRole(String role) {
    final s = _session;
    if (s == null || isGuestSession) return false;
    return s.role.trim().toLowerCase() == role.trim().toLowerCase();
  }

  /// هل الواجهة تعرض هذا الدور حالياً (موظف مسجّل دخوله فقط)؟
  bool isDisplayingAsRole(String role) {
    return appBarDisplayRole == role.trim().toLowerCase();
  }

  /// جلسة موظف حقيقية (ليست وضع الزائر الافتراضي).
  bool get hasAuthenticatedStaffSession =>
      _session != null && !isGuestSession;

  /// إدارة قائمة الموظفين: المالك، المحاسب، مدير الفرع، أو مشترك بقسيمة سارية.
  bool canManageUsers() {
    if (isGuestSession && hasVoucherOnDevice) return true;
    switch (_effectiveRole) {
      case 'owner':
      case 'accountant':
      case 'branch_manager':
        return true;
      case 'guest':
        return false;
      default:
        return false;
    }
  }

  void _requireStaffAdminRole() {
    if (!canManageUsers()) {
      throw Exception('غير مصرح بإدارة فريق العمل.');
    }
  }

  bool _nonOwnerMustNotTouchOwnerRole({
    required String existingRole,
    String? newRole,
  }) {
    if (_effectiveRole == 'owner') return false;
    final ex = existingRole.trim().toLowerCase();
    final nw = newRole?.trim().toLowerCase();
    return ex == 'owner' || nw == 'owner';
  }

  /// الفرع الافتراضي للمؤسسة (أول فرع مسجّل) — لإضافة مستخدمين دون اختيار يدوي.
  Future<String?> resolvePrimaryBranchId() async {
    final s = _mustSession();
    return ensurePrimaryBranchForOrganization(s.organizationId);
  }

  /// يضمن وجود فرع على المؤسسة — مطلوب قبل دمج مستخدمين مُسحَبين من السحابة.
  Future<String?> ensurePrimaryBranchForOrganization(String organizationId) async {
    final orgId = organizationId.trim();
    if (orgId.isEmpty) return null;
    final db = await _databaseService.database;
    final rows = await db.query(
      'branches',
      columns: ['id'],
      where: 'organizationId = ?',
      whereArgs: [orgId],
      orderBy: 'createdAt ASC',
      limit: 1,
    );
    if (rows.isNotEmpty) {
      final id = (rows.first['id'] as String?)?.trim() ?? '';
      if (id.isNotEmpty) return id;
    }
    final sess = _session;
    if (sess != null && sess.organizationId == orgId) {
      final sessBranch = sess.branchId.trim();
      if (sessBranch.isNotEmpty) {
        final exists = await db.query(
          'branches',
          where: 'id = ? AND organizationId = ?',
          whereArgs: [sessBranch, orgId],
          limit: 1,
        );
        if (exists.isEmpty) {
          await db.insert('branches', {
            'id': sessBranch,
            'organizationId': orgId,
            'name': 'الفرع الرئيسي',
            'code': 'MAIN',
            'createdAt': DateTime.now().toIso8601String(),
          });
        }
        return sessBranch;
      }
    }
    final branchId = _uuid.v4();
    await db.insert('branches', {
      'id': branchId,
      'organizationId': orgId,
      'name': 'الفرع الرئيسي',
      'code': 'MAIN',
      'createdAt': DateTime.now().toIso8601String(),
    });
    return branchId;
  }

  String get _effectiveRole => (_session?.role ?? '').trim().toLowerCase();

  bool get _isGuest => _effectiveRole == 'guest';

  /// عمليات تتطلّب اشتراكاً مدفوعاً مفعّلاً (لا يكفي وضع «مسجّل بانتظار التفعيل»).
  ///
  /// يُقبل أيضاً اشتراك القسيمة الساري على الجهاز حتى لو لم يُحدَّث [licenseGate] بعد.
  void _requirePaidSubscription() {
    if (_isGuest) return;
    final now = DateTime.now();
    if (licenseGate.hasPaidCoverage(now) ||
        _voucherSubscriptionActiveOnDevice) {
      return;
    }
    if (licenseGate.coverageKind(now) ==
        LicenseCoverageKind.accessSuspended) {
      throw const LicenseException(LicenseGate.kCodeSubscriptionSuspended);
    }
    throw const LicenseException(LicenseGate.kCodeSubscriptionRequired);
  }

  /// تشغيل يومي بعد تسجيل الدخول قبل إتمام التفعيل المدفوع.
  void _requireRegisteredOperationalAccess() {
    if (_isGuest) return;
    if (_distributorCloudOperationalAccess()) return;
    if (_voucherSubscriptionActiveOnDevice && _effectiveRole != 'distributor') {
      return;
    }
    final now = DateTime.now();
    if (!licenseGate.hasRegisteredOperationalAccess(now)) {
      if (licenseGate.coverageKind(now) ==
          LicenseCoverageKind.accessSuspended) {
        throw const LicenseException(LicenseGate.kCodeSubscriptionSuspended);
      }
      throw const LicenseException(LicenseGate.kCodeSubscriptionRequired);
    }
  }

  /// تصدير التقارير، النسخ الاحتياطي، الاستعادة، ومركز الاستعلامات.
  /// وضع الزائر: مسموح (مركز التقارير، PDF/Excel، النسخ الاحتياطي…) دون اشتراط «تفعيل كامل».
  /// المستخدم المسجّل: [LicenseGate.hasRegisteredOperationalAccess] (مدفوع أو بانتظار التفعيل)،
  /// مع رفض الحساب المجمّد.
  void _requireOperationalCommercialAccess() {
    if (_isGuest) {
      return;
    }
    if (_distributorCloudOperationalAccess()) return;
    if (_voucherSubscriptionActiveOnDevice && _effectiveRole != 'distributor') {
      return;
    }
    final now = DateTime.now();
    if (licenseGate.coverageKind(now) ==
        LicenseCoverageKind.accessSuspended) {
      throw const LicenseException(LicenseGate.kCodeSubscriptionSuspended);
    }
    if (!licenseGate.hasRegisteredOperationalAccess(now)) {
      throw const LicenseException(LicenseGate.kCodeSubscriptionRequired);
    }
  }

  /// نسخ احتياطي واستعادة — نفس شرط [requirePremiumCommercialExport].
  void _requirePremiumCommercialFeatures() =>
      _requireOperationalCommercialAccess();

  /// تصدير التقارير (PDF/Excel/CSV)، الطباعة الشاملة، ومركز الاستعلامات.
  /// يشمل وضع الزائر دون رسالة «نسخة مفعّلة بالكامل».
  void requirePremiumCommercialExport() => _requireOperationalCommercialAccess();

  /// طباعة/تصدير مستندات بسيطة (مثل سندات الرصيد الافتتاحي): يُسمح للزائر،
  /// وللمستخدم المسجّل حتى في وضع «بانتظار التفعيل»، دون اشتراط التفعيل المدفوع الكامل.
  void requireBasicPrintOrExportAccess() {
    if (_isGuest) return;
    _requireRegisteredOperationalAccess();
  }

  bool _isRestrictedInventoryStaffRole() {
    switch (_effectiveRole) {
      case 'cashier':
      case 'distributor':
        return true;
      default:
        return false;
    }
  }

  /// أي موظف مسجّل (مالك / محاسب / مدير / …) ما عدا الأدوار المقيّدة في الأمان.
  bool _hasStaffInventoryCatalogAccess() {
    if (_isGuest || _session == null) return false;
    if (_isRestrictedInventoryStaffRole()) return false;
    return true;
  }

  /// زائر بقسيمة سارية على الجهاز = صلاحيات مخزون كاملة (مثل المشترك المفعّل).
  bool _guestWithVoucherInventoryAccess() =>
      _isGuest && _voucherSubscriptionActiveOnDevice;

  /// زائر بقسيمة سارية = مرتجعات مبيعات/مشتريات (مثل المشترك المفعّل).
  bool _guestWithVoucherSalesAccess() =>
      _isGuest && _voucherSubscriptionActiveOnDevice;

  /// موظف مسجّل (ما عدا الموزع) — مرتجعات الفواتير ضمن العمليات اليومية.
  bool _hasStaffSalesReturnAccess() {
    if (_isGuest || _session == null) return false;
    if (_effectiveRole == 'distributor') return false;
    return true;
  }

  /// عرض السلة، الاسترجاع، ونقل المنتجات إليها.
  bool canAccessProductTrash() {
    if (_session == null) return false;
    if (_guestWithVoucherInventoryAccess()) return true;
    if (_hasStaffInventoryCatalogAccess()) return true;
    return canManageProductsBasic() || canDeleteProducts();
  }

  bool canEditProductPrices() {
    if (_isGuest) return true;
    return _securityPrefs.permissionForRole(
      _effectiveRole,
      SecurityPermissions.editPrices,
    );
  }

  bool canDeleteProducts() {
    if (_session == null) return false;
    if (_guestWithVoucherInventoryAccess()) return true;
    if (_hasStaffInventoryCatalogAccess()) return true;
    return _securityPrefs.permissionForRole(
      _effectiveRole,
      SecurityPermissions.deleteProducts,
    );
  }

  /// نقل منتج إلى سلة المحذوفات.
  bool canMoveProductToTrash() => canAccessProductTrash();

  /// أقصى أصناف في المخزون بدون قسيمة سارية (زائر أو مسجّل).
  static const int trialCatalogProductLimit =
      ProductCatalogTrialLimitException.limit;

  /// أقصى منتجات مميزة في فاتورة بيع/شراء بدون تفعيل القسيمة.
  static const int trialTransactionDistinctProductLimit = 5;

  /// قسيمة Miza سارية على هذا الجهاز.
  bool get hasVoucherOnDevice => _voucherSubscriptionActiveOnDevice;

  /// هل نعرض «تسجيل الدخول بحساب آخر»؟ المدير مع قسيمة مفعّلة: لا — يكفي الخروج.
  bool get offerStaffAccountSwitch {
    if (_session == null) return true;
    if (isGuestSession) {
      return !hasVoucherOnDevice;
    }
    if (_session!.role.trim().toLowerCase() == 'owner' && hasVoucherOnDevice) {
      return false;
    }
    return true;
  }

  /// إعدادات المتجر — متاحة للجميع على الجوال (زائر أو أي موظف).
  bool canAccessStoreSettings() {
    return _session != null;
  }

  /// عدد الأصناف النشطة في فرع الجلسة الحالية.
  Future<int> countCatalogProducts() async {
    final s = _mustSession();
    final db = await _databaseService.database;
    final row = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM products '
      'WHERE organizationId = ? AND branchId = ?',
      [s.organizationId, s.branchId],
    );
    final v = row.first['c'];
    if (v is int) return v;
    return int.tryParse('$v') ?? 0;
  }

  /// هل يُسمح بإضافة صنف جديد الآن؟
  Future<bool> canAddCatalogProduct() async {
    if (_session == null) return false;
    if (_voucherSubscriptionActiveOnDevice) {
      return canManageProductsBasic();
    }
    final n = await countCatalogProducts();
    return n < trialCatalogProductLimit;
  }

  Future<int> _countCatalogProductsTxn(
    DatabaseExecutor txn,
    String organizationId,
    String branchId,
  ) async {
    final row = await txn.rawQuery(
      'SELECT COUNT(*) AS c FROM products '
      'WHERE organizationId = ? AND branchId = ?',
      [organizationId, branchId],
    );
    final v = row.first['c'];
    if (v is int) return v;
    return int.tryParse('$v') ?? 0;
  }

  Future<void> _requireCanAddCatalogProductInTxn(
    DatabaseExecutor txn,
    String organizationId,
    String branchId,
  ) async {
    if (_voucherSubscriptionActiveOnDevice) {
      _requireManageProductsBasic();
      return;
    }
    final c = await _countCatalogProductsTxn(txn, organizationId, branchId);
    if (c >= trialCatalogProductLimit) {
      throw const ProductCatalogTrialLimitException();
    }
  }

  bool canManageProductsBasic() {
    if (_session == null) return false;
    if (_guestWithVoucherInventoryAccess()) return true;
    if (_hasStaffInventoryCatalogAccess()) return true;
    return _securityPrefs.permissionForRole(
      _effectiveRole,
      SecurityPermissions.manageProductsBasic,
    );
  }

  bool canBulkImportProducts() {
    if (_session == null) return false;
    // وضع الزائر هو الوضع الافتراضي للمتجر (بدون دخول فريق العمل).
    // الاستيراد مسموح له مثل إضافة الأصناف؛ حدود التجربة تُطبَّق عند الإدراج.
    if (_isGuest) return true;
    return _securityPrefs.permissionForRole(
      _effectiveRole,
      SecurityPermissions.bulkImportProducts,
    );
  }

  bool canModifyInvoices() {
    if (_session == null) return false;
    // وضع الزائر والتجربة: تعديل وحذف الفواتير ضمن العمليات اليومية.
    if (_isGuest) return true;
    return _securityPrefs.permissionForRole(
      _effectiveRole,
      SecurityPermissions.modifyInvoices,
    );
  }

  bool canCreateReturns() {
    if (_session == null) return false;
    if (_guestWithVoucherSalesAccess()) return true;
    if (_effectiveRole == 'distributor') return true;
    if (_hasStaffSalesReturnAccess()) return true;
    return _securityPrefs.permissionForRole(
      _effectiveRole,
      SecurityPermissions.createReturns,
    );
  }

  bool canViewFinancialReports() {
    if (_isGuest) return true;
    return _securityPrefs.permissionForRole(
      _effectiveRole,
      SecurityPermissions.viewFinancialReports,
    );
  }

  void _requireEditProductPrices() {
    if (!canEditProductPrices()) {
      throw Exception('ليس لديك صلاحية تعديل أسعار المنتجات.');
    }
  }

  void _requireManageProductsBasic() {
    if (!canManageProductsBasic()) {
      throw Exception('ليس لديك صلاحية إدارة أصناف المخزون.');
    }
  }

  void _requireDeleteProducts() {
    if (!canDeleteProducts()) {
      throw Exception('ليس لديك صلاحية حذف المنتجات.');
    }
  }

  void _requireMoveProductToTrash() {
    if (!canMoveProductToTrash()) {
      throw Exception(
        'ليس لديك صلاحية نقل المنتجات إلى سلة المحذوفات.',
      );
    }
  }

  void _requireProductTrashAccess() {
    if (!canAccessProductTrash()) {
      throw Exception(
        'ليس لديك صلاحية عرض أو استرجاع المنتجات المحذوفة.',
      );
    }
  }

  void _requireBulkImportProducts() {
    if (!canBulkImportProducts()) {
      throw Exception('ليس لديك صلاحية استيراد أو تحديث أصناف بالجملة.');
    }
  }

  void _requireModifyInvoices() {
    if (!canModifyInvoices()) {
      throw Exception('ليس لديك صلاحية تعديل أو حذف الفواتير.');
    }
  }

  void _requireCreateReturns() {
    if (!canCreateReturns()) {
      throw Exception('ليس لديك صلاحية إنشاء فواتير المرتجع.');
    }
  }

  Future<List<Map<String, Object?>>> listBranches() async {
    final s = _mustSession();
    final db = await _databaseService.database;
    return db.query(
      'branches',
      where: 'organizationId = ?',
      whereArgs: [s.organizationId],
      orderBy: 'name',
    );
  }

  Future<void> addBranch(String name, String code) async {
    final s = _mustSession();
    if (_isGuest) {
      throw Exception('سجّل الدخول لإضافة فرع.');
    }
    _requirePaidSubscription();
    final db = await _databaseService.database;
    final id = _uuid.v4();
    try {
      await db.insert('branches', {
        'id': id,
        'organizationId': s.organizationId,
        'name': name,
        'code': code,
        'createdAt': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      throw Exception(_translateDbError(e));
    }
    await _audit('create', 'branch', id, 'Created branch $name');
  }

  Future<String?> _signupOriginRequestIdForUser(String userId) async {
    try {
      final db = await _databaseService.database;
      final rows = await db.query(
        'users',
        columns: ['fromSignupRequestId'],
        where: 'id = ?',
        whereArgs: [userId],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      final v = rows.first['fromSignupRequestId'] as String?;
      if (v == null || v.trim().isEmpty) return null;
      return v.trim();
    } catch (_) {
      return null;
    }
  }

  /// مشترك معتمد من التسجيل لا يحق له إدارة مشترك معتمد آخر (عرضاً أو تعديلاً).
  Future<void> _assertSignupSubscriberDoesNotManagePeer({
    required String targetUserId,
  }) async {
    final s = _mustSession();
    final selfOrigin = await _signupOriginRequestIdForUser(s.userId);
    if (selfOrigin == null) return;
    if (targetUserId == s.userId) return;
    final peerOrigin = await _signupOriginRequestIdForUser(targetUserId);
    if (peerOrigin != null) {
      throw Exception(
        'لا يمكن إدارة حساب مشترك آخر تم اعتماده من التسجيل.',
      );
    }
  }

  Future<List<Map<String, Object?>>> listUsers() async {
    final s = _mustSession();
    final db = await _databaseService.database;
    List<Map<String, Object?>> rows;
    try {
      rows = await db.rawQuery(
        '''
      SELECT u.*,
             sr.issuedActivationKey AS signupIssuedActivationKey
      FROM users u
      LEFT JOIN signup_requests sr ON sr.id = u.fromSignupRequestId
      WHERE u.organizationId = ?
        AND lower(trim(u.role)) <> ?
      ORDER BY u.fullName COLLATE NOCASE
      ''',
        [s.organizationId, 'guest'],
      );
    } catch (_) {
      rows = await db.rawQuery(
        '''
      SELECT *
      FROM users
      WHERE organizationId = ?
        AND lower(trim(role)) <> ?
      ORDER BY fullName COLLATE NOCASE
      ''',
        [s.organizationId, 'guest'],
      );
    }

    // نتائج SQLite قد تكون خرائط غير قابلة للتعديل — النسخ يمنع فشل u.remove لغير المالك.
    var list = rows.map((e) => Map<String, Object?>.from(e)).toList();
    for (final u in list) {
      if (!u.containsKey('signupIssuedActivationKey')) {
        u['signupIssuedActivationKey'] = null;
      }
    }
    if (s.role != 'owner') {
      for (final u in list) {
        u.remove('signupIssuedActivationKey');
      }
    }
    final selfOrigin = await _signupOriginRequestIdForUser(s.userId);
    if (selfOrigin != null) {
      list = list.where((u) {
        final sid = (u['fromSignupRequestId'] as String?)?.trim();
        if (sid == null || sid.isEmpty) return true;
        return u['id'] == s.userId;
      }).map((u) => Map<String, Object?>.from(u)).toList();
    }
    return list;
  }

  Future<void> addUser({
    required String branchId,
    required String fullName,
    required String username,
    required String password,
    required String role,
    String dialCode = '+970',
    String phoneNational = '',
    bool distributorCloudEnabled = false,
  }) async {
    final s = _mustSession();
    _requireStaffAdminRole();
    _requirePaidSubscription();
    final rl = role.trim().toLowerCase();
    if (_nonOwnerMustNotTouchOwnerRole(existingRole: '', newRole: rl)) {
      throw Exception('تعيين دور المالك متاح من حساب المالك فقط.');
    }
    final db = await _databaseService.database;
    final id = _uuid.v4();
    final un = username.trim();
    if (un.toLowerCase() == 'guest') {
      throw Exception('اسم الدخول «guest» محجوز.');
    }
    final emailVal =
        un.toLowerCase().contains('@') ? un.toLowerCase() : '$un@legacy.mizapos';
    if (rl == 'owner') {
      await _assertOwnerRoleMatchesSubscriptionEmail(
        db,
        s.organizationId,
        emailVal,
        un,
      );
    }
    final dc = dialCode.trim().isEmpty ? '+970' : dialCode.trim();
    final phoneDigits = _normalizePhoneDigits(phoneNational);
    final cloudFlag = rl == 'distributor' && distributorCloudEnabled ? 1 : 0;
    final teamTenant = await activeSubscriptionEmailForSync(
      localOrganizationId: s.organizationId,
    );
    try {
      await db.insert('users', {
        'id': id,
        'organizationId': s.organizationId,
        'branchId': branchId,
        'fullName': fullName,
        'username': username.trim(),
        'password': PasswordCrypto.hash(password),
        'role': rl,
        'createdAt': DateTime.now().toIso8601String(),
        'email': emailVal,
        'phone': phoneDigits,
        'dialCode': dc,
        'accountStatus': 'active',
        'distributorCloudEnabled': cloudFlag,
        if (teamTenant != null && rl != 'owner' && rl != 'guest')
          'teamSubscriptionEmail': teamTenant,
      });
    } catch (e) {
      throw Exception(_translateDbError(e));
    }
    final inserted = await db.query(
      'users',
      where: 'id = ? AND organizationId = ?',
      whereArgs: [id, s.organizationId],
      limit: 1,
    );
    if (inserted.isNotEmpty) {
      _pushTeamUserToCloudFireAndForget(inserted.first);
    }
    await _audit('create', 'user', id, 'Created user $username');
  }

  /// تحديث مستخدم في المؤسسة الحالية (بدون تغيير الفرع).
  Future<void> updateUser({
    required String userId,
    String? fullName,
    String? username,
    String? password,
    String? role,
    String? dialCode,
    String? phoneNational,
    bool? distributorCloudEnabled,
  }) async {
    final s = _mustSession();
    _requireStaffAdminRole();
    _requirePaidSubscription();
    final db = await _databaseService.database;
    final rows = await db.query(
      'users',
      where: 'id = ? AND organizationId = ?',
      whereArgs: [userId, s.organizationId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw Exception('الحساب غير موجود.');
    }
    final existingRole = (rows.first['role'] as String?) ?? '';
    if (_nonOwnerMustNotTouchOwnerRole(
      existingRole: existingRole,
      newRole: role,
    )) {
      throw Exception(
        'لا يمكن تعديل حساب المالك أو تعيين دور المالك إلا من حساب المالك.',
      );
    }
    final existingEmail = (rows.first['email'] as String?) ?? '';
    final existingUsername = (rows.first['username'] as String?) ?? '';
    final canonicalSub =
        await resolveCanonicalSubscriptionEmailForOrg(db, s.organizationId);
    final existingIdentity = normalizeSubscriptionIdentity(
      existingEmail,
      existingUsername,
    );
    if (canonicalSub != null &&
        existingIdentity == canonicalSub &&
        role != null &&
        role.trim().toLowerCase() != 'owner') {
      throw Exception(
        'لا يمكن تغيير دور صاحب بريد الاشتراك/التفعيل.',
      );
    }
    if (role != null && role.trim().toLowerCase() == 'owner') {
      final nextEmail = username != null
          ? (username.trim().toLowerCase().contains('@')
              ? username.trim().toLowerCase()
              : '${username.trim()}@legacy.mizapos')
          : existingEmail;
      final nextUsername = username ?? existingUsername;
      await _assertOwnerRoleMatchesSubscriptionEmail(
        db,
        s.organizationId,
        nextEmail,
        nextUsername,
      );
    }
    await _assertSignupSubscriberDoesNotManagePeer(targetUserId: userId);
    if (userId == LicenseGate.guestUserId) {
      throw Exception('لا يمكن تعديل حساب الزائر.');
    }
    if (username != null) {
      final nu = username.trim();
      final clash = await db.rawQuery(
        'SELECT id FROM users WHERE organizationId = ? AND id != ? '
        'AND username = ? COLLATE NOCASE',
        [s.organizationId, userId, nu],
      );
      if (clash.isNotEmpty) {
        throw Exception('اسم الدخول محجوز مسبقاً.');
      }
    }
    final patch = <String, Object?>{};
    if (fullName != null) patch['fullName'] = fullName.trim();
    if (username != null) patch['username'] = username.trim();
    if (password != null && password.isNotEmpty) {
      patch['password'] = PasswordCrypto.hash(password);
    }
    if (role != null) patch['role'] = role;
    if (dialCode != null) {
      patch['dialCode'] =
          dialCode.trim().isEmpty ? '+970' : dialCode.trim();
    }
    if (phoneNational != null) {
      patch['phone'] = _normalizePhoneDigits(phoneNational);
    }
    if (distributorCloudEnabled != null) {
      final effectiveRole =
          (role ?? existingRole).trim().toLowerCase();
      patch['distributorCloudEnabled'] =
          effectiveRole == 'distributor' && distributorCloudEnabled ? 1 : 0;
    } else if (role != null && role.trim().toLowerCase() != 'distributor') {
      patch['distributorCloudEnabled'] = 0;
    }
    if (patch.isEmpty) return;
    await db.update(
      'users',
      patch,
      where: 'id = ? AND organizationId = ?',
      whereArgs: [userId, s.organizationId],
    );
    await _audit('update', 'user', userId, 'Updated user $userId');
    final updatedRow = await db.query(
      'users',
      where: 'id = ? AND organizationId = ?',
      whereArgs: [userId, s.organizationId],
      limit: 1,
    );
    if (updatedRow.isNotEmpty) {
      if (TeamUsersSyncService.isEligibleTeamUserRow(updatedRow.first)) {
        _pushTeamUserToCloudFireAndForget(updatedRow.first);
      }
    }
    if (RemoteSignupConfig.activationServerEnabled) {
      final updated = await db.query(
        'users',
        columns: [
          'email',
          'fullName',
          'phone',
          'dialCode',
          'password',
          'fromSignupRequestId',
        ],
        where: 'id = ? AND organizationId = ?',
        whereArgs: [userId, s.organizationId],
        limit: 1,
      );
      if (updated.isNotEmpty) {
        final signupOrigin =
            (updated.first['fromSignupRequestId'] as String?)?.trim() ?? '';
        if (signupOrigin.isEmpty) {
          return;
        }
        final pwdSent = patch.containsKey('password')
            ? (updated.first['password'] as String?)?.trim()
            : null;
        _pushRemoteSignupSyncUserRow(
          organizationId: s.organizationId,
          row: updated.first,
          passwordBcryptHash:
              (pwdSent != null && PasswordCrypto.looksLikeBcrypt(pwdSent))
                  ? pwdSent
                  : null,
        );
      }
    }
  }

  void _pushRemoteSignupSyncUserRow({
    required String organizationId,
    required Map<String, Object?> row,
    String? passwordBcryptHash,
  }) {
    if (!RemoteSignupConfig.activationServerEnabled) return;
    final rawEmail = (row['email'] as String?) ?? '';
    final em = rawEmail.trim().toLowerCase();
    if (!em.contains('@')) return;
    unawaited(
      RemoteSignupApi(
        baseUrl: RemoteSignupConfig.apiBaseUrl,
        sharedSecret: RemoteSignupConfig.sharedSecret,
      ).syncSignupProfile(
        organizationId: organizationId,
        email: em,
        fullName: (row['fullName'] as String?)?.trim(),
        phoneDigits: (row['phone'] as String?) ?? '',
        dialCode: (row['dialCode'] as String?)?.trim(),
        passwordBcryptHash: passwordBcryptHash,
      ),
    );
  }

  void _pushRemoteSignupDeleteForEmail({
    required String organizationId,
    required String? email,
  }) {
    if (!RemoteSignupConfig.activationServerEnabled) return;
    final em = (email ?? '').trim().toLowerCase();
    if (!em.contains('@')) return;
    unawaited(
      RemoteSignupApi(
        baseUrl: RemoteSignupConfig.apiBaseUrl,
        sharedSecret: RemoteSignupConfig.sharedSecret,
      ).deleteSignupAccount(organizationId: organizationId, email: em),
    );
  }

  Future<void> deleteUser(String userId) async {
    final s = _mustSession();
    _requireStaffAdminRole();
    _requirePaidSubscription();
    if (userId == LicenseGate.guestUserId) {
      throw Exception('لا يمكن حذف حساب الزائر.');
    }
    if (userId == s.userId) {
      throw Exception('لا يمكن حذف الحساب الحالي.');
    }
    final db = await _databaseService.database;
    final rows = await db.query(
      'users',
      where: 'id = ? AND organizationId = ?',
      whereArgs: [userId, s.organizationId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw Exception('الحساب غير موجود.');
    }
    if ((rows.first['role'] as String?) == 'owner') {
      throw Exception('لا يمكن حذف مالك النظام.');
    }
    await _assertSignupSubscriberDoesNotManagePeer(targetUserId: userId);
    final deletedEmail = rows.first['email'] as String?;
    final signupOrigin = (rows.first['fromSignupRequestId'] as String?)?.trim();
    final wasTeamCloudUser = TeamUsersSyncService.isEligibleTeamUserRow(rows.first);
    await db.delete(
      'users',
      where: 'id = ? AND organizationId = ?',
      whereArgs: [userId, s.organizationId],
    );
    await _audit('delete', 'user', userId, 'Deleted user $userId');
    if (wasTeamCloudUser) {
      _pushTeamUserDeleteToCloudFireAndForget(userId);
    }
    if (signupOrigin != null && signupOrigin.isNotEmpty) {
      _pushRemoteSignupDeleteForEmail(
        organizationId: s.organizationId,
        email: deletedEmail,
      );
    }
  }

  Future<List<Map<String, Object?>>> listMaster(String table) async {
    final s = _mustSession();
    final db = await _databaseService.database;
    return db.query(
      table,
      where: 'organizationId = ? AND branchId = ?',
      whereArgs: [s.organizationId, s.branchId],
      orderBy: 'name',
    );
  }

  Future<void> updateCustomer({
    required String id,
    required String name,
    String? customerNumber,
    String? phone,
    String? address,
    required double creditLimit,
    int? overdueAlertDays,
    String? notes,
  }) async {
    _mustSession();
    _requireRegisteredOperationalAccess();
    final db = await _databaseService.database;
    final s = _mustSession();
    final nm = name.trim();
    if (nm.isEmpty) {
      throw Exception('اسم العميل مطلوب.');
    }
    if (creditLimit < 0) {
      throw Exception('سقف العميل يجب أن يكون صفر أو أكبر.');
    }
    final cleanNotes = (notes ?? '').trim();
    final cn = customerNumber?.trim();
    await db.update(
      'customers',
      {
        'name': nm,
        'customerNumber': (cn == null || cn.isEmpty) ? null : cn,
        'phone': (phone == null || phone.trim().isEmpty) ? null : phone.trim(),
        'address': (address == null || address.trim().isEmpty) ? null : address.trim(),
        'creditLimit': creditLimit,
        'overdueAlertDays': overdueAlertDays,
        'notes': cleanNotes.isEmpty ? null : cleanNotes,
      },
      where: 'id = ? AND organizationId = ? AND branchId = ?',
      whereArgs: [id, s.organizationId, s.branchId],
    );
    await _audit('update', 'customers', id, 'Updated customer $nm');
    await _syncCatalogOutbox(
      entityType: PartnersSyncConstants.entityTypeCustomer,
      operation: 'update',
      entityId: id,
      payload: partnerEntityCloudPayload(
        id: id,
        organizationId: s.organizationId,
        branchId: s.branchId,
        name: nm,
        partnerNumber: cn,
        phone: phone?.trim(),
        address: address?.trim(),
        notes: cleanNotes.isEmpty ? null : cleanNotes,
        creditLimit: creditLimit,
        overdueAlertDays: overdueAlertDays,
      ),
    );
  }

  Future<void> deleteCustomer(String id) async {
    _mustSession();
    _requireRegisteredOperationalAccess();
    final s = _mustSession();
    final db = await _databaseService.database;
    final invCount = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM salesInvoices '
      'WHERE organizationId = ? AND branchId = ? AND customerId = ?',
      [s.organizationId, s.branchId, id],
    );
    final nInv = (invCount.first['c'] as num?)?.toInt() ?? 0;
    if (nInv > 0) {
      throw Exception('لا يمكن حذف عميل مرتبط بفواتير بيع.');
    }
    final ledCount = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM partnerLedger '
      'WHERE organizationId = ? AND branchId = ? AND partnerKind = ? AND partnerId = ?',
      [s.organizationId, s.branchId, 'customer', id],
    );
    final nLed = (ledCount.first['c'] as num?)?.toInt() ?? 0;
    if (nLed > 0) {
      throw Exception('لا يمكن حذف عميل له حركات في دفتر الذمم (أرصدة/دفعات).');
    }
    final rows = await db.query(
      'customers',
      where: 'id = ? AND organizationId = ? AND branchId = ?',
      whereArgs: [id, s.organizationId, s.branchId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw Exception('العميل غير موجود.');
    }
    final row = rows.first;
    await db.delete(
      'customers',
      where: 'id = ? AND organizationId = ? AND branchId = ?',
      whereArgs: [id, s.organizationId, s.branchId],
    );
    await _audit('delete', 'customers', id, 'Deleted customer $id');
    await _syncCatalogOutbox(
      entityType: PartnersSyncConstants.entityTypeCustomer,
      operation: 'delete',
      entityId: id,
      payload: partnerEntityCloudPayload(
        id: id,
        organizationId: s.organizationId,
        branchId: s.branchId,
        name: (row['name'] ?? '').toString(),
        partnerNumber: row['customerNumber']?.toString(),
        phone: row['phone']?.toString(),
        address: row['address']?.toString(),
        notes: row['notes']?.toString(),
        creditLimit: (row['creditLimit'] as num?)?.toDouble() ?? 0,
        overdueAlertDays: (row['overdueAlertDays'] as num?)?.toInt(),
        deleted: true,
      ),
    );
  }

  Future<void> updateSupplier({
    required String id,
    required String name,
    String? supplierNumber,
    String? phone,
    String? address,
    String? notes,
  }) async {
    _mustSession();
    _requireRegisteredOperationalAccess();
    final db = await _databaseService.database;
    final s = _mustSession();
    final nm = name.trim();
    if (nm.isEmpty) {
      throw Exception('اسم المورد مطلوب.');
    }
    final cleanNotes = (notes ?? '').trim();
    final sn = supplierNumber?.trim();
    await db.update(
      'suppliers',
      {
        'name': nm,
        'supplierNumber': (sn == null || sn.isEmpty) ? null : sn,
        'phone': (phone == null || phone.trim().isEmpty) ? null : phone.trim(),
        'address': (address == null || address.trim().isEmpty) ? null : address.trim(),
        'creditLimit': 0,
        'overdueAlertDays': null,
        'notes': cleanNotes.isEmpty ? null : cleanNotes,
      },
      where: 'id = ? AND organizationId = ? AND branchId = ?',
      whereArgs: [id, s.organizationId, s.branchId],
    );
    await _audit('update', 'suppliers', id, 'Updated supplier $nm');
    await _syncCatalogOutbox(
      entityType: PartnersSyncConstants.entityTypeSupplier,
      operation: 'update',
      entityId: id,
      payload: partnerEntityCloudPayload(
        id: id,
        organizationId: s.organizationId,
        branchId: s.branchId,
        name: nm,
        partnerNumber: sn,
        phone: phone?.trim(),
        address: address?.trim(),
        notes: cleanNotes.isEmpty ? null : cleanNotes,
      ),
    );
  }

  Future<void> deleteSupplier(String id) async {
    _mustSession();
    _requireRegisteredOperationalAccess();
    final s = _mustSession();
    final db = await _databaseService.database;
    final invCount = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM purchaseInvoices '
      'WHERE organizationId = ? AND branchId = ? AND supplierId = ?',
      [s.organizationId, s.branchId, id],
    );
    final nInv = (invCount.first['c'] as num?)?.toInt() ?? 0;
    if (nInv > 0) {
      throw Exception('لا يمكن حذف مورد مرتبط بفواتير شراء.');
    }
    final ledCount = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM partnerLedger '
      'WHERE organizationId = ? AND branchId = ? AND partnerKind = ? AND partnerId = ?',
      [s.organizationId, s.branchId, 'supplier', id],
    );
    final nLed = (ledCount.first['c'] as num?)?.toInt() ?? 0;
    if (nLed > 0) {
      throw Exception('لا يمكن حذف مورد له حركات في دفتر الذمم (أرصدة/دفعات).');
    }
    final rows = await db.query(
      'suppliers',
      where: 'id = ? AND organizationId = ? AND branchId = ?',
      whereArgs: [id, s.organizationId, s.branchId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw Exception('المورد غير موجود.');
    }
    final row = rows.first;
    await db.delete(
      'suppliers',
      where: 'id = ? AND organizationId = ? AND branchId = ?',
      whereArgs: [id, s.organizationId, s.branchId],
    );
    await _audit('delete', 'suppliers', id, 'Deleted supplier $id');
    await _syncCatalogOutbox(
      entityType: PartnersSyncConstants.entityTypeSupplier,
      operation: 'delete',
      entityId: id,
      payload: partnerEntityCloudPayload(
        id: id,
        organizationId: s.organizationId,
        branchId: s.branchId,
        name: (row['name'] ?? '').toString(),
        partnerNumber: row['supplierNumber']?.toString(),
        phone: row['phone']?.toString(),
        address: row['address']?.toString(),
        notes: row['notes']?.toString(),
        deleted: true,
      ),
    );
  }

  Future<void> addMaster(String table, MasterEntity entity) async {
    _mustSession();
    _requireRegisteredOperationalAccess();
    final db = await _databaseService.database;
    final numberColumn = table == 'customers'
        ? 'customerNumber'
        : table == 'suppliers'
            ? 'supplierNumber'
            : null;
    String? partnerNumber = entity.partnerNumber?.trim();
    if (numberColumn != null && (partnerNumber == null || partnerNumber.isEmpty)) {
      partnerNumber = await _generatePartnerNumber(table: table);
    }
    final cleanNotes = (entity.notes ?? entity.extra).trim();
    await db.insert(table, {
      'id': entity.id,
      'organizationId': entity.organizationId,
      'branchId': entity.branchId,
      'name': entity.name,
      'phone': entity.phone,
      'address': entity.address,
      if (numberColumn != null) numberColumn: partnerNumber,
      'creditLimit': entity.creditLimit,
      'overdueAlertDays': entity.overdueAlertDays,
      'notes': cleanNotes.isEmpty ? null : cleanNotes,
      'createdAt': DateTime.now().toIso8601String(),
    });
    await _audit('create', table, entity.id, 'Created ${entity.name}');
    if (table == 'customers') {
      await _syncCatalogOutbox(
        entityType: PartnersSyncConstants.entityTypeCustomer,
        operation: 'create',
        entityId: entity.id,
        payload: partnerEntityCloudPayload(
          id: entity.id,
          organizationId: entity.organizationId,
          branchId: entity.branchId,
          name: entity.name,
          partnerNumber: partnerNumber,
          phone: entity.phone,
          address: entity.address,
          notes: cleanNotes.isEmpty ? null : cleanNotes,
          creditLimit: entity.creditLimit,
          overdueAlertDays: entity.overdueAlertDays,
        ),
      );
    } else if (table == 'suppliers') {
      await _syncCatalogOutbox(
        entityType: PartnersSyncConstants.entityTypeSupplier,
        operation: 'create',
        entityId: entity.id,
        payload: partnerEntityCloudPayload(
          id: entity.id,
          organizationId: entity.organizationId,
          branchId: entity.branchId,
          name: entity.name,
          partnerNumber: partnerNumber,
          phone: entity.phone,
          address: entity.address,
          notes: cleanNotes.isEmpty ? null : cleanNotes,
        ),
      );
    }
  }

  Future<String> _generatePartnerNumber({required String table}) async {
    final s = _mustSession();
    final db = await _databaseService.database;
    final numberColumn = table == 'customers' ? 'customerNumber' : 'supplierNumber';
    final rows = await db.rawQuery(
      'SELECT $numberColumn FROM $table '
      'WHERE organizationId = ? AND branchId = ? '
      'AND $numberColumn IS NOT NULL AND TRIM($numberColumn) != \'\'',
      [s.organizationId, s.branchId],
    );
    var maxNumber = 0;
    for (final row in rows) {
      final value = (row[numberColumn] ?? '').toString();
      final match = RegExp(r'(\d+)').allMatches(value).toList();
      if (match.isEmpty) continue;
      final parsed = int.tryParse(match.last.group(1)!);
      if (parsed != null && parsed > maxNumber) {
        maxNumber = parsed;
      }
    }
    return (maxNumber + 1).toString();
  }

  Future<Map<String, List<Map<String, Object?>>>> _productSaleUnitsForIds(
    Database db,
    String organizationId,
    String branchId,
    List<String> productIds,
  ) async {
    if (productIds.isEmpty) return {};
    final placeholders = List.filled(productIds.length, '?').join(',');
    final rows = await db.rawQuery(
      'SELECT * FROM product_sale_units WHERE organizationId = ? AND branchId = ? '
      'AND productId IN ($placeholders) ORDER BY unitName COLLATE NOCASE ASC',
      [organizationId, branchId, ...productIds],
    );
    final out = <String, List<Map<String, Object?>>>{};
    for (final r in rows) {
      final pid = r['productId'] as String;
      out.putIfAbsent(pid, () => []).add(Map<String, Object?>.from(r));
    }
    return out;
  }

  /// وحدات البيع الإضافية لصنف (معامل التحويل إلى وحدة المخزون/السعر في المنتج).
  Future<List<Map<String, Object?>>> listProductSaleUnits(String productId) async {
    final s = _mustSession();
    final db = await _databaseService.database;
    return db.query(
      'product_sale_units',
      where: 'organizationId = ? AND branchId = ? AND productId = ?',
      whereArgs: [s.organizationId, s.branchId, productId],
      orderBy: 'unitName COLLATE NOCASE ASC',
    );
  }

  /// يستبدل كل وحدات البيع الإضافية للصنف (القائمة الفارغة تحذفها كلها).
  Future<void> replaceProductSaleUnits({
    required String productId,
    required List<ProductSaleUnitInput> units,
  }) async {
    if (units.isNotEmpty) {
      _requireManageProductsBasic();
    }
    _requireRegisteredOperationalAccess();
    final s = _mustSession();
    final db = await _databaseService.database;
    final rows = await db.query(
      'products',
      columns: const ['id', 'unitName'],
      where: 'id = ? AND organizationId = ? AND branchId = ?',
      whereArgs: [productId, s.organizationId, s.branchId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw Exception('الصنف غير موجود.');
    }
    final baseUnit = (rows.first['unitName'] ?? '').toString().trim();
    await db.transaction((txn) async {
      await txn.delete(
        'product_sale_units',
        where: 'productId = ? AND organizationId = ? AND branchId = ?',
        whereArgs: [productId, s.organizationId, s.branchId],
      );
      for (final u in units) {
        final name = u.unitName.trim();
        if (name.isEmpty) continue;
        if (baseUnit.isNotEmpty && name.toLowerCase() == baseUnit.toLowerCase()) {
          continue;
        }
        if (u.toBaseFactor <= 0 || u.toBaseFactor.isNaN || u.toBaseFactor.isInfinite) {
          throw Exception('معامل التحويل يجب أن يكون أكبر من صفر لوحدة: $name');
        }
        await txn.insert('product_sale_units', {
          'id': _uuid.v4(),
          'organizationId': s.organizationId,
          'branchId': s.branchId,
          'productId': productId,
          'unitName': name,
          'toBaseFactor': u.toBaseFactor,
          'createdAt': DateTime.now().toIso8601String(),
        });
      }
    });
    await _audit(
      'update',
      'product_sale_units',
      productId,
      'Replaced ${units.length} alternate sale units',
    );
  }

  /// [forSaleOrPurchasePicker]: يستبعد المخفي والمجمّد (شاشات البيع/الشراء والاستعلامات).
  /// كل عنصر يتضمن المفتاح [saleUnits] كقائمة من جدول وحدات البيع الإضافية.
  Future<List<Map<String, Object?>>> listProducts({
    bool forSaleOrPurchasePicker = false,
  }) async {
    final s = _mustSession();
    final db = await _databaseService.database;
    final where = forSaleOrPurchasePicker
        ? 'organizationId = ? AND branchId = ? AND IFNULL(isHidden,0) = 0 AND IFNULL(isFrozen,0) = 0'
        : 'organizationId = ? AND branchId = ?';
    final maps = await db.query(
      'products',
      where: where,
      whereArgs: [s.organizationId, s.branchId],
      orderBy: 'sortOrder ASC, name COLLATE NOCASE ASC',
    );
    // #region agent log
    DebugSessionLog.write(
      location: 'accounting_service.dart:listProducts',
      message: 'products listed for session scope',
      hypothesisId: 'H1-org-scope',
      runId: 'post-fix',
      data: {
        'organizationId': s.organizationId,
        'branchId': s.branchId,
        'role': s.role,
        'returned': maps.length,
        'forSaleOrPurchasePicker': forSaleOrPurchasePicker,
      },
    );
    // #endregion
    final ids = maps.map((m) => m['id'] as String).toList();
    final grouped =
        await _productSaleUnitsForIds(db, s.organizationId, s.branchId, ids);
    // نسخ الصفوف: بعض إصدارات sqflite تعيد خرائط غير قابلة للتعديل،
    // وإضافة saleUnits على الأصل تُسبب استثناءً وتُبقي شاشة المعاملة في التحميل.
    return [
      for (final m in maps)
        Map<String, Object?>.from(m)
          ..['saleUnits'] = List<Map<String, Object?>>.from(
            grouped[m['id'] as String] ?? const <Map<String, Object?>>[],
          ),
    ];
  }

  /// أصناف محذوفة محفوظة للاسترجاع (المستودع ← سلة المحذوفات).
  Future<List<Map<String, Object?>>> listTrashedProducts() async {
    _requireProductTrashAccess();
    final s = _mustSession();
    final db = await _databaseService.database;
    return db.query(
      'product_trash',
      where: 'organizationId = ? AND branchId = ?',
      whereArgs: [s.organizationId, s.branchId],
      orderBy: 'deletedAt DESC',
    );
  }

  Future<int> _nextProductSortOrder(
    Database db,
    String organizationId,
    String branchId,
  ) async {
    final rows = await db.rawQuery(
      'SELECT COALESCE(MAX(sortOrder), -1) AS m FROM products '
      'WHERE organizationId = ? AND branchId = ?',
      [organizationId, branchId],
    );
    return ((rows.first['m'] as num?) ?? -1).toInt() + 1;
  }

  /// يحدّث ترتيب ظهور الأصناف في البحث والقوائم (حسب المستودع).
  Future<void> setProductDisplayOrder(List<String> orderedProductIds) async {
    _requireManageProductsBasic();
    _requireRegisteredOperationalAccess();
    final s = _mustSession();
    final db = await _databaseService.database;
    await db.transaction((txn) async {
      for (var i = 0; i < orderedProductIds.length; i++) {
        await txn.update(
          'products',
          {'sortOrder': i},
          where: 'id = ? AND organizationId = ? AND branchId = ?',
          whereArgs: [orderedProductIds[i], s.organizationId, s.branchId],
        );
      }
    });
    await _audit(
      'update',
      'product',
      'display_order',
      'Reordered ${orderedProductIds.length} products',
    );
  }

  Future<List<Map<String, Object?>>> listProductCategories() async {
    final s = _mustSession();
    final db = await _databaseService.database;
    return db.query(
      'product_categories',
      where: 'organizationId = ? AND branchId = ?',
      whereArgs: [s.organizationId, s.branchId],
      orderBy: 'name COLLATE NOCASE',
    );
  }

  Future<void> addProductCategory(String name) async {
    _requireManageProductsBasic();
    _requireRegisteredOperationalAccess();
    final s = _mustSession();
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw Exception('اسم التصنيف مطلوب.');
    }
    final db = await _databaseService.database;
    final id = _uuid.v4();
    try {
      await db.insert('product_categories', {
        'id': id,
        'organizationId': s.organizationId,
        'branchId': s.branchId,
        'name': trimmed,
        'createdAt': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      throw Exception(_translateDbError(e));
    }
    await _audit('create', 'product_category', id, 'Created category $trimmed');
    await _syncCatalogOutbox(
      entityType: CatalogSyncConstants.entityTypeProductCategory,
      operation: 'create',
      entityId: id,
      payload: namedEntityCloudPayload(
        id: id,
        organizationId: s.organizationId,
        branchId: s.branchId,
        name: trimmed,
      ),
    );
  }

  Future<void> updateProductCategoryName({
    required String categoryId,
    required String name,
  }) async {
    _requireManageProductsBasic();
    _requireRegisteredOperationalAccess();
    final s = _mustSession();
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw Exception('اسم التصنيف مطلوب.');
    }
    final db = await _databaseService.database;
    try {
      final n = await db.update(
        'product_categories',
        {'name': trimmed},
        where: 'id = ? AND organizationId = ? AND branchId = ?',
        whereArgs: [categoryId, s.organizationId, s.branchId],
      );
      if (n == 0) {
        throw Exception('التصنيف غير موجود.');
      }
    } catch (e) {
      if (e is DatabaseException) {
        throw Exception(_translateDbError(e));
      }
      rethrow;
    }
    await _audit('update', 'product_category', categoryId, 'Renamed category to $trimmed');
    await _syncCatalogOutbox(
      entityType: CatalogSyncConstants.entityTypeProductCategory,
      operation: 'update',
      entityId: categoryId,
      payload: namedEntityCloudPayload(
        id: categoryId,
        organizationId: s.organizationId,
        branchId: s.branchId,
        name: trimmed,
      ),
    );
  }

  Future<void> deleteProductCategory(String categoryId) async {
    _requireManageProductsBasic();
    _requireRegisteredOperationalAccess();
    final s = _mustSession();
    final db = await _databaseService.database;
    await db.transaction((txn) async {
      await txn.update(
        'products',
        {'categoryId': null},
        where: 'organizationId = ? AND branchId = ? AND categoryId = ?',
        whereArgs: [s.organizationId, s.branchId, categoryId],
      );
      final n = await txn.delete(
        'product_categories',
        where: 'id = ? AND organizationId = ? AND branchId = ?',
        whereArgs: [categoryId, s.organizationId, s.branchId],
      );
      if (n == 0) {
        throw Exception('التصنيف غير موجود.');
      }
    });
    await _audit('delete', 'product_category', categoryId, 'Deleted category');
    await _syncCatalogOutbox(
      entityType: CatalogSyncConstants.entityTypeProductCategory,
      operation: 'delete',
      entityId: categoryId,
      payload: namedEntityCloudPayload(
        id: categoryId,
        organizationId: s.organizationId,
        branchId: s.branchId,
        name: '',
        deleted: true,
      ),
    );
  }

  static const List<String> _defaultProductUnitNames = [
    'وقية',
    'كيلو',
    'علبة',
    'حبة',
    'لتر',
    'متر',
    'قطعة',
  ];

  Future<void> _ensureDefaultProductUnits({
    required Database db,
    required String organizationId,
    required String branchId,
  }) async {
    final c = await db.rawQuery(
      'SELECT COUNT(*) AS n FROM product_units '
      'WHERE organizationId = ? AND branchId = ?',
      [organizationId, branchId],
    );
    final n = (c.first['n'] as int?) ?? 0;
    if (n > 0) return;
    final now = DateTime.now().toIso8601String();
    for (final name in _defaultProductUnitNames) {
      await db.insert('product_units', {
        'id': _uuid.v4(),
        'organizationId': organizationId,
        'branchId': branchId,
        'name': name,
        'createdAt': now,
      });
    }
  }

  Future<List<Map<String, Object?>>> listProductUnits() async {
    final s = _mustSession();
    final db = await _databaseService.database;
    await _ensureDefaultProductUnits(
      db: db,
      organizationId: s.organizationId,
      branchId: s.branchId,
    );
    return db.query(
      'product_units',
      where: 'organizationId = ? AND branchId = ?',
      whereArgs: [s.organizationId, s.branchId],
      orderBy: 'name COLLATE NOCASE',
    );
  }

  Future<void> addProductUnit(String name) async {
    _requireManageProductsBasic();
    _requireRegisteredOperationalAccess();
    final s = _mustSession();
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw Exception('اسم الوحدة مطلوب.');
    }
    final db = await _databaseService.database;
    final id = _uuid.v4();
    try {
      await db.insert('product_units', {
        'id': id,
        'organizationId': s.organizationId,
        'branchId': s.branchId,
        'name': trimmed,
        'createdAt': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      throw Exception(_translateDbError(e));
    }
    await _audit('create', 'product_unit', id, 'Created unit $trimmed');
    await _syncCatalogOutbox(
      entityType: CatalogSyncConstants.entityTypeProductUnit,
      operation: 'create',
      entityId: id,
      payload: namedEntityCloudPayload(
        id: id,
        organizationId: s.organizationId,
        branchId: s.branchId,
        name: trimmed,
      ),
    );
  }

  Future<void> updateProductUnitName({
    required String unitId,
    required String name,
  }) async {
    _requireManageProductsBasic();
    _requireRegisteredOperationalAccess();
    final s = _mustSession();
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw Exception('اسم الوحدة مطلوب.');
    }
    final db = await _databaseService.database;
    final existing = await db.query(
      'product_units',
      where: 'id = ? AND organizationId = ? AND branchId = ?',
      whereArgs: [unitId, s.organizationId, s.branchId],
      limit: 1,
    );
    if (existing.isEmpty) {
      throw Exception('الوحدة غير موجودة.');
    }
    final oldName = (existing.first['name'] ?? '').toString().trim();
    try {
      await db.transaction((txn) async {
        final n = await txn.update(
          'product_units',
          {'name': trimmed},
          where: 'id = ? AND organizationId = ? AND branchId = ?',
          whereArgs: [unitId, s.organizationId, s.branchId],
        );
        if (n == 0) {
          throw Exception('الوحدة غير موجودة.');
        }
        if (oldName.isNotEmpty &&
            oldName.toLowerCase() != trimmed.toLowerCase()) {
          await txn.update(
            'products',
            {'unitName': trimmed},
            where:
                'organizationId = ? AND branchId = ? '
                'AND LOWER(TRIM(unitName)) = LOWER(?)',
            whereArgs: [s.organizationId, s.branchId, oldName],
          );
        }
      });
    } catch (e) {
      if (e is DatabaseException) {
        throw Exception(_translateDbError(e));
      }
      rethrow;
    }
    await _audit('update', 'product_unit', unitId, 'Renamed unit to $trimmed');
    await _syncCatalogOutbox(
      entityType: CatalogSyncConstants.entityTypeProductUnit,
      operation: 'update',
      entityId: unitId,
      payload: namedEntityCloudPayload(
        id: unitId,
        organizationId: s.organizationId,
        branchId: s.branchId,
        name: trimmed,
      ),
    );
  }

  Future<void> deleteProductUnit(String unitId) async {
    _requireManageProductsBasic();
    _requireRegisteredOperationalAccess();
    final s = _mustSession();
    final db = await _databaseService.database;
    final rows = await db.query(
      'product_units',
      where: 'id = ? AND organizationId = ? AND branchId = ?',
      whereArgs: [unitId, s.organizationId, s.branchId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw Exception('الوحدة غير موجودة.');
    }
    final unitName = (rows.first['name'] ?? '').toString().trim();
    await db.transaction((txn) async {
      await txn.update(
        'products',
        {'unitName': null},
        where:
            'organizationId = ? AND branchId = ? '
            'AND LOWER(TRIM(unitName)) = LOWER(?)',
        whereArgs: [s.organizationId, s.branchId, unitName],
      );
      final n = await txn.delete(
        'product_units',
        where: 'id = ? AND organizationId = ? AND branchId = ?',
        whereArgs: [unitId, s.organizationId, s.branchId],
      );
      if (n == 0) {
        throw Exception('الوحدة غير موجودة.');
      }
    });
    await _audit('delete', 'product_unit', unitId, 'Deleted unit');
    await _syncCatalogOutbox(
      entityType: CatalogSyncConstants.entityTypeProductUnit,
      operation: 'delete',
      entityId: unitId,
      payload: namedEntityCloudPayload(
        id: unitId,
        organizationId: s.organizationId,
        branchId: s.branchId,
        name: unitName,
        deleted: true,
      ),
    );
  }

  Future<List<Map<String, Object?>>> listTaxes() async {
    final s = _mustSession();
    final db = await _databaseService.database;
    return db.query(
      'taxes',
      where: 'organizationId = ? AND branchId = ?',
      whereArgs: [s.organizationId, s.branchId],
      orderBy: 'sortOrder, name COLLATE NOCASE',
    );
  }

  Future<void> addTax({
    required String name,
    required double percent,
    bool isDefault = false,
    int sortOrder = 0,
  }) async {
    _requireManageProductsBasic();
    _requireRegisteredOperationalAccess();
    final s = _mustSession();
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw Exception('اسم الضريبة مطلوب.');
    final db = await _databaseService.database;
    final id = _uuid.v4();
    await db.insert('taxes', {
      'id': id,
      'organizationId': s.organizationId,
      'branchId': s.branchId,
      'name': trimmed,
      'percent': percent,
      'isDefault': isDefault ? 1 : 0,
      'sortOrder': sortOrder,
      'createdAt': DateTime.now().toIso8601String(),
    });
    await _audit('create', 'tax', id, 'Created tax $trimmed');
    await _syncCatalogOutbox(
      entityType: CatalogSyncConstants.entityTypeTax,
      operation: 'create',
      entityId: id,
      payload: taxEntityCloudPayload(
        id: id,
        organizationId: s.organizationId,
        branchId: s.branchId,
        name: trimmed,
        percent: percent,
        isDefault: isDefault,
        sortOrder: sortOrder,
      ),
    );
  }

  Future<void> updateTax({
    required String taxId,
    required String name,
    required double percent,
    bool isDefault = false,
    int sortOrder = 0,
  }) async {
    _requireManageProductsBasic();
    _requireRegisteredOperationalAccess();
    final s = _mustSession();
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw Exception('اسم الضريبة مطلوب.');
    final db = await _databaseService.database;
    final n = await db.update(
      'taxes',
      {
        'name': trimmed,
        'percent': percent,
        'isDefault': isDefault ? 1 : 0,
        'sortOrder': sortOrder,
      },
      where: 'id = ? AND organizationId = ? AND branchId = ?',
      whereArgs: [taxId, s.organizationId, s.branchId],
    );
    if (n == 0) throw Exception('الضريبة غير موجودة.');
    await _audit('update', 'tax', taxId, 'Updated tax $trimmed');
    await _syncCatalogOutbox(
      entityType: CatalogSyncConstants.entityTypeTax,
      operation: 'update',
      entityId: taxId,
      payload: taxEntityCloudPayload(
        id: taxId,
        organizationId: s.organizationId,
        branchId: s.branchId,
        name: trimmed,
        percent: percent,
        isDefault: isDefault,
        sortOrder: sortOrder,
      ),
    );
  }

  Future<void> deleteTax(String taxId) async {
    _requireManageProductsBasic();
    _requireRegisteredOperationalAccess();
    final s = _mustSession();
    final db = await _databaseService.database;
    final n = await db.delete(
      'taxes',
      where: 'id = ? AND organizationId = ? AND branchId = ?',
      whereArgs: [taxId, s.organizationId, s.branchId],
    );
    if (n == 0) throw Exception('الضريبة غير موجودة.');
    await _audit('delete', 'tax', taxId, 'Deleted tax');
    await _syncCatalogOutbox(
      entityType: CatalogSyncConstants.entityTypeTax,
      operation: 'delete',
      entityId: taxId,
      payload: taxEntityCloudPayload(
        id: taxId,
        organizationId: s.organizationId,
        branchId: s.branchId,
        name: '',
        percent: 0,
        deleted: true,
      ),
    );
  }

  Future<List<Map<String, Object?>>> listPriceLists() async {
    final s = _mustSession();
    final db = await _databaseService.database;
    return db.query(
      'price_lists',
      where: 'organizationId = ? AND branchId = ?',
      whereArgs: [s.organizationId, s.branchId],
      orderBy: 'sortOrder, name COLLATE NOCASE',
    );
  }

  Future<List<Map<String, Object?>>> listPriceListItems(String priceListId) async {
    final s = _mustSession();
    final db = await _databaseService.database;
    return db.query(
      'price_list_items',
      where: 'organizationId = ? AND branchId = ? AND priceListId = ?',
      whereArgs: [s.organizationId, s.branchId, priceListId],
    );
  }

  Future<void> addPriceList({
    required String name,
    bool isDefault = false,
    int sortOrder = 0,
    List<Map<String, dynamic>> items = const [],
  }) async {
    _requireManageProductsBasic();
    _requireRegisteredOperationalAccess();
    final s = _mustSession();
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw Exception('اسم قائمة الأسعار مطلوب.');
    final db = await _databaseService.database;
    final id = _uuid.v4();
    await db.transaction((txn) async {
      await txn.insert('price_lists', {
        'id': id,
        'organizationId': s.organizationId,
        'branchId': s.branchId,
        'name': trimmed,
        'isDefault': isDefault ? 1 : 0,
        'sortOrder': sortOrder,
        'createdAt': DateTime.now().toIso8601String(),
      });
      for (final item in items) {
        final productId = (item['productId'] ?? item['product_id'] ?? '').toString();
        if (productId.isEmpty) continue;
        await txn.insert('price_list_items', {
          'id': _uuid.v4(),
          'organizationId': s.organizationId,
          'branchId': s.branchId,
          'priceListId': id,
          'productId': productId,
          'salePrice': (item['salePrice'] as num?)?.toDouble() ??
              (item['sale_price'] as num?)?.toDouble() ??
              0,
          'createdAt': DateTime.now().toIso8601String(),
        });
      }
    });
    await _audit('create', 'price_list', id, 'Created price list $trimmed');
    await _syncPriceListOutbox(s, id, 'create');
  }

  Future<void> updatePriceList({
    required String priceListId,
    required String name,
    bool isDefault = false,
    int sortOrder = 0,
    List<Map<String, dynamic>> items = const [],
  }) async {
    _requireManageProductsBasic();
    _requireRegisteredOperationalAccess();
    final s = _mustSession();
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw Exception('اسم قائمة الأسعار مطلوب.');
    final db = await _databaseService.database;
    await db.transaction((txn) async {
      final n = await txn.update(
        'price_lists',
        {
          'name': trimmed,
          'isDefault': isDefault ? 1 : 0,
          'sortOrder': sortOrder,
        },
        where: 'id = ? AND organizationId = ? AND branchId = ?',
        whereArgs: [priceListId, s.organizationId, s.branchId],
      );
      if (n == 0) throw Exception('قائمة الأسعار غير موجودة.');
      await txn.delete(
        'price_list_items',
        where: 'priceListId = ?',
        whereArgs: [priceListId],
      );
      for (final item in items) {
        final productId = (item['productId'] ?? item['product_id'] ?? '').toString();
        if (productId.isEmpty) continue;
        await txn.insert('price_list_items', {
          'id': _uuid.v4(),
          'organizationId': s.organizationId,
          'branchId': s.branchId,
          'priceListId': priceListId,
          'productId': productId,
          'salePrice': (item['salePrice'] as num?)?.toDouble() ??
              (item['sale_price'] as num?)?.toDouble() ??
              0,
          'createdAt': DateTime.now().toIso8601String(),
        });
      }
    });
    await _audit('update', 'price_list', priceListId, 'Updated price list $trimmed');
    await _syncPriceListOutbox(s, priceListId, 'update');
  }

  Future<void> deletePriceList(String priceListId) async {
    _requireManageProductsBasic();
    _requireRegisteredOperationalAccess();
    final s = _mustSession();
    final db = await _databaseService.database;
    await db.transaction((txn) async {
      await txn.delete(
        'price_list_items',
        where: 'priceListId = ?',
        whereArgs: [priceListId],
      );
      final n = await txn.delete(
        'price_lists',
        where: 'id = ? AND organizationId = ? AND branchId = ?',
        whereArgs: [priceListId, s.organizationId, s.branchId],
      );
      if (n == 0) throw Exception('قائمة الأسعار غير موجودة.');
    });
    await _audit('delete', 'price_list', priceListId, 'Deleted price list');
    await _syncCatalogOutbox(
      entityType: CatalogSyncConstants.entityTypePriceList,
      operation: 'delete',
      entityId: priceListId,
      payload: priceListEntityCloudPayload(
        id: priceListId,
        organizationId: s.organizationId,
        branchId: s.branchId,
        name: '',
        deleted: true,
      ),
    );
  }

  Future<void> _syncPriceListOutbox(
    AppUserSession s,
    String priceListId,
    String operation,
  ) async {
    final db = await _databaseService.database;
    final header = await db.query(
      'price_lists',
      where: 'id = ?',
      whereArgs: [priceListId],
      limit: 1,
    );
    if (header.isEmpty) return;
    final row = header.first;
    final items = await db.query(
      'price_list_items',
      where: 'priceListId = ?',
      whereArgs: [priceListId],
    );
    final cloudItems = items
        .map(
          (item) => {
            'id': item['id'],
            'product_id': item['productId'],
            'sale_price': (item['salePrice'] as num?)?.toDouble() ?? 0,
          },
        )
        .toList();
    await _syncCatalogOutbox(
      entityType: CatalogSyncConstants.entityTypePriceList,
      operation: operation,
      entityId: priceListId,
      payload: priceListEntityCloudPayload(
        id: priceListId,
        organizationId: s.organizationId,
        branchId: s.branchId,
        name: (row['name'] ?? '').toString(),
        isDefault: ((row['isDefault'] as num?) ?? 0) != 0,
        sortOrder: (row['sortOrder'] as num?)?.toInt() ?? 0,
        items: cloudItems,
      ),
    );
  }

  static String _duplicateBarcodeMessage() =>
      'هذا الباركود مستخدم لصنف آخر في نفس الفرع.';

  Future<void> _assertBarcodeUniqueForBranch({
    required Database db,
    required String organizationId,
    required String branchId,
    required String? normalizedBarcode,
    String? excludeProductId,
  }) async {
    final bc = normalizedBarcode?.trim();
    if (bc == null || bc.isEmpty) return;
    final ex = excludeProductId?.trim();
    final rows = ex == null || ex.isEmpty
        ? await db.rawQuery(
            '''
      SELECT id FROM products
      WHERE organizationId = ? AND branchId = ?
        AND barcode IS NOT NULL AND TRIM(barcode) != ''
        AND LOWER(TRIM(barcode)) = LOWER(?)
      LIMIT 1
      ''',
            [organizationId, branchId, bc],
          )
        : await db.rawQuery(
            '''
      SELECT id FROM products
      WHERE organizationId = ? AND branchId = ?
        AND barcode IS NOT NULL AND TRIM(barcode) != ''
        AND LOWER(TRIM(barcode)) = LOWER(?)
        AND id != ?
      LIMIT 1
      ''',
            [organizationId, branchId, bc, ex],
          );
    if (rows.isNotEmpty) {
      throw _duplicateBarcodeMessage();
    }
  }

  Future<void> _assertCategoryBelongsToBranch({
    required Database db,
    required String organizationId,
    required String branchId,
    required String? categoryId,
  }) async {
    final id = categoryId?.trim();
    if (id == null || id.isEmpty) return;
    final rows = await db.query(
      'product_categories',
      columns: const ['id'],
      where: 'id = ? AND organizationId = ? AND branchId = ?',
      whereArgs: [id, organizationId, branchId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw 'التصنيف غير صالح أو لا يتبع هذا الفرع.';
    }
  }

  Future<void> addProduct(ProductEntity product) async {
    if (_voucherSubscriptionActiveOnDevice) {
      _requireManageProductsBasic();
      _requireRegisteredOperationalAccess();
    }
    final db = await _databaseService.database;
    final barcode =
        product.barcode?.trim().isEmpty ?? true ? null : product.barcode!.trim();
    await _assertBarcodeUniqueForBranch(
      db: db,
      organizationId: product.organizationId,
      branchId: product.branchId,
      normalizedBarcode: barcode,
    );
    final categoryId = product.categoryId?.trim();
    final categoryIdOrNull =
        (categoryId == null || categoryId.isEmpty) ? null : categoryId;
    final description = product.description?.trim();
    final unitName = product.unitName?.trim();
    final imagePath = product.imagePath?.trim();
    await _assertCategoryBelongsToBranch(
      db: db,
      organizationId: product.organizationId,
      branchId: product.branchId,
      categoryId: categoryIdOrNull,
    );
    try {
      final sortOrder = await _nextProductSortOrder(
        db,
        product.organizationId,
        product.branchId,
      );
      final initialStockQty =
          (!product.isService && product.stockQty > 1e-9) ? 0.0 : product.stockQty;
      await db.transaction((txn) async {
        await _requireCanAddCatalogProductInTxn(
          txn,
          product.organizationId,
          product.branchId,
        );
        await txn.insert('products', {
          'id': product.id,
          'organizationId': product.organizationId,
          'branchId': product.branchId,
          'name': product.name,
          'salePrice': product.salePrice,
          'costPrice': product.costPrice,
          'stockQty': initialStockQty,
          'barcode': barcode,
          'categoryId': categoryIdOrNull,
          'description':
              (description == null || description.isEmpty) ? null : description,
          'unitName': (unitName == null || unitName.isEmpty) ? null : unitName,
          'imagePath':
              (imagePath == null || imagePath.isEmpty) ? null : imagePath,
          'expiryDate': _productExpiryDayForSql(product.expiryDate),
          'isHidden': product.isHidden ? 1 : 0,
          'isFrozen': product.isFrozen ? 1 : 0,
          'isService': product.isService ? 1 : 0,
          'sortOrder': sortOrder,
          'createdAt': DateTime.now().toIso8601String(),
        });
      });
      if (!product.isService && product.stockQty > 1e-9) {
        await createOpeningStock(
          productId: product.id,
          openingQuantity: product.stockQty,
        );
      }
    } on ProductCatalogTrialLimitException {
      rethrow;
    } catch (e) {
      throw Exception(_translateDbError(e));
    }
    await _audit('create', 'product', product.id, 'Created ${product.name}');
    await _syncOutboxAfterProductChange('create', product.id, product: product);
  }

  Future<String> generateNextProductBarcode() async {
    final s = _mustSession();
    final db = await _databaseService.database;
    final rows = await db.rawQuery(
      'SELECT barcode FROM products '
      'WHERE organizationId = ? AND branchId = ? '
      'AND barcode IS NOT NULL AND TRIM(barcode) != \'\'',
      [s.organizationId, s.branchId],
    );
    var maxNumber = 100000000000;
    for (final row in rows) {
      final bc = (row['barcode'] ?? '').toString();
      final digitsOnly = bc.replaceAll(RegExp(r'[^0-9]'), '');
      if (digitsOnly.isEmpty) continue;
      final parsed = int.tryParse(digitsOnly);
      if (parsed != null && parsed > maxNumber) {
        maxNumber = parsed;
      }
    }
    return (maxNumber + 1).toString();
  }

  Future<void> updateProductPrices({
    required String productId,
    required double salePrice,
    required double costPrice,
  }) async {
    _requireEditProductPrices();
    _requireRegisteredOperationalAccess();
    final s = _mustSession();
    final db = await _databaseService.database;
    await db.update(
      'products',
      {
        'salePrice': salePrice,
        'costPrice': costPrice,
      },
      where: 'id = ? AND organizationId = ? AND branchId = ?',
      whereArgs: [productId, s.organizationId, s.branchId],
    );
    await _audit('update', 'product_price', productId, 'Updated product prices');
  }

  /// تعيين كمية المخزون الحالية للصنف (للمستودع — ليس عبر فاتورة).
  Future<void> setProductStockQuantity({
    required String productId,
    required double stockQty,
  }) async {
    _requireManageProductsBasic();
    _requireRegisteredOperationalAccess();
    if (stockQty < 0) {
      throw Exception('الكمية لا يمكن أن تكون سالبة.');
    }
    final s = _mustSession();
    final db = await _databaseService.database;
    final rows = await db.query(
      'products',
      columns: const ['isService', 'stockQty'],
      where: 'id = ? AND organizationId = ? AND branchId = ?',
      whereArgs: [productId, s.organizationId, s.branchId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw Exception('الصنف غير موجود.');
    }
    if ((((rows.first['isService'] as num?) ?? 0).toInt()) == 1) {
      throw Exception('أصناف الخدمة لا تحتفظ بكمية في المستودع.');
    }
    final currentQty = (rows.first['stockQty'] as num?)?.toDouble() ?? 0.0;
    if ((stockQty - currentQty).abs() < 1e-9) {
      return;
    }
    if (stockQty > currentQty) {
      await createOpeningStock(
        productId: productId,
        openingQuantity: stockQty - currentQty,
      );
    } else {
      await createInventoryAdjustment(
        productId: productId,
        quantityDelta: stockQty - currentQty,
        adjustmentReason: 'correction',
      );
    }
    await _audit(
      'update',
      'product',
      productId,
      'Set stock quantity to $stockQty',
    );
  }

  /// تعديل كمية المخزون بزيادة أو نقصان (قيمة موجبة أو سالبة).
  Future<String> adjustProductStockDelta({
    required String productId,
    required double delta,
  }) async {
    return createInventoryAdjustment(
      productId: productId,
      quantityDelta: delta,
      adjustmentReason: 'correction',
    );
  }

  /// تسجيل تعديل مخزون عبر مسار المزامنة (زيادة/نقصان موقّع).
  Future<String> createInventoryAdjustment({
    required String productId,
    required double quantityDelta,
    required String adjustmentReason,
    String notes = '',
    DateTime? adjustmentDate,
  }) async {
    _requireManageProductsBasic();
    _requireRegisteredOperationalAccess();
    if (quantityDelta.abs() < 1e-9) {
      throw Exception('كمية التعديل يجب أن تكون غير صفرية.');
    }
    final s = _mustSession();
    final db = await _databaseService.database;
    final rows = await db.query(
      'products',
      columns: const ['isService'],
      where: 'id = ? AND organizationId = ? AND branchId = ?',
      whereArgs: [productId, s.organizationId, s.branchId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw Exception('الصنف غير موجود.');
    }
    if ((((rows.first['isService'] as num?) ?? 0).toInt()) == 1) {
      throw Exception('أصناف الخدمة لا تحتفظ بكمية في المستودع.');
    }
    final reason = adjustmentReason.trim().toLowerCase();
    const allowed = {
      'count',
      'damage',
      'loss',
      'gain',
      'correction',
    };
    if (!allowed.contains(reason)) {
      throw Exception('سبب التعديل غير صالح.');
    }
    final adjustmentId = _uuid.v4();
    final when = adjustmentDate ?? DateTime.now();
    final postResult = await TransactionInventoryAdjustmentSyncService(
      databaseService: _databaseService,
    ).createInventoryAdjustmentDraftAndPost(
      adjustmentId: adjustmentId,
      organizationId: s.organizationId,
      branchId: s.branchId,
      userId: s.userId,
      productId: productId,
      quantityDelta: quantityDelta,
      adjustmentReason: reason,
      adjustmentDate: when,
      notes: notes.isEmpty ? null : notes,
    );
    if (!postResult.ok) {
      throw Exception(transactionInventoryAdjustmentPostFailureMessage(postResult));
    }
    await _audit(
      'create',
      'inventory_adjustment',
      adjustmentId,
      'Stock adjustment delta $quantityDelta ($reason)',
    );
    return adjustmentId;
  }

  /// تسجيل رصيد افتتاحي للمخزون عبر مسار المزامنة (كمية موجبة فقط).
  Future<String> createOpeningStock({
    required String productId,
    required double openingQuantity,
    String notes = '',
    DateTime? openingDate,
  }) async {
    _requireManageProductsBasic();
    _requireRegisteredOperationalAccess();
    if (openingQuantity < 1e-9) {
      throw Exception('كمية الرصيد الافتتاحي يجب أن تكون موجبة.');
    }
    final s = _mustSession();
    final db = await _databaseService.database;
    final rows = await db.query(
      'products',
      columns: const ['isService'],
      where: 'id = ? AND organizationId = ? AND branchId = ?',
      whereArgs: [productId, s.organizationId, s.branchId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw Exception('الصنف غير موجود.');
    }
    if ((((rows.first['isService'] as num?) ?? 0).toInt()) == 1) {
      throw Exception('أصناف الخدمة لا تحتفظ بكمية في المستودع.');
    }
    final openingStockId = _uuid.v4();
    final when = openingDate ?? DateTime.now();
    final postResult = await TransactionOpeningStockSyncService(
      databaseService: _databaseService,
    ).createOpeningStockDraftAndPost(
      openingStockId: openingStockId,
      organizationId: s.organizationId,
      branchId: s.branchId,
      userId: s.userId,
      productId: productId,
      openingQuantity: openingQuantity,
      openingDate: when,
      notes: notes.isEmpty ? null : notes,
    );
    if (!postResult.ok) {
      throw Exception(transactionOpeningStockPostFailureMessage(postResult));
    }
    await _audit(
      'create',
      'opening_stock',
      openingStockId,
      'Opening stock quantity $openingQuantity',
    );
    return openingStockId;
  }

  Future<void> setProductBarcode({
    required String productId,
    String? barcode,
  }) async {
    _requireManageProductsBasic();
    _requireRegisteredOperationalAccess();
    final s = _mustSession();
    final db = await _databaseService.database;
    final raw = barcode?.trim();
    final bcOrNull = (raw == null || raw.isEmpty) ? null : raw;
    await _assertBarcodeUniqueForBranch(
      db: db,
      organizationId: s.organizationId,
      branchId: s.branchId,
      normalizedBarcode: bcOrNull,
      excludeProductId: productId,
    );
    final n = await db.update(
      'products',
      {'barcode': bcOrNull},
      where: 'id = ? AND organizationId = ? AND branchId = ?',
      whereArgs: [productId, s.organizationId, s.branchId],
    );
    if (n == 0) {
      throw Exception('الصنف غير موجود.');
    }
    await _audit(
      'update',
      'product',
      productId,
      bcOrNull == null ? 'Cleared product barcode' : 'Set product barcode',
    );
  }

  Future<void> setProductHidden({
    required String productId,
    required bool isHidden,
  }) async {
    _requireManageProductsBasic();
    _requireRegisteredOperationalAccess();
    final s = _mustSession();
    final db = await _databaseService.database;
    await db.update(
      'products',
      {'isHidden': isHidden ? 1 : 0},
      where: 'id = ? AND organizationId = ? AND branchId = ?',
      whereArgs: [productId, s.organizationId, s.branchId],
    );
    await _audit(
      'update',
      'product',
      productId,
      isHidden ? 'Set product hidden' : 'Set product visible',
    );
  }

  Future<void> setProductFrozen({
    required String productId,
    required bool isFrozen,
  }) async {
    _requireManageProductsBasic();
    _requireRegisteredOperationalAccess();
    final s = _mustSession();
    final db = await _databaseService.database;
    await db.update(
      'products',
      {'isFrozen': isFrozen ? 1 : 0},
      where: 'id = ? AND organizationId = ? AND branchId = ?',
      whereArgs: [productId, s.organizationId, s.branchId],
    );
    await _audit(
      'update',
      'product',
      productId,
      isFrozen ? 'Set product frozen' : 'Set product unfrozen',
    );
  }

  Future<void> setProductFavorite({
    required String productId,
    required bool isFavorite,
  }) async {
    _requireRegisteredOperationalAccess();
    final s = _mustSession();
    final db = await _databaseService.database;
    await db.update(
      'products',
      {'isFavorite': isFavorite ? 1 : 0},
      where: 'id = ? AND organizationId = ? AND branchId = ?',
      whereArgs: [productId, s.organizationId, s.branchId],
    );
    await _audit(
      'update',
      'product',
      productId,
      isFavorite ? 'Set product favorite' : 'Unset product favorite',
    );
  }

  /// تحديث كامل لبيانات الصنف (المستودع).
  Future<void> updateProductDetails({
    required String productId,
    required String name,
    required double salePrice,
    required double costPrice,
    required double stockQty,
    String? barcode,
    String? categoryId,
    String? description,
    String? unitName,
    String? imagePath,
    required bool isService,
    required bool isHidden,
    required bool isFrozen,
    DateTime? expiryDate,
  }) async {
    _requireManageProductsBasic();
    _requireRegisteredOperationalAccess();
    final s = _mustSession();
    final db = await _databaseService.database;
    final bcRaw = barcode?.trim();
    final bcOrNull =
        (bcRaw == null || bcRaw.isEmpty) ? null : bcRaw;
    await _assertBarcodeUniqueForBranch(
      db: db,
      organizationId: s.organizationId,
      branchId: s.branchId,
      normalizedBarcode: bcOrNull,
      excludeProductId: productId,
    );
    final cid = categoryId?.trim();
    final cidOrNull = (cid == null || cid.isEmpty) ? null : cid;
    await _assertCategoryBelongsToBranch(
      db: db,
      organizationId: s.organizationId,
      branchId: s.branchId,
      categoryId: cidOrNull,
    );
    final desc = description?.trim();
    final unit = unitName?.trim();
    final img = imagePath?.trim();
    final rows = await db.query(
      'products',
      columns: const ['isService'],
      where: 'id = ? AND organizationId = ? AND branchId = ?',
      whereArgs: [productId, s.organizationId, s.branchId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw Exception('الصنف غير موجود.');
    }
    final wasService =
        (((rows.first['isService'] as num?) ?? 0).toInt()) == 1;
    final nowService = isService;
    var qty = stockQty;
    if (nowService) {
      qty = 0;
    } else if (qty < 0) {
      throw Exception('الكمية لا يمكن أن تكون سالبة.');
    }
    final n = await db.update(
      'products',
      {
        'name': name.trim(),
        'salePrice': salePrice,
        'costPrice': costPrice,
        'stockQty': qty,
        'barcode': bcOrNull,
        'categoryId': cidOrNull,
        'description': (desc == null || desc.isEmpty) ? null : desc,
        'unitName': (unit == null || unit.isEmpty) ? null : unit,
        'imagePath': (img == null || img.isEmpty) ? null : img,
        'expiryDate': _productExpiryDayForSql(expiryDate),
        'isService': nowService ? 1 : 0,
        'isHidden': isHidden ? 1 : 0,
        'isFrozen': isFrozen ? 1 : 0,
      },
      where: 'id = ? AND organizationId = ? AND branchId = ?',
      whereArgs: [productId, s.organizationId, s.branchId],
    );
    if (n == 0) {
      throw Exception('الصنف غير موجود.');
    }
    await _audit(
      'update',
      'product',
      productId,
      'Updated product details${wasService != nowService ? ' (service toggled)' : ''}',
    );
    await _syncOutboxAfterProductChange('update', productId);
  }

  Future<void> setProductCategory({
    required String productId,
    required String? categoryId,
  }) async {
    _requireManageProductsBasic();
    _requireRegisteredOperationalAccess();
    final s = _mustSession();
    final db = await _databaseService.database;
    final cid = categoryId?.trim();
    final cidOrNull = (cid == null || cid.isEmpty) ? null : cid;
    await _assertCategoryBelongsToBranch(
      db: db,
      organizationId: s.organizationId,
      branchId: s.branchId,
      categoryId: cidOrNull,
    );
    final n = await db.update(
      'products',
      {'categoryId': cidOrNull},
      where: 'id = ? AND organizationId = ? AND branchId = ?',
      whereArgs: [productId, s.organizationId, s.branchId],
    );
    if (n == 0) {
      throw Exception('الصنف غير موجود.');
    }
    await _audit(
      'update',
      'product',
      productId,
      cidOrNull == null ? 'Cleared product category' : 'Set product category',
    );
  }

  /// عدد السجلات المرتبطة بالمنتج في الفواتير والمخزون (يمنع الحذف النهائي).
  Future<int> productTransactionalReferenceCount(String productId) async {
    _requireDeleteProducts();
    final db = await _databaseService.database;
    final row = await db.rawQuery(
      '''
      SELECT
        (SELECT COUNT(*) FROM salesInvoiceItems WHERE productId = ?) +
        (SELECT COUNT(*) FROM purchaseInvoiceItems WHERE productId = ?) +
        (SELECT COUNT(*) FROM salesReturnItems WHERE productId = ?) +
        (SELECT COUNT(*) FROM purchaseReturnItems WHERE productId = ?) +
        (SELECT COUNT(*) FROM stockMovements WHERE productId = ?) AS total
      ''',
      [productId, productId, productId, productId, productId],
    );
    return (row.first['total'] as num?)?.toInt() ?? 0;
  }

  /// حذف نهائي — من المستودع أو من السلة؛ مرفوض إن وُجدت فواتير/حركات مرتبطة.
  Future<void> permanentlyDeleteProduct(String productId) async {
    _requireDeleteProducts();
    _requireRegisteredOperationalAccess();
    final s = _mustSession();
    final refCount = await productTransactionalReferenceCount(productId);
    if (refCount > 0) {
      throw Exception(
        'لا يمكن حذف هذا المنتج نهائياً لأنه مرتبط بفواتير أو حركات مخزون ($refCount). '
        'يمكنك نقله إلى سلة المحذوفات لإخفائه فقط.',
      );
    }
    final db = await _databaseService.database;
    final active = await db.query(
      'products',
      where: 'id = ? AND organizationId = ? AND branchId = ?',
      whereArgs: [productId, s.organizationId, s.branchId],
      limit: 1,
    );
    final deleteSnapshot = active.isNotEmpty
        ? Map<String, Object?>.from(active.first)
        : null;
    final trashed = await db.query(
      'product_trash',
      where: 'id = ? AND organizationId = ? AND branchId = ?',
      whereArgs: [productId, s.organizationId, s.branchId],
      limit: 1,
    );
    if (active.isEmpty && trashed.isEmpty) {
      throw Exception('الصنف غير موجود.');
    }
    try {
      await db.transaction((txn) async {
        await txn.delete(
          'product_sale_units',
          where: 'productId = ?',
          whereArgs: [productId],
        );
        await txn.delete('products', where: 'id = ?', whereArgs: [productId]);
        await txn.delete('product_trash', where: 'id = ?', whereArgs: [productId]);
      });
    } catch (e) {
      throw Exception(_translateDbError(e));
    }
    await _audit('purge', 'product', productId, 'Permanently deleted product');
    if (deleteSnapshot != null) {
      await _syncOutboxAfterProductChange(
        'delete',
        productId,
        deletedSnapshot: deleteSnapshot,
      );
    }
  }

  Future<Map<String, Object?>> deleteProduct(String productId) async {
    if (_session == null) {
      throw Exception('يجب تسجيل الدخول أولاً.');
    }
    if (_isGuest && !_voucherSubscriptionActiveOnDevice) {
      throw Exception(
        'سلة المحذوفات والحذف يتطلبان قسيمة سارية على الجهاز أو دخول فريق العمل.',
      );
    }
    if (!canMoveProductToTrash()) {
      _requireMoveProductToTrash();
    }
    _requireRegisteredOperationalAccess();
    final s = _mustSession();
    final db = await _databaseService.database;
    final rows = await db.query(
      'products',
      where: 'id = ? AND organizationId = ? AND branchId = ?',
      whereArgs: [productId, s.organizationId, s.branchId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw Exception('الصنف غير موجود.');
    }
    final snapshot = Map<String, Object?>.from(rows.first);
    final trashRow = Map<String, Object?>.from(snapshot);
    trashRow['deletedAt'] = DateTime.now().toIso8601String();
    try {
      await db.transaction((txn) async {
        await txn.delete(
          'product_sale_units',
          where: 'productId = ?',
          whereArgs: [productId],
        );
        await txn.insert('product_trash', trashRow);
        await txn.delete('products', where: 'id = ?', whereArgs: [productId]);
      });
    } catch (e) {
      throw Exception(_translateDbError(e));
    }
    await _audit('delete', 'product', productId, 'Deleted product');
    await _syncOutboxAfterProductChange(
      'delete',
      productId,
      deletedSnapshot: snapshot,
    );
    return snapshot;
  }

  Future<void> restoreProduct(Map<String, Object?> snapshot) async {
    _requireProductTrashAccess();
    _requireRegisteredOperationalAccess();
    final id = (snapshot['id'] ?? '').toString();
    if (id.isEmpty) throw Exception('بيانات الاسترجاع غير صالحة.');
    final db = await _databaseService.database;
    final row = Map<String, Object?>.from(snapshot);
    row.remove('deletedAt');
    final org = (row['organizationId'] ?? '').toString();
    final br = (row['branchId'] ?? '').toString();
    final rawBc = row['barcode']?.toString();
    final barcode = (rawBc == null || rawBc.trim().isEmpty) ? null : rawBc.trim();
    await _assertBarcodeUniqueForBranch(
      db: db,
      organizationId: org,
      branchId: br,
      normalizedBarcode: barcode,
    );
    final snapCat = row['categoryId']?.toString().trim();
    final snapCatOrNull =
        (snapCat == null || snapCat.isEmpty) ? null : snapCat;
    await _assertCategoryBelongsToBranch(
      db: db,
      organizationId: org,
      branchId: br,
      categoryId: snapCatOrNull,
    );
    row['sortOrder'] = await _nextProductSortOrder(db, org, br);
    try {
      await db.transaction((txn) async {
        if (!_voucherSubscriptionActiveOnDevice) {
          await _requireCanAddCatalogProductInTxn(txn, org, br);
        }
        await txn.insert('products', row);
        await txn.delete('product_trash', where: 'id = ?', whereArgs: [id]);
      });
    } on ProductCatalogTrialLimitException {
      rethrow;
    } catch (e) {
      throw Exception(_translateDbError(e));
    }
    await _audit('restore', 'product', id, 'Restored product');
  }

  Future<void> upsertProductByName({
    required String name,
    required double salePrice,
    required double costPrice,
    double stockQty = 0,
    String? barcode,
    String? unitName,
  }) async {
    _requireBulkImportProducts();
    _requirePaidSubscription();
    final s = _mustSession();
    final db = await _databaseService.database;
    final bcRaw = barcode?.trim();
    final bcOrNull = (bcRaw == null || bcRaw.isEmpty) ? null : bcRaw;
    final unitRaw = unitName?.trim();
    final unitOrNull = (unitRaw == null || unitRaw.isEmpty) ? null : unitRaw;
    final existing = await db.query(
      'products',
      where: 'organizationId = ? AND branchId = ? AND LOWER(name) = LOWER(?)',
      whereArgs: [s.organizationId, s.branchId, name],
      limit: 1,
    );
    if (existing.isEmpty) {
      final id = _uuid.v4();
      await _assertBarcodeUniqueForBranch(
        db: db,
        organizationId: s.organizationId,
        branchId: s.branchId,
        normalizedBarcode: bcOrNull,
        excludeProductId: id,
      );
      final sortOrder = await _nextProductSortOrder(db, s.organizationId, s.branchId);
      await db.insert('products', {
        'id': id,
        'organizationId': s.organizationId,
        'branchId': s.branchId,
        'name': name,
        'salePrice': salePrice,
        'costPrice': costPrice,
        'stockQty': stockQty,
        'barcode': bcOrNull,
        'unitName': unitOrNull,
        'sortOrder': sortOrder,
        'createdAt': DateTime.now().toIso8601String(),
      });
      await _audit('create', 'product', id, 'Imported product $name');
      return;
    }
    final id = existing.first['id'] as String;
    final currentQty = ((existing.first['stockQty'] as num?) ?? 0).toDouble();
    if (bcOrNull != null) {
      await _assertBarcodeUniqueForBranch(
        db: db,
        organizationId: s.organizationId,
        branchId: s.branchId,
        normalizedBarcode: bcOrNull,
        excludeProductId: id,
      );
    }
    final patch = <String, Object?>{
      'salePrice': salePrice,
      'costPrice': costPrice,
      'stockQty': currentQty + stockQty,
    };
    if (bcOrNull != null) patch['barcode'] = bcOrNull;
    if (unitOrNull != null) patch['unitName'] = unitOrNull;
    await db.update(
      'products',
      patch,
      where: 'id = ?',
      whereArgs: [id],
    );
    await _audit('update', 'product', id, 'Imported update for product $name');
  }

  Future<String?> productIdByName(String name) async {
    if (name.trim().isEmpty) return null;
    final s = _mustSession();
    final db = await _databaseService.database;
    final rows = await db.query(
      'products',
      columns: ['id'],
      where:
          'organizationId = ? AND branchId = ? AND LOWER(TRIM(name)) = LOWER(TRIM(?))',
      whereArgs: [s.organizationId, s.branchId, name.trim()],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['id'] as String;
  }

  Future<String?> masterIdByName(String table, String name) async {
    if (name.trim().isEmpty) return null;
    final s = _mustSession();
    final db = await _databaseService.database;
    final rows = await db.query(
      table,
      columns: ['id'],
      where:
          'organizationId = ? AND branchId = ? AND LOWER(TRIM(name)) = LOWER(TRIM(?))',
      whereArgs: [s.organizationId, s.branchId, name.trim()],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['id'] as String;
  }

  Future<String?> findCustomerIdInBranch(String customerId) async {
    final id = customerId.trim();
    if (id.isEmpty) return null;
    final s = _mustSession();
    final db = await _databaseService.database;
    final rows = await db.query(
      'customers',
      columns: const ['id'],
      where: 'id = ? AND organizationId = ? AND branchId = ?',
      whereArgs: [id, s.organizationId, s.branchId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['id'] as String;
  }

  Future<String?> findProductIdInBranch({
    String? productId,
    String? barcode,
  }) async {
    final s = _mustSession();
    final db = await _databaseService.database;
    final pid = productId?.trim();
    if (pid != null && pid.isNotEmpty) {
      final rows = await db.query(
        'products',
        columns: const ['id'],
        where: 'id = ? AND organizationId = ? AND branchId = ?',
        whereArgs: [pid, s.organizationId, s.branchId],
        limit: 1,
      );
      if (rows.isNotEmpty) return rows.first['id'] as String;
    }
    final bc = barcode?.trim();
    if (bc != null && bc.isNotEmpty) {
      final rows = await db.rawQuery(
        '''
        SELECT id FROM products
        WHERE organizationId = ? AND branchId = ?
          AND barcode IS NOT NULL AND TRIM(barcode) != ''
          AND LOWER(TRIM(barcode)) = LOWER(?)
        LIMIT 1
        ''',
        [s.organizationId, s.branchId, bc],
      );
      if (rows.isNotEmpty) return rows.first['id'] as String;
    }
    return null;
  }

  Future<String> upsertCustomerByName({
    required String name,
    String? phone,
    String? address,
    String? partnerNumber,
    double creditLimit = 0,
  }) async {
    _requireBulkImportProducts();
    _requirePaidSubscription();
    final existing = await masterIdByName('customers', name);
    if (existing != null) return existing;
    final s = _mustSession();
    final id = _uuid.v4();
    final entity = MasterEntity(
      id: id,
      organizationId: s.organizationId,
      branchId: s.branchId,
      name: name.trim(),
      phone: phone?.trim().isEmpty == true ? null : phone?.trim(),
      address: address?.trim().isEmpty == true ? null : address?.trim(),
      partnerNumber:
          partnerNumber?.trim().isEmpty == true ? null : partnerNumber?.trim(),
      creditLimit: creditLimit,
    );
    await addMaster('customers', entity);
    return id;
  }

  Future<String> upsertSupplierByName({
    required String name,
    String? phone,
    String? address,
    String? partnerNumber,
    double creditLimit = 0,
  }) async {
    _requireBulkImportProducts();
    _requirePaidSubscription();
    final existing = await masterIdByName('suppliers', name);
    if (existing != null) return existing;
    final s = _mustSession();
    final id = _uuid.v4();
    final entity = MasterEntity(
      id: id,
      organizationId: s.organizationId,
      branchId: s.branchId,
      name: name.trim(),
      phone: phone?.trim().isEmpty == true ? null : phone?.trim(),
      address: address?.trim().isEmpty == true ? null : address?.trim(),
      partnerNumber:
          partnerNumber?.trim().isEmpty == true ? null : partnerNumber?.trim(),
      creditLimit: creditLimit,
    );
    await addMaster('suppliers', entity);
    return id;
  }

  /// مجاميع رأس الفاتورة: المجموع الفرعي للأسطر، الخصم المطبّق، الضريبة، الإجمالي النهائي.
  static Map<String, double> computeInvoiceHeaderAmounts({
    required List<InvoiceLineInput> lines,
    required double discountAmount,
    required double taxPercent,
  }) {
    final lineSubtotal =
        lines.fold<double>(0, (sum, l) => sum + l.quantity * l.unitPrice);
    final disc = discountAmount.clamp(0.0, lineSubtotal);
    final net = lineSubtotal - disc;
    final taxAmt = net * (taxPercent / 100.0);
    return {
      'lineSubtotal': lineSubtotal,
      'discount': disc,
      'taxAmount': taxAmt,
      'grandTotal': net + taxAmt,
    };
  }

  /// المبلغ المدفوع فعلياً (قد يتجاوز الإجمالي عند دفع زائد).
  static double invoicePaidAmountForDisplay(
    Map<String, Object?> invoice, {
    required double grandTotal,
  }) {
    final stored = (invoice['paidAmount'] as num?)?.toDouble();
    if (stored != null && stored > 1e-9) {
      return stored.clamp(0.0, double.infinity);
    }
    final pay = (invoice['paymentType'] ?? '').toString();
    if (MizaPaymentTypes.isDeferred(pay)) return 0.0;
    return grandTotal;
  }

  /// ما بقي على العميل دفعه (آجل أو ناقص دفع).
  static double invoiceRemainingForDisplay({
    required double grandTotal,
    required double paid,
  }) =>
      (grandTotal - paid).clamp(0.0, double.infinity);

  /// باقي نقدي يُرجع للعميل عند الدفع بأكثر من الإجمالي.
  static double invoiceChangeToCustomerForDisplay({
    required double grandTotal,
    required double paid,
  }) =>
      (paid - grandTotal).clamp(0.0, double.infinity);

  /// أجزاء دفع صالحة (مبلغ موجب، نوع معروف).
  static List<InvoicePaymentSplitInput> normalizePaymentSplits(
    List<InvoicePaymentSplitInput> raw,
  ) {
    final out = <InvoicePaymentSplitInput>[];
    for (final s in raw) {
      if (s.amount <= 1e-9) continue;
      out.add(InvoicePaymentSplitInput(
        paymentType: MizaPaymentTypes.normalize(s.paymentType),
        amount: s.amount,
      ));
    }
    return out;
  }

  /// ما دُفع فوراً (كل ما عدا «آجل»).
  static double immediatePaidFromSplits(List<InvoicePaymentSplitInput> splits) {
    var sum = 0.0;
    for (final s in splits) {
      if (!MizaPaymentTypes.isDeferred(s.paymentType)) {
        sum += s.amount;
      }
    }
    return sum;
  }

  static double totalAllocatedFromSplits(List<InvoicePaymentSplitInput> splits) =>
      splits.fold(0.0, (a, s) => a + s.amount);

  static String headerPaymentTypeFromSplits(List<InvoicePaymentSplitInput> splits) {
    if (splits.length > 1) return MizaPaymentTypes.split;
    if (splits.length == 1) return splits.first.paymentType;
    return MizaPaymentTypes.cash;
  }

  static bool splitNeedsPartnerLedger({
    required double grandTotal,
    required List<InvoicePaymentSplitInput> splits,
  }) {
    if (splits.isEmpty) return false;
    final paidNow = immediatePaidFromSplits(splits);
    final ar = invoiceRemainingForDisplay(grandTotal: grandTotal, paid: paidNow);
    if (ar > 1e-9) return true;
    for (final s in splits) {
      if (MizaPaymentTypes.isDeferred(s.paymentType)) return true;
    }
    return false;
  }

  /// هل سُجّل باقي الدفع الزائد كرصيد دائن للعميل على هذه الفاتورة؟
  Future<bool> saleInvoiceHasOverpayCredit(String invoiceId) async {
    final s = _mustSession();
    final db = await _databaseService.database;
    final rows = await db.query(
      'partnerLedger',
      columns: ['id'],
      where:
          'organizationId = ? AND branchId = ? AND partnerKind = ? '
          'AND referenceType = ? AND referenceId = ? AND entryType = ?',
      whereArgs: [
        s.organizationId,
        s.branchId,
        'customer',
        'sale',
        invoiceId,
        'sale_overpay_credit',
      ],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<void> _insertSaleOverpayCreditIfNeeded(
    dynamic txn, {
    required String? customerId,
    required String invoiceId,
    required double grandTotal,
    required double paid,
    required bool creditOverpayToCustomer,
    required DateTime entryDate,
  }) async {
    if (!creditOverpayToCustomer) return;
    final cid = customerId?.trim();
    if (cid == null || cid.isEmpty) return;
    final overpay = invoiceChangeToCustomerForDisplay(
      grandTotal: grandTotal,
      paid: paid,
    );
    if (overpay <= 1e-9) return;
    await _insertPartnerLedger(
      txn,
      partnerKind: 'customer',
      partnerId: cid,
      entryType: 'sale_overpay_credit',
      referenceType: 'sale',
      referenceId: invoiceId,
      amountSigned: -overpay,
      notes: 'باقي دفع زائد — رصيد دائن للعميل',
      entryDate: entryDate,
    );
  }

  static Future<bool> _txnCashMovementExistsForRef(
    Transaction txn, {
    required String organizationId,
    required String branchId,
    required String referenceType,
    required String referenceId,
  }) async {
    final rows = await txn.query(
      'cashTransactions',
      columns: ['id'],
      where:
          'organizationId = ? AND branchId = ? AND referenceType = ? AND referenceId = ?',
      whereArgs: [organizationId, branchId, referenceType, referenceId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<void> _deleteInvoicePaymentSplits(
    Transaction txn, {
    required String invoiceKind,
    required String invoiceId,
    required String organizationId,
    required String branchId,
  }) async {
    await txn.delete(
      'invoice_payment_splits',
      where:
          'organizationId = ? AND branchId = ? AND invoiceKind = ? AND invoiceId = ?',
      whereArgs: [organizationId, branchId, invoiceKind, invoiceId],
    );
  }

  Future<void> _insertInvoicePaymentSplits(
    Transaction txn, {
    required String invoiceKind,
    required String invoiceId,
    required String organizationId,
    required String branchId,
    required List<InvoicePaymentSplitInput> splits,
  }) async {
    for (var i = 0; i < splits.length; i++) {
      final s = splits[i];
      await txn.insert('invoice_payment_splits', {
        'id': _uuid.v4(),
        'organizationId': organizationId,
        'branchId': branchId,
        'invoiceKind': invoiceKind,
        'invoiceId': invoiceId,
        'paymentType': MizaPaymentTypes.normalize(s.paymentType),
        'amount': s.amount,
        'lineOrder': i,
      });
    }
  }

  Future<void> _postSplitCashMovements(
    Transaction txn, {
    required bool isSale,
    required String invoiceId,
    required List<InvoicePaymentSplitInput> splits,
    required bool recordCashBoxMovement,
    bool Function(String paymentType)? cashBoxFilterForPaymentType,
    String description = 'Invoice split payment',
    String updatedDescription = 'Invoice split payment (updated)',
    bool isUpdate = false,
  }) async {
    if (!recordCashBoxMovement || splits.isEmpty) return;
    final refType = isSale ? 'sale' : 'purchase';
    final cashType = isSale ? 'in' : 'out';
    final desc = isUpdate ? updatedDescription : description;
    for (final s in splits) {
      if (MizaPaymentTypes.isDeferred(s.paymentType) || s.amount <= 1e-9) {
        continue;
      }
      final shouldPost = cashBoxFilterForPaymentType?.call(s.paymentType) ??
          MizaPaymentTypes.postsToCashBox(s.paymentType);
      if (!shouldPost) continue;
      await _insertCash(txn, CashTransactionInput(
        type: cashType,
        amount: s.amount,
        description: desc,
        referenceType: refType,
        referenceId: invoiceId,
      ));
    }
  }

  Future<void> _postPartnerLedgerForInvoiceRemaining({
    required Transaction txn,
    required bool isSale,
    required String? partnerId,
    required String invoiceId,
    required double arRemaining,
    required DateTime entryDate,
    bool isUpdate = false,
  }) async {
    final pid = partnerId?.trim();
    if (pid == null || pid.isEmpty || arRemaining <= 1e-9) return;
    await _insertPartnerLedger(
      txn,
      partnerKind: isSale ? 'customer' : 'supplier',
      partnerId: pid,
      entryType: isSale ? 'sale_ar' : 'purchase_ap',
      referenceType: isSale ? 'sale' : 'purchase',
      referenceId: invoiceId,
      amountSigned: arRemaining,
      notes: isSale
          ? (isUpdate ? 'فاتورة بيع — متبقي (بعد التعديل)' : 'فاتورة بيع — متبقي')
          : (isUpdate ? 'فاتورة شراء — متبقي (بعد التعديل)' : 'فاتورة شراء — متبقي'),
      entryDate: entryDate,
    );
  }

  Future<List<InvoicePaymentSplitInput>> listInvoicePaymentSplits({
    required String invoiceKind,
    required String invoiceId,
  }) async {
    final s = _mustSession();
    final db = await _databaseService.database;
    final rows = await db.query(
      'invoice_payment_splits',
      where:
          'organizationId = ? AND branchId = ? AND invoiceKind = ? AND invoiceId = ?',
      whereArgs: [s.organizationId, s.branchId, invoiceKind, invoiceId],
      orderBy: 'lineOrder ASC',
    );
    return rows
        .map(
          (r) => InvoicePaymentSplitInput(
            paymentType: (r['paymentType'] ?? MizaPaymentTypes.cash).toString(),
            amount: ((r['amount'] as num?) ?? 0).toDouble(),
          ),
        )
        .toList();
  }

  Future<String> createPurchase({
    required String? supplierId,
    required List<InvoiceLineInput> lines,
    String paymentType = 'cash',
    DateTime? invoiceDate,
    double discountAmount = 0,
    double taxPercent = 0,
    String? notes,
    double? paidAmount,
    bool recordCashBoxMovement = true,
    List<InvoicePaymentSplitInput>? paymentSplits,
    bool Function(String paymentType)? cashBoxFilterForPaymentType,
  }) async {
    final s = _mustSession();
    if (!_isGuest) {
      _requireRegisteredOperationalAccess();
    }
    final db = await _databaseService.database;
    final invoiceId = _uuid.v4();
    final now = invoiceDate ?? DateTime.now();
    final am = AccountingService.computeInvoiceHeaderAmounts(
      lines: lines,
      discountAmount: discountAmount,
      taxPercent: taxPercent,
    );
    final lineSubtotal = am['lineSubtotal']!;
    final grandTotal = am['grandTotal']!;
    final disc = am['discount']!;
    final normalizedSplits =
        paymentSplits != null ? normalizePaymentSplits(paymentSplits) : null;
    final useSplits = normalizedSplits != null && normalizedSplits.isNotEmpty;
    final headerPay = useSplits
        ? headerPaymentTypeFromSplits(normalizedSplits)
        : MizaPaymentTypes.normalize(paymentType);
    final paid = useSplits
        ? immediatePaidFromSplits(normalizedSplits)
        : (paidAmount ?? grandTotal).clamp(0.0, double.infinity);
    final nNotes = notes?.trim();
    final syncLines = <({String lineId, String productId, double quantity, double unitCost})>[];
    for (final line in lines) {
      syncLines.add((
        lineId: _uuid.v4(),
        productId: line.productId,
        quantity: line.quantity,
        unitCost: line.unitPrice,
      ));
    }

    int? invoiceNumber;
    await db.transaction((txn) async {
      invoiceNumber = await _allocateInvoiceNumber(
        txn,
        'purchaseInvoices',
        s.organizationId,
        s.branchId,
      );
    });

    final postResult = await TransactionInvoiceSyncService(
      databaseService: _databaseService,
    ).createPurchaseDraftAndPost(
      invoiceId: invoiceId,
      organizationId: s.organizationId,
      branchId: s.branchId,
      userId: s.userId,
      supplierId: supplierId,
      invoiceDate: now,
      paymentType: headerPay,
      lineSubtotal: lineSubtotal,
      discountAmount: disc,
      taxPercent: taxPercent,
      total: grandTotal,
      paidAmount: paid,
      notes: (nNotes == null || nNotes.isEmpty) ? null : nNotes,
      invoiceNumber: invoiceNumber,
      lines: syncLines,
    );
    if (!postResult.ok) {
      throw Exception(transactionInvoicePostFailureMessage(postResult));
    }

    await db.transaction((txn) async {
      for (final line in lines) {
        await txn.rawUpdate(
          'UPDATE products SET costPrice = ? WHERE id = ?',
          [line.unitPrice, line.productId],
        );
      }
      if (useSplits) {
        await _insertInvoicePaymentSplits(
          txn,
          invoiceKind: 'purchase',
          invoiceId: invoiceId,
          organizationId: s.organizationId,
          branchId: s.branchId,
          splits: normalizedSplits,
        );
        await _postSplitCashMovements(
          txn,
          isSale: false,
          invoiceId: invoiceId,
          splits: normalizedSplits,
          recordCashBoxMovement: recordCashBoxMovement,
          cashBoxFilterForPaymentType: cashBoxFilterForPaymentType,
          description: 'Purchase invoice payment',
        );
      } else if (recordCashBoxMovement &&
          MizaPaymentTypes.postsToCashBox(paymentType) &&
          paid > 1e-9) {
        await _insertCash(txn, CashTransactionInput(
          type: 'out',
          amount: paid,
          description: 'Purchase invoice payment',
          referenceType: 'purchase',
          referenceId: invoiceId,
        ));
      }
    });
    await _audit('create', 'purchaseInvoice', invoiceId, 'Created purchase invoice');
    return invoiceId;
  }

  Future<void> updatePurchaseInvoice({
    required String invoiceId,
    required String? supplierId,
    required List<InvoiceLineInput> lines,
    String paymentType = 'cash',
    DateTime? invoiceDate,
    double discountAmount = 0,
    double taxPercent = 0,
    String? notes,
    double? paidAmount,
    bool recordCashBoxMovement = true,
    List<InvoicePaymentSplitInput>? paymentSplits,
    bool Function(String paymentType)? cashBoxFilterForPaymentType,
  }) async {
    _requireModifyInvoices();
    _requireRegisteredOperationalAccess();
    final s = _mustSession();
    final db = await _databaseService.database;
    final now = invoiceDate ?? DateTime.now();
    final am = AccountingService.computeInvoiceHeaderAmounts(
      lines: lines,
      discountAmount: discountAmount,
      taxPercent: taxPercent,
    );
    final lineSubtotal = am['lineSubtotal']!;
    final grandTotal = am['grandTotal']!;
    final disc = am['discount']!;
    final normalizedSplits =
        paymentSplits != null ? normalizePaymentSplits(paymentSplits) : null;
    final useSplits = normalizedSplits != null && normalizedSplits.isNotEmpty;
    final headerPay = useSplits
        ? headerPaymentTypeFromSplits(normalizedSplits)
        : MizaPaymentTypes.normalize(paymentType);
    final paid = useSplits
        ? immediatePaidFromSplits(normalizedSplits)
        : (paidAmount ?? grandTotal).clamp(0.0, double.infinity);
    final nNotes = notes?.trim();
    await db.transaction((txn) async {
      final invoiceRows = await txn.query(
        'purchaseInvoices',
        where: 'id = ? AND organizationId = ? AND branchId = ?',
        whereArgs: [invoiceId, s.organizationId, s.branchId],
        limit: 1,
      );
      if (invoiceRows.isEmpty) {
        throw Exception('الفاتورة غير موجودة أو لا يمكن تعديلها.');
      }
      if ((invoiceRows.first['invoiceStatus'] ?? 'posted').toString() == 'voided') {
        throw Exception('لا يمكن تعديل فاتورة ملغاة.');
      }

      await txn.delete(
        'partnerLedger',
        where: 'organizationId = ? AND branchId = ? AND referenceType = ? AND referenceId = ?',
        whereArgs: [s.organizationId, s.branchId, 'purchase', invoiceId],
      );

      final oldItems = await txn.query(
        'purchaseInvoiceItems',
        columns: ['productId', 'quantity'],
        where: 'invoiceId = ?',
        whereArgs: [invoiceId],
      );

      for (final item in oldItems) {
        final productId = item['productId'] as String;
        final qty = ((item['quantity'] as num?) ?? 0).toDouble();
        await txn.rawUpdate(
          'UPDATE products SET stockQty = stockQty - ? WHERE id = ?',
          [qty, productId],
        );
      }

      await txn.delete(
        'purchaseInvoiceItems',
        where: 'invoiceId = ?',
        whereArgs: [invoiceId],
      );
      await txn.delete(
        'stockMovements',
        where: 'organizationId = ? AND branchId = ? AND referenceType = ? AND referenceId = ?',
        whereArgs: [s.organizationId, s.branchId, 'purchase', invoiceId],
      );
      await txn.delete(
        'cashTransactions',
        where: 'organizationId = ? AND branchId = ? AND referenceType = ? AND referenceId = ?',
        whereArgs: [s.organizationId, s.branchId, 'purchase', invoiceId],
      );
      await _deleteInvoicePaymentSplits(
        txn,
        invoiceKind: 'purchase',
        invoiceId: invoiceId,
        organizationId: s.organizationId,
        branchId: s.branchId,
      );

      await txn.update(
        'purchaseInvoices',
        {
          'supplierId': supplierId,
          'invoiceDate': now.toIso8601String(),
          'total': grandTotal,
          'paymentType': headerPay,
          'invoiceStatus': 'posted',
          'notes': (nNotes == null || nNotes.isEmpty) ? null : nNotes,
          'discountAmount': disc,
          'taxPercent': taxPercent,
          'lineSubtotal': lineSubtotal,
          'totalsFormat': 1,
          'paidAmount': paid,
        },
        where: 'id = ?',
        whereArgs: [invoiceId],
      );

      for (final line in lines) {
        final lineId = _uuid.v4();
        final lineTotal = line.quantity * line.unitPrice;
        await txn.insert('purchaseInvoiceItems', {
          'id': lineId,
          'invoiceId': invoiceId,
          'productId': line.productId,
          'quantity': line.quantity,
          'unitCost': line.unitPrice,
          'lineTotal': lineTotal,
        });
        await txn.rawUpdate(
          'UPDATE products SET stockQty = stockQty + ?, costPrice = ? WHERE id = ?',
          [line.quantity, line.unitPrice, line.productId],
        );
        await txn.insert('stockMovements', {
          'id': _uuid.v4(),
          'organizationId': s.organizationId,
          'branchId': s.branchId,
          'productId': line.productId,
          'movementType': 'in',
          'quantity': line.quantity,
          'referenceType': 'purchase',
          'referenceId': invoiceId,
          'movementDate': now.toIso8601String(),
          'createdBy': s.userId,
        });
      }
      if (useSplits) {
        await _insertInvoicePaymentSplits(
          txn,
          invoiceKind: 'purchase',
          invoiceId: invoiceId,
          organizationId: s.organizationId,
          branchId: s.branchId,
          splits: normalizedSplits,
        );
        await _postSplitCashMovements(
          txn,
          isSale: false,
          invoiceId: invoiceId,
          splits: normalizedSplits,
          recordCashBoxMovement: recordCashBoxMovement,
          cashBoxFilterForPaymentType: cashBoxFilterForPaymentType,
          description: 'Purchase invoice payment',
          updatedDescription: 'Purchase invoice payment (updated)',
          isUpdate: true,
        );
      } else if (recordCashBoxMovement &&
          MizaPaymentTypes.postsToCashBox(paymentType) &&
          paid > 1e-9) {
        await _insertCash(txn, CashTransactionInput(
          type: 'out',
          amount: paid,
          description: 'Purchase invoice payment (updated)',
          referenceType: 'purchase',
          referenceId: invoiceId,
        ));
      }
      final sid = supplierId?.trim();
      final apRemaining = AccountingService.invoiceRemainingForDisplay(
        grandTotal: grandTotal,
        paid: paid,
      );
      if (useSplits) {
        await _postPartnerLedgerForInvoiceRemaining(
          txn: txn,
          isSale: false,
          partnerId: supplierId,
          invoiceId: invoiceId,
          arRemaining: apRemaining,
          entryDate: now,
          isUpdate: true,
        );
      } else if (MizaPaymentTypes.isDeferred(paymentType) &&
          sid != null &&
          sid.isNotEmpty &&
          apRemaining > 1e-9) {
        await _insertPartnerLedger(
          txn,
          partnerKind: 'supplier',
          partnerId: sid,
          entryType: 'purchase_ap',
          referenceType: 'purchase',
          referenceId: invoiceId,
          amountSigned: apRemaining,
          notes: 'فاتورة شراء آجل (بعد التعديل)',
          entryDate: now,
        );
      }
    });
    await _audit('update', 'purchaseInvoice', invoiceId, 'Updated purchase invoice');
  }

  Future<List<Map<String, Object?>>> listRecentPurchaseInvoices({int limit = 20}) async {
    final s = _mustSession();
    final db = await _databaseService.database;
    return db.rawQuery(
      'SELECT p.id, p.invoiceNumber, p.invoiceDate, p.total, p.paymentType, p.supplierId, s.name AS supplierName '
      'FROM purchaseInvoices p '
      'LEFT JOIN suppliers s ON s.id = p.supplierId '
      'WHERE p.organizationId = ? AND p.branchId = ? '
      'AND ${AccountingService._sqlInvoicePostedAlias('p')} '
      'ORDER BY p.invoiceDate DESC '
      'LIMIT ?',
      [s.organizationId, s.branchId, limit],
    );
  }

  Future<List<Map<String, Object?>>> purchaseInvoiceItemsForEdit(String invoiceId) async {
    final s = _mustSession();
    final db = await _databaseService.database;
    return db.rawQuery(
      'SELECT i.productId, p.name AS productName, i.quantity, i.unitCost AS unitPrice '
      'FROM purchaseInvoiceItems i '
      'JOIN purchaseInvoices h ON h.id = i.invoiceId '
      'LEFT JOIN products p ON p.id = i.productId '
      'WHERE i.invoiceId = ? AND h.organizationId = ? AND h.branchId = ?',
      [invoiceId, s.organizationId, s.branchId],
    );
  }

  Future<Map<String, Object?>> deletePurchaseInvoice(String invoiceId) async {
    _requireModifyInvoices();
    _requireRegisteredOperationalAccess();
    final s = _mustSession();
    final db = await _databaseService.database;
    final snapshot = <String, Object?>{};
    await db.transaction((txn) async {
      final invoiceRows = await txn.query(
        'purchaseInvoices',
        where: 'id = ? AND organizationId = ? AND branchId = ?',
        whereArgs: [invoiceId, s.organizationId, s.branchId],
        limit: 1,
      );
      if (invoiceRows.isEmpty) {
        throw Exception('الفاتورة غير موجودة أو لا يمكن حذفها.');
      }
      final invoiceRow = Map<String, Object?>.from(invoiceRows.first);

      final items = await txn.query(
        'purchaseInvoiceItems',
        where: 'invoiceId = ?',
        whereArgs: [invoiceId],
      );
      final stockRows = await txn.query(
        'stockMovements',
        where: 'organizationId = ? AND branchId = ? AND referenceType = ? AND referenceId = ?',
        whereArgs: [s.organizationId, s.branchId, 'purchase', invoiceId],
      );
      final cashRows = await txn.query(
        'cashTransactions',
        where: 'organizationId = ? AND branchId = ? AND referenceType = ? AND referenceId = ?',
        whereArgs: [s.organizationId, s.branchId, 'purchase', invoiceId],
      );
      snapshot['invoice'] = invoiceRow;
      snapshot['items'] = items.map((e) => Map<String, Object?>.from(e)).toList();
      snapshot['stockMovements'] = stockRows.map((e) => Map<String, Object?>.from(e)).toList();
      snapshot['cashTransactions'] = cashRows.map((e) => Map<String, Object?>.from(e)).toList();

      for (final item in items) {
        final productId = item['productId'] as String;
        final qty = ((item['quantity'] as num?) ?? 0).toDouble();
        await txn.rawUpdate(
          'UPDATE products SET stockQty = stockQty - ? WHERE id = ?',
          [qty, productId],
        );
      }

      await txn.delete(
        'purchaseInvoiceItems',
        where: 'invoiceId = ?',
        whereArgs: [invoiceId],
      );
      await txn.delete(
        'stockMovements',
        where: 'organizationId = ? AND branchId = ? AND referenceType = ? AND referenceId = ?',
        whereArgs: [s.organizationId, s.branchId, 'purchase', invoiceId],
      );
      await txn.delete(
        'cashTransactions',
        where: 'organizationId = ? AND branchId = ? AND referenceType = ? AND referenceId = ?',
        whereArgs: [s.organizationId, s.branchId, 'purchase', invoiceId],
      );
      await txn.delete(
        'partnerLedger',
        where: 'organizationId = ? AND branchId = ? AND referenceType = ? AND referenceId = ?',
        whereArgs: [s.organizationId, s.branchId, 'purchase', invoiceId],
      );
      await txn.delete(
        'purchaseInvoices',
        where: 'id = ?',
        whereArgs: [invoiceId],
      );
    });
    await _audit('delete', 'purchaseInvoice', invoiceId, 'Deleted purchase invoice');
    return snapshot;
  }

  Future<void> restoreDeletedPurchaseInvoice(Map<String, Object?> snapshot) async {
    _requireModifyInvoices();
    _requireRegisteredOperationalAccess();
    final s = _mustSession();
    final db = await _databaseService.database;
    final invoice = snapshot['invoice'];
    if (invoice is! Map<String, Object?>) {
      throw Exception('بيانات الاسترجاع غير صالحة.');
    }
    final invoiceId = (invoice['id'] ?? '').toString();
    if (invoiceId.isEmpty) {
      throw Exception('بيانات الفاتورة غير صالحة للاسترجاع.');
    }
    final items = (snapshot['items'] as List<dynamic>? ?? [])
        .cast<Map<String, Object?>>();
    final stockRows = (snapshot['stockMovements'] as List<dynamic>? ?? [])
        .cast<Map<String, Object?>>();
    final cashRows = (snapshot['cashTransactions'] as List<dynamic>? ?? [])
        .cast<Map<String, Object?>>();

    await db.transaction((txn) async {
      final existing = await txn.query(
        'purchaseInvoices',
        columns: ['id'],
        where: 'id = ? AND organizationId = ? AND branchId = ?',
        whereArgs: [invoiceId, s.organizationId, s.branchId],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        throw Exception('لا يمكن الاسترجاع لأن الفاتورة موجودة بالفعل.');
      }

      await txn.insert('purchaseInvoices', invoice);
      for (final item in items) {
        await txn.insert('purchaseInvoiceItems', item);
        final productId = item['productId'] as String;
        final qty = ((item['quantity'] as num?) ?? 0).toDouble();
        await txn.rawUpdate(
          'UPDATE products SET stockQty = stockQty + ? WHERE id = ?',
          [qty, productId],
        );
      }
      for (final row in stockRows) {
        await txn.insert('stockMovements', row);
      }
      for (final row in cashRows) {
        await txn.insert('cashTransactions', row);
      }
      final payType = (invoice['paymentType'] ?? '').toString();
      final supId = invoice['supplierId']?.toString().trim();
      final totInv = ((invoice['total'] as num?) ?? 0).toDouble();
      final dtInv =
          DateTime.tryParse((invoice['invoiceDate'] ?? '').toString()) ?? DateTime.now();
      if (MizaPaymentTypes.isDeferred(payType) &&
          supId != null &&
          supId.isNotEmpty &&
          totInv != 0) {
        await _insertPartnerLedger(
          txn,
          partnerKind: 'supplier',
          partnerId: supId,
          entryType: 'purchase_ap',
          referenceType: 'purchase',
          referenceId: invoiceId,
          amountSigned: totInv,
          notes: 'استرجاع فاتورة شراء محذوفة',
          entryDate: dtInv,
        );
      }
    });
    await _audit('restore', 'purchaseInvoice', invoiceId, 'Restored deleted purchase invoice');
  }

  Future<int> _allocateInvoiceNumber(
    DatabaseExecutor exec,
    String table,
    String organizationId,
    String branchId,
  ) async {
    final rows = await exec.rawQuery(
      'SELECT COALESCE(MAX(invoiceNumber), 0) + 1 AS n FROM $table '
      'WHERE organizationId = ? AND branchId = ?',
      [organizationId, branchId],
    );
    return (rows.first['n'] as num).toInt();
  }

  /// رقم الفاتورة المعروض (أرقام فقط) — من العمود `invoiceNumber`.
  Future<String> invoiceDisplayNumber({
    required String invoiceId,
    required bool isSale,
  }) async {
    final s = _mustSession();
    final db = await _databaseService.database;
    final table = isSale ? 'salesInvoices' : 'purchaseInvoices';
    final rows = await db.query(
      table,
      columns: ['invoiceNumber', 'id'],
      where: 'id = ? AND organizationId = ? AND branchId = ?',
      whereArgs: [invoiceId, s.organizationId, s.branchId],
      limit: 1,
    );
    if (rows.isEmpty) return '-';
    return InvoiceDisplayNumber.fromRow(rows.first);
  }

  static String displayInvoiceNumberFromRow(Map<String, Object?> row) =>
      InvoiceDisplayNumber.fromRow(row);

  Future<String> createSale({
    required String? customerId,
    required List<InvoiceLineInput> lines,
    String paymentType = 'cash',
    DateTime? invoiceDate,
    double discountAmount = 0,
    double taxPercent = 0,
    String? notes,
    double? paidAmount,
    bool recordCashBoxMovement = true,
    bool creditOverpayToCustomer = false,
    List<InvoicePaymentSplitInput>? paymentSplits,
    bool Function(String paymentType)? cashBoxFilterForPaymentType,
  }) async {
    final s = _mustSession();
    if (!_isGuest) {
      _requireRegisteredOperationalAccess();
    }
    final db = await _databaseService.database;
    final invoiceId = _uuid.v4();
    final now = invoiceDate ?? DateTime.now();
    final am = AccountingService.computeInvoiceHeaderAmounts(
      lines: lines,
      discountAmount: discountAmount,
      taxPercent: taxPercent,
    );
    final lineSubtotal = am['lineSubtotal']!;
    final grandTotal = am['grandTotal']!;
    final disc = am['discount']!;
    final normalizedSplits =
        paymentSplits != null ? normalizePaymentSplits(paymentSplits) : null;
    final useSplits = normalizedSplits != null && normalizedSplits.isNotEmpty;
    final headerPay = useSplits
        ? headerPaymentTypeFromSplits(normalizedSplits)
        : MizaPaymentTypes.normalize(paymentType);
    final paid = useSplits
        ? immediatePaidFromSplits(normalizedSplits)
        : (paidAmount ?? grandTotal).clamp(0.0, double.infinity);
    final nNotes = notes?.trim();
    final syncLines = <({String lineId, String productId, double quantity, double unitPrice})>[];
    for (final line in lines) {
      syncLines.add((
        lineId: _uuid.v4(),
        productId: line.productId,
        quantity: line.quantity,
        unitPrice: line.unitPrice,
      ));
    }

    int? invoiceNumber;
    await db.transaction((txn) async {
      invoiceNumber = await _allocateInvoiceNumber(
        txn,
        'salesInvoices',
        s.organizationId,
        s.branchId,
      );
    });

    final postResult = await TransactionInvoiceSyncService(
      databaseService: _databaseService,
    ).createSalesDraftAndPost(
      invoiceId: invoiceId,
      organizationId: s.organizationId,
      branchId: s.branchId,
      userId: s.userId,
      customerId: customerId,
      invoiceDate: now,
      paymentType: headerPay,
      lineSubtotal: lineSubtotal,
      discountAmount: disc,
      taxPercent: taxPercent,
      total: grandTotal,
      paidAmount: paid,
      notes: (nNotes == null || nNotes.isEmpty) ? null : nNotes,
      invoiceNumber: invoiceNumber,
      lines: syncLines,
    );
    if (!postResult.ok) {
      throw Exception(transactionInvoicePostFailureMessage(postResult));
    }

    await db.transaction((txn) async {
      if (useSplits) {
        await _insertInvoicePaymentSplits(
          txn,
          invoiceKind: 'sale',
          invoiceId: invoiceId,
          organizationId: s.organizationId,
          branchId: s.branchId,
          splits: normalizedSplits,
        );
        await _postSplitCashMovements(
          txn,
          isSale: true,
          invoiceId: invoiceId,
          splits: normalizedSplits,
          recordCashBoxMovement: recordCashBoxMovement,
          cashBoxFilterForPaymentType: cashBoxFilterForPaymentType,
          description: 'Sales invoice payment',
        );
      } else if (recordCashBoxMovement &&
          MizaPaymentTypes.postsToCashBox(paymentType) &&
          paid > 1e-9) {
        await _insertCash(txn, CashTransactionInput(
          type: 'in',
          amount: paid,
          description: 'Sales invoice payment',
          referenceType: 'sale',
          referenceId: invoiceId,
        ));
      }
      if (!useSplits) {
        await _insertSaleOverpayCreditIfNeeded(
          txn,
          customerId: customerId,
          invoiceId: invoiceId,
          grandTotal: grandTotal,
          paid: paid,
          creditOverpayToCustomer: creditOverpayToCustomer,
          entryDate: now,
        );
      }
    });
    await _audit('create', 'salesInvoice', invoiceId, 'Created sales invoice');
    return invoiceId;
  }

  /// عرض سعر — لا يخصم مخزوناً ولا يسجّل صندوقاً أو ذمة.
  Future<String> createPriceQuote({
    required String? customerId,
    required List<InvoiceLineInput> lines,
    DateTime? invoiceDate,
    double discountAmount = 0,
    double taxPercent = 0,
    String? notes,
  }) async {
    final s = _mustSession();
    if (!_isGuest) {
      _requireRegisteredOperationalAccess();
    }
    final db = await _databaseService.database;
    final invoiceId = _uuid.v4();
    final now = invoiceDate ?? DateTime.now();
    final am = AccountingService.computeInvoiceHeaderAmounts(
      lines: lines,
      discountAmount: discountAmount,
      taxPercent: taxPercent,
    );
    final lineSubtotal = am['lineSubtotal']!;
    final grandTotal = am['grandTotal']!;
    final disc = am['discount']!;
    final nNotes = notes?.trim();
    await db.transaction((txn) async {
      final invoiceNumber = await _allocateInvoiceNumber(
        txn,
        'salesInvoices',
        s.organizationId,
        s.branchId,
      );
      await txn.insert('salesInvoices', {
        'id': invoiceId,
        'organizationId': s.organizationId,
        'branchId': s.branchId,
        'customerId': customerId,
        'invoiceDate': now.toIso8601String(),
        'total': grandTotal,
        'paymentType': MizaPaymentTypes.cash,
        'invoiceStatus': 'quote',
        'createdBy': s.userId,
        'notes': (nNotes == null || nNotes.isEmpty) ? null : nNotes,
        'discountAmount': disc,
        'taxPercent': taxPercent,
        'lineSubtotal': lineSubtotal,
        'totalsFormat': 1,
        'paidAmount': 0,
        'invoiceNumber': invoiceNumber,
      });
      for (final line in lines) {
        final lineId = _uuid.v4();
        final lineTotal = line.quantity * line.unitPrice;
        await txn.insert('salesInvoiceItems', {
          'id': lineId,
          'invoiceId': invoiceId,
          'productId': line.productId,
          'quantity': line.quantity,
          'unitPrice': line.unitPrice,
          'lineTotal': lineTotal,
        });
      }
    });
    await _audit('create', 'priceQuote', invoiceId, 'Created price quote');
    return invoiceId;
  }

  Future<void> updatePriceQuote({
    required String invoiceId,
    required String? customerId,
    required List<InvoiceLineInput> lines,
    DateTime? invoiceDate,
    double discountAmount = 0,
    double taxPercent = 0,
    String? notes,
  }) async {
    _requireModifyInvoices();
    _requireRegisteredOperationalAccess();
    final s = _mustSession();
    final db = await _databaseService.database;
    final now = invoiceDate ?? DateTime.now();
    final am = AccountingService.computeInvoiceHeaderAmounts(
      lines: lines,
      discountAmount: discountAmount,
      taxPercent: taxPercent,
    );
    final lineSubtotal = am['lineSubtotal']!;
    final grandTotal = am['grandTotal']!;
    final disc = am['discount']!;
    final nNotes = notes?.trim();
    await db.transaction((txn) async {
      final invoiceRows = await txn.query(
        'salesInvoices',
        where: 'id = ? AND organizationId = ? AND branchId = ?',
        whereArgs: [invoiceId, s.organizationId, s.branchId],
        limit: 1,
      );
      if (invoiceRows.isEmpty) {
        throw Exception('عرض السعر غير موجود أو لا يمكن تعديله.');
      }
      if (!invoiceRowIsPriceQuote(invoiceRows.first)) {
        throw Exception('هذه الوثيقة ليست عرض سعر.');
      }

      await txn.delete(
        'salesInvoiceItems',
        where: 'invoiceId = ?',
        whereArgs: [invoiceId],
      );

      await txn.update(
        'salesInvoices',
        {
          'customerId': customerId,
          'invoiceDate': now.toIso8601String(),
          'total': grandTotal,
          'invoiceStatus': 'quote',
          'notes': (nNotes == null || nNotes.isEmpty) ? null : nNotes,
          'discountAmount': disc,
          'taxPercent': taxPercent,
          'lineSubtotal': lineSubtotal,
          'totalsFormat': 1,
          'paidAmount': 0,
        },
        where: 'id = ?',
        whereArgs: [invoiceId],
      );

      for (final line in lines) {
        final lineId = _uuid.v4();
        final lineTotal = line.quantity * line.unitPrice;
        await txn.insert('salesInvoiceItems', {
          'id': lineId,
          'invoiceId': invoiceId,
          'productId': line.productId,
          'quantity': line.quantity,
          'unitPrice': line.unitPrice,
          'lineTotal': lineTotal,
        });
      }
    });
    await _audit('update', 'priceQuote', invoiceId, 'Updated price quote');
  }

  /// تحويل عرض سعر محفوظ إلى فاتورة بيع فعلية (خصم مخزون وصندوق حسب الإعدادات).
  Future<String> convertPriceQuoteToSale({
    required String quoteInvoiceId,
    String? customerId,
    String paymentType = 'cash',
    DateTime? invoiceDate,
    double? paidAmount,
    bool recordCashBoxMovement = true,
    bool creditOverpayToCustomer = false,
    List<InvoicePaymentSplitInput>? paymentSplits,
    bool Function(String paymentType)? cashBoxFilterForPaymentType,
  }) async {
    _requireModifyInvoices();
    _requireRegisteredOperationalAccess();
    _mustSession();
    final header = await invoiceHeaderById(invoiceId: quoteInvoiceId, isSale: true);
    if (header == null || !invoiceRowIsPriceQuote(header)) {
      throw Exception('عرض السعر غير موجود.');
    }
    final items = await salesInvoiceItemsForEdit(quoteInvoiceId);
    final lines = items
        .map(
          (e) => InvoiceLineInput(
            productId: e['productId'] as String,
            quantity: ((e['quantity'] as num?) ?? 0).toDouble(),
            unitPrice: ((e['unitPrice'] as num?) ?? 0).toDouble(),
          ),
        )
        .toList();
    if (lines.isEmpty) {
      throw Exception('عرض السعر لا يحتوي أصنافاً.');
    }
    final cust = customerId ?? header['customerId'] as String?;
    final disc = ((header['discountAmount'] as num?) ?? 0).toDouble();
    final tax = ((header['taxPercent'] as num?) ?? 0).toDouble();
    final notes = (header['notes'] as String?)?.trim();
    return createSale(
      customerId: cust,
      lines: lines,
      invoiceDate: invoiceDate ??
          DateTime.tryParse((header['invoiceDate'] ?? '').toString()) ??
          DateTime.now(),
      paymentType: paymentType,
      discountAmount: disc,
      taxPercent: tax,
      notes: notes?.isEmpty ?? true ? null : notes,
      paidAmount: paidAmount,
      recordCashBoxMovement: recordCashBoxMovement,
      creditOverpayToCustomer: creditOverpayToCustomer,
      paymentSplits: paymentSplits,
      cashBoxFilterForPaymentType: cashBoxFilterForPaymentType,
    );
  }

  Future<void> updateSaleInvoice({
    required String invoiceId,
    required String? customerId,
    required List<InvoiceLineInput> lines,
    String paymentType = 'cash',
    DateTime? invoiceDate,
    double discountAmount = 0,
    double taxPercent = 0,
    String? notes,
    double? paidAmount,
    bool recordCashBoxMovement = true,
    bool creditOverpayToCustomer = false,
    List<InvoicePaymentSplitInput>? paymentSplits,
    bool Function(String paymentType)? cashBoxFilterForPaymentType,
  }) async {
    _requireModifyInvoices();
    _requireRegisteredOperationalAccess();
    final s = _mustSession();
    final db = await _databaseService.database;
    final now = invoiceDate ?? DateTime.now();
    final am = AccountingService.computeInvoiceHeaderAmounts(
      lines: lines,
      discountAmount: discountAmount,
      taxPercent: taxPercent,
    );
    final lineSubtotal = am['lineSubtotal']!;
    final grandTotal = am['grandTotal']!;
    final disc = am['discount']!;
    final normalizedSplits =
        paymentSplits != null ? normalizePaymentSplits(paymentSplits) : null;
    final useSplits = normalizedSplits != null && normalizedSplits.isNotEmpty;
    final headerPay = useSplits
        ? headerPaymentTypeFromSplits(normalizedSplits)
        : MizaPaymentTypes.normalize(paymentType);
    final paid = useSplits
        ? immediatePaidFromSplits(normalizedSplits)
        : (paidAmount ?? grandTotal).clamp(0.0, double.infinity);
    final nNotes = notes?.trim();
    await db.transaction((txn) async {
      final invoiceRows = await txn.query(
        'salesInvoices',
        where: 'id = ? AND organizationId = ? AND branchId = ?',
        whereArgs: [invoiceId, s.organizationId, s.branchId],
        limit: 1,
      );
      if (invoiceRows.isEmpty) {
        throw Exception('الفاتورة غير موجودة أو لا يمكن تعديلها.');
      }
      if ((invoiceRows.first['invoiceStatus'] ?? 'posted').toString() == 'voided') {
        throw Exception('لا يمكن تعديل فاتورة ملغاة.');
      }

      await txn.delete(
        'partnerLedger',
        where: 'organizationId = ? AND branchId = ? AND referenceType = ? AND referenceId = ?',
        whereArgs: [s.organizationId, s.branchId, 'sale', invoiceId],
      );

      final oldItems = await txn.query(
        'salesInvoiceItems',
        columns: ['productId', 'quantity'],
        where: 'invoiceId = ?',
        whereArgs: [invoiceId],
      );

      for (final item in oldItems) {
        final productId = item['productId'] as String;
        final qty = ((item['quantity'] as num?) ?? 0).toDouble();
        await txn.rawUpdate(
          'UPDATE products SET stockQty = stockQty + ? WHERE id = ?',
          [qty, productId],
        );
      }

      await txn.delete(
        'salesInvoiceItems',
        where: 'invoiceId = ?',
        whereArgs: [invoiceId],
      );
      await txn.delete(
        'stockMovements',
        where: 'organizationId = ? AND branchId = ? AND referenceType = ? AND referenceId = ?',
        whereArgs: [s.organizationId, s.branchId, 'sale', invoiceId],
      );
      await txn.delete(
        'cashTransactions',
        where: 'organizationId = ? AND branchId = ? AND referenceType = ? AND referenceId = ?',
        whereArgs: [s.organizationId, s.branchId, 'sale', invoiceId],
      );
      await _deleteInvoicePaymentSplits(
        txn,
        invoiceKind: 'sale',
        invoiceId: invoiceId,
        organizationId: s.organizationId,
        branchId: s.branchId,
      );

      await txn.update(
        'salesInvoices',
        {
          'customerId': customerId,
          'invoiceDate': now.toIso8601String(),
          'total': grandTotal,
          'paymentType': headerPay,
          'invoiceStatus': 'posted',
          'notes': (nNotes == null || nNotes.isEmpty) ? null : nNotes,
          'discountAmount': disc,
          'taxPercent': taxPercent,
          'lineSubtotal': lineSubtotal,
          'totalsFormat': 1,
          'paidAmount': paid,
        },
        where: 'id = ?',
        whereArgs: [invoiceId],
      );

      for (final line in lines) {
        final lineId = _uuid.v4();
        final lineTotal = line.quantity * line.unitPrice;
        await txn.insert('salesInvoiceItems', {
          'id': lineId,
          'invoiceId': invoiceId,
          'productId': line.productId,
          'quantity': line.quantity,
          'unitPrice': line.unitPrice,
          'lineTotal': lineTotal,
        });
        await txn.rawUpdate(
          'UPDATE products SET stockQty = stockQty - ? WHERE id = ?',
          [line.quantity, line.productId],
        );
        await txn.insert('stockMovements', {
          'id': _uuid.v4(),
          'organizationId': s.organizationId,
          'branchId': s.branchId,
          'productId': line.productId,
          'movementType': 'out',
          'quantity': line.quantity,
          'referenceType': 'sale',
          'referenceId': invoiceId,
          'movementDate': now.toIso8601String(),
          'createdBy': s.userId,
        });
      }
      if (useSplits) {
        await _insertInvoicePaymentSplits(
          txn,
          invoiceKind: 'sale',
          invoiceId: invoiceId,
          organizationId: s.organizationId,
          branchId: s.branchId,
          splits: normalizedSplits,
        );
        await _postSplitCashMovements(
          txn,
          isSale: true,
          invoiceId: invoiceId,
          splits: normalizedSplits,
          recordCashBoxMovement: recordCashBoxMovement,
          cashBoxFilterForPaymentType: cashBoxFilterForPaymentType,
          description: 'Sales invoice payment',
          updatedDescription: 'Sales invoice payment (updated)',
          isUpdate: true,
        );
      } else if (recordCashBoxMovement &&
          MizaPaymentTypes.postsToCashBox(paymentType) &&
          paid > 1e-9) {
        await _insertCash(txn, CashTransactionInput(
          type: 'in',
          amount: paid,
          description: 'Sales invoice payment (updated)',
          referenceType: 'sale',
          referenceId: invoiceId,
        ));
      }
      final cid2 = customerId?.trim();
      final arRemaining = AccountingService.invoiceRemainingForDisplay(
        grandTotal: grandTotal,
        paid: paid,
      );
      if (useSplits) {
        await _postPartnerLedgerForInvoiceRemaining(
          txn: txn,
          isSale: true,
          partnerId: customerId,
          invoiceId: invoiceId,
          arRemaining: arRemaining,
          entryDate: now,
          isUpdate: true,
        );
      } else if (MizaPaymentTypes.isDeferred(paymentType) &&
          cid2 != null &&
          cid2.isNotEmpty &&
          arRemaining > 1e-9) {
        await _insertPartnerLedger(
          txn,
          partnerKind: 'customer',
          partnerId: cid2,
          entryType: 'sale_ar',
          referenceType: 'sale',
          referenceId: invoiceId,
          amountSigned: arRemaining,
          notes: 'فاتورة بيع آجل (بعد التعديل)',
          entryDate: now,
        );
      }
      if (!useSplits) {
        await _insertSaleOverpayCreditIfNeeded(
          txn,
          customerId: customerId,
          invoiceId: invoiceId,
          grandTotal: grandTotal,
          paid: paid,
          creditOverpayToCustomer: creditOverpayToCustomer,
          entryDate: now,
        );
      }
    });
    await _audit('update', 'salesInvoice', invoiceId, 'Updated sales invoice');
  }

  Future<Map<String, Object?>> deleteSaleInvoice(String invoiceId) async {
    _requireModifyInvoices();
    _requireRegisteredOperationalAccess();
    final s = _mustSession();
    final db = await _databaseService.database;
    final snapshot = <String, Object?>{};
    await db.transaction((txn) async {
      final invoiceRows = await txn.query(
        'salesInvoices',
        where: 'id = ? AND organizationId = ? AND branchId = ?',
        whereArgs: [invoiceId, s.organizationId, s.branchId],
        limit: 1,
      );
      if (invoiceRows.isEmpty) {
        throw Exception('الفاتورة غير موجودة أو لا يمكن حذفها.');
      }
      final invoiceRow = Map<String, Object?>.from(invoiceRows.first);

      final items = await txn.query(
        'salesInvoiceItems',
        where: 'invoiceId = ?',
        whereArgs: [invoiceId],
      );
      final stockRows = await txn.query(
        'stockMovements',
        where: 'organizationId = ? AND branchId = ? AND referenceType = ? AND referenceId = ?',
        whereArgs: [s.organizationId, s.branchId, 'sale', invoiceId],
      );
      final cashRows = await txn.query(
        'cashTransactions',
        where: 'organizationId = ? AND branchId = ? AND referenceType = ? AND referenceId = ?',
        whereArgs: [s.organizationId, s.branchId, 'sale', invoiceId],
      );
      snapshot['invoice'] = invoiceRow;
      snapshot['items'] = items.map((e) => Map<String, Object?>.from(e)).toList();
      snapshot['stockMovements'] = stockRows.map((e) => Map<String, Object?>.from(e)).toList();
      snapshot['cashTransactions'] = cashRows.map((e) => Map<String, Object?>.from(e)).toList();

      final isQuote = invoiceRowIsPriceQuote(invoiceRow);
      if (!isQuote) {
        for (final item in items) {
          final productId = item['productId'] as String;
          final qty = ((item['quantity'] as num?) ?? 0).toDouble();
          await txn.rawUpdate(
            'UPDATE products SET stockQty = stockQty + ? WHERE id = ?',
            [qty, productId],
          );
        }
      }

      await txn.delete(
        'salesInvoiceItems',
        where: 'invoiceId = ?',
        whereArgs: [invoiceId],
      );
      await txn.delete(
        'stockMovements',
        where: 'organizationId = ? AND branchId = ? AND referenceType = ? AND referenceId = ?',
        whereArgs: [s.organizationId, s.branchId, 'sale', invoiceId],
      );
      await txn.delete(
        'cashTransactions',
        where: 'organizationId = ? AND branchId = ? AND referenceType = ? AND referenceId = ?',
        whereArgs: [s.organizationId, s.branchId, 'sale', invoiceId],
      );
      await txn.delete(
        'partnerLedger',
        where: 'organizationId = ? AND branchId = ? AND referenceType = ? AND referenceId = ?',
        whereArgs: [s.organizationId, s.branchId, 'sale', invoiceId],
      );
      await txn.delete(
        'salesInvoices',
        where: 'id = ?',
        whereArgs: [invoiceId],
      );
    });
    await _audit('delete', 'salesInvoice', invoiceId, 'Deleted sales invoice');
    return snapshot;
  }

  Future<void> restoreDeletedSaleInvoice(Map<String, Object?> snapshot) async {
    _requireModifyInvoices();
    _requireRegisteredOperationalAccess();
    final s = _mustSession();
    final db = await _databaseService.database;
    final invoice = snapshot['invoice'];
    if (invoice is! Map<String, Object?>) {
      throw Exception('بيانات الاسترجاع غير صالحة.');
    }
    final invoiceId = (invoice['id'] ?? '').toString();
    if (invoiceId.isEmpty) {
      throw Exception('بيانات الفاتورة غير صالحة للاسترجاع.');
    }
    final items = (snapshot['items'] as List<dynamic>? ?? [])
        .cast<Map<String, Object?>>();
    final stockRows = (snapshot['stockMovements'] as List<dynamic>? ?? [])
        .cast<Map<String, Object?>>();
    final cashRows = (snapshot['cashTransactions'] as List<dynamic>? ?? [])
        .cast<Map<String, Object?>>();

    await db.transaction((txn) async {
      final existing = await txn.query(
        'salesInvoices',
        columns: ['id'],
        where: 'id = ? AND organizationId = ? AND branchId = ?',
        whereArgs: [invoiceId, s.organizationId, s.branchId],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        throw Exception('لا يمكن الاسترجاع لأن الفاتورة موجودة بالفعل.');
      }

      await txn.insert('salesInvoices', invoice);
      for (final item in items) {
        await txn.insert('salesInvoiceItems', item);
        final productId = item['productId'] as String;
        final qty = ((item['quantity'] as num?) ?? 0).toDouble();
        await txn.rawUpdate(
          'UPDATE products SET stockQty = stockQty - ? WHERE id = ?',
          [qty, productId],
        );
      }
      for (final row in stockRows) {
        await txn.insert('stockMovements', row);
      }
      for (final row in cashRows) {
        await txn.insert('cashTransactions', row);
      }
      final payType = (invoice['paymentType'] ?? '').toString();
      final custId = invoice['customerId']?.toString().trim();
      final totInv = ((invoice['total'] as num?) ?? 0).toDouble();
      final dtInv =
          DateTime.tryParse((invoice['invoiceDate'] ?? '').toString()) ?? DateTime.now();
      if (MizaPaymentTypes.isDeferred(payType) &&
          custId != null &&
          custId.isNotEmpty &&
          totInv != 0) {
        await _insertPartnerLedger(
          txn,
          partnerKind: 'customer',
          partnerId: custId,
          entryType: 'sale_ar',
          referenceType: 'sale',
          referenceId: invoiceId,
          amountSigned: totInv,
          notes: 'استرجاع فاتورة بيع محذوفة',
          entryDate: dtInv,
        );
      }
    });
    await _audit('restore', 'salesInvoice', invoiceId, 'Restored deleted sales invoice');
  }

  Future<void> voidSaleInvoice(String invoiceId) async {
    _requireModifyInvoices();
    _requireRegisteredOperationalAccess();
    final s = _mustSession();
    final db = await _databaseService.database;
    await db.transaction((txn) async {
      final invoiceRows = await txn.query(
        'salesInvoices',
        where: 'id = ? AND organizationId = ? AND branchId = ?',
        whereArgs: [invoiceId, s.organizationId, s.branchId],
        limit: 1,
      );
      if (invoiceRows.isEmpty) {
        throw Exception('الفاتورة غير موجودة.');
      }
      final inv = invoiceRows.first;
      if ((inv['invoiceStatus'] ?? 'posted').toString() == 'voided') {
        throw Exception('الفاتورة ملغاة مسبقًا.');
      }
      final paymentType = (inv['paymentType'] ?? '').toString();
      final total = ((inv['total'] as num?) ?? 0).toDouble();
      final customerId = inv['customerId'] as String?;
      final items = await txn.query(
        'salesInvoiceItems',
        where: 'invoiceId = ?',
        whereArgs: [invoiceId],
      );
      final nowIso = DateTime.now().toIso8601String();
      for (final item in items) {
        final productId = item['productId'] as String;
        final qty = ((item['quantity'] as num?) ?? 0).toDouble();
        await txn.rawUpdate(
          'UPDATE products SET stockQty = stockQty + ? WHERE id = ?',
          [qty, productId],
        );
        await txn.insert('stockMovements', {
          'id': _uuid.v4(),
          'organizationId': s.organizationId,
          'branchId': s.branchId,
          'productId': productId,
          'movementType': 'in',
          'quantity': qty,
          'referenceType': 'sale_void',
          'referenceId': invoiceId,
          'movementDate': nowIso,
          'createdBy': s.userId,
        });
      }
      final hadSaleCash = await AccountingService._txnCashMovementExistsForRef(
        txn,
        organizationId: s.organizationId,
        branchId: s.branchId,
        referenceType: 'sale',
        referenceId: invoiceId,
      );
      if (hadSaleCash && total != 0) {
        await _insertCash(
          txn,
          CashTransactionInput(
            type: 'out',
            amount: total,
            description: 'إلغاء فاتورة بيع نقدي',
            referenceType: 'sale_void',
            referenceId: invoiceId,
          ),
        );
      } else if (MizaPaymentTypes.isDeferred(paymentType)) {
        final cid = customerId?.trim();
        if (cid != null && cid.isNotEmpty && total != 0) {
          await _insertPartnerLedger(
            txn,
            partnerKind: 'customer',
            partnerId: cid,
            entryType: 'sale_void',
            referenceType: 'sale',
            referenceId: invoiceId,
            amountSigned: -total,
            notes: 'إلغاء فاتورة بيع آجل',
          );
        }
      }
      final overpayLedgers = await txn.query(
        'partnerLedger',
        where:
            'organizationId = ? AND branchId = ? AND referenceType = ? '
            'AND referenceId = ? AND entryType = ?',
        whereArgs: [
          s.organizationId,
          s.branchId,
          'sale',
          invoiceId,
          'sale_overpay_credit',
        ],
      );
      final cidOverpay = customerId?.trim();
      if (cidOverpay != null && cidOverpay.isNotEmpty) {
        for (final row in overpayLedgers) {
          final signed = ((row['amountSigned'] as num?) ?? 0).toDouble();
          if (signed.abs() <= 1e-9) continue;
          await _insertPartnerLedger(
            txn,
            partnerKind: 'customer',
            partnerId: cidOverpay,
            entryType: 'sale_void',
            referenceType: 'sale',
            referenceId: invoiceId,
            amountSigned: -signed,
            notes: 'إلغاء رصيد باقي دفع زائد',
          );
        }
      }
      await txn.update(
        'salesInvoices',
        {'invoiceStatus': 'voided'},
        where: 'id = ?',
        whereArgs: [invoiceId],
      );
    });
    await _audit('void', 'salesInvoice', invoiceId, 'Voided sales invoice');
  }

  Future<void> voidPurchaseInvoice(String invoiceId) async {
    _requireModifyInvoices();
    _requireRegisteredOperationalAccess();
    final s = _mustSession();
    final db = await _databaseService.database;
    await db.transaction((txn) async {
      final invoiceRows = await txn.query(
        'purchaseInvoices',
        where: 'id = ? AND organizationId = ? AND branchId = ?',
        whereArgs: [invoiceId, s.organizationId, s.branchId],
        limit: 1,
      );
      if (invoiceRows.isEmpty) {
        throw Exception('الفاتورة غير موجودة.');
      }
      final inv = invoiceRows.first;
      if ((inv['invoiceStatus'] ?? 'posted').toString() == 'voided') {
        throw Exception('الفاتورة ملغاة مسبقًا.');
      }
      final paymentType = (inv['paymentType'] ?? '').toString();
      final total = ((inv['total'] as num?) ?? 0).toDouble();
      final supplierId = inv['supplierId'] as String?;
      final items = await txn.query(
        'purchaseInvoiceItems',
        where: 'invoiceId = ?',
        whereArgs: [invoiceId],
      );
      final nowIso = DateTime.now().toIso8601String();
      for (final item in items) {
        final productId = item['productId'] as String;
        final qty = ((item['quantity'] as num?) ?? 0).toDouble();
        await txn.rawUpdate(
          'UPDATE products SET stockQty = stockQty - ? WHERE id = ?',
          [qty, productId],
        );
        await txn.insert('stockMovements', {
          'id': _uuid.v4(),
          'organizationId': s.organizationId,
          'branchId': s.branchId,
          'productId': productId,
          'movementType': 'out',
          'quantity': qty,
          'referenceType': 'purchase_void',
          'referenceId': invoiceId,
          'movementDate': nowIso,
          'createdBy': s.userId,
        });
      }
      final hadPurchaseCash =
          await AccountingService._txnCashMovementExistsForRef(
        txn,
        organizationId: s.organizationId,
        branchId: s.branchId,
        referenceType: 'purchase',
        referenceId: invoiceId,
      );
      if (hadPurchaseCash && total != 0) {
        await _insertCash(
          txn,
          CashTransactionInput(
            type: 'in',
            amount: total,
            description: 'إلغاء فاتورة شراء نقدي',
            referenceType: 'purchase_void',
            referenceId: invoiceId,
          ),
        );
      } else if (MizaPaymentTypes.isDeferred(paymentType)) {
        final sid = supplierId?.trim();
        if (sid != null && sid.isNotEmpty && total != 0) {
          await _insertPartnerLedger(
            txn,
            partnerKind: 'supplier',
            partnerId: sid,
            entryType: 'purchase_void',
            referenceType: 'purchase',
            referenceId: invoiceId,
            amountSigned: -total,
            notes: 'إلغاء فاتورة شراء آجل',
          );
        }
      }
      await txn.update(
        'purchaseInvoices',
        {'invoiceStatus': 'voided'},
        where: 'id = ?',
        whereArgs: [invoiceId],
      );
    });
    await _audit('void', 'purchaseInvoice', invoiceId, 'Voided purchase invoice');
  }

  Future<String> createSaleReturn({
    required List<InvoiceLineInput> lines,
    String? customerId,
    String? originalInvoiceId,
    required String refundPaymentType,
    DateTime? returnDate,
    String notes = '',
  }) async {
    _requireCreateReturns();
    _requireRegisteredOperationalAccess();
    final s = _mustSession();
    if (lines.isEmpty) {
      throw Exception('لا توجد بنود للمرتجع.');
    }
    final refund = refundPaymentType.trim().toLowerCase();
    if (refund != 'cash' && refund != 'credit') {
      throw Exception('نوع الاسترداد غير صالح.');
    }
    final origSaleStored = () {
      final t = originalInvoiceId?.trim();
      return (t == null || t.isEmpty) ? null : t;
    }();
    if (origSaleStored == null) {
      throw Exception('يجب تحديد الفاتورة الأصلية للمرتجع.');
    }
    final db = await _databaseService.database;
    final returnId = _uuid.v4();
    final now = returnDate ?? DateTime.now();
    final total = lines.fold<double>(0, (sum, l) => sum + (l.quantity * l.unitPrice));

    final syncLines =
        <({String lineId, String productId, double quantity, double unitPrice})>[];
    for (final line in lines) {
      syncLines.add((
        lineId: _uuid.v4(),
        productId: line.productId,
        quantity: line.quantity,
        unitPrice: line.unitPrice,
      ));
    }

    final postResult = await TransactionReturnSyncService(
      databaseService: _databaseService,
    ).createSalesReturnDraftAndPost(
      returnId: returnId,
      organizationId: s.organizationId,
      branchId: s.branchId,
      userId: s.userId,
      customerId: customerId,
      originalInvoiceId: origSaleStored,
      returnDate: now,
      refundPaymentType: refund,
      lineSubtotal: total,
      discountAmount: 0,
      taxPercent: 0,
      total: total,
      paidAmount: total,
      notes: notes.isEmpty ? null : notes,
      lines: syncLines,
    );
    if (!postResult.ok) {
      throw Exception(transactionReturnPostFailureMessage(postResult));
    }

    if (refund == 'cash' && total != 0) {
      await db.transaction((txn) async {
        await _insertCash(
          txn,
          CashTransactionInput(
            type: 'out',
            amount: total,
            description: notes.isEmpty ? 'مرتجع بيع نقدي' : notes,
            referenceType: 'sale_return',
            referenceId: returnId,
          ),
        );
      });
    }

    await _audit('create', 'sale_return', returnId, 'Sale return total $total');
    return returnId;
  }

  Future<String> createPurchaseReturn({
    required List<InvoiceLineInput> lines,
    String? supplierId,
    String? originalInvoiceId,
    required String refundPaymentType,
    DateTime? returnDate,
    String notes = '',
  }) async {
    _requireCreateReturns();
    _requireRegisteredOperationalAccess();
    final s = _mustSession();
    if (lines.isEmpty) {
      throw Exception('لا توجد بنود للمرتجع.');
    }
    final refund = refundPaymentType.trim().toLowerCase();
    if (refund != 'cash' && refund != 'credit') {
      throw Exception('نوع الاسترداد غير صالح.');
    }
    final origPurStored = () {
      final t = originalInvoiceId?.trim();
      return (t == null || t.isEmpty) ? null : t;
    }();
    if (origPurStored == null) {
      throw Exception('يجب تحديد الفاتورة الأصلية للمرتجع.');
    }
    final db = await _databaseService.database;
    final returnId = _uuid.v4();
    final now = returnDate ?? DateTime.now();
    final total = lines.fold<double>(0, (sum, l) => sum + (l.quantity * l.unitPrice));

    final syncLines =
        <({String lineId, String productId, double quantity, double unitCost})>[];
    for (final line in lines) {
      syncLines.add((
        lineId: _uuid.v4(),
        productId: line.productId,
        quantity: line.quantity,
        unitCost: line.unitPrice,
      ));
    }

    final postResult = await TransactionReturnSyncService(
      databaseService: _databaseService,
    ).createPurchaseReturnDraftAndPost(
      returnId: returnId,
      organizationId: s.organizationId,
      branchId: s.branchId,
      userId: s.userId,
      supplierId: supplierId,
      originalInvoiceId: origPurStored,
      returnDate: now,
      refundPaymentType: refund,
      lineSubtotal: total,
      discountAmount: 0,
      taxPercent: 0,
      total: total,
      paidAmount: total,
      notes: notes.isEmpty ? null : notes,
      lines: syncLines,
    );
    if (!postResult.ok) {
      throw Exception(transactionReturnPostFailureMessage(postResult));
    }

    if (refund == 'cash' && total != 0) {
      await db.transaction((txn) async {
        await _insertCash(
          txn,
          CashTransactionInput(
            type: 'in',
            amount: total,
            description: notes.isEmpty ? 'مرتجع شراء نقدي' : notes,
            referenceType: 'purchase_return',
            referenceId: returnId,
          ),
        );
      });
    }

    await _audit('create', 'purchase_return', returnId, 'Purchase return total $total');
    return returnId;
  }

  Future<List<Map<String, Object?>>> listRecentSaleReturns({int limit = 40}) async {
    _requireCreateReturns();
    final s = _mustSession();
    final db = await _databaseService.database;
    return db.rawQuery(
      'SELECT r.id, r.returnDate, r.total, r.customerId, r.originalInvoiceId, '
      'r.refundPaymentType, IFNULL(r.returnStatus, \'posted\') AS returnStatus, '
      'c.name AS customerName '
      'FROM salesReturns r '
      'LEFT JOIN customers c ON c.id = r.customerId '
      'WHERE r.organizationId = ? AND r.branchId = ? '
      'ORDER BY r.returnDate DESC '
      'LIMIT ?',
      [s.organizationId, s.branchId, limit],
    );
  }

  Future<List<Map<String, Object?>>> listRecentPurchaseReturns({int limit = 40}) async {
    _requireCreateReturns();
    final s = _mustSession();
    final db = await _databaseService.database;
    return db.rawQuery(
      'SELECT r.id, r.returnDate, r.total, r.supplierId, r.originalInvoiceId, '
      'r.refundPaymentType, IFNULL(r.returnStatus, \'posted\') AS returnStatus, '
      'sp.name AS supplierName '
      'FROM purchaseReturns r '
      'LEFT JOIN suppliers sp ON sp.id = r.supplierId '
      'WHERE r.organizationId = ? AND r.branchId = ? '
      'ORDER BY r.returnDate DESC '
      'LIMIT ?',
      [s.organizationId, s.branchId, limit],
    );
  }

  Future<bool> _saleReturnLedgerApplied(
    dynamic txn,
    AppUserSession s,
    String? customerId,
    String refund,
    String? originalInvoiceId,
  ) async {
    final cid = customerId?.trim();
    if (cid == null || cid.isEmpty) return false;
    if (refund == 'credit') return true;
    if (refund != 'cash') return false;
    final orig = originalInvoiceId?.trim();
    if (orig == null || orig.isEmpty) return false;
    final rows = await txn.query(
      'salesInvoices',
      columns: ['paymentType'],
      where: 'id = ? AND organizationId = ? AND branchId = ?',
      whereArgs: [orig, s.organizationId, s.branchId],
      limit: 1,
    );
    if (rows.isEmpty) return false;
    return MizaPaymentTypes.isDeferred((rows.first['paymentType'] ?? '').toString());
  }

  Future<bool> _purchaseReturnLedgerApplied(
    dynamic txn,
    AppUserSession s,
    String? supplierId,
    String refund,
    String? originalInvoiceId,
  ) async {
    final sid = supplierId?.trim();
    if (sid == null || sid.isEmpty) return false;
    if (refund == 'credit') return true;
    if (refund != 'cash') return false;
    final orig = originalInvoiceId?.trim();
    if (orig == null || orig.isEmpty) return false;
    final rows = await txn.query(
      'purchaseInvoices',
      columns: ['paymentType'],
      where: 'id = ? AND organizationId = ? AND branchId = ?',
      whereArgs: [orig, s.organizationId, s.branchId],
      limit: 1,
    );
    if (rows.isEmpty) return false;
    return MizaPaymentTypes.isDeferred((rows.first['paymentType'] ?? '').toString());
  }

  /// إلغاء مرتجع بيع (عكس المخزون والصندوق/الذمة).
  Future<void> voidSaleReturn(String returnId) async {
    _requireCreateReturns();
    _requireRegisteredOperationalAccess();
    final s = _mustSession();
    final db = await _databaseService.database;
    await db.transaction((txn) async {
      final retRows = await txn.query(
        'salesReturns',
        where: 'id = ? AND organizationId = ? AND branchId = ?',
        whereArgs: [returnId, s.organizationId, s.branchId],
        limit: 1,
      );
      if (retRows.isEmpty) {
        throw Exception('المرتجع غير موجود.');
      }
      final ret = retRows.first;
      if ((ret['returnStatus'] ?? 'posted').toString() == 'voided') {
        throw Exception('المرتجع ملغى مسبقًا.');
      }
      final total = ((ret['total'] as num?) ?? 0).toDouble();
      final refund = (ret['refundPaymentType'] ?? '').toString();
      final cid = ret['customerId'] as String?;
      final origInv = ret['originalInvoiceId'] as String?;
      final retDate =
          DateTime.tryParse((ret['returnDate'] ?? '').toString()) ?? DateTime.now();
      final notes = (ret['notes'] ?? '').toString();
      final items = await txn.query(
        'salesReturnItems',
        where: 'returnId = ?',
        whereArgs: [returnId],
      );
      final nowIso = DateTime.now().toIso8601String();
      for (final item in items) {
        final productId = item['productId'] as String;
        final qty = ((item['quantity'] as num?) ?? 0).toDouble();
        await txn.rawUpdate(
          'UPDATE products SET stockQty = stockQty - ? WHERE id = ?',
          [qty, productId],
        );
        await txn.insert('stockMovements', {
          'id': _uuid.v4(),
          'organizationId': s.organizationId,
          'branchId': s.branchId,
          'productId': productId,
          'movementType': 'out',
          'quantity': qty,
          'referenceType': 'sale_return_void',
          'referenceId': returnId,
          'movementDate': nowIso,
          'createdBy': s.userId,
        });
      }
      final ledgerApplied =
          await _saleReturnLedgerApplied(txn, s, cid, refund, origInv);
      if (ledgerApplied && cid != null && cid.isNotEmpty && total != 0) {
        await _insertPartnerLedger(
          txn,
          partnerKind: 'customer',
          partnerId: cid,
          entryType: 'sale_return',
          referenceType: 'sale_return_void',
          referenceId: returnId,
          amountSigned: total,
          notes: notes.isEmpty ? 'إلغاء مرتجع بيع' : 'إلغاء مرتجع: $notes',
          entryDate: retDate,
        );
      }
      if (refund == 'cash' && total != 0) {
        await _insertCash(
          txn,
          CashTransactionInput(
            type: 'in',
            amount: total,
            description: notes.isEmpty ? 'إلغاء مرتجع بيع نقدي' : notes,
            referenceType: 'sale_return_void',
            referenceId: returnId,
          ),
        );
      }
      await txn.update(
        'salesReturns',
        {'returnStatus': 'voided'},
        where: 'id = ?',
        whereArgs: [returnId],
      );
    });
    await _audit('void', 'sale_return', returnId, 'Voided sale return');
  }

  /// إلغاء مرتجع شراء (عكس المخزون والصندوق/الذمة).
  Future<void> voidPurchaseReturn(String returnId) async {
    _requireCreateReturns();
    _requireRegisteredOperationalAccess();
    final s = _mustSession();
    final db = await _databaseService.database;
    await db.transaction((txn) async {
      final retRows = await txn.query(
        'purchaseReturns',
        where: 'id = ? AND organizationId = ? AND branchId = ?',
        whereArgs: [returnId, s.organizationId, s.branchId],
        limit: 1,
      );
      if (retRows.isEmpty) {
        throw Exception('المرتجع غير موجود.');
      }
      final ret = retRows.first;
      if ((ret['returnStatus'] ?? 'posted').toString() == 'voided') {
        throw Exception('المرتجع ملغى مسبقًا.');
      }
      final total = ((ret['total'] as num?) ?? 0).toDouble();
      final refund = (ret['refundPaymentType'] ?? '').toString();
      final sid = ret['supplierId'] as String?;
      final origInv = ret['originalInvoiceId'] as String?;
      final retDate =
          DateTime.tryParse((ret['returnDate'] ?? '').toString()) ?? DateTime.now();
      final notes = (ret['notes'] ?? '').toString();
      final items = await txn.query(
        'purchaseReturnItems',
        where: 'returnId = ?',
        whereArgs: [returnId],
      );
      final nowIso = DateTime.now().toIso8601String();
      for (final item in items) {
        final productId = item['productId'] as String;
        final qty = ((item['quantity'] as num?) ?? 0).toDouble();
        await txn.rawUpdate(
          'UPDATE products SET stockQty = stockQty + ? WHERE id = ?',
          [qty, productId],
        );
        await txn.insert('stockMovements', {
          'id': _uuid.v4(),
          'organizationId': s.organizationId,
          'branchId': s.branchId,
          'productId': productId,
          'movementType': 'in',
          'quantity': qty,
          'referenceType': 'purchase_return_void',
          'referenceId': returnId,
          'movementDate': nowIso,
          'createdBy': s.userId,
        });
      }
      final ledgerApplied =
          await _purchaseReturnLedgerApplied(txn, s, sid, refund, origInv);
      if (ledgerApplied && sid != null && sid.isNotEmpty && total != 0) {
        await _insertPartnerLedger(
          txn,
          partnerKind: 'supplier',
          partnerId: sid,
          entryType: 'purchase_return',
          referenceType: 'purchase_return_void',
          referenceId: returnId,
          amountSigned: total,
          notes: notes.isEmpty ? 'إلغاء مرتجع شراء' : 'إلغاء مرتجع: $notes',
          entryDate: retDate,
        );
      }
      if (refund == 'cash' && total != 0) {
        await _insertCash(
          txn,
          CashTransactionInput(
            type: 'out',
            amount: total,
            description: notes.isEmpty ? 'إلغاء مرتجع شراء نقدي' : notes,
            referenceType: 'purchase_return_void',
            referenceId: returnId,
          ),
        );
      }
      await txn.update(
        'purchaseReturns',
        {'returnStatus': 'voided'},
        where: 'id = ?',
        whereArgs: [returnId],
      );
    });
    await _audit('void', 'purchase_return', returnId, 'Voided purchase return');
  }

  /// خصم كمية تالفة من المخزون (لا يمر عبر فاتورة).
  Future<String> recordDamagedStock({
    required String productId,
    required double quantity,
    String notes = '',
  }) async {
    _requireManageProductsBasic();
    _requireRegisteredOperationalAccess();
    if (quantity <= 0) {
      throw Exception('كمية التالف يجب أن تكون أكبر من صفر.');
    }
    return createInventoryAdjustment(
      productId: productId,
      quantityDelta: -quantity,
      adjustmentReason: 'damage',
      notes: notes,
    );
  }

  /// تحويل مبلغ من ذمة طرف إلى طرف (عميل/مورد) دون تأثير على الصندوق.
  Future<void> transferPartnerBalance({
    required String fromKind,
    required String fromPartnerId,
    required String toKind,
    required String toPartnerId,
    required double amount,
    String notes = '',
  }) async {
    _requireModifyInvoices();
    _requireRegisteredOperationalAccess();
    final fk = fromKind.trim().toLowerCase();
    final tk = toKind.trim().toLowerCase();
    if (fk != 'customer' && fk != 'supplier') {
      throw Exception('نوع الحساب المصدر غير صالح.');
    }
    if (tk != 'customer' && tk != 'supplier') {
      throw Exception('نوع الحساب الهدف غير صالح.');
    }
    if (amount <= 0) {
      throw Exception('المبلغ يجب أن يكون أكبر من صفر.');
    }
    final fId = fromPartnerId.trim();
    final tId = toPartnerId.trim();
    if (fId.isEmpty || tId.isEmpty) {
      throw Exception('يجب اختيار الحسابين.');
    }
    if (fk == tk && fId == tId) {
      throw Exception('لا يمكن التحويل لنفس الحساب.');
    }
    _mustSession();
    final db = await _databaseService.database;
    final refId = _uuid.v4();
    final note = notes.trim().isEmpty ? 'تحويل ذمة بين حسابات' : notes.trim();
    await db.transaction((txn) async {
      await _insertPartnerLedger(
        txn,
        partnerKind: fk,
        partnerId: fId,
        entryType: 'partner_transfer',
        referenceType: 'partner_transfer',
        referenceId: refId,
        amountSigned: -amount,
        notes: note,
      );
      await _insertPartnerLedger(
        txn,
        partnerKind: tk,
        partnerId: tId,
        entryType: 'partner_transfer',
        referenceType: 'partner_transfer',
        referenceId: refId,
        amountSigned: amount,
        notes: note,
      );
    });
    await _audit(
      'transfer',
      'partnerLedger',
      refId,
      'Partner balance transfer $amount',
    );
  }

  Future<Map<String, Object?>> invoiceForPrint({
    required String invoiceId,
    required String type,
  }) async {
    final db = await _databaseService.database;
    final isSale = type == 'sale';
    final invoiceTable = isSale ? 'salesInvoices' : 'purchaseInvoices';
    final itemTable = isSale ? 'salesInvoiceItems' : 'purchaseInvoiceItems';
    final unitColumn = isSale ? 'unitPrice' : 'unitCost';
    final invoiceRows = await db.query(invoiceTable, where: 'id = ?', whereArgs: [invoiceId], limit: 1);
    if (invoiceRows.isEmpty) {
      throw Exception('لم يتم العثور على الفاتورة.');
    }
    final itemRows = await db.rawQuery(
      'SELECT i.quantity, i.$unitColumn AS unitPrice, i.lineTotal, p.name AS productName '
      'FROM $itemTable i LEFT JOIN products p ON p.id = i.productId '
      'WHERE i.invoiceId = ?',
      [invoiceId],
    );
    final inv = invoiceRows.first;
    String? partnerName;
    if (isSale) {
      final cid = inv['customerId'] as String?;
      if (cid != null && cid.trim().isNotEmpty) {
        final r = await db.query(
          'customers',
          columns: ['name'],
          where: 'id = ? AND organizationId = ? AND branchId = ?',
          whereArgs: [cid, inv['organizationId'], inv['branchId']],
          limit: 1,
        );
        if (r.isNotEmpty) {
          partnerName = r.first['name'] as String?;
        }
      }
    } else {
      final sid = inv['supplierId'] as String?;
      if (sid != null && sid.trim().isNotEmpty) {
        final r = await db.query(
          'suppliers',
          columns: ['name'],
          where: 'id = ? AND organizationId = ? AND branchId = ?',
          whereArgs: [sid, inv['organizationId'], inv['branchId']],
          limit: 1,
        );
        if (r.isNotEmpty) {
          partnerName = r.first['name'] as String?;
        }
      }
    }
    return {
      'invoice': inv,
      'items': itemRows,
      'type': type,
      'partnerName': partnerName,
      'paymentSplits': await _loadInvoicePaymentSplitsForPrint(
        db,
        invoiceKind: isSale ? 'sale' : 'purchase',
        invoiceId: invoiceId,
      ),
    };
  }

  Future<List<Map<String, Object?>>> _loadInvoicePaymentSplitsForPrint(
    Database db, {
    required String invoiceKind,
    required String invoiceId,
  }) async {
    final rows = await db.query(
      'invoice_payment_splits',
      columns: ['paymentType', 'amount', 'lineOrder'],
      where: 'invoiceKind = ? AND invoiceId = ?',
      whereArgs: [invoiceKind, invoiceId],
      orderBy: 'lineOrder ASC',
    );
    return rows
        .map(
          (r) => {
            'paymentType': (r['paymentType'] ?? MizaPaymentTypes.cash).toString(),
            'amount': ((r['amount'] as num?) ?? 0).toDouble(),
          },
        )
        .toList();
  }

  static List<InvoicePaymentSplitInput> paymentSplitsFromPrintPayload(
    Object? raw,
  ) {
    if (raw is! List) return const [];
    final out = <InvoicePaymentSplitInput>[];
    for (final e in raw) {
      if (e is! Map) continue;
      final m = Map<String, Object?>.from(e);
      out.add(
        InvoicePaymentSplitInput(
          paymentType: (m['paymentType'] ?? MizaPaymentTypes.cash).toString(),
          amount: ((m['amount'] as num?) ?? 0).toDouble(),
        ),
      );
    }
    return normalizePaymentSplits(out);
  }

  static bool invoiceHasSplitPaymentDetails({
    required String? paymentTypeRaw,
    required List<InvoicePaymentSplitInput> splits,
  }) =>
      splits.isNotEmpty &&
      (MizaPaymentTypes.isSplit(paymentTypeRaw) || splits.length > 1);

  /// رأس فاتورة بيع/شراء للتحميل في شاشة المعاملة (ملاحظات، خصم، ضريبة…).
  Future<Map<String, Object?>?> invoiceHeaderById({
    required String invoiceId,
    required bool isSale,
  }) async {
    final s = _mustSession();
    final db = await _databaseService.database;
    final table = isSale ? 'salesInvoices' : 'purchaseInvoices';
    final rows = await db.query(
      table,
      where: 'id = ? AND organizationId = ? AND branchId = ?',
      whereArgs: [invoiceId, s.organizationId, s.branchId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> clearOperationalData() async {
    final s = _mustSession();
    if (_isGuest) {
      throw Exception('سجّل الدخول لتنفيذ هذه العملية.');
    }
    _requirePaidSubscription();
    final db = await _databaseService.database;
    await db.transaction((txn) async {
      final srRows = await txn.query(
        'salesReturns',
        columns: ['id'],
        where: 'organizationId = ? AND branchId = ?',
        whereArgs: [s.organizationId, s.branchId],
      );
      final srIds = srRows.map((e) => e['id'] as String).toList();
      await _deleteByIds(txn, table: 'salesReturnItems', column: 'returnId', ids: srIds);
      await txn.delete(
        'salesReturns',
        where: 'organizationId = ? AND branchId = ?',
        whereArgs: [s.organizationId, s.branchId],
      );

      final prRows = await txn.query(
        'purchaseReturns',
        columns: ['id'],
        where: 'organizationId = ? AND branchId = ?',
        whereArgs: [s.organizationId, s.branchId],
      );
      final prIds = prRows.map((e) => e['id'] as String).toList();
      await _deleteByIds(txn, table: 'purchaseReturnItems', column: 'returnId', ids: prIds);
      await txn.delete(
        'purchaseReturns',
        where: 'organizationId = ? AND branchId = ?',
        whereArgs: [s.organizationId, s.branchId],
      );

      await txn.delete(
        'partnerLedger',
        where: 'organizationId = ? AND branchId = ?',
        whereArgs: [s.organizationId, s.branchId],
      );

      final salesRows = await txn.query(
        'salesInvoices',
        columns: ['id'],
        where: 'organizationId = ? AND branchId = ?',
        whereArgs: [s.organizationId, s.branchId],
      );
      final salesIds = salesRows.map((e) => e['id'] as String).toList();
      await _deleteByIds(txn, table: 'salesInvoiceItems', column: 'invoiceId', ids: salesIds);
      await txn.delete(
        'invoice_payment_splits',
        where: 'organizationId = ? AND branchId = ?',
        whereArgs: [s.organizationId, s.branchId],
      );
      await txn.delete(
        'salesInvoices',
        where: 'organizationId = ? AND branchId = ?',
        whereArgs: [s.organizationId, s.branchId],
      );

      final purchaseRows = await txn.query(
        'purchaseInvoices',
        columns: ['id'],
        where: 'organizationId = ? AND branchId = ?',
        whereArgs: [s.organizationId, s.branchId],
      );
      final purchaseIds = purchaseRows.map((e) => e['id'] as String).toList();
      await _deleteByIds(txn, table: 'purchaseInvoiceItems', column: 'invoiceId', ids: purchaseIds);
      await txn.delete(
        'purchaseInvoices',
        where: 'organizationId = ? AND branchId = ?',
        whereArgs: [s.organizationId, s.branchId],
      );

      await txn.delete(
        'stockMovements',
        where: 'organizationId = ? AND branchId = ?',
        whereArgs: [s.organizationId, s.branchId],
      );
      await txn.delete(
        'cashTransactions',
        where: 'organizationId = ? AND branchId = ?',
        whereArgs: [s.organizationId, s.branchId],
      );
      await txn.delete(
        'expenses',
        where: 'organizationId = ? AND branchId = ?',
        whereArgs: [s.organizationId, s.branchId],
      );
      await txn.delete(
        'auditLogs',
        where: 'organizationId = ? AND branchId = ?',
        whereArgs: [s.organizationId, s.branchId],
      );
    });
    await _audit('delete', 'system_data', s.branchId, 'Cleared operational data');
  }

  /// مسح كل بيانات البرنامج على الجهاز والبدء من جديد (زائر أو مالك).
  Future<void> factoryResetAllData() async {
    if (!_isGuest && _effectiveRole != 'owner') {
      throw Exception('إعادة الضبط الكامل متاحة لوضع الزائر أو حساب المالك فقط.');
    }
    clearSession();
    try {
      await VoucherSessionManager.instance.logout();
    } catch (_) {}
    await AppLocalDataWiper.wipeAll();
    await _databaseService.wipeAndRecreateDatabase();
    await licenseGate.reloadDeviceTrialState();
    await bootstrapDefaults();
    await enterGuestMode();
    await syncLicenseGate();
  }

  Future<void> addExpense(
    String title,
    double amount, {
    String notes = '',
    String paymentType = MizaPaymentTypes.cash,
    bool recordCashBoxMovement = true,
    DateTime? expenseDate,
  }) async {
    final s = _mustSession();
    _requirePaidSubscription();
    final db = await _databaseService.database;
    final expenseId = _uuid.v4();
    final now = (expenseDate ?? DateTime.now()).toIso8601String();
    final pay = MizaPaymentTypes.normalize(paymentType);
    await db.transaction((txn) async {
      await txn.insert('expenses', {
        'id': expenseId,
        'organizationId': s.organizationId,
        'branchId': s.branchId,
        'title': title,
        'amount': amount,
        'expenseDate': now,
        'notes': notes,
        'createdBy': s.userId,
      });
      if (recordCashBoxMovement && MizaPaymentTypes.postsToCashBox(pay)) {
        await _insertCash(txn, CashTransactionInput(
          type: 'out',
          amount: amount,
          description: title,
          referenceType: 'expense',
          referenceId: expenseId,
        ));
      }
    });
    await _audit('create', 'expense', expenseId, 'Created expense $title');
  }

  Future<void> addCashTransaction(CashTransactionInput input) async {
    _mustSession();
    _requirePaidSubscription();
    final db = await _databaseService.database;
    await db.transaction((txn) async {
      await _insertCash(txn, input);
    });
    await _audit('create', 'cashTransaction', input.referenceId, input.description);
  }

  /// قبض من عميل مع خصم الذمة في دفتر الشركاء (يُستخدم للتسديد الحقيقي للآجل).
  Future<String> recordCustomerPayment({
    required String customerId,
    required double amount,
    String notes = '',
    DateTime? paymentDate,
    String? voucherNumber,
    String paymentMethod = 'cash',
  }) async {
    _requirePaidSubscription();
    final s = _mustSession();
    final cid = customerId.trim();
    if (cid.isEmpty) {
      throw Exception('معرف العميل غير صالح.');
    }
    if (amount <= 0) {
      throw Exception('المبلغ يجب أن يكون أكبر من صفر.');
    }
    final paymentId = _uuid.v4();
    final when = paymentDate ?? DateTime.now();
    final postResult = await TransactionPaymentSyncService(
      databaseService: _databaseService,
    ).createCustomerPaymentDraftAndPost(
      paymentId: paymentId,
      organizationId: s.organizationId,
      branchId: s.branchId,
      userId: s.userId,
      customerId: cid,
      amount: amount,
      paymentDate: when,
      paymentMethod: paymentMethod,
      voucherNumber: voucherNumber,
      notes: notes.isEmpty ? null : notes,
    );
    if (!postResult.ok) {
      throw Exception(transactionPaymentPostFailureMessage(postResult));
    }
    await _audit('create', 'customer_payment', paymentId, 'Customer payment $amount');
    return paymentId;
  }

  /// صرف لمورد مع خصم ذمة المورد في دفتر الشركاء.
  Future<String> recordSupplierPayment({
    required String supplierId,
    required double amount,
    String notes = '',
    DateTime? paymentDate,
    String? voucherNumber,
    String paymentMethod = 'cash',
  }) async {
    _requirePaidSubscription();
    final s = _mustSession();
    final sid = supplierId.trim();
    if (sid.isEmpty) {
      throw Exception('معرف المورد غير صالح.');
    }
    if (amount <= 0) {
      throw Exception('المبلغ يجب أن يكون أكبر من صفر.');
    }
    final paymentId = _uuid.v4();
    final when = paymentDate ?? DateTime.now();
    final postResult = await TransactionPaymentSyncService(
      databaseService: _databaseService,
    ).createSupplierPaymentDraftAndPost(
      paymentId: paymentId,
      organizationId: s.organizationId,
      branchId: s.branchId,
      userId: s.userId,
      supplierId: sid,
      amount: amount,
      paymentDate: when,
      paymentMethod: paymentMethod,
      voucherNumber: voucherNumber,
      notes: notes.isEmpty ? null : notes,
    );
    if (!postResult.ok) {
      throw Exception(transactionPaymentPostFailureMessage(postResult));
    }
    await _audit('create', 'supplier_payment', paymentId, 'Supplier payment $amount');
    return paymentId;
  }

  Future<bool> cancelLastManualCashTransactionByType(String type) async {
    final s = _mustSession();
    final db = await _databaseService.database;
    final rows = await db.query(
      'cashTransactions',
      where:
          'organizationId = ? AND branchId = ? AND transactionType = ? AND referenceType = ?',
      whereArgs: [s.organizationId, s.branchId, type, 'manual'],
      orderBy: 'transactionDate DESC',
      limit: 1,
    );
    if (rows.isEmpty) return false;
    final id = rows.first['id'] as String;
    await db.delete('cashTransactions', where: 'id = ?', whereArgs: [id]);
    await _audit('delete', 'cashTransaction', id, 'Cancelled last manual cash transaction ($type)');
    return true;
  }

  Future<bool> cancelLastExpenseWithCash() async {
    final s = _mustSession();
    final db = await _databaseService.database;
    final rows = await db.query(
      'expenses',
      where: 'organizationId = ? AND branchId = ?',
      whereArgs: [s.organizationId, s.branchId],
      orderBy: 'expenseDate DESC',
      limit: 1,
    );
    if (rows.isEmpty) return false;
    final expenseId = rows.first['id'] as String;
    await db.transaction((txn) async {
      await txn.delete('expenses', where: 'id = ?', whereArgs: [expenseId]);
      await txn.delete(
        'cashTransactions',
        where: 'organizationId = ? AND branchId = ? AND referenceType = ? AND referenceId = ?',
        whereArgs: [s.organizationId, s.branchId, 'expense', expenseId],
      );
    });
    await _audit('delete', 'expense', expenseId, 'Cancelled last expense with cash impact');
    return true;
  }

  /// حركات الصندوق اليدوية للفرع الحالي (مرجع `manual`)، الأحدث أولاً.
  /// [movementQuery] يصفّي حسب جزء من `id` أو `referenceId` (غير حساس لحالة الأحرف).
  Future<List<Map<String, Object?>>> listManualCashTransactions({
    String? transactionType,
    String? movementQuery,
    int limit = 150,
  }) async {
    final s = _mustSession();
    final db = await _databaseService.database;
    var where = 'organizationId = ? AND branchId = ? AND referenceType = ?';
    final whereArgs = <Object?>[s.organizationId, s.branchId, 'manual'];
    if (transactionType == 'in' || transactionType == 'out') {
      where += ' AND transactionType = ?';
      whereArgs.add(transactionType);
    }
    final q = movementQuery?.trim() ?? '';
    if (q.isNotEmpty) {
      final p = '%${q.toLowerCase()}%';
      where += ' AND (LOWER(id) LIKE ? OR LOWER(referenceId) LIKE ?)';
      whereArgs.add(p);
      whereArgs.add(p);
    }
    return db.query(
      'cashTransactions',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'transactionDate DESC',
      limit: limit,
    );
  }

  /// إلغاء حركة صندوق يدوية بالمعرّف (يُرفض إن لم تكن `manual` أو ليست للفرع).
  Future<bool> cancelManualCashTransactionById(String id) async {
    final s = _mustSession();
    final tid = id.trim();
    if (tid.isEmpty) return false;
    final db = await _databaseService.database;
    final rows = await db.query(
      'cashTransactions',
      where:
          'id = ? AND organizationId = ? AND branchId = ? AND referenceType = ?',
      whereArgs: [tid, s.organizationId, s.branchId, 'manual'],
      limit: 1,
    );
    if (rows.isEmpty) return false;
    await db.delete('cashTransactions', where: 'id = ?', whereArgs: [tid]);
    await _audit(
      'delete',
      'cashTransaction',
      tid,
      'Cancelled manual cash transaction',
    );
    return true;
  }

  /// مصروفات الفرع الأحدث أولاً (للمراجعة قبل الإلغاء).
  Future<List<Map<String, Object?>>> listRecentExpenses({int limit = 150}) async {
    final s = _mustSession();
    final db = await _databaseService.database;
    return db.query(
      'expenses',
      where: 'organizationId = ? AND branchId = ?',
      whereArgs: [s.organizationId, s.branchId],
      orderBy: 'expenseDate DESC',
      limit: limit,
    );
  }

  /// حذف مصروف محدّد مع صف الصندوق المرتبط (`referenceType = expense`).
  Future<bool> cancelExpenseWithCashById(String expenseId) async {
    final s = _mustSession();
    final eid = expenseId.trim();
    if (eid.isEmpty) return false;
    final db = await _databaseService.database;
    final rows = await db.query(
      'expenses',
      where: 'id = ? AND organizationId = ? AND branchId = ?',
      whereArgs: [eid, s.organizationId, s.branchId],
      limit: 1,
    );
    if (rows.isEmpty) return false;
    await db.transaction((txn) async {
      await txn.delete('expenses', where: 'id = ?', whereArgs: [eid]);
      await txn.delete(
        'cashTransactions',
        where:
            'organizationId = ? AND branchId = ? AND referenceType = ? AND referenceId = ?',
        whereArgs: [s.organizationId, s.branchId, 'expense', eid],
      );
    });
    await _audit(
      'delete',
      'expense',
      eid,
      'Cancelled expense with cash impact',
    );
    return true;
  }

  /// سندات قبض/صرف مرتبطة بعميل أو مورد (`customer_payment` / `supplier_payment`) مع صف الصندوق.
  Future<List<Map<String, Object?>>> listPartnerPaymentVouchers({
    required String partnerKind,
    String? voucherSearch,
    int limit = 80,
  }) async {
    final s = _mustSession();
    if (partnerKind != 'customer' && partnerKind != 'supplier') {
      throw Exception('نوع الشريك غير صالح.');
    }
    final refType =
        partnerKind == 'customer' ? 'customer_payment' : 'supplier_payment';
    final partnerTable = partnerKind == 'customer' ? 'customers' : 'suppliers';
    final db = await _databaseService.database;
    final q = voucherSearch?.trim() ?? '';
    final args = <Object?>[
      s.organizationId,
      s.branchId,
      partnerKind,
      refType,
    ];
    var voucherClause = '';
    if (q.isNotEmpty) {
      final low = '%${q.toLowerCase()}%';
      voucherClause =
          ' AND (IFNULL(pl.voucherNumber, \'\') LIKE ? OR LOWER(pl.referenceId) LIKE ? OR LOWER(ct.id) LIKE ?) ';
      args.add('%$q%');
      args.add(low);
      args.add(low);
    }
    args.add(limit);
    final sql =
        'SELECT pl.referenceId AS paymentId, pl.voucherNumber AS voucherNumber, '
        'pl.partnerId AS partnerId, '
        "COALESCE(p.name, '') AS partnerName, "
        'pl.notes AS ledgerNotes, pl.entryDate AS entryDate, '
        'ct.amount AS amount, ct.description AS cashDescription, '
        'ct.transactionDate AS transactionDate, ct.id AS cashRowId '
        'FROM partnerLedger pl '
        'INNER JOIN cashTransactions ct ON '
        'ct.organizationId = pl.organizationId AND ct.branchId = pl.branchId '
        'AND ct.referenceId = pl.referenceId AND ct.referenceType = pl.referenceType '
        'LEFT JOIN $partnerTable p ON p.id = pl.partnerId '
        'AND p.organizationId = pl.organizationId AND p.branchId = pl.branchId '
        'WHERE pl.organizationId = ? AND pl.branchId = ? '
        'AND pl.partnerKind = ? AND pl.referenceType = ? '
        '$voucherClause'
        'ORDER BY ct.transactionDate DESC LIMIT ?';
    return db.rawQuery(sql, args);
  }

  /// آخر مدفوعات العملاء والموردات مجتمعة (تسديد / سداد ذمة)، مرتبة زمنياً.
  Future<List<Map<String, Object?>>> listMergedPartnerPayments({
    String? movementQuery,
    int limit = 80,
  }) async {
    final c = await listPartnerPaymentVouchers(
      partnerKind: 'customer',
      voucherSearch: movementQuery,
      limit: limit,
    );
    final sup = await listPartnerPaymentVouchers(
      partnerKind: 'supplier',
      voucherSearch: movementQuery,
      limit: limit,
    );
    final merged = <Map<String, Object?>>[
      ...c.map((r) => <String, Object?>{...r, 'ledgerPartnerKind': 'customer'}),
      ...sup.map((r) => <String, Object?>{...r, 'ledgerPartnerKind': 'supplier'}),
    ];
    int sortKey(Map<String, Object?> r) {
      final raw = r['transactionDate'] as String? ?? '';
      final dt = DateTime.tryParse(raw);
      if (dt == null) return 0;
      return dt.millisecondsSinceEpoch;
    }

    merged.sort((a, b) => sortKey(b).compareTo(sortKey(a)));
    if (merged.length <= limit) return merged;
    return merged.sublist(0, limit);
  }

  /// إلغاء سند تسديد عميل/مورد: حذف حركة الصندوق وسطر دفتر الشركاء لنفس `referenceId`.
  Future<bool> cancelPartnerPayment({
    required String partnerKind,
    required String paymentReferenceId,
  }) async {
    final s = _mustSession();
    if (partnerKind != 'customer' && partnerKind != 'supplier') {
      return false;
    }
    final pid = paymentReferenceId.trim();
    if (pid.isEmpty) return false;
    final refType =
        partnerKind == 'customer' ? 'customer_payment' : 'supplier_payment';
    final db = await _databaseService.database;
    final rows = await db.query(
      'partnerLedger',
      where:
          'organizationId = ? AND branchId = ? AND partnerKind = ? AND referenceType = ? AND referenceId = ?',
      whereArgs: [s.organizationId, s.branchId, partnerKind, refType, pid],
      limit: 1,
    );
    if (rows.isEmpty) return false;
    await db.transaction((txn) async {
      await txn.delete(
        'cashTransactions',
        where:
            'organizationId = ? AND branchId = ? AND referenceType = ? AND referenceId = ?',
        whereArgs: [s.organizationId, s.branchId, refType, pid],
      );
      await txn.delete(
        'partnerLedger',
        where:
            'organizationId = ? AND branchId = ? AND referenceType = ? AND referenceId = ?',
        whereArgs: [s.organizationId, s.branchId, refType, pid],
      );
    });
    await _audit('delete', refType, pid, 'Cancelled partner payment');
    return true;
  }

  Future<Map<String, Object?>> kpiSummary() async {
    final s = _mustSession();
    final db = await _databaseService.database;
    final sales = (await db.rawQuery(
      'SELECT IFNULL(SUM(total), 0) AS total FROM salesInvoices '
      'WHERE organizationId = ? AND branchId = ? AND ${AccountingService._sqlPostedSalesRevenueAlias('salesInvoices')}',
      [s.organizationId, s.branchId],
    )).first['total'] as num;
    final purchases = (await db.rawQuery(
      'SELECT IFNULL(SUM(total), 0) AS total FROM purchaseInvoices '
      'WHERE organizationId = ? AND branchId = ? AND ${AccountingService._sqlInvoicePostedAlias('purchaseInvoices')}',
      [s.organizationId, s.branchId],
    )).first['total'] as num;
    final expenses = (await db.rawQuery(
      'SELECT IFNULL(SUM(amount), 0) AS total FROM expenses WHERE organizationId = ? AND branchId = ?',
      [s.organizationId, s.branchId],
    )).first['total'] as num;
    final stockValue = (await db.rawQuery(
      'SELECT IFNULL(SUM(stockQty * costPrice), 0) AS total FROM products '
      'WHERE organizationId = ? AND branchId = ? AND IFNULL(isFrozen,0) = 0',
      [s.organizationId, s.branchId],
    )).first['total'] as num;
    final cashIn = (await db.rawQuery(
      "SELECT IFNULL(SUM(amount), 0) AS total FROM cashTransactions WHERE organizationId = ? AND branchId = ? AND transactionType = 'in'",
      [s.organizationId, s.branchId],
    )).first['total'] as num;
    final cashOut = (await db.rawQuery(
      "SELECT IFNULL(SUM(amount), 0) AS total FROM cashTransactions WHERE organizationId = ? AND branchId = ? AND transactionType = 'out'",
      [s.organizationId, s.branchId],
    )).first['total'] as num;

    return {
      'sales': sales.toDouble(),
      'purchases': purchases.toDouble(),
      'expenses': expenses.toDouble(),
      'stockValue': stockValue.toDouble(),
      'cashBalance': (cashIn - cashOut).toDouble(),
    };
  }

  /// نفس مفاتيح [kpiSummary]؛ المبيعات/المشتريات/المصروفات/صافي الصندوق ضمن
  /// [from]…[toInclusive]، وقيمة المخزون **لحظية** (لا تُفلتر بالفترة).
  Future<Map<String, Object?>> kpiSummaryForRange(
    DateTime from,
    DateTime toInclusive,
  ) async {
    final ranged = await kpiTotalsBetween(from, toInclusive);
    final s = _mustSession();
    final db = await _databaseService.database;
    final stockValue = (await db.rawQuery(
      'SELECT IFNULL(SUM(stockQty * costPrice), 0) AS total FROM products '
      'WHERE organizationId = ? AND branchId = ? AND IFNULL(isFrozen,0) = 0',
      [s.organizationId, s.branchId],
    )).first['total'] as num;
    return {
      'sales': ranged['sales']!,
      'purchases': ranged['purchases']!,
      'expenses': ranged['expenses']!,
      'stockValue': stockValue.toDouble(),
      'cashBalance': ranged['cashNet']!,
    };
  }

  /// مبيعات / مشتريات / مصروفات / صافي حركة الصندوق بين تاريخين (شامل نهاية اليوم).
  Future<Map<String, double>> kpiTotalsBetween(DateTime from, DateTime toInclusive) async {
    final s = _mustSession();
    final db = await _databaseService.database;
    final t0 = isoDayStart(from);
    final t1 = isoDayEnd(toInclusive);
    final postedS = AccountingService._sqlPostedSalesRevenueAlias('salesInvoices');
    final postedP = AccountingService._sqlInvoicePostedAlias('purchaseInvoices');
    final saleRow = await db.rawQuery(
      'SELECT IFNULL(SUM(total), 0) AS total FROM salesInvoices '
      'WHERE organizationId = ? AND branchId = ? AND $postedS '
      'AND invoiceDate >= ? AND invoiceDate <= ?',
      [s.organizationId, s.branchId, t0, t1],
    );
    final purchaseRow = await db.rawQuery(
      'SELECT IFNULL(SUM(total), 0) AS total FROM purchaseInvoices '
      'WHERE organizationId = ? AND branchId = ? AND $postedP '
      'AND invoiceDate >= ? AND invoiceDate <= ?',
      [s.organizationId, s.branchId, t0, t1],
    );
    final expenseRow = await db.rawQuery(
      'SELECT IFNULL(SUM(amount), 0) AS total FROM expenses '
      'WHERE organizationId = ? AND branchId = ? '
      'AND expenseDate >= ? AND expenseDate <= ?',
      [s.organizationId, s.branchId, t0, t1],
    );
    final cashInRow = await db.rawQuery(
      "SELECT IFNULL(SUM(amount), 0) AS total FROM cashTransactions "
      "WHERE organizationId = ? AND branchId = ? AND transactionType = 'in' "
      'AND transactionDate >= ? AND transactionDate <= ?',
      [s.organizationId, s.branchId, t0, t1],
    );
    final cashOutRow = await db.rawQuery(
      "SELECT IFNULL(SUM(amount), 0) AS total FROM cashTransactions "
      "WHERE organizationId = ? AND branchId = ? AND transactionType = 'out' "
      'AND transactionDate >= ? AND transactionDate <= ?',
      [s.organizationId, s.branchId, t0, t1],
    );
    final saleT = (saleRow.first['total'] as num?)?.toDouble() ?? 0;
    final purchaseT = (purchaseRow.first['total'] as num?)?.toDouble() ?? 0;
    final expenseT = (expenseRow.first['total'] as num?)?.toDouble() ?? 0;
    final cin = (cashInRow.first['total'] as num?)?.toDouble() ?? 0;
    final cout = (cashOutRow.first['total'] as num?)?.toDouble() ?? 0;
    return {
      'sales': saleT,
      'purchases': purchaseT,
      'expenses': expenseT,
      'cashNet': cin - cout,
    };
  }

  /// مقارنة **هذا الشهر حتى اليوم** مع **الشهر التقويمي السابق كاملاً**.
  Future<Map<String, Map<String, double>>> dashboardMonthOverMonth() async {
    final now = DateTime.now();
    final currentMonthStart = DateTime(now.year, now.month, 1);
    final currentMonthThroughToday = DateTime(now.year, now.month, now.day);
    final lastDayPrevMonth = DateTime(now.year, now.month, 0);
    final previousMonthStart = DateTime(lastDayPrevMonth.year, lastDayPrevMonth.month, 1);
    final cur = await kpiTotalsBetween(currentMonthStart, currentMonthThroughToday);
    final prev = await kpiTotalsBetween(previousMonthStart, lastDayPrevMonth);
    return {
      'currentMonth': cur,
      'previousMonth': prev,
    };
  }

  /// أصناف رصيدها عند أو تحت الحد (افتراضي 5).
  Future<List<Map<String, Object?>>> lowStockProducts({
    double maxStockQty = 5,
    int limit = 18,
  }) async {
    final s = _mustSession();
    final db = await _databaseService.database;
    return db.rawQuery(
      'SELECT id, name, stockQty, salePrice, costPrice FROM products '
      'WHERE organizationId = ? AND branchId = ? AND stockQty <= ? '
      'AND IFNULL(isHidden,0) = 0 AND IFNULL(isFrozen,0) = 0 '
      'ORDER BY stockQty ASC, name COLLATE NOCASE LIMIT ?',
      [s.organizationId, s.branchId, maxStockQty, limit],
    );
  }

  /// موردون لديهم ذمة مستحقة بحسب [suppliers.overdueAlertDays] وتاريخ آخر فاتورة
  /// (يُعتبر «اليوم» عندما مضت على الفاتورة نفس عدد أيام التنبيه، و«متأخراً» بعدها).
  Future<List<Map<String, Object?>>> supplierDeferredPaymentReminders({
    int limit = 32,
  }) async {
    final rows = await supplierBalancesCheckReport();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final out = <Map<String, Object?>>[];
    for (final r in rows) {
      final balanceDue = ((r['balanceDue'] as num?) ?? 0).toDouble();
      if (balanceDue <= 0.0001) continue;
      final overdueAlertDays = (r['overdueAlertDays'] as int?) ??
          int.tryParse((r['overdueAlertDays'] ?? '').toString());
      if (overdueAlertDays == null || overdueAlertDays <= 0) continue;
      final lastInvoiceRaw = (r['lastInvoiceDate'] ?? '').toString().trim();
      if (lastInvoiceRaw.isEmpty) continue;
      final lastInvoiceDate = DateTime.tryParse(lastInvoiceRaw);
      if (lastInvoiceDate == null) continue;
      final lastDay = DateTime(
        lastInvoiceDate.year,
        lastInvoiceDate.month,
        lastInvoiceDate.day,
      );
      final overdueDays = today.difference(lastDay).inDays;
      if (overdueDays < overdueAlertDays) continue;
      final payStatus =
          overdueDays > overdueAlertDays ? 'overdue' : 'due_today';
      out.add({
        ...r,
        'overdueDays': overdueDays,
        'payStatus': payStatus,
        'balanceDue': balanceDue,
      });
      if (out.length >= limit) break;
    }
    out.sort((a, b) {
      final pa = (a['payStatus'] as String) == 'overdue' ? 0 : 1;
      final pb = (b['payStatus'] as String) == 'overdue' ? 0 : 1;
      if (pa != pb) return pa.compareTo(pb);
      final da = (a['overdueDays'] as int?) ?? 0;
      final db = (b['overdueDays'] as int?) ?? 0;
      return db.compareTo(da);
    });
    return out;
  }

  String _safeLikeFragment(String raw) {
    return raw.trim().replaceAll('%', '').replaceAll('_', '').replaceAll("'", '');
  }

  /// بحث موحّد: عملاء، أصناف، فواتير بيع/شراء (مطابقة جزئية لاسم أو معرّف).
  Future<List<Map<String, Object?>>> globalQuickSearch(
    String rawQuery, {
    int limitPerCategory = 8,
  }) async {
    final needle = _safeLikeFragment(rawQuery);
    if (needle.isEmpty) return [];
    final s = _mustSession();
    final db = await _databaseService.database;
    final like = '%$needle%';
    final hits = <Map<String, Object?>>[];
    final postedS = AccountingService._sqlInvoicePostedAlias('s');
    final postedP = AccountingService._sqlInvoicePostedAlias('p');

    final customers = await db.rawQuery(
      'SELECT id, name, phone FROM customers '
      'WHERE organizationId = ? AND branchId = ? '
      'AND (name LIKE ? COLLATE NOCASE OR IFNULL(phone, \'\') LIKE ? COLLATE NOCASE) '
      'ORDER BY name COLLATE NOCASE LIMIT ?',
      [s.organizationId, s.branchId, like, like, limitPerCategory],
    );
    for (final row in customers) {
      hits.add({
        'hitType': 'customer',
        'id': row['id'],
        'title': row['name'],
        'subtitle': (row['phone'] ?? '').toString().isEmpty ? 'عميل' : row['phone'],
      });
    }

    final products = await db.rawQuery(
      'SELECT id, name, stockQty FROM products '
      'WHERE organizationId = ? AND branchId = ? '
      'AND IFNULL(isHidden,0) = 0 AND IFNULL(isFrozen,0) = 0 '
      'AND name LIKE ? COLLATE NOCASE '
      'ORDER BY name COLLATE NOCASE LIMIT ?',
      [s.organizationId, s.branchId, like, limitPerCategory],
    );
    for (final row in products) {
      hits.add({
        'hitType': 'product',
        'id': row['id'],
        'title': row['name'],
        'subtitle': 'مخزون: ${row['stockQty']}',
      });
    }

    final saleInv = await db.rawQuery(
      'SELECT s.id, s.invoiceDate, s.total, s.paymentType, '
      'COALESCE(c.name, \'عميل نقدي\') AS partnerName '
      'FROM salesInvoices s '
      'LEFT JOIN customers c ON c.id = s.customerId '
      'WHERE s.organizationId = ? AND s.branchId = ? AND $postedS '
      'AND s.id LIKE ? COLLATE NOCASE '
      'ORDER BY s.invoiceDate DESC LIMIT ?',
      [s.organizationId, s.branchId, like, limitPerCategory],
    );
    for (final row in saleInv) {
      hits.add({
        'hitType': 'sale_invoice',
        'id': row['id'],
        'title': 'فاتورة بيع',
        'subtitle':
            '${row['partnerName']} — ${row['total']} (${row['paymentType']}) — ${row['invoiceDate']}',
      });
    }

    final purchaseInv = await db.rawQuery(
      'SELECT p.id, p.invoiceDate, p.total, p.paymentType, '
      'COALESCE(sp.name, \'مورد نقدي\') AS partnerName '
      'FROM purchaseInvoices p '
      'LEFT JOIN suppliers sp ON sp.id = p.supplierId '
      'WHERE p.organizationId = ? AND p.branchId = ? AND $postedP '
      'AND p.id LIKE ? COLLATE NOCASE '
      'ORDER BY p.invoiceDate DESC LIMIT ?',
      [s.organizationId, s.branchId, like, limitPerCategory],
    );
    for (final row in purchaseInv) {
      hits.add({
        'hitType': 'purchase_invoice',
        'id': row['id'],
        'title': 'فاتورة شراء',
        'subtitle':
            '${row['partnerName']} — ${row['total']} (${row['paymentType']}) — ${row['invoiceDate']}',
      });
    }

    return hits;
  }

  Future<List<Map<String, Object?>>> inventoryReport() async {
    final s = _mustSession();
    final db = await _databaseService.database;
    return db.rawQuery(
      'SELECT name, stockQty, costPrice, salePrice, (stockQty * costPrice) AS stockValue '
      'FROM products WHERE organizationId = ? AND branchId = ? '
      'AND IFNULL(isFrozen,0) = 0 ORDER BY name',
      [s.organizationId, s.branchId],
    );
  }

  Future<List<Map<String, Object?>>> inventoryReportByCategory() async {
    final s = _mustSession();
    final db = await _databaseService.database;
    return db.rawQuery(
      'SELECT IFNULL(c.name, \'-\') AS categoryName, p.name AS productName, '
      'p.stockQty, p.costPrice, p.salePrice, (p.stockQty * p.costPrice) AS stockValue '
      'FROM products p '
      'LEFT JOIN product_categories c ON c.id = p.categoryId '
      'AND c.organizationId = p.organizationId AND c.branchId = p.branchId '
      'WHERE p.organizationId = ? AND p.branchId = ? '
      'AND IFNULL(p.isFrozen,0) = 0 '
      'ORDER BY categoryName COLLATE NOCASE, p.name COLLATE NOCASE',
      [s.organizationId, s.branchId],
    );
  }

  Future<List<Map<String, Object?>>> customerBalancesReport() async {
    final s = _mustSession();
    final db = await _databaseService.database;
    return db.rawQuery(
      'SELECT c.id, c.name, '
      'IFNULL((SELECT SUM(pl.amountSigned) FROM partnerLedger pl '
      'WHERE pl.organizationId = c.organizationId AND pl.branchId = c.branchId '
      'AND pl.partnerKind = \'customer\' AND pl.partnerId = c.id), 0) AS balanceDue '
      'FROM customers c '
      'WHERE c.organizationId = ? AND c.branchId = ? '
      'ORDER BY c.name',
      [s.organizationId, s.branchId],
    );
  }

  Future<List<Map<String, Object?>>> customerBalancesCheckReport() async {
    final s = _mustSession();
    final db = await _databaseService.database;
    final posted = AccountingService._sqlInvoicePostedAlias('si');
    return db.rawQuery(
      'SELECT c.id, c.customerNumber, c.name, c.phone, c.address, c.creditLimit, c.overdueAlertDays, c.notes, '
      'IFNULL((SELECT SUM(pl.amountSigned) FROM partnerLedger pl '
      'WHERE pl.organizationId = c.organizationId AND pl.branchId = c.branchId '
      'AND pl.partnerKind = \'customer\' AND pl.partnerId = c.id), 0) AS balanceDue, '
      '(SELECT MAX(si.invoiceDate) FROM salesInvoices si WHERE si.organizationId = c.organizationId '
      'AND si.branchId = c.branchId AND si.customerId = c.id AND $posted) AS lastInvoiceDate '
      'FROM customers c '
      'WHERE c.organizationId = ? AND c.branchId = ? '
      'ORDER BY c.name COLLATE NOCASE',
      [s.organizationId, s.branchId],
    );
  }

  /// مجموع دفتر الشريك لكل عميل (موجب أو سالب أو صفر)، بخلاف [customersReceivablesDebtsSplitReport]
  /// الذي يقتصر على من لديهم إجمالي دفتر موجب فقط.
  Future<List<Map<String, Object?>>> customersPartnerLedgerBalanceTotalsReport() async {
    final s = _mustSession();
    final db = await _databaseService.database;
    return db.rawQuery(
      'SELECT c.id, '
      'IFNULL((SELECT SUM(pl.amountSigned) FROM partnerLedger pl '
      'WHERE pl.organizationId = c.organizationId AND pl.branchId = c.branchId '
      'AND pl.partnerKind = \'customer\' AND pl.partnerId = c.id), 0) AS balanceTotal '
      'FROM customers c '
      'WHERE c.organizationId = ? AND c.branchId = ? '
      'ORDER BY c.name COLLATE NOCASE',
      [s.organizationId, s.branchId],
    );
  }

  Future<Map<String, Object?>?> customerRiskStatus(String customerId) async {
    return _partnerRiskStatus(
      partnerId: customerId,
      table: 'customers',
      partnerKind: 'customer',
      numberColumn: 'customerNumber',
      invoiceTable: 'salesInvoices',
      invoiceAlias: 'si',
      invoicePartnerColumn: 'customerId',
    );
  }

  Future<List<Map<String, Object?>>> customersOutstandingReport() async {
    final s = _mustSession();
    final db = await _databaseService.database;
    final posted = AccountingService._sqlInvoicePostedAlias('si');
    return db.rawQuery(
      'SELECT * FROM ( '
      'SELECT c.id, c.customerNumber, c.name, c.phone, c.address, '
      'IFNULL((SELECT SUM(pl.amountSigned) FROM partnerLedger pl '
      'WHERE pl.organizationId = c.organizationId AND pl.branchId = c.branchId '
      'AND pl.partnerKind = \'customer\' AND pl.partnerId = c.id), 0) AS balanceDue, '
      '(SELECT COUNT(*) FROM salesInvoices si WHERE si.organizationId = c.organizationId '
      'AND si.branchId = c.branchId AND si.customerId = c.id AND $posted) AS invoicesCount, '
      '(SELECT MAX(si.invoiceDate) FROM salesInvoices si WHERE si.organizationId = c.organizationId '
      'AND si.branchId = c.branchId AND si.customerId = c.id AND $posted) AS lastInvoiceDate '
      'FROM customers c '
      'WHERE c.organizationId = ? AND c.branchId = ? '
      ') t WHERE t.balanceDue > 0.0001 ORDER BY t.balanceDue DESC',
      [s.organizationId, s.branchId],
    );
  }

  /// ذمم العملاء مع تقسيم تقريبي: فواتير آجل (بأصناف) مقابل رصيد افتتاحي (فاتورة بدون أصناف)،
  /// مع توزيع باقي حركات الدفتر (دفعات، مرتجعات…) بين العمودين تناسبياً.
  Future<List<Map<String, Object?>>> customersReceivablesDebtsSplitReport() async {
    final s = _mustSession();
    final db = await _databaseService.database;
    final posted = AccountingService._sqlInvoicePostedAlias('si');
    return db.rawQuery(
      'WITH '
      'base_def AS ( '
      '  SELECT pl.partnerId AS cid, SUM(pl.amountSigned) AS amt '
      '  FROM partnerLedger pl '
      '  INNER JOIN salesInvoices si ON si.id = pl.referenceId AND pl.referenceType = \'sale\' '
      '  WHERE pl.organizationId = ? AND pl.branchId = ? AND pl.partnerKind = \'customer\' '
      '  AND si.organizationId = pl.organizationId AND si.branchId = pl.branchId '
      '  AND si.paymentType = \'deferred\' AND $posted '
      '  AND EXISTS (SELECT 1 FROM salesInvoiceItems ii WHERE ii.invoiceId = si.id) '
      '  GROUP BY pl.partnerId '
      '), '
      'base_open AS ( '
      '  SELECT pl.partnerId AS cid, SUM(pl.amountSigned) AS amt '
      '  FROM partnerLedger pl '
      '  INNER JOIN salesInvoices si ON si.id = pl.referenceId AND pl.referenceType = \'sale\' '
      '  WHERE pl.organizationId = ? AND pl.branchId = ? AND pl.partnerKind = \'customer\' '
      '  AND si.organizationId = pl.organizationId AND si.branchId = pl.branchId '
      '  AND si.paymentType = \'deferred\' AND $posted '
      '  AND NOT EXISTS (SELECT 1 FROM salesInvoiceItems ii WHERE ii.invoiceId = si.id) '
      '  GROUP BY pl.partnerId '
      '), '
      'tot AS ( '
      '  SELECT pl.partnerId AS cid, SUM(pl.amountSigned) AS amt '
      '  FROM partnerLedger pl '
      '  WHERE pl.organizationId = ? AND pl.branchId = ? AND pl.partnerKind = \'customer\' '
      '  GROUP BY pl.partnerId '
      ') '
      'SELECT c.id, c.name, '
      'IFNULL(t.amt, 0) AS balanceTotal, '
      'CASE '
      '  WHEN ABS(IFNULL(d.amt, 0) + IFNULL(o.amt, 0)) < 0.0001 THEN 0.0 '
      '  ELSE IFNULL(d.amt, 0) + (IFNULL(t.amt, 0) - IFNULL(d.amt, 0) - IFNULL(o.amt, 0)) '
      '       * (IFNULL(d.amt, 0) / (IFNULL(d.amt, 0) + IFNULL(o.amt, 0))) '
      'END AS balanceDeferredInvoices, '
      'CASE '
      '  WHEN ABS(IFNULL(d.amt, 0) + IFNULL(o.amt, 0)) < 0.0001 THEN IFNULL(t.amt, 0) '
      '  ELSE IFNULL(o.amt, 0) + (IFNULL(t.amt, 0) - IFNULL(d.amt, 0) - IFNULL(o.amt, 0)) '
      '       * (IFNULL(o.amt, 0) / (IFNULL(d.amt, 0) + IFNULL(o.amt, 0))) '
      'END AS balanceOpeningCash '
      'FROM customers c '
      'INNER JOIN tot t ON t.cid = c.id AND t.amt > 0.0001 '
      'LEFT JOIN base_def d ON d.cid = c.id '
      'LEFT JOIN base_open o ON o.cid = c.id '
      'WHERE c.organizationId = ? AND c.branchId = ? '
      'ORDER BY t.amt DESC',
      [
        s.organizationId,
        s.branchId,
        s.organizationId,
        s.branchId,
        s.organizationId,
        s.branchId,
        s.organizationId,
        s.branchId,
      ],
    );
  }

  Future<List<Map<String, Object?>>> customerInvoicesReport(String customerId) async {
    final s = _mustSession();
    final db = await _databaseService.database;
    return db.query(
      'salesInvoices',
      where:
          'organizationId = ? AND branchId = ? AND customerId = ? AND ${AccountingService._sqlInvoicePostedAlias('salesInvoices')}',
      whereArgs: [s.organizationId, s.branchId, customerId],
      orderBy: 'invoiceDate DESC',
    );
  }

  Future<void> _insertCustomerOpeningBalanceCashIfNeeded(
    Transaction txn, {
    required CustomerOpeningBalanceCashEffect cashBoxEffect,
    required double amount,
    required String referenceId,
    required String description,
  }) async {
    if (cashBoxEffect == CustomerOpeningBalanceCashEffect.none) return;
    final type = cashBoxEffect == CustomerOpeningBalanceCashEffect.addToCashBox
        ? 'in'
        : 'out';
    await _insertCash(
      txn,
      CashTransactionInput(
        type: type,
        amount: amount,
        description: description,
        referenceType: 'customer_opening_balance',
        referenceId: referenceId,
      ),
    );
  }

  Future<String> addCustomerOpeningBalance({
    required String customerId,
    required double amount,
    bool customerOwesUs = true,
    String paymentType = 'deferred',
    DateTime? entryDate,
    String? voucherNumber,
    /// يُستخدم عند الترقيم التلقائي فقط (`[prefix]-[تسلسل]`).
    String openingVoucherPrefix = OpeningBalanceVoucherConfig.defaultPrefix,
    String? statement,
    CustomerOpeningBalanceCashEffect cashBoxEffect =
        CustomerOpeningBalanceCashEffect.none,
  }) async {
    final s = _mustSession();
    final db = await _databaseService.database;
    if (amount <= 0) {
      throw Exception('الرصيد الافتتاحي يجب أن يكون أكبر من صفر.');
    }
    final when = entryDate ?? DateTime.now();
    final stmt = statement?.trim();
    final notes = _openingBalanceNotes(
      customerOwesUs: customerOwesUs,
      statement: stmt,
    );

    if (customerOwesUs) {
      final invoiceId = _uuid.v4();
      await db.transaction((txn) async {
        final vn = await _resolveCustomerOpeningVoucherNumber(
          txn,
          voucherNumber,
          autoPrefix: openingVoucherPrefix,
        );
        await txn.insert('salesInvoices', {
          'id': invoiceId,
          'organizationId': s.organizationId,
          'branchId': s.branchId,
          'customerId': customerId,
          'invoiceDate': when.toIso8601String(),
          'total': amount,
          'paymentType': paymentType,
          'invoiceStatus': 'posted',
          'createdBy': s.userId,
          if (stmt != null && stmt.isNotEmpty) 'notes': stmt,
        });
        if (MizaPaymentTypes.isDeferred(paymentType)) {
          await _insertPartnerLedger(
            txn,
            partnerKind: 'customer',
            partnerId: customerId,
            entryType: 'sale_ar',
            referenceType: 'sale',
            referenceId: invoiceId,
            amountSigned: amount,
            notes: notes,
            entryDate: when,
            voucherNumber: vn,
          );
        }
        await _insertCustomerOpeningBalanceCashIfNeeded(
          txn,
          cashBoxEffect: cashBoxEffect,
          amount: amount,
          referenceId: invoiceId,
          description: notes.isEmpty ? 'رصيد افتتاحي عميل (عليه)' : notes,
        );
      });
      await _audit('create', 'customer_opening_balance', invoiceId, 'Added customer opening AR');
      return invoiceId;
    }

    final openingId = _uuid.v4();
    await db.transaction((txn) async {
      final vn = await _resolveCustomerOpeningVoucherNumber(
        txn,
        voucherNumber,
        autoPrefix: openingVoucherPrefix,
      );
      await _insertPartnerLedger(
        txn,
        partnerKind: 'customer',
        partnerId: customerId,
        entryType: 'opening_balance',
        referenceType: 'opening_balance',
        referenceId: openingId,
        amountSigned: -amount,
        notes: notes,
        entryDate: when,
        voucherNumber: vn,
      );
      await _insertCustomerOpeningBalanceCashIfNeeded(
        txn,
        cashBoxEffect: cashBoxEffect,
        amount: amount,
        referenceId: openingId,
        description: notes.isEmpty ? 'رصيد افتتاحي عميل (له)' : notes,
      );
    });
    await _audit('create', 'customer_opening_balance', openingId, 'Added customer opening credit');
    return openingId;
  }

  /// كل أرصدة افتتاحية لعميل (عليه كفاتورة بدون بنود، أو له كقيد دفتر).
  Future<List<Map<String, Object?>>> listCustomerOpeningBalances(
    String customerId,
  ) async {
    final s = _mustSession();
    final db = await _databaseService.database;
    final cid = customerId.trim();
    if (cid.isEmpty) return const [];

    final out = <Map<String, Object?>>[];

    final arRows = await db.rawQuery(
      '''SELECT s.id AS referenceId, s.invoiceDate AS entryDate, s.total AS amount,
                COALESCE(pl.voucherNumber, '') AS voucherNumber
         FROM salesInvoices s
         LEFT JOIN partnerLedger pl ON pl.referenceId = s.id
           AND pl.referenceType = 'sale'
           AND pl.partnerKind = 'customer'
           AND pl.partnerId = s.customerId
           AND pl.entryType = 'sale_ar'
         WHERE s.organizationId = ? AND s.branchId = ? AND s.customerId = ?
           AND ${AccountingService._sqlInvoicePostedAlias('s')}
           AND NOT EXISTS (SELECT 1 FROM salesInvoiceItems i WHERE i.invoiceId = s.id)
         ORDER BY s.invoiceDate DESC''',
      [s.organizationId, s.branchId, cid],
    );
    for (final row in arRows) {
      final amount = ((row['amount'] as num?) ?? 0).toDouble();
      if (amount <= 1e-9) continue;
      out.add({
        'referenceId': row['referenceId'],
        'customerOwesUs': true,
        'voucherNumber': row['voucherNumber'],
        'amount': amount,
        'entryDate': row['entryDate'],
      });
    }

    final creditRows = await db.rawQuery(
      '''SELECT referenceId, entryDate, amountSigned, voucherNumber
         FROM partnerLedger
         WHERE organizationId = ? AND branchId = ?
           AND partnerKind = 'customer' AND partnerId = ?
           AND entryType = 'opening_balance' AND referenceType = 'opening_balance'
         ORDER BY entryDate DESC''',
      [s.organizationId, s.branchId, cid],
    );
    for (final row in creditRows) {
      final amount = ((row['amountSigned'] as num?) ?? 0).toDouble().abs();
      if (amount <= 1e-9) continue;
      out.add({
        'referenceId': row['referenceId'],
        'customerOwesUs': false,
        'voucherNumber': row['voucherNumber'],
        'amount': amount,
        'entryDate': row['entryDate'],
      });
    }

    out.sort((a, b) {
      final ad = DateTime.tryParse((a['entryDate'] ?? '').toString());
      final bd = DateTime.tryParse((b['entryDate'] ?? '').toString());
      if (ad == null && bd == null) return 0;
      if (ad == null) return 1;
      if (bd == null) return -1;
      return bd.compareTo(ad);
    });
    return out;
  }

  Future<void> deleteCustomerOpeningBalance({
    required String customerId,
    required String referenceId,
    required bool customerOwesUs,
  }) async {
    _requireRegisteredOperationalAccess();
    final s = _mustSession();
    final db = await _databaseService.database;
    final cid = customerId.trim();
    final ref = referenceId.trim();
    if (cid.isEmpty || ref.isEmpty) {
      throw Exception('معرّف غير صالح.');
    }

    await db.transaction((txn) async {
      if (customerOwesUs) {
        final invRows = await txn.query(
          'salesInvoices',
          where:
              'id = ? AND organizationId = ? AND branchId = ? AND customerId = ?',
          whereArgs: [ref, s.organizationId, s.branchId, cid],
          limit: 1,
        );
        if (invRows.isEmpty) {
          throw Exception('الرصيد الافتتاحي غير موجود.');
        }
        final itemCount = Sqflite.firstIntValue(
              await txn.rawQuery(
                'SELECT COUNT(*) FROM salesInvoiceItems WHERE invoiceId = ?',
                [ref],
              ),
            ) ??
            0;
        if (itemCount > 0) {
          throw Exception('لا يمكن حذف فاتورة بيع عادية من هنا.');
        }

        await txn.delete(
          'partnerLedger',
          where:
              'organizationId = ? AND branchId = ? AND referenceType = ? AND referenceId = ?',
          whereArgs: [s.organizationId, s.branchId, 'sale', ref],
        );
        await txn.delete(
          'cashTransactions',
          where:
              'organizationId = ? AND branchId = ? AND referenceType = ? AND referenceId = ?',
          whereArgs: [
            s.organizationId,
            s.branchId,
            'customer_opening_balance',
            ref,
          ],
        );
        await txn.delete(
          'cashTransactions',
          where:
              'organizationId = ? AND branchId = ? AND referenceType = ? AND referenceId = ?',
          whereArgs: [s.organizationId, s.branchId, 'sale', ref],
        );
        await txn.delete('salesInvoices', where: 'id = ?', whereArgs: [ref]);
        return;
      }

      final plRows = await txn.query(
        'partnerLedger',
        where:
            'organizationId = ? AND branchId = ? AND partnerKind = ? AND partnerId = ? AND referenceId = ? AND entryType = ? AND referenceType = ?',
        whereArgs: [
          s.organizationId,
          s.branchId,
          'customer',
          cid,
          ref,
          'opening_balance',
          'opening_balance',
        ],
        limit: 1,
      );
      if (plRows.isEmpty) {
        throw Exception('الرصيد الافتتاحي غير موجود.');
      }
      await txn.delete(
        'partnerLedger',
        where:
            'organizationId = ? AND branchId = ? AND partnerKind = ? AND partnerId = ? AND referenceId = ? AND entryType = ? AND referenceType = ?',
        whereArgs: [
          s.organizationId,
          s.branchId,
          'customer',
          cid,
          ref,
          'opening_balance',
          'opening_balance',
        ],
      );
      await txn.delete(
        'cashTransactions',
        where:
            'organizationId = ? AND branchId = ? AND referenceType = ? AND referenceId = ?',
        whereArgs: [
          s.organizationId,
          s.branchId,
          'customer_opening_balance',
          ref,
        ],
      );
    });
    await _audit(
      'delete',
      'customer_opening_balance',
      ref,
      'Deleted customer opening balance',
    );
  }

  String _openingBalanceNotes({
    required bool customerOwesUs,
    String? statement,
  }) {
    final parts = <String>[];
    if (statement != null && statement.isNotEmpty) {
      parts.add(statement);
    }
    parts.add(customerOwesUs ? 'رصيد افتتاحي (عليه)' : 'رصيد افتتاحي (له)');
    return parts.join(' — ');
  }

  Future<List<Map<String, Object?>>> supplierBalancesReport() async {
    final s = _mustSession();
    final db = await _databaseService.database;
    return db.rawQuery(
      'SELECT sp.name, '
      'IFNULL((SELECT SUM(pl.amountSigned) FROM partnerLedger pl '
      'WHERE pl.organizationId = sp.organizationId AND pl.branchId = sp.branchId '
      'AND pl.partnerKind = \'supplier\' AND pl.partnerId = sp.id), 0) AS balanceDue '
      'FROM suppliers sp '
      'WHERE sp.organizationId = ? AND sp.branchId = ? '
      'ORDER BY sp.name',
      [s.organizationId, s.branchId],
    );
  }

  Future<List<Map<String, Object?>>> supplierBalancesCheckReport() async {
    final s = _mustSession();
    final db = await _databaseService.database;
    final posted = AccountingService._sqlInvoicePostedAlias('pi');
    return db.rawQuery(
      'SELECT sp.id, sp.supplierNumber, sp.name, sp.phone, sp.address, sp.creditLimit, sp.overdueAlertDays, sp.notes, '
      'IFNULL((SELECT SUM(pl.amountSigned) FROM partnerLedger pl '
      'WHERE pl.organizationId = sp.organizationId AND pl.branchId = sp.branchId '
      'AND pl.partnerKind = \'supplier\' AND pl.partnerId = sp.id), 0) AS balanceDue, '
      '(SELECT MAX(pi.invoiceDate) FROM purchaseInvoices pi WHERE pi.organizationId = sp.organizationId '
      'AND pi.branchId = sp.branchId AND pi.supplierId = sp.id AND $posted) AS lastInvoiceDate '
      'FROM suppliers sp '
      'WHERE sp.organizationId = ? AND sp.branchId = ? '
      'ORDER BY sp.name COLLATE NOCASE',
      [s.organizationId, s.branchId],
    );
  }

  Future<Map<String, Object?>?> supplierRiskStatus(String supplierId) async {
    return _partnerRiskStatus(
      partnerId: supplierId,
      table: 'suppliers',
      partnerKind: 'supplier',
      numberColumn: 'supplierNumber',
      invoiceTable: 'purchaseInvoices',
      invoiceAlias: 'pi',
      invoicePartnerColumn: 'supplierId',
    );
  }

  Future<Map<String, Object?>?> _partnerRiskStatus({
    required String partnerId,
    required String table,
    required String partnerKind,
    required String numberColumn,
    required String invoiceTable,
    required String invoiceAlias,
    required String invoicePartnerColumn,
  }) async {
    final s = _mustSession();
    final db = await _databaseService.database;
    final posted = AccountingService._sqlInvoicePostedAlias(invoiceAlias);
    final rows = await db.rawQuery(
      'SELECT p.id, p.name, p.$numberColumn AS partnerNumber, p.creditLimit, p.overdueAlertDays, p.notes, '
      'IFNULL((SELECT SUM(pl.amountSigned) FROM partnerLedger pl '
      'WHERE pl.organizationId = p.organizationId AND pl.branchId = p.branchId '
      'AND pl.partnerKind = ? AND pl.partnerId = p.id), 0) AS balanceDue, '
      '(SELECT MAX($invoiceAlias.invoiceDate) FROM $invoiceTable $invoiceAlias '
      'WHERE $invoiceAlias.organizationId = p.organizationId '
      'AND $invoiceAlias.branchId = p.branchId '
      'AND $invoiceAlias.$invoicePartnerColumn = p.id AND $posted) AS lastInvoiceDate '
      'FROM $table p '
      'WHERE p.organizationId = ? AND p.branchId = ? AND p.id = ? LIMIT 1',
      [partnerKind, s.organizationId, s.branchId, partnerId],
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    final balanceDue = ((row['balanceDue'] as num?) ?? 0).toDouble();
    final creditLimit = ((row['creditLimit'] as num?) ?? 0).toDouble();
    final overdueAlertDays = (row['overdueAlertDays'] as int?) ??
        int.tryParse((row['overdueAlertDays'] ?? '').toString());
    final lastInvoiceRaw = (row['lastInvoiceDate'] ?? '').toString().trim();
    final lastInvoiceDate =
        lastInvoiceRaw.isEmpty ? null : DateTime.tryParse(lastInvoiceRaw);
    final overdueDays = lastInvoiceDate == null
        ? null
        : DateTime.now().difference(lastInvoiceDate).inDays;
    final isOverLimit = creditLimit > 0 && balanceDue > creditLimit;
    final isOverdue = overdueAlertDays != null &&
        overdueAlertDays > 0 &&
        overdueDays != null &&
        overdueDays > overdueAlertDays;
    return {
      ...row,
      'balanceDue': balanceDue,
      'creditLimit': creditLimit,
      'overdueAlertDays': overdueAlertDays,
      'overdueDays': overdueDays,
      'isOverLimit': isOverLimit,
      'isOverdue': isOverdue,
    };
  }

  /// معرفات العملاء ذوي التحذير (تجاوز سقف أو تأخر سداد) — استعلام واحد، بدلاً من N استعلام.
  Future<Set<String>> customerIdsWithCreditOrOverdueRisk() async {
    final rows = await customerBalancesCheckReport();
    return _partnerIdsWithRiskFromBalanceRows(rows);
  }

  /// معرفات الموردين ذوي التحذير — استعلام واحد.
  Future<Set<String>> supplierIdsWithCreditOrOverdueRisk() async {
    final rows = await supplierBalancesCheckReport();
    return _partnerIdsWithRiskFromBalanceRows(rows);
  }

  Set<String> _partnerIdsWithRiskFromBalanceRows(
    List<Map<String, Object?>> rows,
  ) {
    final now = DateTime.now();
    final risky = <String>{};
    for (final r in rows) {
      final id = r['id'] as String?;
      if (id == null) continue;
      final balanceDue = ((r['balanceDue'] as num?) ?? 0).toDouble();
      final creditLimit = ((r['creditLimit'] as num?) ?? 0).toDouble();
      final overdueAlertDays = (r['overdueAlertDays'] as int?) ??
          int.tryParse((r['overdueAlertDays'] ?? '').toString());
      final lastInvoiceRaw = (r['lastInvoiceDate'] ?? '').toString().trim();
      final lastInvoiceDate =
          lastInvoiceRaw.isEmpty ? null : DateTime.tryParse(lastInvoiceRaw);
      final overdueDays = lastInvoiceDate == null
          ? null
          : now.difference(lastInvoiceDate).inDays;
      final isOverLimit = creditLimit > 0 && balanceDue > creditLimit;
      final isOverdue = overdueAlertDays != null &&
          overdueAlertDays > 0 &&
          overdueDays != null &&
          overdueDays > overdueAlertDays;
      if (isOverLimit || isOverdue) {
        risky.add(id);
      }
    }
    return risky;
  }

  Future<List<Map<String, Object?>>> suppliersOutstandingReport() async {
    final s = _mustSession();
    final db = await _databaseService.database;
    final posted = AccountingService._sqlInvoicePostedAlias('pi');
    return db.rawQuery(
      'SELECT * FROM ( '
      'SELECT sp.id, sp.supplierNumber, sp.name, sp.phone, sp.address, '
      'IFNULL((SELECT SUM(pl.amountSigned) FROM partnerLedger pl '
      'WHERE pl.organizationId = sp.organizationId AND pl.branchId = sp.branchId '
      'AND pl.partnerKind = \'supplier\' AND pl.partnerId = sp.id), 0) AS balanceDue, '
      '(SELECT COUNT(*) FROM purchaseInvoices pi WHERE pi.organizationId = sp.organizationId '
      'AND pi.branchId = sp.branchId AND pi.supplierId = sp.id AND $posted) AS invoicesCount, '
      '(SELECT MAX(pi.invoiceDate) FROM purchaseInvoices pi WHERE pi.organizationId = sp.organizationId '
      'AND pi.branchId = sp.branchId AND pi.supplierId = sp.id AND $posted) AS lastInvoiceDate '
      'FROM suppliers sp '
      'WHERE sp.organizationId = ? AND sp.branchId = ? '
      ') t WHERE t.balanceDue > 0.0001 ORDER BY t.balanceDue DESC',
      [s.organizationId, s.branchId],
    );
  }

  Future<List<Map<String, Object?>>> supplierInvoicesReport(String supplierId) async {
    final s = _mustSession();
    final db = await _databaseService.database;
    return db.query(
      'purchaseInvoices',
      where:
          'organizationId = ? AND branchId = ? AND supplierId = ? AND ${AccountingService._sqlInvoicePostedAlias('purchaseInvoices')}',
      whereArgs: [s.organizationId, s.branchId, supplierId],
      orderBy: 'invoiceDate DESC',
    );
  }

  Future<String> addSupplierOpeningBalance({
    required String supplierId,
    required double amount,
    /// `true`: ذمة على المتجر تجاه المورد (فاتورة شراء افتتاحية). `false`: رصيد لصالح المتجر (تخفيض ذمة).
    bool weOweSupplier = true,
    String paymentType = 'deferred',
    DateTime? entryDate,
    String? voucherNumber,
    String openingVoucherPrefix = OpeningBalanceVoucherConfig.defaultPrefix,
    String? statement,
  }) async {
    final s = _mustSession();
    final db = await _databaseService.database;
    if (amount <= 0) {
      throw Exception('الرصيد الافتتاحي يجب أن يكون أكبر من صفر.');
    }
    final when = entryDate ?? DateTime.now();
    final stmt = statement?.trim();
    final notes = _supplierOpeningBalanceNotes(
      weOweSupplier: weOweSupplier,
      statement: stmt,
    );

    if (weOweSupplier) {
      final invoiceId = _uuid.v4();
      await db.transaction((txn) async {
        final vn = await _resolveSupplierOpeningVoucherNumber(
          txn,
          voucherNumber,
          autoPrefix: openingVoucherPrefix,
        );
        await txn.insert('purchaseInvoices', {
          'id': invoiceId,
          'organizationId': s.organizationId,
          'branchId': s.branchId,
          'supplierId': supplierId,
          'invoiceDate': when.toIso8601String(),
          'total': amount,
          'paymentType': paymentType,
          'invoiceStatus': 'posted',
          'createdBy': s.userId,
          if (stmt != null && stmt.isNotEmpty) 'notes': stmt,
        });
        if (MizaPaymentTypes.isDeferred(paymentType)) {
          await _insertPartnerLedger(
            txn,
            partnerKind: 'supplier',
            partnerId: supplierId,
            entryType: 'purchase_ap',
            referenceType: 'purchase',
            referenceId: invoiceId,
            amountSigned: amount,
            notes: notes,
            entryDate: when,
            voucherNumber: vn,
          );
        }
      });
      await _audit('create', 'supplier_opening_balance', invoiceId, 'Added supplier opening AP');
      return invoiceId;
    }

    final openingId = _uuid.v4();
    await db.transaction((txn) async {
      final vn = await _resolveSupplierOpeningVoucherNumber(
        txn,
        voucherNumber,
        autoPrefix: openingVoucherPrefix,
      );
      await _insertPartnerLedger(
        txn,
        partnerKind: 'supplier',
        partnerId: supplierId,
        entryType: 'opening_balance',
        referenceType: 'opening_balance',
        referenceId: openingId,
        amountSigned: -amount,
        notes: notes,
        entryDate: when,
        voucherNumber: vn,
      );
    });
    await _audit('create', 'supplier_opening_balance', openingId, 'Added supplier opening credit');
    return openingId;
  }

  String _supplierOpeningBalanceNotes({
    required bool weOweSupplier,
    String? statement,
  }) {
    final parts = <String>[];
    if (statement != null && statement.isNotEmpty) {
      parts.add(statement);
    }
    parts.add(weOweSupplier ? 'رصيد افتتاحي (علينا للمورد)' : 'رصيد افتتاحي (لنا على المورد)');
    return parts.join(' — ');
  }

  Future<List<Map<String, Object?>>> cashMovementReport() async {
    final s = _mustSession();
    final db = await _databaseService.database;
    return db.query(
      'cashTransactions',
      where: 'organizationId = ? AND branchId = ?',
      whereArgs: [s.organizationId, s.branchId],
      orderBy: 'transactionDate DESC',
    );
  }

  Future<List<Map<String, Object?>>> expenseReport() async {
    final s = _mustSession();
    final db = await _databaseService.database;
    return db.query(
      'expenses',
      where: 'organizationId = ? AND branchId = ?',
      whereArgs: [s.organizationId, s.branchId],
      orderBy: 'expenseDate DESC',
    );
  }

  Future<List<Map<String, Object?>>> listRecentSalesInvoices({int limit = 20}) async {
    final s = _mustSession();
    final db = await _databaseService.database;
    return db.rawQuery(
      'SELECT s.id, s.invoiceNumber, s.invoiceDate, s.total, s.paymentType, s.customerId, c.name AS customerName '
      'FROM salesInvoices s '
      'LEFT JOIN customers c ON c.id = s.customerId '
      'WHERE s.organizationId = ? AND s.branchId = ? '
      'AND ${AccountingService._sqlPostedSalesRevenueAlias('s')} '
      'ORDER BY s.invoiceDate DESC '
      'LIMIT ?',
      [s.organizationId, s.branchId, limit],
    );
  }

  Future<List<Map<String, Object?>>> listRecentPriceQuotes({int limit = 20}) async {
    final s = _mustSession();
    final db = await _databaseService.database;
    return db.rawQuery(
      'SELECT s.id, s.invoiceNumber, s.invoiceDate, s.total, s.paymentType, s.customerId, c.name AS customerName '
      'FROM salesInvoices s '
      'LEFT JOIN customers c ON c.id = s.customerId '
      'WHERE s.organizationId = ? AND s.branchId = ? '
      "AND IFNULL(s.invoiceStatus,'posted') = 'quote' "
      'ORDER BY s.invoiceDate DESC '
      'LIMIT ?',
      [s.organizationId, s.branchId, limit],
    );
  }

  Future<List<Map<String, Object?>>> salesInvoiceItemsForEdit(String invoiceId) async {
    final s = _mustSession();
    final db = await _databaseService.database;
    return db.rawQuery(
      'SELECT i.productId, p.name AS productName, i.quantity, i.unitPrice '
      'FROM salesInvoiceItems i '
      'JOIN salesInvoices h ON h.id = i.invoiceId '
      'LEFT JOIN products p ON p.id = i.productId '
      'WHERE i.invoiceId = ? AND h.organizationId = ? AND h.branchId = ?',
      [invoiceId, s.organizationId, s.branchId],
    );
  }

  Future<List<Map<String, Object?>>> listAuditLogs() async {
    final s = _mustSession();
    final db = await _databaseService.database;
    return db.query(
      'auditLogs',
      where: 'organizationId = ?',
      whereArgs: [s.organizationId],
      orderBy: 'createdAt DESC',
      limit: 200,
    );
  }

  Future<String> backupToJson({String? filePath}) async {
    final s = _mustSession();
    _requirePremiumCommercialFeatures();
    final db = await _databaseService.database;
    final tables = [
      'organizations',
      'branches',
      'users',
      'customers',
      'suppliers',
      'product_categories',
      'products',
      'salesInvoices',
      'salesInvoiceItems',
      'purchaseInvoices',
      'purchaseInvoiceItems',
      'partnerLedger',
      'salesReturns',
      'salesReturnItems',
      'purchaseReturns',
      'purchaseReturnItems',
      'stockMovements',
      'cashTransactions',
      'expenses',
      'auditLogs',
    ];
    final payload = <String, dynamic>{
      'metadata': {
        'organizationId': s.organizationId,
        'branchId': s.branchId,
        'exportedAt': DateTime.now().toIso8601String(),
      }
    };
    for (final table in tables) {
      payload[table] = await db.query(table);
    }
    final now = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final path =
        filePath ?? join(appDataDirectoryPath(), 'backup_$now.json');
    await File(path).writeAsString(const JsonEncoder.withIndent('  ').convert(payload));
    await _audit('backup', 'system', now, 'Backup created at $path');
    return path;
  }

  Future<void> restoreFromJson(String filePath) async {
    _mustSession();
    _requirePremiumCommercialFeatures();
    final db = await _databaseService.database;
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('Backup file not found');
    }
    final payload = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    await db.transaction((txn) async {
      final tables = [
        'organizations',
        'branches',
        'users',
        'customers',
        'suppliers',
        'product_categories',
        'products',
        'salesInvoices',
        'salesInvoiceItems',
        'purchaseInvoices',
        'purchaseInvoiceItems',
        'partnerLedger',
        'salesReturns',
        'salesReturnItems',
        'purchaseReturns',
        'purchaseReturnItems',
        'stockMovements',
        'cashTransactions',
        'expenses',
        'auditLogs',
      ];
      for (final table in tables) {
        await txn.delete(table);
      }
      for (final table in tables) {
        final rows = (payload[table] as List<dynamic>? ?? [])
            .cast<Map<String, dynamic>>();
        for (final row in rows) {
          await txn.insert(table, row);
        }
      }
    });
  }

  Future<void> _insertPartnerLedger(
    dynamic txn, {
    required String partnerKind,
    required String partnerId,
    required String entryType,
    required String referenceType,
    required String referenceId,
    required double amountSigned,
    String notes = '',
    DateTime? entryDate,
    String? voucherNumber,
  }) async {
    final s = _mustSession();
    final when = entryDate ?? DateTime.now();
    final vn = voucherNumber?.trim();
    await txn.insert('partnerLedger', {
      'id': _uuid.v4(),
      'organizationId': s.organizationId,
      'branchId': s.branchId,
      'partnerKind': partnerKind,
      'partnerId': partnerId,
      'entryType': entryType,
      'referenceType': referenceType,
      'referenceId': referenceId,
      'amountSigned': amountSigned,
      'notes': notes.isEmpty ? null : notes,
      if (vn != null && vn.isNotEmpty) 'voucherNumber': vn,
      'entryDate': when.toIso8601String(),
      'createdBy': s.userId,
    });
  }

  Future<void> _insertCash(dynamic txn, CashTransactionInput input) async {
    final s = _mustSession();
    await txn.insert('cashTransactions', {
      'id': _uuid.v4(),
      'organizationId': s.organizationId,
      'branchId': s.branchId,
      'transactionType': input.type,
      'amount': input.amount,
      'description': input.description,
      'referenceType': input.referenceType,
      'referenceId': input.referenceId,
      'transactionDate': DateTime.now().toIso8601String(),
      'createdBy': s.userId,
    });
  }

  Future<void> _audit(
    String action,
    String entityType,
    String entityId,
    String details,
  ) async {
    final s = _mustSession();
    final db = await _databaseService.database;
    await db.insert('auditLogs', {
      'id': _uuid.v4(),
      'organizationId': s.organizationId,
      'branchId': s.branchId,
      'userId': s.userId,
      'action': action,
      'entityType': entityType,
      'entityId': entityId,
      'details': details,
      'createdAt': DateTime.now().toIso8601String(),
    });
  }

  /// بعد commit ناجح — تسجيل catalog master في sync_outbox (بدون push).
  Future<void> _syncCatalogOutbox({
    required String entityType,
    required String operation,
    required String entityId,
    required Map<String, dynamic> payload,
  }) async {
    final s = _session;
    if (s == null) return;
    try {
      await CatalogSyncOutboxWriter.record(
        entityType: entityType,
        operation: operation,
        entityId: entityId,
        organizationId: s.organizationId,
        branchId: s.branchId,
        payload: payload,
        databaseService: _databaseService,
        storage: CatalogSyncOutboxWriter.storage,
      );
    } on Object {
      // لا نعطل المحاسبة إذا فشل outbox
    }
  }

  /// بعد commit ناجح — تسجيل product في sync_outbox (بدون push).
  Future<void> _syncOutboxAfterProductChange(
    String operation,
    String productId, {
    ProductEntity? product,
    Map<String, Object?>? deletedSnapshot,
  }) async {
    final s = _session;
    if (s == null) return;
    try {
      await ProductSyncOutboxWriter.record(
        operation: operation,
        productId: productId,
        organizationId: s.organizationId,
        branchId: s.branchId,
        product: product,
        deletedSnapshot: deletedSnapshot,
        databaseService: _databaseService,
        storage: ProductSyncOutboxWriter.storage,
      );
    } on Object {
      // لا نعطل المحاسبة إذا فشل outbox
    }
  }

  AppUserSession _mustSession() {
    final value = _session;
    if (value == null) {
      throw Exception('Not authenticated');
    }
    return value;
  }

  Future<void> _deleteByIds(
    dynamic txn, {
    required String table,
    required String column,
    required List<String> ids,
  }) async {
    if (ids.isEmpty) return;
    final placeholders = List.filled(ids.length, '?').join(',');
    await txn.delete(
      table,
      where: '$column IN ($placeholders)',
      whereArgs: ids,
    );
  }

  static String isoDayStart(DateTime d) =>
      DateTime(d.year, d.month, d.day).toIso8601String();

  static String isoDayEnd(DateTime d) =>
      DateTime(d.year, d.month, d.day, 23, 59, 59, 999).toIso8601String();

  /// تقارير محددة بفترة زمنية (من — إلى شامل).
  Future<List<Map<String, Object?>>> salesSummaryBetween(DateTime from, DateTime to) async {
    final s = _mustSession();
    final db = await _databaseService.database;
    final posted = AccountingService._sqlInvoicePostedAlias('salesInvoices');
    return db.rawQuery(
      '''SELECT COUNT(*) AS invoicesCount,
                IFNULL(SUM(total), 0) AS totalSales,
                IFNULL(AVG(total), 0) AS avgInvoice
         FROM salesInvoices
         WHERE organizationId = ? AND branchId = ?
           AND $posted
           AND invoiceDate >= ? AND invoiceDate <= ?''',
      [s.organizationId, s.branchId, isoDayStart(from), isoDayEnd(to)],
    );
  }

  Future<List<Map<String, Object?>>> salesInvoicesBetween(DateTime from, DateTime to) async {
    final s = _mustSession();
    final db = await _databaseService.database;
    final posted = AccountingService._sqlInvoicePostedAlias('s');
    return db.rawQuery(
      '''SELECT s.id, s.invoiceDate, s.total, s.paymentType,
                s.customerId, c.name AS customerName
         FROM salesInvoices s
         LEFT JOIN customers c ON c.id = s.customerId
         WHERE s.organizationId = ? AND s.branchId = ?
           AND $posted
           AND s.invoiceDate >= ? AND s.invoiceDate <= ?
         ORDER BY s.invoiceDate DESC''',
      [s.organizationId, s.branchId, isoDayStart(from), isoDayEnd(to)],
    );
  }

  Future<List<Map<String, Object?>>> salesDeferredBetween(DateTime from, DateTime to) async {
    final s = _mustSession();
    final db = await _databaseService.database;
    final posted = AccountingService._sqlInvoicePostedAlias('s');
    return db.rawQuery(
      '''SELECT s.id, s.invoiceDate, s.total, s.paidAmount, s.discountAmount,
                s.paymentType, s.customerId, c.name AS customerName
         FROM salesInvoices s
         LEFT JOIN customers c ON c.id = s.customerId
         WHERE s.organizationId = ? AND s.branchId = ?
           AND $posted
           AND s.paymentType = 'deferred'
           AND s.invoiceDate >= ? AND s.invoiceDate <= ?
         ORDER BY s.invoiceDate DESC''',
      [s.organizationId, s.branchId, isoDayStart(from), isoDayEnd(to)],
    );
  }

  Future<List<Map<String, Object?>>> saleReturnsBetween(DateTime from, DateTime to) async {
    final s = _mustSession();
    final db = await _databaseService.database;
    return db.rawQuery(
      '''SELECT r.id, r.returnDate, r.total, r.refundPaymentType,
                r.originalInvoiceId,
                IFNULL(r.returnStatus, 'posted') AS returnStatus,
                c.name AS customerName
         FROM salesReturns r
         LEFT JOIN customers c ON c.id = r.customerId
         WHERE r.organizationId = ? AND r.branchId = ?
           AND r.returnDate >= ? AND r.returnDate <= ?
         ORDER BY r.returnDate DESC''',
      [s.organizationId, s.branchId, isoDayStart(from), isoDayEnd(to)],
    );
  }

  Future<List<Map<String, Object?>>> profitByProductBetween(DateTime from, DateTime to) async {
    final s = _mustSession();
    final db = await _databaseService.database;
    return db.rawQuery(
      '''SELECT COALESCE(p.name, '?') AS productName,
                SUM(i.quantity) AS quantitySold,
                IFNULL(SUM(i.lineTotal), 0) AS revenue,
                IFNULL(SUM(i.quantity * COALESCE(p.costPrice, 0)), 0) AS costEstimate,
                IFNULL(SUM(i.lineTotal - i.quantity * COALESCE(p.costPrice, 0)), 0) AS grossProfit
         FROM salesInvoiceItems i
         JOIN salesInvoices s ON s.id = i.invoiceId
         LEFT JOIN products p ON p.id = i.productId
           AND p.organizationId = s.organizationId AND p.branchId = s.branchId
         WHERE s.organizationId = ? AND s.branchId = ?
           AND ${AccountingService._sqlInvoicePostedAlias('s')}
           AND s.invoiceDate >= ? AND s.invoiceDate <= ?
           AND (p.id IS NULL OR IFNULL(p.isFrozen,0) = 0)
         GROUP BY i.productId, p.name
         ORDER BY productName''',
      [s.organizationId, s.branchId, isoDayStart(from), isoDayEnd(to)],
    );
  }

  /// تقدير ضريبي من أسطر الفواتير (الضريبة غير مخزنة منفصلة؛ يُفترض أن subtotal × النسبة).
  Future<List<Map<String, Object?>>> estimatedSalesTaxByProductBetween(
    DateTime from,
    DateTime to,
    double taxPercent,
  ) async {
    final s = _mustSession();
    final db = await _databaseService.database;
    final rate = taxPercent / 100.0;
    return db.rawQuery(
      '''SELECT COALESCE(p.name, '?') AS productName,
                IFNULL(SUM(i.lineTotal * ?), 0) AS estimatedTax
         FROM salesInvoiceItems i
         JOIN salesInvoices s ON s.id = i.invoiceId
         LEFT JOIN products p ON p.id = i.productId
           AND p.organizationId = s.organizationId AND p.branchId = s.branchId
         WHERE s.organizationId = ? AND s.branchId = ?
           AND ${AccountingService._sqlInvoicePostedAlias('s')}
           AND s.invoiceDate >= ? AND s.invoiceDate <= ?
           AND (p.id IS NULL OR IFNULL(p.isFrozen,0) = 0)
         GROUP BY i.productId, p.name
         ORDER BY productName''',
      [rate, s.organizationId, s.branchId, isoDayStart(from), isoDayEnd(to)],
    );
  }

  Future<List<Map<String, Object?>>> estimatedSalesTaxByCustomerBetween(
    DateTime from,
    DateTime to,
    double taxPercent,
  ) async {
    final s = _mustSession();
    final db = await _databaseService.database;
    final rate = taxPercent / 100.0;
    return db.rawQuery(
      '''SELECT COALESCE(c.name, 'بدون عميل') AS customerName,
                IFNULL(SUM(i.lineTotal * ?), 0) AS estimatedTax
         FROM salesInvoiceItems i
         JOIN salesInvoices s ON s.id = i.invoiceId
         LEFT JOIN customers c ON c.id = s.customerId
         WHERE s.organizationId = ? AND s.branchId = ?
           AND ${AccountingService._sqlInvoicePostedAlias('s')}
           AND s.invoiceDate >= ? AND s.invoiceDate <= ?
         GROUP BY s.customerId, c.name
         ORDER BY customerName''',
      [rate, s.organizationId, s.branchId, isoDayStart(from), isoDayEnd(to)],
    );
  }

  Future<List<Map<String, Object?>>> auditLogsBetween({
    DateTime? from,
    DateTime? to,
    String? entityType,
    List<String>? actions,
    int limit = 400,
  }) async {
    final s = _mustSession();
    final db = await _databaseService.database;
    final where = <String>['organizationId = ?', 'branchId = ?'];
    final args = <Object?>[s.organizationId, s.branchId];
    if (entityType != null && entityType.isNotEmpty) {
      where.add('entityType = ?');
      args.add(entityType);
    }
    if (actions != null && actions.isNotEmpty) {
      where.add('action IN (${List.filled(actions.length, '?').join(',')})');
      args.addAll(actions);
    }
    if (from != null) {
      where.add('createdAt >= ?');
      args.add(isoDayStart(from));
    }
    if (to != null) {
      where.add('createdAt <= ?');
      args.add(isoDayEnd(to));
    }
    return db.query(
      'auditLogs',
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: 'createdAt DESC',
      limit: limit,
    );
  }

  /// وقت آخر نسخ احتياطي مسجّل في سجل التدقيق.
  Future<DateTime?> lastBackupAuditTime() async {
    final rows = await auditLogsBetween(actions: ['backup'], limit: 1);
    if (rows.isEmpty) return null;
    return DateTime.tryParse((rows.first['createdAt'] as String?) ?? '');
  }

  /// معرّف المستخدم → اسم عرض للتدقيق.
  Future<Map<String, String>> userIdToDisplayLabel() async {
    final s = _mustSession();
    final db = await _databaseService.database;
    final rows = await db.query(
      'users',
      columns: ['id', 'username', 'fullName'],
      where: 'organizationId = ?',
      whereArgs: [s.organizationId],
    );
    final m = <String, String>{};
    for (final r in rows) {
      final id = r['id'] as String?;
      if (id == null) continue;
      final fn = (r['fullName'] as String?)?.trim() ?? '';
      final un = (r['username'] as String?)?.trim() ?? '';
      m[id] = fn.isNotEmpty ? fn : (un.isNotEmpty ? un : id);
    }
    return m;
  }

  Future<List<Map<String, Object?>>> topCustomersBySalesBetween(
    DateTime from,
    DateTime to, {
    int limit = 20,
  }) async {
    final s = _mustSession();
    final db = await _databaseService.database;
    final posted = AccountingService._sqlInvoicePostedAlias('s');
    return db.rawQuery(
      '''SELECT COALESCE(c.name, ?) AS customerName,
                COUNT(*) AS invoicesCount,
                IFNULL(SUM(s.total), 0) AS totalSales
         FROM salesInvoices s
         LEFT JOIN customers c ON c.id = s.customerId
         WHERE s.organizationId = ? AND s.branchId = ?
           AND $posted
           AND s.invoiceDate >= ? AND s.invoiceDate <= ?
         GROUP BY s.customerId, c.name
         ORDER BY totalSales DESC
         LIMIT ?''',
      [
        '-',
        s.organizationId,
        s.branchId,
        isoDayStart(from),
        isoDayEnd(to),
        limit,
      ],
    );
  }

  /// أصناف برصيد مخزون لكن بمبيعات منخفضة في الفترة (راكدة).
  Future<List<Map<String, Object?>>> slowMovingProductsBetween(
    DateTime from,
    DateTime to, {
    double minStock = 1,
    double maxQtySold = 2,
    int limit = 40,
  }) async {
    final s = _mustSession();
    final db = await _databaseService.database;
    return db.rawQuery(
      '''SELECT * FROM (
           SELECT p.name AS productName,
                  p.stockQty AS stockQty,
                  IFNULL((
                    SELECT SUM(ii.quantity)
                    FROM salesInvoiceItems ii
                    JOIN salesInvoices si2 ON si2.id = ii.invoiceId
                    WHERE ii.productId = p.id
                      AND si2.organizationId = p.organizationId
                      AND si2.branchId = p.branchId
                      AND (IFNULL(si2.invoiceStatus,'posted') <> 'voided')
                      AND si2.invoiceDate >= ? AND si2.invoiceDate <= ?
                  ), 0) AS qtySoldPeriod
           FROM products p
           WHERE p.organizationId = ? AND p.branchId = ?
             AND p.isHidden = 0
             AND IFNULL(p.isFrozen,0) = 0
             AND p.stockQty >= ?
         ) t
         WHERE t.qtySoldPeriod <= ?
         ORDER BY t.qtySoldPeriod ASC, t.stockQty DESC
         LIMIT ?''',
      [
        isoDayStart(from),
        isoDayEnd(to),
        s.organizationId,
        s.branchId,
        minStock,
        maxQtySold,
        limit,
      ],
    );
  }

  /// ملخص تنفيذي: مبيعات، مشتريات، هامش تقديري، مصروفات، صافٍ تقديري.
  Future<Map<String, Object?>> executiveFinancialSummaryBetween(
    DateTime from,
    DateTime to,
  ) async {
    final sales = await salesSummaryBetween(from, to);
    final purchases = await purchasesSummaryBetween(from, to);
    final profitRows = await profitByProductBetween(from, to);
    final expenseRows = await expensesBetween(from, to);
    var gross = 0.0;
    for (final r in profitRows) {
      gross += ((r['grossProfit'] as num?) ?? 0).toDouble();
    }
    var expTotal = 0.0;
    for (final r in expenseRows) {
      expTotal += ((r['amount'] as num?) ?? 0).toDouble();
    }
    final sRow = sales.isEmpty ? null : sales.first;
    final pRow = purchases.isEmpty ? null : purchases.first;
    return {
      'totalSales': (sRow?['totalSales'] as num?) ?? 0,
      'invoicesCount': (sRow?['invoicesCount'] as num?) ?? 0,
      'totalPurchases': (pRow?['totalPurchases'] as num?) ?? 0,
      'grossProfitEstimate': gross,
      'totalExpenses': expTotal,
      'estimatedNet': gross - expTotal,
    };
  }

  Future<List<Map<String, Object?>>> purchasesSummaryBetween(DateTime from, DateTime to) async {
    final s = _mustSession();
    final db = await _databaseService.database;
    return db.rawQuery(
      '''SELECT COUNT(*) AS invoicesCount,
                IFNULL(SUM(total), 0) AS totalPurchases,
                IFNULL(AVG(total), 0) AS avgInvoice
         FROM purchaseInvoices
         WHERE organizationId = ? AND branchId = ?
           AND invoiceDate >= ? AND invoiceDate <= ?''',
      [s.organizationId, s.branchId, isoDayStart(from), isoDayEnd(to)],
    );
  }

  Future<List<Map<String, Object?>>> purchaseInvoicesBetween(DateTime from, DateTime to) async {
    final s = _mustSession();
    final db = await _databaseService.database;
    return db.rawQuery(
      '''SELECT p.id, p.invoiceDate, p.total, p.paymentType,
                p.supplierId, sp.name AS supplierName
         FROM purchaseInvoices p
         LEFT JOIN suppliers sp ON sp.id = p.supplierId
         WHERE p.organizationId = ? AND p.branchId = ?
           AND p.invoiceDate >= ? AND p.invoiceDate <= ?
         ORDER BY p.invoiceDate DESC''',
      [s.organizationId, s.branchId, isoDayStart(from), isoDayEnd(to)],
    );
  }

  Future<List<Map<String, Object?>>> purchaseDeferredBetween(DateTime from, DateTime to) async {
    final s = _mustSession();
    final db = await _databaseService.database;
    return db.rawQuery(
      '''SELECT p.id, p.invoiceDate, p.total, p.paymentType,
                p.supplierId, sp.name AS supplierName
         FROM purchaseInvoices p
         LEFT JOIN suppliers sp ON sp.id = p.supplierId
         WHERE p.organizationId = ? AND p.branchId = ?
           AND p.paymentType = 'deferred'
           AND p.invoiceDate >= ? AND p.invoiceDate <= ?
         ORDER BY p.invoiceDate DESC''',
      [s.organizationId, s.branchId, isoDayStart(from), isoDayEnd(to)],
    );
  }

  Future<List<Map<String, Object?>>> cashMovementBetween(DateTime from, DateTime to) async {
    final s = _mustSession();
    final db = await _databaseService.database;
    return db.query(
      'cashTransactions',
      where: 'organizationId = ? AND branchId = ? AND transactionDate >= ? AND transactionDate <= ?',
      whereArgs: [s.organizationId, s.branchId, isoDayStart(from), isoDayEnd(to)],
      orderBy: 'transactionDate DESC',
    );
  }

  Future<List<Map<String, Object?>>> expensesBetween(DateTime from, DateTime to) async {
    final s = _mustSession();
    final db = await _databaseService.database;
    return db.query(
      'expenses',
      where: 'organizationId = ? AND branchId = ? AND expenseDate >= ? AND expenseDate <= ?',
      whereArgs: [s.organizationId, s.branchId, isoDayStart(from), isoDayEnd(to)],
      orderBy: 'expenseDate DESC',
    );
  }

  Future<List<Map<String, Object?>>> expensesGroupedByTitleBetween(DateTime from, DateTime to) async {
    final s = _mustSession();
    final db = await _databaseService.database;
    return db.rawQuery(
      '''SELECT title AS expenseTitle,
                COUNT(*) AS entriesCount,
                IFNULL(SUM(amount), 0) AS totalAmount
         FROM expenses
         WHERE organizationId = ? AND branchId = ?
           AND expenseDate >= ? AND expenseDate <= ?
         GROUP BY title
         ORDER BY totalAmount DESC''',
      [s.organizationId, s.branchId, isoDayStart(from), isoDayEnd(to)],
    );
  }

  Future<List<Map<String, Object?>>> expensesForTitleBetween(
    String title,
    DateTime from,
    DateTime to,
  ) async {
    final s = _mustSession();
    final db = await _databaseService.database;
    return db.query(
      'expenses',
      where: 'organizationId = ? AND branchId = ? AND title = ? '
          'AND expenseDate >= ? AND expenseDate <= ?',
      whereArgs: [
        s.organizationId,
        s.branchId,
        title,
        isoDayStart(from),
        isoDayEnd(to),
      ],
      orderBy: 'expenseDate DESC',
    );
  }

  Future<List<Map<String, Object?>>> stockMovementsBetween(DateTime from, DateTime to) async {
    final s = _mustSession();
    final db = await _databaseService.database;
    return db.rawQuery(
      '''SELECT m.movementDate, m.movementType, m.quantity,
                m.referenceType, m.referenceId,
                COALESCE(p.name, '?') AS productName
         FROM stockMovements m
         LEFT JOIN products p ON p.id = m.productId
           AND p.organizationId = m.organizationId AND p.branchId = m.branchId
         WHERE m.organizationId = ? AND m.branchId = ?
           AND m.movementDate >= ? AND m.movementDate <= ?
         ORDER BY m.movementDate DESC''',
      [s.organizationId, s.branchId, isoDayStart(from), isoDayEnd(to)],
    );
  }

  Future<List<Map<String, Object?>>> stockMovementsForProductBetween(
    String productId,
    DateTime from,
    DateTime to,
  ) async {
    final s = _mustSession();
    final db = await _databaseService.database;
    return db.rawQuery(
      '''SELECT m.movementDate, m.movementType, m.quantity,
                m.referenceType, m.referenceId,
                COALESCE(p.name, '?') AS productName
         FROM stockMovements m
         LEFT JOIN products p ON p.id = m.productId
           AND p.organizationId = m.organizationId AND p.branchId = m.branchId
         WHERE m.organizationId = ? AND m.branchId = ?
           AND m.productId = ?
           AND m.movementDate >= ? AND m.movementDate <= ?
         ORDER BY m.movementDate DESC''',
      [s.organizationId, s.branchId, productId, isoDayStart(from), isoDayEnd(to)],
    );
  }

  /// سجل خصومات المخزون بسبب التالف (مرجع [referenceType] = damage).
  /// [reason] من سجل التدقيق المرتبط بنفس معرف الحركة.
  Future<List<Map<String, Object?>>> damagedStockBetween(
    DateTime from,
    DateTime to,
  ) async {
    final s = _mustSession();
    final db = await _databaseService.database;
    return db.rawQuery(
      '''SELECT m.movementDate AS movementDate,
                m.quantity AS quantity,
                COALESCE(p.name, '?') AS productName,
                COALESCE(a.details, '') AS reason
         FROM stockMovements m
         LEFT JOIN products p ON p.id = m.productId
           AND p.organizationId = m.organizationId AND p.branchId = m.branchId
         LEFT JOIN auditLogs a ON a.entityId = m.referenceId
           AND a.action = 'damage'
           AND a.organizationId = m.organizationId AND a.branchId = m.branchId
         WHERE m.organizationId = ? AND m.branchId = ?
           AND m.referenceType = 'damage'
           AND m.movementDate >= ? AND m.movementDate <= ?
         ORDER BY m.movementDate DESC''',
      [s.organizationId, s.branchId, isoDayStart(from), isoDayEnd(to)],
    );
  }

  Future<List<Map<String, Object?>>> listDamagedStockHistory({
    int limit = 500,
  }) async {
    final s = _mustSession();
    final db = await _databaseService.database;
    return db.rawQuery(
      '''SELECT m.movementDate AS movementDate,
                m.quantity AS quantity,
                COALESCE(p.name, '?') AS productName,
                COALESCE(a.details, '') AS reason
         FROM stockMovements m
         LEFT JOIN products p ON p.id = m.productId
           AND p.organizationId = m.organizationId AND p.branchId = m.branchId
         LEFT JOIN auditLogs a ON a.entityId = m.referenceId
           AND a.action = 'damage'
           AND a.organizationId = m.organizationId AND a.branchId = m.branchId
         WHERE m.organizationId = ? AND m.branchId = ?
           AND m.referenceType = 'damage'
         ORDER BY m.movementDate DESC
         LIMIT ?''',
      [s.organizationId, s.branchId, limit],
    );
  }

  Future<List<Map<String, Object?>>> salesOpeningBalancesBetween(DateTime from, DateTime to) async {
    final s = _mustSession();
    final db = await _databaseService.database;
    return db.rawQuery(
      '''SELECT s.id, s.invoiceDate, s.total, s.paymentType,
                s.customerId, c.name AS customerName
         FROM salesInvoices s
         LEFT JOIN customers c ON c.id = s.customerId
         WHERE s.organizationId = ? AND s.branchId = ?
           AND ${AccountingService._sqlInvoicePostedAlias('s')}
           AND NOT EXISTS (SELECT 1 FROM salesInvoiceItems i WHERE i.invoiceId = s.id)
           AND s.invoiceDate >= ? AND s.invoiceDate <= ?
         ORDER BY s.invoiceDate DESC''',
      [s.organizationId, s.branchId, isoDayStart(from), isoDayEnd(to)],
    );
  }

  static String _openingMovementRefDisplay({
    required String referenceId,
    String? voucherNumber,
  }) {
    final vn = voucherNumber?.trim() ?? '';
    if (vn.isNotEmpty) return vn;
    final id = referenceId.trim();
    if (id.isEmpty) return '—';
    return id.length > 8 ? id.substring(0, 8) : id;
  }

  /// صفوف موحّدة لتقرير «رصيد افتتاحي + نقد» لعميل (مفاتيح: eventDate, ref, credit, debit, description).
  Future<List<Map<String, Object?>>> customerOpeningBalanceAndCashMovementBetween(
    String customerId,
    DateTime from,
    DateTime to, {
    bool english = false,
  }) async {
    final s = _mustSession();
    final db = await _databaseService.database;
    final fromIso = isoDayStart(from);
    final toIso = isoDayEnd(to);
    final cid = customerId.trim();
    final rows = <Map<String, Object?>>[];

    final openingInvoices = await db.rawQuery(
      '''SELECT s.id, s.invoiceDate, s.total, s.paymentType, pl.voucherNumber
         FROM salesInvoices s
         LEFT JOIN partnerLedger pl ON pl.referenceId = s.id
           AND pl.referenceType = 'sale'
           AND pl.partnerKind = 'customer'
           AND pl.partnerId = s.customerId
           AND pl.entryType = 'sale_ar'
         WHERE s.organizationId = ? AND s.branchId = ? AND s.customerId = ?
           AND ${AccountingService._sqlInvoicePostedAlias('s')}
           AND NOT EXISTS (SELECT 1 FROM salesInvoiceItems i WHERE i.invoiceId = s.id)
           AND s.invoiceDate >= ? AND s.invoiceDate <= ?''',
      [s.organizationId, s.branchId, cid, fromIso, toIso],
    );
    for (final inv in openingInvoices) {
      final total = ((inv['total'] as num?) ?? 0).toDouble();
      if (total <= 1e-9) continue;
      final id = (inv['id'] ?? '').toString();
      final pt = (inv['paymentType'] ?? '').toString().trim();
      final stmt = pt.isEmpty
          ? (english ? 'Opening balance (due)' : 'رصيد افتتاحي (عليه)')
          : (english
              ? 'Opening balance (due) — $pt'
              : 'رصيد افتتاحي (عليه) — $pt');
      rows.add({
        'eventDate': inv['invoiceDate'],
        'ref': _openingMovementRefDisplay(
          referenceId: id,
          voucherNumber: (inv['voucherNumber'] ?? '').toString(),
        ),
        'credit': 0.0,
        'debit': total,
        'description': stmt,
      });
    }

    final creditLedger = await db.rawQuery(
      '''SELECT referenceId, entryDate, amountSigned, voucherNumber, notes
         FROM partnerLedger
         WHERE organizationId = ? AND branchId = ?
           AND partnerKind = 'customer' AND partnerId = ?
           AND entryType = 'opening_balance' AND referenceType = 'opening_balance'
           AND entryDate >= ? AND entryDate <= ?''',
      [s.organizationId, s.branchId, cid, fromIso, toIso],
    );
    for (final pl in creditLedger) {
      final signed = ((pl['amountSigned'] as num?) ?? 0).toDouble();
      final credit = signed.abs();
      if (credit <= 1e-9) continue;
      final notes = (pl['notes'] ?? '').toString().trim();
      rows.add({
        'eventDate': pl['entryDate'],
        'ref': _openingMovementRefDisplay(
          referenceId: (pl['referenceId'] ?? '').toString(),
          voucherNumber: (pl['voucherNumber'] ?? '').toString(),
        ),
        'credit': credit,
        'debit': 0.0,
        'description': notes.isEmpty
            ? (english ? 'Opening balance (credit)' : 'رصيد افتتاحي (له)')
            : notes,
      });
    }

    final cashRows = await db.rawQuery(
      '''SELECT ct.id, ct.transactionDate, ct.transactionType, ct.amount, ct.description, ct.referenceId
         FROM cashTransactions ct
         WHERE ct.organizationId = ? AND ct.branchId = ?
           AND ct.referenceType = 'customer_opening_balance'
           AND ct.transactionDate >= ? AND ct.transactionDate <= ?
           AND (
             EXISTS (
               SELECT 1 FROM salesInvoices s
               WHERE s.id = ct.referenceId AND s.customerId = ?
                 AND ${AccountingService._sqlInvoicePostedAlias('s')}
                 AND NOT EXISTS (SELECT 1 FROM salesInvoiceItems i WHERE i.invoiceId = s.id)
             )
             OR EXISTS (
               SELECT 1 FROM partnerLedger pl
               WHERE pl.referenceId = ct.referenceId
                 AND pl.partnerKind = 'customer' AND pl.partnerId = ?
                 AND pl.entryType = 'opening_balance'
             )
           )''',
      [s.organizationId, s.branchId, fromIso, toIso, cid, cid],
    );
    for (final c in cashRows) {
      final amt = ((c['amount'] as num?) ?? 0).toDouble();
      if (amt <= 1e-9) continue;
      final isIn = (c['transactionType'] ?? '').toString() == 'in';
      final desc = (c['description'] ?? '').toString().trim();
      final cashDesc = desc.isEmpty
          ? (isIn
              ? (english ? 'Cash — added to cash box' : 'نقد — إضافة للصندوق')
              : (english
                  ? 'Cash — removed from cash box'
                  : 'نقد — صرف من الصندوق'))
          : desc;
      rows.add({
        'eventDate': c['transactionDate'],
        'ref': _openingMovementRefDisplay(
          referenceId: (c['id'] ?? c['referenceId'] ?? '').toString(),
        ),
        'credit': isIn ? amt : 0.0,
        'debit': isIn ? 0.0 : amt,
        'description': cashDesc,
      });
    }

    rows.sort((a, b) {
      final da =
          DateTime.tryParse((a['eventDate'] ?? '').toString()) ?? DateTime(1970);
      final db_ =
          DateTime.tryParse((b['eventDate'] ?? '').toString()) ?? DateTime(1970);
      return da.compareTo(db_);
    });
    return rows;
  }

  /// يستخرج «البيان» الذي أدخله المستخدم من حقل الملاحظات المخزّن مع الرصيد الافتتاحي.
  static String? openingBalanceUserStatementFromNotes(String? notes) {
    final n = notes?.trim();
    if (n == null || n.isEmpty) return null;
    const arMarker = ' — رصيد افتتاحي';
    const enMarker = ' — Opening balance';
    for (final marker in [arMarker, enMarker]) {
      final idx = n.indexOf(marker);
      if (idx > 0) {
        final head = n.substring(0, idx).trim();
        if (head.isNotEmpty) return head;
      }
    }
    if (n.startsWith('رصيد افتتاحي') || n.startsWith('Opening balance')) {
      return null;
    }
    return n;
  }

  /// سجلات رصيد افتتاحي محفوظة لإعادة طباعة السند.
  /// `customerOwesUs == true` → عليه (ذمة) → سند قبض؛ `false` → له (دائن) → سند صرف.
  /// المفاتيح: `voucherNumber`, `amount`, `entryDate`, `statement`, `customerOwesUs`.
  Future<List<Map<String, Object?>>> customerOpeningBalanceVouchersForReprint(
    String customerId, {
    required bool customerOwesUs,
  }) async {
    final s = _mustSession();
    final db = await _databaseService.database;
    final cid = customerId.trim();
    final rows = <Map<String, Object?>>[];

    if (customerOwesUs) {
      final dueRows = await db.rawQuery(
        '''SELECT s.id, s.invoiceDate, s.total, s.notes AS invoiceNotes,
                  pl.voucherNumber, pl.notes AS ledgerNotes
           FROM salesInvoices s
           LEFT JOIN partnerLedger pl ON pl.referenceId = s.id
             AND pl.referenceType = 'sale'
             AND pl.partnerKind = 'customer'
             AND pl.partnerId = s.customerId
             AND pl.entryType = 'sale_ar'
           WHERE s.organizationId = ? AND s.branchId = ? AND s.customerId = ?
             AND ${AccountingService._sqlInvoicePostedAlias('s')}
             AND NOT EXISTS (SELECT 1 FROM salesInvoiceItems i WHERE i.invoiceId = s.id)
           ORDER BY s.invoiceDate DESC''',
        [s.organizationId, s.branchId, cid],
      );
      for (final r in dueRows) {
        final amount = ((r['total'] as num?) ?? 0).toDouble();
        if (amount <= 1e-9) continue;
        final invNotes = (r['invoiceNotes'] ?? '').toString().trim();
        final ledgerNotes = (r['ledgerNotes'] ?? '').toString();
        final stmt = invNotes.isNotEmpty
            ? invNotes
            : openingBalanceUserStatementFromNotes(ledgerNotes);
        final vn = (r['voucherNumber'] ?? '').toString().trim();
        rows.add({
          'voucherNumber': vn.isNotEmpty
              ? vn
              : _openingMovementRefDisplay(referenceId: (r['id'] ?? '').toString()),
          'amount': amount,
          'entryDate': r['invoiceDate'],
          'statement': stmt,
          'customerOwesUs': true,
        });
      }
    } else {
      final creditRows = await db.rawQuery(
        '''SELECT referenceId, entryDate, amountSigned, voucherNumber, notes
           FROM partnerLedger
           WHERE organizationId = ? AND branchId = ?
             AND partnerKind = 'customer' AND partnerId = ?
             AND entryType = 'opening_balance' AND referenceType = 'opening_balance'
           ORDER BY entryDate DESC''',
        [s.organizationId, s.branchId, cid],
      );
      for (final pl in creditRows) {
        final signed = ((pl['amountSigned'] as num?) ?? 0).toDouble();
        final amount = signed.abs();
        if (amount <= 1e-9) continue;
        final notes = (pl['notes'] ?? '').toString();
        final vn = (pl['voucherNumber'] ?? '').toString().trim();
        rows.add({
          'voucherNumber': vn.isNotEmpty
              ? vn
              : _openingMovementRefDisplay(
                  referenceId: (pl['referenceId'] ?? '').toString(),
                ),
          'amount': amount,
          'entryDate': pl['entryDate'],
          'statement': openingBalanceUserStatementFromNotes(notes),
          'customerOwesUs': false,
        });
      }
    }
    return rows;
  }

  Future<List<Map<String, Object?>>> purchaseOpeningBalancesBetween(DateTime from, DateTime to) async {
    final s = _mustSession();
    final db = await _databaseService.database;
    return db.rawQuery(
      '''SELECT p.id, p.invoiceDate, p.total, p.paymentType,
                p.supplierId, sp.name AS supplierName
         FROM purchaseInvoices p
         LEFT JOIN suppliers sp ON sp.id = p.supplierId
         WHERE p.organizationId = ? AND p.branchId = ?
           AND ${AccountingService._sqlInvoicePostedAlias('p')}
           AND NOT EXISTS (SELECT 1 FROM purchaseInvoiceItems i WHERE i.invoiceId = p.id)
           AND p.invoiceDate >= ? AND p.invoiceDate <= ?
         ORDER BY p.invoiceDate DESC''',
      [s.organizationId, s.branchId, isoDayStart(from), isoDayEnd(to)],
    );
  }

  Future<List<Map<String, Object?>>> customerInvoicesBetween(
    String customerId,
    DateTime from,
    DateTime to,
  ) async {
    final s = _mustSession();
    final db = await _databaseService.database;
    return db.rawQuery(
      '''SELECT id, invoiceDate, total, paymentType
         FROM salesInvoices
         WHERE organizationId = ? AND branchId = ?
           AND customerId = ?
           AND ${AccountingService._sqlInvoicePostedAlias('salesInvoices')}
           AND invoiceDate >= ? AND invoiceDate <= ?
         ORDER BY invoiceDate DESC''',
      [s.organizationId, s.branchId, customerId, isoDayStart(from), isoDayEnd(to)],
    );
  }

  Future<List<Map<String, Object?>>> supplierInvoicesBetween(
    String supplierId,
    DateTime from,
    DateTime to,
  ) async {
    final s = _mustSession();
    final db = await _databaseService.database;
    return db.rawQuery(
      '''SELECT id, invoiceDate, total, paymentType
         FROM purchaseInvoices
         WHERE organizationId = ? AND branchId = ?
           AND supplierId = ?
           AND ${AccountingService._sqlInvoicePostedAlias('purchaseInvoices')}
           AND invoiceDate >= ? AND invoiceDate <= ?
         ORDER BY invoiceDate DESC''',
      [s.organizationId, s.branchId, supplierId, isoDayStart(from), isoDayEnd(to)],
    );
  }

  Future<List<Map<String, Object?>>> customerInvoiceTotalsBetween(
    String customerId,
    DateTime from,
    DateTime to,
  ) async {
    final s = _mustSession();
    final db = await _databaseService.database;
    return db.rawQuery(
      '''SELECT IFNULL(COUNT(*), 0) AS invoicesCount,
                IFNULL(SUM(total), 0) AS totalAmount
         FROM salesInvoices
         WHERE organizationId = ? AND branchId = ?
           AND customerId = ?
           AND ${AccountingService._sqlInvoicePostedAlias('salesInvoices')}
           AND invoiceDate >= ? AND invoiceDate <= ?''',
      [s.organizationId, s.branchId, customerId, isoDayStart(from), isoDayEnd(to)],
    );
  }

  Future<List<Map<String, Object?>>> supplierInvoiceTotalsBetween(
    String supplierId,
    DateTime from,
    DateTime to,
  ) async {
    final s = _mustSession();
    final db = await _databaseService.database;
    return db.rawQuery(
      '''SELECT IFNULL(COUNT(*), 0) AS invoicesCount,
                IFNULL(SUM(total), 0) AS totalAmount
         FROM purchaseInvoices
         WHERE organizationId = ? AND branchId = ?
           AND supplierId = ?
           AND ${AccountingService._sqlInvoicePostedAlias('purchaseInvoices')}
           AND invoiceDate >= ? AND invoiceDate <= ?''',
      [s.organizationId, s.branchId, supplierId, isoDayStart(from), isoDayEnd(to)],
    );
  }

  Future<List<Map<String, Object?>>> customerProductTotalsBetween(
    String customerId,
    DateTime from,
    DateTime to,
  ) async {
    final s = _mustSession();
    final db = await _databaseService.database;
    return db.rawQuery(
      '''SELECT COALESCE(p.name, '?') AS productName,
                SUM(i.quantity) AS quantitySold,
                IFNULL(SUM(i.lineTotal), 0) AS lineTotal
         FROM salesInvoiceItems i
         JOIN salesInvoices s ON s.id = i.invoiceId
         LEFT JOIN products p ON p.id = i.productId
         WHERE s.organizationId = ? AND s.branchId = ?
           AND ${AccountingService._sqlInvoicePostedAlias('s')}
           AND s.customerId = ?
           AND s.invoiceDate >= ? AND s.invoiceDate <= ?
         GROUP BY i.productId, p.name
         ORDER BY productName''',
      [s.organizationId, s.branchId, customerId, isoDayStart(from), isoDayEnd(to)],
    );
  }

  Future<List<Map<String, Object?>>> supplierProductTotalsBetween(
    String supplierId,
    DateTime from,
    DateTime to,
  ) async {
    final s = _mustSession();
    final db = await _databaseService.database;
    return db.rawQuery(
      '''SELECT COALESCE(p.name, '?') AS productName,
                SUM(i.quantity) AS quantityPurchased,
                IFNULL(SUM(i.lineTotal), 0) AS lineTotal
         FROM purchaseInvoiceItems i
         JOIN purchaseInvoices h ON h.id = i.invoiceId
         LEFT JOIN products p ON p.id = i.productId
         WHERE h.organizationId = ? AND h.branchId = ?
           AND ${AccountingService._sqlInvoicePostedAlias('h')}
           AND h.supplierId = ?
           AND h.invoiceDate >= ? AND h.invoiceDate <= ?
         GROUP BY i.productId, p.name
         ORDER BY productName''',
      [s.organizationId, s.branchId, supplierId, isoDayStart(from), isoDayEnd(to)],
    );
  }

  Future<List<Map<String, Object?>>> cashReceiptsFromCustomerSalesBetween(
    String customerId,
    DateTime from,
    DateTime to,
  ) async {
    final s = _mustSession();
    final db = await _databaseService.database;
    return db.rawQuery(
      '''SELECT ct.transactionDate, ct.amount, ct.description, ct.referenceId AS invoiceId
         FROM cashTransactions ct
         INNER JOIN salesInvoices si ON si.id = ct.referenceId
         WHERE ct.organizationId = ? AND ct.branchId = ?
           AND ct.referenceType = 'sale'
           AND ct.transactionType = 'in'
           AND ${AccountingService._sqlInvoicePostedAlias('si')}
           AND si.customerId = ?
           AND ct.transactionDate >= ? AND ct.transactionDate <= ?
         ORDER BY ct.transactionDate DESC''',
      [s.organizationId, s.branchId, customerId, isoDayStart(from), isoDayEnd(to)],
    );
  }

  Future<List<Map<String, Object?>>> cashPaymentsToSupplierPurchasesBetween(
    String supplierId,
    DateTime from,
    DateTime to,
  ) async {
    final s = _mustSession();
    final db = await _databaseService.database;
    return db.rawQuery(
      '''SELECT ct.transactionDate, ct.amount, ct.description, ct.referenceId AS invoiceId
         FROM cashTransactions ct
         INNER JOIN purchaseInvoices pi ON pi.id = ct.referenceId
         WHERE ct.organizationId = ? AND ct.branchId = ?
           AND ct.referenceType = 'purchase'
           AND ct.transactionType = 'out'
           AND ${AccountingService._sqlInvoicePostedAlias('pi')}
           AND pi.supplierId = ?
           AND ct.transactionDate >= ? AND ct.transactionDate <= ?
         ORDER BY ct.transactionDate DESC''',
      [s.organizationId, s.branchId, supplierId, isoDayStart(from), isoDayEnd(to)],
    );
  }

  Future<List<Map<String, Object?>>> deferredSalesTotalsByCustomerBetween(DateTime from, DateTime to) async {
    final s = _mustSession();
    final db = await _databaseService.database;
    return db.rawQuery(
      '''SELECT COALESCE(c.name, '?') AS customerName,
                COUNT(*) AS invoicesCount,
                IFNULL(SUM(s.total), 0) AS deferredTotal
         FROM salesInvoices s
         LEFT JOIN customers c ON c.id = s.customerId
         WHERE s.organizationId = ? AND s.branchId = ?
           AND ${AccountingService._sqlInvoicePostedAlias('s')}
           AND s.paymentType = 'deferred'
           AND s.invoiceDate >= ? AND s.invoiceDate <= ?
         GROUP BY s.customerId, c.name
         ORDER BY deferredTotal DESC''',
      [s.organizationId, s.branchId, isoDayStart(from), isoDayEnd(to)],
    );
  }

  Future<List<Map<String, Object?>>> deferredPurchasesTotalsBySupplierBetween(DateTime from, DateTime to) async {
    final s = _mustSession();
    final db = await _databaseService.database;
    return db.rawQuery(
      '''SELECT COALESCE(sp.name, '?') AS supplierName,
                COUNT(*) AS invoicesCount,
                IFNULL(SUM(p.total), 0) AS deferredTotal
         FROM purchaseInvoices p
         LEFT JOIN suppliers sp ON sp.id = p.supplierId
         WHERE p.organizationId = ? AND p.branchId = ?
           AND ${AccountingService._sqlInvoicePostedAlias('p')}
           AND p.paymentType = 'deferred'
           AND p.invoiceDate >= ? AND p.invoiceDate <= ?
         GROUP BY p.supplierId, sp.name
         ORDER BY deferredTotal DESC''',
      [s.organizationId, s.branchId, isoDayStart(from), isoDayEnd(to)],
    );
  }

  Future<List<Map<String, Object?>>> salesTotalsByPaymentTypeBetween(DateTime from, DateTime to) async {
    final s = _mustSession();
    final db = await _databaseService.database;
    return db.rawQuery(
      '''SELECT paymentType,
                COUNT(*) AS invoicesCount,
                IFNULL(SUM(total), 0) AS totalAmount
         FROM salesInvoices
         WHERE organizationId = ? AND branchId = ?
           AND ${AccountingService._sqlInvoicePostedAlias('salesInvoices')}
           AND invoiceDate >= ? AND invoiceDate <= ?
         GROUP BY paymentType
         ORDER BY paymentType''',
      [s.organizationId, s.branchId, isoDayStart(from), isoDayEnd(to)],
    );
  }

  Future<List<Map<String, Object?>>> purchaseTotalsByPaymentTypeBetween(DateTime from, DateTime to) async {
    final s = _mustSession();
    final db = await _databaseService.database;
    return db.rawQuery(
      '''SELECT paymentType,
                COUNT(*) AS invoicesCount,
                IFNULL(SUM(total), 0) AS totalAmount
         FROM purchaseInvoices
         WHERE organizationId = ? AND branchId = ?
           AND ${AccountingService._sqlInvoicePostedAlias('purchaseInvoices')}
           AND invoiceDate >= ? AND invoiceDate <= ?
         GROUP BY paymentType
         ORDER BY paymentType''',
      [s.organizationId, s.branchId, isoDayStart(from), isoDayEnd(to)],
    );
  }

  /// حركة الذمة للعميل من دفتر الشركاء (فواتير آجل، تسديد، إلغاء، مرتجعات).
  Future<List<Map<String, Object?>>> customerSettlementMovementBetween(
    String customerId,
    DateTime from,
    DateTime to,
  ) async {
    final s = _mustSession();
    final db = await _databaseService.database;
    final rows = await db.rawQuery(
      '''SELECT entryDate AS eventDate,
                entryType,
                referenceType,
                referenceId,
                amountSigned,
                notes,
                voucherNumber
         FROM partnerLedger
         WHERE organizationId = ? AND branchId = ?
           AND partnerKind = 'customer' AND partnerId = ?
           AND entryDate >= ? AND entryDate <= ?
         ORDER BY entryDate DESC''',
      [s.organizationId, s.branchId, customerId, isoDayStart(from), isoDayEnd(to)],
    );
    return rows
        .map(
          (r) => <String, Object?>{
            'eventDate': r['eventDate'],
            'movementKind': AccountingService._ledgerMovementKindCustomer(
              (r['entryType'] ?? '').toString(),
            ),
            'amount': r['amountSigned'],
            'paymentType': AccountingService._ledgerReferenceArabic(
              (r['referenceType'] ?? '').toString(),
            ),
            'referenceType': r['referenceType'],
            'referenceId': r['referenceId'],
            'voucherNumber': r['voucherNumber'],
            'notes': r['notes'],
            'entryType': r['entryType'],
          },
        )
        .toList();
  }

  /// مجموع `amountSigned` في دفتر الشركاء للعميل قبل بداية اليوم الأول من الفترة (لصف «رصيد مرحّل»).
  Future<double> customerPartnerLedgerSumBeforePeriodStart(
    String customerId,
    DateTime periodStart,
  ) async {
    final s = _mustSession();
    final db = await _databaseService.database;
    final boundary = AccountingService.isoDayStart(periodStart);
    final q = await db.rawQuery(
      '''SELECT IFNULL(SUM(amountSigned), 0) AS t
         FROM partnerLedger
         WHERE organizationId = ? AND branchId = ?
           AND partnerKind = 'customer' AND partnerId = ?
           AND entryDate < ?''',
      [s.organizationId, s.branchId, customerId, boundary],
    );
    return ((q.first['t'] as num?)?.toDouble() ?? 0.0);
  }

  /// أقدم يوم مسجّل في دفتر الشركاء للعميل (أول معاملة/فاتورة تؤثّر في الذمة)، أو `null` إن لم توجد حركات.
  Future<DateTime?> customerPartnerLedgerFirstEntryDay(String customerId) async {
    final s = _mustSession();
    final db = await _databaseService.database;
    final q = await db.rawQuery(
      '''SELECT MIN(entryDate) AS d
         FROM partnerLedger
         WHERE organizationId = ? AND branchId = ?
           AND partnerKind = 'customer' AND partnerId = ?''',
      [s.organizationId, s.branchId, customerId],
    );
    final raw = q.first['d'];
    if (raw == null) return null;
    final parsed = DateTime.tryParse(raw.toString());
    if (parsed == null) return null;
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  /// رأس فاتورة بيع (للتفاصيل داخل كشف الحساب).
  Future<Map<String, Object?>?> salesInvoiceHeaderForStatement(String invoiceId) async {
    final s = _mustSession();
    final db = await _databaseService.database;
    final rows = await db.query(
      'salesInvoices',
      where: 'id = ? AND organizationId = ? AND branchId = ?',
      whereArgs: [invoiceId, s.organizationId, s.branchId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first;
  }

  /// عدد حركات دفتر الشركاء للعميل ومجموع `amountSigned` (كامل الفترة).
  Future<Map<String, Object?>> customerPartnerLedgerAggregate(String customerId) async {
    final s = _mustSession();
    final db = await _databaseService.database;
    final q = await db.rawQuery(
      'SELECT COUNT(*) AS c, IFNULL(SUM(pl.amountSigned), 0) AS t '
      'FROM partnerLedger pl '
      'WHERE pl.organizationId = ? AND pl.branchId = ? '
      'AND pl.partnerKind = \'customer\' AND pl.partnerId = ?',
      [s.organizationId, s.branchId, customerId],
    );
    final first = q.first;
    return <String, Object?>{
      'entryCount': (first['c'] as num?)?.toInt() ?? 0,
      'signedTotal': (first['t'] as num?)?.toDouble() ?? 0.0,
    };
  }

  /// حركة الذمة للمورد من دفتر الشركاء.
  Future<List<Map<String, Object?>>> supplierSettlementMovementBetween(
    String supplierId,
    DateTime from,
    DateTime to,
  ) async {
    final s = _mustSession();
    final db = await _databaseService.database;
    final rows = await db.rawQuery(
      '''SELECT entryDate AS eventDate,
                entryType,
                referenceType,
                referenceId,
                amountSigned,
                notes
         FROM partnerLedger
         WHERE organizationId = ? AND branchId = ?
           AND partnerKind = 'supplier' AND partnerId = ?
           AND entryDate >= ? AND entryDate <= ?
         ORDER BY entryDate DESC''',
      [s.organizationId, s.branchId, supplierId, isoDayStart(from), isoDayEnd(to)],
    );
    return rows
        .map(
          (r) => <String, Object?>{
            'eventDate': r['eventDate'],
            'movementKind': AccountingService._ledgerMovementKindSupplier(
              (r['entryType'] ?? '').toString(),
            ),
            'amount': r['amountSigned'],
            'paymentType': AccountingService._ledgerReferenceArabic(
              (r['referenceType'] ?? '').toString(),
            ),
            'referenceId': r['referenceId'],
          },
        )
        .toList();
  }

  String _translateDbError(Object error) {
    if (error is! DatabaseException) {
      return 'حدث خطأ غير متوقع أثناء الحفظ.';
    }
    final message = error.toString();
    if (message.contains('uq_branches_org_code_nocase')) {
      return 'كود الفرع مستخدم بالفعل.';
    }
    if (message.contains('uq_users_org_username_nocase')) {
      return 'اسم الدخول محجوز مسبقاً.';
    }
    if (message.contains('uq_products_scope_name_nocase')) {
      return 'اسم الصنف موجود بالفعل.';
    }
    if (message.contains('uq_product_categories_scope_name_nocase')) {
      return 'اسم التصنيف موجود بالفعل في هذا الفرع.';
    }
    if (message.contains('uq_product_units_scope_name_nocase')) {
      return 'اسم الوحدة موجود بالفعل في هذا الفرع.';
    }
    if (message.contains('uq_products_scope_barcode_nocase')) {
      return _duplicateBarcodeMessage();
    }
    if (message.contains('UNIQUE constraint failed')) {
      return 'القيمة المدخلة مكررة ولا يمكن حفظها.';
    }
    return 'تعذر حفظ البيانات. يرجى المحاولة مرة أخرى.';
  }
}
