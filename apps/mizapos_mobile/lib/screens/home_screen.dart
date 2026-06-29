import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mizapos_mobile/models/dashboard_kpi_period.dart';
import 'package:mizapos_mobile/models/entities.dart';
import 'package:mizapos_mobile/screens/auth/login_screen.dart';
import 'package:mizapos_mobile/screens/auth/voucher_activation_dialog.dart';
import 'package:mizapos_mobile/services/voucher_api.dart' show VoucherStatus;
import 'package:mizapos_mobile/services/voucher_session_manager.dart';
import 'package:mizapos_mobile/screens/my_account_screen.dart';
import 'package:mizapos_mobile/screens/subscriber_account_screen.dart';
import 'package:mizapos_mobile/screens/admin_cancellation_screens.dart';
import 'package:mizapos_mobile/screens/distributor_field_orders_screens.dart';
import 'package:mizapos_mobile/screens/distributor_field_expenses_screens.dart';
import 'package:mizapos_mobile/screens/distributor_field_returns_screens.dart';
import 'package:mizapos_mobile/screens/printer_tools_screen.dart';
import 'package:mizapos_mobile/screens/cash_screen.dart';
import 'package:mizapos_mobile/screens/customer_screen.dart';
import 'package:mizapos_mobile/screens/expense_screen.dart';
import 'package:mizapos_mobile/screens/inventory_screen.dart';
import 'package:mizapos_mobile/models/store_ui_preferences.dart';
import 'package:mizapos_mobile/screens/store_settings_screen.dart';
import 'package:mizapos_mobile/screens/shared/pdf_miza_document_theme.dart';
import 'package:mizapos_mobile/screens/shared/report_export_helper.dart';
import 'package:mizapos_mobile/screens/shared/report_pdf_preview_dialog.dart';
import 'package:mizapos_mobile/screens/shared/ui_style_tokens.dart';
import 'package:mizapos_mobile/screens/users_security_screen.dart';
import 'package:mizapos_mobile/widgets/invoice_lifecycle_dialogs.dart';
import 'package:mizapos_mobile/widgets/role_quick_login_sheet.dart';
import 'package:mizapos_mobile/widgets/distributor_hub_panel.dart';
import 'package:mizapos_mobile/widgets/session_identity.dart';
import 'package:mizapos_mobile/screens/audit_log_filter_dialog.dart';
import 'package:mizapos_mobile/screens/classic_reports_screen.dart';
import 'package:mizapos_mobile/screens/queries_screen.dart';
import 'package:path/path.dart' as p;
import 'package:mizapos_mobile/screens/supplier_screen.dart';
import 'package:mizapos_mobile/app_locale.dart';
import 'package:mizapos_mobile/app_theme.dart';
import 'package:mizapos_mobile/l10n/app_localizations.dart';
import 'package:mizapos_mobile/l10n/app_localizations_home.dart';
import 'package:mizapos_mobile/screens/transaction_screen.dart';
import 'package:mizapos_mobile/ui/dial_code_picker_field.dart';
import 'package:mizapos_mobile/ui/mizapos_brand_lockup.dart';
import 'package:mizapos_mobile/ui/overlay_notice_banner.dart';
import 'package:mizapos_mobile/ui/ui_datetime_format.dart';
import 'package:mizapos_mobile/auth/auth_dial_codes.dart';
import 'package:printing/printing.dart';
import 'package:mizapos_mobile/security/security_preferences.dart';
import 'package:mizapos_mobile/config/remote_update_config.dart';
import 'package:mizapos_mobile/config/remote_signup_config.dart';
import 'package:mizapos_mobile/services/app_shutdown.dart';
import 'package:mizapos_mobile/services/accounting_service.dart';
import 'package:mizapos_mobile/services/backup_destination.dart';
import 'package:mizapos_mobile/utils/platform_android.dart';
import 'package:share_plus/share_plus.dart';
import 'package:mizapos_mobile/services/store_settings_ui_prefs.dart';
import 'package:mizapos_mobile/services/android_apk_install.dart';
import 'package:mizapos_mobile/services/app_update_service.dart';
import 'package:mizapos_mobile/services/developer_feedback_mailer.dart';
import 'package:mizapos_mobile/services/field_catalog_sync_service.dart';
import 'package:mizapos_mobile/services/field_truck_stock_sync_service.dart';
import 'package:mizapos_mobile/services/field_orders_outbox_service.dart';
import 'package:mizapos_mobile/services/license_gate.dart';
import 'package:mizapos_mobile/services/local_notifications_service.dart';
import 'package:mizapos_mobile/services/remote_signup_api.dart';
import 'package:mizapos_mobile/services/subscription_expiry_notifier.dart';
import 'package:mizapos_mobile/services/device_binding.dart';
import 'package:mizapos_mobile/utils/device_link_code.dart';
import 'package:mizapos_mobile/utils/windows_run_key.dart';
import 'package:mizapos_mobile/utils/barcode_scan_helpers.dart';
import 'package:mizapos_mobile/utils/hardware_barcode_scanner.dart';
import 'package:mizapos_mobile/utils/money_amount_words.dart';
import 'package:mizapos_mobile/widgets/invoice_pdf_fitted_pages.dart';
import 'package:mizapos_mobile/widgets/desktop_greeting_dialogs.dart';
import 'package:mizapos_mobile/widgets/simple_calculator_dialog.dart';
import 'package:mizapos_mobile/widgets/calendar_appointments_dialog.dart';
import 'package:mizapos_mobile/widgets/currency_converter_dialog.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:url_launcher/url_launcher.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.accountingService});

  final AccountingService accountingService;

  /// مفاتيح ثابتة لترتيب مربعات لوحة التحكم (لا تغيّر التسميات للحفاظ على توافق ملف الإعدادات).
  static const List<String> dashboardTileKeysDefault = [
    'sales',
    'purchases',
    'customers',
    'suppliers',
    'cash',
    'expenses',
    'inventory',
    'queries',
  ];

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  /// عند `true` تُعرض في القائمة الإدارية: إلغاء سند قبض/صرف، وإلغاء مبلغ صندوق/مدفوعات.
  static const bool _showCancelVoucherAdminMenuItems = false;

  bool get _isDistributorRole {
    final role =
        (widget.accountingService.session?.role ?? '').trim().toLowerCase();
    return role == 'distributor';
  }

  late NumberFormat _moneyFormat;
  late NumberFormat _numberFormat;
  late NumberFormat _decimalFormat;
  bool _authenticated = true;
  bool _loading = true;
  bool _savingExitBackup = false;

  /// يُحمَّل من مستخدم مسجّل (جدول users)، لا من إدخال يدوي.
  String? _subscriptionHolderLabel;
  String _currentUsername = '-';

  /// الاسم الظاهر بجانب «اسم الدخول:» في الشريط (موظف أو مشترك قسيمة أو صاحب متجر).
  String _appBarLoginDisplay = '-';

  /// دور الجلسة الحالية (owner، cashier، guest، …) لشارة الواجهة.
  String _appBarStaffRole = 'guest';
  String _storeName = 'متجر فلسطين';
  String _storeCountry = '';
  String _storeAddress = '';
  String _storePhone = '';
  String _storePhoneAlt = '';
  String? _storeLogoPath;
  String _themeColorKey = 'blue';
  // العملة الافتراضية للبرنامج: الجنيه الفلسطيني (₣ / جنيه)، وقسمته «قرش»
  // (100 قرش في الجنيه ⇒ خانتان عشريّتان). تطبَّق فقط في أول تشغيل قبل أن
  // يخصِّص المسؤول العملة من «إعدادات المتجر».
  String _baseCurrencyCode = 'جنيه';
  String _currencySubunitName = 'قرش';
  int _currencyParts = 2;
  double _taxPercent = 0;

  /// عرض أصناف المخزون عند أو تحت هذا الرصيد في لوحة التحكم.
  double _lowStockThreshold = 5;
  bool _isDarkMode = false;
  String? _hoveredCardKey;
  DateTime _now = DateTime.now();
  Timer? _clockTimer;
  Timer? _idleCheckTimer;

  /// مزامنة دورية مع خادم التفعيل أثناء بقاء الشاشة الرئيسية مفتوحة (بدون الاعتماد على الخلفية فقط).
  Timer? _licenseForegroundSyncTimer;

  /// فحص وجود إصدار أحدث (إشعار ويندوز + شريط داخل التطبيق) أثناء الجلسة.
  Timer? _appUpdateCheckTimer;

  bool _licensePeriodicSyncRunning = false;

  /// يُضبط عند [AppLifecycleState.paused] / [hidden] / [detached] لإيقاف المؤقّت دون إهدار الطلبات.
  bool _appBackgroundedForLicenseSync = false;
  bool _idleLocked = false;
  Map<String, Object?> _kpi = const {};
  Map<String, Object?> _previousKpi = const {};
  DashboardKpiPeriod _kpiPeriod = DashboardKpiPeriod.allTime;
  DashboardKpiPeriod? _kpiTrendPeriodMarker;
  Map<String, Map<String, double>> _monthCompare =
      <String, Map<String, double>>{
    'currentMonth': <String, double>{},
    'previousMonth': <String, double>{},
  };
  List<Map<String, Object?>> _lowStock = const [];
  List<Map<String, Object?>> _supplierPayReminders = const [];
  List<String> _dashboardTileOrder =
      List<String>.from(HomeScreen.dashboardTileKeysDefault);

  /// عناوين مخصصة لمربعات الشاشة الرئيسية (المفتاح → نص العرض).
  Map<String, String> _dashboardTileLabels = {};
  StoreUiPreferences _uiPrefs = StoreUiPreferences.defaults;
  bool _stockNotifyShownSession = false;
  bool _pendingActivationBannerShownSession = false;
  bool _accessSuspendedBannerShownSession = false;
  bool _backupReminderShownSession = false;
  bool _distributorCloudAutoSyncDone = false;

  AppUpdateManifest? _availableUpdate;
  String? _windowsNotifSentForVersion;
  String? _materialBannerShownForVersion;
  String? _bannerDismissedForVersion;
  final Set<String> _supplierPayNotifiedSessionKeys = <String>{};

  Map<String, Color> get _themeColorOptions => AppTheme.colorOptions;

  @override
  void initState() {
    super.initState();
    VoucherSessionManager.instance.sessionNotifier
        .addListener(_onVoucherSessionChangedForAppBar);
    VoucherSessionManager.instance.statusNotifier
        .addListener(_onVoucherSessionChangedForAppBar);
    WidgetsBinding.instance.addObserver(this);
    _numberFormat = NumberFormat.decimalPattern('ar');
    _decimalFormat =
        NumberFormat.decimalPatternDigits(locale: 'ar', decimalDigits: 2);
    _moneyFormat = _buildMoneyFormat(_baseCurrencyCode, _currencyParts);
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
    });
    _bootstrap();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncLocaleFormats();
  }

  void _syncLocaleFormats() {
    final lang = Localizations.localeOf(context).languageCode;
    final locTag = lang == 'en' ? 'en' : 'ar';
    _numberFormat = NumberFormat.decimalPattern(locTag);
    _decimalFormat =
        NumberFormat.decimalPatternDigits(locale: locTag, decimalDigits: 2);
    _moneyFormat =
        _buildMoneyFormat(_baseCurrencyCode, _currencyParts, localeTag: locTag);
  }

  bool _arabicLocaleUi() => UiDateTimeFormat.isArabicLocaleUi(context);

  String _formatUiDate(DateTime d) => UiDateTimeFormat.formatCalendarDate(d);

  String _formatUiTime(DateTime d) => UiDateTimeFormat.formatTime12Sec(
        d,
        arabicLocale: _arabicLocaleUi(),
      );

  String _formatUiDateTime(DateTime d) =>
      UiDateTimeFormat.formatCalendarDateTime(
        d,
        arabicLocale: _arabicLocaleUi(),
      );

  /// سطر ثانٍ تحت زر التفعيل أو في الحوار: أيام متبقية للتجربة أو للسنوي.
  String? _activationDaysCountLine(
    AppLocalizations loc,
    LicenseGate gate,
    DateTime now,
  ) {
    switch (gate.coverageKind(now)) {
      case LicenseCoverageKind.annual:
        final d = gate.annualDaysRemaining(now);
        if (d > 0) return loc.activationAnnualDaysRemaining(d);
        return null;
      case LicenseCoverageKind.none:
      case LicenseCoverageKind.pendingActivation:
      case LicenseCoverageKind.accessSuspended:
      case LicenseCoverageKind.grandfather:
      case LicenseCoverageKind.legacyActivated:
        return null;
    }
  }

  /// أيام متبقية لالتقاط لون الشريط (تجربة جهاز، تجربة حساب، أو اشتراك سنوي).
  int? _homeLicenseCountdownDaysForStrip() {
    final svc = widget.accountingService;
    final gate = svc.licenseGate;
    final now = DateTime.now();
    if (svc.isGuestSession) {
      return null;
    }
    switch (gate.coverageKind(now)) {
      case LicenseCoverageKind.annual:
        final d = gate.annualDaysRemaining(now);
        return d > 0 ? d : null;
      default:
        return null;
    }
  }

  /// نص الشريط تحت KPI (نفس صياغة الحوار/التذييل عند وجود عدّاد أيام).
  String? _homeLicenseSummaryStripText(AppLocalizations loc) {
    final svc = widget.accountingService;
    final gate = svc.licenseGate;
    final now = DateTime.now();
    if (svc.isGuestSession) {
      return null;
    }
    // فريق العمل ليس مسؤولاً عن الترخيص — لا نُظهر له شريط العدّ التنازلي.
    if (svc.session?.role != 'owner') {
      return null;
    }
    return _activationDaysCountLine(loc, gate, now);
  }

  Widget _buildLicenseSummaryStrip() {
    if (_loading) return const SizedBox.shrink();
    // إذا الجهاز مُفعَّل بقسيمة سارية، لا حاجة لشريط «بحاجة لمفتاح» القديم.
    return ValueListenableBuilder<VoucherStatus>(
      valueListenable: VoucherSessionManager.instance.statusNotifier,
      builder: (_, status, __) {
        if (status.isActive) return const SizedBox.shrink();
        return _buildLicenseSummaryStripBody();
      },
    );
  }

  Widget _buildLicenseSummaryStripBody() {
    final loc = AppLocalizations.of(context);
    final line = _homeLicenseSummaryStripText(loc);
    if (line == null || line.trim().isEmpty) return const SizedBox.shrink();

    final days = _homeLicenseCountdownDaysForStrip();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;

    late final Color bg;
    late final Color fg;
    late final Color border;
    if (days != null && days <= 7) {
      bg = isDark
          ? Colors.orange.shade900.withValues(alpha: 0.38)
          : Colors.orange.shade50;
      fg = isDark ? Colors.orange.shade100 : Colors.orange.shade900;
      border = Colors.orange.withValues(alpha: isDark ? 0.45 : 0.35);
    } else if (days != null && days <= 14) {
      bg = isDark
          ? Colors.amber.shade900.withValues(alpha: 0.34)
          : Colors.amber.shade50;
      fg = isDark ? Colors.amber.shade100 : Colors.amber.shade900;
      border = Colors.amber.withValues(alpha: isDark ? 0.42 : 0.32);
    } else {
      bg = scheme.surfaceContainerHighest
          .withValues(alpha: isDark ? 0.48 : 0.72);
      fg = scheme.onSurfaceVariant.withValues(alpha: 0.94);
      border = scheme.outline.withValues(alpha: 0.24);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: border, width: 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _openSubscriptionActivationFlow,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.schedule_rounded,
                  size: 17,
                  color: fg.withValues(alpha: 0.88),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    line,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: fg,
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static const Duration _licenseForegroundSyncInterval = Duration(minutes: 3);

  /// فاصل أقصر ليظهر إشعار التحديث قريباً من نشر manifest على الويب دون انتظار طويل.
  static const Duration _appUpdateCheckInterval = Duration(hours: 1);

  @override
  void dispose() {
    VoucherSessionManager.instance.sessionNotifier
        .removeListener(_onVoucherSessionChangedForAppBar);
    VoucherSessionManager.instance.statusNotifier
        .removeListener(_onVoucherSessionChangedForAppBar);
    WidgetsBinding.instance.removeObserver(this);
    _clockTimer?.cancel();
    _idleCheckTimer?.cancel();
    _licenseForegroundSyncTimer?.cancel();
    _appUpdateCheckTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    switch (state) {
      case AppLifecycleState.resumed:
        _appBackgroundedForLicenseSync = false;
        unawaited(_onAppResumedFromBackground());
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        _appBackgroundedForLicenseSync = true;
        break;
      case AppLifecycleState.inactive:
        break;
    }
  }

  Future<void> _onAppResumedFromBackground() async {
    if (!mounted || _loading) return;
    await widget.accountingService.syncLicenseGate();
    if (!mounted) return;
    await _refreshSubscriptionHolder();
    if (mounted) setState(() {});
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _showLicenseStateBannersIfNeeded());
    await _maybeSubscriptionExpiryReminders();
    unawaited(_maybeCheckAppUpdate());
    if (_isDistributorRole) {
      unawaited(_syncDistributorFieldOrdersInBackground());
    }
  }

  Future<void> _syncDistributorFieldOrdersInBackground() async {
    if (!RemoteSignupConfig.activationServerEnabled) return;
    try {
      final outbox = FieldOrdersOutboxService(
        accountingService: widget.accountingService,
      );
      await outbox.syncAllPending();
      await outbox.refreshStatuses();
      final catalog = FieldCatalogSyncService(
        accountingService: widget.accountingService,
      );
      await catalog.pullToLocalCache();
      final truck = FieldTruckStockSyncService(
        accountingService: widget.accountingService,
      );
      await truck.pullToLocalCache();
    } on Object {
      /* تجاهل — المزامنة اختيارية عند العودة للتطبيق */
    }
  }

  void _startLicenseForegroundSyncTimer() {
    _licenseForegroundSyncTimer?.cancel();
    _licenseForegroundSyncTimer =
        Timer.periodic(_licenseForegroundSyncInterval, (_) {
      unawaited(_runPeriodicLicenseSync());
    });
  }

  static bool get _supportsRemoteAppUpdate =>
      RemoteUpdateConfig.enabled &&
      (Platform.isWindows || Platform.isAndroid);

  void _startAppUpdateCheckTimer() {
    if (!_supportsRemoteAppUpdate) return;
    _appUpdateCheckTimer?.cancel();
    _appUpdateCheckTimer = Timer.periodic(_appUpdateCheckInterval, (_) {
      if (!mounted || _loading) return;
      unawaited(_maybeCheckAppUpdate());
    });
  }

  Future<void> _runPeriodicLicenseSync() async {
    if (!mounted || _loading || _appBackgroundedForLicenseSync) return;
    if (_licensePeriodicSyncRunning) return;
    _licensePeriodicSyncRunning = true;
    try {
      await widget.accountingService.syncLicenseGate();
      if (!mounted || _loading) return;
      await _refreshSubscriptionHolder();
      if (mounted) setState(() {});
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _showLicenseStateBannersIfNeeded());
    } finally {
      _licensePeriodicSyncRunning = false;
    }
  }

  Future<void> _maybeSubscriptionExpiryReminders() async {
    if (!mounted || _loading) return;
    await SubscriptionExpiryNotifier.maybeShow(
      context: context,
      loc: AppLocalizations.of(context),
      accounting: widget.accountingService,
    );
  }

  void _startIdleWatcher() {
    _idleCheckTimer?.cancel();
    if (widget.accountingService.isGuestSession) {
      return;
    }
    if (!widget.accountingService.securityPreferences.idleLockEnabled) {
      return;
    }
    widget.accountingService.bumpActivity();
    _idleCheckTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted || !_authenticated || _idleLocked) return;
      if (!widget.accountingService.securityPreferences.idleLockEnabled) {
        return;
      }
      if (widget.accountingService
          .isIdleExceeded(widget.accountingService.idleLockDuration)) {
        widget.accountingService.setSuppressIdleBump(true);
        setState(() => _idleLocked = true);
      }
    });
  }

  void _stopIdleWatcher() {
    _idleCheckTimer?.cancel();
    _idleCheckTimer = null;
  }

  Future<void> _bootstrap() async {
    await widget.accountingService.bootstrapDefaults();
    await _loadStoreSettings();
    applySavedLanguageCode(_uiPrefs.languageCode);
    if (Platform.isWindows) {
      final regErr =
          await _syncWindowsStartupRegistration(_uiPrefs.startWithWindows);
      if (regErr != null) {
        debugPrint('Windows startup Run key sync: $regErr');
      }
    }
    try {
      await widget.accountingService.enterGuestMode();
    } catch (_) {}
    _currentUsername = widget.accountingService.session?.username ?? '-';
    if (!mounted) return;
    setState(() => _loading = false);
    _startIdleWatcher();
    unawaited(_finishBootstrap());
  }

  /// مهام ما بعد الإقلاع (شبكة، لوحة KPI) — لا تُعيق عرض الواجهة.
  Future<void> _finishBootstrap() async {
    unawaited(widget.accountingService.tryFlushQueuedRemoteSignups());
    await widget.accountingService.syncLicenseGate();
    if (!mounted) return;
    await _refreshSubscriptionHolder();
    await _loadDashboard();
    if (!mounted) return;
    _startLicenseForegroundSyncTimer();
    _startAppUpdateCheckTimer();
    _maybeShowSubscriptionBindingSnack();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_maybeSubscriptionExpiryReminders());
      unawaited(_maybeCheckAppUpdate());
      unawaited(_maybeBackupReminder());
    });
  }

  Future<void> _maybeCheckAppUpdate() async {
    if (!mounted) return;
    if (!_supportsRemoteAppUpdate) return;
    try {
      final m = await AppUpdateService.checkForNewerThanInstalled();
      if (!mounted) return;
      if (m == null) {
        setState(() => _availableUpdate = null);
        return;
      }
      final vKey = AppUpdateManifest.formatForDisplay(m.latestVersion);
      setState(() => _availableUpdate = m);
      final loc = AppLocalizations.of(context);
      if (_windowsNotifSentForVersion != vKey) {
        _windowsNotifSentForVersion = vKey;
        await LocalNotificationsService.showAppUpdateAvailable(
          title: loc.appUpdateNotifyTitle,
          body: loc.appUpdateNotifyBody(vKey),
        );
      }
      if (!mounted) return;
      if (_bannerDismissedForVersion == vKey) return;
      if (_materialBannerShownForVersion == vKey) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _showAppUpdateMaterialBanner(vKey);
      });
    } on Object {
      /* تجاهل أخطاء الشبكة */
    }
  }

  void _showAppUpdateMaterialBanner(String versionKey) {
    if (!mounted || _availableUpdate == null) return;
    if (_bannerDismissedForVersion == versionKey) return;
    if (_materialBannerShownForVersion == versionKey) return;
    _materialBannerShownForVersion = versionKey;
    final loc = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentMaterialBanner();
    messenger.showMaterialBanner(
      MaterialBanner(
        leading: const Icon(Icons.system_update_alt_rounded),
        content: Text(loc.updateBannerNewVersion(versionKey)),
        actions: [
          TextButton(
            onPressed: () {
              messenger.hideCurrentMaterialBanner();
              setState(() => _bannerDismissedForVersion = versionKey);
            },
            child: Text(loc.close),
          ),
          FilledButton(
            onPressed: () async {
              messenger.hideCurrentMaterialBanner();
              if (!mounted) return;
              await _showProgramUpdateDialog();
            },
            child: Text(loc.updateInAppInstallButton),
          ),
        ],
      ),
    );
  }

  void _showLicenseStateBannersIfNeeded() {
    _showAccessSuspendedBannerIfNeeded();
    _showPendingActivationBannerIfNeeded();
  }

  void _showAccessSuspendedBannerIfNeeded() {
    if (!mounted) return;
    final gate = widget.accountingService.licenseGate;
    final kind = gate.coverageKind(DateTime.now());
    if (kind != LicenseCoverageKind.accessSuspended) {
      _accessSuspendedBannerShownSession = false;
      return;
    }
    if (_accessSuspendedBannerShownSession) return;
    _accessSuspendedBannerShownSession = true;
    final loc = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    messenger.showMaterialBanner(
      MaterialBanner(
        backgroundColor: Colors.transparent,
        elevation: 0,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        content: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [
                Colors.red.shade900,
                const Color(0xFFB91C1C),
                Colors.orange.shade900,
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.red.withValues(alpha: 0.22),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.ac_unit_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      loc.accessSuspendedBannerHeadline,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      loc.accessSuspendedBannerBody,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.96),
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              messenger.hideCurrentMaterialBanner();
              unawaited(_syncActivationAndNotify());
            },
            child: Text(
              loc.activationRefreshFromWebButton,
              style: const TextStyle(color: Colors.white),
            ),
          ),
          TextButton(
            onPressed: () => messenger.hideCurrentMaterialBanner(),
            child: Text(loc.close, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showPendingActivationBannerIfNeeded() {
    if (!mounted || _pendingActivationBannerShownSession) return;
    if (widget.accountingService.session?.role.trim().toLowerCase() != 'owner') {
      return;
    }
    if (widget.accountingService.hasVoucherOnDevice) return;
    final gate = widget.accountingService.licenseGate;
    final kind = gate.coverageKind(DateTime.now());
    if (kind == LicenseCoverageKind.accessSuspended) return;
    if (kind != LicenseCoverageKind.pendingActivation) {
      return;
    }
    _pendingActivationBannerShownSession = true;
    final loc = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    messenger.showMaterialBanner(
      MaterialBanner(
        backgroundColor: Colors.transparent,
        elevation: 0,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        content: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [Color(0xFF2563EB), Color(0xFF1D4ED8), Color(0xFF0EA5E9)],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.blue.withValues(alpha: 0.25),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.key_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      loc.pendingActivationBannerHeadline,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      loc.pendingActivationBannerBody,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.96),
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              messenger.hideCurrentMaterialBanner();
              unawaited(_openSubscriptionActivationFlow());
            },
            child: Text(loc.activationDialogTitle),
          ),
          TextButton(
            onPressed: () => messenger.hideCurrentMaterialBanner(),
            child: Text(loc.close),
          ),
        ],
      ),
    );
  }

  void _maybeShowSubscriptionBindingSnack() {
    if (!mounted || !widget.accountingService.subscriptionBindingMismatch) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              AppLocalizations.of(context).subscriptionDeviceMismatchSnack),
        ),
      );
    });
  }

  Future<void> _completeLoginAfterSuccess(
    String identifierUsed,
    AppUserSession session,
  ) async {
    setState(() {
      _authenticated = true;
      _idleLocked = false;
      if (_uiPrefs.rememberLoginUsername) {
        _uiPrefs = _uiPrefs.copyWith(lastRememberedUsername: identifierUsed);
      }
    });
    if (_uiPrefs.rememberLoginUsername) {
      await _saveStoreSettings();
    }
    _currentUsername = session.username;
    await widget.accountingService.syncLicenseGate();
    await _refreshSubscriptionHolder();
    await _refreshAppBarLoginDisplay();
    _startLicenseForegroundSyncTimer();
    _startIdleWatcher();
    await _loadDashboard();
    _maybeShowSubscriptionBindingSnack();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _showLicenseStateBannersIfNeeded());
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _tryStartupScreenAfterLogin());
    if (_uiPrefs.secureProgramReminder && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text(AppLocalizations.of(context).securityReminderSnack)),
        );
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_maybeSubscriptionExpiryReminders());
    });
    if (_supportsRemoteAppUpdate) {
      _startAppUpdateCheckTimer();
      WidgetsBinding.instance
          .addPostFrameCallback((_) => unawaited(_maybeCheckAppUpdate()));
    }
    WidgetsBinding.instance
        .addPostFrameCallback((_) => unawaited(_maybeBackupReminder()));
  }

  /// يعرض حواراً لتأكيد تسجيل الخروج لجلسة فريق العمل، ويعيد `true` إذا
  /// أكّد المستخدم. يُستخدم في كل نقاط الخروج التي يبدأها المستخدم يدوياً
  /// (زرّ الشريط العلوي، عنصر القائمة الإدارية، شاشة قفل الخمول، شاشة
  /// «حسابي» لفريق العمل). لا يُستخدم في الخروج التلقائي (مثلاً عند سحب
  /// التفعيل أو تعليق الحساب) لأنّ المستخدم لم يبدأه.
  Future<bool> _confirmStaffLogout([BuildContext? overrideCtx]) async {
    final ctx = overrideCtx ?? context;
    if (!mounted && overrideCtx == null) return false;
    final result = await showDialog<bool>(
      context: ctx,
      builder: (dlgCtx) {
        final scheme = Theme.of(dlgCtx).colorScheme;
        final dlgLoc = AppLocalizations.of(dlgCtx);
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          icon: Icon(
            Icons.logout_rounded,
            color: scheme.error,
            size: 36,
          ),
          title: Text(dlgLoc.staffLogoutConfirmTitle),
          content: Text(
            dlgLoc.staffLogoutConfirmBody,
            style: const TextStyle(height: 1.45),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dlgCtx).pop(false),
              child: Text(dlgLoc.cancel),
            ),
            FilledButton.tonalIcon(
              style: FilledButton.styleFrom(
                backgroundColor: scheme.errorContainer,
                foregroundColor: scheme.onErrorContainer,
              ),
              icon: const Icon(Icons.logout_rounded),
              label: Text(dlgLoc.logout),
              onPressed: () => Navigator.of(dlgCtx).pop(true),
            ),
          ],
        );
      },
    );
    return result == true;
  }

  /// مُغلِّف ملائم: يطلب التأكيد ثم يستدعي [_returnToGuestSession] على
  /// الموافقة فقط. يجب استدعاؤه من نقاط الخروج التي يبدأها المستخدم.
  Future<void> _promptCloseApplication() async {
    final allowExit = await _handleAppExit();
    if (!mounted || !allowExit) return;
    await _leaveApplication();
  }

  Future<void> _returnToGuestSession() async {
    widget.accountingService.setSuppressIdleBump(false);
    _stopIdleWatcher();
    widget.accountingService.clearSession();
    try {
      await widget.accountingService.enterGuestMode();
      await widget.accountingService.ensureLocalOwnerForSubscription();
      await widget.accountingService.syncLicenseGate();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _authenticated = true;
      _idleLocked = false;
      _kpi = const {};
      _previousKpi = const {};
      _kpiTrendPeriodMarker = null;
      _kpiPeriod = DashboardKpiPeriod.allTime;
      _currentUsername = widget.accountingService.session?.username ?? '-';
      _stockNotifyShownSession = false;
      _pendingActivationBannerShownSession = false;
      _accessSuspendedBannerShownSession = false;
      _supplierPayNotifiedSessionKeys.clear();
    });
    await _refreshSubscriptionHolder();
    await _refreshAppBarLoginDisplay();
    await _loadDashboard();
    _startLicenseForegroundSyncTimer();
    _startIdleWatcher();
  }

  Future<void> _refreshSubscriptionHolder() async {
    final name = await widget.accountingService.subscriptionHolderDisplayName();
    if (!mounted) return;
    setState(() => _subscriptionHolderLabel = name);
    await _refreshAppBarLoginDisplay();
  }

  /// يُحدِّث الاسم الظاهر بجانب «اسم الدخول:» في الشريط العلوي بحسب الأولوية:
  /// 1. اسم موظف فريق العمل المسجَّل (`fullName` من جدول `users`)، إن وُجد.
  /// 2. الاسم الكامل لمشترك القسيمة المسجَّل، أو بريده.
  /// 3. اسم صاحب الاشتراك من جدول `users` (المالك).
  /// 4. fallback: `_currentUsername` (عادةً «guest»).
  Future<void> _refreshAppBarLoginDisplay() async {
    String resolved = '';
    try {
      final staffName =
          await widget.accountingService.displayNameForCurrentStaffSession();
      if (staffName.trim().isNotEmpty) {
        resolved = staffName.trim();
      }
    } catch (_) {/* تجاهل */}

    if (resolved.isEmpty) {
      final vSession = VoucherSessionManager.instance.sessionNotifier.value;
      final vFull = (vSession?.fullName ?? '').trim();
      final vEmail = (vSession?.email ?? '').trim();
      if (vFull.isNotEmpty) {
        resolved = vFull;
      } else if (vEmail.isNotEmpty) {
        resolved = vEmail;
      }
    }

    if (resolved.isEmpty) {
      final holder = _subscriptionHolderLabel?.trim() ?? '';
      if (holder.isNotEmpty) {
        resolved = holder;
      }
    }

    if (resolved.isEmpty) {
      resolved = _currentUsername;
    }
    final staffRole = widget.accountingService.appBarDisplayRole;
    if (!mounted) return;
    if (_appBarLoginDisplay != resolved || _appBarStaffRole != staffRole) {
      setState(() {
        _appBarLoginDisplay = resolved;
        _appBarStaffRole = staffRole;
      });
    }
  }

  void _onVoucherSessionChangedForAppBar() {
    if (!mounted) return;
    unawaited(_refreshAppBarLoginDisplay());
  }

  Future<void> _tryStartupScreenAfterLogin() async {
    if (!mounted || !_authenticated) return;
    switch (_uiPrefs.startupScreen) {
      case 'sale':
        await _showSaleDialog();
        break;
      case 'purchase':
        await _showPurchaseDialog();
        break;
      case 'inventory':
        await Navigator.push<void>(
          context,
          MaterialPageRoute(
            builder: (_) => InventoryScreen(
              accountingService: widget.accountingService,
              currencyCode: _baseCurrencyCode,
              currencyParts: _currencyParts,
              taxPercent: _taxPercent,
              uiPrefs: _uiPrefs,
              onUiPrefsChanged: (next) {
                HardwareBarcodeScanner.instance.enabled =
                    next.hardwareBarcodeScannerEnabled;
                setState(() => _uiPrefs = next);
              },
            ),
          ),
        );
        await _loadDashboard();
        break;
      case 'cash':
        await Navigator.push<void>(
          context,
          MaterialPageRoute(
            builder: (_) => CashScreen(
              accountingService: widget.accountingService,
              currencyCode: _baseCurrencyCode,
              currencyParts: _currencyParts,
              taxPercent: _taxPercent,
              storeDisplayName: _storeName,
              storeMetaLines: [
                if (_storeCountry.trim().isNotEmpty)
                  'البلد: ${_storeCountry.trim()}',
                if (_storeAddress.trim().isNotEmpty)
                  'العنوان: ${_storeAddress.trim()}',
                if (_storePhone.trim().isNotEmpty)
                  'هاتف: ${_storePhone.trim()}',
                if (_storePhoneAlt.trim().isNotEmpty)
                  'هاتف آخر: ${_storePhoneAlt.trim()}',
              ],
            ),
          ),
        );
        await _loadDashboard();
        break;
      case 'expense':
        await Navigator.push<void>(
          context,
          MaterialPageRoute(
            builder: (_) =>
                ExpenseScreen(
                  accountingService: widget.accountingService,
                  uiPrefs: _uiPrefs,
                  taxPercent: _taxPercent,
                ),
          ),
        );
        await _loadDashboard();
        break;
      default:
        break;
    }
  }

  /// يعيد `null` عند النجاح، أو نص خطأ لعرضه على المستخدم.
  Future<String?> _syncWindowsStartupRegistration(bool enable) async {
    return WindowsRunKey.syncStartWithWindows(enable);
  }

  /// مخزون منخفض + ذمم موردين + تحديث متوفر (إن وُجد).
  int get _notificationsHubCount {
    var n = _lowStock.length + _supplierPayReminders.length;
    if (_availableUpdate != null) n += 1;
    return n;
  }

  void _notifySupplierPayRemindersImmediately(
    List<Map<String, Object?>> reminders,
  ) {
    if (!mounted || reminders.isEmpty) return;
    final loc = AppLocalizations.of(context);
    for (final r in reminders) {
      final id = (r['id'] ?? r['supplierId'] ?? '').toString();
      final name = (r['name'] ?? '-').toString();
      final st = (r['payStatus'] ?? '').toString();
      final key = '${id.isNotEmpty ? id : name}|$st';
      if (_supplierPayNotifiedSessionKeys.contains(key)) continue;
      _supplierPayNotifiedSessionKeys.add(key);
      final od = (r['overdueDays'] as int?) ?? 0;
      final ad = (r['overdueAlertDays'] as int?) ?? 0;
      final daysPast = od > ad ? od - ad : 0;
      final line = st == 'overdue'
          ? loc.notificationsSupplierOverdue(name, daysPast)
          : loc.notificationsSupplierDueToday(name);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        OverlayNoticeBanner.showMessage(
          context,
          message: line,
          duration: const Duration(seconds: 9),
          actionLabel: loc.viewAction,
          onAction: _showNotificationsHub,
          nearTop: true,
        );
      });
    }
  }

  Future<void> _loadDashboard() async {
    final period = _kpiPeriod;
    final resetTrendMarker = _kpiTrendPeriodMarker != period;
    final data = await _kpiDataForPeriod(period);
    final mom = await widget.accountingService.dashboardMonthOverMonth();
    final low = await widget.accountingService
        .lowStockProducts(maxStockQty: _lowStockThreshold, limit: 16);
    var payRem = const <Map<String, Object?>>[];
    try {
      payRem =
          await widget.accountingService.supplierDeferredPaymentReminders();
    } on Object {
      payRem = const [];
    }
    if (mounted) {
      setState(() {
        if (resetTrendMarker) {
          _kpiTrendPeriodMarker = period;
          _previousKpi = const {};
        } else {
          _previousKpi = _kpi;
        }
        _kpi = data;
        _monthCompare = mom;
        _lowStock = low;
        _supplierPayReminders = payRem;
      });
      _notifySupplierPayRemindersImmediately(payRem);
      if (_uiPrefs.notifyOutOfStock &&
          low.isNotEmpty &&
          !_stockNotifyShownSession &&
          mounted) {
        _stockNotifyShownSession = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final loc = AppLocalizations.of(context);
          OverlayNoticeBanner.showMessage(
            context,
            message: loc.lowStockSnack(low.length),
            duration: const Duration(seconds: 8),
            actionLabel: loc.viewAction,
            onAction: _showNotificationsHub,
            nearTop: true,
          );
        });
      }
    }
  }

  Future<Map<String, Object?>> _kpiDataForPeriod(DashboardKpiPeriod p) async {
    final svc = widget.accountingService;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (p) {
      case DashboardKpiPeriod.allTime:
        return svc.kpiSummary();
      case DashboardKpiPeriod.today:
        return svc.kpiSummaryForRange(today, today);
      case DashboardKpiPeriod.week:
        final start = _mondayOfWeek(today);
        return svc.kpiSummaryForRange(start, today);
      case DashboardKpiPeriod.month:
        return svc.kpiSummaryForRange(DateTime(today.year, today.month, 1), today);
      case DashboardKpiPeriod.last30Days:
        return svc.kpiSummaryForRange(
          today.subtract(const Duration(days: 29)),
          today,
        );
    }
  }

  /// بداية الأسبوع التقويمي (الاثنين) ليوم [day] المحلي.
  DateTime _mondayOfWeek(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    return d.subtract(Duration(days: d.weekday - DateTime.monday));
  }

  Future<void> _showGlobalSearch() async {
    if (!_authenticated) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => _GlobalSearchDialog(
        accountingService: widget.accountingService,
        moneyFormat: _moneyFormat,
        parentContext: context,
        currencyCode: _baseCurrencyCode,
        currencyParts: _currencyParts,
        taxPercent: _taxPercent,
        uiPrefs: _uiPrefs,
        onUiPrefsChanged: (next) {
          HardwareBarcodeScanner.instance.enabled =
              next.hardwareBarcodeScannerEnabled;
          setState(() => _uiPrefs = next);
        },
        storeDisplayName: _storeName,
        storeMetaLines: [
          if (_storeCountry.trim().isNotEmpty) 'البلد: ${_storeCountry.trim()}',
          if (_storeAddress.trim().isNotEmpty)
            'العنوان: ${_storeAddress.trim()}',
          if (_storePhone.trim().isNotEmpty) 'هاتف: ${_storePhone.trim()}',
          if (_storePhoneAlt.trim().isNotEmpty)
            'هاتف آخر: ${_storePhoneAlt.trim()}',
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const MizaPosBrandLockup(maxHeight: 168),
              const SizedBox(height: 28),
              const SizedBox(
                width: 36,
                height: 36,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
            ],
          ),
        ),
      );
    }

    final loc = AppLocalizations.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobileLayout = screenWidth < 900;

    return Stack(
      fit: StackFit.expand,
      children: [
        PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) async {
            if (didPop) return;
            final allowExit = await _handleAppExit();
            if (!mounted || !allowExit) return;
            await _leaveApplication(result);
          },
          child: Shortcuts(
            shortcuts: const {
              SingleActivator(LogicalKeyboardKey.keyD, control: true):
                  _ToggleThemeIntent(),
              SingleActivator(LogicalKeyboardKey.keyK, control: true):
                  _OpenGlobalSearchIntent(),
            },
            child: Actions(
              actions: {
                _ToggleThemeIntent: CallbackAction<_ToggleThemeIntent>(
                  onInvoke: (intent) {
                    _toggleDarkMode();
                    return null;
                  },
                ),
                _OpenGlobalSearchIntent:
                    CallbackAction<_OpenGlobalSearchIntent>(
                  onInvoke: (intent) {
                    _showGlobalSearch();
                    return null;
                  },
                ),
              },
              child: Focus(
                autofocus: true,
                child: Theme(
                  data: _buildScreenTheme(),
                  child: Scaffold(
                    appBar: AppBar(
                      backgroundColor: _currentThemeColor(),
                      title: Text(
                        loc.welcomeTitle,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                      foregroundColor: Colors.white,
                      // على الجوال: الهوية والدور في الشريط السفلي. على الحاسوب: شريط leading.
                      leadingWidth: isMobileLayout ? null : 360,
                      leading: isMobileLayout
                          ? null
                          : Builder(
                              builder: (ctx) {
                                final identitySlot = Flexible(
                                  flex: 5,
                                  child: Padding(
                                    padding:
                                        const EdgeInsetsDirectional.only(
                                            start: 6),
                                    child: SessionIdentityBar(
                                      displayName: _appBarLoginDisplay,
                                      role: _appBarStaffRole,
                                      loc: AppLocalizations.of(ctx),
                                      lightOnDark: true,
                                      inlineRole: true,
                                      borderless: true,
                                      onTap: () => unawaited(
                                          _openSessionIdentitySheet()),
                                    ),
                                  ),
                                );
                                final adminSlot = Flexible(
                                  flex: 6,
                                  child: Padding(
                                    padding:
                                        const EdgeInsetsDirectional.only(
                                            start: 8, end: 4),
                                    child: PopupMenuButton<String>(
                                  tooltip: AppLocalizations.of(ctx).systemAdmin,
                                  onSelected: _handleAdminMenuAction,
                                  itemBuilder: _buildAdminMenuEntries,
                                  position: PopupMenuPosition.under,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14)),
                                  color: Theme.of(ctx).colorScheme.surface,
                                  elevation: 10,
                                  shadowColor:
                                      Colors.black.withValues(alpha: 0.12),
                                  constraints:
                                      const BoxConstraints(minWidth: 278),
                                  menuPadding:
                                      const EdgeInsets.symmetric(vertical: 6),
                                  padding: EdgeInsets.zero,
                                  child: Padding(
                                    padding: const EdgeInsetsDirectional.only(
                                        start: 6, top: 4, bottom: 4),
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: Colors.white
                                            .withValues(alpha: 0.14),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: Colors.white
                                              .withValues(alpha: 0.32),
                                        ),
                                      ),
                                      child: Padding(
                                        padding:
                                            const EdgeInsetsDirectional.only(
                                          start: 10,
                                          end: 6,
                                          top: 8,
                                          bottom: 8,
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.business_rounded,
                                                color: Colors.white, size: 20),
                                            const SizedBox(width: 8),
                                            Text(
                                              AppLocalizations.of(ctx)
                                                  .systemAdmin,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 11.5,
                                                fontWeight: FontWeight.w700,
                                                height: 1.1,
                                              ),
                                            ),
                                            Icon(Icons.arrow_drop_down_rounded,
                                                color: Colors.white
                                                    .withValues(alpha: 0.82),
                                                size: 22),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                  ),
                                );
                                final isRtl = Directionality.of(ctx) ==
                                    ui.TextDirection.rtl;
                                final slots = <Widget>[
                                  identitySlot,
                                  adminSlot,
                                ];
                                return Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children:
                                      isRtl ? slots.reversed.toList() : slots,
                                );
                              },
                            ),
                      centerTitle: true,
                      actions: [
                        if (isMobileLayout)
                          PopupMenuButton<String>(
                            tooltip: AppLocalizations.of(context).systemAdmin,
                            onSelected: _handleAdminMenuAction,
                            itemBuilder: _buildAdminMenuEntries,
                            icon: const Icon(Icons.manage_accounts_rounded),
                          ),
                        IconButton(
                          onPressed: _showGlobalSearch,
                          icon: const Icon(Icons.search_rounded),
                          tooltip: loc.quickSearchTooltip,
                        ),
                        Stack(
                          clipBehavior: Clip.none,
                          alignment: Alignment.center,
                          children: [
                            IconButton(
                              onPressed: _showNotificationsHub,
                              icon: const Icon(Icons.notifications_rounded),
                              tooltip: loc.notificationsCenterTooltip,
                            ),
                            if (_notificationsHubCount > 0)
                              PositionedDirectional(
                                top: 4,
                                end: 2,
                                child: Container(
                                  constraints: const BoxConstraints(
                                      minWidth: 17, minHeight: 17),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 4, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: Colors.red.shade700,
                                    borderRadius: BorderRadius.circular(9),
                                  ),
                                  child: Text(
                                    _notificationsHubCount > 99
                                        ? '99+'
                                        : '$_notificationsHubCount',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        if (!isMobileLayout) ...[
                          IconButton(
                            onPressed: _toggleDarkMode,
                            icon: Icon(_isDarkMode
                                ? Icons.dark_mode_rounded
                                : Icons.light_mode_rounded),
                            tooltip: _isDarkMode
                                ? loc.themeLightTooltip
                                : loc.themeDarkTooltip,
                          ),
                          const SizedBox(width: 4),
                          IconButton(
                            onPressed: () => unawaited(_interactiveBackup()),
                            icon: const Icon(Icons.backup),
                            tooltip: loc.backupTooltip,
                          ),
                          const SizedBox(width: 4),
                          IconButton(
                            onPressed: () =>
                                unawaited(_promptCloseApplication()),
                            icon: const Icon(Icons.exit_to_app_rounded),
                            tooltip: loc.quitApp,
                          ),
                        ] else
                          PopupMenuButton<String>(
                            icon: const Icon(Icons.more_vert_rounded),
                            onSelected: (value) async {
                              switch (value) {
                                case 'theme':
                                  _toggleDarkMode();
                                  break;
                                case 'backup':
                                  await _interactiveBackup();
                                  break;
                                case 'close_app':
                                  await _promptCloseApplication();
                                  break;
                              }
                            },
                            itemBuilder: (ctx) => [
                              PopupMenuItem(
                                value: 'theme',
                                child: Text(_isDarkMode
                                    ? loc.themeLightTooltip
                                    : loc.themeDarkTooltip),
                              ),
                              PopupMenuItem(
                                value: 'backup',
                                child: Text(loc.backupTooltip),
                              ),
                              PopupMenuItem(
                                value: 'close_app',
                                child: Text(loc.quitApp),
                              ),
                            ],
                          ),
                        const SizedBox(width: 6),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: CircleAvatar(
                            backgroundColor:
                                Colors.white.withValues(alpha: 0.18),
                            backgroundImage: _resolvedLogoPath != null
                                ? FileImage(File(_resolvedLogoPath!))
                                : null,
                            child: _resolvedLogoPath == null
                                ? const Icon(Icons.storefront_rounded,
                                    color: Colors.white)
                                : null,
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                    ),
                    body: Column(
                      children: [
                        if (!_isDistributorRole) ...[
                          _VoucherReadOnlyBanner(
                            onOpenActivation: _openSubscriptionActivationFlow,
                          ),
                          if (_uiPrefs.showDashboardGreetingBanner)
                            _buildHeroSummaryHeader(),
                          if (_uiPrefs.isHomeKpiStatsStripVisible) _buildKpiStrip(),
                          _buildLicenseSummaryStrip(),
                        ],
                        Expanded(
                          child: _isDistributorRole
                              ? _buildDistributorHub(context)
                              : LayoutBuilder(
                            builder: (context, constraints) {
                              final height = constraints.maxHeight;
                              // هاتف/عرض ضيق: عمودان؛ لاب توب وسطح مكتب: 4 مربعات في كل صف.
                              final crossAxisCount = isMobileLayout ? 2 : 4;
                              const horizontalPadding = 12.0;
                              const verticalPadding = 12.0;
                              const spacing = 12.0;
                              final menuItems =
                                  _visibleDashboardTilesInOrder(context);
                              final rows =
                                  (menuItems.length / crossAxisCount).ceil();
                              final totalVerticalSpacing = spacing * (rows - 1);
                              final availableHeight = constraints.maxHeight -
                                  (verticalPadding * 2) -
                                  totalVerticalSpacing;
                              final cardHeightMin =
                                  isMobileLayout ? 120.0 : 108.0;
                              final cardHeightMax =
                                  isMobileLayout ? 320.0 : 260.0;
                              final cardHeight = rows > 0
                                  ? (availableHeight / rows)
                                      .clamp(cardHeightMin, cardHeightMax)
                                  : (isMobileLayout ? 160.0 : 148.0);
                              final estimatedGridHeight = (rows * cardHeight) +
                                  totalVerticalSpacing +
                                  (verticalPadding * 2);
                              final shouldScrollGrid =
                                  estimatedGridHeight > height;

                              return Center(
                                child: GridView.builder(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: horizontalPadding,
                                    vertical: verticalPadding,
                                  ),
                                  physics: shouldScrollGrid
                                      ? const AlwaysScrollableScrollPhysics()
                                      : const NeverScrollableScrollPhysics(),
                                  gridDelegate:
                                      SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: crossAxisCount,
                                    mainAxisSpacing: spacing,
                                    crossAxisSpacing: spacing,
                                    mainAxisExtent: cardHeight,
                                  ),
                                  itemCount: menuItems.length,
                                  itemBuilder: (context, index) {
                                    final cfg = menuItems[index];
                                    return _menuCard(cfg);
                                  },
                                ),
                              );
                            },
                          ),
                        ),
                        _buildStoreNameFooter(),
                        if (!isMobileLayout) _buildBottomControlCell(),
                      ],
                    ),
                    bottomNavigationBar: isMobileLayout && !_isDistributorRole
                        ? SafeArea(
                            top: false,
                            child: NavigationBar(
                              height: 64,
                              backgroundColor:
                                  Theme.of(context).colorScheme.surface,
                              indicatorColor: Colors.transparent,
                              labelBehavior:
                                  NavigationDestinationLabelBehavior.alwaysHide,
                              selectedIndex: 0,
                              onDestinationSelected: (index) async {
                                if (_isDistributorRole) {
                                  if (index == 0) {
                                    await _openSessionIdentitySheet();
                                  }
                                  return;
                                }
                                switch (index) {
                                  case 0:
                                    await _showSaleDialog();
                                    break;
                                  case 1:
                                    await _showPurchaseDialog();
                                    break;
                                  case 2:
                                    await _openSubscriptionActivationFlow();
                                    break;
                                  case 3:
                                    await _interactiveBackup();
                                    break;
                                  case 4:
                                    await _openSessionIdentitySheet();
                                    break;
                                }
                                if (mounted) {
                                  await _loadDashboard();
                                }
                              },
                              destinations: [
                                if (!_isDistributorRole) ...[
                                  NavigationDestination(
                                    icon: _mobileBrightIconChip(
                                      Icons.point_of_sale_rounded,
                                      _MobileBrightIconStyle.blue,
                                    ),
                                    label: 'sale',
                                  ),
                                  NavigationDestination(
                                    icon: _mobileBrightIconChip(
                                      Icons.shopping_bag_rounded,
                                      _MobileBrightIconStyle.orange,
                                    ),
                                    label: 'purchase',
                                  ),
                                  NavigationDestination(
                                    icon: _mobileBrightIconChip(
                                      _isVoucherActive
                                          ? Icons.verified_rounded
                                          : Icons.key_rounded,
                                      _isVoucherActive
                                          ? _MobileBrightIconStyle.emerald
                                          : _MobileBrightIconStyle.amber,
                                    ),
                                    label: 'activation',
                                    tooltip: AppLocalizations.of(context)
                                        .activationSubscriptionButtonTooltip,
                                  ),
                                  NavigationDestination(
                                    icon: _mobileBrightIconChip(
                                      Icons.backup_rounded,
                                      _MobileBrightIconStyle.sky,
                                    ),
                                    label: 'backup',
                                    tooltip: AppLocalizations.of(context)
                                        .backupTooltip,
                                  ),
                                ],
                                NavigationDestination(
                                  icon: _buildMobileBottomRoleIcon(),
                                  selectedIcon:
                                      _buildMobileBottomRoleIcon(selected: true),
                                  label: 'account',
                                  tooltip: AppLocalizations.of(context)
                                      .sessionIdentityTapTooltip,
                                ),
                              ],
                            ),
                          )
                        : null,
                  ),
                ),
              ),
            ),
          ),
        ),
        if (_idleLocked)
          _IdleLockBarrier(
            accountingService: widget.accountingService,
            onUnlocked: () {
              widget.accountingService.setSuppressIdleBump(false);
              widget.accountingService.bumpActivity();
              setState(() => _idleLocked = false);
            },
            onLogout: () {
              unawaited(_promptCloseApplication());
            },
          ),
      ],
    );
  }

  /// عند جذر التطبيق لا نستخدم [Navigator.pop] — يُفرغ المكدس وتظهر شاشة سوداء.
  Future<void> _leaveApplication([Object? navigatorResult]) async {
    if (!mounted) return;
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop(navigatorResult);
      return;
    }
    await AppShutdown.exitApplication();
  }

  Future<bool> _handleAppExit() async {
    if (_savingExitBackup) return false;
    final loc = AppLocalizations.of(context);
    final exitDetail = _uiPrefs.autoBackupOnExit
        ? (kIsAndroidApp
            ? loc.confirmExitWithBackupMobile
            : loc.confirmExitWithBackup(
                StoreUiPreferences.sanitizeDriveLetter(
                  _uiPrefs.backupDriveLetter,
                ),
              ))
        : loc.confirmExitNoAutoBackup;
    final confirmExit = await showDesktopThankYouExitDialog(
      context,
      storeName: _storeName,
      extraBody: exitDetail,
    );
    if (!confirmExit) return false;

    if (!_uiPrefs.autoBackupOnExit) {
      return true;
    }

    setState(() => _savingExitBackup = true);
    String? backupPath;
    String? backupError;
    try {
      final now = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      backupPath = await widget.accountingService.backupToJson(
        filePath: _resolveBackupFilePath(now),
      );
    } catch (e) {
      backupError = e is LicenseException
          ? AppLocalizations.of(context).licenseErrorMessage(e.code)
          : e.toString();
    } finally {
      if (mounted) {
        setState(() => _savingExitBackup = false);
      }
    }

    if (!mounted) return true;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final loc = AppLocalizations.of(dialogContext);
        final backupBody = backupError != null
            ? loc.backupFailedBody(backupError)
            : loc.backupSavedBody(backupPath ?? '');
        return AlertDialog(
          title: Text(backupError == null
              ? loc.backupSavedTitle
              : loc.backupFailedTitle),
          content: Text(
            backupBody,
            textAlign: TextAlign.start,
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(loc.quitApp),
            ),
          ],
        );
      },
    );
    return true;
  }

  Widget _buildKpiStrip() {
    final loc = AppLocalizations.of(context);
    final isMobile = MediaQuery.of(context).size.width < 900;
    Widget item(String title, double value, Color tone, String key) {
      final previous = (_previousKpi[key] ?? value) as double;
      final trend = value.compareTo(previous);
      final changePercent = _calculatePercentChange(previous, value);
      final trendIcon = trend > 0
          ? Icons.arrow_upward
          : trend < 0
              ? Icons.arrow_downward
              : Icons.remove;
      final trendColor = trend > 0
          ? Colors.green.shade800
          : trend < 0
              ? Colors.red.shade800
              : Colors.grey.shade700;
      final trendSurface = trend > 0
          ? Colors.green.withValues(alpha: 0.14)
          : trend < 0
              ? Colors.red.withValues(alpha: 0.14)
              : tone.withValues(alpha: 0.12);
      return SizedBox(
        width: isMobile ? 192 : 224,
        child: Card(
          elevation: 0.8,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          color: Theme.of(context).colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: tone.withValues(alpha: 0.26),
              width: 1.1,
            ),
          ),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(
                colors: [
                  trendSurface,
                  Theme.of(context).colorScheme.surface,
                ],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: tone.withValues(alpha: 0.95),
                      fontSize: 12.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _moneyFormat.format(value),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: tone,
                      fontWeight: FontWeight.w800,
                      fontSize: isMobile ? 15.5 : 16.5,
                      letterSpacing: 0.15,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: trendSurface,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(trendIcon, size: 13, color: trendColor),
                            const SizedBox(width: 3),
                            Text(
                              trend > 0
                                  ? loc.momChangeUp(changePercent)
                                  : trend < 0
                                      ? loc.momChangeDown(changePercent)
                                      : loc.momFlat,
                              style: TextStyle(
                                color: trendColor,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (key == 'stockValue' &&
                      _kpiPeriod != DashboardKpiPeriod.allTime) ...[
                    const SizedBox(height: 6),
                    Text(
                      loc.kpiStockCurrentTotalsFootnote,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 9.5,
                        height: 1.2,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.52),
                      ),
                    ),
                  ],
                  if (key == 'cashBalance' &&
                      _kpiPeriod != DashboardKpiPeriod.allTime) ...[
                    const SizedBox(height: 6),
                    Text(
                      loc.kpiCashNetInPeriodFootnote,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 9.5,
                        height: 1.2,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.52),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (isMobile) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            item(loc.kpiSales, (_kpi['sales'] ?? 0.0) as double,
                Colors.green.shade700, 'sales'),
            item(loc.kpiPurchases, (_kpi['purchases'] ?? 0.0) as double,
                AppTheme.seedDark, 'purchases'),
            item(loc.kpiExpenses, (_kpi['expenses'] ?? 0.0) as double,
                Colors.red.shade700, 'expenses'),
            item(loc.kpiCash, (_kpi['cashBalance'] ?? 0.0) as double,
                Colors.teal.shade700, 'cashBalance'),
            item(loc.kpiStockValue, (_kpi['stockValue'] ?? 0.0) as double,
                Colors.deepPurple.shade700, 'stockValue'),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          item(loc.kpiSales, (_kpi['sales'] ?? 0.0) as double,
              Colors.green.shade700, 'sales'),
          item(loc.kpiPurchases, (_kpi['purchases'] ?? 0.0) as double,
              AppTheme.seedDark, 'purchases'),
          item(loc.kpiExpenses, (_kpi['expenses'] ?? 0.0) as double,
              Colors.red.shade700, 'expenses'),
          item(loc.kpiCash, (_kpi['cashBalance'] ?? 0.0) as double,
              Colors.teal.shade700, 'cashBalance'),
          item(loc.kpiStockValue, (_kpi['stockValue'] ?? 0.0) as double,
              Colors.deepPurple.shade700, 'stockValue'),
        ],
      ),
    );
  }

  Future<void> _showMonthComparisonDialog() async {
    final cur = _monthCompare['currentMonth'] ?? const <String, double>{};
    final prev = _monthCompare['previousMonth'] ?? const <String, double>{};
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final loc = AppLocalizations.of(dialogContext);
        return AlertDialog(
          title: Text(loc.monthCompareTitle),
          content: SizedBox(
            width: 760,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    loc.monthCompareHint,
                    textAlign: TextAlign.start,
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    reverse: true,
                    child: Row(
                      children: [
                        _monthCompareBarsCard(
                          loc: loc,
                          label: loc.kpiSales,
                          current: cur['sales'] ?? 0,
                          previous: prev['sales'] ?? 0,
                          color: Colors.green.shade700,
                        ),
                        _monthCompareBarsCard(
                          loc: loc,
                          label: loc.kpiPurchases,
                          current: cur['purchases'] ?? 0,
                          previous: prev['purchases'] ?? 0,
                          color: AppTheme.seedDark,
                        ),
                        _monthCompareBarsCard(
                          loc: loc,
                          label: loc.kpiExpenses,
                          current: cur['expenses'] ?? 0,
                          previous: prev['expenses'] ?? 0,
                          color: Colors.red.shade700,
                        ),
                        _monthCompareBarsCard(
                          loc: loc,
                          label: loc.netCashLabel,
                          current: cur['cashNet'] ?? 0,
                          previous: prev['cashNet'] ?? 0,
                          color: Colors.teal.shade800,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(loc.close)),
          ],
        );
      },
    );
  }

  Widget _monthCompareBarsCard({
    required AppLocalizations loc,
    required String label,
    required double current,
    required double previous,
    required Color color,
  }) {
    final maxV = math.max(current, previous);
    const hBase = 72.0;
    final scale = maxV > 0.00001 ? hBase / maxV : 0.0;
    final hCur = maxV > 0 ? (current * scale).clamp(4.0, hBase) : 4.0;
    final hPrev = maxV > 0 ? (previous * scale).clamp(4.0, hBase) : 4.0;
    final pct = _calculatePercentChange(previous, current);
    return Card(
      margin: const EdgeInsets.only(left: 8, right: 0, top: 2, bottom: 2),
      elevation: 0.4,
      child: SizedBox(
        width: 168,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(label,
                  style: TextStyle(
                      fontWeight: FontWeight.w700, color: color, fontSize: 13)),
              const SizedBox(height: 6),
              SizedBox(
                height: hBase,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _barPillar(
                        height: hCur, color: color, tooltip: loc.monthBarThis),
                    _barPillar(
                        height: hPrev,
                        color: Colors.grey.shade500,
                        tooltip: loc.monthBarPrev),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                loc.monthCurFmt(_moneyFormat.format(current)),
                style: TextStyle(
                    fontSize: 11, color: color.withValues(alpha: 0.95)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                loc.monthPrevFmt(_moneyFormat.format(previous)),
                style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                previous.abs() < 0.00001 && current.abs() < 0.00001
                    ? loc.monthNoData
                    : previous.abs() < 0.00001 && current > 0
                        ? loc.monthActivityThis
                        : loc.monthChangePct(pct),
                style: TextStyle(fontSize: 10.5, color: Colors.grey.shade800),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _barPillar(
      {required double height, required Color color, required String tooltip}) {
    return Tooltip(
      message: tooltip,
      child: Container(
        width: 26,
        height: height,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(6),
        ),
      ),
    );
  }

  Future<void> _showLowStockDialog() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final loc = AppLocalizations.of(dialogContext);
        return AlertDialog(
          title: Text(loc
              .lowStockDialogTitle(_decimalFormat.format(_lowStockThreshold))),
          content: SizedBox(
            width: 560,
            child: _lowStock.isEmpty
                ? Text(loc.lowStockNone)
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: _lowStock.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final r = _lowStock[i];
                      final name = (r['name'] ?? '-').toString();
                      final q = ((r['stockQty'] as num?) ?? 0).toDouble();
                      return ListTile(
                        leading: const Icon(Icons.inventory_2_outlined),
                        title: Text(name),
                        subtitle: Text(
                            loc.qtyAvailableLabel(_decimalFormat.format(q))),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(loc.close)),
            if (_lowStock.isNotEmpty)
              FilledButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => InventoryScreen(
                        accountingService: widget.accountingService,
                        currencyCode: _baseCurrencyCode,
                        currencyParts: _currencyParts,
                        taxPercent: _taxPercent,
                        uiPrefs: _uiPrefs,
                        onUiPrefsChanged: (next) {
                          HardwareBarcodeScanner.instance.enabled =
                              next.hardwareBarcodeScannerEnabled;
                          setState(() => _uiPrefs = next);
                        },
                      ),
                    ),
                  ).then((_) => _loadDashboard());
                },
                child: Text(loc.openInventory),
              ),
          ],
        );
      },
    );
  }

  Future<void> _showQuickScratchpadDialog() async {
    final loc = AppLocalizations.of(context);
    final ctrl = TextEditingController(text: _uiPrefs.quickScratchpadNotes);
    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          final scheme = Theme.of(dialogContext).colorScheme;
          return AlertDialog(
            title: Row(
              children: [
                Icon(Icons.edit_note_rounded, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(child: Text(loc.homeQuickNotesTitle)),
              ],
            ),
            content: SizedBox(
              width: 460,
              height: 300,
              child: TextField(
                controller: ctrl,
                keyboardType: TextInputType.multiline,
                maxLines: null,
                expands: true,
                textAlign: TextAlign.right,
                decoration: InputDecoration(
                  alignLabelWithHint: true,
                  hintText: loc.homeQuickNotesHint,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(loc.cancel),
              ),
              FilledButton(
                onPressed: () async {
                  var t = ctrl.text;
                  if (t.length > 12000) t = t.substring(0, 12000);
                  setState(() {
                    _uiPrefs = _uiPrefs.copyWith(quickScratchpadNotes: t);
                  });
                  await _saveStoreSettings();
                  if (!dialogContext.mounted) return;
                  Navigator.pop(dialogContext);
                  if (mounted) _showSuccess(loc.homeQuickNotesSaved);
                },
                child: Text(loc.save),
              ),
            ],
          );
        },
      );
    } finally {
      ctrl.dispose();
    }
  }

  Widget _notificationsSectionHeader(
    String title,
    IconData icon,
    ColorScheme scheme,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: scheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 15,
                color: scheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showNotificationsHub() async {
    await _loadDashboard();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final loc = AppLocalizations.of(dialogContext);
        final scheme = Theme.of(dialogContext).colorScheme;
        final update = _availableUpdate;
        final updateKey = update == null
            ? null
            : AppUpdateManifest.formatForDisplay(update.latestVersion);
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.notifications_active_rounded, color: scheme.primary),
              const SizedBox(width: 10),
              Expanded(child: Text(loc.notificationsHubTitle)),
            ],
          ),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _notificationsSectionHeader(
                    loc.notificationsSectionLowStock,
                    Icons.inventory_2_outlined,
                    scheme,
                  ),
                  if (_lowStock.isEmpty)
                    Text(
                      loc.notificationsNoneLowStock,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                    )
                  else ...[
                    ..._lowStock.take(5).map((r) {
                      final name = (r['name'] ?? '-').toString();
                      final q = ((r['stockQty'] as num?) ?? 0).toDouble();
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.inventory_2_outlined),
                        title: Text(name),
                        subtitle: Text(
                          loc.qtyAvailableLabel(_decimalFormat.format(q)),
                        ),
                      );
                    }),
                    if (_lowStock.length > 5)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          '+ ${_lowStock.length - 5}',
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton(
                        onPressed: () {
                          Navigator.pop(dialogContext);
                          _showLowStockDialog();
                        },
                        child: Text(loc.notificationsViewLowStockDetails),
                      ),
                    ),
                  ],
                  const Divider(height: 28),
                  _notificationsSectionHeader(
                    loc.notificationsSectionSupplierPay,
                    Icons.receipt_long_rounded,
                    scheme,
                  ),
                  if (_supplierPayReminders.isEmpty)
                    Text(
                      loc.notificationsNoneSupplierPay,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                    )
                  else ...[
                    ..._supplierPayReminders.map((r) {
                      final name = (r['name'] ?? '-').toString();
                      final st = (r['payStatus'] ?? '').toString();
                      final od = (r['overdueDays'] as int?) ?? 0;
                      final ad = (r['overdueAlertDays'] as int?) ?? 0;
                      final daysPast = od > ad ? od - ad : 0;
                      final line = st == 'overdue'
                          ? loc.notificationsSupplierOverdue(name, daysPast)
                          : loc.notificationsSupplierDueToday(name);
                      final bal = ((r['balanceDue'] as num?) ?? 0).toDouble();
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          st == 'overdue'
                              ? Icons.error_outline_rounded
                              : Icons.event_available_rounded,
                          color: st == 'overdue'
                              ? scheme.error
                              : Colors.deepOrange.shade700,
                        ),
                        title: Text(
                          line,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(_moneyFormat.format(bal)),
                        onTap: () {
                          Navigator.pop(dialogContext);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => SupplierScreen(
                                accountingService: widget.accountingService,
                                currencyCode: _baseCurrencyCode,
                                currencyParts: _currencyParts,
                                taxPercent: _taxPercent,
                                storeDisplayName: _storeName,
                                storeMetaLines: [
                                  if (_storeCountry.trim().isNotEmpty)
                                    'البلد: ${_storeCountry.trim()}',
                                  if (_storeAddress.trim().isNotEmpty)
                                    'العنوان: ${_storeAddress.trim()}',
                                  if (_storePhone.trim().isNotEmpty)
                                    'هاتف: ${_storePhone.trim()}',
                                  if (_storePhoneAlt.trim().isNotEmpty)
                                    'هاتف آخر: ${_storePhoneAlt.trim()}',
                                ],
                              ),
                            ),
                          ).then((_) => _loadDashboard());
                        },
                      );
                    }),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton(
                        onPressed: () {
                          Navigator.pop(dialogContext);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => SupplierScreen(
                                accountingService: widget.accountingService,
                                currencyCode: _baseCurrencyCode,
                                currencyParts: _currencyParts,
                                taxPercent: _taxPercent,
                                storeDisplayName: _storeName,
                                storeMetaLines: [
                                  if (_storeCountry.trim().isNotEmpty)
                                    'البلد: ${_storeCountry.trim()}',
                                  if (_storeAddress.trim().isNotEmpty)
                                    'العنوان: ${_storeAddress.trim()}',
                                  if (_storePhone.trim().isNotEmpty)
                                    'هاتف: ${_storePhone.trim()}',
                                  if (_storePhoneAlt.trim().isNotEmpty)
                                    'هاتف آخر: ${_storePhoneAlt.trim()}',
                                ],
                              ),
                            ),
                          ).then((_) => _loadDashboard());
                        },
                        child: Text(loc.notificationsOpenSuppliers),
                      ),
                    ),
                  ],
                  const Divider(height: 28),
                  _notificationsSectionHeader(
                    loc.notificationsSectionSystemUpdate,
                    Icons.system_update_alt_rounded,
                    scheme,
                  ),
                  if (update == null || updateKey == null)
                    Text(
                      loc.notificationsNoneSystemUpdate,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                    )
                  else ...[
                    Text(
                      loc.updateInAppAvailableLine(updateKey),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(dialogContext);
                        unawaited(_showProgramUpdateDialog());
                      },
                      icon: const Icon(Icons.download_rounded),
                      label: Text(loc.notificationsInstallUpdate),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(loc.close),
            ),
          ],
        );
      },
    );
  }

  _MenuCardConfig _menuCardConfig({
    required String tileKey,
    required String title,
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required Color borderColor,
    required Future<void> Function() onTap,
  }) {
    return _MenuCardConfig(
      tileKey: tileKey,
      title: title,
      icon: icon,
      iconColor: iconColor,
      iconBg: iconBg,
      borderColor: borderColor,
      onTap: onTap,
    );
  }

  List<String> _parseDashboardTileOrder(dynamic raw) {
    const defaults = HomeScreen.dashboardTileKeysDefault;
    final valid = defaults.toSet();
    if (raw is! List || raw.isEmpty) {
      return List<String>.from(defaults);
    }
    final out = <String>[];
    final seen = <String>{};
    for (final e in raw) {
      final s = e.toString().trim();
      if (valid.contains(s) && !seen.contains(s)) {
        out.add(s);
        seen.add(s);
      }
    }
    for (final k in defaults) {
      if (!seen.contains(k)) {
        out.add(k);
      }
    }
    return out;
  }

  Map<String, String> _parseDashboardTileLabels(dynamic raw) {
    final valid = HomeScreen.dashboardTileKeysDefault.toSet();
    if (raw is! Map) return {};
    final out = <String, String>{};
    for (final e in raw.entries) {
      final k = e.key.toString().trim();
      if (!valid.contains(k)) continue;
      final v = e.value?.toString().trim() ?? '';
      if (v.isNotEmpty) {
        out[k] = v;
      }
    }
    return out;
  }

  String _dashboardTileDisplayTitle(String key) {
    final o = _dashboardTileLabels[key]?.trim();
    if (o != null && o.isNotEmpty) {
      return o;
    }
    return AppLocalizations.of(context).dashboardTileTitle(key);
  }

  String _localizedDashboardTileTitle(String key) =>
      _dashboardTileDisplayTitle(key);

  Map<String, _MenuCardConfig> _buildDashboardTileRegistry(
      BuildContext context) {
    final m = <String, _MenuCardConfig>{
      'sales': _menuCardConfig(
        tileKey: 'sales',
        title: _dashboardTileDisplayTitle('sales'),
        icon: Icons.shopping_cart_checkout_rounded,
        iconColor: const Color(0xFF172554),
        iconBg: const Color(0xFF9BB7D6),
        borderColor: const Color(0xFF5A7FA6),
        onTap: () => _showSaleDialog(),
      ),
      'purchases': _menuCardConfig(
        tileKey: 'purchases',
        title: _dashboardTileDisplayTitle('purchases'),
        icon: Icons.shopping_bag_rounded,
        iconColor: const Color(0xFF7C2D12),
        iconBg: const Color(0xFFE8B896),
        borderColor: const Color(0xFFB45309),
        onTap: () => _showPurchaseDialog(),
      ),
      'customers': _menuCardConfig(
        tileKey: 'customers',
        title: _dashboardTileDisplayTitle('customers'),
        icon: Icons.groups_rounded,
        iconColor: const Color(0xFF0C4A6E),
        iconBg: const Color(0xFF8EBAD8),
        borderColor: const Color(0xFF3B6B91),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CustomerScreen(
              accountingService: widget.accountingService,
              currencyCode: _baseCurrencyCode,
              currencyParts: _currencyParts,
              storeDisplayName: _storeName,
              storeMetaLines: [
                if (_storeCountry.trim().isNotEmpty)
                  'البلد: ${_storeCountry.trim()}',
                if (_storeAddress.trim().isNotEmpty)
                  'العنوان: ${_storeAddress.trim()}',
                if (_storePhone.trim().isNotEmpty)
                  'هاتف: ${_storePhone.trim()}',
                if (_storePhoneAlt.trim().isNotEmpty)
                  'هاتف آخر: ${_storePhoneAlt.trim()}',
              ],
            ),
          ),
        ),
      ),
      'suppliers': _menuCardConfig(
        tileKey: 'suppliers',
        title: _dashboardTileDisplayTitle('suppliers'),
        icon: Icons.inventory_2_rounded,
        iconColor: const Color(0xFF7C2D12),
        iconBg: const Color(0xFFE8C9A0),
        borderColor: const Color(0xFFC27A38),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SupplierScreen(
              accountingService: widget.accountingService,
              currencyCode: _baseCurrencyCode,
              currencyParts: _currencyParts,
              taxPercent: _taxPercent,
              storeDisplayName: _storeName,
              storeMetaLines: [
                if (_storeCountry.trim().isNotEmpty)
                  'البلد: ${_storeCountry.trim()}',
                if (_storeAddress.trim().isNotEmpty)
                  'العنوان: ${_storeAddress.trim()}',
                if (_storePhone.trim().isNotEmpty)
                  'هاتف: ${_storePhone.trim()}',
                if (_storePhoneAlt.trim().isNotEmpty)
                  'هاتف آخر: ${_storePhoneAlt.trim()}',
              ],
            ),
          ),
        ),
      ),
      'cash': _menuCardConfig(
        tileKey: 'cash',
        title: _dashboardTileDisplayTitle('cash'),
        icon: Icons.account_balance_wallet_rounded,
        iconColor: const Color(0xFF064E3B),
        iconBg: const Color(0xFF7EBFB2),
        borderColor: const Color(0xFF3D7A6E),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CashScreen(
              accountingService: widget.accountingService,
              currencyCode: _baseCurrencyCode,
              currencyParts: _currencyParts,
              taxPercent: _taxPercent,
              storeDisplayName: _storeName,
              storeMetaLines: [
                if (_storeCountry.trim().isNotEmpty)
                  'البلد: ${_storeCountry.trim()}',
                if (_storeAddress.trim().isNotEmpty)
                  'العنوان: ${_storeAddress.trim()}',
                if (_storePhone.trim().isNotEmpty)
                  'هاتف: ${_storePhone.trim()}',
                if (_storePhoneAlt.trim().isNotEmpty)
                  'هاتف آخر: ${_storePhoneAlt.trim()}',
              ],
            ),
          ),
        ),
      ),
      'expenses': _menuCardConfig(
        tileKey: 'expenses',
        title: _dashboardTileDisplayTitle('expenses'),
        icon: Icons.payment_rounded,
        iconColor: const Color(0xFF713F12),
        iconBg: const Color(0xFFE8D49A),
        borderColor: const Color(0xFFB45309),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ExpenseScreen(
              accountingService: widget.accountingService,
              uiPrefs: _uiPrefs,
              taxPercent: _taxPercent,
            ),
          ),
        ),
      ),
      'inventory': _menuCardConfig(
        tileKey: 'inventory',
        title: _dashboardTileDisplayTitle('inventory'),
        icon: Icons.warehouse_rounded,
        iconColor: const Color(0xFF052E16),
        iconBg: const Color(0xFF8FC4A0),
        borderColor: const Color(0xFF3F6B4C),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => InventoryScreen(
              accountingService: widget.accountingService,
              currencyCode: _baseCurrencyCode,
              currencyParts: _currencyParts,
              taxPercent: _taxPercent,
              uiPrefs: _uiPrefs,
              onUiPrefsChanged: (next) {
                HardwareBarcodeScanner.instance.enabled =
                    next.hardwareBarcodeScannerEnabled;
                setState(() => _uiPrefs = next);
              },
            ),
          ),
        ),
      ),
    };
    if (widget.accountingService.canViewFinancialReports() ||
        widget.accountingService.isGuestSession) {
      m['queries'] = _menuCardConfig(
        tileKey: 'queries',
        title: _dashboardTileDisplayTitle('queries'),
        icon: Icons.insert_chart_outlined_rounded,
        iconColor: const Color(0xFF1E1B4B),
        iconBg: const Color(0xFFB8BEE8),
        borderColor: const Color(0xFF5C62A0),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => QueriesScreen(
              accountingService: widget.accountingService,
              taxPercent: _taxPercent,
              onOpenSaleInvoiceFromReport:
                  _openSaleTransactionForInvoiceEdit,
              onOpenClassicReports:
                  widget.accountingService.canViewFinancialReports()
                      ? _showReportsDialog
                      : null,
            ),
          ),
        ),
      );
    }
    return m;
  }

  Future<void> _openDistributorReturns(BuildContext context) async {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => DistributorFieldReturnsListScreen(
          accountingService: widget.accountingService,
          currencyCode: _baseCurrencyCode,
          currencyParts: _currencyParts,
        ),
      ),
    );
  }

  Future<void> _openDistributorExpenses(BuildContext context) async {
    final loc = AppLocalizations.of(context);
    final distributorName =
        await widget.accountingService.currentUserDisplayName();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Row(
                    children: [
                      const Icon(Icons.payments_outlined,
                          color: Color(0xFF059669)),
                      const SizedBox(width: 10),
                      Text(
                        loc.distributorExpenses,
                        style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ],
                  ),
                ),
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFD1FAE5),
                    child: Icon(Icons.add_card_rounded,
                        color: Color(0xFF059669)),
                  ),
                  title: Text(loc.distributorNewExpense),
                  onTap: () {
                    Navigator.pop(ctx);
                    unawaited(
                      Navigator.of(context).push<bool>(
                        MaterialPageRoute<bool>(
                          builder: (_) => DistributorFieldExpenseComposeScreen(
                            accountingService: widget.accountingService,
                            currencyCode: _baseCurrencyCode,
                            currencyParts: _currencyParts,
                            distributorDisplayName: distributorName,
                          ),
                        ),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFD1FAE5),
                    child: Icon(Icons.history_rounded, color: Color(0xFF059669)),
                  ),
                  title: Text(loc.distributorMyExpenses),
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => DistributorFieldExpensesListScreen(
                          accountingService: widget.accountingService,
                          currencyCode: _baseCurrencyCode,
                          currencyParts: _currencyParts,
                          distributorDisplayName: distributorName,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDistributorHub(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final svc = widget.accountingService;
    final cloudPending =
        svc.isSessionCloudDistributor && !svc.hasDistributorCloudAccess;

    if (cloudPending && !_distributorCloudAutoSyncDone) {
      _distributorCloudAutoSyncDone = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final ok = await svc.refreshDistributorCloudLicense();
        if (!mounted) return;
        setState(() {});
        if (ok) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(loc.distributorCloudSyncOk)),
          );
        }
      });
    }

    return FutureBuilder<String>(
      future: widget.accountingService.currentUserDisplayName(),
      builder: (context, nameSnap) {
        final distributorName = nameSnap.data ?? '';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (cloudPending) ...[
              Material(
                color: const Color(0xFFFFF7ED),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.cloud_off_rounded,
                              size: 22, color: Color(0xFFC2410C)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              loc.distributorCloudSyncPendingBanner,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 12.5,
                                height: 1.35,
                                color: Color(0xFF9A3412),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      FilledButton.icon(
                        onPressed: () async {
                          final ok = await svc.refreshDistributorCloudLicense();
                          if (!mounted) return;
                          setState(() {});
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                ok
                                    ? loc.distributorCloudSyncOk
                                    : loc.distributorCloudSyncFailed,
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.sync_rounded, size: 18),
                        label: Text(loc.distributorCloudSyncButton),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            Expanded(
              child: DistributorHubPanel(
                displayName: distributorName,
                loc: loc,
                isLocalDistributor:
                    svc.isSessionLocalDistributor || cloudPending,
                onOpenIdentity: () => unawaited(_openSessionIdentitySheet()),
                onNewSale: () {
                  unawaited(
                    Navigator.of(context).push<bool>(
                      MaterialPageRoute<bool>(
                        builder: (_) => DistributorFieldOrderComposeScreen(
                          accountingService: widget.accountingService,
                          currencyCode: _baseCurrencyCode,
                          currencyParts: _currencyParts,
                          taxPercent: _taxPercent,
                          distributorDisplayName: distributorName,
                        ),
                      ),
                    ),
                  );
                },
                onMySales: () {
                  Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => DistributorFieldOrdersListScreen(
                        accountingService: widget.accountingService,
                        currencyCode: _baseCurrencyCode,
                        currencyParts: _currencyParts,
                        taxPercent: _taxPercent,
                        distributorDisplayName: distributorName,
                      ),
                    ),
                  );
                },
                onQuickNotes: () => unawaited(_showQuickScratchpadDialog()),
                onCalculator: () => showSimpleCalculatorDialog(context),
                onReturns: () => unawaited(_openDistributorReturns(context)),
                onExpenses: () => unawaited(_openDistributorExpenses(context)),
                onExitToMainApp: () async {
                  if (!await _confirmStaffLogout(context)) return;
                  await _returnToGuestSession();
                },
              ),
            ),
          ],
        );
      },
    );
  }

  List<_MenuCardConfig> _visibleDashboardTilesInOrder(BuildContext context) {
    final reg = _buildDashboardTileRegistry(context);
    final out = <_MenuCardConfig>[];
    final added = <String>{};
    for (final k in _dashboardTileOrder) {
      final c = reg[k];
      if (c != null) {
        out.add(c);
        added.add(k);
      }
    }
    for (final k in HomeScreen.dashboardTileKeysDefault) {
      if (!added.contains(k) && reg[k] != null) {
        out.add(reg[k]!);
      }
    }
    return out;
  }

  Future<List<String>?> _showDashboardTilesReorderDialog(
      List<String> initialOrder) async {
    final draft = List<String>.from(initialOrder);
    return showDialog<List<String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final loc = AppLocalizations.of(ctx);
          final rtl = Directionality.of(ctx) == ui.TextDirection.rtl;
          final hintAlign = rtl ? TextAlign.right : TextAlign.left;
          return AlertDialog(
            title: Text(loc.reorderTilesTitle),
            content: SizedBox(
              width: 420,
              height: 420,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    loc.reorderTilesHint,
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade800),
                    textAlign: hintAlign,
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ReorderableListView.builder(
                      buildDefaultDragHandles: false,
                      itemCount: draft.length,
                      onReorder: (oldIndex, newIndex) {
                        setLocal(() {
                          if (newIndex > oldIndex) newIndex -= 1;
                          final item = draft.removeAt(oldIndex);
                          draft.insert(newIndex, item);
                        });
                      },
                      itemBuilder: (context, index) {
                        final k = draft[index];
                        final queriesHidden = k == 'queries' &&
                            !widget.accountingService
                                .canViewFinancialReports() &&
                            !widget.accountingService.isGuestSession;
                        return ReorderableDragStartListener(
                          index: index,
                          key: ValueKey<String>(k),
                          child: Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            elevation: 0.5,
                            child: ListTile(
                              title: Text(_localizedDashboardTileTitle(k)),
                              subtitle: queriesHidden
                                  ? Text(
                                      loc.queriesHiddenSubtitle,
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.orange.shade800),
                                    )
                                  : null,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  setLocal(() {
                    draft
                      ..clear()
                      ..addAll(HomeScreen.dashboardTileKeysDefault);
                  });
                },
                child: Text(loc.restoreDefaultOrder),
              ),
              TextButton(
                  onPressed: () => Navigator.pop(ctx), child: Text(loc.cancel)),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, List<String>.from(draft)),
                child: Text(loc.applyOrder),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _menuCard(_MenuCardConfig config) {
    final isHovered = _hoveredCardKey == config.tileKey;
    final isMobile = MediaQuery.of(context).size.width < 900;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () async {
        await config.onTap();
        await _loadDashboard();
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _hoveredCardKey = config.tileKey),
        onExit: (_) {
          if (_hoveredCardKey == config.tileKey) {
            setState(() => _hoveredCardKey = null);
          }
        },
        child: AnimatedScale(
          scale: isHovered && !isMobile ? 1.03 : 1.0,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final h = constraints.maxHeight;
              final compact = h < 220;
              final iconBoxBase = compact ? 76.0 : 94.0;
              final iconBox = iconBoxBase.clamp(70.0, 110.0);
              final hoverBoost = (isHovered && !isMobile) ? 6.0 : 0.0;
              final iconSize = (iconBox * 0.58) + (isHovered ? 3.0 : 0.0);
              return Card(
                elevation: isHovered ? 5 : 1.2,
                shadowColor:
                    config.iconColor.withValues(alpha: isHovered ? 0.20 : 0.06),
                color: Theme.of(context).colorScheme.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: isHovered
                        ? config.iconColor.withValues(alpha: 0.6)
                        : config.borderColor,
                    width: isHovered ? 2 : 1.5,
                  ),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.center,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: iconBox + hoverBoost,
                          height: iconBox + hoverBoost,
                          decoration: BoxDecoration(
                            color: config.iconBg
                                .withValues(alpha: isHovered ? 0.85 : 0.65),
                            borderRadius:
                                BorderRadius.circular(compact ? 16 : 20),
                            boxShadow: [
                              BoxShadow(
                                color: config.iconColor
                                    .withValues(alpha: isHovered ? 0.20 : 0.09),
                                blurRadius: isHovered ? 14 : 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Icon(
                            config.icon,
                            size: iconSize,
                            color: config.iconColor,
                          ),
                        ),
                        SizedBox(height: compact ? 8 : 12),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            config.title,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize:
                                  compact ? 13 : (isHovered ? 15.5 : 14.5),
                              color: isHovered
                                  ? config.iconColor.withValues(alpha: 0.95)
                                  : Theme.of(context)
                                      .textTheme
                                      .bodyLarge
                                      ?.color,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildStoreNameFooter() {
    final accent = _currentThemeColor();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isMobile = MediaQuery.of(context).size.width < 900;
    final textColor =
        isDark ? Colors.white.withValues(alpha: 0.94) : const Color(0xFF0F172A);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 6, 24, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                  child: Divider(
                      height: 1,
                      thickness: 1,
                      color: accent.withValues(alpha: 0.35))),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Icon(Icons.store_mall_directory_rounded,
                    size: 20, color: accent.withValues(alpha: 0.9)),
              ),
              Expanded(
                  child: Divider(
                      height: 1,
                      thickness: 1,
                      color: accent.withValues(alpha: 0.35))),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _storeName,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: isMobile ? 20 : 26,
              height: 1.35,
              fontWeight: FontWeight.w800,
              letterSpacing: isMobile ? 0.2 : 0.6,
              color: textColor,
              shadows: [
                Shadow(
                  color: accent.withValues(alpha: isDark ? 0.35 : 0.18),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _dismissDashboardGreetingBanner() async {
    setState(() {
      _uiPrefs = _uiPrefs.copyWith(showDashboardGreetingBanner: false);
    });
    await _saveStoreSettings();
  }

  Widget _buildHeroSummaryHeader() {
    final loc = AppLocalizations.of(context);
    final isMobile = MediaQuery.of(context).size.width < 900;
    final sales = ((_kpi['sales'] as num?) ?? 0).toDouble();
    final purchases = ((_kpi['purchases'] as num?) ?? 0).toDouble();
    final expenses = ((_kpi['expenses'] as num?) ?? 0).toDouble();
    final net = sales - purchases - expenses;
    final accent = _currentThemeColor();
    final netColor = net >= 0 ? Colors.green.shade700 : Colors.red.shade700;
    final prevSales = ((_previousKpi['sales'] as num?) ?? sales).toDouble();
    final prevPurchases =
        ((_previousKpi['purchases'] as num?) ?? purchases).toDouble();
    final prevExpenses =
        ((_previousKpi['expenses'] as num?) ?? expenses).toDouble();
    final previousNet = prevSales - prevPurchases - prevExpenses;
    final netTrend = net.compareTo(previousNet);
    final netChangePct = _calculatePercentChange(previousNet, net);
    final bool showTrendChip = netTrend != 0;
    final String trendLabel;
    final Color trendChipColor;
    if (netTrend > 0) {
      trendLabel = loc.momChangeUp(netChangePct);
      trendChipColor = Colors.green.shade700;
    } else if (netTrend < 0) {
      trendLabel = loc.momChangeDown(netChangePct);
      trendChipColor = Colors.red.shade700;
    } else {
      trendLabel = loc.momFlat;
      trendChipColor = Colors.grey.shade700;
    }
    final scheme = Theme.of(context).colorScheme;
    final heroLineRtl =
        Directionality.of(context) == ui.TextDirection.rtl;
    final periodTooltip = _kpiPeriod == DashboardKpiPeriod.allTime
        ? loc.dashboardKpiContextLine(_kpiPeriod)
        : '${loc.dashboardKpiContextLine(_kpiPeriod)}\n${loc.dashboardHeroNetPeriodHint}';

    return Container(
      margin:
          EdgeInsets.fromLTRB(isMobile ? 10 : 14, 8, isMobile ? 10 : 14, 2),
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 10 : 14,
        vertical: isMobile ? 8 : 9,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          colors: [
            accent.withValues(alpha: 0.18),
            Theme.of(context).colorScheme.surface,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: isMobile ? 16 : 19,
                backgroundColor: accent.withValues(alpha: 0.22),
                child: Icon(
                  Icons.analytics_rounded,
                  color: accent,
                  size: isMobile ? 18 : 22,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: isMobile ? 13.5 : 15,
                          height: 1.2,
                          color: scheme.onSurface,
                        ),
                        children: heroLineRtl
                            ? [
                                TextSpan(
                                    text: loc.splashStartupGreeting(_now)),
                                const TextSpan(text: '\u2004'),
                                TextSpan(text: _storeName),
                              ]
                            : [
                                TextSpan(text: _storeName),
                                const TextSpan(text: '\u2004'),
                                TextSpan(
                                    text: loc.splashStartupGreeting(_now)),
                              ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${loc.netCashLabel}: ${_moneyFormat.format(net)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: netColor,
                        fontWeight: FontWeight.w700,
                        fontSize: isMobile ? 12 : 13,
                      ),
                    ),
                  ],
                ),
              ),
              Builder(
                builder: (ctx) {
                  final isRtl =
                      Directionality.of(ctx) == ui.TextDirection.rtl;
                  final trendChip = showTrendChip
                      ? Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 4),
                          decoration: BoxDecoration(
                            color: trendChipColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            trendLabel,
                            style: TextStyle(
                              color: trendChipColor,
                              fontWeight: FontWeight.w700,
                              fontSize: isMobile ? 10 : 11,
                            ),
                          ),
                        )
                      : null;
                  final closeButton = IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 30,
                      minHeight: 30,
                    ),
                    tooltip: loc.close,
                    onPressed: () =>
                        unawaited(_dismissDashboardGreetingBanner()),
                    icon: Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: scheme.onSurface.withValues(alpha: 0.55),
                    ),
                  );
                  final periodLabel = loc.dashboardKpiPeriodChip(_kpiPeriod);
                  final periodMenu = Tooltip(
                    message: periodTooltip,
                    waitDuration: const Duration(milliseconds: 400),
                    child: PopupMenuButton<DashboardKpiPeriod>(
                      padding: EdgeInsets.zero,
                      tooltip: '',
                      offset: const Offset(0, 6),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      onSelected: (p) {
                        if (_kpiPeriod == p) return;
                        setState(() => _kpiPeriod = p);
                        unawaited(_loadDashboard());
                      },
                      itemBuilder: (c) => [
                        for (final p in DashboardKpiPeriod.values)
                          PopupMenuItem<DashboardKpiPeriod>(
                            value: p,
                            child: Text(loc.dashboardKpiPeriodChip(p)),
                          ),
                      ],
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 118),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 4),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                              color: accent.withValues(alpha: 0.32)),
                          color: accent.withValues(alpha: 0.1),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: isRtl
                              ? [
                                  Icon(
                                    Icons.tune_rounded,
                                    size: isMobile ? 15 : 16,
                                    color: accent,
                                  ),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      periodLabel,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: isMobile ? 10 : 10.5,
                                        color: scheme.onSurface,
                                      ),
                                    ),
                                  ),
                                  Icon(
                                    Icons.arrow_drop_down_rounded,
                                    size: 17,
                                    color: scheme.onSurface
                                        .withValues(alpha: 0.65),
                                  ),
                                ]
                              : [
                                  Flexible(
                                    child: Text(
                                      periodLabel,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: isMobile ? 10 : 10.5,
                                        color: scheme.onSurface,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(
                                    Icons.tune_rounded,
                                    size: isMobile ? 15 : 16,
                                    color: accent,
                                  ),
                                  Icon(
                                    Icons.arrow_drop_down_rounded,
                                    size: 17,
                                    color: scheme.onSurface
                                        .withValues(alpha: 0.65),
                                  ),
                                ],
                        ),
                      ),
                    ),
                  );
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: isRtl
                        ? [
                            closeButton,
                            const SizedBox(width: 2),
                            periodMenu,
                            if (trendChip != null) ...[
                              const SizedBox(width: 6),
                              trendChip,
                            ],
                          ]
                        : [
                            if (trendChip != null) ...[
                              trendChip,
                              const SizedBox(width: 6),
                            ],
                            periodMenu,
                            const SizedBox(width: 2),
                            closeButton,
                          ],
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            _kpiPeriod == DashboardKpiPeriod.allTime
                ? loc.dashboardKpiContextLine(_kpiPeriod)
                : '${loc.dashboardKpiContextLine(_kpiPeriod)} · ${loc.dashboardHeroNetPeriodHint}',
            textAlign: TextAlign.start,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              height: 1.25,
              fontWeight: FontWeight.w500,
              color: scheme.onSurface.withValues(alpha: 0.52),
            ),
          ),
          if (_lowStock.isNotEmpty) ...[
            const SizedBox(height: 6),
            Material(
              color: Colors.orange.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                onTap: _showLowStockDialog,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      Icon(Icons.inventory_2_outlined,
                          color: Colors.orange.shade900, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          loc.lowStockSnack(_lowStock.length),
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Colors.orange.shade900,
                            height: 1.25,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _activationFooterLabel(AppLocalizations loc) {
    final svc = widget.accountingService;
    final gate = svc.licenseGate;
    final now = DateTime.now();
    if (svc.isGuestSession) return loc.activationFooterGuest;
    switch (gate.coverageKind(now)) {
      case LicenseCoverageKind.none:
        return loc.activationFooterNeedsKey;
      case LicenseCoverageKind.grandfather:
        return loc.activationFooterGrandfather;
      case LicenseCoverageKind.legacyActivated:
        return loc.activationFooterLegacy;
      case LicenseCoverageKind.pendingActivation:
        return loc.activationFooterPendingLimited;
      case LicenseCoverageKind.accessSuspended:
        return loc.activationFooterSuspended;
      case LicenseCoverageKind.annual:
        final end = gate.annualEndAt;
        return end != null
            ? loc.activationFooterAnnualUntil(_formatUiDate(end))
            : loc.activatedBadge(true);
    }
  }

  bool _activationFooterShowsPriceHint({
    required bool voucherActive,
    required bool isGuest,
    required LicenseCoverageKind kind,
  }) {
    if (voucherActive) return false;
    if (isGuest) return true;
    return kind == LicenseCoverageKind.none ||
        kind == LicenseCoverageKind.pendingActivation;
  }

  Widget _buildActivationFooterButtonLabel(
    AppLocalizations loc, {
    required String primary,
    String? daysDetail,
    required bool showPriceHint,
    TextStyle? primaryStyle,
    TextStyle? detailStyle,
  }) {
    final primaryWidget = Text(
      primary,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: primaryStyle,
    );
    if (!showPriceHint && (daysDetail == null || daysDetail.isEmpty)) {
      return primaryWidget;
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        primaryWidget,
        if (showPriceHint)
          Text(
            loc.subscriptionPlanPriceShort,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: detailStyle,
          ),
        if (daysDetail != null && daysDetail.isNotEmpty)
          Text(
            daysDetail,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: detailStyle,
          ),
      ],
    );
  }

  Color _activationFooterButtonColor() {
    final svc = widget.accountingService;
    final gate = svc.licenseGate;
    final now = DateTime.now();
    if (svc.isGuestSession) {
      return Theme.of(context).colorScheme.tertiary;
    }
    switch (gate.coverageKind(now)) {
      case LicenseCoverageKind.none:
        return Colors.deepOrange.shade800;
      case LicenseCoverageKind.pendingActivation:
        return Colors.teal.shade700;
      case LicenseCoverageKind.accessSuspended:
        return Colors.red.shade900;
      case LicenseCoverageKind.annual:
      case LicenseCoverageKind.grandfather:
      case LicenseCoverageKind.legacyActivated:
        return Colors.green.shade800;
    }
  }

  /// هل القسيمة (الجديدة) مُفعَّلة على هذا الجهاز؟
  bool get _isVoucherActive =>
      VoucherSessionManager.instance.statusNotifier.value.isActive;

  /// فتح بنود القائمة المحمية (نسخ، تدقيق، …): قسيمة نشطة على الجهاز **أو**
  /// ترخيص تشغيلي بعد تسجيل دخول موظف — وضع الزائر مع قسيمة = مسموح.
  bool get _adminLicenseOrVoucherUnlocked {
    if (_isVoucherActive) return true;
    final svc = widget.accountingService;
    if (svc.isGuestSession) return false;
    final now = DateTime.now();
    if (svc.licenseGate.coverageKind(now) ==
        LicenseCoverageKind.accessSuspended) {
      return false;
    }
    return svc.licenseGate.hasRegisteredOperationalAccess(now);
  }

  /// هل الجلسة الحالية للمالك؟ (لتقييد إدارة الاشتراك/تحرير الجهاز
  /// على مالك النظام دون أعضاء فريق العمل أو وضع الزائر).
  bool get _isOwnerSession {
    final svc = widget.accountingService;
    if (svc.isGuestSession) return false;
    return svc.session?.role == 'owner';
  }

  /// إدارة حساب المشترك (تسجيل خروج، إدارة القسيمة) — للمالك/مدير الفرع
  /// أو للمشترك في وضع الزائر بجلسة قسيمة نشطة.
  bool get _canManageSubscriberAccount {
    if (!VoucherSessionManager.instance.hasSession) return false;
    final svc = widget.accountingService;
    if (svc.isGuestSession) return true;
    final role = svc.session?.role.trim().toLowerCase() ?? '';
    return role == 'owner' || role == 'branch_manager';
  }

  /// الزر الموحَّد «تفعيل الاشتراك»: يفتح فوراً مسار القسيمة الجديد،
  /// ثم يحدِّث الحالة ويعيد بناء الواجهة كي يتغيّر لون الزر فور التفعيل.
  Future<void> _openSubscriptionActivationFlow() async {
    if (!mounted) return;
    await showVoucherActivationDialog(
      context,
      allowSubscriberManagement: _isOwnerSession,
    );
    if (!mounted) return;
    // التزامن مع نظام التراخيص القديم (إن وُجد) + إعادة بناء.
    try {
      await widget.accountingService.syncLicenseGate();
    } catch (_) {
      /* تجاهل أخطاء الشبكة هنا */
    }
    // نُجبر على فحص حالة القسيمة من السيرفر لضمان أحدث isActive.
    try {
      await VoucherSessionManager.instance.refreshStatus();
    } catch (_) {
      /* نعتمد على الحالة المحلية المخزّنة */
    }
    if (!mounted) return;
    setState(() {});
  }

  Widget _buildMobileBottomRoleIcon({bool selected = false}) {
    final roleColors = SessionRolePalette.colorsFor(_appBarStaffRole);
    final icon = SessionRolePalette.iconFor(_appBarStaffRole);
    return Icon(
      icon,
      size: selected ? 26 : 24,
      color: roleColors.fg,
    );
  }

  /// يفتح لوحة الهوية والدور: تبديل الحساب أو تسجيل الدخول/الخروج.
  Future<void> _openSessionIdentitySheet() async {
    if (!mounted) return;
    final loc = AppLocalizations.of(context);
    final svc = widget.accountingService;
    final isStaff = !svc.isGuestSession && svc.session != null;
    final pick = await showSessionIdentitySheet(
      context: context,
      loc: loc,
      displayName: _appBarLoginDisplay,
      role: _appBarStaffRole,
      isStaffSignedIn: isStaff,
      showSwitchAccount: svc.offerStaffAccountSwitch,
    );
    if (!mounted || pick == null) return;
    if (pick.role != null) {
      await _openRoleQuickLogin(pick.role!);
      return;
    }
    final action = pick.action;
    if (action == null) return;
    switch (action) {
      case SessionIdentitySheetAction.switchAccount:
        await _openStaffLoginFormFullscreen();
        break;
      case SessionIdentitySheetAction.signOut:
        if (!await _confirmStaffLogout(context)) return;
        await _returnToGuestSession();
        break;
      case SessionIdentitySheetAction.openMyAccount:
        if (VoucherSessionManager.instance.hasSession) {
          await _openMyAccountPage();
        } else {
          await _openStaffLoginScreen();
        }
        break;
    }
    if (mounted) await _refreshAppBarLoginDisplay();
  }

  /// دخول سريع لدور معيّن (مدير، محاسب، …) من لوحة الهوية.
  Future<void> _openRoleQuickLogin(String role) async {
    if (!mounted) return;
    final loc = AppLocalizations.of(context);
    final ok = await showRoleQuickLoginSheet(
      context: context,
      accountingService: widget.accountingService,
      loc: loc,
      role: role,
      currentDisplayName: _appBarLoginDisplay,
      onLoginSuccess: _completeLoginAfterSuccess,
      onSignOut: () async {
        if (!await _confirmStaffLogout(context)) return;
        await _returnToGuestSession();
      },
      onOpenFullStaffLogin: _openStaffLoginFormFullscreen,
    );
    if (!mounted || !ok) return;
    setState(() {});
    await _refreshAppBarLoginDisplay();
  }

  /// يفتح مسار دخول فريق العمل (الموظفين). إذا كان هناك عضو مسجَّل دخوله
  /// أصلاً، نعرض له ملخّص حسابه مع خياري «تبديل الحساب» و«تسجيل الخروج»
  /// بدل إعادة عرض نموذج الدخول الفارغ. وإلا نفتح [LoginScreen] مباشرة.
  Future<void> _openStaffLoginScreen() async {
    if (!mounted) return;
    final svc = widget.accountingService;
    if (!svc.isGuestSession && svc.session != null) {
      if (VoucherSessionManager.instance.hasSession) {
        await _openMyAccountPage();
        return;
      }
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (pageCtx) => Theme(
            data: _buildScreenTheme(),
            child: MyAccountScreen(
              accountingService: widget.accountingService,
              onSignOut: () async {
                if (!await _confirmStaffLogout(pageCtx)) return;
                if (pageCtx.mounted) Navigator.of(pageCtx).pop();
                await _returnToGuestSession();
              },
              onSwitchAccount: () async {
                Navigator.of(pageCtx).pop();
                if (!mounted) return;
                await _openStaffLoginFormFullscreen();
              },
            ),
          ),
        ),
      );
      if (mounted) {
        await widget.accountingService.syncLicenseGate();
        setState(() {});
      }
      return;
    }
    await _openStaffLoginFormFullscreen();
  }

  /// يفتح نموذج تسجيل دخول فريق العمل ([LoginScreen]) فعلياً.
  /// مفصول كي يستعمله مسار «تبديل الحساب» في صفحة حسابي للموظف.
  Future<void> _openStaffLoginFormFullscreen() async {
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (ctx) => Theme(
          data: _buildScreenTheme(),
          child: LoginScreen(
            accountingService: widget.accountingService,
            rememberLoginUsername: _uiPrefs.rememberLoginUsername,
            lastRememberedEmail: _uiPrefs.lastRememberedUsername,
            onRememberChanged: (v) async {
              setState(() {
                _uiPrefs = _uiPrefs.copyWith(rememberLoginUsername: v);
              });
              await _saveStoreSettings();
            },
            onLoginSuccess: _completeLoginAfterSuccess,
          ),
        ),
      ),
    );
    if (mounted) {
      await widget.accountingService.syncLicenseGate();
      setState(() {});
    }
  }

  /// يفتح صفحة «حسابي» العصرية إذا توفّرت جلسة مشترك،
  /// وإلا يفتح مباشرة حوار تفعيل/تسجيل دخول القسيمة.
  Future<void> _openMyAccountPage() async {
    if (!mounted) return;
    final hasSession = VoucherSessionManager.instance.hasSession;
    if (!hasSession) {
      await _openSubscriptionActivationFlow();
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (pageCtx) => Theme(
          data: _buildScreenTheme(),
          child: SubscriberAccountScreen(
            allowSubscriberManagement: _canManageSubscriberAccount,
            onManageVoucher: () async {
              await _openSubscriptionActivationFlow();
            },
            onSignedOut: () async {
              // بعد تسجيل خروج المشترك نُعيد مزامنة الترخيص + الواجهة،
              // ليصبح زر «تفعيل الاشتراك» الأخضر برتقاليّاً مجدّداً
              // ويُفسح المجال لدخول فريق العمل من نفس القائمة.
              try {
                await widget.accountingService.syncLicenseGate();
              } catch (_) {/* تجاهل */}
              try {
                await VoucherSessionManager.instance.refreshStatus();
              } catch (_) {/* تجاهل */}
              if (mounted) setState(() {});
            },
          ),
        ),
      ),
    );
    if (!mounted) return;
    setState(() {});
  }

  String _activationDialogStatusText(AppLocalizations loc) {
    final svc = widget.accountingService;
    final gate = svc.licenseGate;
    final now = DateTime.now();
    if (svc.isGuestSession) return loc.activationDialogCoverageGuest;
    switch (gate.coverageKind(now)) {
      case LicenseCoverageKind.none:
        return loc.activationDialogCoverageNone;
      case LicenseCoverageKind.grandfather:
        return loc.activationDialogCoverageGrandfather;
      case LicenseCoverageKind.legacyActivated:
        return loc.activationDialogCoverageLegacy;
      case LicenseCoverageKind.pendingActivation:
        return loc.activationDialogCoveragePending;
      case LicenseCoverageKind.accessSuspended:
        return loc.activationDialogCoverageSuspended;
      case LicenseCoverageKind.annual:
        final end = gate.annualEndAt;
        if (end == null) return loc.activationDialogCoverageNone;
        final base = loc.activationDialogCoverageAnnual(_formatUiDate(end));
        final extra = _activationDaysCountLine(loc, gate, now);
        return extra != null ? '$base $extra' : base;
    }
  }

  String _activationDeviceSubtitle(AppLocalizations loc) {
    final gate = widget.accountingService.licenseGate;
    final now = DateTime.now();
    String withDays(String primary) {
      final extra = _activationDaysCountLine(loc, gate, now);
      if (extra == null || extra.isEmpty) return primary;
      return primary.isEmpty ? extra : '$primary · $extra';
    }

    switch (gate.coverageKind(now)) {
      case LicenseCoverageKind.grandfather:
        return loc.deviceSubtitleGrandfather;
      case LicenseCoverageKind.legacyActivated:
        return loc.deviceSubtitleLegacy;
      case LicenseCoverageKind.pendingActivation:
        return loc.deviceSubtitlePendingActivation;
      case LicenseCoverageKind.accessSuspended:
        return loc.activationFooterSuspended;
      case LicenseCoverageKind.annual:
        final end = gate.annualEndAt;
        if (end != null) {
          return withDays(
            loc.activationFooterAnnualUntil(_formatUiDate(end)),
          );
        }
        return loc.deviceSubtitleAnnualUnknown;
      case LicenseCoverageKind.none:
        return '';
    }
  }

  Widget _buildActivationFooterWidget(AppLocalizations loc) {
    // نُلَفّ الجسم كاملاً بـ ValueListenableBuilder كي يتحدّث الزر تلقائياً
    // فور نجاح تفعيل القسيمة (تغيير اللون/النص/الأيقونة بدون إعادة بناء يدوية).
    return ValueListenableBuilder<VoucherStatus>(
      valueListenable: VoucherSessionManager.instance.statusNotifier,
      builder: (_, __, ___) => _buildActivationFooterContent(loc),
    );
  }

  Widget _buildActivationFooterContent(AppLocalizations loc) {
    final svc = widget.accountingService;
    final gate = svc.licenseGate;
    final now = DateTime.now();
    final kind = gate.coverageKind(now);
    final daysDetail = _activationDaysCountLine(loc, gate, now);
    final voucherActive = _isVoucherActive;

    TextStyle? filledDetailStyle() => TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          height: 1.12,
          color: Colors.white.withValues(alpha: 0.93),
        );

    // 1) القسيمة مُفعَّلة على هذا الجهاز ⇒ زر أخضر «مُفعَّل بقسيمة» يفتح
    // حوار القسيمة لإدارة الاشتراك (تحرير الجهاز، إلخ).
    // يطبَّق حتى في وضع الزائر لكي يرى المشترك أن البرنامج فعلاً تفعّل.
    if (voucherActive) {
      return _buildVoucherActivatedFooterButton(loc);
    }

    // وضع الزائر بدون قسيمة: زر «تفعيل الاشتراك» فقط (بلا زر تعليمات بجانبه).
    if (svc.isGuestSession) {
      final showPriceHint = _activationFooterShowsPriceHint(
        voucherActive: voucherActive,
        isGuest: true,
        kind: kind,
      );
      final labelWidget = _buildActivationFooterButtonLabel(
        loc,
        primary: _activationFooterLabel(loc),
        daysDetail: daysDetail,
        showPriceHint: showPriceHint,
        detailStyle: filledDetailStyle(),
      );
      return Tooltip(
        message: loc.activationSubscriptionButtonTooltip,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: _activationFooterButtonColor(),
            foregroundColor: Colors.white,
          ),
          onPressed: _openSubscriptionActivationFlow,
          icon: const Icon(Icons.key_rounded),
          label: labelWidget,
        ),
      );
    }
    if (kind == LicenseCoverageKind.none ||
        kind == LicenseCoverageKind.pendingActivation ||
        kind == LicenseCoverageKind.accessSuspended) {
      final showPriceHint = _activationFooterShowsPriceHint(
        voucherActive: voucherActive,
        isGuest: false,
        kind: kind,
      );
      return Tooltip(
        message: loc.activationSubscriptionButtonTooltip,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: _activationFooterButtonColor(),
            foregroundColor: Colors.white,
          ),
          onPressed: _openSubscriptionActivationFlow,
          icon: const Icon(Icons.key_rounded),
          label: _buildActivationFooterButtonLabel(
            loc,
            primary: _activationFooterLabel(loc),
            daysDetail: daysDetail,
            showPriceHint: showPriceHint,
            detailStyle: filledDetailStyle(),
          ),
        ),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final holder = _subscriptionHolderLabel?.trim();
    final line = (holder != null && holder.isNotEmpty)
        ? '${loc.deviceActivatedBannerTitle} · $holder'
        : loc.deviceActivatedBannerTitle;

    // نفس عائلة أزرار الشريط السفلي (OutlinedButton مع التجربة والتاريخ).
    final outline = Colors.green.shade600;
    final fg = isDark ? Colors.green.shade200 : Colors.green.shade800;
    final bg = isDark
        ? Colors.green.shade900.withValues(alpha: 0.28)
        : Colors.green.shade50;

    final titleRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            line,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w800,
              fontSize: 14,
              letterSpacing: -0.2,
              height: 1.15,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Icon(
          Icons.celebration_rounded,
          size: 18,
          color: fg.withValues(alpha: 0.9),
        ),
      ],
    );

    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: fg,
        backgroundColor: bg,
        side: BorderSide(color: outline, width: 1.35),
      ),
      onPressed: _showActivationDialog,
      icon: Icon(Icons.verified_rounded, color: fg, size: 20),
      label: daysDetail == null
          ? titleRow
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                titleRow,
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    daysDetail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: fg.withValues(alpha: 0.92),
                      fontWeight: FontWeight.w700,
                      fontSize: 11.5,
                      height: 1.12,
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  /// زرّ بديل يظهر عندما يكون الجهاز مُفعَّلاً بقسيمة سارية.
  /// يبدّل لون «تفعيل الاشتراك» إلى أخضر، ويغيّر النص والأيقونة، ويفتح
  /// حوار القسيمة لإدارة الاشتراك.
  Widget _buildVoucherActivatedFooterButton(AppLocalizations loc) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final outline = Colors.green.shade600;
    final fg = isDark ? Colors.green.shade100 : Colors.green.shade900;
    final bg = isDark
        ? Colors.green.shade900.withValues(alpha: 0.32)
        : Colors.green.shade50;

    return Tooltip(
      message: loc.voucherActiveTitle,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          side: BorderSide(color: outline, width: 1.35),
          shadowColor: Colors.transparent,
        ),
        onPressed: _openSubscriptionActivationFlow,
        icon: Icon(Icons.verified_rounded, color: fg, size: 20),
        label: Text(
          loc.deviceActivatedBannerTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: fg,
            fontWeight: FontWeight.w800,
            fontSize: 14,
            letterSpacing: -0.2,
            height: 1.15,
          ),
        ),
      ),
    );
  }

  Color _activationDialogStatusColor() {
    final svc = widget.accountingService;
    final gate = svc.licenseGate;
    final now = DateTime.now();
    if (svc.isGuestSession) return Colors.blueGrey.shade700;
    switch (gate.coverageKind(now)) {
      case LicenseCoverageKind.none:
        return Colors.deepOrange.shade800;
      case LicenseCoverageKind.pendingActivation:
        return Colors.teal.shade700;
      case LicenseCoverageKind.accessSuspended:
        return Colors.red.shade800;
      case LicenseCoverageKind.annual:
      case LicenseCoverageKind.grandfather:
      case LicenseCoverageKind.legacyActivated:
        return Colors.green.shade700;
    }
  }

  // ignore: unused_element
  Widget _guestDialogTrialSection(
    AppLocalizations loc,
    ThemeData theme,
    ColorScheme cs,
    ({GuestDeviceTrialPhase phase, int daysRemaining}) snap,
  ) {
    final serverActivation = RemoteSignupConfig.activationServerEnabled;

    Widget phaseBanner(Color bg, Color fg, IconData icon, String text) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: fg.withValues(alpha: 0.35)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: fg, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    height: 1.45,
                    fontWeight: FontWeight.w700,
                    color: fg,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outline.withValues(alpha: 0.28)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline_rounded, color: cs.primary, size: 26),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    serverActivation
                        ? loc.guestModeAfterSignInNeedsActivationHeadline
                        : loc.guestModeGuestLimitedHeadline,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              serverActivation
                  ? loc.guestModeAfterSignInNeedsActivationBody
                  : loc.guestModeGuestLimitedBody,
              style: theme.textTheme.bodyMedium?.copyWith(
                height: 1.45,
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            snap.phase == GuestDeviceTrialPhase.grandfather
                ? phaseBanner(
                    Colors.deepPurple.withValues(alpha: 0.12),
                    Colors.deepPurple.shade800,
                    Icons.workspace_premium_rounded,
                    loc.guestModeTrialGrandfatherNote,
                  )
                : phaseBanner(
                    cs.secondaryContainer.withValues(alpha: 0.65),
                    cs.onSecondaryContainer,
                    Icons.login_rounded,
                    loc.guestModeSignInForRegisteredFeaturesNote,
                  ),
          ],
        ),
      ),
    );
  }

  // ignore: unused_element
  Future<void> _showGuestModeInstructionsDialog() async {
    if (!mounted) return;
    await widget.accountingService.licenseGate.reloadDeviceTrialState();
    if (!mounted) return;
    final snap = widget.accountingService.licenseGate
        .guestDeviceTrialSnapshot(DateTime.now());
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        final dlgLoc = AppLocalizations.of(dialogContext);
        final theme = Theme.of(dialogContext);
        final cs = theme.colorScheme;
        final mq = MediaQuery.sizeOf(dialogContext);
        final outerCtx = context;
        final limitsBody = dlgLoc.licenseFooterHintBody(
          true,
          remoteActivationServer: RemoteSignupConfig.activationServerEnabled,
        );
        return Dialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: SizedBox(
            width: math.min(520, mq.width - 40),
            height: math.min(720, mq.height * 0.92),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 4, 8),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor:
                            cs.primaryContainer.withValues(alpha: 0.95),
                        child: Icon(
                          Icons.person_outline_rounded,
                          color: cs.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          dlgLoc.guestModeGuideTitle,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: cs.outlineVariant),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _guestDialogTrialSection(dlgLoc, theme, cs, snap),
                        const SizedBox(height: 22),
                        Text(
                          limitsBody,
                          textAlign: TextAlign.start,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            height: 1.55,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 22),
                        FilledButton.icon(
                          icon: const Icon(Icons.key_rounded),
                          label: Text(dlgLoc.guestModeOpenActivate),
                          onPressed: () {
                            Navigator.pop(dialogContext);
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (!mounted) return;
                              unawaited(_openSubscriptionActivationFlow());
                            });
                          },
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.chat_rounded),
                          label: Text(dlgLoc.guestModeOpenWhatsApp),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.green.shade800,
                            side: BorderSide(color: Colors.green.shade600),
                          ),
                          onPressed: () {
                            Navigator.pop(dialogContext);
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (!mounted) return;
                              _launchSupportWhatsApp(outerCtx);
                            });
                          },
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.public_rounded),
                          label: Text(dlgLoc.guestModeOpenWebsite),
                          onPressed: () {
                            Navigator.pop(dialogContext);
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (!mounted) return;
                              _launchActivationOfficialSite(outerCtx);
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: Text(dlgLoc.close),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFooterLeadingLicenseWidget(AppLocalizations loc) {
    final svc = widget.accountingService;
    final gate = svc.licenseGate;
    final kind = gate.coverageKind(DateTime.now());
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (svc.isGuestSession) {
      // تعليمات وضع الزائر مدمجة مع زر «تفعيل الاشتراك» في الشريط السفلي.
      return const SizedBox.shrink();
    }
    // القسيمة السارية تُعرض في [_buildActivationFooterWidget] — لا نكرّر زر التفعيل.
    if (_isVoucherActive) {
      return const SizedBox.shrink();
    }
    // أعضاء فريق العمل (كاشير/محاسب/مدير/موزع) لا يديرون الترخيص؛
    // نُخفي شارة «ترخيص ترقية/سنوي» من واجهتهم لأنها معلومة خاصة بالمالك.
    if (svc.session?.role != 'owner') {
      return const SizedBox.shrink();
    }

    switch (kind) {
      case LicenseCoverageKind.grandfather:
      case LicenseCoverageKind.legacyActivated:
      case LicenseCoverageKind.annual:
        return _buildFooterLicensedRibbon(loc, kind, gate, isDark);
      case LicenseCoverageKind.pendingActivation:
        return Tooltip(
          message: loc.activationSubscriptionButtonTooltip,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.teal.shade800,
              side: BorderSide(color: Colors.teal.shade400),
            ),
            onPressed: _openSubscriptionActivationFlow,
            icon:
                Icon(Icons.hourglass_top_rounded, color: Colors.teal.shade800),
            label: _buildActivationFooterButtonLabel(
              loc,
              primary: loc.footerPendingActivationBadge,
              showPriceHint: true,
              detailStyle: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.teal.shade700,
              ),
            ),
          ),
        );
      case LicenseCoverageKind.accessSuspended:
        return Tooltip(
          message: loc.activationSubscriptionButtonTooltip,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red.shade900,
              side: BorderSide(color: Colors.red.shade400),
            ),
            onPressed: _openSubscriptionActivationFlow,
            icon: Icon(Icons.ac_unit_rounded, color: Colors.red.shade900),
            label: Text(loc.activationFooterSuspended),
          ),
        );
      case LicenseCoverageKind.none:
        return Tooltip(
          message: loc.activationSubscriptionButtonTooltip,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.deepOrange.shade800,
              side: BorderSide(color: Colors.deepOrange.shade400),
            ),
            onPressed: _openSubscriptionActivationFlow,
            icon: const Icon(Icons.key_rounded),
            label: _buildActivationFooterButtonLabel(
              loc,
              primary: loc.footerActivateSubscriptionBadge,
              showPriceHint: true,
              detailStyle: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.deepOrange.shade700,
              ),
            ),
          ),
        );
    }
  }

  Widget _buildFooterLicensedRibbon(
    AppLocalizations loc,
    LicenseCoverageKind kind,
    LicenseGate gate,
    bool isDark,
  ) {
    late final String title;
    late final IconData icon;
    switch (kind) {
      case LicenseCoverageKind.annual:
        title = loc.footerRibbonAnnual;
        icon = Icons.calendar_month_rounded;
        break;
      case LicenseCoverageKind.grandfather:
        title = loc.footerRibbonGrandfather;
        icon = Icons.workspace_premium_rounded;
        break;
      case LicenseCoverageKind.legacyActivated:
        title = loc.footerRibbonLegacy;
        icon = Icons.all_inclusive_rounded;
        break;
      default:
        title = loc.footerRibbonLegacy;
        icon = Icons.verified_rounded;
    }
    final end = gate.annualEndAt;
    final suffix = kind == LicenseCoverageKind.annual && end != null
        ? ' · ${_formatUiDate(end)}'
        : '';

    final fg = isDark ? Colors.green.shade200 : Colors.green.shade900;
    final border =
        Colors.green.shade500.withValues(alpha: isDark ? 0.65 : 0.85);
    final gradStart = isDark
        ? Colors.green.shade900.withValues(alpha: 0.42)
        : Colors.green.shade50;
    final gradEnd = isDark
        ? Colors.teal.shade900.withValues(alpha: 0.28)
        : Color.lerp(Colors.teal.shade50, Colors.green.shade50, 0.5)!;

    return Tooltip(
      message: loc.footerRibbonLicensedTooltip,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [gradStart, gradEnd],
          ),
          border: Border.all(color: border, width: 1.35),
          boxShadow: [
            BoxShadow(
              color: Colors.green.withValues(alpha: isDark ? 0.22 : 0.12),
              blurRadius: isDark ? 10 : 14,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 19, color: fg),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  '$title$suffix',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                    letterSpacing: -0.2,
                    color: fg,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomControlCell() {
    final loc = AppLocalizations.of(context);
    final dateText = _formatUiDate(_now);
    final timeText = _formatUiTime(_now);
    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(
            top: BorderSide(
                color: Theme.of(context).dividerColor.withValues(alpha: 0.35)),
          ),
        ),
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 10,
          runSpacing: 10,
          children: [
            if (_uiPrefs.showHomeFooterBeforeCalendar) ...[
              _buildFooterLeadingLicenseWidget(loc),
              _buildActivationFooterWidget(loc),
            ],
            Tooltip(
              message: loc.homeCalendarTooltip,
              child: OutlinedButton.icon(
                onPressed: () => showCalendarAppointmentsDialog(context),
                icon: const Icon(Icons.event_note_rounded),
                label: Text(dateText),
              ),
            ),
            if (_uiPrefs.showHomeFooterAfterCalendar) ...[
              Tooltip(
                message: loc.homeDateTimeNowTooltip,
                child: OutlinedButton.icon(
                  onPressed: () {
                    setState(() => _now = DateTime.now());
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(_formatUiDateTime(_now)),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                  icon: const Icon(Icons.access_time_outlined),
                  label: Text(timeText),
                ),
              ),
              Tooltip(
                message: loc.homeCurrencyConverterTooltip,
                child: OutlinedButton.icon(
                  onPressed: () => showCurrencyConverterDialog(
                    context,
                    storeCurrencyCode: _baseCurrencyCode,
                  ),
                  icon: const Icon(Icons.currency_exchange_rounded),
                  label: Text(loc.homeCurrencyConverterTitle),
                ),
              ),
              Tooltip(
                message: loc.homeQuickCalculatorTooltip,
                child: OutlinedButton.icon(
                  onPressed: () => showSimpleCalculatorDialog(context),
                  icon: const Icon(Icons.calculate_rounded),
                  label: Text(loc.homeQuickCalculatorTitle),
                ),
              ),
              Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  Tooltip(
                    message: loc.homeQuickNotesTooltip,
                    child: OutlinedButton.icon(
                      onPressed: _showQuickScratchpadDialog,
                      icon: const Icon(Icons.edit_note_rounded),
                      label: Text(loc.homeQuickNotesTitle),
                    ),
                  ),
                  if (_uiPrefs.quickScratchpadNotes.trim().isNotEmpty)
                    PositionedDirectional(
                      end: 6,
                      top: 6,
                      child: Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.tertiary,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Theme.of(context).colorScheme.surface,
                            width: 1.2,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _showSaleDialog() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => TransactionScreen(
          mode: TransactionMode.sale,
          accountingService: widget.accountingService,
          currencyCode: _baseCurrencyCode,
          currencyParts: _currencyParts,
          taxPercent: _taxPercent,
          uiPrefs: _uiPrefs,
          onPrintSaleInvoice: (id) =>
              _askPrintInvoice(invoiceId: id, type: 'sale'),
          onPrintPurchaseInvoice: (id) =>
              _askPrintInvoice(invoiceId: id, type: 'purchase'),
          onAfterInvoiceSaved: _loadDashboard,
          buildInvoicePdfBytesForPreview:
              ({
                required invoiceId,
                required isSale,
                required previewContext,
              }) =>
                  _buildInvoicePdfBytes(
            invoiceId: invoiceId,
            type: isSale ? 'sale' : 'purchase',
            l10nContext: previewContext,
          ),
        ),
      ),
    );
  }

  Future<void> _openSaleTransactionForInvoiceEdit(String invoiceId) async {
    if (!widget.accountingService.canModifyInvoices()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ليس لديك صلاحية تعديل أو حذف الفواتير.'),
        ),
      );
      return;
    }
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => TransactionScreen(
          mode: TransactionMode.sale,
          accountingService: widget.accountingService,
          currencyCode: _baseCurrencyCode,
          currencyParts: _currencyParts,
          taxPercent: _taxPercent,
          uiPrefs: _uiPrefs,
          openSaleInvoiceIdForEdit: invoiceId,
          onPrintSaleInvoice: (id) =>
              _askPrintInvoice(invoiceId: id, type: 'sale'),
          onPrintPurchaseInvoice: (id) =>
              _askPrintInvoice(invoiceId: id, type: 'purchase'),
          onAfterInvoiceSaved: _loadDashboard,
          buildInvoicePdfBytesForPreview:
              ({
                required invoiceId,
                required isSale,
                required previewContext,
              }) =>
                  _buildInvoicePdfBytes(
            invoiceId: invoiceId,
            type: isSale ? 'sale' : 'purchase',
            l10nContext: previewContext,
          ),
        ),
      ),
    );
  }

  Future<void> _showPurchaseDialog() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => TransactionScreen(
          mode: TransactionMode.purchase,
          accountingService: widget.accountingService,
          currencyCode: _baseCurrencyCode,
          currencyParts: _currencyParts,
          taxPercent: _taxPercent,
          uiPrefs: _uiPrefs,
          onPrintSaleInvoice: (id) =>
              _askPrintInvoice(invoiceId: id, type: 'sale'),
          onPrintPurchaseInvoice: (id) =>
              _askPrintInvoice(invoiceId: id, type: 'purchase'),
          onAfterInvoiceSaved: _loadDashboard,
          buildInvoicePdfBytesForPreview:
              ({
                required invoiceId,
                required isSale,
                required previewContext,
              }) =>
                  _buildInvoicePdfBytes(
            invoiceId: invoiceId,
            type: isSale ? 'sale' : 'purchase',
            l10nContext: previewContext,
          ),
        ),
      ),
    );
  }

  Future<void> _showReportsDialog() async {
    if (!widget.accountingService.canViewFinancialReports()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                AppLocalizations.of(context).noFinancialReportsPermission)),
      );
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ClassicReportsScreen(
          accountingService: widget.accountingService,
        ),
      ),
    );
  }

  String _formatCellValue(Object? value) {
    if (value == null) return '-';
    if (value is DateTime) {
      return _formatUiDateTime(value);
    }
    if (value is num) {
      return value is int
          ? _numberFormat.format(value)
          : _decimalFormat.format(value);
    }
    if (value is String) {
      final normalized = value.trim();
      final parsedDate = DateTime.tryParse(normalized);
      if (parsedDate != null) {
        final hasTime = normalized.contains('T') || normalized.contains(' ');
        return hasTime
            ? _formatUiDateTime(parsedDate)
            : _formatUiDate(parsedDate);
      }
      final parsedNumber = num.tryParse(normalized);
      if (parsedNumber != null) {
        return parsedNumber is int
            ? _numberFormat.format(parsedNumber)
            : _decimalFormat.format(parsedNumber);
      }
      return normalized;
    }
    return value.toString();
  }

  /// حوار لطيف يُعرَض عند محاولة فتح إعدادات المتجر دون حساب مدير.
  Future<void> _showSettingsManagerOnlyDialog() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final loc = AppLocalizations.of(dialogContext);
        final cs = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          icon: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cs.errorContainer.withValues(alpha: 0.55),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.admin_panel_settings_outlined,
              color: cs.onErrorContainer,
              size: 28,
            ),
          ),
          title: Text(
            loc.settingsManagerOnlyTitle,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          content: Text(
            loc.settingsManagerOnlyBody,
            textAlign: TextAlign.center,
            style: const TextStyle(height: 1.5),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(loc.close),
            ),
          ],
        );
      },
    );
  }

  /// حوار لطيف يُعرَض عند محاولة فتح ميزة محجوزة للأجهزة المُفعَّلة.
  Future<void> _showActivationRequiredDialog() async {
    if (!mounted) return;
    final shouldActivate = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final loc = AppLocalizations.of(dialogContext);
        final cs = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          icon: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.lock_outline_rounded,
                color: cs.onPrimaryContainer, size: 28),
          ),
          title: Text(
            loc.featureRequiresActivationTitle,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          content: Text(
            loc.featureRequiresActivationBody,
            textAlign: TextAlign.center,
            style: const TextStyle(height: 1.5),
          ),
          actionsAlignment: MainAxisAlignment.spaceBetween,
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(loc.close),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              icon: const Icon(Icons.key_rounded),
              label: Text(loc.featureRequiresActivationCta),
            ),
          ],
        );
      },
    );
    if (shouldActivate == true && mounted) {
      await _openSubscriptionActivationFlow();
    }
  }

  /// مدخل موحّد «الموظفين»: دخول موظف أو إدارة الحسابات (بدون عنصرين متجاورين في القائمة).
  Future<void> _openEmployeesHub() async {
    if (!mounted) return;
    final svc = widget.accountingService;
    final loc = AppLocalizations.of(context);

    if (!svc.isGuestSession && svc.session != null) {
      if (svc.canManageUsers()) {
        await _openUsersSecurityScreen();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loc.usersNoPermission)),
        );
      }
      return;
    }

    if (svc.isGuestSession && !_adminLicenseOrVoucherUnlocked) {
      await _openStaffLoginScreen();
      return;
    }

    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) {
        final theme = Theme.of(sheetCtx);
        final scheme = theme.colorScheme;
        final en = loc.isEnglish;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  loc.menuUsers,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  loc.employeesHubSubtitle,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 18),
                Material(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(14),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      ListTile(
                        leading: CircleAvatar(
                          backgroundColor:
                              scheme.primary.withValues(alpha: 0.12),
                          child: Icon(Icons.login_rounded, color: scheme.primary),
                        ),
                        title: Text(
                          loc.menuEmployeesSignIn,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(loc.menuStaffLoginSubtitle),
                        trailing: Icon(
                          en
                              ? Icons.chevron_right_rounded
                              : Icons.chevron_left_rounded,
                        ),
                        onTap: () => Navigator.pop(sheetCtx, 'signin'),
                      ),
                      Divider(
                        height: 1,
                        color: scheme.outlineVariant.withValues(alpha: 0.5),
                      ),
                      ListTile(
                        leading: CircleAvatar(
                          backgroundColor:
                              scheme.tertiary.withValues(alpha: 0.12),
                          child:
                              Icon(Icons.groups_rounded, color: scheme.tertiary),
                        ),
                        title: Text(
                          loc.menuEmployeesManage,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(loc.usersTeamScreenSubtitle),
                        trailing: Icon(
                          en
                              ? Icons.chevron_right_rounded
                              : Icons.chevron_left_rounded,
                        ),
                        onTap: () => Navigator.pop(sheetCtx, 'manage'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted || choice == null) return;
    if (choice == 'signin') {
      await _openStaffLoginScreen();
    } else if (choice == 'manage') {
      await _openUsersSecurityScreen();
    }
  }

  Future<void> _openUsersSecurityScreen() async {
    // عند تفعيل القسيمة، يُعتبر صاحب الجلسة هو مالك الاشتراك وله صلاحيات
    // إدارة الموظفين دون الحاجة لفحص دور النظام القديم.
    if (!_adminLicenseOrVoucherUnlocked &&
        !widget.accountingService.canManageUsers()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).usersNoPermission)),
      );
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => UsersSecurityScreen(
          accountingService: widget.accountingService,
          initialUiPrefs: _uiPrefs,
          onUiPrefsSaved: (next) async {
            setState(() => _uiPrefs = next);
            await _saveStoreSettings();
          },
          persistStoreSettings: _saveStoreSettings,
          onOpenStoreSettings: () async {
            await _showAdminSettingsDialog();
          },
        ),
      ),
    );
  }

  Future<void> _showAuditDialog() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AuditLogFilterDialog(
        accountingService: widget.accountingService,
      ),
    );
  }

  String _resolveBackupFilePath(String stamp) {
    if (kIsAndroidApp) {
      return BackupDestination.defaultBackupFilePath(stamp);
    }
    final folder = _uiPrefs.backupFolderPath.trim();
    if (folder.isNotEmpty) {
      return p.join(folder, 'backup_$stamp.json');
    }
    final drive = StoreUiPreferences.sanitizeDriveLetter(
      _uiPrefs.backupDriveLetter,
    );
    return '$drive:${Platform.pathSeparator}backup_$stamp.json';
  }

  Future<void> _offerShareBackupFile(String savedPath) async {
    final file = File(savedPath);
    if (!await file.exists()) return;
    final loc = AppLocalizations.of(context);
    final share = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final l = AppLocalizations.of(ctx);
        return AlertDialog(
          title: Text(l.backupSavedTitle),
          content: Text(l.backupSavedBody(savedPath)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.close),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.share_rounded),
              label: Text(l.backupDestinationExport),
            ),
          ],
        );
      },
    );
    if (share != true || !mounted) return;
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(savedPath)],
        text: loc.backupSavedTitle,
      ),
    );
  }

  /// نسخة يدوية: اختيار الحفظ على الجهاز (مربع حفظ) أو مجلد Google Drive المزامن.
  /// يُرجع [true] عند إنشاء النسخة بنجاح.
  Future<bool> _interactiveBackup() async {
    if (!_adminLicenseOrVoucherUnlocked) {
      await _showActivationRequiredDialog();
      return false;
    }
    final loc = AppLocalizations.of(context);
    final stamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());

    if (kIsAndroidApp) {
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) {
          final l = AppLocalizations.of(ctx);
          return AlertDialog(
            title: Text(l.backupDestinationTitle),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.save_rounded),
                  title: Text(l.backupDestinationAppFolder),
                  subtitle: Text(
                    l.backupDestinationAppFolderSub,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                  onTap: () => Navigator.pop(ctx, 'app'),
                ),
                ListTile(
                  leading: const Icon(Icons.ios_share_rounded),
                  title: Text(l.backupDestinationExport),
                  subtitle: Text(
                    l.backupDestinationExportSub,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                  onTap: () => Navigator.pop(ctx, 'export'),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(l.cancel),
              ),
            ],
          );
        },
      );
      if (choice == null || !mounted) return false;
      try {
        if (choice == 'app') {
          final path = _resolveBackupFilePath(stamp);
          final saved =
              await widget.accountingService.backupToJson(filePath: path);
          if (!mounted) return false;
          await _offerShareBackupFile(saved);
          return true;
        }
        if (choice == 'export') {
          final path = await BackupDestination.pickSavePath(stamp);
          if (path == null || !mounted) return false;
          final saved =
              await widget.accountingService.backupToJson(filePath: path);
          if (!mounted) return false;
          _showSuccess(loc.backupCreatedSnack(saved));
          return true;
        }
      } on Object catch (e) {
        if (!mounted) return false;
        _showError(_friendlyError(e));
      }
      return false;
    }

    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final l = AppLocalizations.of(ctx);
        return AlertDialog(
          title: Text(l.backupDestinationTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.folder_rounded),
                title: Text(l.backupDestinationLocal),
                subtitle: Text(
                  l.backupDestinationLocalSub,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
                onTap: () => Navigator.pop(ctx, 'local'),
              ),
              ListTile(
                leading: const Icon(Icons.cloud_upload_rounded),
                title: Text(l.backupDestinationGoogleDrive),
                subtitle: Text(
                  l.backupDestinationGoogleDriveSub,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
                onTap: () => Navigator.pop(ctx, 'gdrive'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l.cancel),
            ),
          ],
        );
      },
    );

    if (choice == null || !mounted) return false;

    try {
      if (choice == 'local') {
        final path = await BackupDestination.pickSavePath(stamp);
        if (path == null || !mounted) return false;
        final saved =
            await widget.accountingService.backupToJson(filePath: path);
        if (!mounted) return false;
        _showSuccess(loc.backupCreatedSnack(saved));
        return true;
      }
      if (choice == 'gdrive') {
        final folder = BackupDestination.googleDriveMyDriveFolder();
        if (folder != null) {
          final filePath = p.join(folder, 'mizapos_backup_$stamp.json');
          final saved = await widget.accountingService.backupToJson(
            filePath: filePath,
          );
          if (!mounted) return false;
          _showSuccess(loc.backupCreatedSnack(saved));
          return true;
        }
        if (!mounted) return false;
        return await _showGoogleDriveNotFoundDialog(stamp);
      }
    } on Object catch (e) {
      if (!mounted) return false;
      _showError(_friendlyError(e));
    }
    return false;
  }

  Future<bool> _showGoogleDriveNotFoundDialog(String stamp) async {
    var savedOk = false;
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        final l = AppLocalizations.of(ctx);
        return AlertDialog(
          title: Text(l.backupGoogleDriveNotFoundTitle),
          content: SingleChildScrollView(
            child: Text(l.backupGoogleDriveNotFoundBody),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l.close),
            ),
            TextButton(
              onPressed: () async {
                final uri =
                    Uri.parse('https://drive.google.com/drive/my-drive');
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
              child: Text(l.backupOpenDriveWeb),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(ctx);
                final path = await BackupDestination.pickSavePath(stamp);
                if (path == null || !mounted) return;
                try {
                  final saved = await widget.accountingService.backupToJson(
                    filePath: path,
                  );
                  if (!mounted) return;
                  savedOk = true;
                  _showSuccess(
                    AppLocalizations.of(context).backupCreatedSnack(saved),
                  );
                } on Object catch (e) {
                  if (!mounted) return;
                  _showError(_friendlyError(e));
                }
              },
              child: Text(l.backupPickFolderSave),
            ),
          ],
        );
      },
    );
    return savedOk;
  }

  Future<void> _maybeBackupReminder() async {
    if (!mounted ||
        _backupReminderShownSession ||
        widget.accountingService.isGuestSession) {
      return;
    }
    if (!widget.accountingService.canManageUsers()) return;
    final days = _uiPrefs.backupReminderDays;
    if (days <= 0) return;
    DateTime? last;
    try {
      last = await widget.accountingService.lastBackupAuditTime();
    } on Object {
      return;
    }
    final now = DateTime.now();
    if (last != null && now.difference(last).inDays < days) return;
    _backupReminderShownSession = true;
    if (!mounted) return;
    final loc = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(loc.backupReminderSnack(days)),
        action: SnackBarAction(
          label: loc.menuBackup,
          onPressed: () => unawaited(_interactiveBackup()),
        ),
      ),
    );
  }

  double _calculatePercentChange(double previous, double current) {
    if (previous == 0) {
      if (current == 0) return 0;
      return 100;
    }
    return ((current - previous) / previous) * 100;
  }

  Future<pw.MemoryImage?> _loadPdfMemoryImage(String? path) async {
    final trimmed = path?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    try {
      final file = File(trimmed);
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return null;
      return pw.MemoryImage(bytes);
    } catch (_) {
      return null;
    }
  }

  List<pw.Widget> _invoicePdfTaxIdentityWidgets(
    pw.Font arabicFontRegular,
    pw.Font arabicFontBold,
    AppLocalizations loc,
  ) {
    final rows = <String>[];
    final nif = _uiPrefs.taxIdNif.trim();
    final rc = _uiPrefs.commercialRc.trim();
    final ai = _uiPrefs.articleAi.trim();
    final nis = _uiPrefs.statisticalNis.trim();
    if (nif.isNotEmpty) rows.add(loc.pdfTaxLine(loc.taxNifLbl, nif));
    if (rc.isNotEmpty) rows.add(loc.pdfTaxLine(loc.taxRcLbl, rc));
    if (ai.isNotEmpty) rows.add(loc.pdfTaxLine(loc.taxAiLbl, ai));
    if (nis.isNotEmpty) rows.add(loc.pdfTaxLine(loc.taxNisLbl, nis));
    if (rows.isEmpty) return [];
    return [
      pw.SizedBox(height: 10),
      pw.Text(
        loc.pdfTaxIdentitySection,
        style: pw.TextStyle(
          fontSize: 11,
          fontWeight: pw.FontWeight.bold,
          font: arabicFontBold,
        ),
      ),
      pw.SizedBox(height: 4),
      ...rows.map(
        (s) => pw.Text(
          s,
          style: pw.TextStyle(
            font: arabicFontRegular,
            fontSize: 9,
            color: PdfColors.grey800,
          ),
        ),
      ),
    ];
  }

  Future<void> _askPrintInvoice(
      {required String invoiceId, required String type}) async {
    if (!mounted) return;
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        final loc = AppLocalizations.of(dialogContext);
        return AlertDialog(
          shape: UiStyleTokens.dialogShape,
          title: Text(loc.printInvoiceTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(loc.printInvoiceQuestion),
              const SizedBox(height: 8),
              Text(
                loc.printInvoiceChooseAction,
                style: Theme.of(dialogContext).textTheme.bodySmall?.copyWith(
                      color:
                          Theme.of(dialogContext).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                icon: const Icon(Icons.print_rounded),
                label: Text(loc.printButton),
                onPressed: () => Navigator.pop(dialogContext, 'print'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.visibility_rounded),
                label: Text(loc.printInvoicePreviewButton),
                onPressed: () => Navigator.pop(dialogContext, 'preview'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, 'later'),
                child: Text(loc.laterButton),
              ),
            ],
          ),
        );
      },
    );
    if (!mounted) return;
    if (choice == null || choice == 'later') return;
    if (choice == 'preview') {
      await _openInvoicePdfPreview(invoiceId: invoiceId, type: type);
      return;
    }
    if (choice == 'print') {
      await _printInvoice(invoiceId: invoiceId, type: type);
    }
  }

  Future<void> _openInvoicePdfPreview({
    required String invoiceId,
    required String type,
  }) async {
    final bytes = await _buildInvoicePdfBytes(invoiceId: invoiceId, type: type);
    if (bytes == null || !mounted) return;
    final loc = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final mq = MediaQuery.sizeOf(context);
    final dialogW = (mq.width * 0.38).clamp(320.0, 420.0);
    final dialogH = (mq.height * 0.62).clamp(420.0, 620.0);
    final shortId = invoiceId.substring(0, 8);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return Dialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          shape: UiStyleTokens.dialogShape,
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: dialogW,
            height: dialogH,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Material(
                  color: cs.surfaceContainerHighest,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Row(
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsetsDirectional.only(
                                start: 12, end: 4),
                            child: Text(
                              loc.invoicePreviewAppBarTitle,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: MaterialLocalizations.of(dialogContext)
                              .closeButtonTooltip,
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.of(dialogContext).pop(),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: PdfPreview.builder(
                    build: (_) async => bytes,
                    padding: EdgeInsets.zero,
                    maxPageWidth: null,
                    scrollViewDecoration:
                        const BoxDecoration(color: Colors.transparent),
                    previewPageMargin: EdgeInsets.zero,
                    canChangePageFormat: false,
                    canChangeOrientation: false,
                    canDebug: false,
                    allowPrinting: true,
                    allowSharing: false,
                    pdfFileName: 'invoice_$shortId.pdf',
                    actionBarTheme: PdfActionBarTheme(
                      height: 40,
                      elevation: 0,
                      backgroundColor: cs.primaryContainer,
                      iconColor: cs.onPrimaryContainer,
                    ),
                    pagesBuilder: InvoicePdfFittedPages.builder,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _pdfInvoiceDisplayNumber(Map<String, Object?> invoice) =>
      AccountingService.displayInvoiceNumberFromRow(invoice);

  Future<Uint8List?> _buildInvoicePdfBytes({
    required String invoiceId,
    required String type,
    BuildContext? l10nContext,
  }) async {
    final l10nCtx = l10nContext ?? context;
    final data = await widget.accountingService
        .invoiceForPrint(invoiceId: invoiceId, type: type);
    final invoice = data['invoice'] as Map<String, Object?>;
    final isQuote = type == 'sale' &&
        AccountingService.invoiceRowIsPriceQuote(invoice);
    final items = (data['items'] as List).cast<Map<String, Object?>>();
    final partnerNameRaw = data['partnerName'] as String?;
    final arabicFont = await ReportExportHelper.pdfExportFontRegular();
    final arabicFontBold = await ReportExportHelper.pdfExportFontBold();

    if (!mounted && l10nContext == null) return null;
    final loc = AppLocalizations.of(l10nCtx);

    final logoImg = await _loadPdfMemoryImage(_resolvedLogoPath);
    final stampImg = await _loadPdfMemoryImage(_uiPrefs.stampSignaturePath);

    final doc = pw.Document();
    final invoiceNumber = ReportExportHelper.stripPdfInvisibleChars(
      _pdfInvoiceDisplayNumber(invoice),
    );
    final rawInvDate = invoice['invoiceDate'];
    DateTime? invDt;
    var invDateHasTime = false;
    if (rawInvDate is DateTime) {
      invDt = rawInvDate;
      invDateHasTime = true;
    } else if (rawInvDate is String) {
      final s = rawInvDate.trim();
      invDt = DateTime.tryParse(s);
      invDateHasTime = s.contains('T') || RegExp(r'\s\d{1,2}:').hasMatch(s);
    }
    final arMeridiem = Localizations.localeOf(l10nCtx).languageCode == 'ar';
    final String dateForPdf;
    if (invDt != null) {
      dateForPdf = invDateHasTime
          ? UiDateTimeFormat.formatCalendarDateTimeForPdf(
              invDt,
              arabicMeridiem: arMeridiem,
            )
          : UiDateTimeFormat.formatCalendarDateForPdf(invDt);
    } else {
      dateForPdf = _formatCellValue(rawInvDate);
    }
    final date = ReportExportHelper.pdfText(dateForPdf);
    final totalsFormat = (invoice['totalsFormat'] as num?)?.toInt() ?? 0;
    final lineSubtotalDb = (invoice['lineSubtotal'] as num?)?.toDouble();
    final discountDb = (invoice['discountAmount'] as num?)?.toDouble() ?? 0;
    final taxPercentDb = (invoice['taxPercent'] as num?)?.toDouble() ?? 0;
    final totalStored = (invoice['total'] as num).toDouble();
    final invNotes = (invoice['notes'] as String?)?.trim();
    final rate = _taxPercent;

    late final double displaySubtotal;
    late final double displayDiscount;
    late final double displayTax;
    late final double displayGrand;
    late final double effectiveTaxRateForFootnote;

    if (totalsFormat == 1 && lineSubtotalDb != null && lineSubtotalDb > 0) {
      displaySubtotal = lineSubtotalDb;
      displayDiscount = discountDb.clamp(0, lineSubtotalDb);
      final net =
          (displaySubtotal - displayDiscount).clamp(0.0, double.infinity);
      displayTax = net * (taxPercentDb / 100.0);
      displayGrand = totalStored;
      effectiveTaxRateForFootnote = taxPercentDb;
    } else {
      displaySubtotal = totalStored;
      displayDiscount = 0;
      effectiveTaxRateForFootnote = rate;
      displayTax = rate > 0 ? displaySubtotal * rate / 100.0 : 0.0;
      displayGrand = displaySubtotal + displayTax;
    }

    final amountWords = MoneyAmountWords.format(
      displayGrand,
      arabic: Localizations.localeOf(l10nCtx).languageCode == 'ar',
      currencyLabel: _baseCurrencyCode,
    );

    final storeMetaLines = <String>[
      if (_storeCountry.trim().isNotEmpty)
        loc.pdfStoreCountry(_storeCountry.trim()),
      if (_storeAddress.trim().isNotEmpty)
        loc.pdfStoreAddress(_storeAddress.trim()),
      if (_storePhone.trim().isNotEmpty) loc.pdfStorePhone(_storePhone.trim()),
      if (_storePhoneAlt.trim().isNotEmpty)
        loc.pdfStorePhoneAlt(_storePhoneAlt.trim()),
    ];

    final partnerLine = loc.pdfInvoicePartnerLine(
      isSale: type == 'sale',
      partnerName: partnerNameRaw,
    );
    final payRaw = (invoice['paymentType'] ?? '').toString();
    final paymentSplits = AccountingService.paymentSplitsFromPrintPayload(
      data['paymentSplits'],
    );
    final hasSplitDetails = AccountingService.invoiceHasSplitPaymentDetails(
      paymentTypeRaw: payRaw,
      splits: paymentSplits,
    );
    final payLine = isQuote
        ? loc.pdfPriceQuoteDisclaimer
        : '${loc.txInvoicePaymentMethodField}: ${loc.invoicePaymentMethodLabel(payRaw)}';
    final thermalTotals = <({String label, String value, bool emphasize})>[
      (
        label: loc.pdfInvoiceReceiptLinesSum,
        value: _moneyFormat.format(displaySubtotal),
        emphasize: false,
      ),
    ];
    if (displayDiscount > 1e-9) {
      thermalTotals.add((
        label: loc.txInvoiceDiscountFieldLabel,
        value: _moneyFormat.format(displayDiscount),
        emphasize: false,
      ));
    }
    if (effectiveTaxRateForFootnote > 1e-9 && displayTax > 1e-9) {
      thermalTotals.add((
        label: loc.pdfInvoiceReceiptTaxLabel(
          effectiveTaxRateForFootnote.toStringAsFixed(2),
        ),
        value: _moneyFormat.format(displayTax),
        emphasize: false,
      ));
    }
    thermalTotals.add((
      label: loc.pdfInvoiceReceiptNet,
      value: _moneyFormat.format(displayGrand),
      emphasize: true,
    ));
    final displayPaid = AccountingService.invoicePaidAmountForDisplay(
      invoice,
      grandTotal: displayGrand,
    );
    final displayRemaining = AccountingService.invoiceRemainingForDisplay(
      grandTotal: displayGrand,
      paid: displayPaid,
    );
    final displayChange = AccountingService.invoiceChangeToCustomerForDisplay(
      grandTotal: displayGrand,
      paid: displayPaid,
    );
    thermalTotals.add((
      label: loc.txInvoicePaidFieldLabel,
      value: _moneyFormat.format(displayPaid),
      emphasize: false,
    ));
    if (hasSplitDetails) {
      final paidIdx = thermalTotals.length - 1;
      final splitRows = <({String label, String value, bool emphasize})>[
        (
          label: loc.pdfSplitPaymentDetails,
          value: '',
          emphasize: true,
        ),
        for (final s in paymentSplits)
          (
            label: loc.invoicePaymentMethodLabel(s.paymentType),
            value: _moneyFormat.format(s.amount),
            emphasize: false,
          ),
      ];
      final allocated =
          AccountingService.totalAllocatedFromSplits(paymentSplits);
      final splitRemaining =
          (displayGrand - allocated).clamp(0.0, double.infinity);
      if (splitRemaining > 1e-6) {
        splitRows.add((
          label: loc.txInvoiceRemainingFieldLabel,
          value: _moneyFormat.format(splitRemaining),
          emphasize: true,
        ));
      }
      thermalTotals.insertAll(paidIdx, splitRows);
    }
    if (displayChange > 1e-6) {
      thermalTotals.add((
        label: loc.txInvoiceChangeToCustomerLabel,
        value: _moneyFormat.format(displayChange),
        emphasize: true,
      ));
    } else {
      thermalTotals.add((
        label: loc.txInvoiceRemainingFieldLabel,
        value: _moneyFormat.format(displayRemaining),
        emphasize: displayRemaining > 1e-6,
      ));
    }

    final pdfDir = loc.rtlLayout ? pw.TextDirection.rtl : pw.TextDirection.ltr;

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 36, vertical: 40),
        maxPages: 80,
        theme: pw.ThemeData.withFont(base: arabicFont, bold: arabicFontBold),
        textDirection: pdfDir,
        build: (ctx) => [
          pw.Directionality(
            textDirection: pdfDir,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                pw.Container(height: 4, color: PdfMizaDocumentTheme.accent),
                pw.SizedBox(height: 14),
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            ReportExportHelper.stripPdfInvisibleChars(
                                _storeName),
                            style: pw.TextStyle(
                              fontSize: 20,
                              fontWeight: pw.FontWeight.bold,
                              font: arabicFontBold,
                              color: PdfMizaDocumentTheme.primary,
                            ),
                          ),
                          if (storeMetaLines.isNotEmpty) pw.SizedBox(height: 6),
                          ...storeMetaLines.map(
                            (line) => pw.Text(
                              ReportExportHelper.stripPdfInvisibleChars(line),
                              style: pw.TextStyle(
                                font: arabicFont,
                                fontSize: 9.5,
                                color: PdfColors.grey700,
                                height: 1.25,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (logoImg != null)
                      pw.Padding(
                        padding: const pw.EdgeInsets.only(right: 8),
                        child: pw.Image(logoImg,
                            width: 76, fit: pw.BoxFit.contain),
                      ),
                  ],
                ),
                ..._invoicePdfTaxIdentityWidgets(
                    arabicFont, arabicFontBold, loc),
                pw.SizedBox(height: 16),
                pw.Container(
                  padding: const pw.EdgeInsets.only(bottom: 8),
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(
                      bottom: pw.BorderSide(color: PdfMizaDocumentTheme.accent, width: 2.5),
                    ),
                  ),
                  child: pw.Text(
                    isQuote
                        ? loc.pdfInvoicePriceQuote
                        : (type == 'sale'
                            ? loc.pdfInvoiceSale
                            : loc.pdfInvoicePurchase),
                    style: pw.TextStyle(
                      fontSize: 22,
                      fontWeight: pw.FontWeight.bold,
                      font: arabicFontBold,
                      color: PdfMizaDocumentTheme.primary,
                    ),
                  ),
                ),
                pw.SizedBox(height: 12),
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Expanded(
                      child: pw.Container(
                        padding: const pw.EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        decoration: pw.BoxDecoration(
                          color: PdfColors.grey100,
                          borderRadius: pw.BorderRadius.circular(6),
                        ),
                        child: pw.Text(
                          ReportExportHelper.stripPdfInvisibleChars(
                              loc.pdfInvoiceNumber(invoiceNumber)),
                          style: pw.TextStyle(
                            font: arabicFont,
                            fontSize: 9.5,
                            color: PdfColors.grey900,
                          ),
                        ),
                      ),
                    ),
                    pw.SizedBox(width: 10),
                    pw.Expanded(
                      child: pw.Container(
                        padding: const pw.EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        decoration: pw.BoxDecoration(
                          color: PdfColors.grey100,
                          borderRadius: pw.BorderRadius.circular(6),
                        ),
                        child: pw.Text(
                          ReportExportHelper.pdfText(
                              loc.pdfInvoiceDate(date)),
                          style: pw.TextStyle(
                            font: arabicFont,
                            fontSize: 9.5,
                            color: PdfColors.grey900,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 10),
                pw.Align(
                  alignment: pw.Alignment.centerLeft,
                  child: pw.Text(
                    ReportExportHelper.stripPdfInvisibleChars(partnerLine),
                    style: pw.TextStyle(
                      font: arabicFont,
                      fontSize: 10,
                      color: PdfColors.grey900,
                      height: 1.25,
                    ),
                  ),
                ),
                pw.SizedBox(height: 4),
                if (hasSplitDetails) ...[
                  pw.Align(
                    alignment: pw.Alignment.centerLeft,
                    child: pw.Text(
                      ReportExportHelper.stripPdfInvisibleChars(payLine),
                      style: pw.TextStyle(
                        font: arabicFont,
                        fontSize: 10,
                        color: PdfColors.grey800,
                        height: 1.25,
                      ),
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Align(
                    alignment: pw.Alignment.centerLeft,
                    child: pw.Text(
                      ReportExportHelper.stripPdfInvisibleChars(
                        loc.pdfSplitPaymentDetails,
                      ),
                      style: pw.TextStyle(
                        font: arabicFontBold,
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.grey900,
                        height: 1.25,
                      ),
                    ),
                  ),
                  for (final s in paymentSplits) ...[
                    pw.SizedBox(height: 2),
                    pw.Align(
                      alignment: pw.Alignment.centerLeft,
                      child: pw.Text(
                        ReportExportHelper.stripPdfInvisibleChars(
                          loc.pdfSplitPaymentLine(
                            loc.invoicePaymentMethodLabel(s.paymentType),
                            _moneyFormat.format(s.amount),
                          ),
                        ),
                        style: pw.TextStyle(
                          font: arabicFont,
                          fontSize: 9.5,
                          color: PdfColors.grey800,
                          height: 1.25,
                        ),
                      ),
                    ),
                  ],
                  if ((displayGrand -
                              AccountingService.totalAllocatedFromSplits(
                                paymentSplits,
                              ))
                          .clamp(0.0, double.infinity) >
                      1e-6) ...[
                    pw.SizedBox(height: 2),
                    pw.Align(
                      alignment: pw.Alignment.centerLeft,
                      child: pw.Text(
                        ReportExportHelper.stripPdfInvisibleChars(
                          loc.pdfSplitPaymentLine(
                            loc.txInvoiceRemainingFieldLabel,
                            _moneyFormat.format(
                              (displayGrand -
                                      AccountingService
                                          .totalAllocatedFromSplits(
                                        paymentSplits,
                                      ))
                                  .clamp(0.0, double.infinity),
                            ),
                          ),
                        ),
                        style: pw.TextStyle(
                          font: arabicFont,
                          fontSize: 9.5,
                          color: PdfColors.grey800,
                          height: 1.25,
                        ),
                      ),
                    ),
                  ],
                ] else
                  pw.Align(
                    alignment: pw.Alignment.centerLeft,
                    child: pw.Text(
                      ReportExportHelper.stripPdfInvisibleChars(payLine),
                      style: pw.TextStyle(
                        font: arabicFont,
                        fontSize: 10,
                        color: PdfColors.grey800,
                        height: 1.25,
                      ),
                    ),
                  ),
                if (invNotes != null && invNotes.isNotEmpty) ...[
                  pw.SizedBox(height: 10),
                  pw.Text(
                    ReportExportHelper.stripPdfInvisibleChars(
                        '${loc.rtlLayout ? 'ملاحظات' : 'Notes'}: $invNotes'),
                    style: pw.TextStyle(
                      font: arabicFont,
                      fontSize: 9.5,
                      color: PdfColors.grey800,
                      height: 1.3,
                    ),
                  ),
                ],
                pw.SizedBox(height: 14),
                ReportExportHelper.buildPdfDataTable(
                  headers: loc.pdfInvoiceTableHeaders,
                  data: items
                      .map((e) => [
                            (e['productName'] ?? '-').toString(),
                            _formatCellValue(e['quantity']),
                            _formatCellValue(e['unitPrice']),
                            _formatCellValue(e['lineTotal']),
                          ])
                      .toList(),
                  font: arabicFont,
                  bold: arabicFontBold,
                  rtl: loc.rtlLayout,
                  headerBackgroundColor: PdfMizaDocumentTheme.primary,
                  headerTextColor: PdfColors.white,
                  zebraStripes: true,
                  rowStripeColor: PdfMizaDocumentTheme.tableStripe,
                  borderColor: PdfMizaDocumentTheme.tableBorder,
                  borderWidth: 0.45,
                ),
                pw.SizedBox(height: 10),
                ReportExportHelper.buildPdfReceiptStyleTotals(
                  font: arabicFont,
                  bold: arabicFontBold,
                  rtl: loc.rtlLayout,
                  ruleColor: PdfMizaDocumentTheme.tableBorder,
                  rows: thermalTotals,
                ),
                if (effectiveTaxRateForFootnote > 1e-9) ...[
                  pw.SizedBox(height: 8),
                  pw.Text(
                    loc.pdfInvoiceTaxFootnote,
                    style: pw.TextStyle(
                      font: arabicFont,
                      fontSize: 8.5,
                      color: PdfColors.grey700,
                    ),
                  ),
                ],
                pw.SizedBox(height: 12),
                pw.Text(
                  ReportExportHelper.stripPdfInvisibleChars(
                      '${loc.rtlLayout ? 'المبلغ كتابة' : 'Amount in words'}: $amountWords'),
                  style: pw.TextStyle(
                    font: arabicFont,
                    fontSize: 9.5,
                    color: PdfColors.grey800,
                    fontStyle: pw.FontStyle.italic,
                    height: 1.35,
                  ),
                ),
                if (stampImg != null) ...[
                  pw.SizedBox(height: 22),
                  pw.Align(
                    alignment: pw.Alignment.center,
                    child: pw.Column(
                      mainAxisSize: pw.MainAxisSize.min,
                      children: [
                        pw.Image(
                          stampImg,
                          width: 120,
                          height: 64,
                          fit: pw.BoxFit.contain,
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          loc.pdfStampCaption,
                          style: pw.TextStyle(
                            font: arabicFont,
                            fontSize: 8,
                            color: PdfColors.grey700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
    return Uint8List.fromList(await doc.save());
  }

  Future<void> _printInvoice(
      {required String invoiceId, required String type}) async {
    final bytes = await _buildInvoicePdfBytes(invoiceId: invoiceId, type: type);
    if (bytes == null || !mounted) return;
    final loc = AppLocalizations.of(context);
    if (!context.mounted) return;
    await openReportPdfPreviewDialog(
      context,
      bytes: bytes,
      title: loc.isEnglish ? 'Invoice' : 'فاتورة',
      suggestedFileName: ReportExportHelper.pdfSuggestedFileName(
        '${loc.isEnglish ? 'invoice' : 'فاتورة'}_${invoiceId}_$type',
        'invoice',
      ),
    );
  }

  void _showError(String message, {BuildContext? messengerContext}) {
    final ctx = messengerContext ?? context;
    if (!ctx.mounted) return;
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _showSuccess(String message, {BuildContext? messengerContext}) {
    final ctx = messengerContext ?? context;
    if (!ctx.mounted) return;
    if (_uiPrefs.enableSounds) {
      unawaited(BarcodeScanHelpers.playSuccessSoundIfEnabled(true));
    }
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green.shade700,
      ),
    );
  }

  /// أيقونة الشريط السفلي في الرئيسية (بدون خلفية ملوّنة).
  Widget _mobileBrightIconChip(
    IconData icon,
    Color tint, {
    double size = 24,
  }) {
    return Icon(icon, size: size, color: tint);
  }

  Widget _adminMenuTile(
    BuildContext context,
    IconData icon,
    String label, {
    Color? iconTint,
    double iconBoxAlpha = 0.2,
  }) {
    final cs = Theme.of(context).colorScheme;
    final tint = iconTint ?? cs.primary;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: tint.withValues(alpha: iconBoxAlpha),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(icon, size: 20, color: tint),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.15,
                  height: 1.25,
                ),
          ),
        ),
      ],
    );
  }

  List<PopupMenuEntry<String>> _buildAdminMenuEntries(
      BuildContext menuContext) {
    final loc = AppLocalizations.of(menuContext);
    final svc = widget.accountingService;
    final activationMenuIcon =
        (!svc.isGuestSession && svc.licenseGate.hasPaidCoverage(DateTime.now()))
            ? Icons.verified_rounded
            : Icons.key_rounded;
    final activationTint =
        (!svc.isGuestSession && svc.licenseGate.hasPaidCoverage(DateTime.now()))
            ? _MobileBrightIconStyle.emerald
            : _MobileBrightIconStyle.amber;
    Widget tile(
      IconData icon,
      String label, {
      required Color tint,
      double iconAlpha = _MobileBrightIconStyle.menuBgAlpha,
    }) =>
        _adminMenuTile(menuContext, icon, label,
            iconTint: tint, iconBoxAlpha: iconAlpha);

    Widget loginMenuChild() {
      // «حسابي» مرتبط الآن بحساب المشترك (نظام القسيمة) — البيانات نفسها
      // المستعملة في تفعيل القسيمة. لا علاقة بنظام دخول الموظفين القديم.
      final voucherEmail =
          VoucherSessionManager.instance.sessionNotifier.value?.email.trim() ??
              '';
      if (voucherEmail.isNotEmpty) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            tile(Icons.account_circle_rounded, loc.menuSignedInAccountEntry,
                tint: _MobileBrightIconStyle.indigo),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 2, end: 2),
              child: Text(
                voucherEmail,
                style: Theme.of(menuContext).textTheme.bodySmall?.copyWith(
                      color: Theme.of(menuContext)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.72),
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
              ),
            ),
          ],
        );
      }
      return tile(Icons.account_circle_rounded, loc.menuSignedInAccountEntry,
          tint: _MobileBrightIconStyle.indigo);
    }

    return [
      PopupMenuItem<String>(
        value: 'login',
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: loginMenuChild(),
      ),
      PopupMenuItem<String>(
        value: 'users',
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: tile(Icons.badge_rounded, loc.menuUsers, tint: _MobileBrightIconStyle.violet),
      ),
      const PopupMenuDivider(height: 1),
      PopupMenuItem<String>(
        value: 'settings',
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: tile(Icons.settings_rounded, loc.menuSettings, tint: _MobileBrightIconStyle.slate),
      ),
      const PopupMenuDivider(height: 1),
      PopupMenuItem<String>(
        value: 'month_compare',
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: tile(Icons.calendar_month_rounded, loc.menuMonthCompare,
            tint: _MobileBrightIconStyle.teal),
      ),
      PopupMenuItem<String>(
        value: 'audit',
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: tile(Icons.fact_check_rounded, loc.menuAudit, tint: _MobileBrightIconStyle.cyan),
      ),
      const PopupMenuDivider(height: 1),
      PopupMenuItem<String>(
        value: 'printer',
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: tile(Icons.print_rounded, loc.menuPrinter, tint: _MobileBrightIconStyle.orange),
      ),
      const PopupMenuDivider(height: 1),
      PopupMenuItem<String>(
        value: 'backup',
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: tile(Icons.cloud_download_rounded, loc.menuBackup,
            tint: _MobileBrightIconStyle.blue),
      ),
      if (_showCancelVoucherAdminMenuItems) ...[
        const PopupMenuDivider(height: 1),
        PopupMenuItem<String>(
          value: 'cancel_cash',
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: tile(Icons.point_of_sale_rounded, loc.menuCancelCash,
              tint: _MobileBrightIconStyle.rose, iconAlpha: 0.18),
        ),
        PopupMenuItem<String>(
          value: 'cancel_amounts',
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: tile(Icons.price_change_rounded, loc.menuCancelAmounts,
              tint: _MobileBrightIconStyle.rose, iconAlpha: 0.18),
        ),
        const PopupMenuDivider(height: 1),
      ],
      PopupMenuItem<String>(
        value: 'activation',
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: tile(activationMenuIcon, loc.activationDialogTitle,
            tint: activationTint),
      ),
      PopupMenuItem<String>(
        value: 'agents',
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: tile(Icons.handshake_rounded, loc.menuAgents, tint: _MobileBrightIconStyle.pink),
      ),
      PopupMenuItem<String>(
        value: 'help',
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: tile(Icons.help_center_rounded, loc.menuHelp, tint: _MobileBrightIconStyle.sky),
      ),
      PopupMenuItem<String>(
        value: 'about',
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: tile(Icons.info_outline_rounded, loc.menuAbout, tint: _MobileBrightIconStyle.indigo),
      ),
      PopupMenuItem<String>(
        value: 'program_update',
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: tile(Icons.system_update_alt_rounded, loc.menuProgramUpdate,
            tint: _MobileBrightIconStyle.amber),
      ),
      const PopupMenuDivider(height: 1),
      PopupMenuItem<String>(
        value: 'owner_feedback',
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: tile(Icons.mark_email_unread_rounded, loc.menuOwnerFeedback,
            tint: _MobileBrightIconStyle.rose),
      ),
    ];
  }

  /// الميزات المحجوزة ما لم تُفتح عبر قسيمة الجهاز أو ترخيص تشغيلي (اشتراك/تفعيل).
  /// تفتح حواراً شارحاً + زر «تفعيل الاشتراك» عند محاولة دخولها بدون أحدهما.
  static const Set<String> _voucherGatedMenuActions = {
    'users',
    'backup',
    if (_showCancelVoucherAdminMenuItems) 'cancel_cash',
    if (_showCancelVoucherAdminMenuItems) 'cancel_amounts',
    'audit',
    'month_compare',
    // «وكلاؤنا»: معلومات واتصال — متاحة دون تفعيل القسيمة/الاشتراك.
  };

  Future<void> _handleAdminMenuAction(String value) async {
    if (_voucherGatedMenuActions.contains(value) &&
        !_adminLicenseOrVoucherUnlocked) {
      await _showActivationRequiredDialog();
      return;
    }
    if (value == 'settings') {
      await _showAdminSettingsDialog();
    } else if (value == 'month_compare') {
      await _showMonthComparisonDialog();
    } else if (value == 'users') {
      await _openEmployeesHub();
    } else if (value == 'audit') {
      await _showAuditDialog();
    } else if (value == 'printer') {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => Theme(
            data: _buildScreenTheme(),
            child: const PrinterToolsScreen(),
          ),
        ),
      );
      if (mounted) {
        final disk = await loadStoreUiPreferences();
        setState(() {
          _uiPrefs = _uiPrefs.copyWith(
            preferredPrinterUrl: disk.preferredPrinterUrl,
            preferredPrinterName: disk.preferredPrinterName,
          );
        });
      }
    } else if (value == 'backup') {
      await _interactiveBackup();
    } else if (value == 'cancel_cash') {
      await _openCancelCashVoucherScreen();
    } else if (value == 'cancel_amounts') {
      await _openCancelAmountsScreen();
    } else if (value == 'agents') {
      await _showAgentsDialog();
    } else if (value == 'activation') {
      await _openSubscriptionActivationFlow();
    } else if (value == 'help') {
      await _showHelpDialog();
    } else if (value == 'about') {
      await _showAboutProgramDialog();
    } else if (value == 'program_update') {
      await _showProgramUpdateDialog();
    } else if (value == 'owner_feedback') {
      await _showOwnerFeedbackMailDialog();
    } else if (value == 'login') {
      // «حسابي»: إذا للمشترك جلسة مفتوحة نفتح صفحة الحساب الحديثة،
      // وإلا نفتح حوار تفعيل القسيمة لتسجيل/إنشاء حساب.
      await _openMyAccountPage();
    }
    await _loadDashboard();
  }

  Future<void> _toggleDarkMode() async {
    setState(() => _isDarkMode = !_isDarkMode);
    AppTheme.apply(isDarkMode: _isDarkMode);
    await _saveStoreSettings();
    final loc = AppLocalizations.of(context);
    _showSuccess(_isDarkMode ? loc.themeEnabledDark : loc.themeEnabledLight);
  }

  Future<void> _openCancelCashVoucherScreen() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => Theme(
          data: _buildScreenTheme(),
          child: CancelCashVoucherScreen(
            accountingService: widget.accountingService,
            currencyCode: _baseCurrencyCode,
            currencyParts: _currencyParts,
          ),
        ),
      ),
    );
  }

  Future<void> _openCancelAmountsScreen() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => Theme(
          data: _buildScreenTheme(),
          child: CancelAmountsScreen(
            accountingService: widget.accountingService,
            currencyCode: _baseCurrencyCode,
            currencyParts: _currencyParts,
          ),
        ),
      ),
    );
  }

  Future<void> _showAgentsDialog() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final loc = AppLocalizations.of(dialogContext);
        final theme = Theme.of(dialogContext);
        final cs = theme.colorScheme;
        Widget benefitRow(IconData icon, String text) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, size: 16, color: cs.primary),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      text,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        height: 1.45,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            );

        return Dialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: [
                    cs.primary.withValues(alpha: 0.12),
                    const Color(0xFF6366F1).withValues(alpha: 0.08),
                    Colors.white,
                  ],
                ),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      width: 70,
                      height: 70,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [cs.primary, const Color(0xFF3B82F6)],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: cs.primary.withValues(alpha: 0.28),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.handshake_rounded,
                          color: Colors.white, size: 34),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      loc.agentsDialogHeroTitle,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      loc.agentsDialogHeroBody,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        height: 1.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.amber.shade200),
                      ),
                      child: Text(
                        loc.agentsDialogNeedLine,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: Colors.amber.shade900,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      loc.agentsDialogBenefitsTitle,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: cs.primary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    benefitRow(
                        Icons.trending_up_rounded, loc.agentsDialogBenefit1),
                    benefitRow(
                        Icons.support_agent_rounded, loc.agentsDialogBenefit2),
                    benefitRow(Icons.workspace_premium_rounded,
                        loc.agentsDialogBenefit3),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: () => _launchSupportWhatsApp(dialogContext),
                      icon: const Icon(Icons.chat_rounded),
                      label: Text(loc.agentsDialogCtaWhatsApp),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () =>
                          _launchActivationOfficialSite(dialogContext),
                      icon: const Icon(Icons.public_rounded),
                      label: Text(loc.agentsDialogCtaWebsite),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      loc.agentsDialogFooter,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showHelpDialog() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final loc = AppLocalizations.of(dialogContext);
        final theme = Theme.of(dialogContext);
        final cs = theme.colorScheme;
        TextStyle heading(bool top) => theme.textTheme.titleSmall!.copyWith(
              fontWeight: FontWeight.w800,
              color: cs.primary,
              letterSpacing: -0.2,
            );

        Widget sectionTitle(String text, {bool top = false}) => Padding(
              padding: EdgeInsets.only(top: top ? 0 : 18, bottom: 8),
              child: Text(text, style: heading(top)),
            );

        Widget bulletLine(String text) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Icon(Icons.circle, size: 6, color: cs.primary),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      text,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        height: 1.45,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            );

        return AlertDialog(
          title: Text(loc.helpDialogTitle),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  sectionTitle(loc.helpSectionShortcuts, top: true),
                  bulletLine(loc.helpShortcutThemeToggle),
                  sectionTitle(loc.helpSectionUsingApp),
                  Text(
                    loc.helpTipAdminMenu,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      height: 1.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  sectionTitle(loc.helpSectionContact),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: cs.outlineVariant.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Icon(Icons.chat_rounded,
                              size: 28, color: Colors.green.shade700),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  loc.helpWhatsAppLabel,
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                SelectableText(
                                  loc.helpWhatsAppNumber,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.5,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(loc.okGotIt),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showAboutProgramDialog() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final loc = AppLocalizations.of(dialogContext);
        final theme = Theme.of(dialogContext);
        final cs = theme.colorScheme;
        final year = DateTime.now().year;
        final bodyStyle = theme.textTheme.bodyMedium?.copyWith(
          height: 1.52,
          fontWeight: FontWeight.w500,
        );

        return AlertDialog(
          title: Text(loc.menuAbout),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const MizaPosDialogBrandBanner(bannerHeight: 132),
                  const SizedBox(height: 12),
                  Text(
                    loc.aboutLeadLine,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(loc.aboutDescription, style: bodyStyle),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    child: Divider(
                      height: 1,
                      color: cs.outlineVariant.withValues(alpha: 0.6),
                    ),
                  ),
                  Text(
                    loc.aboutSupportIntro,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: cs.primary,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: cs.outlineVariant.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Icon(Icons.chat_rounded,
                              size: 28, color: Colors.green.shade700),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  loc.helpWhatsAppLabel,
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                SelectableText(
                                  loc.helpWhatsAppNumber,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.5,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const MizaPosSocialLinksSection(),
                  const SizedBox(height: 16),
                  Text(
                    loc.aboutCopyrightLine(year),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant.withValues(alpha: 0.85),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(loc.okGotIt),
            ),
          ],
        );
      },
    );
  }

  static final Uri _supportWhatsAppUri =
      Uri.parse('https://wa.me/970599488939');

  static final Uri _activationWebsiteUri =
      Uri.parse('https://mizapos.com/drhsn');

  Future<void> _launchActivationOfficialSite(BuildContext context) async {
    try {
      final ok = await launchUrl(
        _activationWebsiteUri,
        mode: LaunchMode.externalApplication,
      );
      if (!ok && context.mounted) {
        _showError(AppLocalizations.of(context).updateLaunchDownloadFailed);
      }
    } catch (_) {
      if (context.mounted) {
        _showError(AppLocalizations.of(context).updateLaunchDownloadFailed);
      }
    }
  }

  Future<void> _launchSupportWhatsApp(BuildContext context) async {
    try {
      final ok = await launchUrl(
        _supportWhatsAppUri,
        mode: LaunchMode.externalApplication,
      );
      if (!ok && context.mounted) {
        _showError(AppLocalizations.of(context).updateLaunchWhatsAppFailed);
      }
    } catch (_) {
      if (context.mounted) {
        _showError(AppLocalizations.of(context).updateLaunchWhatsAppFailed);
      }
    }
  }

  Future<void> _launchProgramDownloadPage(BuildContext context) async {
    final loc = AppLocalizations.of(context);
    final raw = loc.updateDownloadPageUrl.trim();
    if (raw.isEmpty) {
      if (context.mounted) {
        _showError(loc.updateLaunchDownloadFailed);
      }
      return;
    }
    late final Uri uri;
    try {
      uri = Uri.parse(raw);
      if (!uri.hasScheme || uri.host.isEmpty) {
        throw FormatException('invalid url', raw);
      }
    } catch (_) {
      if (context.mounted) {
        _showError(loc.updateLaunchDownloadFailed);
      }
      return;
    }
    try {
      final ok = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!ok && context.mounted) {
        _showError(loc.updateLaunchDownloadFailed);
      }
    } catch (_) {
      if (context.mounted) {
        _showError(loc.updateLaunchDownloadFailed);
      }
    }
  }

  Future<void> _showOwnerFeedbackMailDialog() async {
    final loc = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final englishUi = _uiPrefs.languageCode == 'en';
    final fullNameCtrl = TextEditingController();
    final whatsCtrl = TextEditingController();
    final contactEmailCtrl = TextEditingController();
    final subjectCtrl = TextEditingController();
    final messageCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    var dialCode = kDefaultDialCode;

    String appContextBlock() {
      final ar = _uiPrefs.languageCode != 'en';
      final storeLine = ar ? 'المتجر: $_storeName' : 'Store: $_storeName';
      final userLine = widget.accountingService.isGuestSession
          ? (ar ? 'الجلسة: زائر' : 'Session: guest')
          : (ar ? 'الحساب: $_currentUsername' : 'Account: $_currentUsername');
      return loc.ownerFeedbackMailBodyPrefix(storeLine, userLine);
    }

    bool? sent;
    try {
      sent = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          final scheme = Theme.of(dialogContext).colorScheme;
          var sending = false;
          return StatefulBuilder(
            builder: (ctx, setLocal) {
              Future<void> submit() async {
                if (!(formKey.currentState?.validate() ?? false)) return;
                setLocal(() => sending = true);
                var skipSendingReset = false;
                try {
                  final outcome = await sendDeveloperFeedbackEmail(
                    fullName: fullNameCtrl.text.trim(),
                    dialCode: dialCode,
                    whatsAppNational: whatsCtrl.text.trim(),
                    feedbackText: messageCtrl.text.trim(),
                    contactEmail: contactEmailCtrl.text.trim(),
                    subjectLine: subjectCtrl.text.trim(),
                    appContextLines: appContextBlock(),
                  );
                  if (!ctx.mounted) return;
                  switch (outcome) {
                    case DeveloperFeedbackSent():
                      skipSendingReset = true;
                      Navigator.pop(ctx, true);
                    case DeveloperFeedbackSentViaWhatsApp():
                      // فُتح واتساب وملأنا الرسالة — أغلِق الحوار وأخطر
                      // المستخدم بأنّه عليه ضغط «إرسال» داخل واتساب.
                      skipSendingReset = true;
                      Navigator.pop(ctx, true);
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(loc.ownerFeedbackOpenedWhatsApp),
                          duration: const Duration(seconds: 5),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    case DeveloperFeedbackSmtpMissing():
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(loc.ownerFeedbackSmtpMissingSnack),
                          duration: const Duration(seconds: 8),
                        ),
                      );
                    case DeveloperFeedbackFailed(:final message):
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(loc.ownerFeedbackSendFailed(message)),
                        ),
                      );
                  }
                } finally {
                  if (ctx.mounted && !skipSendingReset) {
                    setLocal(() => sending = false);
                  }
                }
              }

              return AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                title: Text(
                  loc.ownerFeedbackDialogTitle,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                content: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: SizedBox(
                    width: MediaQuery.of(dialogContext).size.width * 0.94,
                    child: SingleChildScrollView(
                      child: Form(
                        key: formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const MizaPosDialogBrandBanner(bannerHeight: 120),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: fullNameCtrl,
                              textAlign:
                                  englishUi ? TextAlign.left : TextAlign.right,
                              decoration: UiStyleTokens.formFieldDecoration(
                                loc.ownerFeedbackFullNameLabel,
                              ),
                              validator: (v) {
                                if ((v ?? '').trim().isEmpty) {
                                  return loc.ownerFeedbackFullNameRequired;
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 10),
                            DialCodePickerField(
                              dialCode: dialCode,
                              onDialCodeChanged: (c) =>
                                  setLocal(() => dialCode = c),
                              labelText: loc.ownerFeedbackDialCodeLabel,
                              enabled: !sending,
                              englishUi: englishUi,
                              decoration: UiStyleTokens.formFieldDecoration(
                                loc.ownerFeedbackDialCodeLabel,
                              ).copyWith(
                                prefixIcon: Icon(
                                  Icons.public_rounded,
                                  color: scheme.primary.withValues(alpha: 0.85),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextFormField(
                              controller: whatsCtrl,
                              textAlign:
                                  englishUi ? TextAlign.left : TextAlign.right,
                              keyboardType: TextInputType.phone,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              decoration: UiStyleTokens.formFieldDecoration(
                                loc.ownerFeedbackWhatsAppLabel,
                              ).copyWith(
                                hintText: loc.ownerFeedbackWhatsAppHint,
                              ),
                              validator: (v) {
                                final t = (v ?? '').trim();
                                if (t.isEmpty) {
                                  return loc.ownerFeedbackWhatsAppRequired;
                                }
                                if (t.length < 6) {
                                  return loc.ownerFeedbackWhatsAppTooShort;
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 10),
                            TextFormField(
                              controller: contactEmailCtrl,
                              textAlign:
                                  englishUi ? TextAlign.left : TextAlign.right,
                              keyboardType: TextInputType.emailAddress,
                              decoration: UiStyleTokens.formFieldDecoration(
                                loc.ownerFeedbackContactEmailLabel,
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextFormField(
                              controller: subjectCtrl,
                              textAlign:
                                  englishUi ? TextAlign.left : TextAlign.right,
                              decoration: UiStyleTokens.formFieldDecoration(
                                loc.ownerFeedbackSubjectLabel,
                              ).copyWith(
                                hintText: loc.ownerFeedbackSubjectHint,
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextFormField(
                              controller: messageCtrl,
                              textAlign:
                                  englishUi ? TextAlign.left : TextAlign.right,
                              minLines: 5,
                              maxLines: 12,
                              decoration: UiStyleTokens.formFieldDecoration(
                                loc.ownerFeedbackMessageLabel,
                              ).copyWith(
                                alignLabelWithHint: true,
                              ),
                              validator: (v) {
                                if ((v ?? '').trim().isEmpty) {
                                  return loc.ownerFeedbackMessageRequired;
                                }
                                return null;
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed:
                        sending ? null : () => Navigator.pop(dialogContext),
                    child: Text(loc.cancel),
                  ),
                  FilledButton.icon(
                    onPressed: sending ? null : submit,
                    icon: sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded, size: 20),
                    label: Text(loc.ownerFeedbackSendButton),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      fullNameCtrl.dispose();
      whatsCtrl.dispose();
      contactEmailCtrl.dispose();
      subjectCtrl.dispose();
      messageCtrl.dispose();
    }
    if (mounted && sent == true) {
      await _showOwnerFeedbackThankYouDialog();
    }
  }

  Future<void> _showOwnerFeedbackThankYouDialog() async {
    final loc = AppLocalizations.of(context);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        final scheme = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.favorite_rounded, color: scheme.primary, size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  loc.ownerFeedbackThankYouTitle,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Text(
              loc.ownerFeedbackThankYouBody,
              textAlign: _uiPrefs.languageCode == 'en'
                  ? TextAlign.start
                  : TextAlign.right,
              style: Theme.of(dialogContext).textTheme.bodyLarge?.copyWith(
                    height: 1.55,
                  ),
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(loc.ownerFeedbackThankYouButton),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showProgramUpdateDialog() async {
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (dialogContext) {
        return _ModernProgramUpdateDialog(
          onClose: () => Navigator.pop(dialogContext),
          onWhatsApp: () => _launchSupportWhatsApp(dialogContext),
          onOpenDownload: () => _launchProgramDownloadPage(dialogContext),
          onBackupBeforeUpdate: _interactiveBackup,
        );
      },
    );
  }

  // ignore: unused_element
  Future<void> _showLoginFromMenuDialog() async {
    final svc = widget.accountingService;
    if (!svc.isGuestSession && svc.session != null) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (pageCtx) => Theme(
            data: _buildScreenTheme(),
            child: MyAccountScreen(
              accountingService: widget.accountingService,
              onSignOut: () async {
                if (!await _confirmStaffLogout(pageCtx)) return;
                if (pageCtx.mounted) Navigator.of(pageCtx).pop();
                await _returnToGuestSession();
              },
              onSwitchAccount: () async {
                Navigator.of(pageCtx).pop();
                if (!mounted) return;
                await Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    fullscreenDialog: true,
                    builder: (loginCtx) => Theme(
                      data: _buildScreenTheme(),
                      child: LoginScreen(
                        accountingService: widget.accountingService,
                        rememberLoginUsername: _uiPrefs.rememberLoginUsername,
                        lastRememberedEmail: _uiPrefs.lastRememberedUsername,
                        onRememberChanged: (v) async {
                          setState(() {
                            _uiPrefs =
                                _uiPrefs.copyWith(rememberLoginUsername: v);
                          });
                          await _saveStoreSettings();
                        },
                        onLoginSuccess: _completeLoginAfterSuccess,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      if (mounted) {
        await widget.accountingService.syncLicenseGate();
        setState(() {});
      }
      return;
    }

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (ctx) => Theme(
          data: _buildScreenTheme(),
          child: LoginScreen(
            accountingService: widget.accountingService,
            rememberLoginUsername: _uiPrefs.rememberLoginUsername,
            lastRememberedEmail: _uiPrefs.lastRememberedUsername,
            onRememberChanged: (v) async {
              setState(() {
                _uiPrefs = _uiPrefs.copyWith(rememberLoginUsername: v);
              });
              await _saveStoreSettings();
            },
            onLoginSuccess: _completeLoginAfterSuccess,
          ),
        ),
      ),
    );
    if (mounted) {
      await widget.accountingService.syncLicenseGate();
      setState(() {});
    }
  }

  Future<void> _showActivationDialog() async {
    await widget.accountingService.syncLicenseGate();
    if (!mounted) return;
    final svc = widget.accountingService;
    final gate = svc.licenseGate;
    final now = DateTime.now();
    final kind = gate.coverageKind(now);

    // اشتراك سنوي أو ترخيص كامل فقط — لا تعامل التجربة كـ«مفعّل بالكامل».
    final fullyLicensed = kind == LicenseCoverageKind.annual ||
        kind == LicenseCoverageKind.grandfather ||
        kind == LicenseCoverageKind.legacyActivated;
    if (!svc.isGuestSession && fullyLicensed) {
      final holder = await svc.subscriptionHolderDisplayName();
      final subscriptionEmail = await svc.currentUserSubscriptionEmail();
      if (!mounted) return;
      final isDark = Theme.of(context).brightness == Brightness.dark;
      await showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (dialogContext) {
          final dlgLoc = AppLocalizations.of(dialogContext);
          final subLine = _activationDeviceSubtitle(dlgLoc);
          final emailTrimmed = subscriptionEmail?.trim();
          final hasEmail = emailTrimmed != null && emailTrimmed.isNotEmpty;
          return Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
            clipBehavior: Clip.antiAlias,
            child: _ActivationCelebrationDialogBody(
              headline: dlgLoc.activationAccountActiveHeadline,
              congratsLine: dlgLoc.activationCelebrationCongrats,
              subscriptionEmail: hasEmail ? emailTrimmed : null,
              registeredEmailCaption: dlgLoc.activationRegisteredEmailLabel,
              fallbackSubtitle: dlgLoc.activationManageTitle,
              statusText: _activationDialogStatusText(dlgLoc),
              statusColor: _activationDialogStatusColor(),
              subLine: subLine,
              holderLine: holder != null && holder.trim().isNotEmpty
                  ? dlgLoc.deviceActivatedNamedLine(holder.trim())
                  : null,
              closeLabel: dlgLoc.close,
              isDark: isDark,
              onClose: () => Navigator.pop(dialogContext),
            ),
          );
        },
      );
      await _refreshSubscriptionHolder();
      return;
    }

    final homeContext = context;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final dlgLoc = AppLocalizations.of(dialogContext);
        final cs = Theme.of(dialogContext).colorScheme;
        var deviceLinkLoading = true;
        var deviceLinkCode = '';
        var applyingDeviceSync = false;
        String? deviceSyncErr;
        var deviceLinkInitScheduled = false;
        return StatefulBuilder(
          builder: (_, setDialogState) {
            if (!deviceLinkInitScheduled) {
              deviceLinkInitScheduled = true;
              WidgetsBinding.instance.addPostFrameCallback((_) async {
                final id = await DeviceBinding.readInstallationId();
                final formatted = DeviceLinkCode.fromInstallationId(id);
                if (!dialogContext.mounted) return;
                setDialogState(() {
                  deviceLinkCode = formatted;
                  deviceLinkLoading = false;
                });
                // إعلام السيرفر بـ installation_id ↔ organization_id (المحلي) حتى تستخدمها لوحة
                // المسؤول عند ضغط «تفعيل الاشتراك بهذا الجهاز» (بدلاً من توليد قيم لا تطابق التطبيق).
                final slug = formatted
                    .replaceAll(RegExp(r'[^A-Za-z0-9]'), '')
                    .toLowerCase();
                final clamped = slug.length > 20 ? slug.substring(0, 20) : slug;
                if (clamped.isNotEmpty) {
                  unawaited(
                    svc.pushDeviceLinkClaimToActivationServer(
                      'device-$clamped@mizapos.local',
                    ),
                  );
                }
              });
            }
            final media = MediaQuery.sizeOf(dialogContext);
            final headerAccent =
                Color.lerp(cs.primary, const Color(0xFF0D9488), 0.28) ??
                    cs.primary;
            final sectionBg = cs.surfaceContainerHigh.withValues(alpha: 0.86);
            final sectionBorder = cs.outlineVariant.withValues(alpha: 0.55);
            final stepLines = <String>[
              dlgLoc.subscriptionActivationStep1,
              dlgLoc.subscriptionActivationStep2,
              dlgLoc.subscriptionActivationStep3,
              dlgLoc.subscriptionActivationStep4,
              dlgLoc.subscriptionActivationStep5,
            ];
            return Dialog(
              insetPadding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
              backgroundColor: Colors.transparent,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
              clipBehavior: Clip.antiAlias,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                      color: cs.outlineVariant.withValues(alpha: 0.45)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 30,
                      offset: const Offset(0, 14),
                    ),
                  ],
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: 460,
                    maxHeight: media.height * 0.92,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [cs.primary, headerAccent],
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
                          child: Column(
                            children: [
                              Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.14),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.22),
                                  ),
                                ),
                                child: Icon(
                                  Icons.workspace_premium_outlined,
                                  color: Colors.white.withValues(alpha: 0.96),
                                  size: 30,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                dlgLoc.subscriptionActivationPageTitle,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  height: 1.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                    minimumSize: const Size.fromHeight(44),
                                  ),
                                  icon: const Icon(
                                    Icons.confirmation_number_outlined,
                                  ),
                                  label: Text(dlgLoc.voucherDialogTitle),
                                  onPressed: () async {
                                    Navigator.of(dialogContext).pop();
                                    await showVoucherActivationDialog(
                                      homeContext,
                                      allowSubscriberManagement:
                                          _isOwnerSession,
                                    );
                                    if (mounted) {
                                      await widget.accountingService
                                          .syncLicenseGate();
                                      if (mounted) setState(() {});
                                    }
                                  },
                                ),
                              ),
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  color: _activationDialogStatusColor()
                                      .withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  child: Text(
                                    _activationDialogStatusText(dlgLoc),
                                    textAlign: TextAlign.start,
                                    style: TextStyle(
                                      color: _activationDialogStatusColor(),
                                      fontWeight: FontWeight.w700,
                                      height: 1.35,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  color: sectionBg,
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(color: sectionBorder),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Text(
                                        dlgLoc
                                            .subscriptionActivationDeviceCodeLabel,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                          color: cs.onSurfaceVariant,
                                          letterSpacing: 0.2,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      if (deviceLinkLoading)
                                        const Center(
                                          child: Padding(
                                            padding: EdgeInsets.all(10),
                                            child: SizedBox(
                                              width: 24,
                                              height: 24,
                                              child: CircularProgressIndicator(
                                                  strokeWidth: 2),
                                            ),
                                          ),
                                        )
                                      else
                                        Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.center,
                                          children: [
                                            Expanded(
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 12,
                                                  vertical: 12,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: cs.surface,
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                  border: Border.all(
                                                    color: cs.outlineVariant
                                                        .withValues(alpha: 0.6),
                                                  ),
                                                ),
                                                child: SelectableText(
                                                  deviceLinkCode.isEmpty
                                                      ? dlgLoc
                                                          .activationDeviceCodeMissing
                                                      : deviceLinkCode,
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w800,
                                                    fontSize: 13.5,
                                                    height: 1.35,
                                                    color: cs.onSurface,
                                                    fontFeatures: const [
                                                      ui.FontFeature
                                                          .tabularFigures(),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            FilledButton.tonalIcon(
                                              onPressed: deviceLinkCode.isEmpty
                                                  ? null
                                                  : () async {
                                                      await Clipboard.setData(
                                                        ClipboardData(
                                                            text:
                                                                deviceLinkCode),
                                                      );
                                                      if (!dialogContext
                                                          .mounted) {
                                                        return;
                                                      }
                                                      ScaffoldMessenger.of(
                                                              dialogContext)
                                                          .showSnackBar(
                                                        SnackBar(
                                                          content: Text(dlgLoc
                                                              .activationCodeCopied),
                                                        ),
                                                      );
                                                    },
                                              icon: const Icon(
                                                  Icons.copy_rounded,
                                                  size: 18),
                                              label: Text(
                                                  dlgLoc.activationCopyCode),
                                            ),
                                          ],
                                        ),
                                      if (deviceSyncErr != null &&
                                          deviceSyncErr!.isNotEmpty) ...[
                                        const SizedBox(height: 8),
                                        Text(
                                          deviceSyncErr!,
                                          style: TextStyle(
                                            color: cs.error,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                      const SizedBox(height: 14),
                                      FilledButton.icon(
                                        onPressed: (applyingDeviceSync ||
                                                deviceLinkLoading ||
                                                deviceLinkCode.isEmpty)
                                            ? null
                                            : () async {
                                                deviceSyncErr = null;
                                                applyingDeviceSync = true;
                                                setDialogState(() {});
                                                try {
                                                  final session = await svc
                                                      .trySessionFromSignupActivationKey(
                                                          '');
                                                  if (!dialogContext.mounted) {
                                                    return;
                                                  }
                                                  if (session == null) {
                                                    deviceSyncErr = dlgLoc
                                                        .activationDeviceLinkNotLinkedYet;
                                                    return;
                                                  }
                                                  await svc.syncLicenseGate();
                                                  Navigator.pop(dialogContext);
                                                  if (!mounted) return;
                                                  if (widget.accountingService
                                                      .subscriptionBindingMismatch) {
                                                    _showError(dlgLoc
                                                        .activationBindingMismatch);
                                                    return;
                                                  }
                                                  await _refreshSubscriptionHolder();
                                                  await _loadDashboard();
                                                  final gate = widget
                                                      .accountingService
                                                      .licenseGate;
                                                  final now = DateTime.now();
                                                  if (gate
                                                      .hasPaidCoverage(now)) {
                                                    ScaffoldMessenger.of(
                                                            homeContext)
                                                        .hideCurrentMaterialBanner();
                                                    _showSuccess(dlgLoc
                                                        .activationCodeAppliedSnack);
                                                  } else {
                                                    _showSuccess(dlgLoc
                                                        .activationCodeAppliedPendingSnack);
                                                  }
                                                  setState(() {});
                                                } on RemoteSignupOfflineException {
                                                  deviceSyncErr =
                                                      dlgLoc.authErrNoInternet;
                                                } on LicenseException catch (e) {
                                                  deviceSyncErr = dlgLoc
                                                      .licenseErrorMessage(
                                                          e.code);
                                                } catch (e) {
                                                  deviceSyncErr = e.toString();
                                                } finally {
                                                  applyingDeviceSync = false;
                                                  if (dialogContext.mounted) {
                                                    setDialogState(() {});
                                                  }
                                                }
                                              },
                                        icon: applyingDeviceSync
                                            ? const SizedBox(
                                                width: 18,
                                                height: 18,
                                                child:
                                                    CircularProgressIndicator(
                                                        strokeWidth: 2),
                                              )
                                            : const Icon(
                                                Icons.verified_rounded),
                                        label: Text(
                                          applyingDeviceSync
                                              ? dlgLoc
                                                  .activationApplyCodeWorking
                                              : dlgLoc
                                                  .subscriptionActivateButton,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  color: sectionBg,
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(color: sectionBorder),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                              Icons
                                                  .format_list_numbered_rounded,
                                              color: cs.primary,
                                              size: 22),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              dlgLoc
                                                  .subscriptionActivationStepsTitle,
                                              style: TextStyle(
                                                fontWeight: FontWeight.w800,
                                                fontSize: 14.5,
                                                color: cs.onSurface,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      for (var i = 0;
                                          i < stepLines.length;
                                          i++) ...[
                                        if (i > 0) const SizedBox(height: 8),
                                        Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Container(
                                              width: 24,
                                              height: 24,
                                              alignment: Alignment.center,
                                              decoration: BoxDecoration(
                                                color: cs.primary
                                                    .withValues(alpha: 0.12),
                                                shape: BoxShape.circle,
                                              ),
                                              child: Text(
                                                '${i + 1}',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 12,
                                                  color: cs.primary,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Text(
                                                stepLines[i],
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  height: 1.5,
                                                  fontWeight: FontWeight.w600,
                                                  color: cs.onSurfaceVariant,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  color:
                                      cs.errorContainer.withValues(alpha: 0.30),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: cs.error.withValues(alpha: 0.32),
                                  ),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(Icons.info_outline_rounded,
                                          color: cs.error, size: 20),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          dlgLoc.subscriptionActivationNote,
                                          style: TextStyle(
                                            fontSize: 12.8,
                                            height: 1.5,
                                            fontWeight: FontWeight.w600,
                                            color: cs.onErrorContainer,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
                        child: SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(dlgLoc.close),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _syncActivationAndNotify() async {
    final loc = AppLocalizations.of(context);
    if (!mounted) return;
    if (RemoteSignupConfig.activationServerEnabled) {
      try {
        await widget.accountingService.trySessionFromSignupActivationKey('');
      } on RemoteSignupOfflineException {
        _showError(loc.authErrNoInternet);
        return;
      } on LicenseException catch (e) {
        _showError(loc.licenseErrorMessage(e.code));
        return;
      } catch (e) {
        _showError(e.toString());
        return;
      }
    }
    await widget.accountingService.syncLicenseGate();
    if (!mounted) return;
    if (widget.accountingService.subscriptionBindingMismatch) {
      _showError(loc.activationBindingMismatch);
      return;
    }
    final gate = widget.accountingService.licenseGate;
    final now = DateTime.now();
    final kind = gate.coverageKind(now);
    if (kind != LicenseCoverageKind.accessSuspended) {
      ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
    }
    if (gate.hasPaidCoverage(now)) {
      await _refreshSubscriptionHolder();
      _showSuccess(loc.activationRefreshedNowActive);
      setState(() {});
    } else if (kind == LicenseCoverageKind.accessSuspended) {
      _showError(loc.licenseSubscriptionSuspended);
    } else {
      _showError(loc.activationRefreshedStillPending);
    }
  }

  Future<void> _confirmAndFactoryReset(BuildContext anchorContext) async {
    if (!anchorContext.mounted) return;
    final guest = widget.accountingService.isGuestSession;
    if (!guest && widget.accountingService.session?.role != 'owner') {
      _showError(
        'إعادة الضبط الكامل متاحة لوضع الزائر أو حساب المالك فقط.',
        messengerContext: anchorContext,
      );
      return;
    }
    final loc = AppLocalizations.of(anchorContext);
    final phrase = loc.factoryResetConfirmPhrase.trim();
    final isEnglish =
        Localizations.localeOf(anchorContext).languageCode == 'en';
    final confirmed = await showDialog<bool>(
      context: anchorContext,
      barrierDismissible: false,
      builder: (dlgCtx) => _FactoryResetConfirmDialog(
        phrase: phrase,
        isEnglish: isEnglish,
        loc: loc,
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.accountingService.factoryResetAllData();
      if (!mounted) return;
      _applyDefaultStoreSettingsAfterFactoryReset();
      setState(() {
        _authenticated = true;
        _currentUsername = widget.accountingService.session?.username ?? '-';
        _subscriptionHolderLabel = null;
      });
      await _refreshAppBarLoginDisplay();
      await _loadDashboard();
      if (!mounted) return;
      if (anchorContext.mounted && Navigator.of(anchorContext).canPop()) {
        Navigator.of(anchorContext).pop();
      }
      _showSuccess(loc.factoryResetOk);
    } catch (e) {
      if (!mounted) return;
      _showError(_friendlyError(e), messengerContext: anchorContext);
    }
  }

  bool get _en => Localizations.localeOf(context).languageCode == 'en';

  Future<void> _showAdminSettingsDialog() async {
    if (!widget.accountingService.canAccessStoreSettings()) {
      await _showSettingsManagerOnlyDialog();
      return;
    }
    final bundle = StoreSettingsBundle(
      storeName: _storeName,
      storeCountry: _storeCountry,
      storeAddress: _storeAddress,
      storePhone: _storePhone,
      storePhoneAlt: _storePhoneAlt,
      storeLogoPath: _storeLogoPath,
      themeColorKey: _themeColorKey,
      baseCurrencyCode: _baseCurrencyCode,
      currencySubunitName: _currencySubunitName,
      currencyParts: _currencyParts,
      taxPercent: _taxPercent,
      isDarkMode: _isDarkMode,
      lowStockThreshold: _lowStockThreshold,
      dashboardTileOrder: List<String>.from(_dashboardTileOrder),
      initialDashboardTileLabels:
          Map<String, String>.from(_dashboardTileLabels),
      preferences: _uiPrefs,
    );
    final saved = await Navigator.of(context).push<StoreSettingsBundle>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => StoreSettingsScreen(
          bundle: bundle,
          themeColorOptions: _themeColorOptions,
          themeColorLabels: {
            for (final k in _themeColorOptions.keys)
              k: AppLocalizations.of(context).themeColorLabel(k),
          },
          accountingService: widget.accountingService,
          lastRememberedLoginIdentifier: _uiPrefs.rememberLoginUsername
              ? _uiPrefs.lastRememberedUsername
              : null,
          onOpenLogin: (navCtx) async {
            await Navigator.of(navCtx).push<void>(
              MaterialPageRoute<void>(
                fullscreenDialog: true,
                builder: (ctx) => Theme(
                  data: _buildScreenTheme(),
                  child: LoginScreen(
                    accountingService: widget.accountingService,
                    rememberLoginUsername: _uiPrefs.rememberLoginUsername,
                    lastRememberedEmail: _uiPrefs.lastRememberedUsername,
                    onRememberChanged: (v) async {
                      setState(() {
                        _uiPrefs = _uiPrefs.copyWith(rememberLoginUsername: v);
                      });
                      await _saveStoreSettings();
                    },
                    onLoginSuccess: _completeLoginAfterSuccess,
                  ),
                ),
              ),
            );
            if (mounted) setState(() {});
          },
          onOpenTeamManagement: (navCtx) async {
            if (!widget.accountingService.canManageUsers()) return;
            await Navigator.of(navCtx).push<void>(
              MaterialPageRoute<void>(
                fullscreenDialog: true,
                builder: (_) => Theme(
                  data: _buildScreenTheme(),
                  child: UsersSecurityScreen(
                    accountingService: widget.accountingService,
                    initialUiPrefs: _uiPrefs,
                    onUiPrefsSaved: (next) async {
                      setState(() => _uiPrefs = next);
                      await _saveStoreSettings();
                    },
                    persistStoreSettings: _saveStoreSettings,
                    onOpenStoreSettings: () async {
                      if (Navigator.of(navCtx).canPop()) {
                        Navigator.of(navCtx).pop();
                      }
                    },
                  ),
                ),
              ),
            );
            if (mounted) setState(() {});
          },
          onReorderDashboardTiles: _showDashboardTilesReorderDialog,
          localizedDashboardTileTitle: _localizedDashboardTileTitle,
          dashboardTileKeys:
              List<String>.from(HomeScreen.dashboardTileKeysDefault),
          onBackupNow: () async {
            await _interactiveBackup();
          },
          onRestoreFromPath: (path) async {
            try {
              await widget.accountingService.restoreFromJson(path);
              await _loadDashboard();
              if (!mounted) return;
              _showSuccess(AppLocalizations.of(context).restoreOk);
            } catch (e) {
              if (!mounted) return;
              _showError(_friendlyError(e));
            }
          },
          onClearOperationalData: () async {
            final confirm = await showDialog<bool>(
                  context: context,
                  builder: (context) {
                    final loc = AppLocalizations.of(context);
                    return AlertDialog(
                      title: Text(loc.confirmClearOpsTitle),
                      content: Text(loc.confirmClearOpsBody),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: Text(loc.cancel),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: Text(loc.yesClear),
                        ),
                      ],
                    );
                  },
                ) ??
                false;
            if (!confirm) return;
            await widget.accountingService.clearOperationalData();
            await _loadDashboard();
            if (!mounted) return;
            _showSuccess(AppLocalizations.of(context).clearOperationalOk);
          },
          onFactoryReset: _confirmAndFactoryReset,
        ),
      ),
    );
    if (saved == null || !mounted) return;
    setState(() {
      _storeName = saved.storeName;
      _storeCountry = saved.storeCountry;
      _storeAddress = saved.storeAddress;
      _storePhone = saved.storePhone;
      _storePhoneAlt = saved.storePhoneAlt;
      _storeLogoPath = saved.storeLogoPath;
      _themeColorKey = saved.themeColorKey;
      _baseCurrencyCode = saved.baseCurrencyCode;
      _currencySubunitName = saved.currencySubunitName;
      _currencyParts = saved.currencyParts;
      _taxPercent = saved.taxPercent;
      _isDarkMode = saved.isDarkMode;
      _lowStockThreshold = saved.lowStockThreshold;
      _dashboardTileOrder = List<String>.from(saved.dashboardTileOrder);
      _dashboardTileLabels =
          Map<String, String>.from(saved.dashboardTileLabels);
      _uiPrefs = saved.uiPrefs;
      _moneyFormat = _buildMoneyFormat(
        _baseCurrencyCode,
        _currencyParts,
        localeTag: (_uiPrefs.languageCode == 'en') ? 'en' : 'ar',
      );
    });
    AppTheme.apply(themeColorKey: _themeColorKey, isDarkMode: _isDarkMode);
    applySavedLanguageCode(_uiPrefs.languageCode);
    await _saveStoreSettings();
    final regErr = await _syncWindowsStartupRegistration(_uiPrefs.startWithWindows);
    if (_authenticated) _startIdleWatcher();
    if (!mounted) return;
    if (regErr != null) {
      _showError(
        AppLocalizations.of(context).settingsSavedWindowsStartupFailed(regErr),
      );
    } else {
      _showSuccess(AppLocalizations.of(context).settingsSavedOk);
    }
  }

  String _storeSettingsPath() => storeSettingsJsonPath();

  void _applyDefaultStoreSettingsAfterFactoryReset() {
    _storeName = 'متجر فلسطين';
    _storeCountry = '';
    _storeAddress = '';
    _storePhone = '';
    _storePhoneAlt = '';
    _storeLogoPath = null;
    _themeColorKey = 'blue';
    _baseCurrencyCode = 'جنيه';
    _currencySubunitName = 'قرش';
    _currencyParts = 2;
    _taxPercent = 0;
    _lowStockThreshold = 5;
    _isDarkMode = false;
    _dashboardTileOrder =
        List<String>.from(HomeScreen.dashboardTileKeysDefault);
    _dashboardTileLabels = {};
    _uiPrefs = StoreUiPreferences.defaults;
    HardwareBarcodeScanner.instance.enabled =
        _uiPrefs.hardwareBarcodeScannerEnabled;
    _moneyFormat = _buildMoneyFormat(
      _baseCurrencyCode,
      _currencyParts,
      localeTag: (_uiPrefs.languageCode == 'en') ? 'en' : 'ar',
    );
    AppTheme.apply(themeColorKey: _themeColorKey, isDarkMode: _isDarkMode);
    widget.accountingService.applySecurityPreferences(SecurityPreferences.defaults);
    applySavedTextScale(_uiPrefs.uiTextScale);
  }

  Future<void> _loadStoreSettings() async {
    final file = File(_storeSettingsPath());
    if (!await file.exists()) return;
    final raw = await file.readAsString();
    if (raw.trim().isEmpty) return;
    final Map<String, dynamic> map;
    try {
      map = jsonDecode(raw) as Map<String, dynamic>;
    } catch (e, st) {
      debugPrint('store_settings.json parse failed: $e\n$st');
      return;
    }
    _storeName = (map['storeName'] as String?)?.trim().isNotEmpty == true
        ? map['storeName'] as String
        : _storeName;
    _storeCountry = (map['storeCountry'] as String?)?.trim() ?? _storeCountry;
    _storeAddress = (map['storeAddress'] as String?)?.trim() ?? _storeAddress;
    _storePhone = (map['storePhone'] as String?)?.trim() ?? _storePhone;
    _storePhoneAlt =
        (map['storePhoneAlt'] as String?)?.trim() ?? _storePhoneAlt;
    final savedLogo = (map['storeLogoPath'] as String?)?.trim();
    _storeLogoPath =
        (savedLogo != null && savedLogo.isNotEmpty) ? savedLogo : null;
    final savedTheme = (map['themeColorKey'] as String?) ?? _themeColorKey;
    _themeColorKey = _themeColorOptions.containsKey(savedTheme)
        ? savedTheme
        : _themeColorKey;
    final savedCurrency =
        (map['baseCurrencyCode'] as String?)?.trim().toUpperCase();
    _baseCurrencyCode = (savedCurrency != null && savedCurrency.isNotEmpty)
        ? savedCurrency
        : _baseCurrencyCode;
    _currencySubunitName =
        (map['currencySubunitName'] as String?)?.trim().isNotEmpty == true
            ? (map['currencySubunitName'] as String).trim()
            : _currencySubunitName;
    final savedParts = (map['currencyParts'] as num?)?.toInt();
    _currencyParts = (savedParts != null && savedParts >= 0 && savedParts <= 5)
        ? savedParts
        : _currencyParts;
    _taxPercent = ((map['taxPercent'] as num?) ?? 0).toDouble();
    _lowStockThreshold =
        ((map['lowStockThreshold'] as num?) ?? 5).toDouble().clamp(0, 1e6);
    _dashboardTileOrder = _parseDashboardTileOrder(map['dashboardTileOrder']);
    _dashboardTileLabels =
        _parseDashboardTileLabels(map['dashboardTileLabels']);
    _uiPrefs = StoreUiPreferences.fromJson(map['uiPrefs']);
    HardwareBarcodeScanner.instance.enabled =
        _uiPrefs.hardwareBarcodeScannerEnabled;
    _moneyFormat = _buildMoneyFormat(
      _baseCurrencyCode,
      _currencyParts,
      localeTag: (_uiPrefs.languageCode == 'en') ? 'en' : 'ar',
    );
    _isDarkMode = (map['isDarkMode'] as bool?) ?? false;
    AppTheme.apply(themeColorKey: _themeColorKey, isDarkMode: _isDarkMode);
    final secRaw = map['security'];
    widget.accountingService.applySecurityPreferences(
      SecurityPreferences.fromJson(
          secRaw is Map<String, dynamic> ? secRaw : null),
    );
    applySavedTextScale(_uiPrefs.uiTextScale);
  }

  Future<void> _saveStoreSettings() async {
    final diskPrefs = await loadStoreUiPreferences();
    _uiPrefs = _uiPrefs.copyWith(
      preferredPrinterUrl: diskPrefs.preferredPrinterUrl,
      preferredPrinterName: diskPrefs.preferredPrinterName,
    );
    final file = File(_storeSettingsPath());
    final payload = {
      'storeName': _storeName,
      'storeCountry': _storeCountry,
      'storeAddress': _storeAddress,
      'storePhone': _storePhone,
      'storePhoneAlt': _storePhoneAlt,
      'storeLogoPath': _storeLogoPath,
      'themeColorKey': _themeColorKey,
      'baseCurrencyCode': _baseCurrencyCode,
      'currencySubunitName': _currencySubunitName,
      'currencyParts': _currencyParts,
      'taxPercent': _taxPercent,
      'lowStockThreshold': _lowStockThreshold,
      'dashboardTileOrder': _dashboardTileOrder,
      'dashboardTileLabels': {
        for (final e in _dashboardTileLabels.entries)
          if (e.value.trim().isNotEmpty) e.key: e.value.trim(),
      },
      'uiPrefs': _uiPrefs.toJson(),
      'isDarkMode': _isDarkMode,
      'security': widget.accountingService.securityPreferences.toJson(),
      'updatedAt': DateTime.now().toIso8601String(),
    };
    await file
        .writeAsString(const JsonEncoder.withIndent('  ').convert(payload));
    applySavedTextScale(_uiPrefs.uiTextScale);
    AppTheme.apply(themeColorKey: _themeColorKey, isDarkMode: _isDarkMode);
  }

  String? get _resolvedLogoPath {
    final value = _storeLogoPath?.trim();
    if (value == null || value.isEmpty) return null;
    return File(value).existsSync() ? value : null;
  }

  Color _currentThemeColor() => AppTheme.seedColor;

  NumberFormat _buildMoneyFormat(String currencyCode, int decimalDigits,
      {String localeTag = 'ar'}) {
    return NumberFormat.currency(
      locale: localeTag == 'en' ? 'en' : 'ar',
      symbol: '$currencyCode ',
      decimalDigits: decimalDigits,
    );
  }

  ThemeData _buildScreenTheme() => AppTheme.themeData;

  String _friendlyError(Object error) {
    if (error is LicenseException) {
      return AppLocalizations.of(context).licenseErrorMessage(error.code);
    }
    final message = error.toString();
    if (message.startsWith('Exception: ')) {
      return message.substring('Exception: '.length);
    }
    return message;
  }
}

class _IdleLockBarrier extends StatefulWidget {
  const _IdleLockBarrier({
    required this.accountingService,
    required this.onUnlocked,
    required this.onLogout,
  });

  final AccountingService accountingService;
  final VoidCallback onUnlocked;
  final VoidCallback onLogout;

  @override
  State<_IdleLockBarrier> createState() => _IdleLockBarrierState();
}

class _IdleLockBarrierState extends State<_IdleLockBarrier> {
  final TextEditingController _passwordController = TextEditingController();
  bool _busy = false;
  String? _errorText;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _tryUnlock() async {
    setState(() {
      _errorText = null;
      _busy = true;
    });
    final pw = _passwordController.text;
    final okUser = await widget.accountingService.verifyCurrentUserPassword(pw);
    final okProgram = widget.accountingService.programUnlockActive &&
        widget.accountingService.verifyProgramUnlockPassword(pw);
    final ok = okUser || okProgram;
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) {
      setState(() => _errorText = AppLocalizations.of(context).wrongPassword);
      return;
    }
    _passwordController.clear();
    widget.onUnlocked();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return Positioned.fill(
      child: Material(
        color: Colors.black54,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      loc.idleLockTitle,
                      textAlign: TextAlign.start,
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.accountingService.programUnlockActive
                          ? loc.idleLockBodyProgramOrUser
                          : loc.idleLockBody,
                      textAlign: TextAlign.start,
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _passwordController,
                      obscureText: true,
                      textAlign: TextAlign.right,
                      decoration: InputDecoration(
                        labelText: loc.password,
                        border: const OutlineInputBorder(),
                      ),
                      onSubmitted: (_) {
                        if (!_busy) _tryUnlock();
                      },
                    ),
                    if (_errorText != null) ...[
                      const SizedBox(height: 8),
                      Text(_errorText!,
                          textAlign: TextAlign.start,
                          style: const TextStyle(color: Colors.red)),
                    ],
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        TextButton(
                            onPressed: widget.onLogout,
                            child: Text(loc.quitApp)),
                        const Spacer(),
                        FilledButton(
                          onPressed: _busy ? null : _tryUnlock,
                          child: _busy
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : Text(loc.unlock),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OpenGlobalSearchIntent extends Intent {
  const _OpenGlobalSearchIntent();
}

class _GlobalSearchDialog extends StatefulWidget {
  const _GlobalSearchDialog({
    required this.accountingService,
    required this.moneyFormat,
    required this.parentContext,
    required this.currencyCode,
    required this.currencyParts,
    required this.taxPercent,
    required this.uiPrefs,
    this.onUiPrefsChanged,
    this.storeDisplayName = '',
    this.storeMetaLines = const [],
  });

  final AccountingService accountingService;
  final NumberFormat moneyFormat;
  final BuildContext parentContext;
  final String currencyCode;
  final int currencyParts;
  final double taxPercent;
  final StoreUiPreferences uiPrefs;
  final ValueChanged<StoreUiPreferences>? onUiPrefsChanged;
  final String storeDisplayName;
  final List<String> storeMetaLines;

  @override
  State<_GlobalSearchDialog> createState() => _GlobalSearchDialogState();
}

class _GlobalSearchDialogState extends State<_GlobalSearchDialog> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;
  List<Map<String, Object?>> _hits = [];
  bool _busy = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  IconData _iconForHit(String? hitType) {
    switch (hitType) {
      case 'customer':
        return Icons.person_search_rounded;
      case 'product':
        return Icons.inventory_2_rounded;
      case 'sale_invoice':
        return Icons.receipt_long_rounded;
      case 'purchase_invoice':
        return Icons.shopping_bag_rounded;
      default:
        return Icons.search_rounded;
    }
  }

  Future<void> _runSearch(String raw) async {
    setState(() => _busy = true);
    try {
      final rows = await widget.accountingService.globalQuickSearch(raw);
      if (!mounted) return;
      setState(() => _hits = rows);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _scheduleSearch(String value) {
    _debounce?.cancel();
    _debounce =
        Timer(const Duration(milliseconds: 280), () => _runSearch(value));
  }

  Future<void> _openHit(Map<String, Object?> hit) async {
    final hitType = hit['hitType'] as String? ?? '';
    final id = hit['id'] as String? ?? '';
    Navigator.of(context).pop();
    final navCtx = widget.parentContext;
    switch (hitType) {
      case 'customer':
        if (!navCtx.mounted) return;
        await Navigator.push<void>(
          navCtx,
          MaterialPageRoute(
            builder: (_) => CustomerScreen(
              accountingService: widget.accountingService,
              currencyCode: widget.currencyCode,
              currencyParts: widget.currencyParts,
              storeDisplayName: widget.storeDisplayName,
              storeMetaLines: widget.storeMetaLines,
            ),
          ),
        );
        break;
      case 'product':
        if (!navCtx.mounted) return;
        await Navigator.push<void>(
          navCtx,
          MaterialPageRoute(
            builder: (_) => InventoryScreen(
              accountingService: widget.accountingService,
              currencyCode: widget.currencyCode,
              currencyParts: widget.currencyParts,
              taxPercent: widget.taxPercent,
              uiPrefs: widget.uiPrefs,
              onUiPrefsChanged: widget.onUiPrefsChanged,
            ),
          ),
        );
        break;
      case 'sale_invoice':
      case 'purchase_invoice':
        try {
          final invData = await widget.accountingService.invoiceForPrint(
            invoiceId: id,
            type: hitType == 'sale_invoice' ? 'sale' : 'purchase',
          );
          if (!navCtx.mounted) return;
          final invMap = invData['invoice'];
          final itemsList = invData['items'];
          final loc = AppLocalizations.of(navCtx);
          final lines = StringBuffer();
          if (itemsList is List) {
            for (final row in itemsList) {
              if (row is Map) {
                lines.writeln(
                  loc.invoiceLineSummary(
                    '${row['productName'] ?? '-'}',
                    row['quantity'] ?? '-',
                    row['unitPrice'] ?? '-',
                    row['lineTotal'] ?? '-',
                  ),
                );
              }
            }
          }
          final taxFoot = <String>[];
          final up = widget.uiPrefs;
          if (up.taxIdNif.trim().isNotEmpty) {
            taxFoot.add(loc.pdfTaxLine(loc.taxNifLbl, up.taxIdNif.trim()));
          }
          if (up.commercialRc.trim().isNotEmpty) {
            taxFoot.add(loc.pdfTaxLine(loc.taxRcLbl, up.commercialRc.trim()));
          }
          if (up.articleAi.trim().isNotEmpty) {
            taxFoot.add(loc.pdfTaxLine(loc.taxAiLbl, up.articleAi.trim()));
          }
          if (up.statisticalNis.trim().isNotEmpty) {
            taxFoot
                .add(loc.pdfTaxLine(loc.taxNisLbl, up.statisticalNis.trim()));
          }
          final taxBlock = taxFoot.isEmpty
              ? ''
              : '${loc.invoiceTaxFooter}${taxFoot.join('\n')}';

          await showDialog<void>(
            context: navCtx,
            builder: (c) {
              final dlgLoc = AppLocalizations.of(c);
              return AlertDialog(
                title: Text(
                    hit['title']?.toString() ?? dlgLoc.invoiceDefaultTitle),
                content: SingleChildScrollView(
                  child: SelectableText(
                    '${dlgLoc.invoiceMetaId}: $id\n'
                    '${dlgLoc.invoiceMetaDetails}: ${invMap is Map ? invMap.entries.map((e) => '${e.key}: ${e.value}').join('\n') : '-'}\n\n'
                    '${dlgLoc.invoiceMetaLines}:\n${lines.toString().trim()}$taxBlock',
                    textAlign: TextAlign.start,
                  ),
                ),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c),
                      child: Text(dlgLoc.close)),
                ],
              );
            },
          );
        } catch (e) {
          if (!navCtx.mounted) return;
          ScaffoldMessenger.of(navCtx).showSnackBar(
            SnackBar(
                content:
                    Text(AppLocalizations.of(navCtx).invoiceOpenFailed(e))),
          );
        }
        break;
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(loc.globalSearchTitle),
      content: SizedBox(
        width: 500,
        height: 440,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              textAlign: TextAlign.right,
              decoration: InputDecoration(
                hintText: loc.globalSearchHint,
                prefixIcon: const Icon(Icons.search_rounded),
              ),
              onChanged: _scheduleSearch,
            ),
            const SizedBox(height: 8),
            if (_busy) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: _hits.isEmpty
                  ? Center(
                      child: Text(
                        _controller.text.trim().isEmpty
                            ? loc.searchStartTyping
                            : loc.searchNoResults,
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.separated(
                      itemCount: _hits.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final h = _hits[index];
                        return ListTile(
                          leading: Icon(_iconForHit(h['hitType'] as String?)),
                          title: Text((h['title'] ?? '').toString()),
                          subtitle: Text((h['subtitle'] ?? '').toString()),
                          onTap: () => _openHit(h),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: Text(loc.close)),
      ],
    );
  }
}

class _ToggleThemeIntent extends Intent {
  const _ToggleThemeIntent();
}

/// ألوان زاهية لأيقونات قائمة إدارة النظام على الجوال.
abstract final class _MobileBrightIconStyle {
  static const menuBgAlpha = 0.2;

  static const indigo = Color(0xFF6366F1);
  static const violet = Color(0xFF8B5CF6);
  static const slate = Color(0xFF64748B);
  static const teal = Color(0xFF0D9488);
  static const cyan = Color(0xFF0891B2);
  static const orange = Color(0xFFEA580C);
  static const blue = Color(0xFF2563EB);
  static const emerald = Color(0xFF059669);
  static const amber = Color(0xFFD97706);
  static const pink = Color(0xFFDB2777);
  static const sky = Color(0xFF0284C7);
  static const rose = Color(0xFFE11D48);
}

class _MenuCardConfig {
  const _MenuCardConfig({
    required this.tileKey,
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.borderColor,
    required this.onTap,
  });

  final String tileKey;
  final String title;
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final Color borderColor;
  final Future<void> Function() onTap;
}

/// شريط دائم أعلى الشاشة الرئيسية حين تكون القسيمة ملغاةً (وضع قراءة-فقط).
class _VoucherReadOnlyBanner extends StatelessWidget {
  const _VoucherReadOnlyBanner({required this.onOpenActivation});
  final Future<void> Function() onOpenActivation;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return ValueListenableBuilder<VoucherStatus>(
      valueListenable: VoucherSessionManager.instance.statusNotifier,
      builder: (context, status, _) {
        if (!VoucherSessionManager.instance.isReadOnlyMode) {
          return const SizedBox.shrink();
        }
        final cs = Theme.of(context).colorScheme;
        return Container(
          width: double.infinity,
          color: cs.errorContainer,
          padding: const EdgeInsetsDirectional.fromSTEB(14, 10, 14, 10),
          child: Row(
            children: [
              Icon(Icons.lock_outline, color: cs.onErrorContainer),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      loc.voucherReadOnlyBannerTitle,
                      style: TextStyle(
                        color: cs.onErrorContainer,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      loc.voucherReadOnlyBannerBody,
                      style: TextStyle(
                        color: cs.onErrorContainer,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.confirmation_number_outlined, size: 18),
                label: Text(loc.voucherReadOnlyBannerAction),
                onPressed: onOpenActivation,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// حوار احتفالي عند عرض حالة اشتراك سارية — أيقونة كبيرة وأنيميشن خفيف.
class _ActivationCelebrationDialogBody extends StatefulWidget {
  const _ActivationCelebrationDialogBody({
    required this.headline,
    required this.congratsLine,
    required this.subscriptionEmail,
    required this.registeredEmailCaption,
    required this.fallbackSubtitle,
    required this.statusText,
    required this.statusColor,
    required this.subLine,
    required this.holderLine,
    required this.closeLabel,
    required this.isDark,
    required this.onClose,
  });

  final String headline;
  final String congratsLine;
  final String? subscriptionEmail;
  final String registeredEmailCaption;
  final String fallbackSubtitle;
  final String statusText;
  final Color statusColor;
  final String subLine;
  final String? holderLine;
  final String closeLabel;
  final bool isDark;
  final VoidCallback onClose;

  @override
  State<_ActivationCelebrationDialogBody> createState() =>
      _ActivationCelebrationDialogBodyState();
}

class _ActivationCelebrationDialogBodyState
    extends State<_ActivationCelebrationDialogBody>
    with TickerProviderStateMixin {
  late AnimationController _bounce;
  late AnimationController _burst;
  late Animation<double> _bounceAnim;

  @override
  void initState() {
    super.initState();
    _bounce = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 780),
    )..forward();
    _bounceAnim = CurvedAnimation(parent: _bounce, curve: Curves.elasticOut);
    _burst = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 920),
    )..forward();
  }

  @override
  void dispose() {
    _bounce.dispose();
    _burst.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final muted = widget.isDark ? Colors.grey.shade400 : Colors.grey.shade700;
    final cs = Theme.of(context).colorScheme;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 380),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 172,
              width: double.infinity,
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  AnimatedBuilder(
                    animation: _burst,
                    builder: (_, __) {
                      final v = Curves.easeOutCubic.transform(_burst.value);
                      return Stack(
                        alignment: Alignment.center,
                        clipBehavior: Clip.none,
                        children: [
                          for (var i = 0; i < 12; i++)
                            Transform.translate(
                              offset: Offset(
                                math.cos(math.pi * 2 * i / 12) * 56 * v,
                                math.sin(math.pi * 2 * i / 12) * 56 * v,
                              ),
                              child: Opacity(
                                opacity: v < 0.02
                                    ? 0
                                    : (1 - v * 0.45).clamp(0.0, 1.0),
                                child: Icon(
                                  i.isEven
                                      ? Icons.auto_awesome_rounded
                                      : Icons.star_rounded,
                                  size: 14.0 + (i % 4) * 3,
                                  color: Colors.amber.shade700,
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                  ScaleTransition(
                    scale: _bounceAnim,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            Colors.green.shade400,
                            Colors.green.shade800,
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.green.withValues(alpha: 0.55),
                            blurRadius: 32,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: const Padding(
                        padding: EdgeInsets.all(28),
                        child: Icon(
                          Icons.verified_rounded,
                          size: 78,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Text(
              widget.congratsLine,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Colors.green.shade700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.headline,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.8,
                height: 1.05,
                color: cs.onSurface,
              ),
            ),
            if (widget.holderLine != null) ...[
              const SizedBox(height: 10),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.teal.withValues(
                    alpha: widget.isDark ? 0.22 : 0.12,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: Text(
                    widget.holderLine!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: widget.isDark
                          ? Colors.teal.shade100
                          : Colors.teal.shade900,
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 8),
            widget.subscriptionEmail != null &&
                    widget.subscriptionEmail!.trim().isNotEmpty
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        widget.registeredEmailCaption,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: muted,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.alternate_email_rounded,
                            size: 18,
                            color: muted,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Directionality(
                              textDirection: ui.TextDirection.ltr,
                              child: Text(
                                widget.subscriptionEmail!.trim(),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: cs.onSurface,
                                  letterSpacing: 0.2,
                                  height: 1.25,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  )
                : Text(
                    widget.fallbackSubtitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: muted,
                      height: 1.35,
                    ),
                  ),
            const SizedBox(height: 14),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      widget.statusText,
                      style: TextStyle(
                        color: widget.statusColor,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                    if (widget.subLine.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        widget.subLine,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          height: 1.35,
                          color: muted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: Colors.green.shade700,
                  foregroundColor: Colors.white,
                ),
                onPressed: widget.onClose,
                child: Text(widget.closeLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// نافذة «تحديث البرنامج» بتصميم حديث (تدرج، بطاقات حالة، تبويب تفاصيل).
class _ModernProgramUpdateDialog extends StatefulWidget {
  const _ModernProgramUpdateDialog({
    required this.onClose,
    required this.onWhatsApp,
    required this.onOpenDownload,
    required this.onBackupBeforeUpdate,
  });

  final VoidCallback onClose;
  final VoidCallback onWhatsApp;
  final VoidCallback onOpenDownload;
  final Future<bool> Function() onBackupBeforeUpdate;

  @override
  State<_ModernProgramUpdateDialog> createState() =>
      _ModernProgramUpdateDialogState();
}

class _ModernProgramUpdateDialogState
    extends State<_ModernProgramUpdateDialog> {
  late final Future<
      ({
        PackageInfo pkg,
        AppUpdateManifest? newer,
        bool didCheckRemote,
        bool remoteCheckFailed,
      })> _stateFuture;
  int _segment = 0;
  bool _installingUpdate = false;
  double? _installProgress;
  String? _installError;

  @override
  void initState() {
    super.initState();
    _stateFuture = _loadUpdateState();
  }

  Future<
      ({
        PackageInfo pkg,
        AppUpdateManifest? newer,
        bool didCheckRemote,
        bool remoteCheckFailed,
      })> _loadUpdateState() async {
    final pkg = await PackageInfo.fromPlatform();
    if (!RemoteUpdateConfig.enabled) {
      return (
        pkg: pkg,
        newer: null,
        didCheckRemote: false,
        remoteCheckFailed: false,
      );
    }
    if (!Platform.isWindows && !Platform.isAndroid) {
      return (
        pkg: pkg,
        newer: null,
        didCheckRemote: false,
        remoteCheckFailed: false,
      );
    }
    final remote = await AppUpdateService.fetchManifest();
    if (remote == null) {
      return (
        pkg: pkg,
        newer: null,
        didCheckRemote: false,
        remoteCheckFailed: true,
      );
    }
    final newer = await AppUpdateService.newerThanInstalledFromManifest(remote);
    return (
      pkg: pkg,
      newer: newer,
      didCheckRemote: true,
      remoteCheckFailed: false,
    );
  }

  String? _releaseNotesForLocale(AppLocalizations loc, AppUpdateManifest m) {
    final ar = m.notesAr?.trim();
    final en = m.notesEn?.trim();
    if (loc.locale.languageCode == 'en') {
      if (en != null && en.isNotEmpty) return en;
      if (ar != null && ar.isNotEmpty) return ar;
    } else {
      if (ar != null && ar.isNotEmpty) return ar;
      if (en != null && en.isNotEmpty) return en;
    }
    return null;
  }

  Future<bool> _ensureBackupBeforeUpdate() async {
    final loc = AppLocalizations.of(context);
    final proceed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.backup_rounded),
        title: Text(loc.updateBackupRequiredTitle),
        content: Text(loc.updateBackupRequiredBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(loc.cancel),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.backup_outlined, size: 20),
            label: Text(loc.updateBackupRequiredAction),
          ),
        ],
      ),
    );
    if (proceed != true || !mounted) return false;

    final backedUp = await widget.onBackupBeforeUpdate();
    if (!mounted) return false;
    if (!backedUp) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.updateBackupRequiredSkipped)),
      );
    }
    return backedUp;
  }

  Future<bool> _ensureAndroidInstallPermission() async {
    if (!Platform.isAndroid) return true;
    if (await AndroidApkInstall.canInstallPackages()) return true;

    final loc = AppLocalizations.of(context);
    final open = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.install_mobile_rounded),
        title: Text(loc.updateInstallPermissionTitle),
        content: Text(loc.updateInstallPermissionBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(loc.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(loc.updateInstallPermissionAction),
          ),
        ],
      ),
    );
    if (open != true || !mounted) return false;

    await AndroidApkInstall.openInstallPermissionSettings();
    if (await AndroidApkInstall.waitForInstallPermission()) return true;
    if (!mounted) return false;

    final retry = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.updateInstallPermissionTitle),
        content: Text(loc.updateInstallPermissionStillDenied),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(loc.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(loc.updateInstallPermissionAction),
          ),
        ],
      ),
    );
    if (retry == true && mounted) {
      return _ensureAndroidInstallPermission();
    }
    return false;
  }

  Future<void> _startInAppInstall(AppUpdateManifest manifest) async {
    if (_installingUpdate || !mounted) return;
    if (!await _ensureBackupBeforeUpdate()) return;

    final loc = AppLocalizations.of(context);
    final confirmBody = Platform.isAndroid
        ? loc.updateInAppInstallConfirmBodyAndroid
        : loc.updateInAppInstallConfirmBody;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.updateInAppInstallConfirmTitle),
        content: Text(confirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(loc.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(loc.continueLabel),
          ),
        ],
      ),
    );
    if (go != true || !mounted) return;

    if (Platform.isAndroid && !await _ensureAndroidInstallPermission()) {
      return;
    }

    setState(() {
      _installingUpdate = true;
      _installProgress = 0;
      _installError = null;
    });

    final downloadUrl = manifest.resolveDownloadUrl();
    try {
      if (Platform.isAndroid) {
        await AppUpdateService.downloadAndOpenAndroidApk(
          downloadUrl,
          onProgress: (p) {
            if (!mounted) return;
            setState(() => _installProgress = p);
          },
        );
        if (mounted) {
          setState(() {
            _installingUpdate = false;
            _installProgress = 1;
          });
        }
      } else {
        await AppUpdateService.downloadAndRunInstaller(
          downloadUrl,
          onProgress: (p) {
            if (!mounted) return;
            setState(() => _installProgress = p);
          },
        );
      }
    } on ApkInstallPermissionDeniedException {
      if (!mounted) return;
      setState(() {
        _installError = loc.updateInstallPermissionRequired;
        _installingUpdate = false;
      });
    } on ApkInstallIncompatibleException catch (e) {
      if (!mounted) return;
      final friendly = e.code.startsWith('PACKAGE_MISMATCH')
          ? loc.updateApkPackageMismatch
          : loc.updateApkSignatureMismatch;
      setState(() {
        _installError = friendly;
        _installingUpdate = false;
      });
    } on Object catch (e) {
      if (!mounted) return;
      final msg = '$e';
      final friendly = msg.contains('REQUEST_INSTALL_PACKAGES')
          ? loc.updateInstallPermissionRequired
          : loc.updateInAppInstallFailed(msg);
      setState(() {
        _installError = friendly;
        _installingUpdate = false;
      });
    }
  }

  Widget _segmentChip({
    required ThemeData theme,
    required ColorScheme cs,
    required int index,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final sel = _segment == index;
    return Expanded(
      child: Material(
        color: sel
            ? cs.primaryContainer.withValues(alpha: 0.55)
            : cs.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: sel ? cs.primary : cs.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: sel ? FontWeight.w800 : FontWeight.w600,
                      color: sel ? cs.onPrimaryContainer : cs.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _detailTile(
    ThemeData theme,
    ColorScheme cs, {
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
          color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
        ),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 14, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Icon(icon, size: 22, color: cs.primary),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: cs.primary,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      value,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final bodyStyle = theme.textTheme.bodyMedium?.copyWith(
      height: 1.52,
      fontWeight: FontWeight.w500,
    );

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Material(
          color: cs.surface,
          elevation: 8,
          shadowColor: Colors.black.withValues(alpha: 0.22),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
            side: BorderSide(color: cs.outline.withValues(alpha: 0.12)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                    colors: [
                      Color(0xFF2563EB),
                      Color(0xFF1D4ED8),
                      Color(0xFF0EA5E9),
                    ],
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(18, 18, 12, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Icon(
                              Icons.system_update_rounded,
                              color: Colors.white,
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  loc.menuProgramUpdate,
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    height: 1.15,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  loc.updateDialogHeroSubtitle,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: Colors.white.withValues(alpha: 0.92),
                                    fontWeight: FontWeight.w600,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: loc.close,
                            onPressed: widget.onClose,
                            style: IconButton.styleFrom(
                              foregroundColor: Colors.white,
                            ),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    _segmentChip(
                      theme: theme,
                      cs: cs,
                      index: 0,
                      icon: Icons.system_update_alt_rounded,
                      label: loc.updateSegmentUpdate,
                      onTap: () => setState(() => _segment = 0),
                    ),
                    const SizedBox(width: 10),
                    _segmentChip(
                      theme: theme,
                      cs: cs,
                      index: 1,
                      icon: Icons.info_outline_rounded,
                      label: loc.updateSegmentDetails,
                      onTap: () => setState(() => _segment = 1),
                    ),
                  ],
                ),
              ),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.52,
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
                  child: _segment == 0
                      ? _buildUpdateTab(context, loc, theme, cs, bodyStyle)
                      : _buildDetailsTab(context, loc, theme, cs),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: OutlinedButton(
                  onPressed: widget.onClose,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(loc.close),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUpdateTab(
    BuildContext context,
    AppLocalizations loc,
    ThemeData theme,
    ColorScheme cs,
    TextStyle? bodyStyle,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FutureBuilder<
            ({
              PackageInfo pkg,
              AppUpdateManifest? newer,
              bool didCheckRemote,
              bool remoteCheckFailed,
            })>(
          future: _stateFuture,
          builder: (ctx, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Column(
                  children: [
                    const SizedBox(
                      height: 4,
                      child: LinearProgressIndicator(minHeight: 4),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      loc.updateCheckingStatus,
                      textAlign: TextAlign.center,
                      style: bodyStyle?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              );
            }
            if (snap.hasError || !snap.hasData) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(loc.updateDetailsLoadError, style: bodyStyle),
              );
            }
            final data = snap.data!;
            final pkg = data.pkg;
            final newer = data.newer;
            final checked = data.didCheckRemote;
            final remoteCheckFailed = data.remoteCheckFailed;
            final installedVersion = pkg.buildNumber.trim().isEmpty
                ? pkg.version
                : '${pkg.version}+${pkg.buildNumber}';

            if (checked && newer != null) {
              final notes = _releaseNotesForLocale(loc, newer);
              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color(0xFF059669),
                            Color(0xFF0D9488),
                            Color(0xFF0891B2),
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color:
                                const Color(0xFF059669).withValues(alpha: 0.28),
                            blurRadius: 18,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.22),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    loc.updateAvailableBadge,
                                    style: theme.textTheme.labelLarge?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                Icon(
                                  Icons.rocket_launch_rounded,
                                  color: Colors.white.withValues(alpha: 0.9),
                                  size: 26,
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              loc.updateInAppAvailableLine(
                                AppUpdateManifest.formatForDisplay(
                                  newer.latestVersion,
                                ),
                              ),
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                height: 1.3,
                              ),
                            ),
                            if (notes != null) ...[
                              const SizedBox(height: 12),
                              Text(
                                loc.updateReleaseNotesTitle,
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.9),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                notes,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.95),
                                  height: 1.45,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: const Color(0xFF047857),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              onPressed: _installingUpdate
                                  ? null
                                  : () => _startInAppInstall(newer),
                              icon: const Icon(Icons.download_done_rounded),
                              label: Text(loc.updateInAppInstallButton),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }

            if (checked && newer == null) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        color: cs.primaryContainer.withValues(alpha: 0.38),
                        border: Border.all(
                          color: cs.primary.withValues(alpha: 0.22),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.verified_rounded,
                              color: cs.primary,
                              size: 36,
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    loc.updateUpToDateTitle,
                                    style:
                                        theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: cs.onPrimaryContainer,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    loc.updateUpToDateBody(installedVersion),
                                    style: bodyStyle?.copyWith(
                                      color: cs.onPrimaryContainer
                                          .withValues(alpha: 0.9),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }

            if (remoteCheckFailed) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        color: cs.errorContainer.withValues(alpha: 0.35),
                        border: Border.all(
                          color: cs.error.withValues(alpha: 0.24),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.wifi_off_rounded,
                              color: cs.error,
                              size: 34,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    loc.updateCheckFailedTitle,
                                    style:
                                        theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: cs.onErrorContainer,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    loc.updateCheckFailedBody,
                                    style: bodyStyle?.copyWith(
                                      color: cs.onErrorContainer
                                          .withValues(alpha: 0.92),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }

            return const SizedBox.shrink();
          },
        ),
        if (_installingUpdate || _installError != null) ...[
          const SizedBox(height: 10),
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: _installError == null
                  ? cs.primaryContainer.withValues(alpha: 0.45)
                  : cs.errorContainer.withValues(alpha: 0.45),
              border: Border.all(
                color: _installError == null
                    ? cs.primary.withValues(alpha: 0.28)
                    : cs.error.withValues(alpha: 0.28),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_installError == null) ...[
                    LinearProgressIndicator(
                      minHeight: 8,
                      borderRadius: BorderRadius.circular(999),
                      value: _installProgress,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _installProgress == null
                          ? loc.updateInAppDownloadProgressUnknown
                          : loc.updateInAppDownloadProgress(
                              (_installProgress! * 100).toStringAsFixed(0),
                            ),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ] else ...[
                    Text(
                      _installError!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onErrorContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (Platform.isAndroid &&
                        _installError ==
                            loc.updateInstallPermissionRequired) ...[
                      const SizedBox(height: 10),
                      FilledButton.icon(
                        onPressed: _installingUpdate
                            ? null
                            : () => unawaited(
                                  _ensureAndroidInstallPermission(),
                                ),
                        icon: const Icon(Icons.settings_rounded, size: 20),
                        label: Text(loc.updateInstallPermissionAction),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 8),
        FilledButton.tonalIcon(
          onPressed: _installingUpdate ? null : widget.onWhatsApp,
          icon: const Icon(Icons.chat_rounded),
          label: Text(loc.updatePanelWhatsApp),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _installingUpdate ? null : widget.onOpenDownload,
          icon: const Icon(Icons.download_rounded),
          label: Text(loc.updatePanelOpenDownload),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDetailsTab(
    BuildContext context,
    AppLocalizations loc,
    ThemeData theme,
    ColorScheme cs,
  ) {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (ctx, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snap.hasError || !snap.hasData) {
          return Text(loc.updateDetailsLoadError);
        }
        final p = snap.data!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              loc.updateCurrentVersionLabel,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: cs.primary,
              ),
            ),
            const SizedBox(height: 10),
            _detailTile(
              theme,
              cs,
              icon: Icons.apps_rounded,
              label: loc.updateDetailsPackageLabel,
              value: p.packageName,
            ),
            _detailTile(
              theme,
              cs,
              icon: Icons.tag_rounded,
              label: loc.updateDetailsVersionLabel,
              value: p.version,
            ),
            _detailTile(
              theme,
              cs,
              icon: Icons.build_circle_outlined,
              label: loc.updateDetailsBuildLabel,
              value: p.buildNumber,
            ),
            _detailTile(
              theme,
              cs,
              icon: Icons.laptop_windows_rounded,
              label: loc.updateDetailsPlatformLabel,
              value:
                  '${Platform.operatingSystem} (${Platform.operatingSystemVersion})',
            ),
          ],
        );
      },
    );
  }
}

class _FactoryResetConfirmDialog extends StatefulWidget {
  const _FactoryResetConfirmDialog({
    required this.phrase,
    required this.isEnglish,
    required this.loc,
  });

  final String phrase;
  final bool isEnglish;
  final AppLocalizations loc;

  @override
  State<_FactoryResetConfirmDialog> createState() =>
      _FactoryResetConfirmDialogState();
}

class _FactoryResetConfirmDialogState extends State<_FactoryResetConfirmDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final typed = _controller.text.trim();
    final matches = widget.isEnglish
        ? typed.toUpperCase() == widget.phrase.toUpperCase()
        : typed == widget.phrase;
    return AlertDialog(
      icon: Icon(Icons.warning_amber_rounded, color: scheme.error, size: 40),
      title: Text(widget.loc.factoryResetTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.loc.factoryResetBody,
              style: const TextStyle(height: 1.45),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                labelText: widget.phrase,
                border: const OutlineInputBorder(),
                errorText: typed.isEmpty || matches
                    ? null
                    : (widget.isEnglish
                        ? 'Phrase does not match'
                        : 'العبارة غير مطابقة'),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(widget.loc.cancel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: scheme.error,
            foregroundColor: scheme.onError,
          ),
          onPressed: matches ? () => Navigator.pop(context, true) : null,
          child: Text(widget.loc.factoryResetConfirmButton),
        ),
      ],
    );
  }
}
