import 'package:flutter/material.dart';
import 'package:mizapos_desktop/models/dashboard_kpi_period.dart';
import 'package:mizapos_desktop/models/miza_payment_types.dart';
import 'package:mizapos_desktop/security/security_preferences.dart';
import 'package:mizapos_desktop/services/excel_import_service.dart';

/// ترجمات الواجهة (عربي / إنجليزي) بدون codegen.
class AppLocalizations {
  AppLocalizations(this.locale);

  final Locale locale;

  bool get _en => locale.languageCode == 'en';

  /// واجهة عامة للتعرف على لغة الواجهة الحالية. مفيدة للودجتات التي
  /// تحمل أسماء/بيانات ثنائية اللغة (مثل أسماء الدول في `CountryFlag`).
  bool get isEnglish => _en;

  String _t(String ar, String en) => _en ? en : ar;

  static AppLocalizations of(BuildContext context) {
    final l = Localizations.of<AppLocalizations>(context, AppLocalizations);
    assert(l != null, 'AppLocalizations not found');
    return l!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  String securityPerm(String key) =>
      _en ? SecurityPermissions.labelEn(key) : SecurityPermissions.labelAr(key);

  String securityRole(String role) => _en
      ? SecurityPermissions.roleLabelEn(role)
      : SecurityPermissions.roleLabelAr(role);

  String dashboardTileTitle(String key) {
    switch (key) {
      case 'sales':
        return navSales;
      case 'purchases':
        return navPurchases;
      case 'customers':
        return navCustomers;
      case 'suppliers':
        return navSuppliers;
      case 'cash':
        return navCash;
      case 'expenses':
        return navExpenses;
      case 'inventory':
        return navInventory;
      case 'queries':
        return navQueries;
      case 'miza_cloud':
        return menuMizaCloud;
      case 'quick_notes':
        return homeQuickNotesTitle;
      default:
        return key;
    }
  }

  /// وصف قصير تحت عنوان مربّع لوحة التحكم (واجهة فقط).
  String dashboardTileSubtitle(String key) {
    switch (key) {
      case 'sales':
        return _t(
          'إنشاء فواتير البيع والمرتجعات والتحصيل',
          'Create sales invoices, returns, and collections',
        );
      case 'purchases':
        return _t(
          'فواتير الشراء والمرتجعات ومدفوعات الموردين',
          'Purchase invoices, returns, and supplier payments',
        );
      case 'customers':
        return _t(
          'إدارة بيانات العملاء والأرصدة والفواتير',
          'Manage customers, balances, and invoices',
        );
      case 'suppliers':
        return _t(
          'بيانات الموردين والمشتريات والمدفوعات',
          'Suppliers, purchases, and payments',
        );
      case 'cash':
        return _t(
          'إدارة حركة الصندوق والإيرادات والمصروفات',
          'Cash movements, income, and expenses',
        );
      case 'expenses':
        return _t(
          'تسجيل ومتابعة مصاريف التشغيل اليومية',
          'Record and track daily operating expenses',
        );
      case 'inventory':
        return _t(
          'متابعة الأصناف والكميات والحركات',
          'Track items, quantities, and stock movements',
        );
      case 'queries':
        return _t(
          'تقارير وإحصائيات وتحليلات النظام',
          'Reports, statistics, and system analytics',
        );
      case 'miza_cloud':
        return _t(
          'مزامنة البيانات بين جميع الأجهزة',
          'Sync data across all your devices',
        );
      case 'quick_notes':
        return _t(
          'تسجيل الملاحظات والمهام اليومية',
          'Capture daily notes and tasks',
        );
      default:
        return '';
    }
  }

  String themeColorLabel(String key) {
    switch (key) {
      case 'blue':
        return themeBlue;
      case 'teal':
        return themeTeal;
      case 'purple':
        return themePurple;
      case 'orange':
        return themeOrange;
      case 'rose':
        return themeRose;
      default:
        return key;
    }
  }

  // --- عام ---
  String get appTitle => _t('MizaPos', 'MizaPos');
  String get cancel => _t('إلغاء', 'Cancel');
  String get save => _t('حفظ', 'Save');
  String get close => _t('إغلاق', 'Close');
  String get delete => _t('حذف', 'Delete');
  String get continueLabel => _t('متابعة', 'Continue');
  String get login => _t('تسجيل الدخول', 'Sign in');
  String get logout => _t('تسجيل خروج', 'Sign out');
  String get username => _t('اسم الدخول', 'Username');
  String get password => _t('كلمة المرور', 'Password');
  String get enterAction => _t('دخول', 'Enter');

  String get welcomeTitle => _t('MizaPos للمحاسبة', 'MizaPos Accounting');

  /// ترحيب شاشة الإقلاع حسب الساعة المحلية للجهاز.
  String splashStartupGreeting(DateTime now) {
    final h = now.hour;
    if (_en) {
      if (h >= 5 && h < 12) return 'Good morning';
      if (h >= 12 && h < 17) return 'Good afternoon';
      if (h >= 17 && h < 22) return 'Good evening';
      return 'Welcome';
    }
    if (h >= 5 && h < 12) return 'صباح الخير';
    if (h >= 12 && h < 22) return 'مساء الخير';
    return 'مرحباً';
  }

  /// مقدمة الإقلاع أسفل الشعار.
  String get splashIntroHeadline => _t(
        'محاسبة ونقطة بيع — ببساطة واحترافية',
        'Accounting & point of sale — clear and capable.',
      );
  String get splashIntroSubline => _t(
        'مبيعات، مشتريات، صندوق، وذمم في مكان واحد.',
        'Sales, purchases, cash, and partner balances in one place.',
      );
  String get splashLoadingHint =>
      _t('جارٍ تجهيز البيانات…', 'Preparing your workspace…');
  String usernameColonLabel(String name) =>
      _en ? 'Username: $name' : 'اسم الدخول: $name';
  String get usernameTrailing => _t('اسم الدخول: ', 'Username: ');
  String get systemAdmin => _t('إدارة النظام', 'System admin');
  String get quickSearchTooltip =>
      _t('بحث سريع (Ctrl+K)', 'Quick search (Ctrl+K)');
  String get lowStockTooltip => _t('تنبيه المخزون المنخفض', 'Low stock alert');
  String get notificationsCenterTooltip => _t(
        'مركز الإشعارات (مخزون، ذمم موردين، تحديث)',
        'Notifications (stock, supplier dues, updates)',
      );
  String get themeLightTooltip => _t('الوضع الفاتح', 'Light mode');
  String get themeDarkTooltip => _t('الوضع الداكن', 'Dark mode');
  String get refreshKpisTooltip => _t('تحديث المؤشرات', 'Refresh KPIs');
  String get backupTooltip => _t('نسخة احتياطية', 'Backup');
  String backupCreatedSnack(String path) =>
      _en ? 'Backup created: $path' : 'تم إنشاء النسخة الاحتياطية: $path';
  String get kpisUpdated => _t('تم تحديث المؤشرات.', 'KPIs updated.');
  String lowStockSnack(int count) => _en
      ? 'Alert: $count item(s) at or below low-stock threshold.'
      : 'تنبيه: يوجد $count صنفًا ضمن حدود المخزون المنخفض.';
  String get adminBroadcastBannerClose =>
      _t('إغلاق الإشعار', 'Dismiss notice');
  String get notificationsSectionAdminBroadcast => _t(
        'رسالة من إدارة التفعيل',
        'Message from activation admin',
      );
  String get notificationsNoneAdminBroadcast => _t(
        'لا توجد رسالة إدارية جديدة.',
        'No new admin message.',
      );
  String get viewAction => _t('عرض', 'View');

  String get homeQuickCalculatorTitle => _t('آلة حاسبة', 'Calculator');
  String get homeCalculatorClear => _t('مسح', 'AC');
  String get homeQuickCalculatorTooltip =>
      _t('فتح آلة حاسبة', 'Open calculator');
  String get homeQuickNotesTooltip =>
      _t('مفكرة ملاحظات سريعة', 'Quick notepad');
  String get homeQuickNotesTitle => _t('مفكرة سريعة', 'Quick notepad');
  String get homeQuickNotesHint => _t(
        'اكتب تفاصيل الملاحظة هنا… نواقص، طلبات، ملاحظات زبائن',
        'Write note details… shortages, orders, customer notes',
      );
  String get homeQuickNotesSaved => _t('تم حفظ الملاحظات.', 'Notes saved.');
  String get quickNotesSmartSubtitle =>
      _t('ملاحظات مرتّبة وقابلة للتثبيت', 'Organized, pinnable notes');
  String get quickNotesSearchHint =>
      _t('بحث في الملاحظات…', 'Search notes…');
  String get quickNotesNew => _t('ملاحظة جديدة', 'New note');
  String get quickNotesEmptyList =>
      _t('لا توجد ملاحظات مطابقة', 'No matching notes');
  String get quickNotesTitleHint =>
      _t('عنوان الملاحظة', 'Note title');
  String get quickNotesPickOrCreate => _t(
        'اختر ملاحظة أو أنشئ واحدة جديدة',
        'Pick a note or create a new one',
      );
  String get quickNotesPin => _t('تثبيت', 'Pin');
  String get quickNotesUnpin => _t('إلغاء التثبيت', 'Unpin');
  String get quickNotesDeleteTitle =>
      _t('حذف الملاحظة؟', 'Delete note?');
  String get quickNotesDeleteBody => _t(
        'سيتم حذف هذه الملاحظة نهائياً.',
        'This note will be permanently deleted.',
      );
  String get quickNotesLimitReached => _t(
        'وصلت إلى الحد الأقصى لعدد الملاحظات.',
        'You reached the maximum number of notes.',
      );
  String get quickNotesTagGeneral => _t('عام', 'General');
  String get quickNotesTagShortage => _t('نقص', 'Shortage');
  String get quickNotesTagOrder => _t('طلب', 'Order');
  String get quickNotesTagCustomer => _t('زبون', 'Customer');
  String get quickNotesJustNow => _t('الآن', 'Just now');
  String quickNotesMinutesAgo(int m) =>
      _t('منذ $m د', '$m min ago');
  String quickNotesHoursAgo(int h) =>
      _t('منذ $h س', '$h h ago');
  String quickNotesDaysAgo(int d) =>
      _t('منذ $d ي', '$d d ago');

  String get homeDistributorsHubTitle =>
      _t('منظومة الموزعون', 'Distributors hub');

  String get homeDistributorsHubTooltip => _t(
        'تحميل السيارات ومبيعات الميدان والتقارير',
        'Vehicle loads, field sales, and reports',
      );

  String get subscriptionPlanTitle =>
      _t('خطة اشتراك MizaPos', 'MizaPos subscription plan');

  /// سطر مختصر للسعر — يُعرض تحت زر «تفعيل الاشتراك» في الشريط السفلي.
  String get subscriptionPlanPriceShort => _t(
        '70 \$ · سنوياً · حاسوب + أندرويد',
        '\$70 · yearly · PC + Android',
      );

  /// عنوان فرعي أوضح في بطاقة الخطة.
  String get subscriptionPlanPriceHeadline => _t(
        '70 دولار سنوياً — حاسوب ويندوز + جوال أندرويد',
        'USD 70 per year — Windows PC + Android mobile',
      );

  /// شعار الخطّة الأساسي.
  String get subscriptionPlanBadgeOneTime =>
      _t('اشتراك سنوي', 'Annual subscription');

  String get subscriptionPlanBadgeNoRecurring => _t(
        'تجديد سنوي — بدون اشتراك شهري',
        'Yearly renewal — no monthly billing',
      );

  /// السعر معروض كرقم + رمز العملة بصيغة موحّدة. القيمة ثابتة حاليّاً.
  String get subscriptionPlanPriceAmount => '70';

  String get subscriptionPlanPriceCurrency => _t('دولار', 'USD');

  String get subscriptionPlanPriceSuffix => _t('/ سنة', '/ year');

  String get subscriptionPlanIncludesTitle =>
      _t('يشمل الاشتراك السنوي:', 'Annual plan includes:');

  String get subscriptionPlanDevicesLabel =>
      _t('حاسوب + أندرويد', 'PC + Android');

  String get subscriptionPlanDeviceWindows => _t('حاسوب ويندوز', 'Windows PC');

  String get subscriptionPlanDeviceAndroid =>
      _t('جوال أندرويد', 'Android mobile');

  String get subscriptionPlanFootnote => _t(
        'اشتراك سنوي واحد يشمل نسخة الحاسوب ونسخة الجوال لنفس الحساب.',
        'One annual subscription covers desktop and mobile for the same account.',
      );

  String get subscriptionPlanCloudAddonTitle => _t(
        'إضافة اختيارية — سحابة الموزّعين',
        'Optional add-on — Distributor cloud',
      );

  String get subscriptionPlanCloudAddonPrice => _t(
        '50 \$ / سنة',
        '\$50 / year',
      );

  String get subscriptionPlanCloudAddonBody => _t(
        'منفصلة عن قسيمة POS — مزامنة الميدان مع 10 أجهزة جوال.',
        'Separate from POS voucher — field sync with up to 10 mobile devices.',
      );

  String get homeCalendarAppointmentsTitle =>
      _t('التقويم والمواعيد', 'Calendar & reminders');

  String get homeCalendarTooltip => _t(
        'تقويم شهري وتذكيرات يومية (لا تُربط تلقائياً بفواتير البرنامج)',
        'Monthly calendar and daily reminders (not linked to invoices)',
      );

  String homeCalendarAppointmentsFor(String dayLabel) =>
      _en ? 'Reminders for $dayLabel' : 'المواعيد — $dayLabel';

  String get homeCalendarNoAppointments =>
      _t('لا توجد مواعيد لهذا اليوم.', 'No reminders for this day.');

  String get homeCalendarAppointmentTitleLabel => _t('عنوان الموعد', 'Title');

  String get homeCalendarAppointmentNoteLabel =>
      _t('ملاحظة (اختياري)', 'Note (optional)');

  String get homeCalendarAdd => _t('إضافة موعد', 'Add reminder');

  String get homeCalendarTitleRequired =>
      _t('يرجى إدخال عنوان للموعد.', 'Please enter a title.');

  String get homeCalendarSaved => _t('تم حفظ الموعد.', 'Reminder saved.');

  String get homeCalendarRemindAt =>
      _t('تنبيه بوقت محدد', 'Alert at a set time');
  String get homeCalendarRemindAtSub => _t(
        'يُعرض إشعار وصوت عند حلول الساعة (فعّل «تنبيهات موعد التقويم» و«تشغيل الأصوات» من الإعدادات عند الحاجة).',
        'Shows a notification and sound when the time is reached (enable calendar alerts and sounds in Settings as needed).',
      );
  String get homeCalendarPickTime => _t('الساعة', 'Time');

  // --- تحويل العملة (شريط سفلي) ---

  String get homeCurrencyConverterTitle =>
      _t('تحويل العملة', 'Currency converter');

  String get homeCurrencyConverterTooltip => _t(
        'تحويل سريع بسعر يدوي (للمراجعة — لا يُسجّل في الحسابات)',
        'Quick conversion with a manual rate (reference only — not booked)',
      );

  String homeCurrencyConverterHint(String storeCurrency) => _t(
        'عملة المتجر الحالية: $storeCurrency. أدخل سعر الصرف كما يظهر في سوق الصرف أو عقدك (مثلاً: 1 دولار = كم وحدة بعملة المتجر).',
        'Store currency: $storeCurrency. Enter the rate as you use it (e.g. how many store units equal 1 unit of the foreign currency).',
      );

  String get homeCurrencyForeignLabel =>
      _t('العملة الأجنبية', 'Foreign currency');

  String get homeCurrencyAmountForeign =>
      _t('المبلغ بالعملة الأجنبية', 'Amount in foreign currency');

  String homeCurrencyRateLabel(String storeCurrency) => _t(
        'سعر الصرف (1 أجنبي = ؟ $storeCurrency)',
        'Exchange rate (1 foreign = ? $storeCurrency)',
      );

  String get homeCurrencyRateHelper => _t(
        'مثال: إذا 1 دولار = 3.50 جنيه أدخل 3.50',
        'Example: if 1 USD equals 3.50 in store currency, enter 3.50',
      );

  String get homeCurrencyResultInStore =>
      _t('المقابل بعملة المتجر', 'Equivalent in store currency');

  String homeCurrencyInverse(String store, String foreign) => _en
      ? 'Check: 1 $store equals how many $foreign?'
      : 'للمراجعة: كم تساوي 1 $store من $foreign؟';

  String get homeDateTimeNowTooltip =>
      _t('التاريخ والوقت الحاليان', 'Current date & time');

  String get navSales => _t('إدارة المبيعات', 'Sales management');
  String get navPurchases =>
      _t('إدارة المشتريات', 'Purchases management');
  String get navCustomers => _t('إدارة العملاء', 'Customer management');
  String get navSuppliers => _t('إدارة الموردين', 'Supplier management');

  /// شاشة الموردين الموحّدة (شريط أزرق + شريط تقارير + شريط تلميح + قائمة).
  String get suppliersToolbarHintShort => _t(
        'الأزرق: إجراءات يومية. الأبيض: تقارير الاستعلامات (نفس إدارة الاستعلامات) مع فترة من/إلى. أسفلها تلميح مختصر.',
        'Blue: daily actions. White: query reports (same as query management) with a from/to period. A short hint sits below.',
      );
  String get suppliersToolbarHintDetail => _t(
        'الشريط الأزرق: مورد جديد، «اختر التقرير»، وأيقونة الدفتر (ذمم الآجل، الأرصدة الافتتاحية والنقدي، المتبقي). بعد اختيار التقرير حدّد الفترة ثم اعرضه؛ قد يُطلب اختيار مورد.',
        'Blue bar: new supplier, «Pick report», and notebook menu (deferred AP, opening balances & cash, outstanding). After picking a report, set the period; some reports ask you to pick a supplier.',
      );
  String get suppliersToolbarHintDialogTitle =>
      _t('شرح شاشة إدارة الموردين', 'Suppliers screen');
  String get suppliersSearchFieldHint => _t(
        'بحث (اسم / هاتف / رقم مورد)',
        'Search (name / phone / supplier no.)',
      );
  String get suppliersChipNewSupplier => _t('مورد جديد', 'New supplier');
  String get suppliersChipOpeningBalances =>
      _t('الأرصدة الافتتاحية والنقدي', 'Opening balances & cash');
  String get suppliersChipDeferredBalances =>
      _t('ذمم الآجل', 'Deferred AP');
  String get suppliersChipBalanceCheck =>
      _t('فحص الأرصدة', 'Balance check');
  String get suppliersChipOutstandingReport =>
      _t('المتبقي', 'Outstanding');
  String get suppliersChipQueryReportsMenu =>
      _t('اختر التقرير', 'Pick report');
  String get suppliersQueryReportsMenuTitle =>
      _t('تقارير الموردين', 'Supplier reports');
  String get suppliersQueryReportsMenuHint => _t(
        'اختر التقرير ثم حدّد الفترة من داخل التقرير',
        'Pick a report, then set the date range inside it',
      );
  String get suppliersChipDirectoryFull =>
      _t('قائمة بملء الشاشة', 'Full-screen list');
  String get suppliersChipPdfPreview => _t('PDF', 'PDF');
  String get suppliersChipPdfPreviewTooltip => _t(
        'معاينة التقرير ثم حفظ أو طباعة من شريط المعاينة',
        'Preview the report, then save or print from the preview toolbar',
      );
  String get suppliersQueryReportsSectionTitle => _t(
        'تقارير الموردين',
        'Supplier reports',
      );
  String get suppliersQueryReportsPeriodCaption => _t(
        'يُحدَّد التاريخ عند اختيار التقرير',
        'Dates are set when you pick a report',
      );
  String get suppliersQueryReportsPeriodDialogTitle => _t(
        'فترة التقرير',
        'Report period',
      );
  String get suppliersQueryReportsShowReport =>
      _t('عرض التقرير', 'Show report');
  String get suppliersNoSuppliersAddFirst => _t(
        'لا يوجد موردون. أضف موردًا أولًا.',
        'No suppliers yet. Add a supplier first.',
      );

  String get navCash => _t('إدارة الصندوق', 'Cash management');
  String get cashToolbarHintShort => _t(
        'تحت العنوان: حركة الصندوق وتقرير PDF. سطر الإدخال: خصم/إضافة، المبلغ، التاريخ، حفظ.',
        'Below the title: cash flow and PDF report. Entry row: out/in, amount, date, save.',
      );
  String get cashToolbarHintDetail => _t(
        '«حركة الصندوق» يعرض التقرير بعد اختيار الفترة. «تقرير PDF» يفتح معاينة الحركة. الرصيد يتحدّث تلقائياً بعد الحفظ.',
        'Cash flow shows the report after you pick a period. PDF opens movement preview. Balance updates automatically after save.',
      );
  String get cashToolbarHintDialogTitle =>
      _t('شرح شاشة إدارة الصندوق', 'Cash screen');
  String get cashQueryReportsSectionTitle =>
      _t('تقارير الصندوق', 'Cash query reports');
  String get cashQueryReportsPeriodCaption => _t(
        'يُحدَّد التاريخ عند اختيار التقرير',
        'Dates are set when you pick a report',
      );
  String get cashChipRefreshBalance =>
      _t('تحديث الرصيد', 'Refresh balance');
  String get cashChipPdfMovement =>
      _t('تقرير PDF', 'PDF report');
  String get cashFormWithdraw =>
      _t('خصم من الصندوق', 'Withdraw from cash');
  String get cashFormDeposit =>
      _t('إضافة للصندوق', 'Add to cash');
  String get cashFormAmount => _t('المبلغ', 'Amount');
  String get cashFormDescription => _t('البيان', 'Description');
  String get cashFormBalanceTitle =>
      _t('رصيد الصندوق', 'Cash balance');
  String get cashTagSalesCustomers => _t(
        'إضافة مبالغ المبيعات والعملاء للصندوق',
        'Add sales and customer amounts to cash',
      );
  String get cashTagPurchasesSuppliers => _t(
        'خصم مبالغ المشتريات والموردين من الصندوق',
        'Deduct purchases and supplier amounts from cash',
      );
  String get cashTagExpenses => _t(
        'خصم مبالغ المصروفات من الصندوق',
        'Deduct expense amounts from cash',
      );
  String get cashSavedDeposit =>
      _t('تمت إضافة الصندوق.', 'Cash deposit recorded.');
  String get cashSavedWithdraw =>
      _t('تم الخصم من الصندوق.', 'Cash withdrawal recorded.');
  String get cashInvalidAmount => _t(
        'أدخل مبلغًا صحيحًا أكبر من صفر.',
        'Enter a valid amount greater than zero.',
      );
  String get cashMovementDefault =>
      _t('حركة صندوق', 'Cash movement');
  String get cashPdfOpenError => _t(
        'تعذر فتح التقرير',
        'Could not open report',
      );
  String get expChipPaymentsTable =>
      _t('جدول المصاريف', 'Expenses table');
  String get expChipExpenseLog =>
      _t('سجل المصاريف', 'Expense log');
  String get expToolbarHintShort => _t(
        'تحت العنوان: سجل المصاريف، تقرير حسب الحساب، وتقرير لحساب محدد — يُحدَّد التاريخ عند اختيار التقرير. ثم نموذج الإدخال.',
        'Below the title: expense log, report by account, and report for one account — dates when you pick a report. Then the entry form.',
      );
  String get expToolbarHintDetail => _t(
        'كل زر تقرير يطلب الفترة (من / إلى) ثم يعرض النتيجة داخل الصفحة. التصدير عبر PDF من شريط التقرير.',
        'Each report button asks for the period (from / to) then shows results inline. Export via PDF from the report bar.',
      );
  String get expToolbarHintDialogTitle =>
      _t('شرح شاشة إدارة المصاريف', 'Expenses screen');
  String get expQueryReportsSectionTitle =>
      _t('تقارير المصاريف', 'Expense query reports');
  String get expQueryReportsPeriodCaption => _t(
        'يُحدَّد التاريخ عند اختيار التقرير',
        'Dates are set when you pick a report',
      );
  String get navExpenses => _t('إدارة المصاريف', 'Expense management');
  /// تسمية قصيرة لطريقة الدفع النقدية في شاشة المصاريف (ليست عنوان الشاشة).
  String get expenseCashPaymentSegment => _t('نقدي', 'Cash');
  String get navInventory => _t('إدارة المخزون', 'Inventory management');
  String get navQueries =>
      _t('إدارة الاستعلامات', 'Query management');

  /// شاشة العملاء — رسائل مشتركة وثنائية اللغة.
  String get customersNoCustomersAddFirst => _t(
        'لا يوجد عملاء. أضف عميلًا أولًا.',
        'No customers yet. Add a customer first.',
      );
  String get customersNoCustomersRegistered => _t(
        'لا يوجد عملاء مسجلون.',
        'No registered customers.',
      );
  String customersLoadFailed(Object error) =>
      _en ? 'Could not load customers: $error' : 'تعذّر تحميل العملاء: $error';
  String get customersDeleteDialogTitle => _t('حذف العميل', 'Delete customer');
  String customersDeleteDialogBody(String name) => _en
      ? 'Delete "$name"? This cannot be undone.'
      : 'حذف «$name»؟ لا يمكن التراجع.';
  String customersDeleteFailed(Object error) =>
      _en ? 'Could not delete: $error' : 'تعذّر الحذف: $error';
  String get customersDeletedSuccess =>
      _t('تم حذف العميل.', 'Customer deleted.');
  String customersOpeningPdfCustomerLine(String name) =>
      _en ? 'Customer: $name' : 'العميل: $name';

  String get customersSelectTableRowFirst => _t(
        'اختر صفًا من جدول العملاء أولاً.',
        'Select a customer row in the table first.',
      );
  String get customersSelectCustomerFirst => _t(
        'اختر عميلاً أولاً.',
        'Select a customer first.',
      );
  String get customersNoBalanceDue => _t(
        'لا يوجد متبقي مستحق لهذا العميل.',
        'No balance due for this customer.',
      );
  String get customersNoOpeningReceiptVoucher => _t(
        'لا يوجد رصيد افتتاحي «عليه» محفوظ لهذا العميل (سند قبض).',
        'No saved opening balance “due” entry for this customer (receipt voucher).',
      );
  String get customersNoOpeningPaymentVoucher => _t(
        'لا يوجد رصيد افتتاحي «له» محفوظ لهذا العميل (سند صرف).',
        'No saved opening balance “credit” entry for this customer (payment voucher).',
      );
  String get customersPickOpeningVoucherTitle => _t(
        'اختر سند الرصيد الافتتاحي',
        'Select opening balance voucher',
      );
  String get customersManageOpeningBalancesTitle => _t(
        'إدارة الأرصدة الافتتاحية',
        'Manage opening balances',
      );
  String get customersNoOpeningBalancesForCustomer => _t(
        'لا توجد أرصدة افتتاحية مسجّلة لهذا العميل.',
        'No opening balances recorded for this customer.',
      );
  String get customersDeleteOpeningBalanceTitle => _t(
        'حذف رصيد افتتاحي',
        'Delete opening balance',
      );
  String customersDeleteOpeningBalanceBody(String voucher, String amount) => _t(
        'هل تريد حذف الرصيد الافتتاحي «$voucher» بمبلغ $amount؟',
        'Delete opening balance «$voucher» for $amount?',
      );
  String get customersOpeningBalanceDeleted => _t(
        'تم حذف الرصيد الافتتاحي.',
        'Opening balance deleted.',
      );
  String customersDeleteOpeningBalanceFailed(Object e) => _t(
        'تعذّر حذف الرصيد الافتتاحي: $e',
        'Could not delete opening balance: $e',
      );
  String get customersOpeningBalanceDueLabel => _t('عليه', 'Due (AR)');
  String get customersOpeningBalanceCreditLabel => _t('له', 'Credit');
  String get customersChipManageOpeningBalances => _t(
        'حذف / إدارة رصيد افتتاحي',
        'Delete / manage opening balance',
      );
  String get customersLoadingDirectory => _t(
        'جارٍ تحميل العملاء…',
        'Loading customers…',
      );
  String get customersToolbarHintShort => _t(
        'شريط أزرق للتقارير (اختر صفاً عند الحاجة)، شريط أبيض للقائمة وPDF والطباعة.',
        'Blue: reports (pick a row when needed). White: list, PDF, print.',
      );
  String get customersToolbarHintDetail => _t(
        'الشريط الأزرق: عميل جديد، أرصدة، التقارير (اختر صفاً عند الحاجة). الشريط الأبيض: فحص الأرصدة (معاينة PDF)، الأرصدة الافتتاحية والنقد (PDF)، طباعة القائمة، إعادة طباعة السندات — بنفس أسلوب الأزرار المصغّرة.',
        'Blue bar: new customer, balances, reports (select a row when needed). White bar: balance check (PDF preview), opening balances & cash (PDF), print list, reprint vouchers — same chip style as the blue bar.',
      );
  String get customersToolbarHintDialogTitle => _t(
        'شرح شاشة إدارة العملاء',
        'Customer management screen toolbars',
      );
  String get customersSearchFieldHint => _t(
        'بحث (اسم / هاتف / رقم عميل)',
        'Search (name / phone / customer no.)',
      );

  String get customersChipNewCustomer => _t('عميل جديد', 'New customer');
  String get customersChipAddOpeningBalance =>
      _t('إضافة رصيد افتتاحي', 'Add opening balance');
  String get customersChipReceivablesFull =>
      _t('ذمم العملاء', 'Customer receivables');
  String get customersChipReceivablesFullTooltip => _t(
        'تقرير شامل لذمم العملاء — معاينة مباشرة',
        'Full receivables report — opens preview',
      );
  String get customersChipReceivablesSingle =>
      _t('ذمم العميل', 'Customer receivables');
  String get customersChipDetailedStatement =>
      _t('كشف حساب تفصيلي', 'Detailed statement');
  String get customersChipAccountReconciliation =>
      _t('تقرير مصادقة حساب', 'Account reconciliation');
  String get customersChipOpeningBalanceMovement =>
      _t('حركة الرصيد الافتتاحي والنقد', 'Opening balance & cash movement');
  String get customersChipInvoicesReport =>
      _t('تقرير بالفواتير', 'Invoices report');
  String get customersChipPaymentMovement =>
      _t('تقرير بحركة السداد لعميل', 'Payment movement');
  String get customersChipPaymentMovementTooltip => _t(
        'تقرير بحركة السداد لعميل — اختيار الفترة ثم المعاينة',
        'Customer payment movement — pick period, then PDF preview',
      );
  String get customersChipBalanceCheck => _t('فحص الأرصدة', 'Balance check');
  String get customersChipBalanceCheckTooltip => _t(
        'أرصدة العملاء — اختيار الفترة ثم معاينة PDF',
        'Customer balances — pick period, then PDF preview',
      );
  String get customersChipOpeningBalancesCashPdf =>
      _t('الأرصدة الافتتاحية والنقد', 'Opening balances & cash');
  String get customersChipOpeningBalancesCashPdfTooltip => _t(
        'الأرصدة الافتتاحية والنقد — اختيار الفترة ثم معاينة PDF',
        'Opening balances & cash — pick period, then PDF preview',
      );
  String get customersChipPrintList => _t('طباعة القائمة', 'Print list');
  String get customersChipPrintListTooltip => _t(
        'نفس تخطيط PDF — اختيار الفترة ثم المعاينة',
        'Same layout as PDF — pick period, then preview',
      );
  String get customersChipReprintReceiptVoucher =>
      _t('إعادة طباعة سند قبض', 'Reprint receipt voucher');
  String get customersChipReprintPaymentVoucher =>
      _t('إعادة طباعة سند الصرف', 'Reprint payment voucher');
  String get customersChipFullPage => _t('صفحة كاملة', 'Full page');

  String get openingBalancePdfDirectionReceivable => _t(
        'رصيد افتتاحي — عليه (ذمة على العميل). يُستكمل التحصيل النقدي عبر الصندوق عند الاقتضاء.',
        'Opening balance — receivable (amount owed by the customer). Cash collection can be completed via the cash box when needed.',
      );
  String get openingBalancePdfDirectionPayable => _t(
        'رصيد افتتاحي — له (رصيد دائن للعميل).',
        'Opening balance — credit (balance in favour of the customer).',
      );
  String get openingBalanceVoucherTitleReceipt =>
      _t('سند قبض', 'Receipt voucher');
  String get openingBalanceVoucherTitlePayment =>
      _t('سند صرف', 'Payment voucher');
  String get openingBalancePdfFooterMatchedVoucher => _t(
        'وثيقة توثيق رصيد افتتاحي — لا تُنشئ حركة نقدية تلقائياً. يُستكمل التحصيل أو الصرف النقدي عبر الصندوق عند الاقتضاء.',
        'Opening balance record — does not post cash automatically. Cash receipt or payment can be completed via the cash box when needed.',
      );
  String get openingBalancePdfTitleSummary =>
      _t('تقرير رصيد افتتاحي', 'Opening balance report');
  String get openingBalancePdfFooterNoteSummary => _t(
        'تقرير توثيقي لرصيد افتتاحي عميل — لا يُنشئ حركة نقدية تلقائياً. يُطابق القيد المحفوظ عند استخدام «حفظ» بنفس البيانات.',
        'Summary opening balance for this customer — does not post cash automatically. Matches the ledger posting when you use Save with the same details.',
      );

  /// نموذج «إضافة رصيد افتتاحي» (حوار).
  String get openingBalanceFormTitle =>
      _t('إضافة رصيد افتتاحي', 'Add opening balance');
  String get openingBalanceFormIntro => _t(
        'قيد على دفتر عميل (ذمم). يمكن اختيار إضافة المبلغ للصندوق أو حذفه منه عند الحفظ.',
        'Customer ledger entry. You may optionally add the amount to the cash box or remove it on save.',
      );
  String get openingBalanceFormCustomerSection =>
      _t('اختيار العميل', 'Customer');
  String openingBalanceFormCustomerNumberLabel(String n) =>
      _en ? 'No.: $n' : 'الرقم: $n';
  String get openingBalanceFormChange => _t('تغيير', 'Change');
  String get openingBalanceFormSearchHint => _t(
        'ابحث بالاسم أو الهاتف أو رقم العميل',
        'Search by name, phone, or customer #',
      );
  String get openingBalanceFormSearchMinChars => _t(
        'اكتب حرفاً واحداً على الأقل لعرض النتائج.',
        'Type at least one character to show matches.',
      );
  String get openingBalanceFormNoCustomerMatch =>
      _t('لا يوجد عميل مطابق.', 'No matching customer.');
  String openingBalanceFormListCustomerNumberLine(String n) =>
      _en ? 'No. $n' : 'رقم: $n';
  String get openingBalanceFormBalanceDirectionTitle =>
      _t('اتجاه الرصيد', 'Balance direction');
  String get openingBalanceFormDirectionDueExplanation => _t(
        'عليه: ذمة على العميل — بعد الحفظ يمكن طباعة سند قبض.',
        'Due (customer owes): you can print a receipt voucher after saving.',
      );
  String get openingBalanceFormDirectionCreditExplanation => _t(
        'له: رصيد دائن للعميل — بعد الحفظ يمكن طباعة سند صرف.',
        'Credit (we owe customer): you can print a payment voucher after saving.',
      );
  String get openingBalanceFormChipCreditLabel => _t('له', 'Credit');
  String get openingBalanceFormChipDueLabel => _t('عليه', 'Due');
  String get openingBalanceFormCashBoxSection =>
      _t('الصندوق (اختياري)', 'Cash box (optional)');
  String get openingBalanceFormCashBoxNone =>
      _t('بدون حركة صندوق', 'No cash movement');
  String get openingBalanceFormCashBoxAdd =>
      _t('إضافة المبلغ للصندوق', 'Add amount to cash box');
  String get openingBalanceFormCashBoxRemove =>
      _t('حذف المبلغ من الصندوق', 'Remove amount from cash box');
  String get openingBalanceFormAmountSection => _t('قيمة المبلغ', 'Amount');
  String get openingBalanceFormAmountFieldHint => _t('قيمة المبلغ', 'Amount');
  String get openingBalanceFormVoucherNumberSection =>
      _t('رقم السند', 'Voucher number');
  String get openingBalanceFormVoucherAuto => _t('تلقائي', 'Auto');
  String get openingBalanceFormVoucherManual => _t('يدوي', 'Manual');
  String get openingBalanceFormVoucherPrefixFieldHint => _t(
        'بادئة الترقيم (ثم - ثم التسلسل)',
        'Number prefix (then hyphen, then sequence)',
      );
  String openingBalanceFormVoucherPrefixNote(String defaultPrefix) => _en
      ? 'Hyphens (-) are stripped from the prefix. A random 6-digit suffix is added (e.g. $defaultPrefix-482917). Tap refresh for a new number.'
      : 'تُزال الواصلة (-) من البادئة ويُضاف 6 أرقام عشوائية (مثل $defaultPrefix-482917). اضغط تحديث لرقم جديد.';
  String get openingBalanceFormVoucherNextPreviewLabel =>
      _t('رقم السند (عشوائي)', 'Voucher no. (random)');
  String get openingBalanceFormVoucherLoading =>
      _t('جاري التحميل…', 'Loading…');
  String get openingBalanceFormVoucherManualFieldHint => _t(
        'رقم السند كاملاً (كما سيُحفظ)',
        'Full voucher number (as stored)',
      );
  String get openingBalanceFormVoucherManualNote => _t(
        'في الوضع اليدوي يُحفظ النص كما أدخلته دون بادئة تلقائية.',
        'In manual mode the text is saved exactly as entered without an automatic prefix.',
      );
  String get openingBalanceFormDescriptionField => _t('البيان', 'Description');
  String get openingBalanceFormEntryDate => _t('تاريخ القيد', 'Entry date');
  String get openingBalanceFormReset => _t('تراجع', 'Reset');
  String get openingBalanceFormPrintSection => _t('طباعة', 'Print');
  String get openingBalanceFormPrintHint => _t(
        'نوع السند يتبع «له / عليه» تلقائياً. التقرير عنوانه ثابت ولا يبدّل سند قبض/صرف.',
        'Voucher type follows Due / Credit. The summary report title is fixed.',
      );
  String get openingBalanceFormPrintReceiptVoucherBtn =>
      _t('طباعة سند قبض', 'Print receipt voucher');
  String get openingBalanceFormPrintPaymentVoucherBtn =>
      _t('طباعة سند صرف', 'Print payment voucher');
  String get openingBalanceFormPrintPdfReportBtn =>
      _t('تقرير PDF', 'PDF report');

  String get openingBalanceFormErrSearchPickCustomer => _t(
        'ابحث واختر عميلاً أولاً.',
        'Search and pick a customer first.',
      );
  String get openingBalanceFormErrAmount => _t(
        'أدخل مبلغاً صحيحاً أكبر من صفر.',
        'Enter a valid amount greater than zero.',
      );
  String get openingBalanceFormErrManualVoucherEmpty => _t(
        'أدخل رقم السند في الوضع اليدوي.',
        'Enter the voucher number in manual mode.',
      );
  String openingBalanceFormErrSave(Object e) =>
      _en ? 'Save failed: $e' : 'تعذر الحفظ: $e';
  String get openingBalanceFormSaveOk =>
      _t('تم تسجيل الرصيد الافتتاحي.', 'Opening balance saved.');
  String openingBalanceFormSavedVoucherLine(String v) =>
      _en ? 'Voucher no.: $v' : 'رقم السند: $v';
  String get openingBalanceFormSavedFinish => _t('إنهاء', 'Done');
  String get openingBalanceFormErrPrintPickCustomer => _t(
        'اختر عميلاً أولاً للطباعة.',
        'Pick a customer before printing.',
      );
  String get openingBalanceFormErrPrintAmount => _t(
        'أدخل المبلغ أولاً للطباعة.',
        'Enter the amount before printing.',
      );

  /// نموذج «أرصدة افتتاحية — موردين» (حوار، يشبه نموذج العملاء).
  String get supplierOpeningBalanceFormTitle => _t(
        'الأرصدة الافتتاحية للموردين',
        'Supplier opening balances',
      );
  String get supplierOpeningBalanceFormIntro => _t(
        'قيد على ذمة المورد (حسابات الدفع). لا يُنشئ قبضاً أو صرفاً نقدياً تلقائياً — تُكمَّل التسويات لاحقاً من الصندوق أو الشيكات.',
        'Posting on the supplier AP ledger. Does not post cash receipt/payment automatically — settle later via cash or checks.',
      );
  String get supplierOpeningBalanceFormSupplierSection =>
      _t('اختيار المورد', 'Supplier');
  String supplierOpeningBalanceFormSupplierNumberLabel(String n) =>
      _en ? 'No.: $n' : 'الرقم: $n';
  String get supplierOpeningBalanceFormSearchHint => _t(
        'ابحث بالاسم أو الهاتف أو رقم المورد',
        'Search by name, phone, or supplier #',
      );
  String get supplierOpeningBalanceFormNoSupplierMatch =>
      _t('لا يوجد مورد مطابق.', 'No matching supplier.');
  String supplierOpeningBalanceFormListSupplierNumberLine(String n) =>
      _en ? 'No. $n' : 'رقم: $n';
  String get supplierOpeningBalanceFormDirectionWeAreOwedExplanation => _t(
        'لنا: رصيد لصالح المتجر على المورد — يُطبَع «سند قبض» عند طباعة السند.',
        'We are owed: balance in favor of the store — prints as receipt voucher.',
      );
  String get supplierOpeningBalanceFormDirectionWeOweExplanation => _t(
        'علينا: ذمة مشتريات على المتجر — يُطبَع «سند صرف» عند طباعة السند.',
        'We owe supplier: purchase AP on the store — prints as payment voucher.',
      );
  String get supplierOpeningBalanceFormChipWeAreOwedLabel =>
      _t('لنا', 'We are owed');
  String get supplierOpeningBalanceFormChipWeOweLabel => _t('علينا', 'We owe');
  String get supplierOpeningBalanceFormPrintHint => _t(
        'نوع السند يتبع «لنا / علينا» تلقائياً. التقرير عنوانه ثابت ولا يبدّل سند قبض/صرف.',
        'Voucher type follows We are owed / We owe. The summary title is fixed.',
      );
  String get supplierOpeningBalanceFormErrSearchPickSupplier => _t(
        'ابحث واختر مورداً أولاً.',
        'Search and pick a supplier first.',
      );
  String supplierOpeningBalanceFormErrSave(Object e) =>
      _en ? 'Save failed: $e' : 'تعذر الحفظ: $e';
  String get supplierOpeningBalanceFormErrPrintPickSupplier => _t(
        'اختر مورداً أولاً للطباعة.',
        'Pick a supplier before printing.',
      );
  String supplierOpeningBalancePdfPartyLine(String name) =>
      _en ? 'Supplier: $name' : 'المورد: $name';
  String get supplierOpeningBalancePdfDirectionWeOwe => _t(
        'رصيد افتتاحي — علينا للمورد (ذمة مشتريات). يُستكمل السداد عبر الصندوق عند الدفع.',
        'Opening balance — payable to supplier (AP). Cash settlement is completed separately.',
      );
  String get supplierOpeningBalancePdfDirectionWeAreOwed => _t(
        'رصيد افتتاحي — لنا على المورد (رصيد لصالح المتجر).',
        'Opening balance — receivable from supplier (in favor of the store).',
      );
  String get supplierOpeningBalancePdfFooterMatchedVoucher => _t(
        'وثيقة توثيق رصيد افتتاحي مورد — لا تُنشئ حركة نقدية تلقائياً. يُستكمل السداد أو التسوية عبر الصندوق عند الاقتضاء.',
        'Supplier opening balance voucher — does not post cash automatically. Settle via cash box when needed.',
      );
  String get supplierOpeningBalancePdfTitleSummary => _t(
        'تقرير رصيد افتتاحي — مورد',
        'Supplier opening balance report',
      );
  String get supplierOpeningBalancePdfFooterSummary => _t(
        'تقرير توثيقي لرصيد افتتاحي مورد — لا يُنشئ حركة نقدية تلقائياً. يُطابق القيد عند «حفظ» بنفس البيانات.',
        'Summary supplier opening balance — does not post cash automatically. Matches the saved posting.',
      );

  String get expPaymentsReportTitle => _t('تقرير المصاريف', 'Expense report');
  String get expPaymentsReportTooltip => _t(
        'جدول المصاريف — معاينة وطباعة وتصدير',
        'Expenses table — preview, print, and export',
      );
  String get expPaymentsReportEmpty =>
      _t('لا توجد مصاريف مسجّلة.', 'No expenses yet.');
  String get expPaymentsSaveOk =>
      _t('تم حفظ المصروف بنجاح.', 'Expense saved successfully.');

  String get themeBlue => _t('أزرق', 'Blue');
  String get themeTeal => _t('تركواز', 'Teal');
  String get themePurple => _t('بنفسجي', 'Purple');
  String get themeOrange => _t('برتقالي', 'Orange');
  String get themeRose => _t('وردي داكن', 'Rose');

  String get demoModeHint =>
      _t('البرنامج يعمل بوضع النسخة التجريبية.', 'Running in demo mode.');
  String get licenseGuestBadge => _t('وضع زائر', 'Guest');

  String get guestModeGuideTitle =>
      _t('تعليمات وضع الزائر', 'Guest mode instructions');

  String get guestModeTrial30DaysHeadline =>
      _t('التجربة 30 يوماً', '30-day trial');

  String get guestModeTrial30DaysBody => _t(
        'بعد أول تسجيل دخول بحساب حقيقي على هذا الجهاز، تحصل على صلاحيات كاملة لمدة 30 يوماً.',
        'After the first sign-in with a real account on this device, you get full access for 30 days.',
      );

  String get guestModeGuestLimitedHeadline => _t(
        'استخدام محدود كزائر',
        'Limited use as a guest',
      );

  String get guestModeGuestLimitedBody => _t(
        'يمكنك المعاينة ضمن حدود الزائر. بعد التسجيل وتسجيل الدخول تحصل على صلاحيات تشغيل أوسع إلى أن تُكمّل تفعيل الاشتراك.',
        'You can preview within guest limits. After you register and sign in you get broader day‑to‑day features until you complete subscription activation.',
      );

  String get guestModeSignInForRegisteredFeaturesNote => _t(
        'سجّل الدخول بحسابك بعد التسجيل؛ بعض الإعدادات المتقدمة والمالية تبقى مقفلة حتى إتمام التفعيل المدفوع.',
        'Sign in with your account after registering; advanced and financial features stay locked until paid activation is complete.',
      );

  /// عند ربط التطبيق بخادم التفعيل: لا وعد بتجربة 30 يوماً كاملة بعد التسجيل.
  String get guestModeAfterSignInNeedsActivationHeadline => _t(
        'بعد التسجيل: التفعيل من الويب',
        'After signup: activate via the web',
      );

  String get guestModeAfterSignInNeedsActivationBody => _t(
        'عند إنشاء حساب جديد ثم تسجيل الدخول، لا يُعتبر الجهاز «مفعّلاً بالكامل» حتى تُدخل رمز التفعيل الصادر من لوحة التفعيل بعد اعتماد الطلب. حتى ذلك الحين تبقى كثير من الصلاحيات والعمليات مقيدة.',
        'After you create an account and sign in, this device is not fully activated until you enter the activation code from the web portal once your request is approved. Many permissions and actions stay limited until then.',
      );

  String guestModeTrialDaysRemaining(int days) => _en
      ? '$days days left on this device'
      : 'متبقي على هذا الجهاز: $days يوماً';

  String get guestModeTrialGrandfatherNote => _t(
        'هذا الجهاز على ترخيص ترقية — وصول كامل.',
        'This install has an upgrade license — full access.',
      );

  String get guestModeTrialEndedNote => _t(
        'انتهت فترة التجربة على هذا الجهاز.',
        'The trial on this device has ended.',
      );

  String get guestModeTrialNotStartedNote => _t(
        'لم تبدأ التجربة بعد على هذا الجهاز — سجّل الدخول بحساب حقيقي للبدء.',
        'Trial has not started on this device yet — sign in with a real account to begin.',
      );

  String get guestModeOpenActivate => _t('فتح التفعيل', 'Open activation');

  String get guestModeOpenWhatsApp => _t('تواصل واتساب', 'WhatsApp');

  String get guestModeOpenWebsite =>
      _t('زيارة MizaPos.com', 'Visit MizaPos.com');

  String licenseFooterHintBody(
    bool guest, {
    bool remoteActivationServer = false,
  }) {
    if (guest) {
      if (remoteActivationServer) {
        return _en
            ? 'Guest mode: up to 5 products per sale/purchase invoice and 10 inventory items without activation. A voucher (Menu → Activate subscription — code; two devices per code) unlocks unlimited products and gated premium menu items. Staff sign-in is optional.'
            : 'وضع الزائر: حتى 5 منتجات في فاتورة البيع/الشراء و10 أصناف في المخزون بدون تفعيل. تفعيل القسيمة (القائمة ← تفعيل الاشتراك — الكود، جهازان لكل كود) يفتح عدداً غير محدود وبعض بنود القائمة المحجوبة. دخول فريق العمل اختياري.';
      }
      return _en
          ? 'Guest mode: up to 5 products per sale/purchase invoice and 10 inventory items without activation. Menu → Activate subscription unlocks unlimited products and gated premium items. Staff sign-in is optional.'
          : 'وضع الزائر: حتى 5 منتجات في فاتورة البيع/الشراء و10 أصناف في المخزون بدون تفعيل. القائمة ← تفعيل الاشتراك تفتح عدداً غير محدود وبعض الإجراءات المقفلة. دخول فريق العمل اختياري.';
    }
    if (remoteActivationServer) {
      return _en
          ? 'Full features unlock after you enter the activation code from the portal. Backup/restore and other premium tools stay locked until then.'
          : 'تُفتح الصلاحيات الكاملة بعد إدخال كود التفعيل من لوحة المالك؛ النسخ الاحتياطي والاستعادة وغيرها تبقى للنسخة المفعّلة.';
    }
    return _en
        ? 'After sign-in you can work with limited features until you complete activation from the web portal.'
        : 'بعد تسجيل الدخول تعمل ضمن صلاحيات محدودة إلى أن تُكمّل التفعيل من لوحة التفعيل على الويب.';
  }

  String licenseErrorMessage(String code) {
    switch (code) {
      case 'license_subscription_required':
        return licenseSubscriptionRequired;
      case 'license_subscription_suspended':
        return licenseSubscriptionSuspended;
      case 'license_premium_feature_requires_activation':
        return licensePremiumFeatureRequiresActivation;
      case 'license_activation_device_limit':
        return licenseActivationDeviceLimit;
      default:
        return code;
    }
  }

  String get licenseSubscriptionRequired => _t(
        'يلزم تفعيل الاشتراك. أنجز الدفع ثم التفعيل من لوحة الويب، واستخدم «تفعيل الاشتراك» بالأسفل.',
        'Subscription activation is required. Complete payment and activation from the web dashboard, then use «Activate subscription» below.',
      );

  String get licenseSubscriptionSuspended => _t(
        'تم تجميد اشتراكك من لوحة التفعيل. تواصل مع الدعم أو المالك لفك التجميد، ثم استخدم «تفعيل».',
        'Your subscription was suspended from the activation portal. Contact support or the owner to lift the freeze, then use «Activate».',
      );

  String get licensePremiumFeatureRequiresActivation => _t(
        'هذه الميزة متاحة في النسخة المفعّلة بالكامل. استخدم «تفعيل الاشتراك» من القائمة واربط الجهاز من صفحة التفعيل على الويب ثم «تفعيل».',
        'This feature is available on the fully activated edition. Use «Activate subscription», link the device on the activation website, then «Activate».',
      );

  String get licenseActivationDeviceLimit => _t(
        'وصل هذا الاشتراك إلى الحد الأقصى من الأجهزة (جهازان). لإضافة جهاز جديد، يُفك ربط جهاز من لوحة التفعيل.',
        'This subscription has reached the maximum number of devices (two). To add another device, unlink a device in the activation portal.',
      );

  String get trialBadge => _t('نسخة تجريبية', 'Trial');

  /// الشريط السفلي عند انتهاء التجربة دون اشتراك سنوي بعد تسجيل الدخول.
  String get footerActivateSubscriptionBadge =>
      _t('تفعيل الاشتراك', 'Activate subscription');

  /// مسجّل دخول بلا تفعيل مدفوع بعد — ليست حالة «مفعّل بالكامل».
  String get footerPendingActivationBadge =>
      _t('بانتظار التفعيل الكامل', 'Pending full activation');

  String get pendingActivationBannerHeadline =>
      _t('أكمل تفعيل الاشتراك', 'Complete subscription activation');

  String get pendingActivationBannerBody => _t(
        'أنت مسجّل الدخول وتعمل ضمن صلاحيات محدودة إلى أن يُفعَّل اشتراكك بالكامل من لوحة التفعيل.',
        'You are signed in with limited features until your subscription is fully activated from the web portal.',
      );

  String get accessSuspendedBannerHeadline =>
      _t('الاشتراك مجمّد', 'Subscription suspended');

  String get accessSuspendedBannerBody => _t(
        'تم تعليق الوصول من لوحة تفعيل MizaPos. راجع المالك أو الدعم؛ بعد فك التجميد اضغط «تفعيل» في نافذة التفعيل.',
        'Access was suspended from the MizaPos activation portal. Ask your owner or support; after unfreezing, tap «Activate» in the activation dialog.',
      );

  String get activationFooterPendingLimited => _t(
        'صلاحيات محدودة — أكمل التفعيل',
        'Limited features — complete activation',
      );

  String get activationDialogCoveragePending => _t(
        'حسابك مسجّل لكن التفعيل المدفوع غير مكتمل. أكمل الدفع والخطوات على موقع التفعيل ثم استخدم «تفعيل». بعض الميزات (الفروع، الفريق، المصروفات، حركة الصندوق المتقدمة، الاستيراد الجماعي…) تبقى مقفلة حتى التفعيل.',
        'Your account is registered but paid activation is not complete yet. Finish payment on the activation site, then use «Activate». Some features (branches, team, expenses, advanced cash movements, bulk import, …) stay locked until activation.',
      );

  String get deviceSubtitlePendingActivation => _t(
      'بانتظار تفعيل الاشتراك الكامل', 'Awaiting full subscription activation');

  String get activationFooterSuspended =>
      _t('اشتراك مجمّد — تواصل مع الدعم', 'Suspended — contact support');

  String get activationDialogCoverageSuspended => _t(
        'تم تجميد اشتراك هذا الحساب من لوحة التفعيل على الويب. لا يمكن متابعة العمل إلى أن يُلغى التجميد هناك؛ بعدها استخدم «تفعيل».',
        'This account’s subscription was frozen from the web activation portal. Work stays blocked until it is unfrozen there; then use «Activate».',
      );

  /// شارة بديلة عن زر «نسخة تجريبية» عند وجود اشتراك/ترخيص فعّال.
  String get footerRibbonAnnual =>
      _t('اشتراك سنوي مفعّل', 'Annual subscription active');

  String get footerRibbonGrandfather =>
      _t('ترخيص ترقية — كامل', 'Full upgrade license');

  String get footerRibbonLegacy => _t('ترخيص مستمر', 'Ongoing license');

  String get footerRibbonLicensedTooltip =>
      _t('اشتراكك أو ترخيصك نشط.', 'Your subscription or license is active.');

  String get subscriptionDeviceMismatchSnack => _t(
        'الاشتراك السنوي مفعّل لبريد وحاسوب مختلفين عن هذا الجلسة. استخدم الحساب والجهاز المعتمدين، أو يُطلب إعادة التفعيل.',
        'This subscription is locked to another email/device. Sign in with the approved account on the activated PC, or activate again.',
      );

  String activatedBadge(bool ok) =>
      ok ? _t('تم التفعيل', 'Activated') : _t('تفعيل البرنامج', 'Activate');

  /// زر الشريط السفلي — يعرض حالة الترخيص الفعلية (متطابقة مع [LicenseGate]).
  String get activationFooterGuest =>
      _t('تفعيل الاشتراك', 'Activate subscription');

  String activationFooterAnnualUntil(String date) =>
      _en ? 'Annual license until $date' : 'ترخيص سنوي حتى $date';

  String activationFooterTrialUntil(String date) =>
      _en ? 'Trial until $date' : 'تجربة حتى $date';

  String activationTrialDaysRemaining(int days) =>
      _en ? '$days day(s) left on trial' : 'متبقي على التجربة: $days يوماً';

  String activationAnnualDaysRemaining(int days) => _en
      ? '$days day(s) left on annual subscription'
      : 'متبقي على الاشتراك السنوي: $days يوماً';

  /// تذكير يومي في التطبيق قبل انتهاء التجربة (≤14 يوماً).
  String subscriptionReminderTrialDays(int days) => _en
      ? 'Reminder: $days day(s) left on the trial period. Activate your subscription before it ends.'
      : 'تنبيه: متبقٍ $days يوماً على انتهاء الفترة التجريبية. فعّل الاشتراك قبل انتهائها.';

  /// تذكير يومي قبل انتهاء الاشتراك السنوي (≤14 يوماً).
  String subscriptionReminderAnnualDays(int days) => _en
      ? 'Reminder: $days day(s) left on your annual subscription. Ask your administrator to renew from the web dashboard.'
      : 'تنبيه: متبقٍ $days يوماً على انتهاء الاشتراك السنوي. يمكن للمالك التجديد من لوحة الويب قبل انتهائه.';

  String get activationFooterGrandfather =>
      _t('وصول كامل (ترقية)', 'Full access (upgrade)');

  String get activationFooterLegacy =>
      _t('تفعيل قديم — ساري', 'Legacy activation active');

  String get activationFooterNeedsKey => _t(
      'تفعيل الاشتراك — بعد الدفع من لوحة الويب',
      'Activate subscription — after payment via web');

  String get deviceActivatedBannerTitle =>
      _t('الاشتراك مفعّل', 'Subscription active');

  String deviceActivatedNamedLine(String name) =>
      _en ? 'Activated for: $name' : 'مفعّل باسم $name';

  String get deviceSubtitleGrandfather =>
      _t('ترخيص ترقية — وصول كامل', 'Upgrade license — full access');

  String get deviceSubtitleLegacy =>
      _t('تفعيل سابق بدون تاريخ انتهاء', 'Legacy activation (no expiry date)');

  String get deviceSubtitleAnnualUnknown =>
      _t('ترخيص سنوي ساري', 'Annual license active');

  String get deviceSubtitleTrialActive =>
      _t('فترة تجريبية سارية', 'Trial period active');

  String get activationManageTitle =>
      _t('إدارة اشتراك الحساب', 'Manage account subscription');

  /// عنوان فوق عنوان البريد في حوار التفعيل الاحتفالي.
  String get activationRegisteredEmailLabel =>
      _t('البريد المسجّل بالاشتراك', 'Registered subscription email');

  String get subscriberDisplayNameLabel =>
      _t('اسم صاحب الاشتراك (اختياري)', 'Subscription holder (optional)');

  String get subscriberDisplayNameHint => _t(
        'يُعرض أسفل الشريط بعد «مفعّل باسم»',
        'Shown in the footer after «Activated for»',
      );

  String get activationReplaceKeyExpand => _t(
        'استبدال مفتاح التفعيل (متقدّم)',
        'Replace activation key (advanced)',
      );

  String get activationPrefsSavedSnack =>
      _t('تم حفظ إعدادات التفعيل.', 'Activation settings saved.');

  String get activationEnterCodeSectionTitle =>
      _t('إدخال كود التفعيل', 'Enter activation code');
  String get activationEnterCodeSectionBody => _t(
        'عندما تستلم رمز التفعيل لحسابك، انسخه هنا واضغط «تطبيق الكود».',
        'When you receive your activation code, paste it here and tap «Apply code».',
      );
  String get activationEnterCodeLabel => _t('كود التفعيل', 'Activation code');
  String get activationEnterCodeHint => _t(
        'مثال: MizaPos-…',
        'e.g. MizaPos-…',
      );
  String get activationApplyCodeButton => _t('تطبيق الكود', 'Apply code');
  String get activationApplyCodeWorking => _t('جاري التحقق…', 'Verifying…');
  String get activationCodeEmpty =>
      _t('أدخل كود التفعيل.', 'Enter the activation code.');
  String get activationCodeNotMatched => _t(
        'الكود غير صالح أو سبق استخدامه.',
        'Invalid or already used code.',
      );
  String get activationCodeAppliedSnack =>
      _t('تم تفعيل الاشتراك بنجاح.', 'Subscription activated successfully.');
  String get activationCodeAppliedPendingSnack => _t(
        'تم قبول الكود. إن بقي الحساب بانتظار التفعيل الكامل، جرّب «تفعيل» من نافذة التفعيل.',
        'Code accepted. If full activation is still pending, try «Activate» from the activation dialog.',
      );

  String get activationDeviceLinkTitle =>
      _t('كود ربط هذا الجهاز', 'This device’s link code');
  String get activationDeviceLinkBody => _t(
        'تُفتح صفحة التفعيل مع كود هذا الجهاز. أكمل «تفعيل» هناك (كود الجهاز أولاً ثم البريد وكلمة المرور). بعدها اضغط «تفعيل» هنا.',
        'The activation page opens with this device’s code. Finish «Activate» there (device code first, then email and password). Then tap «Activate» here.',
      );
  String get activationDeviceLinkOpenWeb =>
      _t('فتح صفحة التفعيل', 'Open activation page');
  String get activationDeviceCodeMissing => _t(
        'تعذّر توليد كود الجهاز.',
        'Could not build the device code.',
      );
  String get activationDeviceLinkNotLinkedYet => _t(
        'الجهاز غير مفعّل: لم يُفعَّل هذا الجهاز من لوحة «تفعيل الويب» بعد. بعد أن يُدخل المطوّر كود جهازك هناك ويُبلغك رسمياً، اضغط «تفعيل» من جديد.',
        'Device not activated: this device has not been activated on the web activation portal yet. After your administrator enters your device code there and confirms with you, tap «Activate» again.',
      );
  // --- صفحة تفعيل الاشتراك (التصميم المبسّط) ---

  String get subscriptionActivationPageTitle =>
      _t('صفحة تفعيل الاشتراك', 'Subscription Activation');

  String get subscriptionActivationDeviceCodeLabel =>
      _t('كود الجهاز', 'Device code');

  String get subscriptionActivationStepsTitle =>
      _t('خطوات تفعيل الجهاز', 'Steps to activate the device');

  String get subscriptionActivationStep1 => _t(
        'يقوم صاحب الجهاز (المشترك) بنسخ «كود الجهاز» من هذه الصفحة.',
        'The subscriber copies the «device code» from this page.',
      );

  String get subscriptionActivationStep2 => _t(
        'يرسل المشترك هذا الكود إلى مطوّر البرنامج أو المسؤول المختص.',
        'The subscriber sends this code to the developer or responsible administrator.',
      );

  String get subscriptionActivationStep3 => _t(
        'يقوم المطوّر بإدخال الكود المستلم في صفحة «تفعيل الويب» الخاصة بالنظام.',
        'The developer enters the received code on the system’s web activation page.',
      );

  String get subscriptionActivationStep4 => _t(
        'يُبلِّغ المطوّر المشترك رسمياً بأنه قد تم تفعيل جهازه على النظام.',
        'The developer officially notifies the subscriber that the device has been activated.',
      );

  String get subscriptionActivationStep5 => _t(
        'يضغط المشترك «تفعيل» داخل التطبيق ليكتمل الربط مباشرة.',
        'The subscriber taps «Activate» inside the app to complete linking directly.',
      );

  String get subscriptionActivationNote => _t(
        'ملاحظة مهمة: إذا لم يُفعَّل الجهاز من قبل المطوّر مسبقاً على الويب، ستظل تظهر رسالة تنبيه بأن «الجهاز غير مفعّل» حتى لو ضغط المشترك على «تفعيل».',
        'Important: if the developer has not activated the device on the web first, the alert «device not activated» will keep appearing even when the subscriber taps «Activate».',
      );

  /// نص الزر «تفعيل».
  String get subscriptionActivateButton => _t('تفعيل', 'Activate');

  // --- منظومة القسائم (Vouchers) ---

  String get voucherDialogTitle =>
      _t('تفعيل الاشتراك بقسيمة', 'Activate subscription with a voucher');

  String get voucherTabLogin => _t('تسجيل دخول', 'Sign in');
  String get voucherTabRegister => _t('حساب جديد', 'Create account');

  String get voucherFieldEmail => _t('البريد الإلكتروني', 'Email');
  String get voucherFieldPassword => _t('كلمة المرور', 'Password');
  String get voucherFieldPasswordConfirm =>
      _t('تأكيد كلمة المرور', 'Confirm password');
  String get voucherFieldFullName => _t('الاسم الكامل', 'Full name');
  String get voucherFieldPhone => _t('رقم الهاتف', 'Phone');
  String get voucherFieldCode => _t('رمز القسيمة', 'Voucher code');

  String get voucherActionLogin => _t('تسجيل الدخول', 'Sign in');
  String get voucherRememberLogin => _t(
        'حفظ بيانات تسجيل الدخول',
        'Remember sign-in',
      );
  String get voucherSubscribeAgentsLink => _t(
        'للإشتراك اضغط هنا',
        'To subscribe, tap here',
      );
  String get voucherActionRegister =>
      _t('إنشاء الحساب وحفظ الجلسة', 'Create account & sign in');
  String get voucherActionRedeem => _t('تفعيل بالقسيمة', 'Redeem voucher');
  String get voucherLogout => _t('خروج', 'Log out');
  String get voucherPasteFromClipboard =>
      _t('لصق من الحافظة', 'Paste from clipboard');

  String get voucherRedeemHint => _t(
        'الصق رمز القسيمة الذي حصلت عليه من مطوّر البرنامج لتفعيل اشتراك هذا الجهاز.',
        'Paste the voucher code you received from the developer to activate this device.',
      );
  String get voucherRedeemSuccess =>
      _t('تم تفعيل الاشتراك بنجاح.', 'Subscription activated successfully.');

  String get voucherActiveTitle => _t(
        'اشتراكك مُفعَّل على هذا الجهاز',
        'Your subscription is active on this device',
      );
  String get voucherActiveDevicesLabel =>
      _t('الأجهزة المُفعَّلة', 'Activated devices');
  String get voucherActiveRedeemedAt => _t('تاريخ التفعيل', 'Activated at');

  String get voucherReleaseThisDevice =>
      _t('تحرير هذا الجهاز من القسيمة', 'Release this device from the voucher');
  String get voucherReleaseConfirmTitle =>
      _t('تأكيد تحرير الجهاز', 'Confirm device release');
  String get voucherReleaseConfirmBody => _t(
        'سيتم تحرير هذا الجهاز من القسيمة لإفساح مكان لجهاز جديد. هل تريد المتابعة؟',
        'This device will be released from the voucher to free a slot for another device. Continue?',
      );
  String get voucherReleaseConfirm => _t('تأكيد التحرير', 'Confirm release');

  // --- لوحة الاشتراك المُفعَّل (Hero / تفاصيل) ---
  String get voucherActiveHeroBadge => _t('مُفعَّل', 'Activated');
  String get voucherActiveHeroSubtitle => _t(
        'اشتراكك يعمل بكامل صلاحياته على هذا الجهاز.',
        'Your subscription is fully active on this device.',
      );
  String get voucherActiveSubscriberLabel => _t('المشترك', 'Subscriber');
  String get voucherActiveCodeLabel => _t('رمز القسيمة', 'Voucher code');
  String get voucherActiveDeviceCardTitle => _t('هذا الجهاز', 'This device');
  String get voucherActiveCopiedCode =>
      _t('تم نسخ رمز القسيمة', 'Voucher code copied');
  String get voucherCopyAction => _t('نسخ', 'Copy');
  String get voucherActiveDevicesUsedOfMax =>
      _t('الأجهزة المُستخدمة', 'Devices in use');
  String get voucherActiveSlotsFreeLabel => _t('أماكن متاحة', 'Free slots');

  // --- نقل التفعيل إلى جهاز آخر (Transfer device flow) ---
  String get voucherTransferTitle =>
      _t('نقل التفعيل إلى جهاز آخر', 'Move activation to another device');
  String get voucherTransferOpenButton =>
      _t('نقل التفعيل إلى جهاز آخر', 'Move activation to another device');
  String get voucherTransferIntro => _t(
        'يمكنك تحرير هذا الجهاز من القسيمة وإعادة استخدام نفس الرمز لتفعيل جهاز جديد.',
        'You can release this device from the voucher and reuse the same code on another device.',
      );
  String get voucherTransferStepsTitle =>
      _t('كيف يتم النقل؟', 'How the transfer works');
  String get voucherTransferStep1 => _t(
        'نُحرّر هذا الجهاز من القسيمة فوراً ويتحول إلى وضع قراءة فقط.',
        'This device is released from the voucher and switches to read-only mode.',
      );
  String get voucherTransferStep2 => _t(
        'نعرض لك رمز القسيمة لتنسخه بسهولة.',
        'We reveal the voucher code so you can copy it easily.',
      );
  String get voucherTransferStep3 => _t(
        'افتح MizaPos على الجهاز الجديد، سجّل دخولك بنفس الحساب، ثم الصق الرمز في حقل تفعيل القسيمة.',
        'Open MizaPos on the new device, sign in with the same account, then paste the code in the activation field.',
      );
  String get voucherTransferConfirmPasswordLabel =>
      _t('كلمة مرور المشترك', 'Subscriber password');
  String get voucherTransferConfirmPasswordHint => _t(
        'لتأكيد العملية، نطلب منك إدخال كلمة مرورك مرة أخرى.',
        'To confirm the action, please re-enter your password.',
      );
  String get voucherTransferSecurityNote => _t(
        'هذه خطوة أمان: لا يتم تحرير أي جهاز قبل التحقق من هويتك.',
        'A security step: no device is released until your identity is verified.',
      );
  String get voucherTransferOnlineRequired => _t(
        'تحتاج اتصالاً بالإنترنت لإتمام النقل.',
        'You need an internet connection to complete the transfer.',
      );
  String get voucherTransferCta =>
      _t('تحرير الجهاز وإظهار الرمز', 'Release & reveal the code');
  String get voucherTransferDoneTitle =>
      _t('تم تحرير الجهاز بنجاح', 'Device released successfully');
  String get voucherTransferDoneSubtitle => _t(
        'انتقل الآن إلى الجهاز الجديد، سجّل دخولك بنفس الحساب، ثم الصق الرمز التالي:',
        'Now go to the new device, sign in with the same account, and paste this code:',
      );
  String get voucherTransferCodeCopyHint => _t(
        'احتفظ بالرمز في مكان آمن حتى تكمل التفعيل على الجهاز الجديد.',
        'Keep this code safe until you finish activation on the new device.',
      );
  String get voucherTransferDoneFinish => _t('فهمت، إغلاق', 'Got it, close');
  String get voucherTransferWrongPassword => _t(
        'كلمة المرور غير صحيحة، حاول مجدداً.',
        'Incorrect password, please try again.',
      );

  String get voucherValidationCredentials => _t(
        'تأكد من البريد (يحتوي @) وكلمة مرور لا تقل عن 4 أحرف.',
        'Check the email (must contain @) and a password of at least 4 characters.',
      );
  String get voucherErrorOffline => _t(
        'تعذّر الاتصال بخادم القسائم. تأكد من اتصالك بالإنترنت ثم أعد المحاولة.',
        'Could not reach the vouchers server. Check your internet and try again.',
      );

  /// تظهر بعد نجاح الدخول المحلي عندما يكون السيرفر غير متاح.
  String get voucherOfflineLoginSuccess => _t(
        'تم الدخول محلياً بدون اتصال. ستُحدَّث البيانات تلقائياً عند عودة الإنترنت.',
        'Signed in offline. Data will sync automatically when the internet is back.',
      );

  /// رسالة عند الفشل في الدخول المحلي لعدم وجود كاش سابق على هذا الجهاز.
  String get voucherOfflineNoCache => _t(
        'لا توجد إنترنت ولم يسبق تسجيل الدخول من هذا الجهاز. يُرجى الاتصال بالإنترنت في أول دخول.',
        'No internet and no previous sign-in on this device. Please connect to the internet for your first sign-in.',
      );

  /// رسالة عند محاولة الدخول المحلي ببريد مختلف عمّا حُفظ.
  String voucherOfflineEmailMismatch(String cachedEmail) => _t(
        'الدخول المحلي متاح فقط للحساب الذي سجّل سابقاً على هذا الجهاز ($cachedEmail).',
        'Offline sign-in is limited to the account previously used on this device ($cachedEmail).',
      );

  /// تظهر تحت زرّ الدخول كتلميح هادئ عندما يكون الكاش موجوداً.
  String voucherOfflineHintAvailable(String cachedEmail) => _t(
        'الدخول المحلي بدون إنترنت متاح لـ $cachedEmail.',
        'Offline sign-in is available for $cachedEmail.',
      );

  /// SnackBar بعد نجاح دخول فريق العمل عند انقطاع الإنترنت.
  String get staffOfflineLoginSuccess => _t(
        'دخول محلي بدون إنترنت. ستُكمَل المزامنة تلقائياً عند عودة الاتصال.',
        'Signed in offline. Sync will resume automatically when the internet is back.',
      );
  String get voucherErrorWrongCredentials => _t(
        'البريد أو كلمة المرور غير صحيحة.',
        'Incorrect email or password.',
      );
  String get voucherErrorInvalidCode => _t(
        'رمز القسيمة غير صالح. الصيغة المتوقّعة: Miza-XXXX-XXXX-XXXX.',
        'Invalid voucher code. Expected format: Miza-XXXX-XXXX-XXXX.',
      );
  String get voucherErrorRevoked => _t(
        'هذه القسيمة ملغاة من قِبل المطوّر. تواصل معه لتجديد الاشتراك.',
        'This voucher has been revoked by the developer. Contact them to renew.',
      );
  String get voucherErrorBoundToOther => _t(
        'هذه القسيمة مرتبطة بحساب مشترك آخر. تأكد من الكود أو سجّل بنفس الحساب.',
        'This voucher is bound to another subscriber account.',
      );
  String get voucherErrorMaxDevices => _t(
        'وصلت القسيمة للحد الأقصى من الأجهزة. حرّر جهازاً من حسابك أو تواصل مع المطوّر.',
        'Voucher has reached its maximum devices. Release a device or contact the developer.',
      );
  String get voucherErrorDesktopLimit => _t(
        'تم تفعيل القسيمة على حاسوب بالفعل. يمكنك تفعيل جهاز أندرويد فقط، أو حرّر جهازاً من حسابك.',
        'This voucher is already active on a desktop. You can activate Android only, or release a device.',
      );
  String get voucherErrorAndroidLimit => _t(
        'تم تفعيل القسيمة على أندرويد بالفعل. يمكنك تفعيل حاسوب فقط، أو حرّر جهازاً من حسابك.',
        'This voucher is already active on Android. You can activate desktop only, or release a device.',
      );
  String get voucherErrorWeakPassword => _t(
        'كلمة المرور قصيرة جداً (4 أحرف على الأقل).',
        'Password is too short (4 characters minimum).',
      );
  String get voucherErrorWrongPassword =>
      _t('كلمة المرور القديمة غير صحيحة.', 'Old password is incorrect.');
  String get voucherErrorPasswordMismatch =>
      _t('كلمتا المرور غير متطابقتين.', 'Passwords do not match.');
  String get voucherErrorMissingOrg => _t(
        'تعذّر تحديد رقم المؤسسة المحلي. أعد فتح البرنامج وحاول مجدداً.',
        'Could not determine the local organization id. Restart the app and try again.',
      );
  String get voucherErrorServerDisabled => _t(
        'خادم القسائم غير مُفعَّل في إعدادات هذا التطبيق.',
        'The vouchers server is not enabled in this app configuration.',
      );
  String get voucherErrorForbidden => _t(
        'رفض الخادم الطلب (إعدادات الأمان). إن سبق تسجيل الدخول على هذا الجهاز جرّب نفس البريد وكلمة المرور، أو تواصل مع الدعم.',
        'The server rejected the request (security settings). If you signed in on this device before, use the same email and password, or contact support.',
      );
  String get voucherErrorInvalidResponse => _t(
        'تعذّر قراءة ردّ الخادم. جرّب إعادة تشغيل البرنامج. للتأكد من السيرفر افتح في المتصفح: https://mizapos.com/drhsn/api/health (يجب أن يظهر {"ok":true}). رابط تسجيل الدخول لا يُفتح من المتصفح — يستخدمه البرنامج بطلب POST فقط.',
        'Could not read the server response. Restart the app. To verify the server, open https://mizapos.com/drhsn/api/health in a browser (expect {"ok":true}). The login URL is POST-only, not for opening in a browser.',
      );
  String get voucherErrorWrongApiUrl => _t(
        'عنوان خادم القسائم في إعدادات التطبيق غير صالح. استخدم https://mizapos.com/drhsn أو ملف remote_signup.json بمفتاح api_base_url.',
        'The vouchers server URL in app settings is invalid. Use https://mizapos.com/drhsn or remote_signup.json with api_base_url.',
      );
  String get voucherErrorGeneric => _t(
      'تعذّر إكمال العملية. أعد المحاولة لاحقاً.',
      'Operation failed. Please try again.');

  // --- صفحة «حسابي» العصرية (Subscriber Account Screen) ---

  String get subscriberAccountTitle => _t('حسابي', 'My account');

  String get subscriberAccountHeroBadge =>
      _t('اشتراك مُفعَّل', 'Active subscription');

  /// شارة واضحة: حساب على فترة تجربة (وليس اشتراكاً سنوياً مدفوعاً).
  String get subscriberAccountHeroBadgeTrial =>
      _t('حساب تجربة', 'Trial account');

  /// شارة واضحة: اشتراك سنوي مدفوع ومفعّل.
  String get subscriberAccountHeroBadgeAnnual =>
      _t('اشتراك سنوي مفعّل', 'Annual subscription active');

  String get subscriberAccountHeroBadgePending =>
      _t('بانتظار التفعيل السنوي', 'Awaiting annual activation');

  String get subscriberAccountHeroBadgeRevoked =>
      _t('الاشتراك معلَّق', 'Subscription suspended');

  String get subscriberAccountHeroSubtitleActive => _t(
        'يسعدنا انضمامك. اشتراكك يعمل على هذا الجهاز.',
        'Glad to have you. Your subscription is active on this device.',
      );

  String subscriberAccountHeroSubtitleTrial(int days) => _en
      ? 'This is a trial account — $days day(s) remaining. Activate the annual plan for uninterrupted access.'
      : 'هذا حساب تجربة — متبقٍ $days يوماً. فعّل الاشتراك السنوي لاستمرار الوصول دون انقطاع.';

  String get subscriberAccountHeroSubtitleAnnual => _t(
        'حساب مفعّل باشتراك سنوي على هذا الجهاز.',
        'This account has an active annual subscription on this device.',
      );

  String get subscriberAccountHeroSubtitleInactive => _t(
        'الحساب مسجّل لكن الاشتراك السنوي غير مفعّل بعد. أكمل التفعيل من الصفحة الرئيسية.',
        'Account is signed in, but the annual subscription is not activated yet. Complete activation from the home screen.',
      );

  // --- بطاقة تغطية الاشتراك (تجربة / سنوي) ---

  String get subscriptionCoverageTrialEyebrow =>
      _t('وضع التجربة', 'Trial mode');

  String get subscriptionCoverageTrialTitle =>
      _t('نسخة تجربة نشطة', 'Active trial edition');

  String subscriptionCoverageTrialBody(int days) => _en
      ? 'You are on a trial — not a paid annual plan. $days day(s) left. Contact an agent to activate the official yearly subscription.'
      : 'أنت على نسخة تجربة — وليست اشتراكاً سنوياً مدفوعاً. متبقٍ $days يوماً. تواصل مع وكيل لتفعيل الاشتراك السنوي الرسمي.';

  String get subscriptionCoverageAnnualEyebrow =>
      _t('تفعيل رسمي', 'Official activation');

  String get subscriptionCoverageAnnualTitle =>
      _t('اشتراك سنوي مفعّل', 'Annual subscription active');

  String get subscriptionCoverageAnnualBody => _t(
        'تم تفعيل البرنامج رسمياً لسنة كاملة على هذا الحساب والجهاز.',
        'The program is officially activated for a full year on this account and device.',
      );

  String subscriptionCoverageAnnualBodyUntil(String date) => _en
      ? 'Official yearly activation is active until $date.'
      : 'التفعيل السنوي الرسمي ساري حتى $date.';

  String get subscriptionCoverageAnnualPill =>
      _t('لمدة سنة', '1 year');

  String subscriptionCoverageDaysLeft(int days) =>
      _en ? '$days d left' : '$days يوم';

  String get subscriptionCoverageAgentsCta =>
      _t('وكلاؤنا — للتفعيل السنوي', 'Our agents — annual activation');

  String get subscriptionCoverageAnnualContinue =>
      _t('متابعة العمل', 'Continue');

  String get activationCelebrationTrialHeadline =>
      _t('مرحباً بك في نسخة التجربة', 'Welcome to the trial edition');

  String get activationCelebrationAnnualHeadline =>
      _t('تم التفعيل السنوي بنجاح', 'Annual activation complete');

  String get subscriberAccountSectionDetails =>
      _t('بيانات المشترك', 'Subscriber details');

  String get subscriberAccountSectionSubscription =>
      _t('بيانات الاشتراك', 'Subscription details');

  String get subscriberAccountFieldName => _t('اسم المشترك', 'Subscriber name');

  String get subscriberAccountFieldEmail => _t('البريد الإلكتروني', 'Email');

  String get subscriberAccountFieldOrg => _t('رقم المؤسسة', 'Organization id');

  String get subscriberAccountFieldCountry => _t('الدولة', 'Country');

  String get subscriberAccountFieldPhone => _t('رقم الهاتف', 'Phone number');

  String get subscriberAccountFieldVoucher => _t('رمز القسيمة', 'Voucher code');

  String get subscriberAccountFieldDevices =>
      _t('الأجهزة المُفعَّلة', 'Activated devices');

  String get subscriberAccountFieldRedeemedAt =>
      _t('تاريخ التفعيل', 'Activated at');

  String get subscriberAccountActionManageVoucher =>
      _t('إدارة القسيمة والأجهزة', 'Manage voucher & devices');

  String get subscriberAccountActionSignOut =>
      _t('تسجيل خروج من حساب المشترك', 'Sign out of subscriber account');

  String get subscriberAccountSignOutHint => _t(
        'يُتيح تسجيل الخروج دخول فريق العمل على هذا الجهاز.',
        'Signing out lets team members sign in on this device.',
      );

  String get subscriberAccountSignOutConfirmTitle =>
      _t('تأكيد تسجيل الخروج', 'Confirm sign-out');

  String get subscriberAccountSignOutConfirmBody => _t(
        'سيخرج المشترك من هذا الجهاز. لن تُحذف بيانات المتجر، ويمكن إعادة دخول المشترك لاحقاً (بما في ذلك دون إنترنت بكلمة المرور نفسها). يمكن لفريق العمل تسجيل الدخول أيضاً. هل تريد المتابعة؟',
        'The subscriber will be signed out from this device. Store data is kept. The same subscriber can sign in again later (including offline with the same password). Team members can sign in too. Continue?',
      );

  String get subscriberAccountCopiedToClipboard =>
      _t('تم النسخ إلى الحافظة.', 'Copied to clipboard.');

  String get subscriberAccountCopyTooltip => _t('نسخ', 'Copy');

  String get subscriberAccountNoSubscription => _t(
        'لا يوجد اشتراك نشط على هذا الجهاز بعد.',
        'No active subscription on this device yet.',
      );

  // --- تأكيد تسجيل خروج فريق العمل ---

  String get staffLogoutConfirmTitle =>
      _t('تأكيد تسجيل الخروج', 'Confirm sign-out');

  String get staffLogoutConfirmBody => _t(
        'سيُنهي ذلك جلسة فريق العمل الحاليّة على هذا الجهاز ويعود البرنامج لوضع الزائر. لن تُحذف أي بيانات. هل تريد المتابعة؟',
        'This will end the current staff session on this device and switch back to guest mode. No data will be deleted. Continue?',
      );

  // --- ترحيب وشكر (سطح المكتب) ---

  String appWelcomeDialogTitle(String greeting) =>
      _en ? '$greeting!' : '$greeting!';

  String appWelcomeDialogBody(String storeName) => _t(
        'مرحباً بك في $storeName.\nنتمنى لك يوماً موفقاً مع MizaPos.',
        'Welcome to $storeName.\nWe wish you a productive day with MizaPos.',
      );

  String get appWelcomeOk => _t('متابعة', 'Continue');

  String get appThankYouDialogTitle =>
      _t('شكراً لاستخدامك MizaPos', 'Thank you for using MizaPos');

  String appThankYouDialogBody(String storeName) => _t(
        'شكراً لك على استخدام البرنامج.\nنراك قريباً — $storeName',
        'Thank you for using the program.\nSee you soon — $storeName',
      );

  // --- تأكيد إغلاق التطبيق ---

  String get appCloseConfirmTitle => _t('إغلاق MizaPos', 'Close MizaPos');

  String get appCloseConfirmBody => _t(
        'هل تريد إغلاق البرنامج الآن؟ سيتم حفظ التغييرات المعتمدة قبل الخروج.',
        'Do you want to close the program now? Saved changes will be preserved.',
      );

  String get appCloseAction => _t('إغلاق', 'Close');

  // --- مدخل تسجيل دخول فريق العمل ---

  String get menuStaffLogin => menuEmployeesSignIn;

  String get menuStaffLoginSubtitle => _t(
        'سجِّل الدخول بحساب موظف مُسجَّل في هذا الجهاز.',
        'Sign in with a staff account registered on this device.',
      );

  String get menuEmployeesSignIn =>
      _t('تسجيل دخول موظف', 'Employee sign-in');

  String get menuEmployeesManage =>
      _t('إدارة الموظفين والصلاحيات', 'Manage employees & permissions');

  String get employeesHubSubtitle => _t(
        'اختر ما تريد تنفيذه — الدخول للعمل اليومي أو إدارة الحسابات.',
        'Choose what you need — daily sign-in or account management.',
      );

  String get subscriberAccountStaffLoginCardTitle => _t(
        'دخول الموظفين',
        'Employee sign-in',
      );

  String get subscriberAccountStaffLoginCardBody => _t(
        'للكاشير والمحاسب وغيرهم: سجّل دخولك بحسابك دون تسجيل خروج المشترك.',
        'For cashiers, accountants, and others: sign in with your account without signing the subscriber out.',
      );

  String get subscriberAccountStaffLoginCta =>
      _t('تسجيل الدخول', 'Sign in');

  // --- شاشة دخول الموظفين (LoginScreen) ---

  String get staffLoginHeroTitle => _t('الموظفين', 'Employees');

  String get staffLoginHeroSubtitle => _t(
        'سجّل الدخول بحساب موظف ضبطه مالك النسخة على هذا الجهاز.',
        'Sign in with a staff account the owner configured on this device.',
      );

  String get staffLoginUsernameLabel => _t('اسم الدخول', 'Username');

  String get staffLoginUsernameHint => _t(
        'اسم المستخدم الذي زوّدك به مالك النسخة',
        'The username provided by the store owner',
      );

  String get staffLoginValidationEmpty => _t(
        'أدخل اسم الدخول وكلمة المرور للمتابعة.',
        'Enter your username and password to continue.',
      );

  String get staffLoginFooterTipManageAccount => _t(
        'لإدارة بيانات الاشتراك استعمل «حسابي» من القائمة الإدارية.',
        'To manage subscription data use «My account» from the admin menu.',
      );

  String get showPassword => _t('إظهار كلمة المرور', 'Show password');
  String get hidePassword => _t('إخفاء كلمة المرور', 'Hide password');

  /// ملاحظة تظهر داخل صفحة «حسابي» وحوار القسيمة عندما يفتحها عضو فريق العمل:
  /// إدارة الجلسة/تحرير الجهاز محصورة بصاحب الاشتراك (المالك).
  String get subscriberAccountOwnerOnlyNote => _t(
        'إدارة جلسة المشترك وتحرير الجهاز من القسيمة متاحة لصاحب الاشتراك (المالك) فقط.',
        'Subscriber session management and releasing the device from the voucher are available only to the subscription owner.',
      );

  // وضع قراءة-فقط بعد إلغاء القسيمة
  String get voucherReadOnlyBannerTitle =>
      _t('وضع القراءة فقط', 'Read-only mode');
  String get voucherReadOnlyBannerBody => _t(
        'اشتراك هذا الجهاز معلَّق. يمكنك تصفّح البيانات لكن لا يمكنك إنشاء أو تعديل أي عملية حتى يُجدَّد الاشتراك.',
        'This device subscription is suspended. You can browse data but cannot create or modify any record until renewed.',
      );
  String get voucherReadOnlyBannerAction =>
      _t('فتح حوار التفعيل', 'Open activation dialog');

  /// نص الحالة داخل حوار التفعيل.
  String activationDialogCoverageAnnual(String date) => _en
      ? 'Annual subscription for this account is active until $date.'
      : 'الاشتراك السنوي لهذا الحساب ساري حتى $date.';

  String activationDialogCoverageTrial(String date) => _en
      ? 'Trial until $date. After it ends, pay once on the website then tap «Activate».'
      : 'التجربة سارية حتى $date. بعد انتهائها: ادفع من صفحة التفعيل على الموقع ثم اضغط «تفعيل».';

  String get activationDialogCoverageGrandfather => _t(
        'وصول كامل تلقائياً عند الترقية من إصدارات سابقة.',
        'Full access granted for installs upgraded from older versions.',
      );

  String get activationDialogCoverageLegacy => _t(
        'هذا الحساب على ترخيص قديم دون تاريخ انتهاء محدد.',
        'This account uses legacy licensing without an expiry date.',
      );

  String get activationDialogCoverageNone => _t(
        'لا يوجد تفعيل كامل بعد. انسخ «كود ربط الجهاز» أدناه وأكمل الربط من صفحة التفعيل على الويب (حتى جهازين لكل اشتراك)، ثم «تفعيل». دخول فريق العمل من القائمة اختياري.',
        'Not fully activated yet. Copy your device link code below, finish linking on the activation website (up to two devices per subscription), then «Activate». Staff sign-in from the menu is optional.',
      );

  String get activationDialogCoverageGuest => _t(
        'أنت زائر: للنسخة الكاملة انسخ كود الجهاز وأكمل الربط من صفحة التفعيل على الويب مع بريد المشترك وكلمة المرور، ثم «تفعيل».',
        'Guest: copy the device code and complete linking on the activation website with the subscriber email and password, then «Activate».',
      );

  String get activationSignInBeforeGenericAnnual => _t(
        'فعّل الاشتراك من صفحة الويب ثم «تفعيل».',
        'Activate from the website, then «Activate».',
      );

  /// عنوان احتفالي في حوار التفعيل الناجح.
  String get activationAccountActiveHeadline =>
      _t('الحساب مفعّل', 'Account activated');

  String get activationCelebrationCongrats =>
      _t('مبروك التفعيل!', 'Congratulations on activating!');

  String get loginFailed =>
      _t('بيانات الدخول غير صحيحة', 'Invalid credentials');
  String get authEmailLabel => _t('البريد الإلكتروني', 'Email');
  String get authEmailHint => _t('example@domain.com', 'example@domain.com');
  String get authForgotPassword => _t('نسيت كلمة المرور؟', 'Forgot password?');
  String get authNoAccount => _t('ليس لديك حساب؟', 'No account?');
  String get authRegisterLink => _t('إنشاء حساب', 'Sign up');
  String get authLoginActivationLinkNote => _t(
      'التفعيل عبر صفحة الويب: كود الجهاز من البرنامج ثم الربط هناك.',
      'Activation uses the website: device code from the app, then link there.');
  String get authStaffLoginSubtitle => _t(
        'للفريق (كاشير، محاسب…): أدخل اسم الدخول وكلمة المرور التي يضبطها مالك النسخة.',
        'For staff (cashier, accountant…): enter the username and password the owner configured.',
      );
  String get authActivateFromMenuNote => _t(
        'للتفعيل الكامل: من القائمة الرئيسية اختر «تفعيل الاشتراك» وأدخل الكود.',
        'For full activation: from the main menu choose «Activate subscription» and enter your code.',
      );
  String get authRegisterTitle => _t('إنشاء حساب جديد', 'Create account');
  String get authFullName => _t('الاسم الكامل', 'Full name');
  String get authPhoneNational =>
      _t('رقم الهاتف (بدون كود الدولة)', 'Phone number (without country code)');
  String get authDialCodeLabel => _t('رمز الدولة', 'Country code');

  String get dialPickerSheetTitle =>
      _t('اختر رمز الاتصال', 'Choose country calling code');

  String get dialPickerSearchHint =>
      _t('ابحث بالدولة أو الرمز…', 'Search by country or code…');

  String get dialPickerCustomSectionTitle => _t(
        'رمز غير مدرج؟',
        'Code not listed?',
      );

  String get dialPickerCustomLabel =>
      _t('رمز يدوي (مثال +353)', 'Custom code (e.g. +353)');

  String get dialPickerCustomHint =>
      _t('أدخل + متبوعاً بالأرقام', 'Enter + then digits');

  String get dialPickerApply => _t('تطبيق الرمز', 'Apply code');

  String get dialPickerInvalidCode => _t(
        'رمز غير صالح. استخدم + ثم أرقام فقط (مثال +216).',
        'Invalid code. Use + followed by digits (e.g. +216).',
      );

  String get dialPickerNoResults => _t(
        'لا توجد دولة مطابقة. استخدم الإدخال اليدوي بالأسفل.',
        'No matching country. Use manual entry below.',
      );

  String get authConfirmPassword => _t('تأكيد كلمة المرور', 'Confirm password');
  String get authSubmitRegister =>
      _t('إرسال طلب التسجيل', 'Submit registration');
  String get authSignupPendingBody => _t(
        'تم إنشاء حسابك بنجاح ويمكنك تسجيل الدخول فورًا بنفس البيانات التي أدخلتها. تعمل ضمن صلاحيات محدودة إلى أن تُكمّل التفعيل المدفوع من صفحة التفعيل على الويب؛ عند الموافقة سيصلك رمز التفعيل على بياناتك المسجّلة.',
        'Your account has been created successfully, and you can sign in immediately with the same credentials. You work within limited features until you complete paid activation from the web activation page; once approved, your activation code is sent to your registered details.',
      );
  String get authSignupCelebrationTitle => _t('تهانينا! تم إنشاء حسابك بنجاح',
      'Congratulations! Your account is created');
  String get authSignupCelebrationSubtitle =>
      _t('أهلاً بك في عائلة MizaPos', 'Welcome to the MizaPos family');
  String authSignupCelebrationPersonalized(String fullName) => _en
      ? 'Hi $fullName, welcome to MizaPos'
      : 'أهلاً $fullName، نرحب بك في MizaPos';
  String get authSignupCelebrationAdminReceived => _t(
        'تم إرسال طلبك إلى الإدارة بنجاح',
        'Your request has been successfully sent to admin',
      );
  String get authSubscriberWelcomeBody => _t(
        'يمكنك إغلاق هذا الحوار وتجربة البرنامج الآن بصلاحيات محدودة، أو المتابعة لطلب تفعيل الاشتراك بإدخال رمز القسيمة الذي تحصل عليه من مطوّر البرنامج.',
        'You can close this dialog and try the app now with limited features, or continue to activate your subscription by entering the voucher code you receive from the developer.',
      );
  String authSubscriberWelcomeBodyEmailTrial(int days) => _en
      ? 'You have a free $days-day trial with full access to all core POS features (sales, inventory, purchases, reports, and more). Cloud subscriptions are not included during the trial.'
      : 'لديك تجربة مجانية لمدة $days ${days == 1 ? 'يوم' : 'أيام'} — وصول كامل لكل ميزات البرنامج الأساسية (مبيعات، مخزون، مشتريات، تقارير، وغيرها). اشتراكات السحابة غير مشمولة أثناء التجربة.';
  String authSubscriberWelcomeTrialBadge(int days) => _en
      ? '$days-day full trial'
      : 'تجربة كاملة — $days ${days == 1 ? 'يوم' : 'أيام'}';
  String get authSubscriberWelcomeTryApp =>
      _t('ابدأ التجربة المجانية', 'Start free trial');
  String get authSubscriberWelcomeActivateVoucher => _t(
        'لدي قسيمة — تفعيل الاشتراك',
        'I have a voucher — activate',
      );
  String get authSubscriberTrialActiveTitle =>
      _t('تجربتك نشطة', 'Your trial is active');
  String authSubscriberTrialActiveBody(int days) => _en
      ? 'You have $days ${days == 1 ? 'day' : 'days'} left with full access to all core POS features. Cloud subscriptions are not included during the trial.'
      : 'متبقٍ $days ${days == 1 ? 'يوم' : 'أيام'} على تجربتك — وصول كامل لكل ميزات البرنامج الأساسية. اشتراكات السحابة غير مشمولة.';
  String get authSubscriberTrialActiveContinue =>
      _t('متابعة إلى البرنامج', 'Continue to the app');
  String get authBackToLogin => _t('العودة لتسجيل الدخول', 'Back to sign in');
  String get authLoginNow => _t('تسجيل الدخول الآن', 'Sign in now');
  String get authResetPasswordTitle =>
      _t('إعادة تعيين كلمة المرور', 'Reset password');
  String get authResetPasswordHelp => _t(
        'أدخل بريدك الإلكتروني فقط. سنرسل كلمة مرور مؤقتة إلى نفس البريد.',
        'Enter your email only. A temporary password will be sent to that email.',
      );
  String get authResetSubmit =>
      _t('إرسال كلمة مرور مؤقتة', 'Send temporary password');
  String get authResetOk => _t('تم تحديث كلمة المرور.', 'Password updated.');
  String get authResetFail => _t(
        'تعذر تنفيذ إعادة التعيين الآن. حاول لاحقًا.',
        'Could not complete reset now. Please try again later.',
      );
  String get authResetSentTitle =>
      _t('تم إرسال كلمة المرور المؤقتة', 'Temporary password sent');
  String get authResetSentBody => _t(
        'تم إرسال كلمة مرور مؤقتة إلى بريدك الإلكتروني. بعد تسجيل الدخول، يجب تغيير كلمة المرور فورًا من «فريق العمل».',
        'A temporary password was sent to your email. After signing in, you must change the password immediately from Team.',
      );
  String get authResetEmailNotFound => _t(
        'لا يوجد حساب نشط بهذا البريد.',
        'No active account found for this email.',
      );
  String get authResetSmtpMissing => _t(
        'لا يمكن الإرسال لأن إعدادات البريد (SMTP) غير مهيأة على هذا الجهاز.',
        'Cannot send email because SMTP settings are not configured on this device.',
      );
  String get authErrWelcomeMailFailed => _t(
        'تعذّر إرسال رسالة الترحيب. حاول لاحقاً أو تواصل مع الدعم.',
        'Could not send the welcome email. Try again later or contact support.',
      );
  String get authPasswordMismatchShort =>
      _t('كلمتا المرور غير متطابقتين.', 'Passwords do not match.');
  String get authPasswordTooShort =>
      _t('كلمة المرور قصيرة جداً.', 'Password is too short.');
  String get authErrNoOrg => _t(
        'قاعدة البيانات غير مهيأة.',
        'Database is not initialized.',
      );
  String get authErrEmailInvalid => _t('البريد غير صالح.', 'Invalid email.');
  String get authErrPhoneInvalid =>
      _t('رقم الهاتف غير صالح.', 'Invalid phone number.');
  String get authErrEmailTaken =>
      _t('البريد مستخدم بالفعل.', 'Email already in use.');
  String get authSignupVerifyTitle => _t(
        'تحقق من بريدك الإلكتروني',
        'Verify your email',
      );
  String authSignupVerifyBody(String email) => _en
      ? 'We sent a welcome message to $email with the official MizaPos website and a confirmation link. Open your inbox and tap «Confirm email» to prove you own this address.'
      : 'أرسلنا رسالة ترحيب إلى $email تتضمن الموقع الرسمي لـ MizaPos ورابط تأكيد. افتح بريدك واضغط «تأكيد البريد الإلكتروني» لإثبات أنك صاحب هذا العنوان.';
  String authSignupVerifyBodyQueued(String email) => _en
      ? 'Your account was saved on this device. When internet returns, a welcome email with a confirmation link will be sent to $email. The official website:'
      : 'حُفظ حسابك على هذا الجهاز. عند عودة الإنترنت ستُرسل رسالة ترحيب مع رابط تأكيد إلى $email. الموقع الرسمي:';
  String get authSignupVerifyResend =>
      _t('إعادة الإرسال', 'Resend');
  String get authSignupVerifyResentOk => _t(
        'أُعيد إرسال رسالة التأكيد إلى بريدك.',
        'Confirmation email resent to your inbox.',
      );
  String get authSignupVerifyResendFailed => _t(
        'تعذّر إرسال الرسالة. تحقق من الإنترنت أو إعدادات البريد على الخادم.',
        'Could not send the email. Check internet or server mail settings.',
      );
  String get authSignupVerifyOpenSite =>
      _t('فتح الموقع', 'Open website');
  String get authErrNoInternet => _t(
        'لا يوجد اتصال بالإنترنت أو تعذّر الوصول إلى خادم التسجيل.',
        'No internet or cannot reach the signup server.',
      );
  String get authLoginRequiresActivationServer => _t(
        'تسجيل الدخول يتطلّب الاتصال بخادم التفعيل لمزامنة الحساب. تحقّق من الإنترنت وحاول مجدداً.',
        'Sign-in requires reaching the activation server to sync your account. Check your connection and try again.',
      );
  String get authErrActivationPending => _t(
        'يوجد طلب مسجّل لنفس البريد وبانتظار إكمال التفعيل بالكود المرسل.',
        'A signup for this email is awaiting activation with the issued code.',
      );
  String get authErrRemoteForbidden => _t(
        'رفض الخادم الطلب (تحقق من السرّ المشترك أو الإعدادات).',
        'Server rejected the request (check shared secret / configuration).',
      );
  String get authErrRemoteValidation => _t(
        'البيانات غير مقبولة من الخادم.',
        'The server rejected the submitted data.',
      );
  String get authErrRemoteServer => _t(
        'خطأ من الخادم أثناء التسجيل. حاول لاحقاً.',
        'Server error during signup. Try again later.',
      );
  String get authSignupRequiresInternetShort => _t(
        'طلب التسجيل يُرسَل للإدارة عبر الخادم ويحتاج إنترنت. بعد الإرسال يمكنك تسجيل الدخول ضمن صلاحيات محدودة إلى التفعيل الكامل. للدعم: واتساب +970599488939',
        'Registration is sent to admin through the server and requires internet. After submission you can sign in with limited features until full activation. Support WhatsApp: +970599488939',
      );

  String get authSignupRequiresInternetActivationShort => _t(
        'طلب التسجيل يُرسَل عبر الخادم ويحتاج إنترنت. بعد التسجيل يمكنك تسجيل الدخول، لكن التفعيل الكامل والصلاحيات الواسعة تتطلّب رمز التفعيل من لوحة التفعيل على الويب بعد اعتماد الطلب. للدعم: واتساب +970599488939',
        'Registration goes through the server and needs internet. After signup you can sign in, but full activation and broader permissions require the activation code from the web portal once approved. Support WhatsApp: +970599488939',
      );
  String get authSignupRemoteDisabledBanner => _t(
        'التسجيل عبر الخادم معطّل (مثلاً SIGNUP_REMOTE_DISABLED=1). الطلب يُحفظ على هذا الجهاز فقط. '
            'لإعادة التفعيل أزل ذلك المتغير، أو ضع ملف remote_signup.json بجانب البرنامج، أو عرّف SIGNUP_API_BASE_URL.',
        'Remote signup is disabled (e.g. SIGNUP_REMOTE_DISABLED=1) — requests stay on this PC only. '
            'Remove that variable, add remote_signup.json next to the app, or set SIGNUP_API_BASE_URL to re-enable.',
      );
  String get authSignupLocalOwnerApprovalShort => _t(
        'طلب «إنشاء حساب» هنا يُرسل إلى مالك المتجر ليقبله أو يرفضه من «فريق العمل» داخل البرنامج فقط. أما تفعيل الاشتراك الأول للزبون بعد الشراء فيتم عبر صفحة/خادم التفعيل على الويب كما هو معتاد. يمكن لمالك المتجر أيضاً إضافة موظفين مباشرة من نفس الشاشة.',
        'This signup request goes to the store owner for approval under «Team» inside the app only. The purchaser’s first subscription activation after purchase still uses the web activation server as usual. The owner can also add staff directly from the same screen.',
      );
  String get authSignupPendingBodyRemote => _t(
        'تم إنشاء حسابك على الخادم بنجاح ويمكنك تسجيل الدخول فورًا بنفس البيانات. تعمل ضمن صلاحيات محدودة إلى أن تُكمّل التفعيل من صفحة التفعيل على الويب؛ عند اعتماد الطلب يصلك رمز التفعيل على بياناتك المسجّلة.',
        'Your account has been created on the server, and you can sign in immediately with your submitted credentials. You work within limited features until you complete activation from the web portal; once approved, your activation code is sent to your registered details.',
      );

  /// عند تفعيل خادم التفعيل: لا وعد بتجربة 30 يوماً؛ التفعيل بالرمز من الويب.
  String get authSignupPendingBodyNeedsWebActivation => _t(
        'تم إنشاء حسابك بنجاح ويمكنك تسجيل الدخول فورًا بنفس البيانات. الجهاز لا يُعتبر مفعّلاً بالكامل حتى تُدخل رمز التفعيل من لوحة التفعيل على الويب بعد اعتماد طلبك من الإدارة؛ حتى ذلك الحين تبقى كثير من الصلاحيات مقيدة.',
        'Your account was created — you can sign in right away with the same credentials. This device is not fully activated until you enter the activation code from the web portal after your request is approved; many permissions stay limited until then.',
      );

  String get authSignupPendingBodyRemoteNeedsWebActivation => _t(
        'تم إنشاء حسابك على الخادم ويمكنك تسجيل الدخول فورًا. بعد الموافقة على الطلب من لوحة التفعيل على الويب سيصلك رمز التفعيل — أدخله من «تفعيل الاشتراك» في البرنامج لتفعيل الجهاز والصلاحيات الكاملة.',
        'Your account is on the server — sign in anytime. After approval on the web activation portal you receive an activation code — enter it under «Activate subscription» in the app to fully activate this device and unlock permissions.',
      );
  String get authSignupQueuedOfflineTitle => _t(
        'تم حفظ الطلب محلياً',
        'Saved offline',
      );
  String get authSignupQueuedOfflineBody => _t(
        'لا يتوفر اتصال بالإنترنت أو الخادم الآن. حُفظ طلب التسجيل على هذا الجهاز وسيُرسَل تلقائيًا عند عودة الاتصال. يمكنك الاستمرار كزائر أو بعد توفر الحساب ضمن الصلاحيات المحدودة إلى التفعيل الكامل. للدعم: واتساب +970599488939',
        'No internet or server is currently unreachable. Your signup request was saved on this PC and will be sent automatically when online. You can continue as a guest or, once the account exists, with limited features until full activation. Support WhatsApp: +970599488939',
      );

  String get authSignupQueuedOfflineBodyNeedsActivation => _t(
        'لا يتوفر اتصال بالإنترنت أو الخادم الآن. حُفظ الطلب محلياً وسيُرسَل عند عودة الاتصال. يمكنك تسجيل الدخول إن وُجد حساب، لكن التفعيل الكامل يتطلّب رمزاً من لوحة التفعيل بعد اعتماد الطلب على الخادم.',
        'No connection right now. Your request was saved locally and will sync when online. You may be able to sign in if an account exists, but full activation needs a code from the web portal after the server approves your request.',
      );
  String signupQueuedRemoteSubtitle(int count) => _en
      ? '$count signup request(s) waiting to sync to the server.'
      : 'يوجد $count طلب/طلبات محفوظة محلياً وبانتظار الإرسال للخادم.';
  String get authErrPendingExists => _t(
        'يوجد طلب تسجيل قيد المراجعة لهذا البريد.',
        'A pending signup already exists for this email.',
      );
  String get signupApprovalViaWebTitle =>
      _t('موافقة التسجيل عبر الموقع', 'Signup approval on the web');
  String signupApprovalViaWebBody(String url) => _en
      ? 'Pending registrations are processed here:\n$url'
      : 'معالجة طلبات التسجيل المعلّقة تتم من لوحة الموافقة على الرابط التالي:\n$url';
  String get signupApprovalViaWebOpenButton =>
      _t('فتح صفحة الموافقة', 'Open approval page');
  String get signupApprovalViaWebLaunchFailed =>
      _t('تعذّر فتح المتصفّح.', 'Could not open the browser.');

  String get signupRequestsSection =>
      _t('طلبات التسجيل بانتظار الموافقة', 'Pending signup requests');
  String get signupRequestsEmpty =>
      _t('لا توجد طلبات.', 'No pending requests.');
  String get signupApprove => _t('موافقة وتفعيل', 'Approve & activate');
  String get signupReject => _t('رفض', 'Reject');
  String signupRequestLine(String name, String email) =>
      _en ? '$name — $email' : '$name — $email';
  String get signupApprovedOk =>
      _t('تمت الموافقة وتفعيل الحساب.', 'Account approved.');
  String get signupRejectedOk => _t('تم رفض الطلب.', 'Request rejected.');
  String signupApproveConfirm(String email) => _en
      ? 'Approve and activate «$email»?'
      : 'الموافقة وتفعيل الحساب «$email»؟';
  String signupRejectConfirm(String email) =>
      _en ? 'Reject signup «$email»?' : 'رفض طلب «$email»؟';

  /// ملخص الدولة والهاتف في الموافقة / القائمة / الجدول.
  String signupPhoneCountrySummary(String dialCode, String nationalDigits) {
    final d = dialCode.trim().isEmpty ? '—' : dialCode.trim();
    final n = nationalDigits.trim().isEmpty ? '—' : nationalDigits.trim();
    return _en
        ? 'Country code: $d — Phone: $n'
        : 'رمز الدولة: $d — رقم الهاتف: $n';
  }

  String signupApproveConfirmFull(
          String email, String dialCode, String nationalDigits) =>
      '${signupApproveConfirm(email)}\n${signupPhoneCountrySummary(dialCode, nationalDigits)}';

  String signupRejectConfirmFull(
          String email, String dialCode, String nationalDigits) =>
      '${signupRejectConfirm(email)}\n${signupPhoneCountrySummary(dialCode, nationalDigits)}';

  String get usersColPhoneFull => _t('رقم الهاتف', 'Phone number');

  /// عمود مرجعي بعد اعتماد التسجيل (لم يعد يُصدَر كود من التطبيق).
  String get usersColSignupActivationCode =>
      _t('مرجع التفعيل', 'Activation ref.');

  /// عنوان الموقع كما يُعرض للزبون في رسالة التفعيل.
  static const String mizaPosWebsiteDisplay = 'www.MizaPos.com';

  /// رابط الموقع الكامل في رسالة HTML.
  static const String mizaPosWebsiteHref = 'https://www.MizaPos.com';

  String get activationEmailSubject =>
      _t('MizaPos — تم اعتماد حسابك', 'MizaPos — Account approved');

  String activationEmailBody(String recipientName, String? code) {
    if (code == null || code.trim().isEmpty) {
      return _activationWebOnlyPlain(recipientName);
    }
    return _en
        ? 'Hello $recipientName,\n\n'
            'Your MizaPos account has been approved.\n\n'
            'Legacy activation code (if applicable):\n$code\n\n'
            'Website: ${AppLocalizations.mizaPosWebsiteDisplay}\n\n'
            'Regards,\nMizaPos Team'
        : _activationPlainArabic(recipientName, code);
  }

  /// نص عربي موحّد لرسالة التفعيل (mailto / SMTP نصّي) — عند وجود كود قديم.
  String _activationPlainArabic(String recipientName, String code) =>
      'مرحباً $recipientName،\n\n'
      'تمت الموافقة على حسابك في MizaPos.\n\n'
      'كود تفعيل (قديم):\n'
      '$code\n\n'
      'موقع البرنامج: ${AppLocalizations.mizaPosWebsiteDisplay}\n\n'
      'مع تحياتنا،\nفريق MizaPos';

  /// ترحيب بدون كود — التفعيل من صفحة الويب بعد الدفع.
  String _activationWebOnlyPlain(String recipientName) => _en
      ? 'Hello ${recipientName.trim()},\n\n'
          'Your MizaPos account has been approved.\n\n'
          'Program price: US \$70 per year. It covers the Windows desktop app and the Android app linked to the same email.\n\n'
          'After you pay on our official website, open MizaPos, sign in with this email, open «Activate program», then tap «Activate».\n\n'
          'Website: ${AppLocalizations.mizaPosWebsiteDisplay}\n\n'
          'Regards,\nMizaPos Team'
      : 'مرحباً ${recipientName.trim()}،\n\n'
          'تمت الموافقة على حسابك في MizaPos.\n\n'
          'سعر البرنامج: 70 دولاراً أمريكياً سنوياً، ويشمل نسخة ويندوز ونسخة أندرويد المرتبطة بنفس البريد.\n\n'
          'بعد إتمام الدفع من صفحة التفعيل على الموقع الرسمي: سجّل الدخول في البرنامج بنفس البريد، ثم من القائمة اختر «تفعيل البرنامج» واضغط «تفعيل».\n\n'
          'موقع البرنامج: ${AppLocalizations.mizaPosWebsiteDisplay}\n\n'
          'مع تحياتنا،\nفريق MizaPos';

  /// عنوان البريد المرسل للزبون عبر SMTP — دائماً بالعربية (مع كود قديم).
  String get activationEmailSubjectOutboundArabic =>
      'MizaPos — تم اعتماد حسابك وكود التفعيل';

  /// عنوان البريد — تفعيل عبر الموقع فقط.
  String get activationEmailSubjectWebOutboundArabic =>
      'MizaPos — تم اعتماد حسابك (التفعيل من الموقع)';

  /// جسم نصّي عربي/إنجليزي للزبون (SMTP / mailto).
  String activationEmailBodyOutboundArabic(String recipientName, String? code) {
    if (code == null || code.trim().isEmpty) {
      return _activationWebOnlyPlain(recipientName);
    }
    return _activationPlainArabic(recipientName, code.trim());
  }

  static String _activationEsc(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  /// قالب HTML عربي — تفعيل من الموقع دون كود.
  String _activationWebOnlyHtmlArabic(String n) {
    const href = AppLocalizations.mizaPosWebsiteHref;
    const display = AppLocalizations.mizaPosWebsiteDisplay;
    return '''
<!DOCTYPE html>
<html dir="rtl" lang="ar">
<head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head>
<body style="margin:0;padding:0;background:#f1f5f9;font-family:'Segoe UI',Tahoma,'Arabic UI Text',Arial,sans-serif;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f1f5f9;padding:24px 12px;"><tr><td align="center">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:560px;background:#ffffff;border-radius:16px;overflow:hidden;box-shadow:0 12px 40px rgba(15,23,42,0.12);">
<tr><td style="background:linear-gradient(135deg,#2563eb,#4f46e5);padding:26px 22px;text-align:center;">
<div style="color:#fff;font-size:22px;font-weight:800;letter-spacing:-0.5px;">MizaPos</div>
<div style="color:rgba(255,255,255,0.92);font-size:14px;margin-top:8px;font-weight:600;">اعتماد الحساب والتفعيل عبر الموقع</div></td></tr>
<tr><td style="padding:26px 22px;color:#1e293b;font-size:17px;line-height:1.85;text-align:right;">
<p style="margin:0 0 14px;">مرحباً <strong>$n</strong>،</p>
<p style="margin:0 0 14px;color:#475569;">تمت الموافقة على حسابك. سعر البرنامج <strong>70 دولاراً أمريكياً سنوياً</strong> ويشمل نسخة ويندوز وأندرويد لنفس البريد.</p>
<p style="margin:0 0 14px;color:#475569;">بعد الدفع من <strong>صفحة التفعيل</strong> على الموقع: سجّل الدخول في البرنامج، ثم «تفعيل البرنامج» ← «تفعيل».</p>
<p style="margin:22px 0 0;text-align:center;"><a href="$href" style="color:#2563eb;font-weight:700;text-decoration:none;font-size:16px;">$display</a></p>
<p style="margin:18px 0 0;color:#94a3b8;font-size:14px;text-align:center;">مع تحياتنا،<br/>فريق MizaPos</p>
</td></tr></table></td></tr></table></body></html>''';
  }

  /// قالب HTML عربي للزبون — خط واضح، RTL، الكود monospace ثابت، رابط الموقع.
  String _activationHtmlArabic(String n, String c) {
    const href = AppLocalizations.mizaPosWebsiteHref;
    const display = AppLocalizations.mizaPosWebsiteDisplay;
    return '''
<!DOCTYPE html>
<html dir="rtl" lang="ar">
<head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head>
<body style="margin:0;padding:0;background:#f1f5f9;font-family:'Segoe UI',Tahoma,'Arabic UI Text',Arial,sans-serif;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f1f5f9;padding:24px 12px;"><tr><td align="center">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:560px;background:#ffffff;border-radius:16px;overflow:hidden;box-shadow:0 12px 40px rgba(15,23,42,0.12);">
<tr><td style="background:linear-gradient(135deg,#2563eb,#4f46e5);padding:26px 22px;text-align:center;">
<div style="color:#fff;font-size:22px;font-weight:800;letter-spacing:-0.5px;">MizaPos</div>
<div style="color:rgba(255,255,255,0.92);font-size:14px;margin-top:8px;font-weight:600;">تفعيل البرنامج</div></td></tr>
<tr><td style="padding:26px 22px;color:#1e293b;font-size:17px;line-height:1.85;text-align:right;">
<p style="margin:0 0 14px;">مرحباً <strong>$n</strong>،</p>
<p style="margin:0 0 14px;color:#475569;">تمت الموافقة على حسابك. استخدم الكود أدناه لتفعيل برنامج <strong>MizaPos</strong> على جهاز العمل.</p>
<div style="margin:22px 0;text-align:center;">
<table role="presentation" cellpadding="0" cellspacing="0" style="margin:0 auto;background:#f8fafc;border:2px dashed #cbd5e1;border-radius:14px;"><tr><td style="padding:18px 24px;text-align:center;">
<div style="font-size:13px;color:#64748b;margin-bottom:10px;font-weight:700;">كود التفعيل</div>
<div style="font-family:Consolas,'Courier New','Segoe UI Mono',monospace;font-size:17px;font-weight:700;color:#0f172a;letter-spacing:0.06em;direction:ltr;unicode-bidi:plaintext;text-align:center;">$c</div>
</td></tr></table></div>
<ol style="margin:14px 0;padding-right:22px;color:#475569;font-size:16px;line-height:1.75;">
<li style="margin-bottom:10px;">افتح برنامج <strong>MizaPos</strong> على جهازك.</li>
<li style="margin-bottom:10px;">من القائمة اختر <strong>«تفعيل البرنامج»</strong>.</li>
<li>الصق الكود ثم أكّد.</li></ol>
<p style="margin:22px 0 0;text-align:center;"><a href="$href" style="color:#2563eb;font-weight:700;text-decoration:none;font-size:16px;">$display</a></p>
<p style="margin:18px 0 0;color:#94a3b8;font-size:14px;text-align:center;">مع تحياتنا،<br/>فريق MizaPos</p>
</td></tr></table></td></tr></table></body></html>''';
  }

  /// HTML عربي للإرسال SMTP للزبون دائماً (بغض النظر عن لغة واجهة المالك).
  String activationEmailHtmlOutboundArabic(String recipientName, String? code) {
    final n = _activationEsc(recipientName.trim());
    if (code == null || code.trim().isEmpty) {
      return _activationWebOnlyHtmlArabic(n);
    }
    return _activationHtmlArabic(n, _activationEsc(code.trim()));
  }

  /// رسالة HTML للبريد بحسب لغة الواجهة (mailto لا يستخدم HTML عادةً).
  String activationEmailHtml(String recipientName, String? code) {
    final n = _activationEsc(recipientName.trim());
    if (code == null || code.trim().isEmpty) {
      return _activationWebOnlyHtmlArabic(n);
    }
    final c = _activationEsc(code.trim());
    const href = AppLocalizations.mizaPosWebsiteHref;
    const display = AppLocalizations.mizaPosWebsiteDisplay;
    if (_en) {
      return '''
<!DOCTYPE html>
<html lang="en">
<head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head>
<body style="margin:0;padding:0;background:#f1f5f9;font-family:'Segoe UI',Tahoma,Arial,sans-serif;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f1f5f9;padding:24px 12px;"><tr><td align="center">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:560px;background:#ffffff;border-radius:16px;overflow:hidden;box-shadow:0 12px 40px rgba(15,23,42,0.12);">
<tr><td style="background:linear-gradient(135deg,#2563eb,#4f46e5);padding:26px 22px;text-align:center;">
<div style="color:#fff;font-size:22px;font-weight:800;letter-spacing:-0.5px;">MizaPos</div>
<div style="color:rgba(255,255,255,0.92);font-size:14px;margin-top:8px;font-weight:600;">Program activation</div></td></tr>
<tr><td style="padding:26px 22px;color:#1e293b;font-size:16px;line-height:1.65;text-align:left;">
<p style="margin:0 0 14px;">Hello <strong>$n</strong>,</p>
<p style="margin:0 0 14px;color:#475569;">Your account has been approved. Use the code below to activate <strong>MizaPos</strong> on your computer.</p>
<div style="margin:22px 0;text-align:center;">
<table role="presentation" cellpadding="0" cellspacing="0" style="margin:0 auto;background:#f8fafc;border:2px dashed #cbd5e1;border-radius:14px;"><tr><td style="padding:18px 24px;text-align:center;">
<div style="font-size:12px;color:#64748b;margin-bottom:8px;font-weight:600;">Activation code</div>
<div style="font-family:Consolas,'Courier New',monospace;font-size:17px;font-weight:700;color:#0f172a;letter-spacing:0.05em;">$c</div>
</td></tr></table></div>
<ol style="margin:14px 0;padding-left:20px;color:#475569;font-size:15px;">
<li style="margin-bottom:8px;">Open MizaPos.</li>
<li style="margin-bottom:8px;">Choose <strong>Activate program</strong> from the menu.</li>
<li>Paste the code and confirm.</li></ol>
<p style="margin:22px 0 0;text-align:center;"><a href="$href" style="color:#2563eb;font-weight:700;text-decoration:none;font-size:15px;">$display</a></p>
<p style="margin:18px 0 0;color:#94a3b8;font-size:13px;text-align:center;">Regards,<br/>MizaPos Team</p>
</td></tr></table></td></tr></table></body></html>''';
    }
    return _activationHtmlArabic(n, c);
  }

  String get activationEmailFallbackTitle =>
      _t('تعذّر فتح البريد تلقائياً', 'Could not open your mail app');

  String activationEmailFallbackBody(String recipientName, String? code) =>
      activationEmailBodyOutboundArabic(recipientName, code);

  String get activationCopyCode => _t('نسخ الكود', 'Copy code');

  String get activationCodeCopied =>
      _t('تم نسخ كود التفعيل.', 'Activation code copied.');

  String get signupApprovedMailComposeOpened => _t(
        'تم فتح برنامج البريد لإرسال رسالة التفعيل إلى العميل.',
        'Mail app opened — send the activation message to the customer.',
      );

  String get signupApprovedMailSentInstant => _t(
        'تم إرسال رسالة التفعيل إلى بريد العميل فوراً.',
        'Activation email sent to the customer immediately.',
      );

  String get signupApprovedMailSmtpRetryCompose => _t(
        'تعذّر الإرسال التلقائي؛ تم فتح البريد لإرسال الرسالة يدوياً إن أمكن.',
        'Automatic send failed — mail app opened so you can send manually.',
      );

  /// عند غياب smtp_config أو كلمة مرور وهمية — التطبيق يعتمد على mailto أو الحوار.
  String get signupApprovedMailNoSmtpExplainManualSend => _t(
        'لا يوجد إعداد SMTP صالح (ملف smtp_config.json مع كلمة مرور تطبيق Google). '
            'سيُفتح البريد للإرسال اليدوي — اضغط «إرسال» في النافذة التي تظهر.',
        'No valid SMTP setup (smtp_config.json + Google app password). '
            'Opening your mail app — tap Send in the window that opens.',
      );

  String get reorderTilesTitle =>
      _t('ترتيب مربعات لوحة التحكم', 'Reorder dashboard tiles');
  String get reorderTilesHint => _t(
        'اضغط مطوّلاً على صف ثم اسحبه لإعادة ترتيب المربعات.',
        'Press and hold a row, then drag to reorder tiles.',
      );
  String get queriesHiddenSubtitle => _t(
        'لا يظهر في لوحة التحكم بدون صلاحية الاستعلامات المالية',
        'Hidden without financial reports permission',
      );
  String get reportsHubSubtitle => _t(
        'تقارير مالية وتشغيلية حسب الفترة',
        'Financial and operational reports by period',
      );
  String get reportsPeriodCardTitle => _t('فترة التقارير', 'Report period');
  String get reportsDateFromShort => _t('من', 'From');
  String get reportsDateToShort => _t('إلى', 'To');
  String get reportsSearchHint => _t(
        'بحث في أسماء الاستعلامات…',
        'Search query names…',
      );
  String get reportsClassicTooltip => _t(
        'تقارير إضافية (الوضع الكلاسيكي)',
        'More reports (classic)',
      );
  String get reportsNoMatches =>
      _t('لا توجد استعلامات مطابقة للبحث.', 'No matching queries.');
  String get reportsHubIntroCaption => _t(
        'في الشريط: «المتجر» ثم التواريخ بجانبه، ثم «إدارة المبيعات» و«إدارة المشتريات» — كل قائمة تقاريرها. ثم الرسم البياني والتقارير الكلاسيكية. أسفل الشريط يظهر رسم حركة المتجر للفترة المختارة.',
        'Toolbar: Store, dates beside it, then Sales and Purchases — each menu lists its reports. Then chart and classic. Below, store movement chart for the selected range.',
      );
  String get reportsColumnSalesShort =>
      _t('إدارة المبيعات', 'Sales management');
  String get reportsColumnStoreShort => _t('المتجر', 'Store');
  String get reportsColumnPurchasesShort =>
      _t('إدارة المشتريات', 'Purchases management');
  String reportsCategoryReportCount(int count) {
    if (_en) return count == 1 ? '1 report' : '$count reports';
    if (count == 1) return 'تقرير واحد';
    if (count == 2) return 'تقريران';
    return '$count تقارير';
  }

  String get reportsExecutiveOpen =>
      _t('فتح لوحة الاستعلامات التنفيذية', 'Open executive dashboard');

  String get storeMovementChartScreenTitle =>
      _t('حركة المتجر — الرسم البياني', 'Store movement — chart');
  String storeMovementChartLoadError(String err) => _en
      ? 'Could not load chart data: $err'
      : 'تعذّر تحميل بيانات الرسم: $err';
  String get storeMovementChartEmptyRange =>
      _t('لا توجد أيام في الفترة المحددة.', 'No days in the selected range.');
  String get storeMovementChartCaption => _t(
        'المحور: مجموع القيمة المطلقة للكميات اليومية (نشاط تقريبي للمخزون).',
        'Axis: sum of absolute daily quantities (approximate stock activity).',
      );
  String get storeMovementChartOpenTable =>
      _t('عرض الجدول التفصيلي', 'Open detail table');

  String get queriesHeroCardTitle => _t(
        'حركة المتجر — الرسم البياني',
        'Store movement — chart',
      );
  String get queriesHeroCardSubtitle => _t(
        'ملخص بصري لنشاط المخزون في الفترة أعلاه؛ للأرقام التفصيلية استخدم الجدول.',
        'Visual summary for the period above; use the table for line-level detail.',
      );
  String get queriesHeroCardButton =>
      _t('فتح الرسم البياني', 'Open chart');

  String get queriesToolbarJumpSales =>
      _t('قسم المبيعات', 'Sales section');
  String get queriesToolbarJumpStore =>
      _t('حركة المتجر (جدول)', 'Store table');
  String get queriesToolbarJumpPurchases =>
      _t('قسم المشتريات', 'Purchases section');
  String get queriesToolbarOpenChart =>
      _t('الرسم البياني', 'Chart');
  String get queriesToolbarClassicShort =>
      _t('تقارير كلاسيكية', 'Classic reports');
  String get queriesToolbarHintLine => _t(
        'اضغط أحد الأقسام لفتح قائمة التقارير؛ التواريخ بجانب «المتجر»؛ «الرسم البياني» يفتح الرسم في صفحة كاملة.',
        'Tap a section for its report list; dates sit beside Store; Chart opens the full-screen chart.',
      );
  String get restoreDefaultOrder => _t('استعادة الافتراضي', 'Restore default');
  String get applyOrder => _t('اعتماد الترتيب', 'Apply order');

  String get confirmExitTitleAuto => _t('تأكيد الإغلاق', 'Confirm exit');
  String get confirmExitTitleManual => _t('إغلاق البرنامج', 'Exit application');
  String confirmExitWithBackup(String drive) => _en
      ? 'A backup will be created on drive $drive before closing. Continue?'
      : 'سيتم إنشاء نسخة احتياطية على القرص $drive قبل الإغلاق. هل تريد المتابعة؟';
  String get confirmExitWithBackupMobile => _t(
        'سيتم حفظ نسخة احتياطية داخل مجلد التطبيق قبل الخروج. هل تريد المتابعة؟',
        'A backup will be saved in the app folder before you leave. Continue?',
      );
  String get confirmExitNoAutoBackup => _t(
        'إغلاق بدون نسخ احتياطي تلقائي (يمكنك تعطيل ذلك أو تفعيله من الإعدادات). متابعة؟',
        'Exit without automatic backup (you can enable/disable this in Settings). Continue?',
      );

  String get backupSavedTitle => _t('تم حفظ النسخة الاحتياطية', 'Backup saved');
  String get backupFailedTitle =>
      _t('تعذر حفظ النسخة الاحتياطية', 'Could not save backup');
  String backupSavedBody(String path) =>
      _en ? 'Saved to:\n$path' : 'تم حفظ النسخة في:\n$path';
  String backupFailedBody(String err) => _en
      ? 'You can exit now, but a manual backup is recommended.\n\n$err'
      : 'يمكنك الإغلاق الآن، لكن يفضل إنشاء نسخة احتياطية يدويًا.\n\n$err';
  String get quitApp => _t('إغلاق البرنامج', 'Quit');

  String momChangeUp(double pct) => _en
      ? 'Up ${pct.toStringAsFixed(1)}%'
      : 'ارتفاع ${pct.toStringAsFixed(1)}%';
  String momChangeDown(double pct) => _en
      ? 'Down ${pct.abs().toStringAsFixed(1)}%'
      : 'انخفاض ${pct.abs().toStringAsFixed(1)}%';
  String get momFlat => _t('ثابت', 'Flat');

  String get dashboardGreetingPrefix => _t('مرحباً', 'Welcome');
  String get dashboardGreetingGuest =>
      _t('أهلاً بك — وضع زائر', 'Hello — guest session');
  String get dashboardKpiSectionTitle => _t('ملخص الأرقام', 'Totals overview');
  String get dashboardKpiSectionSubtitle => _t(
        'إجماليات الفرع الحالي (يُحدَّث من زر التحديث)',
        'Current branch totals (updates when you refresh)',
      );
  String get dashboardShortcutsTitle => _t('اختصارات العمل', 'Quick actions');
  String get dashboardShortcutsSubtitle => _t(
        'وصول سريع للمهام اليومية',
        'Fast access to everyday tasks',
      );

  String dashboardKpiPeriodChip(DashboardKpiPeriod p) {
    switch (p) {
      case DashboardKpiPeriod.allTime:
        return _t('منذ البداية', 'All time');
      case DashboardKpiPeriod.today:
        return _t('اليوم', 'Today');
      case DashboardKpiPeriod.week:
        return _t('هذا الأسبوع', 'This week');
      case DashboardKpiPeriod.month:
        return _t('هذا الشهر', 'This month');
      case DashboardKpiPeriod.last30Days:
        return _t('30 يوماً', '30 days');
    }
  }

  String dashboardKpiContextLine(DashboardKpiPeriod p) {
    switch (p) {
      case DashboardKpiPeriod.allTime:
        return _t(
          'المؤشرات: إجمالي كامل البيانات',
          'Metrics: all-time totals',
        );
      case DashboardKpiPeriod.today:
        return _t('المؤشرات: اليوم فقط', 'Metrics: today only');
      case DashboardKpiPeriod.week:
        return _t(
          'المؤشرات: من بداية الأسبوع حتى اليوم',
          'Metrics: week to date',
        );
      case DashboardKpiPeriod.month:
        return _t(
          'المؤشرات: من بداية الشهر حتى اليوم',
          'Metrics: month to date',
        );
      case DashboardKpiPeriod.last30Days:
        return _t(
          'المؤشرات: آخر 30 يوماً (شاملاً اليوم)',
          'Metrics: last 30 days (incl. today)',
        );
    }
  }

  String get dashboardHeroNetPeriodHint => _t(
        'الصافي أدناه يتبع الفترة المختارة.',
        'Net below follows the selected period.',
      );

  String get kpiStockCurrentTotalsFootnote => _t(
        'قيمة راهنة (لا تُفلتر بالفترة)',
        'Current value (not filtered by period)',
      );

  String get kpiCashNetInPeriodFootnote => _t(
        'صافي حركة الصندوق في الفترة',
        'Net cash movement in the period',
      );

  String get kpiSales => _t('مبيعات', 'Sales');
  String get kpiPurchases => _t('مشتريات', 'Purchases');
  String get kpiExpenses => _t('مصاريف', 'Expenses');
  String get kpiCash => _t('نقدية', 'Cash');
  String get kpiStockValue => _t('قيمة المخزون', 'Stock value');

  String get monthCompareTitle => _t(
      'مقارنة الشهر الحالي بالشهر السابق', 'Current month vs previous month');
  String get monthCompareHint => _t(
        'الشهر الحالي يُحتسب حتى اليوم، والمقارنة مع الشهر السابق كاملًا.',
        'Current month is counted through today; previous month is full.',
      );
  String get netCashLabel => _t('صافي الصندوق', 'Net cashbox');

  String get monthBarThis => _t('هذا الشهر', 'This month');
  String get monthBarPrev => _t('الشهر السابق', 'Previous month');
  String monthCurFmt(String v) => _en ? 'Current: $v' : 'حالي: $v';
  String monthPrevFmt(String v) => _en ? 'Previous: $v' : 'سابق: $v';
  String get monthNoData =>
      _t('لا بيانات في الفترتين', 'No data in either period');
  String get monthActivityThis =>
      _t('ظهور نشاط هذا الشهر', 'Activity this month');
  String monthChangePct(double pct) => _en
      ? 'Change ${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(1)}%'
      : 'تغيّر ${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(1)}%';

  String lowStockDialogTitle(String threshold) =>
      _en ? 'Low stock (≤ $threshold)' : 'تنبيه مخزون منخفض (≤ $threshold)';
  String get lowStockNone =>
      _t('لا توجد أصناف تحت الحد حاليًا.', 'No items below threshold.');
  String qtyAvailableLabel(String q) =>
      _en ? 'Qty available: $q' : 'الكمية المتاحة: $q';
  String get openInventory =>
      _t('فتح إدارة المخزون', 'Open inventory management');

  String get reportsDialogTitle =>
      _t('إدارة الاستعلامات', 'Query management');
  String get reportsInventory =>
      _t('إدارة المخزون', 'Inventory management');
  String get reportsCustomers => _t('أرصدة العملاء', 'Customer balances');
  String get reportsSuppliers => _t('أرصدة الموردين', 'Supplier balances');
  String get reportsCash => _t('حركة الصندوق', 'Cash movements');
  String exportPdfOk(String path) =>
      _en ? 'Exported PDF: $path' : 'تم تصدير PDF: $path';
  String exportExcelOk(String path) =>
      _en ? 'Exported Excel: $path' : 'تم تصدير Excel: $path';
  String get exportSaveCancelled => _t(
        'أُلغي اختيار مكان الحفظ.',
        'Save location selection was cancelled.',
      );
  String get noFinancialReportsPermission => _t(
      'ليس لديك صلاحية عرض الاستعلامات المالية.',
      'You do not have permission to view financial reports.');
  String get emptyData => _t('لا توجد بيانات', 'No data');

  String get branchesTitle => _t('الفروع', 'Branches');
  String get branchName => _t('اسم الفرع', 'Branch name');
  String get branchCode => _t('الكود', 'Code');
  String get addBranch => _t('إضافة', 'Add');
  String get branchNameRequired =>
      _t('اسم الفرع مطلوب.', 'Branch name is required.');
  String get branchCodeRequired =>
      _t('كود الفرع مطلوب.', 'Branch code is required.');
  String get branchCodeTaken =>
      _t('كود الفرع مستخدم بالفعل.', 'Branch code already in use.');
  String get branchAddedOk => _t('تمت إضافة الفرع بنجاح.', 'Branch added.');

  String get usersNoPermission => _t(
        'إدارة فريق العمل متاحة للمالك أو المحاسب أو مدير الفرع فقط.',
        'Managing the team is limited to the owner, accountant, or branch manager.',
      );

  String get settingsNoPermission => _t(
        'إعدادات المتجر تتطلّب تسجيل دخول موظف.',
        'Store settings require a signed-in staff account.',
      );

  String get settingsManagerOnlyTitle =>
      _t('إعدادات المتجر', 'Store settings');

  String get settingsManagerOnlyBody => _t(
        'هذه الشاشة غير متاحة في وضع الزائر. سجّل الدخول بحساب موظف للوصول إليها.',
        'This screen is not available in guest mode. Sign in with a staff account to access it.',
      );

  String get featureRequiresActivationTitle =>
      _t('ميزة مرتبطة بالاشتراك', 'Subscription required');
  String get featureRequiresActivationBody => _t(
        'هذه الميزة متاحة فقط للأجهزة المُفعَّلة، فعّل البرنامج لاستخدامها.',
        'This feature is available only for activated devices. Activate the program to use it.',
      );
  String get featureRequiresActivationCta =>
      _t('تفعيل الاشتراك', 'Activate subscription');
  String get usersTitle => _t('الموظفين', 'Employees');
  String get usersSecurityScreenTitle => _t('الموظفين', 'Employees');
  String get usersTeamScreenSubtitle => _t(
        'صلاحيات الدخول، الأدوار، وقفل الجلسة',
        'Sign-in roles, permissions, and session lock',
      );
  String get usersTeamRosterTitle => _t('قائمة الموظفين', 'Employee roster');
  String get usersSearchHint => _t('بحث في الموظفين…', 'Search employees…');
  String get usersListEmpty =>
      _t('لا يوجد موظفون بعد.', 'No employees yet.');
  String get usersLoadFailed => _t(
        'تعذر تحميل قائمة الموظفين.',
        'Could not load the employee list.',
      );
  String get usersTeamSyncCredentialsMissing => _t(
        'تعذّر سحب الموظفين من السحابة — تأكد من تفعيل القسيمة بنفس بريد المالك على هذا الجهاز.',
        'Could not pull employees from cloud — activate the voucher with the owner e-mail on this device.',
      );
  String get usersColActions => _t('الإجراءات', 'Actions');
  String get usersLoginIdentifierHint => _t(
        'يُستخدم لتسجيل الدخول (غالباً البريد الإلكتروني).',
        'Used to sign in (usually your email).',
      );
  String get usersAddSectionTitle => _t('إضافة عضو', 'Add member');
  String get usersSecuritySectionTitle =>
      _t('وصول الموظفين والأمان', 'Employee access & security');
  String get usersSelectedRolePermsTitle =>
      _t('صلاحيات الدور المختار', 'Selected role — permissions');
  String get usersSelectedRolePermsHint => _t(
        'الملخص يعكس الإعدادات الحالية. لتعديل الصلاحيات لكل دور، وسّع القسم في «الأمان» أدناه.',
        'This summary reflects current settings. Expand each role under Security below to edit.',
      );
  String get usersSecureProgramTitle =>
      _t('تأمين البرنامج', 'Secure application');
  String get usersSecureProgramSub => _t(
        'تذكير عند فتح البرنامج',
        'Reminder when opening the app',
      );
  String get usersRememberLoginTitle =>
      _t('تذكير بيانات الدخول', 'Remember sign-in');
  String get usersRememberLoginSub => _t(
        'حفظ بيانات تسجيل الدخول',
        'Keep login ID for next sign-in',
      );
  String get usersTypeRegular => _t('كاشير', 'Cashier');
  String get usersTypeAdmin => _t('محاسب', 'Accountant');
  String get usersErrNoBranch => _t(
        'تعذر تحديد الفرع الافتراضي للمؤسسة.',
        'Could not resolve the organization default branch.',
      );
  String get usersConfirmPassword => _t('تأكيد كلمة السر', 'Confirm password');
  String get usersPasswordMismatch =>
      _t('كلمة السر غير متطابقة.', 'Passwords do not match.');
  String get usersBranchLabel => _t('الفرع', 'Branch');
  String get usersEditTooltip => _t('تعديل', 'Edit');
  String get usersSaveChanges => _t('حفظ التعديلات', 'Save changes');
  String get usersCancelEdit => _t('إلغاء التعديل', 'Cancel edit');
  String get usersPasswordKeepHint => _t(
        'اترك كلمة المرور فارغة للإبقاء على الحالية',
        'Leave password blank to keep the current one',
      );
  String get usersUpdatedOk => _t('تم تحديث بيانات العضو.', 'Member updated.');
  String get usersSavedLocalCloudSyncFailed => _t(
        'حُفظ الحساب محلياً؛ فشلت المزامنة السحابية:',
        'Account saved locally; cloud sync failed:',
      );
  String get usersDeletedOk => _t('تم حذف العضو.', 'Member removed.');
  String get usersCannotDeleteSelf => _t(
      'لا يمكن حذف الحساب الحالي.', 'You cannot delete the signed-in account.');
  String get usersCannotDeleteOwner =>
      _t('لا يمكن حذف مالك النظام.', 'Cannot delete the system owner.');
  String get usersCannotEditOwner => _t(
      'لا يمكن تعديل حساب المالك إلا من حساب المالك.',
      'Only the owner account can edit another owner.');
  String get usersDeleteConfirmTitle => _t('حذف العضو', 'Remove member');
  String usersDeleteConfirmBody(String name) => _en
      ? 'Remove team member «$name»? This cannot be undone.'
      : 'حذف العضو «$name» من الفريق؟ لا يمكن التراجع.';
  String get usersOpenSettingsTooltip => _t('الإعدادات', 'Settings');
  String get usersRefreshTooltip => _t('تحديث القائمة', 'Refresh list');
  String get usersActionsSoon => _t('لا إجراءات حالياً', 'No actions yet');
  String get securityReminderSnack => _t(
        'تذكير أمني: لا تشارك كلمة المرور واحفظ النسخ الاحتياطية.',
        'Security tip: keep your password private and backups safe.',
      );
  String get roleOwner => _t('Admin', 'Admin');
  String get roleBranchManager => _t('محاسب', 'Accountant');
  String get roleAccountant => _t('محاسب', 'Accountant');
  String get roleCashier => _t('كاشير', 'Cashier');
  String get fieldName => _t('الاسم', 'Name');

  String get saleSavedOk =>
      _t('تم حفظ فاتورة البيع بنجاح.', 'Sale invoice saved.');
  String get purchaseSavedOk =>
      _t('تم حفظ فاتورة الشراء بنجاح.', 'Purchase invoice saved.');
  String get settingsSavedOk =>
      _t('تم حفظ إعدادات المتجر.', 'Store settings saved.');
  String settingsSavedWindowsStartupFailed(String detail) => _en
      ? 'Store settings were saved, but Windows startup could not be updated:\n$detail'
      : 'تم حفظ إعدادات المتجر، لكن تعذر تحديث «بدء التشغيل مع ويندوز»:\n$detail';
  String get backupRequestedOk => _t('تم طلب النسخة.', 'Backup requested.');
  String get restoreOk => _t('تمت استعادة البيانات بنجاح.', 'Data restored.');
  String get clearOperationalOk =>
      _t('تم مسح البيانات التشغيلية بنجاح.', 'Operational data cleared.');

  String get confirmClearOpsTitle =>
      _t('تأكيد مسح الحركات', 'Confirm clearing transactions');
  String get confirmClearOpsBody => _t(
        'سيتم حذف الفواتير والمصروفات وحركات الصندوق والمخزون لهذه الجلسة. هل تريد المتابعة؟',
        'Invoices, expenses, cash movements and inventory for this session will be removed. Continue?',
      );
  String get yesClear => _t('نعم، مسح', 'Yes, clear');

  String get menuStaffSignIn => menuEmployeesSignIn;

  String get menuLoginGuestSubtitle => _t(
        'وضع زائر — اختياري لكاشير/محاسب بعد ضبط المالك للحسابات',
        'Guest — optional for cashier/accountant after the owner sets up users',
      );

  String menuLoginGuestWithRemembered(String id) =>
      _en ? 'Last remembered sign-in: $id' : 'آخر اسم مُتذكَّر للدخول: $id';

  String menuLoginSignedInSubtitle(String username) =>
      _en ? 'Current session: $username' : 'الجلسة الحالية: $username';

  /// عنصر القائمة عند وجود جلسة (يفتح ملخص الحساب وليس نموذج الدخول).
  String get menuSignedInAccountEntry => _t('حسابي', 'My account');

  String get accountSessionSheetTitle =>
      _t('أنت مسجّل الدخول', 'You are signed in');

  String get accountSessionActiveChip => _t('جلسة نشطة', 'Active session');

  String get accountSessionSheetSubtitle => _t(
        'هذه بيانات جلستك الحالية على هذا الجهاز.',
        'Here is your current session on this device.',
      );

  String get accountSessionFieldUsername => _t('اسم الدخول', 'Username');

  String get accountSessionFieldRole => _t('الدور', 'Role');

  String get accountSessionFieldEmail => _t('البريد', 'Email');

  String get accountSessionFieldSubscription =>
      _t('صاحب الاشتراك', 'Subscription holder');

  String get accountSessionSignOutHint => _t(
        'ستعود إلى وضع الزائر. لن تُحذف بيانات المتجر من الجهاز.',
        'You will return to guest mode. Store data on this device is kept.',
      );

  String get accountSwitchAccountButton => _t(
        'تسجيل الدخول بحساب آخر',
        'Sign in with another account',
      );

  String get sessionIdentityTapTooltip =>
      _t('حسابي — اضغط لفتح صفحة الحساب', 'My account — tap to open');

  String get sessionIdentitySheetTitle => _t('تسجيل الدخول', 'Sign in');

  String get sessionIdentityGuestPrompt =>
      _t('من أنت؟', 'Who are you?');

  String get sessionIdentityPickRoleHint => _t(
        'اختر بطاقة الدور ثم أدخل كلمة المرور.',
        'Pick your role card, then enter your password.',
      );

  String get sessionIdentitySwitchHint => _t(
        'لتبديل الحساب اختر دوراً آخر، أو افتح «حسابي»، أو سجّل الخروج.',
        'To switch accounts, pick another role, open My account, or sign out.',
      );

  String get sessionIdentitySignOutOnlyHint => _t(
        'لإنهاء جلسة المدير استخدم تسجيل الخروج.',
        'Use sign out to end the manager session.',
      );

  String get sessionIdentityRolesLegend =>
      _t('أدوار فريق العمل', 'Staff roles');

  String get sessionIdentityDistributorPortalTitle => _t(
        'تسجيل دخول الموزّعين',
        'Distributor sign-in',
      );

  String get sessionIdentityDistributorPortalBody => _t(
        'هذه مساحة تسجيل دخول الموزّعين بعد تعيينهم في نسخة الحاسوب وتفعيل اشتراك السحابة.',
        'This is the distributor sign-in area after they are assigned on the desktop app and the cloud subscription is activated.',
      );

  String get sessionIdentityGuestLabel => _t('زائر', 'Guest');

  String roleQuickLoginTitle(String roleLabel) =>
      _t('دخول $roleLabel', 'Sign in as $roleLabel');

  String get roleQuickLoginNoUsers => _t(
        'لا يوجد حساب مسجّل لهذا الدور على هذا الجهاز.',
        'No account for this role is registered on this device.',
      );

  String roleQuickLoginNoUsersHint(String roleLabel) => _t(
        'للدخول كـ$roleLabel استخدم «تسجيل الدخول بالبريد» بنفس بريد وكلمة سر تفعيل الاشتراك.',
        'To sign in as $roleLabel, use «Sign in with email» with your subscription email and password.',
      );

  String get roleQuickLoginSignInWithEmail =>
      _t('تسجيل الدخول بالبريد', 'Sign in with email');

  String get roleQuickLoginPickUser =>
      _t('اختر الحساب', 'Choose account');

  String get roleQuickLoginOwnerHint => _t(
        'يُنصح بتفعيل كلمة سر حصرية للمدير من إعدادات المتجر حتى لا يدخل الموظفون بحسابه.',
        'Enable an exclusive admin password in Store settings so staff cannot use the admin account.',
      );

  String get roleQuickLoginOwnerExclusiveOn => _t(
        'كلمة سر المدير حصرية — لا يعرفها باقي الفريق.',
        'Admin password is exclusive — other team members do not know it.',
      );

  String get roleQuickLoginAlreadySignedIn => _t(
        'أنت مسجّل الدخول حالياً',
        'You are signed in',
      );

  String get roleQuickLoginSwitchSameRole => _t(
        'تسجيل الدخول بحساب آخر',
        'Sign in with another account',
      );

  String get roleQuickLoginVoucherOwnerActive => _t(
        'القسيمة مفعّلة — تعمل كمسؤول على هذا الجهاز',
        'Voucher active — operating as admin on this device',
      );

  String get settingsOwnerLoginTitle =>
      _t('كلمة سر دخول المدير (حصرية)', 'Exclusive admin sign-in password');

  String get settingsOwnerLoginSub => _t(
        'عند التفعيل، لا يستطيع المحاسب أو الكاشير أو غيرهما الدخول بحساب المدير إلا بكلمة السر التي تضبطها هنا.',
        'When enabled, accountants, cashiers, and others cannot sign in as admin unless they know this password.',
      );

  String get settingsOwnerLoginHintExisting => _t(
        'اترك الحقول فارغة للإبقاء على كلمة السر الحالية.',
        'Leave fields empty to keep the current password.',
      );

  String get settingsErrOwnerLoginMismatch => _t(
        'كلمتا سر المدير غير متطابقتين.',
        'Admin passwords do not match.',
      );

  String get settingsErrOwnerLoginNeedsPw => _t(
        'أدخل كلمة سر للمدير أو عطّل الخيار.',
        'Enter an admin password or turn the option off.',
      );

  String get settingsLoginCardTitle => _t('تسجيل الدخول', 'Sign in');

  String get settingsLoginCardGuestBody => _t(
        'أنت غير مسجّل الدخول (وضع زائر). أدخل البريد أو اسم الدخول وكلمة المرور لحساب مسجّل في هذا المتجر.',
        'You are not signed in (guest). Enter the email or login ID and password for an account registered in this store.',
      );

  String get settingsLoginOpenButton =>
      _t('فتح نموذج تسجيل الدخول', 'Open sign-in form');

  String get settingsLoginRememberedCaption => _t(
        'آخر اسم مُتذكَّر للدخول',
        'Last remembered sign-in',
      );

  String get settingsLoginBootstrapDefaultsTitle => _t(
        'بيانات المالك الافتراضية (أول تشغيل)',
        'Default owner sign-in (first install)',
      );

  String get settingsLoginBootstrapDefaultsBody => _t(
        'إذا لم تُغيّر كلمة مرور المالك بعد التثبيت الأول، يمكنك تسجيل الدخول بهذه القيم ثم تغييرها من «فريق العمل»:',
        'If you have not changed the owner password since the first install, sign in with these values, then change them under Team:',
      );

  String get settingsLoginBootstrapUsernameLabel =>
      _t('اسم الدخول', 'Login ID');

  String get settingsLoginBootstrapPasswordLabel =>
      _t('كلمة المرور', 'Password');

  String settingsLoginBootstrapEmailLine(String email) =>
      _en ? 'Or sign in with email: $email' : 'أو بالبريد: $email';

  String get settingsLoginBootstrapChangedNote => _t(
        'كلمة مرور المالك الافتراضية لم تعد صالحة (تم تغييرها أو حذف الحساب). استخدم البريد أو اسم الدخول وكلمة المرور التي عيّنها مدير المتجر.',
        'The default owner password is no longer in use (it was changed or the account was removed). Use the email or login ID and password set by your store admin.',
      );

  String get menuLoginBootstrapStillDefault => _t(
        'أول تشغيل: owner / 1234 — غيّرها بعد الدخول',
        'First install: owner / 1234 — change after sign-in',
      );

  String get menuLoginBootstrapNotDefault => _t(
        'استخدم بيانات دخول مسجّلة لديك',
        'Use sign-in credentials registered for this store',
      );

  String get loginScreenBootstrapBannerTitle => _t(
        'تسجيل دخول المالك (أول تشغيل)',
        'Owner sign-in (first install)',
      );

  String loginScreenBootstrapBannerBody(
          String user, String pass, String email) =>
      _en
          ? 'Login ID: $user — Password: $pass — or email: $email'
          : 'اسم الدخول: $user — كلمة المرور: $pass — أو البريد: $email';

  // إعدادات المتجر
  String get settingsScreenTitle => _t('الإعدادات', 'Settings');
  String get settingsSaveButton => _t('حفظ الإعدادات', 'Save settings');
  String get settingsSectionPickerLabel =>
      _t('قسم الإعدادات', 'Settings section');
  String get settingsDataActionsMenu => _t(
        'إجراءات البيانات والنسخ',
        'Data & backup actions',
      );
  String get settingsHomeActionsMenu =>
      _t('إجراءات الشاشة الرئيسية', 'Home screen actions');
  String get settingsTeamActionsMenu =>
      _t('إجراءات الفريق والأمان', 'Team & security actions');
  String get settingsNavGeneral => _t('عام', 'General');
  String get settingsNavBranding => _t('الهوية', 'Branding');
  String get settingsNavFinance => _t('مالية', 'Finance');
  String get settingsNavLook => _t('المظهر', 'Appearance');
  String get settingsNavAlerts => _t('تنبيهات', 'Alerts');
  String get settingsNavSales => _t('البيع', 'Sales');
  String get settingsNavStock => _t('المخزون', 'Stock');
  String get settingsNavHome => _t('الرئيسية', 'Dashboard');
  String get settingsNavData => _t('البيانات', 'Data');
  String get mizaCloudScreenTitle => _t('ميزا كلاود', 'Miza Cloud');
  String get mizaCloudComingSoonNote => _t(
        'الإشتراك في هذه الخدمة سيتوفر قريباً.',
        'Subscription to this service will be available soon.',
      );
  String get mizaCloudOpenFromSettings => _t('ميزا كلاود', 'Miza Cloud');
  String get cloudSyncEnabledTitle => _t(
        'تفعيل المزامنة السحابية',
        'Enable cloud sync',
      );
  String get cloudSyncEnabledSubtitle => _t(
        'مزامنة تلقائية للمنتجات والمعاملات عند توفر الإنترنت.',
        'Automatically sync products and transactions when online.',
      );
  String get cloudSyncWifiOnlyTitle => _t(
        'المزامنة على WiFi فقط',
        'Sync on WiFi only',
      );
  String get cloudSyncWifiOnlySubtitle => _t(
        'لا تُزامن على بيانات الجوال أو الاتصال المقيد — يشمل المزامنة التلقائية.',
        'Skip mobile data and constrained links — includes automatic sync.',
      );
  String get cloudLoginTitle =>
      _t('تسجيل دخول Miza Cloud', 'Miza Cloud sign-in');
  String get cloudLoginHero => _t(
        'سجّل الدخول إلى حساب Miza Cloud لمزامنة بيانات متجرك بين جميع أجهزتك',
        'Sign in to your Miza Cloud account to sync your store data across all your devices',
      );
  String get cloudLoginResetSentBody => _t(
        'تم إرسال كلمة مرور مؤقتة إلى بريدك. استخدمها لتسجيل الدخول إلى Miza Cloud.',
        'A temporary password was sent to your email. Use it to sign in to Miza Cloud.',
      );
  String get cloudLoginSubtitle => _t(
        'أدخل بيانات حساب السحابة — منفصلة عن دخول الموظفين المحلي.',
        'Enter your cloud account credentials — separate from local staff login.',
      );
  String get cloudLoginSelectStoreTitle =>
      _t('اختر المتجر', 'Select store');
  String get cloudLoginEmail => _t('البريد الإلكتروني', 'Email');
  String get cloudLoginPassword => _t('كلمة المرور', 'Password');
  String get cloudLoginSubmit => _t('تسجيل الدخول', 'Sign in');
  String get cloudLoginValidationEmpty => _t(
        'أدخل البريد وكلمة المرور.',
        'Enter email and password.',
      );
  String get cloudLoginTenantIdsRequired => _t(
        'أدخل معرّف الشركة والفرع (مطلوب لهذا الحساب).',
        'Enter company and branch IDs (required for this account).',
      );
  String get cloudLoginInvalidCredentials => _t(
        'بيانات الدخول غير صحيحة.\nتأكد أنك تستخدم كلمة مرور حساب Miza Cloud — وليست كلمة مرور البرنامج المحلي أو بوابة التفعيل.\nإن لم تتذكرها: «نسيت كلمة المرور».',
        'Invalid sign-in credentials.\nUse your Miza Cloud password — not the local app or activation portal password.\nIf you forgot it, use «Forgot password».',
      );
  String get cloudLoginDeviceNotRegistered => _t(
        'الجهاز غير مسجّل — أكمل خطوة ربط الجهاز.',
        'Device not registered — complete device pairing.',
      );
  String get cloudLoginCompanySuspended => _t(
        'حساب المتجر موقوف.',
        'Store account is suspended.',
      );
  String get cloudLoginAccountDisabled => _t(
        'الحساب معطّل.',
        'Account is disabled.',
      );
  String get cloudLoginForbidden => _t(
        'لا صلاحية للوصول إلى هذا الفرع.',
        'No access to this branch.',
      );
  String get cloudLoginFailed => _t(
        'تعذّر تسجيل الدخول.',
        'Sign-in failed.',
      );
  String get cloudLoginTenantIdsToggle => _t(
        'معرّفات المتجر (متقدم)',
        'Store IDs (advanced)',
      );
  String get cloudLoginCompanyId => _t('معرّف الشركة', 'Company ID');
  String get cloudLoginBranchId => _t('معرّف الفرع', 'Branch ID');
  String get cloudDeviceSetupTitle =>
      _t('ربط الجهاز', 'Pair this device');
  String get cloudDeviceSetupHero => _t(
        'سجّل هذا الجهاز على السحابة',
        'Register this device on the cloud',
      );
  String get cloudDeviceSetupSubtitle => _t(
        'سيظهر الجهاز في قائمة أجهزة المتجر ويمكنه المزامنة.',
        'This device will appear in your store device list and can sync.',
      );
  String get cloudDeviceNameRequired => _t(
        'أدخل اسماً للجهاز.',
        'Enter a device name.',
      );
  String cloudDevicePlatformHint(String platform) => _t(
        'المنصة: $platform',
        'Platform: $platform',
      );
  String get cloudDeviceRegisterSubmit =>
      _t('ربط الجهاز الآن', 'Pair device now');
  String get cloudDeviceLimitReached => _t(
        'تم بلوغ حد الأجهزة في خطتك.',
        'Device limit reached for your plan.',
      );
  String get cloudDeviceInstallationConflict => _t(
        'معرّف التثبيت مرتبط بمتجر آخر.',
        'Installation ID belongs to another store.',
      );
  String get cloudDeviceRevoked => _t(
        'هذا الجهاز ملغى — تواصل مع الدعم.',
        'This device is revoked — contact support.',
      );
  String get cloudDeviceRegisterFailed => _t(
        'تعذّر ربط الجهاز.',
        'Device pairing failed.',
      );
  String get cloudLogout => _t('خروج من السحابة', 'Cloud sign-out');
  String get mizaCloudOpenHint => _t(
        'حالة الاتصال، آخر مزامنة، والعمليات المعلقة.',
        'Connection status, last sync, and pending operations.',
      );
  String get mizaCloudRefresh => _t('تحديث', 'Refresh');
  String get mizaCloudNotInitialized => _t(
        'محرك المزامنة غير مهيأ على هذا الجهاز.',
        'Sync engine is not initialized on this device.',
      );
  String get mizaCloudConnected => _t('متصل', 'Connected');
  String get mizaCloudDisconnected => _t('غير متصل', 'Disconnected');
  String get mizaCloudSectionDevice => _t('بيانات الجهاز', 'Device');
  String get mizaCloudDeviceName => _t('اسم الجهاز', 'Device name');
  String get mizaCloudDeviceId => _t('Device ID', 'Device ID');
  String get mizaCloudSectionAccount => _t('بيانات الحساب', 'Account');
  String get mizaCloudAccountEmail => _t('البريد الإلكتروني', 'Email');
  String get mizaCloudStoreName => _t('اسم المتجر', 'Store name');
  String get mizaCloudSectionLastSync => _t('آخر مزامنة', 'Last sync');
  String get mizaCloudLastSyncDate => _t('التاريخ', 'Date');
  String get mizaCloudLastSyncTime => _t('الوقت', 'Time');
  String get mizaCloudSectionPending =>
      _t('العمليات المعلقة', 'Pending operations');
  String get mizaCloudPendingPush => _t('بانتظار الرفع', 'Pending upload');
  String get mizaCloudOutboxFailed =>
      _t('فشل في الإرسال', 'Send failures');
  String get mizaCloudSectionFailedDetails =>
      _t('العمليات الفاشلة', 'Failed operations');
  String get mizaCloudFailedType => _t('النوع', 'Type');
  String get mizaCloudFailedError => _t('سبب الخطأ', 'Error');
  String mizaCloudFailedGroupSummary({
    required String entityType,
    required int count,
    required String error,
  }) =>
      _t(
        '${mizaCloudOutboxEntityType(entityType)} ×$count — $error',
        '${mizaCloudOutboxEntityType(entityType)} ×$count — $error',
      );
  String mizaCloudFailedMore(int count) =>
      _t('+$count أخرى', '+$count more');
  String get mizaCloudRepairFailedButton =>
      _t('إصلاح العمليات الفاشلة', 'Fix failed operations');
  String mizaCloudRepairFailedDone(int count) => _t(
        'تم إصلاح $count عملية — جارٍ المزامنة…',
        'Repaired $count operation(s) — syncing…',
      );
  String get mizaCloudRepairFailedNothing => _t(
        'لا توجد عمليات قابلة للإصلاح تلقائياً.',
        'No operations could be repaired automatically.',
      );
  String mizaCloudOutboxEntityType(String type) {
    switch (type) {
      case 'product':
        return _t('منتج', 'Product');
      case 'product_category':
        return _t('تصنيف منتج', 'Product category');
      case 'product_unit':
        return _t('وحدة قياس', 'Product unit');
      case 'tax':
        return _t('ضريبة', 'Tax');
      case 'price_list':
        return _t('قائمة أسعار', 'Price list');
      case 'customer':
        return _t('عميل', 'Customer');
      case 'supplier':
        return _t('مورد', 'Supplier');
      case 'sales_invoice':
        return _t('فاتورة مبيعات', 'Sales invoice');
      case 'purchase_invoice':
        return _t('فاتورة مشتريات', 'Purchase invoice');
      case 'sales_return':
        return _t('مرتجع مبيعات', 'Sales return');
      case 'purchase_return':
        return _t('مرتجع مشتريات', 'Purchase return');
      case 'customer_payment':
        return _t('دفعة عميل', 'Customer payment');
      case 'supplier_payment':
        return _t('دفعة مورد', 'Supplier payment');
      case 'inventory_adjustment':
        return _t('تسوية مخزون', 'Inventory adjustment');
      case 'opening_stock':
        return _t('رصيد افتتاحي', 'Opening stock');
      case 'cash_movement':
      case 'cash':
        return _t('حركة صندوق', 'Cash movement');
      case 'expense':
        return _t('مصروف', 'Expense');
      default:
        return type;
    }
  }

  String mizaCloudOutboxOperation(String operation) {
    switch (operation) {
      case 'create':
        return _t('إنشاء', 'Create');
      case 'update':
        return _t('تعديل', 'Update');
      case 'post':
        return _t('ترحيل', 'Post');
      case 'cancel':
        return _t('إلغاء', 'Cancel');
      case 'void':
        return _t('إبطال', 'Void');
      case 'delete':
        return _t('حذف', 'Delete');
      default:
        return operation;
    }
  }

  String mizaCloudOutboxErrorLabel(String code) {
    switch (code) {
      case 'validation_error':
      case 'validation_failed':
        return _t('بيانات غير صالحة', 'Invalid data');
      case 'invalid_request':
      case 'invalid_payload':
      case 'bad_request':
        return _t('طلب غير صالح', 'Invalid request');
      case 'unauthorized':
        return _t('غير مصرّح', 'Unauthorized');
      case 'forbidden':
        return _t('ممنوع', 'Forbidden');
      case 'push_failed':
        return _t('فشل الرفع', 'Upload failed');
      case 'pull_failed':
        return _t('فشل التنزيل', 'Download failed');
      case 'push_no_progress':
        return _t('توقف الرفع بدون تقدّم', 'Upload stuck with no progress');
      case 'product_not_found':
        return _t(
          'المنتج غير موجود على السحابة بعد — اضغط «إصلاح» ثم زامن',
          'Product not on cloud yet — tap Repair then sync',
        );
      case 'not_found':
      case 'invoice_not_found':
      case 'draft_not_found':
        return _t(
          'الفاتورة غير موجودة على السحابة بعد — اضغط «إصلاح» ثم زامن',
          'Invoice not on cloud yet — tap Repair then sync',
        );
      case 'insufficient_stock':
        return _t(
          'المخزون غير كافٍ على السحابة — راجع الكميات ثم أعد المحاولة',
          'Insufficient cloud stock — check quantities then retry',
        );
      case 'push_rejected':
      case 'partial_reject':
        return _t(
          'رُفض جزء من الدفعة على السحابة — راجع التفاصيل الفاشلة',
          'Part of the batch was rejected on cloud — check failed details',
        );
      case 'push_partial':
        return _t(
          'قبول جزئي غامض — ستُعاد المحاولة تلقائياً',
          'Ambiguous partial accept — will retry automatically',
        );
      case 'apply_failed':
        return _t(
          'فشل تطبيق الحدث على السحابة',
          'Failed to apply event on cloud',
        );
      case 'partner_not_found':
      case 'customer_not_found':
      case 'supplier_not_found':
        return _t(
          'العميل/المورد غير موجود على السحابة بعد',
          'Customer/supplier not on cloud yet',
        );
      case 'category_not_found':
        return _t('التصنيف غير موجود على السحابة', 'Category not on cloud');
      case 'internal_error':
        return _t('خطأ داخلي في السحابة', 'Cloud internal error');
      case 'create_version_conflict':
        return _t(
          'تعارض إصدار: جهاز آخر عدّل نفس السجل — سيتم اعتماد الأحدث بعد السحب',
          'Version conflict: another device changed the same record — latest wins after pull',
        );
      case 'conflict':
        return _t(
          'تعارض: السجل موجود مسبقاً على السحابة — سيتم تجاهل التكرار',
          'Conflict: record already exists on cloud — duplicate will be ignored',
        );
      case 'posting_conflict':
        return _t(
          'تعارض عند الترحيل: الفاتورة قد تكون مرحّلة مسبقاً على جهاز آخر',
          'Posting conflict: invoice may already be posted on another device',
        );
      case 'offline_during_retry':
      case 'offline':
        return _t('لا يوجد اتصال بالإنترنت', 'No internet connection');
      case 'unknown':
        return _t('سبب غير معروف', 'Unknown reason');
      default:
        final lower = code.toLowerCase();
        if (lower.contains('unique constraint failed') &&
            lower.contains('sync_meta')) {
          return _t(
            'تعارض مؤقت في حالة المزامنة — أعد المحاولة',
            'Temporary sync-state conflict — please retry',
          );
        }
        if (lower.contains('no such table') ||
            lower.contains('sqliteexception') ||
            lower.contains('sqlite_error')) {
          return _t(
            'قاعدة البيانات تحتاج تحديثاً — أعد تشغيل البرنامج ثم زامن',
            'Database needs an update — restart the app then sync',
          );
        }
        if (code.length > 120) {
          return '${code.substring(0, 117)}…';
        }
        return code;
    }
  }

  String get mizaCloudSectionHealth =>
      _t('صحة المزامنة', 'Sync health');
  String get mizaCloudHealthOk =>
      _t('مكتمل وجاهز', 'Complete and ready');
  String get mizaCloudHealthPending =>
      _t('بانتظار رفع بيانات', 'Waiting to upload data');
  String get mizaCloudHealthFailed =>
      _t('يحتاج إصلاح', 'Needs repair');
  String get mizaCloudHealthOffline =>
      _t('غير متصل', 'Offline');
  String get mizaCloudHealthSyncing =>
      _t('جارٍ المزامنة…', 'Syncing…');
  String mizaCloudHealthCounts({
    required int products,
    required int customers,
    required int invoices,
  }) =>
      _t(
        'محلياً: $products منتج · $customers عميل · $invoices فاتورة',
        'Local: $products products · $customers customers · $invoices invoices',
      );

  String get mizaCloudRestoreButton =>
      _t('استعادة من السحابة', 'Restore from cloud');
  String get mizaCloudRestoreTitle =>
      _t('استعادة جهاز جديد', 'New device restore');
  String get mizaCloudRestoreBody => _t(
        'سيتم تنزيل بيانات حسابك من السحابة إلى هذا الجهاز (منتجات، عملاء، فواتير…).',
        'Your cloud account data will be downloaded to this device (products, customers, invoices…).',
      );
  String get mizaCloudRestoreStart => _t('ابدأ الاستعادة', 'Start restore');
  String get mizaCloudRestoreWorking =>
      _t('جارٍ الاستعادة من السحابة…', 'Restoring from cloud…');
  String mizaCloudRestoreDone({
    required int products,
    required int customers,
    required int invoices,
  }) =>
      _t(
        'تمت الاستعادة.\nمنتجات: $products\nعملاء: $customers\nفواتير: $invoices',
        'Restore complete.\nProducts: $products\nCustomers: $customers\nInvoices: $invoices',
      );
  String get mizaCloudRestoreEmptyHint => _t(
        'هذا الجهاز فارغ تقريباً — يمكنك استعادة البيانات من السحابة.',
        'This device is nearly empty — you can restore data from the cloud.',
      );

  String get mizaCloudSectionActivity =>
      _t('آخر نشاط', 'Recent activity');
  String mizaCloudActivityPush(int count) =>
      _t('تم رفع $count عنصر', 'Uploaded $count item(s)');
  String mizaCloudActivityPull(int count) =>
      _t('تم تنزيل $count عنصر', 'Downloaded $count item(s)');
  String get mizaCloudActivityPushStarted =>
      _t('بدء الرفع…', 'Upload started…');
  String get mizaCloudActivityPullStarted =>
      _t('بدء التنزيل…', 'Download started…');
  String mizaCloudActivityRetry(int attempt) =>
      _t('إعادة محاولة ($attempt)', 'Retry ($attempt)');
  String mizaCloudActivityError(String detail) =>
      _t('خطأ: $detail', 'Error: $detail');
  String mizaCloudSelfCheckImages(int count) => _t(
        'صور بانتظار الرفع: $count',
        'Images waiting to upload: $count',
      );
  String get mizaCloudSelfCheckOk => _t(
        'الفحص الذاتي: لا توجد فجوات ظاهرة',
        'Self-check: no obvious gaps',
      );
  String get mizaCloudSelfCheckNeedsRepair => _t(
        'الفحص الذاتي: توجد عمليات فاشلة تحتاج إصلاحاً',
        'Self-check: failed operations need repair',
      );
  String get mizaCloudSelfCheckPending => _t(
        'الفحص الذاتي: ما زال هناك بيانات بانتظار الرفع',
        'Self-check: data still waiting to upload',
      );
  String get mizaCloudSelfCheckConflict => _t(
        'الفحص الذاتي: تعارض مع جهاز آخر — اسحب ثم أصلح',
        'Self-check: conflict with another device — pull then repair',
      );
  String mizaCloudSelfCheckDeferred(int count) => _t(
        'بانتظار اعتماد $count عنصر من السحابة (نواقص محلية)',
        '$count cloud items waiting on local dependencies',
      );
  String get mizaCloudHealthPartial =>
      _t('مزامنة جزئية — أكمل الدورة', 'Partial sync — continue syncing');
  String get mizaCloudSyncPartial => _t(
        'اكتملت المزامنة جزئياً — أعد المزامنة بعد لحظات',
        'Sync completed partially — sync again in a moment',
      );

  String get mizaCloudSectionDiagnostics =>
      _t('تشخيص المزامنة', 'Sync diagnostics');
  String get mizaCloudDiagDeferred =>
      _t('مؤجّل من السحب', 'Deferred pull');
  String get mizaCloudDiagLastPush =>
      _t('آخر رفع', 'Last push');
  String get mizaCloudDiagLastPull =>
      _t('آخر سحب', 'Last pull');
  String get mizaCloudDiagTopError =>
      _t('أكثر خطأ', 'Top error');
  String get mizaCloudDiagNever => _t('—', '—');
  String mizaCloudDiagLastRun({
    required int pushed,
    required int pulled,
    required int deferred,
  }) =>
      _t(
        'آخر دورة: رفع $pushed · سحب $pulled · مؤجّل $deferred',
        'Last run: push $pushed · pull $pulled · deferred $deferred',
      );
  String mizaCloudDiagTopErrorCount(String label, int count) =>
      _t('$label ($count)', '$label ($count)');
  String mizaCloudErrorActionHint(String code) {
    switch (code) {
      case 'product_not_found':
        return _t(
          'الإجراء: إصلاح الفاشل ثم مزامنة الآن',
          'Action: Repair failed then Sync now',
        );
      case 'insufficient_stock':
        return _t(
          'الإجراء: عدّل الكمية محلياً أو استلم مخزوناً ثم أعد الرفع',
          'Action: Adjust qty locally or receive stock, then upload again',
        );
      case 'partner_not_found':
      case 'customer_not_found':
      case 'supplier_not_found':
        return _t(
          'الإجراء: زامن العملاء/الموردين أولاً ثم أعد الفاتورة',
          'Action: Sync partners first, then retry the document',
        );
      case 'partial_reject':
      case 'push_rejected':
        return _t(
          'الإجراء: افتح التفاصيل الفاشلة وأصلح الصف المرفوض',
          'Action: Open failed details and fix the rejected row',
        );
      default:
        return '';
    }
  }

  String get mizaCloudResolveConflictsButton =>
      _t('حل التعارضات (سحب ثم مزامنة)', 'Resolve conflicts (pull then sync)');
  String get mizaCloudResolveConflictsDone => _t(
        'تم حل التعارضات وإعادة المزامنة',
        'Conflicts resolved and sync restarted',
      );
  String get mizaCloudNetworkFast => _t('الشبكة: سريعة', 'Network: fast');
  String get mizaCloudNetworkStandard =>
      _t('الشبكة: عادية', 'Network: standard');
  String get mizaCloudNetworkConstrained =>
      _t('الشبكة: محدودة', 'Network: constrained');

  String get mizaCloudSectionLastError =>
      _t('آخر خطأ مزامنة', 'Last sync error');
  String get mizaCloudSyncNow => _t('مزامنة الآن', 'Sync now');
  String get mizaCloudSyncInProgress =>
      _t('جارٍ المزامنة…', 'Syncing…');
  String get mizaCloudSyncPhasePush =>
      _t('جارٍ رفع البيانات', 'Uploading data');
  String mizaCloudSyncPhasePushDetail(String step) =>
      _t('جارٍ الرفع: $step', 'Uploading: $step');
  String get mizaCloudSyncPhasePull =>
      _t('جارٍ تنزيل البيانات', 'Downloading data');
  String mizaCloudSyncPhasePullDetail(String step) =>
      _t('جارٍ التنزيل: $step', 'Downloading: $step');
  String mizaCloudSyncProgressPending(int done, int total) =>
      _t('تم رفع $done من $total', 'Uploaded $done of $total');
  String mizaCloudSyncProgressStep(int current, int total) =>
      _t('الخطوة $current من $total', 'Step $current of $total');
  String mizaCloudSyncStepLabel(String key) {
    switch (key) {
      case 'catalog_masters':
        return _t('بيانات الكتالوج', 'Catalog data');
      case 'partners':
        return _t('العملاء والموردين', 'Customers & suppliers');
      case 'transactions':
        return _t('الفواتير والمعاملات', 'Invoices & transactions');
      case 'product_images':
        return _t('صور المنتجات', 'Product images');
      case 'push_start':
        return _t('بدء الرفع', 'Starting upload');
      case 'pull_start':
        return _t('بدء التنزيل', 'Starting download');
      default:
        return mizaCloudOutboxEntityType(key);
    }
  }
  String get mizaCloudSyncPhaseRetry =>
      _t('إعادة المحاولة…', 'Retrying…');
  String get mizaCloudSyncSuccess =>
      _t('تمت المزامنة بنجاح', 'Sync completed successfully');
  String mizaCloudSuccessAt(String when) =>
      _t('آخر مزامنة: $when', 'Last sync: $when');
  String get mizaCloudSyncFailed =>
      _t('تعذّرت المزامنة', 'Sync failed');
  String get mizaCloudRetry => _t('إعادة المحاولة', 'Retry');
  String get mizaCloudErrorGeneric => _t(
        'حدث خطأ أثناء المزامنة. تحقّق من الاتصال وحاول مجدداً.',
        'An error occurred during sync. Check your connection and try again.',
      );
  String get mizaCloudErrorOffline => _t(
        'لا يوجد اتصال بالإنترنت.',
        'No internet connection.',
      );
  String get mizaCloudErrorNoContext => _t(
        'لا يوجد سياق مزامنة (تسجيل دخول أو تسجيل جهاز).',
        'No sync context (sign-in or device registration required).',
      );
  String get mizaCloudErrorSessionExpired => _t(
        'انتهت الجلسة السحابية. سجّل دخولك إلى ميزا كلاود مرة أخرى.',
        'Your cloud session expired. Sign in to Miza Cloud again.',
      );
  String get mizaCloudSignInAgain =>
      _t('تسجيل الدخول', 'Sign in');
  String get mizaCloudRemapTitle => _t(
        'تأكيد ربط المتجر',
        'Confirm store link',
      );
  String get mizaCloudRemapBody => _t(
        'سجّلت الدخول بحساب ميزا كلاود مختلف عن الحساب المرتبط سابقاً بهذا الجهاز. '
        'اضغط «متابعة» فقط إذا كان هذا هو متجرك الصحيح. '
        'إذا كان حساب متجر آخر، اضغط إلغاء وسجّل بالحساب الصحيح.',
        'You signed in with a Miza Cloud account different from the one previously linked on this device. '
        'Tap Continue only if this is the correct store. '
        'If it is another store’s account, cancel and sign in with the right account.',
      );
  String mizaCloudRemapDetail({
    required String localOrg,
    required String cloudOrg,
  }) =>
      '';
  String _shortId(String id) {
    final t = id.trim();
    if (t.length <= 12) return t;
    return '${t.substring(0, 8)}…${t.substring(t.length - 4)}';
  }
  String get mizaCloudRemapConfirm => _t('متابعة', 'Continue');
  String get mizaCloudRemapSkipped => _t(
        'لم يُربَط الحساب. سجّل دخول حساب متجرك الصحيح ثم أعد المزامنة.',
        'Account was not linked. Sign in with your store account, then sync again.',
      );
  String get mizaCloudRemapAutoDone => _t(
        'تم ربط بيانات المتجر بالسحابة. جارٍ إكمال المزامنة…',
        'Store data linked to the cloud. Finishing sync…',
      );
  String get settingsSearchHint =>
      _t('ابحث في الإعدادات…', 'Search settings…');
  String get settingsSearchEmpty =>
      _t('لا توجد نتائج مطابقة.', 'No matching settings.');
  String settingsSearchResultLocation(String section, String panel) =>
      _t('$section · $panel', '$section · $panel');
  String get settingsTeamProgramCardTitle =>
      _t('الموظفين وكلمة مرور البرنامج', 'Employees & program password');
  String get settingsTeamProgramCardBody => _t(
        'أضف الموظفين (اسم دخول وكلمة مرور). صاحب الاشتراك يظهر كـ Admin.',
        'Add employees with their own sign-in. The subscription owner appears as Admin.',
      );
  String get settingsTeamOpenFullManager =>
      _t('إدارة الموظفين والصلاحيات…', 'Manage employees & permissions…');
  String get settingsProgramUnlockTitle =>
      _t('كلمة مرور موحّدة لفتح القفل', 'Shared unlock password');
  String get settingsProgramUnlockSub => _t(
        'عند التفعيل يمكن إدخال هذه الكلمة أو كلمة مرور المستخدم الحالي بعد قفل الخمول. عطّل الخيار لإلغاء الكلمة الموحّدة.',
        'When on, you can enter this password or the current user password after idle lock. Turn off to disable the shared password.',
      );
  String get settingsProgramUnlockPassword =>
      _t('كلمة المرور الموحّدة', 'Shared password');
  String get settingsProgramUnlockPasswordConfirm =>
      _t('تأكيد كلمة المرور', 'Confirm password');
  String get settingsProgramUnlockHintExisting => _t(
        'اترك الحقلين فارغين للإبقاء على الكلمة الحالية.',
        'Leave both fields blank to keep the current password.',
      );
  String get settingsErrProgramUnlockNeedsPw => _t(
        'فعّلت كلمة المرور الموحّدة — أدخل كلمة مرور جديدة وتأكيدها.',
        'Shared unlock is on — enter and confirm a new password.',
      );
  String get settingsErrProgramUnlockMismatch =>
      _t('كلمتا المرور غير متطابقتين.', 'Passwords do not match.');
  String get ownerDisplayNameAdmin => _t('المدير', 'Admin');
  String get settingsHeaderSubtitle =>
      _t('اضبط المتجر والواجهة والنسخ الاحتياطي', 'Store, UI & backups');
  String get settingsErrStoreName =>
      _t('اسم المتجر مطلوب.', 'Store name is required.');
  String get settingsErrCurrency =>
      _t('العملة مطلوبة.', 'Currency is required.');
  String get settingsErrLogoPath =>
      _t('مسار الشعار غير صحيح.', 'Invalid logo path.');
  String get settingsErrStampPath =>
      _t('مسار التوقيع أو الختم غير صحيح.', 'Invalid stamp/signature path.');
  String get settingsErrBackupFolder => _t(
        'مجلد النسخ غير موجود أو غير متاح.',
        'Backup folder does not exist or is unavailable.',
      );
  String get settingsErrLowStock =>
      _t('عتبة المخزون المنخفض غير صحيحة.', 'Invalid low-stock threshold.');
  String get settingsErrTax =>
      _t('نسبة الضريبة غير صحيحة (0–100).', 'Tax rate must be 0–100.');
  String get settingsErrLineQtyStep => _t(
        'خطوة الكمية يجب أن تكون بين 0.01 و 999.',
        'Quantity step must be between 0.01 and 999.',
      );
  String settingsErrRecentSaleRibbon(int min, int max) => _t(
        'عدد فواتير شريط «أحدث المبيعات» يجب أن يكون عدداً صحيحاً بين $min و $max.',
        'Recent sale invoices ribbon count must be an integer between $min and $max.',
      );
  String get settingsErrIdle => _t('مهلة الخمول يجب أن تكون بين 1 و 480 دقيقة.',
      'Idle timeout must be 1–480 minutes.');

  String get secCardStoreLang => _t('المتجر واللغة', 'Store & language');
  String get secLangLabel => _t('اللغة', 'Language');
  String get secLangArabic => _t('العربية', 'Arabic');
  String get secLangEnglish => 'English';
  String get secStoreName => _t('اسم المتجر', 'Store name');
  String get secStoreAddress => _t('عنوان المتجر', 'Store address');
  String get secPhone => _t('رقم الهاتف', 'Phone');
  String get secPhoneAlt => _t('رقم هاتف إضافي', 'Alternate phone');
  String get secCountry => _t('الدولة / المنطقة', 'Country / region');

  String get secLogoStamp => _t('الشعار والختم', 'Logo & stamp');
  String get secLogoPath => _t('شعار المتجر (ملف)', 'Store logo (file)');
  String get secLogoPathHint =>
      _t('اختر صورة من الجهاز (PNG أو JPG)', 'Pick an image (PNG or JPG)');
  String get secStampPath =>
      _t('التوقيع أو الختم (ملف)', 'Stamp / signature (file)');
  String get secStampPathHint =>
      _t('صورة للطباعة على الفاتورة', 'Image printed on invoices');
  String get secPickImageTooltip => _t('اختيار ملف صورة', 'Choose image file');

  String get secFinanceTax => _t('المالية والضريبة', 'Finance & tax');
  String get secCurrency => _t('العملة', 'Currency');
  String get secSubunitName => _t('اسم أجزاء العملة', 'Subunit name');
  String get secSubunitHint => _t('مثل: أغورة، قرش، فلس', 'e.g. cent, piastre');
  String get secDecimalPlaces => _t('عدد الأجزاء العشرية', 'Decimal places');
  String get secTaxPercent => _t('نسبة الضريبة %', 'Tax rate %');
  String get secTaxIdsTitle => _t('المعلومات الضريبية والتعريف', 'Tax IDs');
  String get secTaxNif => _t('الرقم الضريبي (NIF)', 'Tax ID (NIF)');
  String get secTaxRc =>
      _t('رقم السجل التجاري (RC)', 'Commercial register (RC)');
  String get secTaxAi => _t('رقم المادة (AI)', 'Article ID (AI)');
  String get secTaxNis =>
      _t('رقم التعريف الإحصائي (NIS)', 'Statistical ID (NIS)');

  String get secAppearance => _t('المظهر', 'Appearance');
  String get secThemeColor => _t('لون الواجهة', 'Theme color');
  String get secDarkMode => _t('الوضع الداكن', 'Dark mode');
  String get secDarkModeSub =>
      _t('تباين أفضل في الإضاءة المنخفضة', 'Better contrast in low light');

  String get secHomeMainScreen => _t('الشاشة الرئيسية', 'Home screen');
  String get secHomeMainScreenSub => _t(
        'إظهار أو إخفاء شريط الأرقام والأزرار بجانب التقويم في الأسفل.',
        'Show or hide the KPI strip and footer buttons next to the calendar.',
      );
  String get secHomeKpiStrip =>
      _t('شريط الأرقام الإحصائية (مبيعات، مشتريات…)', 'KPI strip (sales, purchases…)');
  String get secHomeKpiStripSub => _t(
        'الصف الأفقي للبطاقات تحت عنوان الترحيب.',
        'Horizontal cards row under the greeting header.',
      );
  String get secHomeGreetingBanner => _t(
        'بطاقة الترحيب (صباح الخير)',
        'Greeting banner (good morning)',
      );
  String get secHomeGreetingBannerSub => _t(
        'المستطيل العلوي باسم المتجر وصافي الصندوق. يمكن إغلاقه من × في الصفحة الرئيسية.',
        'Top card with store name and net cash. Can be dismissed with × on the home screen.',
      );
  String get secHomeFooterBeforeCalendar => _t(
        'أزرار يسار التقويم (ترخيص، تفعيل)',
        'Buttons left of calendar (license, activation)',
      );
  String get secHomeFooterBeforeCalendarSub => _t(
        'في الشريط السفلي للشاشة الرئيسية.',
        'In the home footer bar.',
      );
  String get secHomeFooterAfterCalendar => _t(
        'أزرار يمين التقويم (وقت، عملة، حاسبة)',
        'Buttons right of calendar (time, currency, calculator)',
      );
  String get secHomeFooterAfterCalendarSub => _t(
        'أدوات مساعدة بجانب زر التقويم.',
        'Helper tools next to the calendar button.',
      );
  String get secHomeFooterDistributorsHub => _t(
        'زر منظومة الموزعون',
        'Distributors hub button',
      );
  String get secHomeFooterDistributorsHubSub => _t(
        'في الشريط السفلي للشاشة الرئيسية (سطح المكتب).',
        'In the desktop home footer bar.',
      );
  String get secNotifyCalendarAppointments =>
      _t('تنبيهات موعد التقويم', 'Calendar appointment alerts');
  String get secNotifyCalendarAppointmentsSub => _t(
        'إشعار سطح المكتب وصوت عند حلول وقت موعد اخترت له ساعة في التقويم.',
        'Desktop notification and sound when a calendar entry reaches its set time.',
      );

  String get secNotifyBackup =>
      _t('الإشعارات والنسخ الاحتياطي', 'Notifications & backup');
  String get secSounds => _t('تشغيل الأصوات', 'Sounds');
  String get secSoundsSub => _t(
      'أصوات خفيفة عند نجاح الباركود واختيار منتج من قائمة العرض في البيع/الشراء',
      'Light sounds when scanning barcodes and when picking a product from the browse list in sales/purchase');
  String get secNotifyStock => _t('إشعارات نفاذ الكمية', 'Low quantity alerts');
  String get secNotifyStockSub => _t(
      'تنبيه عند وجود أصناف منخفضة في لوحة التحكم',
      'Alert when items are low on the dashboard');
  String get secNotifyExpiry => _t('إشعارات انتهاء الصلاحية', 'Expiry alerts');
  String get secNotifyExpirySub => _t('ميزة مخزنة — تتطلب بيانات صلاحية لاحقًا',
      'Reserved — needs expiry data later');
  String get secNotifyLate =>
      _t('إشعارات العملاء المتأخرين', 'Late payment alerts');
  String get secNotifyLateSub => _t(
      'ميزة مخزنة — تتطلب تقرير الذمم', 'Reserved — needs receivables report');
  String get secAutoBackupExit =>
      _t('تفعيل النسخ التلقائي عند الإغلاق', 'Backup on exit');
  String get secAutoBackupExitSub => _t(
        'إنشاء نسخة احتياطية عند إغلاق البرنامج (حسب الإعداد أدناه)',
        'Create backup when closing (see drive below)',
      );
  String get secAutoBackupExitSubMobile => _t(
        'حفظ نسخة في مجلد التطبيق عند الضغط على زر الرجوع للخروج',
        'Save a backup in the app folder when you press back to exit',
      );
  String get secBackupDriveTitle =>
      _t('اختيار القرص للنسخ الاحتياطي عند الخروج', 'Backup drive on exit');
  String get secBackupMobileFolderTitle =>
      _t('مجلد النسخ داخل التطبيق', 'In-app backup folder');
  String get secBackupMobileFolderSub => _t(
        'تُحفظ النسخ الاحتياطية هنا تلقائياً. يمكنك تصديرها أو مشاركتها من «نسخة احتياطية الآن».',
        'Backups are stored here automatically. Export or share them via «Backup now».',
      );
  String get secBackupDestinationHintMobile => _t(
        'اختر ملف نسخة للاستعادة، أو أنشئ نسخة جديدة ثم شاركها عبر التطبيقات الأخرى.',
        'Pick a backup file to restore, or create a new backup and share it with other apps.',
      );
  String get backupDestinationAppFolder =>
      _t('حفظ في مجلد التطبيق', 'Save in app folder');
  String get backupDestinationAppFolderSub => _t(
        'يُحفظ داخل بيانات التطبيق ويمكن مشاركته لاحقاً.',
        'Saved inside app data; you can share it later.',
      );
  String get backupDestinationExport =>
      _t('تصدير / مشاركة', 'Export / share');
  String get backupDestinationExportSub => _t(
        'اختر مكان الحفظ أو شارك الملف عبر تطبيق آخر.',
        'Pick a save location or share via another app.',
      );

  String get secStartup => _t('تشغيل النظام', 'Startup');
  String get secWinStartup => _t('بدء التشغيل مع ويندوز', 'Start with Windows');
  String get secWinStartupSub => _t(
        'إضافة/إزالة مفتاح التشغيل التلقائي في سجل ويندوز',
        'Add/remove Run key in Windows registry',
      );
  String get secStartupScreenLabel =>
      _t('الشاشة عند بدء الجلسة بعد تسجيل الدخول', 'Screen after login');
  String get secStartupHome => _t('الشاشة الرئيسية', 'Home');
  String get secStartupSale => navSales;
  String get secStartupPurchase => navPurchases;
  String get secStartupInventory => navInventory;
  String get secStartupCash => navCash;
  String get secStartupExpense => navExpenses;

  String get secSaleUi => _t('إعدادات البيع والعرض', 'Sales & display');
  String get secQuickSale => _t('السماح بالبيع السريع', 'Allow quick sale');
  String get secQuickSaleSub => _t('أزرار البيع السريع واختصارات البحث السريع',
      'Quick-sale buttons and shortcuts');
  String get secBarcodeQuickAdd =>
      _t('إضافة فورية عند مطابقة الباركود', 'Instant add on barcode match');
  String get secHardwareBarcodeScanner => _t(
        'قارئ الباركود (USB/Bluetooth)',
        'Barcode scanner (USB/Bluetooth)',
      );
  String get secHardwareBarcodeScannerSub => _t(
        'يقبل المسح السريع في الفواتير والمخزون والبحث — امسح ثم Enter أو F3 لتركيز الحقل',
        'Accepts fast keyboard-wedge scans in invoices, stock, and search — scan then Enter or F3 to focus',
      );
  String get secBarcodeQuickAddSub => _t(
      'عند مسح باركود يطابق منتجاً واحداً: إضافة سطر بكمية ١ والسعر الافتراضي دون نافذة؛ مع صوت خفيف عند النجاح إذا فُعّل «تفعيل الأصوات».',
      'When scan matches one product: add a line with qty 1 and default price without a dialog; soft click sound on success if sounds are enabled.');
  String get secProdVertical =>
      _t('قائمة منتجات عمودية في نافذة الاختيار', 'Vertical product list');
  String get secProdVerticalSub => _t(
      'عرض أكثر راحة في نافذة جميع المنتجات', 'More comfortable picker layout');
  String get secProdImage => _t('إظهار صورة المنتج', 'Show product image');
  String get secProdImageSub => _t(
      'في الحاسوب: إظهار الصورة في قائمة المنتجات ونتائج البحث (الجوال يعرضها دائماً)',
      'On desktop: show images in product list and search (always on mobile)');
  String get secDupLines =>
      _t('تكرار السطر لنفس المنتج', 'Duplicate lines per product');
  String get secDupLinesSub =>
      _t('عدم دمج الكميات في سطر واحد', 'Do not merge quantities');
  String get secShowUnit => _t('إظهار عمود الوحدة', 'Show unit column');
  String get secShowUnitSub =>
      _t('جاهز عند إضافة حقل وحدة للمنتجات', 'Ready when unit field is added');
  String get secShowTaxCol =>
      _t('إظهار الضريبة في قائمة الأسطر', 'Show tax column');
  String get secShowTaxColSub =>
      _t('عمود مقابل الخصم الضريبي في الجدول', 'Column for tax/discount');
  String get secFavSale =>
      _t('قائمة المفضلة في المبيعات', 'Favorites in sales');
  String get secFavSaleSub => _t(
        'شريط أصناف مفضّلة فوق جدول الفاتورة للإضافة السريعة',
        'Quick-pick ribbon of starred products above the invoice lines',
      );
  String get secCreditSale => _t('السماح بالبيع بالأجل', 'Allow credit sales');
  String get secCreditSaleSub => _t('اختيار عميل مسجل بدل النقدي فقط',
      'Pick registered customer vs cash only');
  String get secCashBoxByPaymentTitle => _t(
      'حركة الصندوق حسب طريقة الدفع',
      'Cash box entries by payment method',
    );
  String get secCashBoxByPaymentIntro => _t(
      'عطّل أي خيار إذا لم ترد أن تُسجَّل فواتير أو مصاريف بهذه الطريقة كحركة في صندوق البرنامج (يبقى نوع الدفع على الفاتورة للتقارير). النقدي يُسجَّل دائماً.',
      'Turn off to skip posting that payment type to the app cash box (the invoice still stores the method for reports). Cash always posts.',
    );
  String get secPostBankToCashBox =>
      _t('تسجيل «بنك» في الصندوق', 'Post bank payments to cash box');
  String get secPostBankToCashBoxSub => _t(
      'عند التعطيل: فاتورة بنك لا تُضيف قبضاً أو صرفاً في حركة الصندوق.',
      'When off, bank-tagged invoices do not add cash movements.',
    );
  String get secPostWalletToCashBox =>
      _t('تسجيل «محفظة» في الصندوق', 'Post wallet payments to cash box');
  String get secPostWalletToCashBoxSub => _t(
      'عند التعطيل: فاتورة محفظة لا تُسجَّل في الصندوق.',
      'When off, wallet-tagged invoices skip the cash box.',
    );
  String get secPostCheckToCashBox =>
      _t('تسجيل «شيك» في الصندوق', 'Post check payments to cash box');
  String get secPostCheckToCashBoxSub => _t(
      'عند التعطيل: فاتورة شيك لا تُسجَّل في الصندوق.',
      'When off, check-tagged invoices skip the cash box.',
    );
  String get secPriceQuotes => _t('السماح بعرض السعر', 'Allow price quotes');
  String get secPriceQuotesSub => _t(
      'إنشاء عروض أسعار للمنتجات دون خصم مخزون أو تسجيل صندوق',
      'Create product price quotes without stock or cash posting');
  String get secEditPriceAdd =>
      _t('تعديل السعر عند الإضافة', 'Edit price when adding');
  String get secEditPriceAddSub => _t('تمكين حقل السعر في نافذة إضافة الصنف',
      'Enable price field in add dialog');
  String get secSellBelowCost =>
      _t('السماح بالبيع دون التكلفة', 'Allow selling below cost');
  String get secSellBelowCostSub =>
      _t('السماح بسعر بيع أقل من التكلفة', 'Allow sale price under cost');
  String get secEditInvDate =>
      _t('السماح بتعديل تاريخ الفاتورة', 'Allow editing invoice date');
  String secEditInvDateSub(bool on) => on
      ? _t('يمكن تغيير التاريخ', 'Date can be changed')
      : _t('تاريخ اليوم فقط', 'Today only');
  String get secEditInvNo =>
      _t('السماح بتعديل رقم الفاتورة', 'Allow editing invoice number');
  String get secEditInvNoSub => _t(
      'يتطلب دعمًا من الخادم لاحقًا — مخزن كإعداد', 'Reserved — needs backend');
  String get secAutoPaid =>
      _t('عرض المبلغ المدفوع تلقائيًا', 'Auto-show paid amount');
  String get secAutoPaidSub =>
      _t('جاهز للربط بحقل الدفع', 'Reserved for payment field');
  String get secAddBalTx => _t(
      'السماح بالإضافة للرصيد من الشاشة', 'Allow balance actions from screen');
  String get secAddBalTxSub =>
      _t('زر تسديد العملاء/الموردين', 'Customer/supplier settlement button');
  String get secQtyPicker =>
      _t('إظهار الكمية المتوفرة في البحث', 'Show qty in product search');
  String get secQtyPickerSub =>
      _t('في قائمة اختيار المنتجات', 'In product picker');
  String get secLineQtyStep =>
      _t('خطوة الكمية في جدول الفاتورة (+/−)', 'Invoice line qty step (+/−)');
  String get secLineQtyStepHint => _t(
        'مقدار الزيادة أو النقصان عند الضغط على الزرين بجانب الكمية (مثال: 1 أو 0.5).',
        'Amount added or removed per +/− tap next to quantity (e.g. 1 or 0.5).',
      );
  String get secRecentSaleRibbonLimit => _t(
        'عدد فواتير «أحدث المبيعات» في شاشة البيع',
        'Recent sale invoices count on sale screen',
      );
  String get secRecentSaleRibbonLimitSub => _t(
        'الشريط الأفقي أسفل شاشة الفاتورة (افتراضي 10، بين 3 و 100).',
        'Horizontal ribbon on the invoice screen (default 10, range 3–100).',
      );

  String get secInventoryWarn =>
      _t('المخزون والتحذيرات', 'Inventory & warnings');
  String get secLowStockField =>
      _t('عتبة تنبيه المخزون المنخفض', 'Low-stock threshold');
  String get secLowStockFieldHint => _t(
      'تُستخدم في لوحة التحكم وتنبيه المخزون', 'Used on dashboard and alerts');
  String get secWarnLow => _t('تحذير عند نقص المخزون', 'Warn on low stock');
  String get secWarnLowSub => _t('تمييز أقوى في لوحة التحكم عند التفعيل',
      'Stronger highlight on dashboard');
  String get secPreventOos =>
      _t('منع البيع عند نفاد الكمية', 'Block sale when out of stock');
  String get secPreventOosSub =>
      _t('التحقق من الرصيد قبل الحفظ', 'Check stock before save');
  String get secCostInv =>
      _t('إظهار التكلفة في شاشة إدارة المخزون', 'Show cost in inventory screen');
  String get secCostInvSub =>
      _t('عمود التكلفة في جدول المنتجات', 'Cost column in grid');
  String get secInvOnlyStock =>
      _t('عرض ما له مخزون فقط', 'Only items with stock');
  String get secInvOnlyStockSub =>
      _t('إخفاء الأصناف ذات الرصيد صفر', 'Hide zero-qty rows');
  String get secInvShowBarcodeTable => _t(
        'إظهار الباركود في جدول المخزون',
        'Show barcode in warehouse table',
      );
  String get secInvShowBarcodeTableSub => _t(
        'سطر الباركود تحت اسم المنتج في صفحة الأصناف المتوفرة',
        'Barcode line under the product name on the stock browse page',
      );

  String get secDashSecurity => _t('لوحة التحكم', 'Dashboard layout');
  String get secReorderTiles =>
      _t('ترتيب مربعات لوحة التحكم', 'Reorder dashboard tiles');
  String get secDashTileLabelsSection =>
      _t('تسميات المربعات على الشاشة الرئيسية', 'Home screen tile names');
  String get secDashTileLabelsHint => _t(
        'اترك الحقل فارغًا لاستخدام الاسم الافتراضي للغة الحالية.',
        'Leave empty to use the default label for the current language.',
      );
  String get secDashTileShortcuts =>
      _t('اختصارات تحت المربعات', 'Shortcuts under tiles');
  String get secDashTileShortcutsSub => _t(
        'أزرار خفيفة تحت كل مربّع في الصفحة الرئيسية (فاتورة مبيعات، عرض سعر، …)',
        'Quick-action chips under each home tile (sales invoice, quote, …)',
      );
  String get secDashShortcutsCustomize =>
      _t('تخصيص الاختصارات', 'Customize shortcuts');
  String get secDashShortcutsDialogHint => _t(
        'اختر حتى 3 اختصارات لكل مربّع. اضغط على الزر لإضافته أو إزالته.',
        'Pick up to 3 shortcuts per tile. Tap a chip to add or remove it.',
      );
  String get secDashShortcutsReset =>
      _t('استعادة الافتراضي', 'Restore defaults');
  String dashShortcutLabel(String actionId) {
    switch (actionId) {
      case 'sales_invoice':
        return _t('فاتورة مبيعات', 'Sales invoice');
      case 'sales_quote':
        return _t('عرض سعر', 'Price quote');
      case 'sales_archive':
        return _t('أرشيف الفواتير', 'Invoice archive');
      case 'purchase_invoice':
        return _t('فاتورة شراء', 'Purchase invoice');
      case 'purchase_archive':
        return _t('أرشيف الشراء', 'Purchase archive');
      case 'customers_open':
        return _t('دليل العملاء', 'Customers');
      case 'customers_add':
        return _t('عميل جديد', 'New customer');
      case 'suppliers_open':
        return _t('دليل الموردين', 'Suppliers');
      case 'suppliers_add':
        return _t('مورد جديد', 'New supplier');
      case 'cash_open':
        return _t('حركة الصندوق', 'Cash box');
      case 'cash_receipt':
        return _t('قبض', 'Receipt');
      case 'cash_payment':
        return _t('صرف', 'Payment');
      case 'expenses_open':
        return _t('المصروفات', 'Expenses');
      case 'expenses_new':
        return _t('مصروف جديد', 'New expense');
      case 'inventory_open':
        return _t('المخزون', 'Inventory');
      case 'inventory_low_stock':
        return _t('نواقص المخزون', 'Low stock');
      case 'queries_open':
        return _t('الاستعلامات', 'Queries');
      case 'queries_classic':
        return _t('تقارير كلاسيكية', 'Classic reports');
      default:
        return actionId;
    }
  }
  String get dashboardPreviewPrefix => _t('المعاينة:', 'Preview:');
  String dashboardPreviewJoin(List<String> titles) =>
      titles.join(_en ? ' · ' : ' ← ');
  String get secSecurityPermsTitle =>
      _t('الأمان والصلاحيات', 'Security & permissions');
  String secIdleHint(int minutes, bool idleEnabled) => _en
      ? idleEnabled
          ? 'Idle lock is on ($minutes min).\nOnly the system owner can change security.'
          : 'Idle lock is off.\nOnly the system owner can change security.'
      : idleEnabled
          ? 'قفل الخمول مفعّل — المهلة: $minutes دقيقة.\nتعديل الأمان متاح لمالك النظام فقط.'
          : 'قفل الخمول معطّل.\nتعديل الأمان متاح لمالك النظام فقط.';
  String get secIdleLockToggle =>
      _t('تفعيل قفل الشاشة بعد الخمول', 'Enable idle screen lock');
  String get secIdleLockToggleSub => _t(
      'عند التعطيل لا يُطلب قفل الشاشة مهما طال عدم النشاط',
      'When off, the screen will not lock after inactivity');
  String get secIdleLockField =>
      _t('مهلة الخمول قبل القفل (دقيقة)', 'Minutes before lock');
  String get secIdleLockHelper => _t('من 1 إلى 480', '1 to 480');
  String get secOwnerPermsRo =>
      _t('صلاحيات كاملة — للقراءة فقط هنا', 'Full access — read-only here');

  String get secBackupCard => _t(
        'البيانات: استيراد إكسل والنسخ الاحتياطي',
        'Data: Excel import & backup',
      );
  String get secBackupDestinationHint => _t(
        'يُمكن الحفظ على الجهاز (أي مجلد) أو داخل مجلد Google Drive المزامن على هذا الكمبيوتر.',
        'Save to any local folder, or to your synced Google Drive folder on this PC.',
      );
  String get backupDestinationTitle =>
      _t('وجهة النسخة الاحتياطية', 'Backup destination');
  String get backupDestinationLocal =>
      _t('على الجهاز (اختر المجلد)', 'This PC (choose folder)');
  String get backupDestinationLocalSub => _t(
        'يظهر مربع حفظ الملف — يمكنك اختيار سطح المكتب أو أي قرص.',
        'Opens a save dialog (Desktop, USB, etc.).',
      );
  String get backupDestinationGoogleDrive =>
      _t('Google Drive (المجلد المزامن)', 'Google Drive (synced folder)');
  String get backupDestinationGoogleDriveSub => _t(
        'يُحفظ تلقائيًا إذا وُجد تطبيق «Google Drive للكمبيوتر» أو المزامنة الكلاسيكية.',
        'Saves automatically if Google Drive for desktop / sync is installed.',
      );
  String get backupGoogleDriveNotFoundTitle =>
      _t('لم يُعثر على مجلد Google Drive', 'Google Drive folder not found');
  String get backupGoogleDriveNotFoundBody => _t(
        'ثبّت «Google Drive للكمبيوتر» وفعّل المزامنة، أو احفظ الملف على الجهاز ثم ارفعه يدويًا إلى drive.google.com من المتصفح.',
        'Install Google Drive for desktop and sync your folder, or save a file below and upload it manually at drive.google.com.',
      );
  String get backupPickFolderSave =>
      _t('اختيار مكان الحفظ', 'Choose save location');
  String get backupOpenDriveWeb =>
      _t('فتح Google Drive في المتصفح', 'Open Google Drive in browser');
  String get secBackupNow => _t('نسخة احتياطية الآن', 'Backup now');
  String get secRestorePathEmpty =>
      _t('أدخل مسار ملف النسخة.', 'Enter backup file path.');
  String secRestorePickerFailed(Object e) => _en
      ? 'Could not open file picker: $e'
      : 'تعذر فتح نافذة اختيار الملف: $e';
  String get secRestoreFromFile => _t('استعادة من ملف', 'Restore from file');
  String get secClearOps =>
      _t('مسح البيانات التشغيلية', 'Clear operational data');

  String get secExcelImportCard =>
      _t('استيراد من إكسل', 'Import from Excel');
  String get secExcelImportHint => _t(
        'استيراد منتجات أو عملاء أو موردين أو فواتير شراء/بيع أو مصاريف من ملف إكسل صادر من أي برنامج محاسبة. '
        'حمّل القالب، عبّئ الأعمدة، ثم اختر الملف.',
        'Import products, customers, suppliers, purchase/sale invoices, or expenses from an Excel file exported from another accounting app. '
        'Download the template, fill the columns, then pick your file.',
      );
  String get secExcelImportOpen =>
      _t('فتح استيراد إكسل…', 'Open Excel import…');

  String get excelImportScreenTitle =>
      _t('استيراد بيانات من إكسل', 'Import data from Excel');
  String get excelImportIntro => _t(
        'اختر نوع البيانات ثم ملف إكسل. لا حاجة لتسجيل دخول فريق العمل — يكفي استخدام البرنامج كالمعتاد. '
        'يُتعرّف على أسماء الأعمدة بالعربية أو الإنجليزية. '
        'فواتير الشراء والبيع تُجمَّع تلقائياً حسب رقم الفاتورة. '
        'لا تُسجَّل حركات صندوق عند الاستيراد (بيانات تاريخية).',
        'Choose the data type and an Excel file. No team login required — normal app use is enough. '
        'Column headers may be Arabic or English. '
        'Purchase and sale lines are grouped by invoice number. '
        'Cash box is not updated on import (historical data).',
      );
  String get excelImportNoPermission => _t(
        'ليس لديك صلاحية استيراد البيانات من إكسل. إن كنت موظفاً، اطلب من المسؤول تفعيل «استيراد بيانات من إكسل» من فريق العمل → الصلاحيات.',
        'You do not have permission to import from Excel. If you are staff, ask an admin to enable “Import data from Excel” under Team → Permissions.',
      );
  String get excelImportUnavailable => _t(
        'استيراد إكسل غير متاح في هذه الشاشة.',
        'Excel import is not available on this screen.',
      );
  String get excelImportKindLabel =>
      _t('نوع البيانات', 'Data type');
  String excelImportKindName(ExcelImportKind kind) {
    switch (kind) {
      case ExcelImportKind.products:
        return _t('المنتجات', 'Products');
      case ExcelImportKind.customers:
        return _t('العملاء', 'Customers');
      case ExcelImportKind.suppliers:
        return _t('الموردين', 'Suppliers');
      case ExcelImportKind.purchases:
        return _t('فواتير الشراء', 'Purchase invoices');
      case ExcelImportKind.sales:
        return _t('فواتير البيع', 'Sales invoices');
      case ExcelImportKind.expenses:
        return _t('المصاريف', 'Expenses');
    }
  }

  String excelImportKindHint(ExcelImportKind kind) {
    switch (kind) {
      case ExcelImportKind.products:
        return _t('اسم، أسعار، كمية مخزون', 'Name, prices, stock qty');
      case ExcelImportKind.customers:
        return _t('اسم، هاتف، عنوان', 'Name, phone, address');
      case ExcelImportKind.suppliers:
        return _t('اسم، هاتف، عنوان', 'Name, phone, address');
      case ExcelImportKind.purchases:
        return _t('سطر لكل صنف في الفاتورة', 'One row per line item');
      case ExcelImportKind.sales:
        return _t('سطر لكل صنف في الفاتورة', 'One row per line item');
      case ExcelImportKind.expenses:
        return _t('بيان ومبلغ وتاريخ', 'Title, amount, date');
    }
  }

  String get excelImportColumnsTitle =>
      _t('أعمدة الملف المتوقعة', 'Expected file columns');
  String get excelImportDownloadTemplate =>
      _t('تحميل قالب إكسل', 'Download Excel template');
  String get excelImportPickFile =>
      _t('اختيار ملف…', 'Choose file…');
  String get excelImportRun => _t('بدء الاستيراد', 'Start import');
  String excelImportPickFailed(Object e) =>
      _t('تعذر فتح الملف: $e', 'Could not open file: $e');
  String excelImportTemplateSaved(String path) =>
      _t('تم حفظ القالب: $path', 'Template saved: $path');
  String get excelImportTemplateShared => _t(
        'القالب جاهز — اختر «حفظ في الملفات» أو التطبيق المناسب من قائمة المشاركة.',
        'Template ready — choose Save to Files or another app from the share menu.',
      );
  String excelImportTemplateFailed(Object e) =>
      _t('تعذر تحميل القالب: $e', 'Could not download template: $e');
  String excelImportDoneSummary(ExcelImportResult r) => _en
      ? 'Imported: ${r.imported}, skipped: ${r.skipped}'
          '${r.errors.isEmpty ? '' : ', errors: ${r.errors.length}'}'
      : 'تم استيراد ${r.imported}، تخطي ${r.skipped}'
          '${r.errors.isEmpty ? '' : '، أخطاء: ${r.errors.length}'}';
  String get excelImportResultTitle =>
      _t('نتيجة الاستيراد', 'Import result');
  String get excelImportErrorsTitle =>
      _t('تفاصيل الأخطاء', 'Error details');
  String excelImportMoreErrors(int n) =>
      _t('و $n خطأ إضافي…', 'and $n more errors…');

  String get secFactoryReset =>
      _t('مسح كل البيانات والبدء من جديد', 'Erase all data & start fresh');

  String get secFactoryResetCardTitle =>
      _t('بداية جديدة على هذا الجهاز', 'Fresh start on this device');

  String get secFactoryResetCardBody => _t(
        'بعد تجربة البرنامج يمكنك مسح كل البيانات المحلية والعودة كأنك تثبّته لأول مرة. '
        'مفيد قبل إنشاء متجرك الحقيقي أو مشاركة الجهاز.',
        'After trying the app you can erase all local data and start as if it were a new install. '
        'Useful before setting up your real store or sharing the device.',
      );

  String get factoryResetTitle =>
      _t('مسح كل البيانات', 'Erase all data');

  String get factoryResetBody => _t(
        'سيتم حذف كل ما على هذا الجهاز نهائياً:\n'
        '• الفواتير والمرتجعات والمصروفات\n'
        '• العملاء والموردين والأصناف\n'
        '• المستخدمون وكلمات المرور\n'
        '• حركات الصندوق والمخزون والذمم\n'
        '• إعدادات المتجر والجلسة والنسخ الاحتياطية المحلية\n\n'
        'يُنصح بأخذ نسخة احتياطية قبل المتابعة إن كانت لديك بيانات مهمة.\n\n'
        'للتأكيد اكتب: مسح الكل',
        'Everything on this device will be permanently deleted:\n'
        '• Invoices, returns, and expenses\n'
        '• Customers, suppliers, and products\n'
        '• Users and passwords\n'
        '• Cash, stock, and ledger movements\n'
        '• Store settings, session, and local backups\n\n'
        'Back up first if you have important data.\n\n'
        'Type DELETE ALL to confirm',
      );

  String get factoryResetConfirmPhrase => _t('مسح الكل', 'DELETE ALL');

  String get factoryResetConfirmButton =>
      _t('مسح الكل والبدء من جديد', 'Erase all & start fresh');

  String get factoryResetOk => _t(
        'تم مسح البيانات. البرنامج جاهز للبدء من جديد — سجّل حساب المالك أو استخدم وضع الزائر.',
        'All data was erased. You can start fresh — sign in as owner or continue as guest.',
      );
  String get secRestorePathField =>
      _t('ملف النسخة الاحتياطية للاستعادة', 'Backup file to restore');
  String get secRestorePathHint => _t(
        'ملف JSON من النسخ الاحتياطي — «استعادة من ملف» يفتح الاختيار ثم يستعيد',
        'Backup JSON file — «Restore from file» opens the picker then restores',
      );
  String get secPickBackupTooltip =>
      _t('اختيار ملف النسخة', 'Choose backup file');

  // قفل الخمول
  String get idleLockTitle => _t('قفل تلقائي للخمول', 'Idle lock');
  String get idleLockBody => _t(
        'لم يتم تسجيل أي نشاط لفترة. أدخل كلمة المرور للمتابعة.',
        'No activity for a while. Enter your password to continue.',
      );
  String get idleLockBodyProgramOrUser => _t(
        'أدخل كلمة مرور المستخدم الحالي أو كلمة مرور البرنامج الموحّدة.',
        'Enter the current user password or the shared program unlock password.',
      );
  String get unlock => _t('فتح القفل', 'Unlock');
  String get wrongPassword =>
      _t('كلمة المرور غير صحيحة.', 'Incorrect password.');

  // بحث سريع
  String get globalSearchTitle => _t('بحث سريع', 'Quick search');
  String get globalSearchHint => _t(
        'ابحث عن عميل، صنف، أو جزء من رقم الفاتورة…',
        'Search customer, product, or part of invoice number…',
      );
  String get searchStartTyping =>
      _t('ابدأ بالكتابة للبحث.', 'Start typing to search.');
  String get searchNoResults =>
      _t('لا توجد نتائج مطابقة.', 'No matching results.');
  String get invoiceDefaultTitle => _t('فاتورة', 'Invoice');
  String invoiceOpenFailed(Object e) =>
      _en ? 'Could not open invoice: $e' : 'تعذر فتح الفاتورة: $e';
  String invoiceLineSummary(String name, Object q, Object p, Object total) =>
      _en ? '$name — qty $q × $p = $total' : '$name — كمية $q × $p = $total';
  String get invoiceTaxFooter =>
      _en ? '\n\nTax IDs:\n' : '\n\nالبيانات الضريبية:\n';
  String get taxNifLbl => _t('الرقم الضريبي (NIF)', 'Tax ID (NIF)');
  String get taxRcLbl => _t('السجل التجاري (RC)', 'Commercial register (RC)');
  String get taxAiLbl => _t('رقم المادة (AI)', 'Article ID (AI)');
  String get taxNisLbl => _t('التعريف الإحصائي (NIS)', 'Statistical ID (NIS)');
  String get invoiceMetaId => _t('المعرّف', 'ID');
  String get invoiceMetaDetails => _t('التفاصيل', 'Details');
  String get invoiceMetaLines => _t('البنود', 'Lines');

  // قائمة الإدارة
  String get menuSettings => settingsScreenTitle;
  String get menuBranches => branchesTitle;
  String get menuUsers => usersSecurityScreenTitle;
  String get menuTax => _t('الضريبة', 'Tax');
  String get menuMonthCompare => _t('مقارنة الأشهر', 'Month comparison');
  String get menuAudit => _t('التدقيق', 'Audit');
  String get menuPrinter => _t('الطابعة', 'Printer');
  String get menuBackup => _t('النسخ الاحتياطي', 'Backup');
  String get menuMizaCloud => mizaCloudScreenTitle;
  String get menuCancelCash =>
      _t('إلغاء سند قبض/صرف', 'Void cash receipt/payment');
  String get menuCancelAmounts =>
      _t('إلغاء مبلغ صندوق / مصروفات', 'Void cashbox/expense amount');
  String get menuAgents => _t('وكلاؤنا', 'Our agents');
  String get menuHelp => _t('المساعدة', 'Help');
  String get menuAbout => _t('عن البرنامج', 'About');
  String get legalTermsOfUse => _t('شروط الاستخدام', 'Terms of use');
  String get legalPrivacyPolicy => _t('سياسة الخصوصية', 'Privacy policy');
  String get legalLinkOpenFailed => _t(
        'تعذّر فتح الرابط. تحقق من الاتصال بالإنترنت.',
        'Could not open the link. Check your internet connection.',
      );
  String legalLastUpdated(String date) =>
      _t('آخر تحديث: $date', 'Last updated: $date');
  String get menuProgramUpdate => _t('تحديث البرنامج', 'Program update');

  String get menuFieldOrders => _t('طلبات الميدان', 'Field orders');

  String get menuPublishFieldCatalog => _t(
        'نشر كتالوج الميدان',
        'Publish field catalog',
      );

  String fieldCatalogPublishOk(int productCount, int customerCount) => _t(
        'تم نشر $productCount صنفاً و $customerCount عميلاً للموزّعين.',
        'Published $productCount product(s) and $customerCount customer(s) for distributors.',
      );

  String get fieldCatalogPublishFailed => _t(
        'تعذّر نشر الكتالوج. تحقق من الاتصال وإعدادات الخادم.',
        'Could not publish catalog. Check connection and server settings.',
      );

  String get fieldCatalogPullForbidden => _t(
        'تعذّر جلب الكتالوج. تأكد من تفعيل القسيمة على هذا الجهاز.',
        'Could not fetch catalog. Ensure the voucher is activated on this device.',
      );

  String get fieldCatalogPublishEmpty => _t(
        'لا توجد أصناف أو عملاء لنشرها.',
        'No products or customers to publish.',
      );

  String get distributorCatalogSyncing => _t(
        'جارٍ تحديث كتالوج الميدان…',
        'Updating field catalog…',
      );

  String distributorCatalogSynced(int products, int customers) => _t(
        'كتالوج الميدان: $products صنفاً · $customers عميلاً',
        'Field catalog: $products product(s) · $customers customer(s)',
      );

  String get fieldOrdersScreenTitle => menuFieldOrders;

  String get fieldOrdersUnavailable => _t(
        'طلبات الميدان تتطلب اتصال خادم التفعيل وبريد اشتراك صالحاً.',
        'Field orders require the activation server and a valid subscription e-mail.',
      );

  String get fieldOrdersReviewerLoginRequired => _t(
        'سجّل دخول كمالك أو مدير فرع أو محاسب لاستخدام طلبات الميدان ونشر الكتالوج.',
        'Sign in as owner, branch manager, or accountant to use field orders and publish the catalog.',
      );

  String get fieldOrdersOffline => _t(
        'تعذر الاتصال بالخادم. تحقق من الإنترنت وحاول مجدداً.',
        'Could not reach the server. Check your connection and try again.',
      );

  String get fieldOrdersForbidden => _t(
        'لا صلاحية لعرض طلبات هذه المؤسسة.',
        'No permission to view orders for this organization.',
      );

  String get fieldOrdersLoadFailed => _t(
        'تعذر تحميل الطلبات المعلّقة.',
        'Could not load pending orders.',
      );

  String get fieldOrdersEmpty => _t(
        'لا توجد طلبات معلّقة من الموزّعين.',
        'No pending distributor orders.',
      );

  String get fieldOrdersPendingBadge => _t('معلّق', 'Pending');

  String fieldOrdersDistributor(String name) =>
      _t('الموزّع: $name', 'Distributor: $name');

  String fieldOrdersLineCount(int n) =>
      _t('$n بند', n == 1 ? '1 line' : '$n lines');

  String fieldOrdersTotal(String amount) =>
      _t('الإجمالي: $amount', 'Total: $amount');

  String get fieldOrdersApproveTitle => _t('اعتماد الطلب', 'Approve order');

  String fieldOrdersApproveBody(String customer) => _t(
        'اعتماد طلب العميل «$customer» وإنشاء فاتورة بيع (آجل)؟',
        'Approve order for «$customer» and create a deferred sales invoice?',
      );

  String get fieldOrdersApproveCreatesSale => _t(
        'يُخصم المخزون ويُسجَّل البيع في قاعدة هذا الجهاز.',
        'Stock will be deducted and the sale recorded on this device.',
      );

  String get fieldOrdersApproveAction => _t('اعتماد', 'Approve');

  String get fieldOrdersRejectTitle => _t('رفض الطلب', 'Reject order');

  String get fieldOrdersRejectReasonLabel => _t('سبب الرفض', 'Rejection reason');

  String get fieldOrdersRejectAction => _t('رفض', 'Reject');

  String fieldOrdersApprovedOk(String invoiceId) => _t(
        'تم الاعتماد وإنشاء فاتورة البيع.',
        'Approved and sales invoice created.',
      );

  String get fieldOrdersRejectedOk => _t('تم رفض الطلب.', 'Order rejected.');

  String fieldOrdersProductNotFound(String name) => _t(
        'الصنف غير موجود محلياً: $name',
        'Product not found locally: $name',
      );

  String fieldOrdersPriceRequired(String name) => _t(
        'السعر مطلوب للصنف: $name',
        'Price required for: $name',
      );

  String get fieldOrdersCustomerRequired => _t(
        'اسم العميل مطلوب.',
        'Customer name is required.',
      );

  String get fieldOrdersRejectReasonRequired => _t(
        'أدخل سبب الرفض.',
        'Enter a rejection reason.',
      );

  String get fieldOrdersAlreadyReviewed => _t(
        'تمت مراجعة هذا الطلب مسبقاً.',
        'This order was already reviewed.',
      );

  String fieldOrdersRemoteApproveFailed(String detail) => _t(
        'تعذر اعتماد الطلب على الخادم: $detail',
        'Could not approve the order on the server: $detail',
      );

  String get fieldOrdersApproveFailed => _t(
        'تعذر اعتماد الطلب.',
        'Could not approve the order.',
      );

  String fieldOrdersApproveFailedDetail(String detail) => _t(
        'تعذر اعتماد الطلب: $detail',
        'Could not approve the order: $detail',
      );

  String get fieldOrdersRefresh => _t('تحديث', 'Refresh');

  String get fieldOrdersRetry => _t('إعادة المحاولة', 'Retry');

  String get menuDistributors => _t('الموزعون', 'Distributors');

  String get distributorsHubSubtitle => _t(
        'طلبات الميدان، السيارات، والمخزون',
        'Field orders, trucks, and inventory',
      );

  String get menuFieldExpenses => _t('مصروفات الميدان', 'Field expenses');

  String get fieldExpensesUnavailable => _t(
        'مصروفات الميدان غير متاحة — تحقق من إعدادات الخادم.',
        'Field expenses unavailable — check server settings.',
      );

  String get fieldExpensesLoadFailed => _t(
        'تعذّر تحميل مصروفات الميدان.',
        'Could not load field expenses.',
      );

  String get fieldExpensesEmptyPending => _t(
        'لا توجد مصروفات بانتظار الاعتماد.',
        'No expenses awaiting approval.',
      );

  String get fieldExpensesApproveTitle =>
      _t('اعتماد المصروف', 'Approve expense');

  String fieldExpensesApproveBody(String title) => _t(
        'تسجيل مصروف «$title» في دفتر المصروفات بعد الاعتماد.',
        'Record expense «$title» in the expense ledger after approval.',
      );

  String get fieldExpensesApproveOk => _t(
        'تم اعتماد المصروف وتسجيله.',
        'Expense approved and recorded.',
      );

  String get fieldExpensesRejectOk => _t(
        'تم رفض المصروف.',
        'Expense rejected.',
      );

  String get fieldExpensesApproveFailed => _t(
        'تعذّر اعتماد المصروف.',
        'Could not approve expense.',
      );

  String fieldExpensesRemoteApproveFailed(String detail) => _t(
        'تعذّر اعتماد المصروف على الخادم: $detail',
        'Could not approve the expense on the server: $detail',
      );

  String fieldExpensesApproveFailedDetail(String detail) => _t(
        'تعذّر اعتماد المصروف: $detail',
        'Could not approve the expense: $detail',
      );

  String get fieldExpensesLocalExpenseFailed => _t(
        'تعذّر تسجيل المصروف محلياً.',
        'Could not record the expense locally.',
      );

  String get distributorsHubReturnsDesc => _t(
        'مرتجعات العملاء وتفريغ السيارة',
        'Customer returns and truck unload',
      );

  String get menuFieldReturns => _t('مرتجعات الميدان', 'Field returns');

  String get distributorsHubReturnsCustomerDesc => _t(
        'اعتماد مرتجعات العملاء الواردة من الميدان',
        'Approve customer returns from the field',
      );


  String get fieldReturnsUnavailable => _t(
        'مرتجعات الميدان غير متاحة — تحقق من إعدادات الخادم.',
        'Field returns unavailable — check server settings.',
      );

  String get fieldReturnsLoadFailed => _t(
        'تعذّر تحميل مرتجعات الميدان.',
        'Could not load field returns.',
      );

  String get fieldReturnsEmptyPending => _t(
        'لا توجد مرتجعات بانتظار الاعتماد.',
        'No returns awaiting approval.',
      );

  String get fieldReturnsApproveTitle =>
      _t('اعتماد المرتجع', 'Approve return');

  String fieldReturnsApproveBody(int lineCount) => _t(
        'تسجيل مرتجع بـ $lineCount أصناف في المحاسبة بعد الاعتماد.',
        'Record a return of $lineCount items in accounting after approval.',
      );

  String get fieldReturnsApproveOk => _t(
        'تم اعتماد المرتجع وتسجيله.',
        'Return approved and recorded.',
      );

  String get fieldReturnsRejectOk => _t(
        'تم رفض المرتجع.',
        'Return rejected.',
      );

  String get fieldReturnsApproveFailed => _t(
        'تعذّر اعتماد المرتجع.',
        'Could not approve return.',
      );

  String get fieldReturnsOrderNotFound => _t(
        'تعذّر العثور على البيع الأصلي على الخادم. '
        'تأكد أن المبيعة مُرسلة ومعتمدة من «طلبات الميدان» قبل اعتماد المرتجع.',
        'Could not find the original sale on the server. '
        'Ensure the sale was sent and approved from field orders before approving the return.',
      );

  String get fieldReturnsOrderNotApproved => _t(
        'يجب اعتماد البيع الأصلي قبل اعتماد المرتجع.',
        'The original sale must be approved before approving the return.',
      );

  String fieldReturnsRemoteApproveFailed(String detail) => _t(
        'تعذّر اعتماد المرتجع على الخادم: $detail',
        'Could not approve the return on the server: $detail',
      );

  String fieldReturnsApproveFailedDetail(String detail) => _t(
        'تعذّر اعتماد المرتجع: $detail',
        'Could not approve the return: $detail',
      );

  String get fieldReturnsLocalReturnFailed => _t(
        'تعذّر تسجيل المرتجع محلياً.',
        'Could not record the return locally.',
      );

  String get distributorHubTitle => _t('التوزيع الميداني', 'Field distribution');

  String get distributorsHubPublishAction => _t('نشر الآن', 'Publish now');

  String get distributorsHubHeroBadge => _t(
        'سيارات التوزيع والميدان',
        'Delivery trucks & field sales',
      );

  String get distributorsHubHeroTitle => _t(
        'مركز إدارة موزّعي البضاعة',
        'Field distributor control center',
      );

  String get distributorsHubHeroBody => _t(
        'هذه الصفحة مخصّصة لموزّعي البضاعة على سيارات التوزيع. يُصدر الموزّع الفواتير والطلبات من هاتفه المحمول، بينما يتصل برنامج الحاسوب بخادم المزامنة لمتابعة السيارات، تحميل المخزون، اعتماد المبيعات، واستخراج التقارير.',
        'This page is for distributors on delivery vehicles. The distributor issues invoices and orders from a mobile phone, while the desktop app connects to the sync server to manage vehicles, load stock, approve sales, and run reports.',
      );

  String get distributorsHubInternetNoticeTitle => _t(
        'تنبيه — يتطلب اتصالاً بالإنترنت',
        'Notice — internet connection required',
      );

  String get distributorsHubInternetNoticeBody => _t(
        'تعتمد خدمة الموزعين على إنترنت فعّال لربط نسخة الحاسوب بتطبيق الجوال لدى الموزّعين في الميدان. '
        'بدون اتصال لا تُزامَن المخزونات، ولا تصل مبيعات الميدان، ولا تُحدَّث بيانات السيارات.',
        'The distributors service needs an active internet connection to link the desktop app with distributors’ mobile apps in the field. '
        'Without connectivity, inventory will not sync, field sales will not arrive, and vehicle data will not update.',
      );

  String get distributorsHubSyncTitle => _t(
        'الربط بين الحاسوب والجوال',
        'Desktop ↔ mobile connection',
      );

  String get distributorsHubSyncHint => _t(
        'البيانات تتدفق عبر الإنترنت بين نقطة التحكم على الحاسوب وتطبيق الموزّع على الهاتف: المخزون، مخزون السيارة، والطلبات الواردة من الميدان.',
        'Data flows over the internet between the desktop control point and the distributor phone app: inventory, truck stock, and field orders.',
      );

  String get distributorsHubSyncDesktop => _t('الحاسوب', 'Desktop');
  String get distributorsHubSyncServer => _t('خادم المزامنة', 'Sync server');
  String get distributorsHubSyncMobile => _t('هاتف الموزّع', 'Distributor phone');

  String get distributorsHubSyncDesktopCaption => _t(
        'تحميل السيارة، الاعتماد، التقارير',
        'Load trucks, approve, reports',
      );

  String get distributorsHubSyncServerCaption => _t(
        'نشر المخزون ومزامنة البيانات',
        'Inventory publish & data sync',
      );

  String get distributorsHubSyncMobileCaption => _t(
        'فواتير وطلبات من الميدان',
        'Invoices & orders from the field',
      );

  String get distributorsHubWorkflowPublish => _t(
        '١ نشر المخزون للجوال',
        '1 Publish inventory to phone',
      );

  String get distributorsHubWorkflowLoad => _t(
        '٢ تحميل السيارة',
        '2 Load the truck',
      );

  String get distributorsHubWorkflowSell => _t(
        '٣ بيع من الهاتف',
        '3 Sell from phone',
      );

  String get distributorsHubWorkflowApprove => _t(
        '٤ اعتماد على الحاسوب',
        '4 Approve on desktop',
      );

  String get distributorsHubSectionOperations => _t(
        'العمليات اليومية',
        'Daily operations',
      );

  String get distributorsHubSectionOperationsSub => _t(
        'إدارة الطلبات، السيارات، والمزامنة مع الجوال',
        'Orders, vehicles, and mobile sync',
      );

  String get distributorsHubSectionReports => _t('التقارير', 'Reports');

  String get distributorsHubReportsDropdownHint =>
      _t('اختر تقريراً', 'Select a report');

  String get distributorsHubSectionReportsSub => _t(
        'معاينة وطباعة وتصدير PDF',
        'Preview, print, and PDF export',
      );

  String get distributorsHubStatDistributors => _t('موزّعون', 'Distributors');

  String get distributorsHubStatPending => _t(
        'طلبات بانتظار الاعتماد',
        'Pending approval',
      );

  String get distributorsHubStatMovements => _t(
        'حركات مسجّلة',
        'Recorded movements',
      );

  String get distributorsHubNotesTitle => _t('ملاحظات', 'Notes');

  String get distributorsHubNotesDesc => _t(
        'ملاحظات خاصة بمنظومة الموزعين — منفصلة عن مفكرة الصفحة الرئيسية',
        'Notes for the distributors hub only — separate from the home notepad',
      );

  String get distributorsHubNotesHint => _t(
        'ملاحظات التوزيع، الموزّعين، الطلبات الميدانية…',
        'Distribution notes, distributors, field orders…',
      );

  String get distributorsHubNotesSaved =>
      _t('تم حفظ ملاحظات الموزعين.', 'Distributor notes saved.');

  String get distributorsHubConnectionTitle =>
      _t('حالة الربط', 'Connection status');

  String get distributorsHubConnectionOk => _t(
        'الربط جاهز — الكتالوج منشور للجوال',
        'Link ready — catalog published to mobile',
      );

  String get distributorsHubConnectionWarning => _t(
        'تحقق من الإعدادات أو انشر الكتالوج للجوال',
        'Check settings or publish the catalog to mobile',
      );

  String get distributorsHubConnectionOffline => _t(
        'خادم المزامنة غير مفعّل',
        'Sync server is not enabled',
      );

  String distributorsHubLastPublish(String when, int products) => _t(
        'آخر نشر: $when — $products صنف',
        'Last publish: $when — $products products',
      );

  String get distributorsHubNeverPublished => _t(
        'لم يُنشر الكتالوج بعد',
        'Catalog not published yet',
      );

  String get distributorsHubTodayActivity =>
      _t('نشاط اليوم', 'Today\'s activity');

  String get distributorsHubTodayActivityEmpty => _t(
        'لا حركات مسجّلة اليوم',
        'No movements recorded today',
      );

  String get distributorsHubViewAllMovements =>
      _t('كل الحركات', 'All movements');

  String get fieldOrdersLoadTruckAction => _t(
        'تحميل إضافي',
        'Extra load',
      );

  String get distributorTruckLoadTotalValue =>
      _t('قيمة التحميل', 'Load value');

  String get distributorTruckLoadCopyLastLoad => _t(
        'نسخ آخر تحميل',
        'Copy last load',
      );

  String get distributorTruckLoadTemplates => _t(
        'قوالب التحميل',
        'Load templates',
      );

  String get distributorTruckLoadSaveTemplate => _t(
        'حفظ كقالب',
        'Save as template',
      );

  String get distributorTruckLoadTemplateName => _t(
        'اسم القالب',
        'Template name',
      );

  String get distributorTruckLoadTemplateSaved => _t(
        'تم حفظ القالب.',
        'Template saved.',
      );

  String get distributorTruckLoadTemplateApplied => _t(
        'تم تطبيق القالب.',
        'Template applied.',
      );

  String get distributorTruckLoadLastLoadApplied => _t(
        'تم نسخ آخر تحميل.',
        'Last load copied.',
      );

  String get distributorTruckLoadNoLastLoad => _t(
        'لا يوجد تحميل سابق لهذا الموزّع.',
        'No previous load for this distributor.',
      );

  String get distributorTruckLoadNoTemplates => _t(
        'لا توجد قوالب محفوظة.',
        'No saved templates.',
      );

  String distributorTruckLoadTemplateMeta(int lines, String qty) => _t(
        '$lines صنف · $qty',
        '$lines items · $qty',
      );

  String get fieldOrdersBatchMode => _t('تحديد متعدد', 'Multi-select');

  String get fieldOrdersSelectAll => _t('تحديد الكل', 'Select all');

  String get fieldOrdersClearSelection => _t('إلغاء التحديد', 'Clear selection');

  String fieldOrdersBatchApprove(int count) => _t(
        'اعتماد ($count)',
        'Approve ($count)',
      );

  String fieldOrdersBatchReject(int count) => _t(
        'رفض ($count)',
        'Reject ($count)',
      );

  String fieldOrdersBatchApproveDone(int ok, int failed) => _t(
        'تم اعتماد $ok — فشل $failed',
        'Approved $ok — failed $failed',
      );

  String fieldOrdersBatchRejectDone(int ok, int failed) => _t(
        'تم رفض $ok — فشل $failed',
        'Rejected $ok — failed $failed',
      );

  String get distributorsHubReportVarianceTitle => _t(
        'فروقات السيارات',
        'Truck variances',
      );

  String get distributorsHubReportVarianceDesc => _t(
        'مقارنة ما حُمّل وما بيع وما تبقى على السيارة',
        'Compare loaded, sold, and remaining on truck',
      );

  String get distributorReportColExpected => _t('المتوقع', 'Expected');

  String get distributorReportColVariance => _t('الفرق', 'Variance');

  String get distributorReportVariancesIssuesOnly =>
      _t('فروقات فقط', 'Issues only');

  String get distributorReportColCleared => _t('تفريغ', 'Cleared');

  String get distributorsHubLoadDesc => _t(
        'نقل أصناف من المستودع إلى سيارة الموزّع',
        'Move items from warehouse to distributor truck',
      );

  String get distributorsHubFieldOrdersDesc => _t(
        'اعتماد طلبات المبيعات الواردة من الميدان',
        'Approve sales orders from the field',
      );

  String get distributorsHubMovementsDesc => _t(
        'سجل تحميل وبيع وإرجاع بضاعة السيارة',
        'Truck load, sale, and return log',
      );

  String get distributorsHubPublishDesc => _t(
        'نشر المنتجات والعملاء لتطبيق الموزّع',
        'Publish products and customers to the distributor app',
      );

  String get distributorsHubFieldExpensesDesc => _t(
        'اعتماد مصروفات الموزّعين من الميدان',
        'Approve distributor field expenses',
      );

  String get distributorsHubReturnsEmptyTruckDesc => _t(
        'اختر أصنافاً محمّلة على السيارة وأعدها للمستودع',
        'Select loaded truck items and return them to warehouse',
      );

  String get distributorsHubReportMovementsTitle => _t(
        'تقرير حركات السيارات',
        'Truck movements report',
      );

  String get distributorsHubReportMovementsDesc => _t(
        'سجل تحميل وبيع وإرجاع بضاعة كل موزّع مع معاينة وطباعة',
        'Load, sale, and return log per distributor with preview and print',
      );

  String get distributorsHubReportSummaryTitle => _t(
        'ملخص أداء الموزّعين',
        'Distributor performance summary',
      );

  String get distributorsHubReportSummaryDesc => _t(
        'إجمالي التحميل والبيع والإرجاع لكل موزّع',
        'Total load, sale, and return per distributor',
      );

  String get distributorsHubReportTruckStockTitle => _t(
        'بضاعة على السيارات',
        'Stock on trucks',
      );

  String get distributorsHubReportTruckStockDesc => _t(
        'الأصناف الحالية على سيارة كل موزّع',
        'Current items on each distributor truck',
      );

  String get distributorsHubReportFieldExpensesTitle => _t(
        'مصروفات الميدان',
        'Field expenses',
      );

  String get distributorsHubReportFieldExpensesDesc => _t(
        'مصروفات الموزّعين المرسلة من الميدان',
        'Distributor expenses submitted from the field',
      );

  String get distributorsHubReportFieldReturnsTitle => _t(
        'مرتجعات الميدان',
        'Field returns',
      );

  String get distributorsHubReportFieldReturnsDesc => _t(
        'مرتجعات العملاء المرسلة من موزّعي الميدان',
        'Customer returns submitted by field distributors',
      );

  String get distributorReportPreviewPdf => _t('معاينة PDF', 'Preview PDF');

  String get distributorReportPrint => _t('طباعة', 'Print');

  String get distributorReportFilterDistributor =>
      _t('تصفية بالموزّع', 'Filter by distributor');

  String get distributorReportColDistributor => _t('الموزّع', 'Distributor');

  String get distributorReportColProduct => _t('الصنف', 'Product');

  String get distributorReportColType => _t('نوع الحركة', 'Movement type');

  String get distributorReportColQty => _t('الكمية', 'Quantity');

  String get distributorReportColDate => _t('التاريخ', 'Date');

  String get distributorReportColLoads => _t('تحميل', 'Loaded');

  String get distributorReportColSales => _t('بيع', 'Sold');

  String get distributorReportColReturns => _t('إرجاع', 'Returned');

  String get distributorReportColOnTruck => _t('على السيارة', 'On truck');

  String get distributorReportColMovements => _t('عدد الحركات', 'Movements');

  String get distributorReportColSalePrice => _t('سعر البيع', 'Sale price');

  String get distributorReportColUnit => _t('الوحدة', 'Unit');

  String get distributorReportColAmount => _t('المبلغ', 'Amount');

  String get distributorReportColStatus => _t('الحالة', 'Status');

  String get distributorReportColTitle => _t('العنوان', 'Title');

  String get distributorReportColPayment => _t('طريقة الدفع', 'Payment');

  String get distributorReportColNotes => _t('ملاحظات', 'Notes');

  String get distributorReportFilterStatus => _t('الحالة', 'Status');

  String get distributorReportStatusAll => _t('الكل', 'All');

  String get distributorReportStatusPending =>
      _t('بانتظار الاعتماد', 'Pending');

  String get distributorReportStatusApproved => _t('معتمد', 'Approved');

  String get distributorReportStatusRejected => _t('مرفوض', 'Rejected');

  String distributorReportExpensesTotal(String amount) => _t(
        'إجمالي المصروفات: $amount',
        'Total expenses: $amount',
      );

  String distributorReportReturnsTotal(String amount, int count) => _t(
        'إجمالي المرتجعات: $amount · $count فاتورة',
        'Total returns: $amount · $count invoices',
      );

  String get distributorReportFieldExpensesEmpty => _t(
        'لا مصروفات مطابقة للتصفية.',
        'No expenses match the filter.',
      );

  String get distributorReportFieldReturnsEmpty => _t(
        'لا مرتجعات مطابقة للتصفية.',
        'No returns match the filter.',
      );

  String get distributorReportFieldDataUnavailable => _t(
        'تعذّر تحميل البيانات — تحقق من إعدادات خادم التفعيل.',
        'Could not load data — check activation server settings.',
      );


  String get menuLoadDistributorTruck => _t(
        'تحميل سيارة موزّع',
        'Load distributor truck',
      );

  String get distributorTruckLoadTitle =>
      _t('تحميل سيارة الموزّع', 'Load distributor truck');

  String get distributorTruckLoadIntro => _t(
        'اختر الموزّع وأدخل الكميات لنقلها من المستودع إلى السيارة. سيتم خصمها من مخزون الفرع ونشرها للجوال.',
        'Pick a distributor and enter quantities to move from the warehouse to the truck. Branch stock is reduced and synced to mobile.',
      );

  String get distributorTruckLoadSearchHint => _t(
        'ابحث بالاسم أو الباركود لإضافة أصناف',
        'Search by name or barcode to add items',
      );

  String get distributorTruckLoadCategoryAll =>
      _t('كل التصنيفات', 'All categories');

  String get distributorTruckLoadTableEmpty => _t(
        'ابحث عن صنف أو اختر من المنتجات لإضافته إلى فاتورة التحميل',
        'Search or pick products to add to the load invoice',
      );

  String get distributorTruckLoadInvoiceTitle => _t(
        'فاتورة تحميل السيارة',
        'Truck load invoice',
      );

  String get distributorTruckLoadNewInvoice => _t(
        'فاتورة جديدة',
        'New invoice',
      );

  String get distributorTruckLoadShowProducts => _t(
        'عرض المنتجات',
        'Browse products',
      );

  String get distributorTruckLoadConfirmTitle => _t(
        'اعتماد تحميل السيارة',
        'Confirm truck load',
      );

  String get distributorTruckLoadProductsPanel => _t('المنتجات', 'Products');

  String get distributorTruckLoadSelectedPanel =>
      _t('المختارة للتحميل', 'Selected for load');

  String get distributorTruckLoadPreviewInvoice =>
      _t('معاينة فاتورة الموزّع', 'Preview distributor invoice');

  String get distributorTruckLoadPreviewPrintInvoice => _t(
        'معاينة فاتورة الموزّع وطباعتها',
        'Preview and print distributor invoice',
      );

  String get distributorTruckLoadPrintInvoice =>
      _t('طباعة فاتورة الموزّع', 'Print distributor invoice');

  String distributorTruckLoadConfirmBody(String distributor) => _t(
        'اعتماد فاتورة التحميل للموزّع «$distributor» ونشرها على الجوال؟',
        'Confirm the load invoice for «$distributor» and publish to mobile?',
      );

  String distributorTruckOnBoardSummary(int count, String qtyLabel) => _t(
        'على السيارة: $count صنف · $qtyLabel',
        'On truck: $count items · $qtyLabel',
      );

  String get distributorTruckLoadColStock => _t('المستودع', 'Warehouse');

  String get distributorTruckLoadColOnTruck => _t('السيارة', 'Truck');

  String get distributorTruckLoadPickDistributor =>
      _t('الموزّع', 'Distributor');

  String get distributorTruckLoadAddQty =>
      _t('كميات الإضافة للسيارة', 'Quantities to add to truck');

  String get distributorTruckLoadQtyLabel => _t('إضافة', 'Add');

  String get distributorTruckLoadSubmit =>
      _t('تحميل ونشر', 'Load and publish');

  String get distributorTruckLoadNoQty => _t(
        'أدخل كمية واحدة على الأقل.',
        'Enter at least one quantity.',
      );

  String get distributorTruckLoadOk => _t(
        'تم تحميل السيارة ونشرها للموزّع.',
        'Truck loaded and published to the distributor.',
      );

  String distributorTruckLoadInsufficient(String product) => _t(
        'مخزون غير كافٍ: $product',
        'Insufficient stock: $product',
      );

  String distributorTruckCurrentQty(double qty) => _t(
        'على السيارة: $qty',
        'On truck: $qty',
      );

  String get distributorTruckDeductFromWarehouse => _t(
        'خصم من المستودع',
        'Deduct from warehouse',
      );

  String get distributorTruckDeductFromWarehouseHint => _t(
        'عند التفعيل تُنقَل الكمية من مخزون الفرع. عند الإيقاف تُعيَّن على السيارة فقط.',
        'When on, quantity moves from branch stock. When off, it is assigned to the truck only.',
      );

  String get distributorTruckAssignQty =>
      _t('كميات التعيين على السيارة', 'Quantities to assign on truck');

  String get distributorTruckAssignSubmit =>
      _t('تعيين ونشر', 'Assign and publish');

  String get distributorTruckAssignOk => _t(
        'تم تعيين الكميات على السيارة ونشرها.',
        'Quantities assigned on the truck and published.',
      );

  String get distributorTruckOnBoardTitle =>
      _t('البضاعة الحالية على السيارة', 'Current truck inventory');

  String get distributorTruckOnBoardEmpty => _t(
        'لا توجد أصناف محمّلة على سيارة هذا الموزّع.',
        'No items loaded on this distributor\'s truck.',
      );

  String get distributorTruckAddQtyLabel =>
      _t('إضافة', 'Add');

  String get distributorTruckEmptyAction =>
      _t('تفريغ السيارة', 'Empty truck');

  String get distributorTruckEmptyTitle =>
      _t('تفريغ السيارة', 'Empty truck');

  String distributorTruckEmptyConfirm(String distributor) => _t(
        'تفريغ سيارة «$distributor»؟ اختر إرجاع البضاعة للمستودع أو التفريغ فقط.',
        'Empty truck for «$distributor»? Return stock to warehouse or clear only.',
      );

  String get distributorTruckEmptyReturnWarehouse =>
      _t('إرجاع للمستودع', 'Return to warehouse');

  String get distributorTruckEmptyClearOnly =>
      _t('تفريغ فقط', 'Clear only');

  String get distributorTruckEmptyReturnedOk => _t(
        'تم إرجاع بضاعة السيارة للمستودع.',
        'Truck stock returned to the warehouse.',
      );

  String get distributorTruckEmptyClearedOk => _t(
        'تم تفريغ السيارة.',
        'Truck emptied.',
      );

  String get distributorTruckAlreadyEmpty => _t(
        'السيارة فارغة بالفعل.',
        'Truck is already empty.',
      );

  String get distributorTruckUnloadItemsPanel => _t(
        'أصناف محمّلة على السيارة',
        'Items loaded on truck',
      );

  String get distributorTruckUnloadSelectAll =>
      _t('تحديد الكل', 'Select all');

  String get distributorTruckUnloadClearSelection =>
      _t('مسح التحديد', 'Clear selection');

  String get distributorTruckUnloadMax =>
      _t('الحد الأقصى', 'Maximum');

  String get distributorTruckUnloadNoQty => _t(
        'اختر كمية واحدة على الأقل للإرجاع.',
        'Select at least one quantity to return.',
      );

  String get distributorTruckUnloadSubmit =>
      _t('إرجاع للمستودع', 'Return to warehouse');

  String get distributorTruckUnloadConfirmTitle => _t(
        'تأكيد إرجاع من السيارة',
        'Confirm truck unload',
      );

  String distributorTruckUnloadConfirmBody(String distributor) => _t(
        'إرجاع الأصناف المحددة من سيارة «$distributor».',
        'Return selected items from truck «$distributor».',
      );

  String get distributorTruckUnloadReturnHint => _t(
        'عند التفعيل تُضاف الكميات إلى مخزون الفرع وتُخصم من سيارة الموزّع.',
        'When on, quantities are added to branch stock and deducted from the distributor truck.',
      );

  String get distributorTruckUnloadReturnedOk => _t(
        'تم إرجاع الأصناف للمستودع وخصمها من السيارة.',
        'Items returned to warehouse and deducted from truck.',
      );

  String distributorTruckUnloadInsufficient(String product) => _t(
        'الكمية تتجاوز الموجود على السيارة: $product',
        'Quantity exceeds truck stock: $product',
      );

  String get distributorTruckUnloadFailed => _t(
        'تعذّر إرجاع الأصناف من السيارة.',
        'Could not unload items from truck.',
      );


  String fieldReturnsLineCount(int count) => _t(
        '$count صنف',
        '$count items',
      );

  String get distributorTruckMovementsTitle =>
      _t('حركة السيارة', 'Truck movements');

  String get distributorTruckMovementsAll =>
      _t('كل الموزّعين', 'All distributors');

  String get distributorTruckMovementsEmpty => _t(
        'لا حركات مسجّلة.',
        'No movements recorded.',
      );

  String distributorTruckMovementsShowing(int shown, int total) => _t(
        'عرض $shown من $total حركة',
        'Showing $shown of $total movements',
      );

  String get distributorTruckMovementsLoadMore =>
      _t('تحميل المزيد', 'Load more');

  String get distributorTruckMovementsFilterType =>
      _t('نوع الحركة', 'Movement type');

  String get distributorTruckMovementsFilterPeriod => _t('الفترة', 'Period');

  String get distributorTruckMovementsPeriod7d => _t('٧ أيام', '7 days');

  String get distributorTruckMovementsPeriod30d => _t('٣٠ يوماً', '30 days');

  String get distributorTruckMovementsPeriod90d => _t('٩٠ يوماً', '90 days');

  String get distributorTruckMovementsPeriodAll => _t('الكل', 'All');

  String get distributorTruckMovementsSearchProduct =>
      _t('بحث بالصنف', 'Search product');

  String get distributorTruckMovementsAllTypes =>
      _t('كل الأنواع', 'All types');

  String get distributorTruckMovementsLargeDataHint => _t(
        'عند وجود آلاف الحركات، استخدم التصفية أعلاه أو تقرير «حركات السيارات» من صفحة الموزعون لتصدير السجل الكامل.',
        'With thousands of movements, use the filters above or the vehicle movements report on the Distributors page for a full export.',
      );

  String get distributorTruckMovementLoad =>
      _t('تحميل من المستودع', 'Load from warehouse');

  String get distributorTruckMovementAssign =>
      _t('تعيين بدون خصم', 'Assign (no deduct)');

  String get distributorTruckMovementSale =>
      _t('بيع معتمد', 'Approved sale');

  String get distributorTruckMovementReturn =>
      _t('إرجاع للمستودع', 'Return to warehouse');

  String get distributorTruckMovementClear =>
      _t('تفريغ', 'Clear');

  String get menuDistributorTruckMovements => _t(
        'حركة سيارات الموزّعين',
        'Distributor truck movements',
      );

  String distributorStockAvailable(double qty) => _t(
        'المخزون: $qty',
        'Stock: $qty',
      );






  String get distributorHubIntro => _t(
        'أنشئ طلبات العملاء؛ يراجعها المكتب على الحاسوب قبل تسجيل الفاتورة.',
        'Create customer orders; the office reviews them on desktop before invoicing.',
      );

  String get distributorNewOrder => _t('طلب جديد', 'New order');

  String get distributorNewSale => _t('بيع جديد', 'New sale');

  String get distributorMySales => _t('مبيعاتي', 'My sales');

  String get distributorComposeSaleTitle => _t('فاتورة بيع', 'Sales invoice');

  String get distributorSubmitSale => _t('إتمام البيع', 'Complete sale');

  String get distributorSaleSent => _t(
        'تم إرسال الفاتورة للمراجعة.',
        'Invoice sent for review.',
      );

  String get distributorPaymentMethod => _t('طريقة الدفع', 'Payment method');

  String get distributorPaidAmount => _t('المبلغ المدفوع', 'Amount paid');

  String get distributorDiscount => _t('خصم', 'Discount');

  String get distributorGrandTotal => _t('الإجمالي', 'Grand total');

  String get distributorRemainingDeferred => _t('المتبقي (آجل)', 'Balance (deferred)');

  String distributorHubWelcome(String name) => _t(
        'الموزّع: $name',
        'Distributor: $name',
      );

  String get distributorExitToMainApp => _t(
        'العودة للتطبيق الرئيسي',
        'Back to main app',
      );

  String get distributorEditSale => _t('تعديل', 'Edit');

  String get distributorEditSaleTitle => _t('تعديل البيع', 'Edit sale');

  String get distributorSaveSaleChanges => _t('حفظ التعديلات', 'Save changes');

  String get distributorDeleteSale => _t('حذف', 'Delete');

  String get distributorDeleteSaleTitle => _t('حذف البيع', 'Delete sale');

  String distributorDeleteSaleConfirm(String customer) => _t(
        'حذف بيع العميل «$customer»؟ لا يمكن التراجع.',
        'Delete sale for «$customer»? This cannot be undone.',
      );

  String get distributorSaleDeleted => _t('تم حذف البيع.', 'Sale deleted.');

  String get distributorSaleUpdated => _t('تم تحديث البيع.', 'Sale updated.');

  String get distributorResendSale => _t('إعادة الإرسال', 'Resend');

  String get distributorSaleResent => _t('تم إرسال البيع مجدداً.', 'Sale sent again.');

  String get distributorCannotEditSale => _t(
        'لا يمكن تعديل أو حذف بيع معتمد أو مرفوض.',
        'Approved or rejected sales cannot be edited or deleted.',
      );

  String get distributorPrintSale => _t('طباعة الفاتورة', 'Print invoice');

  String get distributorShareSale => _t('مشاركة الفاتورة', 'Share invoice');

  String get distributorApprovedSaleReceiptTitle =>
      _t('فاتورة بيع معتمدة', 'Approved sales invoice');

  String get distributorInventorySourceLabel =>
      _t('مصدر البيع', 'Sale source');

  String get distributorSellFromMain =>
      _t('من المستودع الرئيسي', 'From main warehouse');

  String get distributorSellFromTruck =>
      _t('من السيارة', 'From vehicle');

  String get distributorTruckStockEmpty => _t(
        'لا توجد بضاعة محمّلة على السيارة. اطلب من المدير تحميل السيارة.',
        'No stock loaded in the vehicle. Ask your manager to load the vehicle.',
      );

  String get distributorInsufficientTruckStock => _t(
        'الكمية تتجاوز مخزون السيارة.',
        'Quantity exceeds vehicle stock.',
      );

  String get distributorInsufficientMainStock => _t(
        'الكمية تتجاوز المخزون المتاح.',
        'Quantity exceeds available stock.',
      );

  String get distributorCatalogEmptyHint => _t(
        'انشر كتالوج الميدان من الحاسوب لعرض المخزون.',
        'Publish field catalog from desktop to show inventory.',
      );

  String get distributorMyOrders => _t('طلباتي', 'My orders');

  String get distributorComposeTitle => _t('طلب توزيع', 'Distribution order');

  String get distributorSelectCustomer => _t('العميل', 'Customer');

  String get distributorCustomerNameHint => _t('اسم العميل', 'Customer name');

  String get distributorCustomerPhoneHint => _t('هاتف (اختياري)', 'Phone (optional)');

  String get distributorNotesHint => _t('ملاحظة (اختياري)', 'Note (optional)');

  String get distributorAddLine => _t('إضافة صنف', 'Add item');

  String get distributorShowProducts => _t('عرض المنتجات', 'Browse products');

  String get distributorShowItems => _t('عرض الأصناف', 'Browse items');

  String get distributorSyncRefresh =>
      _t('تحديث ومزامنة', 'Update & sync');

  String distributorShowAllProducts(int count) => _t(
        'عرض كل الأصناف ($count)',
        'Show all items ($count)',
      );

  String get distributorOpenFullCatalog =>
      _t('فتح قائمة كاملة', 'Open full list');

  String get distributorAddCustomer =>
      _t('إضافة عميل جديد', 'Add new customer');

  String get distributorInvoiceNotes =>
      _t('ملاحظات الفاتورة', 'Invoice notes');

  String get distributorSelectCategory => _t('التصنيف', 'Category');

  String get distributorAllCategories => _t('كل التصنيفات', 'All categories');

  String get distributorNoCategory => _t('بدون تصنيف', 'Uncategorized');

  String get distributorCheckoutTitle => _t('إتمام الدفع', 'Checkout');

  String get distributorConfirmSale => _t('تأكيد البيع', 'Confirm sale');

  String get distributorReturns => _t('مرتجعات', 'Returns');

  String get distributorNewReturn =>
      _t('مرتجع مبيعات جديد', 'New sales return');

  String get distributorMyReturns =>
      _t('مرتجعات سابقة', 'Previous returns');

  String get distributorReturnFromCustomerHint => _t(
        'مرتجع من عميل لبيع معتمد',
        'Return from customer for an approved sale',
      );

  String get distributorReturnQtyExceedsSale => _t(
        'كمية المرتجع أكبر من كمية البيع.',
        'Return quantity exceeds sold quantity.',
      );

  String get distributorReturnLinesRequired => _t(
        'حدد كمية مرتجعة لصنف واحد على الأقل.',
        'Enter a return quantity for at least one item.',
      );

  String get distributorReturnOrderNotSynced => _t(
        'يجب أن يكون البيع معتمداً ومُزامناً مع المكتب أولاً.',
        'The sale must be approved and synced with the office first.',
      );

  String get distributorReturnSent => _t(
        'أُرسل المرتجع للمكتب — بانتظار الاعتماد.',
        'Return sent to office — awaiting approval.',
      );

  String get distributorReturnQtyLabel => _t('مرتجع', 'Return');

  String get distributorNoApprovedSalesForReturn => _t(
        'لا توجد مبيعات معتمدة يمكن إرجاعها.',
        'No approved sales available for return.',
      );

  String get distributorPickSaleForReturn =>
      _t('اختر البيع المراد إرجاعه', 'Pick sale to return');

  String get distributorNoReturnsYet => _t(
        'لا توجد مرتجعات مسجّلة بعد.',
        'No returns recorded yet.',
      );

  String get distributorSendReturnNow =>
      _t('إرسال للمكتب', 'Send to office');

  String get distributorReturnSoldQty => _t('مباع', 'Sold');

  String get distributorReturnComposeTitle =>
      _t('فاتورة مرتجع', 'Return invoice');

  String get distributorReturnStockHint => _t(
        'بعد اعتماد المكتب على الحاسوب تُسجَّل فاتورة المرتجع وتُعاد الكميات للمخزن أو سيارة الموزّع.',
        'After office approval on desktop, the return invoice is posted and quantities go back to warehouse or truck stock.',
      );

  String get distributorReturnTotal => _t('إجمالي المرتجع', 'Return total');

  String get distributorReturnRemaining =>
      _t('متبقٍ للإرجاع', 'Remaining');

  String get distributorReturnAlreadyReturned =>
      _t('مُرتجع سابقاً', 'Already returned');

  String get distributorReturnConfirmSend => _t(
        'إرسال المرتجع للمكتب',
        'Send return to office',
      );

  String get distributorExpenses => _t('مصروفات', 'Expenses');

  String get distributorNewExpense =>
      _t('مصروف جديد', 'New expense');

  String get distributorMyExpenses =>
      _t('مصروفاتي', 'My expenses');

  String get distributorExpenseTitleLabel => _t('البيان', 'Description');

  String get distributorExpenseAmountLabel => _t('المبلغ', 'Amount');

  String get distributorExpenseDateLabel => _t('تاريخ المصروف', 'Expense date');

  String get distributorExpenseTitleRequired =>
      _t('البيان مطلوب.', 'Description is required.');

  String get distributorExpenseAmountRequired =>
      _t('المبلغ غير صحيح.', 'Invalid amount.');

  String get distributorExpenseSavedLocal => _t(
        'حُفظ المصروف محلياً. اضغط «إرسال للمكتب» عند توفر الإنترنت.',
        'Expense saved locally. Tap «Send to office» when online.',
      );

  String get distributorSaveExpenseLocal =>
      _t('حفظ محلي', 'Save locally');

  String get distributorSendExpenseNow =>
      _t('إرسال للمكتب', 'Send to office');

  String get distributorExpenseSent => _t(
        'أُرسل المصروف للمكتب — بانتظار الاعتماد.',
        'Expense sent to office — awaiting approval.',
      );

  String get distributorNoExpensesYet => _t(
        'لا توجد مصروفات مسجّلة بعد.',
        'No expenses recorded yet.',
      );

  String get distributorDeleteExpenseTitle =>
      _t('حذف المصروف', 'Delete expense');

  String distributorDeleteExpenseConfirm(String title) => _t(
        'حذف مصروف «$title»؟',
        'Delete expense «$title»?',
      );

  String get distributorCannotEditExpense => _t(
        'لا يمكن تعديل أو حذف هذا المصروف.',
        'This expense cannot be edited or deleted.',
      );

  String get distributorExpenseDeleted =>
      _t('تم حذف المصروف.', 'Expense deleted.');

  String get distributorCartSection => _t('أصناف الفاتورة', 'Invoice items');

  String get distributorSendSaleNow => _t('إرسال للمكتب', 'Send to office');

  String get distributorSaleSavedLocally => _t(
        'حُفظ البيع محلياً. اضغط «إرسال للمكتب» عند توفر الإنترنت.',
        'Sale saved locally. Tap «Send to office» when online.',
      );

  String get distributorOfflineBanner => _t(
        'لا يوجد اتصال — يُحفظ البيع على الجهاز ويُرسل لاحقاً.',
        'No connection — sale is saved on device and sent later.',
      );

  String get distributorCatalogDone => _t('تم', 'Done');

  String distributorCatalogDoneWithCount(int n) => _t(
        'تم — أُضيف $n صنفاً',
        'Done — $n item(s) added',
      );

  String distributorProductsAddedThisSession(int n) => _t(
        'أُضيف $n صنفاً في هذه الجلسة',
        '$n item(s) added this session',
      );

  String get distributorSubmitOrder => _t('إرسال الطلب', 'Send order');

  String get distributorNoLines => _t('أضف صنفاً واحداً على الأقل.', 'Add at least one item.');

  String get distributorOrderSent => _t(
        'تم إرسال الطلب للمكتب.',
        'Order sent to the office.',
      );

  String distributorOrderSavedOffline(String err) => _t(
        'حُفظ محلياً؛ سيتم الإرسال عند عودة الاتصال ($err).',
        'Saved locally; will send when online ($err).',
      );

  String fieldOrdersSendError(String err) {
    final code = err.trim().toLowerCase();
    switch (code) {
      case 'not_found':
        return _t(
          'تعذّر الإرسال: خادم المزامنة لا يتضمن واجهة الميدان. '
          'حدّث ملفات drhsn/includes على الخادم (field_orders.php و field_returns.php و field_expenses.php).',
          'Send failed: the sync server does not expose field API routes yet. '
          'Deploy drhsn/includes (field_orders.php, field_returns.php, and field_expenses.php) on the server.',
        );
      case 'order_not_found':
        return _t(
          'البيع غير موجود على الخادم — أرسل البيع أولاً من «مبيعاتي» ثم أعد إرسال المرتجع.',
          'Sale not found on server — send the sale from My sales first, then resend the return.',
        );
      case 'order_not_approved':
        return _t(
          'البيع لم يُعتمد بعد على الحاسوب — انتظر الاعتماد ثم أعد إرسال المرتجع.',
          'Sale is not approved on desktop yet — wait for approval, then resend the return.',
        );
      case 'forbidden':
        return _t(
          'رفض الخادم الطلب — تحقق من بريد اشتراك المالك ومعرّف المؤسسة على الجهاز.',
          'Server rejected the request — check owner subscription e-mail and organization id on this device.',
        );
      case 'validation':
      case 'customer_required':
      case 'lines_required':
        return _t(
          'بيانات الإرسال غير مكتملة — راجع الفاتورة وحاول مجدداً.',
          'Send payload incomplete — review the invoice and try again.',
        );
      case 'server':
      case 'server_error':
        return _t(
          'خطأ من خادم المزامنة — حدّث ملفات drhsn/includes على الخادم أو تواصل مع الدعم.',
          'Sync server error — update drhsn/includes on the server or contact support.',
        );
      case 'offline':
        return fieldOrdersOffline;
      case 'distributor_cloud_required':
        return distributorCloudRequired;
      case 'distributor_trial_product_limit':
        return distributorTrialProductLimit(5);
      case 'distributor_trial_expense_limit':
        return distributorTrialExpenseLimit(3);
      case 'distributor_seats_limit':
        return distributorSeatsLimit;
      default:
        return _t(
          'تعذّر الإرسال ($err). تحقق من إعدادات خادم التفعيل وحاول مجدداً.',
          'Send failed ($err). Check activation server settings and try again.',
        );
    }
  }

  String get distributorSendButton => _t('إرسال', 'Send');

  String get fieldOrderStatusUnsent => _t('لم يُرسل', 'Not sent');

  String get fieldOrderStatusPending => _t('بانتظار الاعتماد', 'Awaiting approval');

  String get fieldOrderStatusApproved => _t('معتمد', 'Approved');

  String get fieldOrderStatusRejected => _t('مرفوض', 'Rejected');



  String distributorRejectReason(String reason) =>
      _t('سبب الرفض: $reason', 'Rejection reason: $reason');

  String get distributorPickProduct => _t('اختر صنفاً', 'Pick a product');

  String get distributorSearchProductHint => _t(
        'ابحث بالاسم أو الباركود…',
        'Search by name or barcode…',
      );

  String get distributorNoProductsMatchSearch => _t(
        'لا أصناف مطابقة للبحث.',
        'No products match your search.',
      );

  String get distributorRemoveLine => _t('حذف الصنف', 'Remove item');

  String get distributorIncreaseQty => _t('زيادة الكمية', 'Increase quantity');

  String get distributorDecreaseQty => _t('تقليل الكمية', 'Decrease quantity');

  String get distributorScanBarcode => _t('مسح باركود', 'Scan barcode');



  String get distributorCloudRequired => _t(
        'يتطلب اشتراك سحابة الموزّعين (\$50/سنة). '
        'فعّله من لوحة التفعيل أو تواصل مع الدعم.',
        'Distributor cloud subscription required (\$50/year). '
        'Enable it from the activation panel or contact support.',
      );

  String get distributorCloudRequiredShort => _t(
        'سحابة الموزّعين غير مفعّلة',
        'Distributor cloud not active',
      );

  String get distributorTrialBanner => _t(
        'وضع التجربة: يمكنك تحميل حتى 5 منتجات وإرسال 3 مصروفات ميدانية. '
        'فعّل اشتراك MizaPos أو سحابة الموزّعين لاستخدام المنظومة بالكامل.',
        'Trial mode: load up to 5 products and send 3 field expenses. '
        'Activate MizaPos or distributor cloud for full access.',
      );

  String distributorTrialProductLimit(int limit) => _t(
        'حد التجربة: $limit منتجات كحد أقصى للتحميل. فعّل الاشتراك لرفع الحد.',
        'Trial limit: $limit products max to load. Activate subscription to lift the limit.',
      );

  String distributorTrialExpenseLimit(int limit) => _t(
        'حد التجربة: $limit مصروفات ميدانية كحد أقصى. فعّل سحابة الموزّعين لرفع الحد.',
        'Trial limit: $limit field expenses max. Enable distributor cloud to lift the limit.',
      );

  String get distributorCloudSyncButton => _t(
        'مزامنة سحابة الموزّعين',
        'Sync distributor cloud',
      );

  String get distributorCloudSyncPendingBanner => _t(
        'سحابة الموزّعين غير متزامنة على هذا الجهاز. اضغط «مزامنة» مع اتصال الإنترنت — أو اعمل محلياً إلى أن تُحدَّث.',
        'Distributor cloud is not synced on this device. Tap «Sync» with internet — or work locally until updated.',
      );

  String get distributorCloudSyncOk => _t(
        'تمت مزامنة سحابة الموزّعين.',
        'Distributor cloud synced.',
      );

  String get distributorCloudSyncFailed => _t(
        'لم تُجلب سحابة الموزّعين. تحقق من الإنترنت وتفعيل لوحة الويب لنفس بريد المالك.',
        'Could not fetch distributor cloud. Check internet and web activation for the owner email.',
      );

  String get distributorSeatsLimit => _t(
        'بلغت الحد الأقصى لمقاعد موزّعي السحابة على هذا الحساب.',
        'Maximum cloud distributor seats reached for this account.',
      );

  String get distributorModeLocal => _t('موزّع محلي', 'Local distributor');

  String get distributorCloudOnlyForFieldHub => _t(
        'التوزيع الميداني والشاحنة للموزّعين السحابة فقط — اختر موزّعاً مفعّلاً بالسحابة.',
        'Field distribution and truck load are for cloud distributors only — pick a cloud-enabled distributor.',
      );

  String get distributorModeCloud => _t('موزّع سحابة', 'Cloud distributor');

  String get distributorModeLocalHint => _t(
        'ضمن اشتراك POS — بدون مزامنة ميدانية سحابية.',
        'Included in POS subscription — no field cloud sync.',
      );

  String get distributorModeCloudHint => _t(
        'يتطلب اشتراك سحابة الموزّعين ومقعداً متاحاً.',
        'Requires distributor cloud subscription and an available seat.',
      );

  String get distributorLocalHubBanner => _t(
        'موزّع محلي — العمل على هذا الجهاز دون مزامنة سحابة الميدان.',
        'Local distributor — work on this device without field cloud sync.',
      );

  String get distributorLocalHubIntro => _t(
        'يمكنك إصدار مبيعات ميدانية محلياً. للمزامنة مع الحاسوب والمركبات فعّل موزّع سحابة من المسؤول.',
        'You can issue field sales locally. Ask your admin to enable cloud distributor for sync with desktop and vehicles.',
      );

  String get fieldOrdersLocalOnlyHint => _t(
        'حُفظ محلياً — المزامنة السحابية متاحة لموزّعي السحابة فقط.',
        'Saved locally — cloud sync is for cloud distributors only.',
      );




  String get distributorSalesFilterStatus => _t('الحالة', 'Status');

  String get distributorSalesFilterAll => _t('كل المبيعات', 'All sales');

  String get distributorSalesPickDate => _t('تحديد التاريخ', 'Pick dates');

  String get distributorSalesClearDate => _t('مسح التاريخ', 'Clear dates');

  String distributorSalesDateRange(String from, String to) => _t(
        'من $from إلى $to',
        'From $from to $to',
      );

  String get distributorMySalesEmpty => _t(
        'لا توجد مبيعات مسجّلة.',
        'No sales recorded.',
      );

  String get distributorMySalesNoMatch => _t(
        'لا توجد مبيعات مطابقة للفلتر.',
        'No sales match the filter.',
      );

  String distributorMySalesCount(int count) => _t(
        '$count مبيعة',
        '$count sale(s)',
      );

  String get menuOwnerFeedback => _t(
        'رأي أو طلب تحسين للمطوّر',
        'Feedback & requests to developer',
      );

  String get ownerFeedbackDialogTitle => _t(
        'رسالة إلى مطوّر البرنامج',
        'Message to the developer',
      );

  String get ownerFeedbackDialogIntro => _t(
        'تُرسل الرسالة مباشرةً إلى مطوّر البرنامج عبر خادم SMTP المعرّف في الملف smtp_config.json بجانب التطبيق (نفس إعداد إرسال أكواد التفعيل).',
        'The message is sent directly to the developer using the SMTP server defined in smtp_config.json next to the app (same as activation e-mail).',
      );

  String ownerFeedbackRecipientLine(String email) =>
      _en ? 'To: $email' : 'إلى: $email';

  String get ownerFeedbackFullNameLabel => _t('الاسم الكامل', 'Full name');

  String get ownerFeedbackCountryLabel => _t('الدولة', 'Country');

  String get ownerFeedbackCountryHint => _t(
        'يمكنك كتابة اسم أي دولة (مثال: السويد، اليابان، الأرجنتين…).',
        'You can type any country name (e.g. Sweden, Japan, Argentina…).',
      );

  String get ownerFeedbackDialCodeLabel =>
      _t('رمز الدولة للواتساب', 'WhatsApp country code');

  String get ownerFeedbackWhatsAppLabel => _t('رقم الواتساب (بدون رمز الدولة)',
      'WhatsApp number (without country code)');

  String get ownerFeedbackWhatsAppHint =>
      _t('أرقام فقط، مثال: 599123456', 'Digits only, e.g. 599123456');

  String get ownerFeedbackContactEmailLabel => _t(
        'بريد للرد (اختياري)',
        'Reply e-mail (optional)',
      );

  String get ownerFeedbackSubjectLabel =>
      _t('موضوع الرسالة (اختياري)', 'Subject (optional)');

  String get ownerFeedbackSubjectHint =>
      _t('مثال: اقتراح تحسين لواجهة المبيعات', 'e.g. Sales screen improvement');

  String get ownerFeedbackMessageLabel => _t(
        'الرأي، التحسينات، أو التحديثات المطلوبة',
        'Feedback, improvements, or requested updates',
      );

  String get ownerFeedbackMessageRequired =>
      _t('يرجى كتابة نص الرسالة.', 'Please enter your message.');

  String get ownerFeedbackFullNameRequired =>
      _t('يرجى إدخال الاسم.', 'Please enter your name.');

  String get ownerFeedbackCountryRequired =>
      _t('يرجى إدخال الدولة.', 'Please enter your country.');

  String get ownerFeedbackWhatsAppRequired =>
      _t('يرجى إدخال رقم الواتساب.', 'Please enter your WhatsApp number.');

  String get ownerFeedbackWhatsAppTooShort =>
      _t('رقم الواتساب قصير جداً.', 'WhatsApp number is too short.');

  String get ownerFeedbackSendButton => _t('إرسال', 'Send');

  String get ownerFeedbackSmtpMissingSnack => _t(
        'تعذّر الإرسال تلقائياً ولم يتمكّن البرنامج من فتح واتساب. أعد المحاولة، أو راسل المطوّر يدوياً عبر واتساب: +970 599 488 939.',
        'Could not send automatically and could not open WhatsApp. Please retry, or message the developer manually on WhatsApp: +970 599 488 939.',
      );

  String get ownerFeedbackOpenedWhatsApp => _t(
        'تمّ فتح واتساب وملء الرسالة. اضغط «إرسال» داخل التطبيق لإكمال الإرسال إلى المطوّر.',
        'WhatsApp opened with your message ready. Press "Send" inside WhatsApp to complete delivery to the developer.',
      );

  String get ownerFeedbackThankYouTitle => _t(
        'شكراً لك',
        'Thank you',
      );

  String get ownerFeedbackThankYouBody => _t(
        'شكراً لمشاركة رأيك معنا. تم استلام رسالتك، وسيتم أخذها في عين الاعتبار عند إدخال التطويرات والتحسينات على البرنامج في الفترة القادمة.',
        'Thank you for sharing your feedback. Your message has been received and will be taken into account as we plan improvements and new features for the application.',
      );

  String get ownerFeedbackThankYouButton => _t('حسناً', 'OK');

  String ownerFeedbackSendFailed(String err) =>
      _en ? 'Send failed: $err' : 'فشل الإرسال: $err';

  String ownerFeedbackMailBodyPrefix(String storeLine, String userLine) => _en
      ? '---\n$storeLine\n$userLine\n---'
      : '---\n$storeLine\n$userLine\n---';

  // معاملة (بيع/شراء)
  String get txCustomer => _t('العميل', 'Customer');
  String get txSupplier => _t('المورد', 'Supplier');
  String get txSuppliersPlural => _t('الموردون', 'Suppliers');
  String get txQuickSaleBtn => _t('بيع سريع', 'Quick sale');
  String get txQuickPurchaseBtn => _t('شراء سريع', 'Quick purchase');
  String get txAddCustomer => _t('إضافة عميل', 'Add customer');
  String get txAddSupplier => _t('إضافة مورد', 'Add supplier');
  String get txDefaultPayNoteSale =>
      _t('تسديد دين عميل', 'Customer debt payment');
  String get txDefaultPayNotePurchase =>
      _t('سداد رصيد مورد', 'Supplier balance payment');

  String get txQty => _t('الكمية', 'Quantity');
  String get txSaleUnitInputLabel =>
      _t('وحدة إدخال الكمية', 'Quantity entry unit');
  String get txQtyFractionHintShort =>
      _t('الكمية يمكن أن تكون كسراً (مثال 0.5).',
          'Quantity can be a fraction (e.g. 0.5).');
  String get txPriceEditDisabled =>
      _t('تعديل السعر معطل من الإعدادات', 'Price editing disabled in settings');
  String get txInvalidQtyPrice =>
      _t('يرجى إدخال كمية وسعر صالحين.', 'Enter valid quantity and price.');
  String get txNoProductMatch =>
      _t('لا يوجد منتج مطابق للبحث.', 'No matching product.');
  String get txAllProductsTitle => _t('عرض جميع المنتجات', 'All products');
  String get txSearchProductHint => _t('ابحث عن منتج', 'Search products');
  String availableQty(double s) =>
      _en ? 'Avail: ${s.toStringAsFixed(2)}' : 'متوفر: ${s.toStringAsFixed(2)}';
  String availableQtyShort(double s) => _en
      ? 'Available ${s.toStringAsFixed(2)}'
      : 'متوفرة ${s.toStringAsFixed(2)}';
  String get txAddAtLeastOne =>
      _t('أضف صنفًا واحدًا على الأقل.', 'Add at least one line.');
  String get txCreditDisabled => _t(
      'البيع بالأجل معطل من الإعدادات — اختر البيع النقدي.',
      'Credit sales disabled — use walk-in.');
  String txStockShortage(String product, double avail) => _en
      ? 'Insufficient qty for «$product» (available ${avail.toStringAsFixed(2)}).'
      : 'الكمية غير متوفرة للمنتج «$product» (المتوفر ${avail.toStringAsFixed(2)}).';
  String txBelowCost(String product) => _en
      ? 'Selling below cost not allowed for «$product».'
      : 'البيع أقل من التكلفة غير مسموح للمنتج «$product».';
  String get txBelowCostDialogTitle => _t(
        'البيع دون التكلفة غير مسموح',
        'Selling below cost blocked',
      );
  String txBelowCostPriceDetail(String sale, String cost) => _en
      ? 'Sale price: $sale · Cost: $cost'
      : 'سعر البيع: $sale · التكلفة: $cost';
  String get txBelowCostDialogHint => _t(
        'يمكن السماح بذلك من الإعدادات ← المبيعات ← السماح بسعر بيع أقل من التكلفة.',
        'You can allow this in Settings → Sales → Allow sale price under cost.',
      );
  String newInvoiceOpened(String label) =>
      _en ? 'Opened new $label.' : 'تم فتح $label جديدة.';
  String get txSaleInvoice => _t('فاتورة مبيعات', 'Sale invoice');
  String get txPurchaseInvoice => _t('فاتورة مشتريات', 'Purchase invoice');
  String noneOfPartners(String plural) =>
      _en ? 'No $plural.' : 'لا يوجد $plural.';
  String get txPhone => _t('الهاتف', 'Phone');
  String get txAddress => _t('العنوان', 'Address');
  String partnerRequired(String single) =>
      _en ? '$single is required.' : '$single مطلوب.';
  String partnerAddedOk(String single) =>
      _en ? '$single added.' : 'تمت إضافة $single بنجاح.';
  String get txNoCustomersPay =>
      _t('لا يوجد عملاء لتسديد ديونهم.', 'No customers to settle.');
  String get txNoSuppliersPay =>
      _t('لا يوجد موردون لتسديد ذممهم.', 'No suppliers to pay.');
  String get txSettleCustomer => _t('تسديد ديون عميل', 'Customer payment');
  String get txSettleSupplier => _t('سداد ذمة مورد', 'Supplier payment');
  String get txAmount => _t('المبلغ', 'Amount');
  String get paymentVoucherFieldOptional => _t(
        'رقم السند (اختياري)',
        'Voucher # (optional)',
      );
  String get txDescription => _t('الوصف', 'Description');
  String get txSettleAction => _t('تسديد', 'Settle');
  String get txSupplierSettleSubmit => _t('سداد', 'Pay');
  String get txSettleSearchHint =>
      _t('بحث بالاسم أو جزء منه…', 'Search by name…');
  String get txSettlePickPartner =>
      _t('اختر العميل أو المورد', 'Select customer or supplier');
  String get txSettleCurrentBalance =>
      _t('رصيد الذمة الحالي', 'Outstanding balance');
  String get txLineCategoryAndUnit =>
      _t('تصنيف · وحدة', 'Category · unit');
  String get txLinePriceCostQty =>
      _t('سعر · تكلفة · كمية', 'Price · cost · qty');
  String get txLinePriceQty => _t('سعر · كمية', 'Price · qty');
  String get txInvalidAmount => _t('يرجى إدخال مبلغ صحيح أكبر من صفر.',
      'Enter an amount greater than zero.');
  String paymentRecorded(String amt) =>
      _en ? 'Payment recorded: $amt' : 'تم تسجيل تسديد بقيمة $amt';
  String get txNoPastSales =>
      _t('لا توجد فواتير مبيعات سابقة.', 'No previous sale invoices.');
  String get txNoPastPurchases =>
      _t('لا توجد فواتير مشتريات سابقة.', 'No previous purchase invoices.');
  String get txEditSaleInv =>
      _t('تعديل/حذف فاتورة مبيعات', 'Edit/delete sale invoice');
  String get txEditPurchaseInv =>
      _t('تعديل/حذف فاتورة مشتريات', 'Edit/delete purchase invoice');
  String get walkInCustomer => _t('عميل نقدي', 'Walk-in customer');
  String get walkInSupplier => _t('مورد نقدي', 'Walk-in supplier');
  String get txLeaveInvoiceTitle => _t('مغادرة الفاتورة', 'Leave invoice');
  String get txLeaveInvoiceBody => _t(
        'توجد أصناف في الفاتورة. اختر حفظها أو الخروج دون حفظ.',
        'This invoice has lines. Save, or exit without saving.',
      );
  String get txLeaveDiscard => _t('خروج دون حفظ', 'Exit without saving');
  String get txLeaveSave => _t('حفظ الفاتورة', 'Save invoice');
  String get txPartnerSearchHint => _t('ابحث بالاسم…', 'Search by name…');
  String get txInvoiceNotesLabel => _t('ملاحظات الفاتورة', 'Invoice notes');
  String get txInvoiceLinesTitle =>
      _t('أصناف الفاتورة', 'Invoice line items');
  String get txHideProductBrowsePanel =>
      _t('إخفاء المنتجات', 'Hide products panel');
  String get txShowProductBrowsePanel =>
      _t('عرض المنتجات', 'Show products');

  String get txProductBrowseGridView => _t(
        'عرض شبكة الصور',
        'Image grid view',
      );

  String get txProductBrowseListView => _t(
        'عرض قائمة',
        'List view',
      );

  String get txProductBrowseImagesAction => _t(
        'صور المنتجات',
        'Product images',
      );

  String get txAmountInWordsLabel => _t('المبلغ كتابة', 'Amount in words');
  String get txInvoiceFooterSummaryTitle =>
      _t('ملخص الفاتورة', 'Invoice summary');
  String get txInvoiceFooterItemsTotalLabel =>
      _t('مجموع الأصناف', 'Items count');
  String get txInvoiceDiscountFieldLabel => _t('خصم', 'Discount');
  String get txInvoicePaidFieldLabel => _t('المبلغ المدفوع', 'Paid amount');
  String get txInvoiceRemainingFieldLabel => _t('متبقي', 'Remaining');
  String get txInvoiceChangeToCustomerLabel =>
      _t('باقي للعميل', 'Change to customer');
  String get txInvoiceCreditToCustomerBalanceLabel =>
      _t('يُضاف لرصيد العميل', 'Added to customer balance');
  String get txCreditOverpayToCustomerCheckbox => _t(
        'تسجيل الباقي كرصيد للعميل',
        'Keep overpay on customer account',
      );
  String get txCreditOverpayNeedsCustomer => _t(
        'اختر عميلاً مسجّلاً لتسجيل الباقي كرصيد على حسابه.',
        'Select a registered customer to credit the overpay.',
      );
  String get txInvoiceTableLinesSubtotal =>
      _t('مجموع البنود', 'Lines subtotal');
  String get txInvoiceTableGrandLabel => _t('الإجمالي', 'Grand total');
  String txInvoiceFooterDiscountLine(String amt) => _t(
        'بعد خصم $amt',
        'After discount $amt',
      );
  String get txRecentSalesTitle =>
      _t('أحدث فواتير البيع', 'Recent sale invoices');
  String get txRecentSalesEmpty => _t(
        'لا توجد فواتير محفوظة بعد.',
        'No saved invoices yet.',
      );
  String get txRecentSalesRefreshTooltip => _t('تحديث القائمة', 'Refresh list');
  String get txRecentSalesRibbonHide =>
      _t('إخفاء أحدث الفواتير', 'Hide recent invoices');
  String get txRecentSalesRibbonShow =>
      _t('إظهار أحدث الفواتير', 'Show recent invoices');
  String get txFavoriteProductsTitle =>
      _t('المنتجات المفضلة', 'Favorite products');
  String get txFavoriteProductAddTooltip =>
      _t('إضافة للفاتورة', 'Add to invoice');
  String get txFavoriteProductToggleTooltip => _t(
        'إضافة أو إزالة من المفضلة',
        'Add or remove from favorites',
      );
  String get invProductAddFavoriteMenu =>
      _t('إضافة للمفضلة', 'Add to favorites');
  String get invProductRemoveFavoriteMenu =>
      _t('إزالة من المفضلة', 'Remove from favorites');
  String get txSaleInvoiceArchive =>
      _t('أرشيف فواتير البيع', 'Sale invoices archive');
  String get txSaleInvoiceArchiveTooltip =>
      _t('أرشيف فواتير البيع والبحث', 'Sale invoices archive & search');
  String get txSaleInvoiceArchiveTitle =>
      _t('أرشيف فواتير البيع', 'Sale invoices archive');
  String get txSaleInvoiceArchiveSearchHint => _t(
        'بحث برقم الفاتورة أو العميل أو المبلغ…',
        'Search by invoice id, customer, or amount…',
      );
  String get txSaleInvoiceArchiveEmpty => _t(
        'لا توجد نتائج.',
        'No matching invoices.',
      );
  String get txRecentPurchasesTitle =>
      _t('أحدث فواتير الشراء', 'Recent purchase invoices');
  String get txRecentPurchasesEmpty => _t(
        'لا توجد فواتير مشتريات محفوظة بعد.',
        'No saved purchase invoices yet.',
      );
  String get txRecentPurchasesRibbonHide =>
      _t('إخفاء أحدث فواتير الشراء', 'Hide recent purchase invoices');
  String get txRecentPurchasesRibbonShow =>
      _t('إظهار أحدث فواتير الشراء', 'Show recent purchase invoices');
  String get txPurchaseInvoiceArchive =>
      _t('أرشيف فواتير الشراء', 'Purchase invoices archive');
  String get txPurchaseInvoiceArchiveTooltip =>
      _t('أرشيف فواتير الشراء والبحث', 'Purchase invoices archive & search');
  String get txPurchaseInvoiceArchiveTitle =>
      _t('أرشيف فواتير الشراء', 'Purchase invoices archive');
  String get txPurchaseInvoiceArchiveSearchHint => _t(
        'بحث برقم الفاتورة أو المورد أو المبلغ…',
        'Search by invoice id, supplier, or amount…',
      );
  String get txPurchaseInvoiceArchiveEmpty => _t(
        'لا توجد نتائج.',
        'No matching invoices.',
      );
  String get txRecentPurchaseSheetTitle =>
      _t('فاتورة شراء محفوظة', 'Saved purchase invoice');
  String get txRecentPurchasePrintUnavailable => _t(
        'طباعة فاتورة الشراء غير مفعّلة من هذه الشاشة. استخدم الرئيسية بعد الحفظ.',
        'Purchase printing is not wired here. Save from home to print.',
      );
  String get txInvoicePaymentCash => _t('نقدي', 'Cash');
  String get txInvoicePaymentDeferred => _t('آجل', 'Credit');
  String get txPaymentBank => _t('بنك', 'Bank');
  String get txPaymentWallet => _t('محفظة', 'Wallet');
  String get txPaymentCheck => _t('شيك', 'Check');
  String get txPaymentSplit => _t('دفع متعدد', 'Split payment');

  /// تسمية طريقة دفع فاتورة أو مصروف (رموز [MizaPaymentTypes]).
  String invoicePaymentMethodLabel(String? raw) {
    switch (MizaPaymentTypes.normalize(raw)) {
      case MizaPaymentTypes.bank:
        return txPaymentBank;
      case MizaPaymentTypes.wallet:
        return txPaymentWallet;
      case MizaPaymentTypes.check:
        return txPaymentCheck;
      case MizaPaymentTypes.deferred:
        return txInvoicePaymentDeferred;
      case MizaPaymentTypes.split:
        return txPaymentSplit;
      case MizaPaymentTypes.cash:
        return txInvoicePaymentCash;
      default:
        return txInvoicePaymentCash;
    }
  }

  String get txSplitPaymentToggle =>
      _t('دفع متعدد (نقدي + محفظة + …)', 'Split payment (cash + wallet + …)');
  String get txSplitPaymentAddRow => _t('إضافة طريقة دفع', 'Add payment method');
  String get txSplitPaymentRemoveRow => _t('حذف', 'Remove');
  String get txSplitPaymentAllocated =>
      _t('مجموع الدفعات', 'Total allocated');
  String get txSplitPaymentAmountField => _t('المبلغ', 'Amount');
  String get txSplitPaymentOverTotal => _t(
        'مجموع الدفعات يتجاوز إجمالي الفاتورة.',
        'Payment splits exceed the invoice total.',
      );
  String get txSplitPaymentNeedsPartner => _t(
        'اختر عميلاً أو مورداً للمتبقي أو الدفع الآجل.',
        'Pick a customer or supplier for the remaining balance or credit.',
      );
  String get txSplitPaymentEmpty => _t(
        'أدخل مبلغاً في طريقة دفع واحدة على الأقل.',
        'Enter an amount in at least one payment method.',
      );

  String get txInvoicePaymentMethodField =>
      _t('طريقة الدفع', 'Payment method');
  String get txInvoiceSaveDeferredNoPartner => _t(
        'اختر عميلاً أو مورداً للبيع أو الشراء الآجل.',
        'Pick a customer or supplier for a deferred invoice.',
      );

  String get txRecentSaleSheetTitle => _t('فاتورة محفوظة', 'Saved invoice');
  String get txRecentSaleOpenEditor => _t('فتح للتعديل', 'Open to edit');
  String get txRecentSaleActionsSection => _t('إجراءات سريعة', 'Quick actions');
  String get txRecentSalePrint => _t('طباعة', 'Print');
  String get txRecentSalePrintUnavailable => _t(
        'طباعة الفاتورة غير مفعّلة من شاشة البيع. استخدم الرئيسية بعد الحفظ.',
        'Printing from this screen is not wired. Save from home flow to print.',
      );
  String get txRecentInvoicePreviewFailed => _t(
        'تعذر تحميل معاينة الفاتورة.',
        'Could not load invoice preview.',
      );
  String get txRecentSaleReturn => _t('مرتجع', 'Return');
  String get txRecentSaleVoid => _t('إلغاء الفاتورة', 'Void invoice');
  String get txRecentSaleHardDelete => _t('حذف نهائي', 'Delete permanently');
  String get txHardDeleteInvoiceTitle =>
      _t('تأكيد الحذف النهائي', 'Confirm permanent delete');
  String get txHardDeleteInvoiceBody => _t(
        'سيتم حذف سجل الفاتورة نهائياً من النظام (مع إمكانية التراجع من التنبيه). المتابعة؟',
        'The invoice will be permanently removed (you may undo from the snackbar). Continue?',
      );
  String invoiceShortTitle(String id8) => _en ? 'Invoice $id8' : 'فاتورة $id8';
  String get txDeleteInvoiceTooltip => _t('حذف الفاتورة', 'Delete invoice');
  String get txConfirmDeleteTitle => _t('تأكيد الحذف', 'Confirm delete');
  String get txConfirmDeleteBody => _t(
        'سيتم حذف الفاتورة وعكس أثرها على المخزون والصندوق. هل تريد المتابعة؟',
        'The invoice will be removed and stock/cash reversed. Continue?',
      );
  String get txUndo => _t('تراجع', 'Undo');
  String get saleDeletedOk =>
      _t('تم حذف فاتورة المبيعات بنجاح.', 'Sale invoice deleted.');
  String get purchaseDeletedOk =>
      _t('تم حذف فاتورة المشتريات بنجاح.', 'Purchase invoice deleted.');
  String get invoiceRestoredOk =>
      _t('تم استرجاع الفاتورة المحذوفة.', 'Invoice restored.');
  String get txLoadedForEdit => _t(
        'تم تحميل الفاتورة للتعديل. سيتم تحديثها عند الحفظ.',
        'Invoice loaded for editing. Save to update.',
      );
  String get txConfirmPrint => _t('تأكيد طباعة', 'Confirm / print');
  String get txSaveInvoiceDialogTitle =>
      _t('تأكيد حفظ الفاتورة', 'Confirm save invoice');
  String get txPriceQuoteMode => _t('عرض سعر', 'Price quote');
  String get txPriceListLabel => _t('قائمة الأسعار', 'Price list');
  String get txPriceListBaseOption => _t('السعر الأساسي', 'Base price');
  String get txPriceQuoteSave => _t('حفظ عرض السعر', 'Save price quote');
  String get txPriceQuoteSaveConfirmTitle =>
      _t('حفظ عرض السعر؟', 'Save price quote?');
  String get txPriceQuoteSaveConfirmBody => _t(
        'لن يُخصم مخزون ولا يُسجَّل صندوق — للعرض على العميل فقط.',
        'No stock or cash movement — for customer reference only.',
      );
  String txPriceQuoteSavedTitle(String invoiceNo) => _t(
        'تم حفظ عرض السعر رقم $invoiceNo',
        'Price quote $invoiceNo saved',
      );
  String get txPriceQuoteConvertToSale =>
      _t('إصدار فاتورة بيع', 'Issue sales invoice');
  String get txRecentPriceQuotesRibbonShow =>
      _t('إظهار عروض الأسعار', 'Show price quotes');
  String get txRecentPriceQuotesRibbonHide =>
      _t('إخفاء عروض الأسعار', 'Hide price quotes');
  String get txSaveInvoiceBack => _t('عودة', 'Back');
  String get txSaveInvoiceContinue => _t('متابعة', 'Continue');
  String get txSaveInvoiceSelectedPartner =>
      _t('العميل / المورد', 'Customer / supplier');
  String txInvoiceSavedTitle(String invoiceNo) => _t(
        'تم حفظ الفاتورة رقم $invoiceNo',
        'Invoice $invoiceNo saved',
      );
  String get txInvoiceSavedPrint => _t('طباعة', 'Print');
  String get txInvoiceSavedSendWhatsApp =>
      _t('إرسال واتساب', 'Send via WhatsApp');
  String get txInvoiceSavedFinish => _t('إنهاء', 'Finish');
  String txInvoiceShareWhatsAppMessage(String invoiceNo, String total) => _t(
        'فاتورة رقم $invoiceNo — الإجمالي: $total',
        'Invoice $invoiceNo — total: $total',
      );
  String get txEditInvoice => _t('تعديل فاتورة', 'Edit invoice');
  String get cashierShortcutsLine => _t(
        'اختصارات الكاشير: F3 بحث/باركود • F4 تأكيد وطباعة • F5 فاتورة جديدة • F8 تسديد • Ctrl+N جديد • Ctrl+Enter حفظ',
        'Cashier: F3 search/barcode • F4 confirm/print • F5 new • F8 settle • Ctrl+N new • Ctrl+Enter save',
      );
  String invoiceDateEditable(String d) =>
      _en ? 'Invoice date $d' : 'تاريخ الفاتورة $d';
  String invoiceDateTodayFixed(String d) =>
      _en ? 'Today $d (fixed)' : 'تاريخ اليوم $d (ثابت)';
  String get txSearchProductField => _t('ابحث عن منتج', 'Search product');
  String get txSearchProductBarcodeHint => _t(
      'اسم المنتج أو الباركود — امسح ثم Enter',
      'Name or barcode — scan then Enter');
  String get txBarcodeScanFieldHint => _t(
        'امسح الباركود أو أدخل الرقم ثم Enter',
        'Scan barcode or type code, then Enter',
      );
  String editModeChip(String id8) =>
      _en ? 'Editing: $id8' : 'وضع التعديل: $id8';
  String get colProduct => _t('المنتج', 'Product');
  String get colUnit => _t('الوحدة', 'Unit');
  String get colPrice => _t('السعر', 'Price');
  String get txPurchaseUnitPrice => _t('سعر الشراء', 'Purchase price');
  String get colCost => _t('التكلفة', 'Cost');
  String get colLineTax => _t('ضريبة السطر', 'Line tax');
  String get colTotal => _t('الإجمالي', 'Total');
  String get colPiecesCount => _t('عدد القطع', 'Pieces');
  String get colLineCount => _t('عدد المنتجات', 'Lines');
  String totalWithTaxLabel(String formatted) =>
      _en ? 'Total + tax: $formatted' : 'الإجمالي + الضريبة: $formatted';
  String get saveInvoice => _t('حفظ الفاتورة', 'Save invoice');
  String get addProductTitlePrefix => _t('إضافة', 'Add');

  // مخزون
  String get invNoAddPerm =>
      _t('ليس لديك صلاحية إضافة منتجات.', 'No permission to add products.');
  String catalogTrialLimitVoucherBody(int limit) => _en
      ? 'You can add up to $limit products without an active voucher. Activate a subscription voucher to add more.'
      : 'يمكنك إضافة $limit صنفاً كحد أقصى بدون قسيمة سارية. فعّل قسيمة الاشتراك لإضافة المزيد.';
  String catalogTrialRemainingHint(int current, int limit) => _en
      ? 'Trial catalog: $current / $limit products — voucher required for more'
      : 'تجربة المخزون: $current / $limit صنفاً — القسيمة مطلوبة للمزيد';
  String transactionTrialProductLimitBody(int limit) => _en
      ? 'You can add up to $limit different products per invoice without activation. Activate the program for unlimited products.'
      : 'يمكنك اختيار $limit منتجات مختلفة كحد أقصى في الفاتورة بدون تفعيل. فعّل البرنامج لعدد غير محدود.';
  String get invWarehouseReportTitle =>
      _t('تقرير المخزون', 'Inventory report');
  String get inventoryToolbarHintShort => _t(
        'الشريط العلوي: تقارير المخزون (يُحدَّد التاريخ عند التقارير التي تحتاج فترة) وإجراءات المخزون. الجدول في الأسفل.',
        'Top bar: inventory reports (dates when a report needs a period) and inventory actions. The product table is below.',
      );
  String get inventoryToolbarHintDetail => _t(
        'الشريط العلوي: إظهار الباركود، المجمدة، إضافة منتج، إدارة المنتجات، التقارير، وعرض المنتجات. التقارير التي تحتاج فترة (حركة منتج، أصناف تالفة) تطلب التاريخ عند الاختيار.',
        'Top bar: show barcode, frozen items, add product, product management, reports, and browse. Period-based reports (product movement, damaged items) ask for dates when selected.',
      );
  String get invToolbarProductManagement =>
      _t('إدارة المنتجات', 'Product management');
  String get invToolbarReports => _t('تقارير', 'Reports');
  String get invShowBarcodeToolbar => _t('إظهار الباركود', 'Show barcode');
  String get invShowImagesToolbar => _t('عرض الصور', 'Show images');
  String get invBrowseColCategory => _t('الصنف', 'Category');
  String get invBrowseColUnit => _t('الوحدة', 'Unit');
  String get invBrowseColCost => _t('التكلفة', 'Cost');
  String get invDamagedDisposeMenu => _t('اتلاف منتجات', 'Write off stock');
  String get inventoryToolbarHintDialogTitle =>
      _t('شرح شاشة إدارة المخزون', 'Inventory management screen');
  String get inventoryQueryReportsSectionTitle => _t(
        'تقارير المخزون',
        'Inventory query reports',
      );
  String get inventoryQueryReportsPeriodCaption => _t(
        'يُحدَّد التاريخ عند اختيار التقرير',
        'Dates are set when you pick a report',
      );
  String get invPartnerTransferChip => _t('تحويل ذمة', 'Partner transfer');
  String get invImportExcelChip => _t('استيراد Excel', 'Excel import');
  String get invEditPricesChip => _t('تعديل الأسعار', 'Edit prices');
  String get invAddProductTitle => _t('إضافة منتج جديد', 'Add product');
  String get invBarcodeField => _t('الباركود', 'Barcode');
  String get invBarcodeHint =>
      _t('اختياري — امسح أو اكتب', 'Optional — scan or type');
  String get invValidationNameRequired =>
      _t('أدخل اسم المنتج.', 'Enter a product name.');
  String get invValidationNumberNonNegative =>
      _t('أدخل رقماً صحيحاً غير سالب.', 'Enter a valid non-negative number.');
  String get invQtyDisabledService => _t('الخدمات لا تحتفظ بكمية في المستودع.',
      'Services have no stock quantity.');
  String get invSwitchService => _t('صنف خدمة', 'Service item');
  String get invSwitchServiceSub => _t(
      'بدون كمية في المستودع؛ لا يُخصم عند البيع',
      'No stock; not deducted from warehouse on sale');
  String get invSwitchHidden =>
      _t('إخفاء من اختيار المنتجات', 'Hidden from picker');
  String get invSwitchHiddenSub => _t(
      'لا يظهر في البحث السريع حتى تُلغِ الإخفاء من المستودع',
      'Hidden from quick search until you unhide in warehouse');
  String get invPurchasePriceLabel =>
      _t('سعر الشراء / التكلفة', 'Purchase / cost price');
  String get invPurchasePriceHelper => _t(
      'يُحفظ كسعر التكلفة وسعر البيع الابتدائي',
      'Saved as cost and initial sale price');
  String get invProductName => _t('اسم المنتج', 'Product name');
  String get invSalePrice => _t('سعر البيع', 'Sale price');
  String get invCostPrice => _t('سعر التكلفة', 'Cost price');
  String get invOpeningQty => _t('الكمية', 'Quantity');
  String get invProductExpiryDate =>
      _t('تاريخ انتهاء الصلاحية', 'Expiry date');
  String get invProductExpiryNone => _t('لم يُحدد', 'Not set');
  String get invProductExpiryPick => _t('اختيار التاريخ', 'Choose date');
  String get invProductExpiryClear => _t('مسح التاريخ', 'Clear date');
  String get invProductAdded => _t('تمت إضافة المنتج.', 'Product added.');
  String get invBrowseTitle => _t('عرض المنتجات', 'Products');
  String get invWarehouseProductsPageTitle => _t(
        'المنتجات المتوفرة في المخزون',
        'Products in stock',
      );
  String get invWarehouseProductsPageSubtitle => _t(
        'جرد الأصناف — السعر والكمية والبحث بالباركود',
        'Stock list — price, quantity & barcode search',
      );
  String get invWarehouseMoreReportsHint => _t(
        'من قائمة إدارة المخزون الرئيسية: أصناف تالفة، ترتيب العرض، استيراد Excel، سلة المحذوفات…',
        'From the main inventory menu: damaged stock, order, Excel import, trash…',
      );
  String get invReportsMenu => _t('تقارير المخزون', 'Inventory reports');
  String get invReportFullWarehouse =>
      _t('تقرير المخزون الشامل', 'Full inventory report');
  String get invManageCategoriesFromHere =>
      _t('إدارة التصنيفات', 'Manage categories');
  String get invTableActionColumn => _t('إجراءات', 'Actions');
  String get invBarcodePrint =>
      _t('طباعة لصيقة الباركود', 'Print barcode label');
  String get invBarcodeLabelPaperSection =>
      _t('نوع الورق', 'Paper type');
  String get invBarcodeLabelPaperThermal =>
      _t('حراري', 'Thermal');
  String get invBarcodeLabelPaperA4 => _t('A4', 'A4');
  String get invBarcodeLabelA4LayoutSection =>
      _t('تخطيط الصفحة', 'Page layout');
  String get invBarcodeLabelA4Columns => _t('أعمدة', 'Columns');
  String get invBarcodeLabelA4Rows => _t('صفوف', 'Rows');
  String invBarcodeLabelA4PerPage(int count) => _en
      ? '$count label${count == 1 ? '' : 's'} per page'
      : '$count ملصق في الصفحة';
  String get invBarcodeLabelCopiesSection =>
      _t('عدد النسخ', 'Number of copies');
  String get invBarcodeLabelCopiesLabel =>
      _t('النسخ', 'Copies');
  String get invBarcodeLabelCopiesIncrease =>
      _t('زيادة', 'Increase');
  String get invBarcodeLabelCopiesDecrease =>
      _t('تقليل', 'Decrease');
  String get invBarcodeLabelCopiesInvalid => _t(
        'أدخل عدداً بين 1 و 999.',
        'Enter a number between 1 and 999.',
      );
  String get invBarcodeLabelDisplaySection =>
      _t('محتوى الملصق', 'Label content');
  String get invBarcodeLabelShowStoreName =>
      _t('اسم المتجر', 'Store name');
  String get invBarcodeLabelStoreNameMissing => _t(
        'لم يُعرَّف اسم المتجر في الإعدادات.',
        'Store name is not set in settings.',
      );
  String get invBarcodeLabelShowProductName =>
      _t('اسم المنتج', 'Product name');
  String get invBarcodeLabelShowPrice =>
      _t('سعر البيع', 'Sale price');
  String get invBarcodeLabelShowBarcodeText =>
      _t('رقم الباركود تحت الرمز', 'Barcode number under symbol');
  String get invBarcodeLabelPrintAction =>
      _t('معاينة وطباعة', 'Preview & print');
  String get invBarcodeGeneratePrint =>
      _t('إنشاء باركود وطباعته', 'Generate barcode & print');
  String get invBarcodeGenerateConfirmTitle =>
      _t('إنشاء باركود؟', 'Generate barcode?');
  String invBarcodeGenerateConfirmBody(String name) => _en
      ? 'Assign a new barcode to «$name» and print the label?'
      : 'تعيين باركود جديد لـ«$name» وطباعة اللصيقة؟';
  String get invBarcodePrintedOk =>
      _t('تم إرسال اللصيقة للطباعة.', 'Label sent to printer.');
  String get invBarcodeFoundByScan =>
      _t('تم التعرف على المنتج بالباركود.', 'Product matched by barcode.');
  String get barcodeCameraTitle =>
      _t('مسح الباركود بالكاميرا', 'Scan barcode with camera');
  String get barcodeCameraHint => _t(
        'وجّه الكاميرا نحو الباركود أو رمز QR داخل الإطار',
        'Point the camera at the barcode or QR code inside the frame',
      );
  String get barcodeCameraTorch => _t('الفلاش', 'Torch');
  String get barcodeCameraScanTooltip =>
      _t('مسح بالكاميرا', 'Scan with camera');
  String get barcodeCameraPermissionDenied => _t(
        'تعذّر فتح الكاميرا. تأكد من منح صلاحية الكاميرا للتطبيق من إعدادات الجهاز.',
        'Could not open the camera. Grant camera permission to the app in device settings.',
      );
  String get barcodeCameraNotAvailable => _t(
        'مسح الباركود بالكاميرا متاح على الجوال فقط.',
        'Camera barcode scanning is available on mobile only.',
      );
  String get invNoBarcodeCantPrint => _t(
        'لا يوجد باركود لهذا الصنف.',
        'This item has no barcode.',
      );
  String get invNoProducts => _t('لا توجد منتجات', 'No products');
  String get invShowBarcodeInBrowseTable =>
      _t('إظهار الباركود في الجدول', 'Show barcode in table');
  String get invHideBarcodeInBrowseTable =>
      _t('إخفاء الباركود من الجدول', 'Hide barcode from table');
  String get invColName => _t('الاسم', 'Name');
  String get invColDelete => _t('حذف', 'Delete');
  String get invDeletedToCart =>
      _t('تم حذف المنتج ونقله للسلة.', 'Product moved to trash.');
  String get invTrashTitle => _t('سلة المنتجات المحذوفة', 'Deleted products');
  String get invTrashEmpty => _t('لا توجد أصناف في السلة.', 'Trash is empty.');
  String get invTrashRestore => _t('استرجاع', 'Restore');
  String get invTrashRestored => _t('تم استرجاع الصنف.', 'Product restored.');
  String get invTrashNoPerm => _t(
        'ليس لديك صلاحية عرض أو استرجاع المنتجات المحذوفة.',
        'No permission to view or restore deleted products.',
      );
  String get invTrashDeletedAt => _t('تاريخ الحذف', 'Deleted at');
  String get invReorderProductsTitle =>
      _t('ترتيب ظهور الأصناف', 'Product display order');
  String get invReorderProductsHint => _t(
        'اسحب الصفوف لترتيب ظهور الأصناف في البحث وشاشات البيع والشراء.',
        'Drag rows to change order in search, sales, and purchase screens.',
      );
  String get invReorderProductsSaved =>
      _t('تم حفظ الترتيب.', 'Display order saved.');
  String get invManageTrashOption =>
      _t('سلة المنتجات المحذوفة', 'Deleted products');
  String get invReorderProductsOption =>
      _t('ترتيب الأصناف', 'Reorder products');
  String get invNoCategoryPerm => _t('ليس لديك صلاحية إدارة التصنيفات.',
      'No permission to manage categories.');
  String get invNoDeleteProductPerm => _t(
        'ليس لديك صلاحية حذف المنتجات.',
        'No permission to delete products.',
      );
  String get invDeleteProductOption =>
      _t('حذف منتج', 'Delete product');
  String get invPermanentDeleteOption =>
      _t('حذف نهائي', 'Delete permanently');
  String get invPermanentDeleteConfirmTitle =>
      _t('حذف نهائي؟', 'Delete permanently?');
  String invPermanentDeleteConfirmBody(String name) => _en
      ? '«$name» will be removed permanently from the system. This cannot be undone. Continue?'
      : 'سيتم حذف «$name» نهائياً من النظام ولا يمكن التراجع. المتابعة؟';
  String get invPermanentDeleted =>
      _t('تم الحذف النهائي للمنتج.', 'Product permanently deleted.');
  String get invTrashPermanentDelete =>
      _t('حذف نهائي', 'Delete permanently');
  String get invAddCategory => _t('إضافة تصنيف جديد', 'Add category');
  String get invCategoryName => _t('اسم التصنيف', 'Category name');
  String categorySaved(String n) =>
      _en ? 'Category saved ($n).' : 'تم حفظ التصنيف ($n)';
  String get invManageCategoriesOption =>
      _t('إدارة التصنيفات', 'Manage categories');
  String get invManageUnitsOption =>
      _t('إدارة وحدات القياس', 'Manage units of measure');
  String get invManageUnitsDialogTitle =>
      _t('إدارة وحدات القياس', 'Units of measure');
  String get invProductUnitHelper => _t(
        'وحدة المخزون والسعر الأساسية. أضف وحدات بيع (كرتونة، باكو…) مع «جزء من وحدة أكبر» أدناه.',
        'Base stock/price unit. Add sale units (carton, pack…) as parts of a larger unit below.',
      );
  String get invSaleUnitsSectionTitle =>
      _t('وحدات بيع إضافية', 'Additional sale units');
  String get invSaleUnitsSectionSub => _t(
        'مثال: وحدة المخزون «حبة»، باكو = 12 حبة، كرتونة = 24 باكو (جزء من باكو).',
        'Example: stock unit «piece», pack = 12 pieces, carton = 24 packs (part of pack).',
      );
  String get invSaleUnitsEmptyHint => _t(
        'اختياري — للبيع بالكرتونة أو الباكو مع تحويل تلقائي للمخزون.',
        'Optional — sell by carton or pack with automatic stock conversion.',
      );
  String invSaleUnitRowLabel(int n) =>
      _en ? 'Unit $n' : 'وحدة $n';
  String get invSaleUnitPartOfParent =>
      _t('جزء من وحدة أكبر', 'Part of a larger unit');
  String get invSaleUnitParentLabel =>
      _t('الوحدة الأكبر', 'Larger unit');
  String get invSaleUnitBaseStockLabel =>
      _t('وحدة المخزون الأساسية', 'Base stock unit');
  String invSaleUnitParentIsBase(String base) =>
      _en ? 'Base: $base' : 'الأساسية: $base';
  String invSaleUnitCountInParentLabel(String parent, String child) => _en
      ? 'How many «$parent» in one «$child»?'
      : 'كم «$parent» في كل «$child»؟';
  String get invSaleUnitCountInParentHelper => _t(
        'مثال: 24 باكو في كل كرتونة.',
        'Example: 24 packs per carton.',
      );
  String invSaleUnitDirectFactorLabel(String base) => _en
      ? 'How many «$base» in one of this unit?'
      : 'كم «$base» في كل وحدة من هذه؟';
  String get invSaleUnitDirectFactorHelper => _t(
        'للوزن أو الكسر (مثل وقية = 0.25 كيلو) عطّل «جزء من وحدة أكبر».',
        'For weight or fractions (e.g. quarter kg) turn off «part of larger unit».',
      );
  String get invSaleUnitAddRow =>
      _t('إضافة وحدة بيع', 'Add sale unit');
  String get invProductUnitNone => _t('بدون وحدة', 'No unit');
  String get invUnitAddTitle => _t('إضافة وحدة قياس', 'Add unit');
  String get invUnitEditTitle => _t('تعديل وحدة القياس', 'Edit unit');
  String get invUnitNameLabel =>
      _t('اسم الوحدة (مثال: كيلو، علبة)', 'Unit name');
  String get invUnitCatalogPackagingHint => _t(
        'تعريف «كم باكو في كرتونة» يتم عند إضافة/تعديل الصنف في قسم «وحدات بيع إضافية».',
        'Pack sizes (e.g. packs per carton) are set when adding/editing a product under «Additional sale units».',
      );
  String get invUnitAddButton => _t('إضافة وحدة', 'Add unit');
  String get invUnitSaved => _t('تم حفظ الوحدة.', 'Unit saved.');
  String get invUnitUpdated => _t('تم تحديث الوحدة.', 'Unit updated.');
  String get invUnitDeleted => _t('تم حذف الوحدة.', 'Unit deleted.');
  String get invNoUnits => _t('لا توجد وحدات.', 'No units.');
  String get invUnitDeleteConfirm => _t(
        'هل تريد حذف هذه الوحدة؟ سيتم إزالة اختيارها من الأصناف التي تستخدمها.',
        'Delete this unit? It will be cleared from products that use it.',
      );
  String get invManageTaxesOption =>
      _t('إدارة الضرائب', 'Manage taxes');
  String get invManagePriceListsOption =>
      _t('قوائم الأسعار', 'Price lists');
  String get invTaxAddTitle => _t('إضافة ضريبة', 'Add tax');
  String get invTaxEditTitle => _t('تعديل الضريبة', 'Edit tax');
  String get invTaxNameLabel => _t('اسم الضريبة', 'Tax name');
  String get invTaxPercentLabel => _t('النسبة %', 'Rate %');
  String get invTaxDefaultLabel => _t('افتراضية', 'Default');
  String get invTaxAddButton => _t('إضافة ضريبة', 'Add tax');
  String get invTaxSaved => _t('تم حفظ الضريبة.', 'Tax saved.');
  String get invTaxUpdated => _t('تم تحديث الضريبة.', 'Tax updated.');
  String get invTaxDeleted => _t('تم حذف الضريبة.', 'Tax deleted.');
  String get invNoTaxes => _t('لا توجد ضرائب.', 'No taxes.');
  String get invTaxDeleteConfirm => _t(
        'حذف هذه الضريبة؟',
        'Delete this tax?',
      );
  String get invPriceListAddTitle =>
      _t('إضافة قائمة أسعار', 'Add price list');
  String get invPriceListEditTitle =>
      _t('تعديل قائمة الأسعار', 'Edit price list');
  String get invPriceListNameLabel =>
      _t('اسم القائمة', 'List name');
  String get invPriceListDefaultLabel =>
      _t('قائمة افتراضية', 'Default list');
  String get invPriceListAddButton =>
      _t('إضافة قائمة', 'Add list');
  String get invPriceListSaved =>
      _t('تم حفظ قائمة الأسعار.', 'Price list saved.');
  String get invPriceListUpdated =>
      _t('تم تحديث قائمة الأسعار.', 'Price list updated.');
  String get invPriceListDeleted =>
      _t('تم حذف قائمة الأسعار.', 'Price list deleted.');
  String get invNoPriceLists =>
      _t('لا توجد قوائم أسعار.', 'No price lists.');
  String get invPriceListDeleteConfirm => _t(
        'حذف قائمة الأسعار هذه؟',
        'Delete this price list?',
      );
  String get invPriceListItemsHint => _t(
        'اترك سعر القائمة فارغاً لاستبعاد الصنف من هذه القائمة.',
        'Leave list price empty to exclude the product from this list.',
      );
  String get invPriceListEditItemsTitle =>
      _t('أسعار قائمة الأسعار', 'Price list items');
  String invPriceListEditItemsFor(String name) => _t(
        'أسعار: $name',
        'Prices: $name',
      );
  String get invPriceListEditItemsButton =>
      _t('تعديل أسعار الأصناف', 'Edit item prices');
  String get invPriceListBasePriceCol =>
      _t('السعر الأساسي', 'Base price');
  String get invPriceListListPriceCol =>
      _t('سعر القائمة', 'List price');
  String get invPriceListItemsSaved =>
      _t('تم حفظ أسعار القائمة.', 'List prices saved.');
  String get invPriceListCopyBaseHint => _t(
        'انسخ السعر الأساسي إلى عمود سعر القائمة للأصناف المحددة.',
        'Copy base price into the list price column for visible items.',
      );
  String get invPriceListCopyBaseButton =>
      _t('نسخ الأساسي', 'Copy base');
  String invTaxPercentSummary(double percent) => _t(
        '$percent%',
        '$percent%',
      );
  String get invProductCategory => _t('التصنيف', 'Category');
  String get invCategoryNone => _t('بدون تصنيف', 'No category');
  String get invCategoryEditTitle => _t('تعديل التصنيف', 'Edit category');
  String get invCategoryDeleteConfirm => _t(
      'حذف هذا التصنيف؟ ستُزال العلاقة عن الأصناف المرتبطة دون حذف الأصناف.',
      'Delete this category? Linked products will have no category.');
  String get invCategoryDeleted => _t('تم حذف التصنيف.', 'Category deleted.');
  String get invCategoryUpdated => _t('تم تحديث التصنيف.', 'Category updated.');
  String get invColCategory => _t('التصنيف', 'Category');
  String get invNoCategories =>
      _t('لا توجد تصنيفات بعد.', 'No categories yet.');
  String get invChangeProductCategoryTitle =>
      _t('تغيير تصنيف الصنف', 'Change item category');
  String get invProductCategoryAssigned =>
      _t('تم حفظ تصنيف الصنف.', 'Product category saved.');
  String get invColChangeCategory => _t('تعديل التصنيف', 'Edit category');
  String get invNoPricePerm =>
      _t('ليس لديك صلاحية تعديل الأسعار.', 'No permission to edit prices.');
  String get invNoProductsMsg => _t('لا توجد منتجات.', 'No products.');
  String get invBulkPricesTitle =>
      _t('تعديل أسعار المنتجات', 'Bulk price edit');
  String get invSelectProduct => _t('المنتج', 'Product');
  String get invPricesUpdated => _t('تم تحديث الأسعار.', 'Prices updated.');
  String get invSearchHint =>
      _t('بحث بالاسم أو الباركود…', 'Search name or barcode…');
  String get invShowHiddenProducts => _t('إظهار المخفي', 'Show hidden');
  String get invOnlyWithStockFilter => _t('بكمية فقط', 'In stock only');
  String get invProductVisibleState => _t('ظاهر', 'Visible');
  String get invProductHiddenState => _t('مخفي', 'Hidden');
  String get invProductTypeStock => _t('صنف مخزون', 'Stock item');
  String get invDeleteProductConfirmTitle =>
      _t('حذف المنتج؟', 'Delete product?');
  String invDeleteProductConfirmBody(String name) => _en
      ? 'Move «$name» to trash? You can restore it from the warehouse trash.'
      : 'نقل «$name» إلى سلة المحذوفات؟ يمكنك استرجاعه من سلة المستودع.';
  String get invStockQtyNew =>
      _t('الكمية في المستودع (الجديدة)', 'Stock quantity (new)');
  String get invStockQtyHelper => _t(
        'أدخل الكمية الإجمالية الحالية بعد التعديل.',
        'Enter the new on-hand quantity.',
      );
  String get invStockModeSetTotal => _t('تعيين الكمية', 'Set quantity');
  String get invStockModeDelta => _t('زيادة / خصم', 'Add / subtract');
  String get invStockDeltaLabel =>
      _t('التغيير (+ زيادة، − خصم)', 'Change (+ add, − subtract)');
  String get invStockDeltaHelper => _t(
        'اترك الحقل فارغاً أو 0 إن لم ترد تعديل المخزون.',
        'Leave empty or 0 to keep stock unchanged.',
      );
  String get invSavedPricesAndStock => _t(
        'تم حفظ الأسعار والكمية.',
        'Prices and quantity saved.',
      );
  String get invExportPdfDone => _t('تم تصدير PDF', 'PDF exported');
  String get invExportExcelDone => _t('تم تصدير Excel', 'Excel exported');
  String get invReportRowsCount => _t('عدد الأصناف', 'Items');
  String get invReportTotalQty =>
      _t('إجمالي وحدات المخزون', 'Total stock units');
  String get invShareReport => _t('مشاركة PDF', 'Share PDF');
  String get invPrintReport => _t('طباعة', 'Print');

  String get invDamagedStockMenu =>
      _t('منتجات تالفة (خصم مخزون)', 'Damaged products (stock write-off)');
  String get invDamagedStockTitle => _t('منتجات تالفة', 'Damaged products');
  String get invDamagedStockSubtitle => _t(
        'يُخصم المخزون فعلياً. سجّل سبب الإتلاف. التقرير يعرض العمليات السابقة.',
        'Stock is reduced. Record a reason. The report lists past write-offs.',
      );
  String get invDamagedStockSearchHint =>
      _t('بحث بالاسم أو الباركود…', 'Search name or barcode…');
  String get invDamagedStockWarehouseQty =>
      _t('الكمية في المستودع', 'Quantity in warehouse');
  String get invDamagedStockDisposeQty =>
      _t('الكمية المراد إتلافها', 'Quantity to write off');
  String get invDamagedStockReason => _t('سبب الإتلاف', 'Reason for write-off');
  String get invDamagedStockReasonHint =>
      _t('مثال: تلف، انتهاء، كسر…', 'e.g. spoilage, breakage…');
  String get invDamagedStockSubmit => _t('تسجيل الإتلاف', 'Record write-off');
  String get invDamagedStockReportTitle =>
      _t('تقرير المنتجات التالفة', 'Damaged products report');
  String get invDamagedStockNoHistory =>
      _t('لا توجد عمليات إتلاف مسجّلة.', 'No write-offs recorded yet.');
  String get invDamagedStockSelectProduct =>
      _t('اختر صنفاً من نتائج البحث.', 'Pick a product from search results.');
  String get invDamagedStockServiceSkip =>
      _t('الخدمات لا تُتلف كمخزون.', 'Services are not stock items.');
  String get invDamagedStockDisposedOk =>
      _t('تم تسجيل الإتلاف وتحديث المخزون.', 'Write-off saved; stock updated.');
  String get invDamagedQtyExceedsStock => _t(
        'الكمية المطلوب إتلافها أكبر من المتاح في المستودع.',
        'Quantity exceeds available warehouse stock.',
      );
  String get invDamagedQtyInvalid => _t(
        'أدخل كمية أكبر من صفر.',
        'Enter a quantity greater than zero.',
      );
  String get invDamagedStockReasonRequired =>
      _t('أدخل سبب الإتلاف.', 'Enter a reason for the write-off.');
  String get invDamagedStockConfirmTitle =>
      _t('تأكيد الإتلاف', 'Confirm write-off');
  String invDamagedStockConfirmBody(String name, String qty) => _en
      ? 'Write off $qty of «$name» from warehouse stock?'
      : 'هل تؤكد إتلاف كمية $qty من «$name» من المخزون؟';
  String get invDamagedExportColDate => _t('التاريخ', 'Date');
  String get invDamagedExportColProduct => _t('الصنف', 'Product');
  String get invDamagedExportColQty => _t('الكمية المُتلفة', 'Qty written off');
  String get invDamagedExportColReason => _t('السبب', 'Reason');
  String get invDamagedNoPerm => _t(
        'ليس لديك صلاحية تنفيذ هذه العملية.',
        'You have no permission for this action.',
      );

  String get invProductEditFullMenu =>
      _t('تعديل بيانات المنتج', 'Edit product details');
  String get invProductFreezeMenu => _t('تجميد المنتج', 'Freeze product');
  String get invProductUnfreezeMenu => _t('إلغاء التجميد', 'Unfreeze product');
  String get invProductFrozenBadge => _t('مجمّد', 'Frozen');
  String get invShowFrozenProductsFilter => _t('إظهار المجمدة', 'Show frozen');
  String get invProductCancelMenu => _t('إلغاء المنتج', 'Cancel product');
  String get invCancelProductConfirmTitle =>
      _t('إلغاء المنتج؟', 'Cancel this product?');
  String invCancelProductConfirmBody(String name) => _en
      ? '«$name» will be moved to trash. You can restore it from the warehouse trash.'
      : 'سيتم نقل «$name» إلى سلة المحذوفات. يمكنك استرجاعه من سلة المستودع.';
  String get invEditProductFullTitle =>
      _t('تعديل بيانات المنتج', 'Edit product');
  String get invSwitchFrozen => _t('تجميد المنتج', 'Freeze product');
  String get invSwitchFrozenSub => _t(
        'لا يظهر في البيع أو الشراء أو البحث السريع، ويُستبعد من تقارير جرد المستودع وتقارير الأرباح حسب الصنف.',
        'Hidden from sales/purchase/quick search; excluded from warehouse stock reports and profit-by-product.',
      );
  String get invProductUpdated =>
      _t('تم تحديث بيانات المنتج.', 'Product updated.');

  // تقارير تنفيذية
  String get executiveReportsTitle => _t('تقارير تنفيذية', 'Executive reports');
  String get executiveFromTo => _t('الفترة', 'Period');
  String get executiveSummaryTab => _t('الملخص', 'Summary');
  String get executiveTopCustomersTab => _t('أعلى العملاء', 'Top customers');
  String get executiveSlowProductsTab => _t('أصناف راكدة', 'Slow-moving items');
  String get executiveExportCsv => _t('تصدير CSV', 'Export CSV');
  String get executiveRefreshTooltip => _t('تحديث البيانات', 'Refresh data');
  String get executiveTotalSales => _t('إجمالي المبيعات', 'Total sales');
  String get executiveInvoicesCount =>
      _t('عدد فواتير البيع', 'Sale invoices count');
  String get executiveTotalPurchases =>
      _t('إجمالي المشتريات', 'Total purchases');
  String get executiveGrossProfit =>
      _t('هامش ربح تقديري', 'Estimated gross profit');
  String get executiveTotalExpenses =>
      _t('إجمالي المصاريف', 'Total expenses');
  String get executiveEstimatedNet => _t('صافي تقديري', 'Estimated net');
  String get executiveCustomer => _t('العميل', 'Customer');
  String get executiveInvoices => _t('الفواتير', 'Invoices');
  String get executiveTotalSalesCol => _t('إجمالي المبيعات', 'Total sales');
  String get executiveProduct => _t('الصنف', 'Product');
  String get executiveStock => _t('المخزون', 'Stock');
  String get executiveQtySold => _t('مبيعات الفترة', 'Qty sold (period)');
  String executiveCsvSaved(String path) =>
      _en ? 'CSV saved: $path' : 'تم حفظ الملف: $path';
  String executiveCsvFailed(String e) =>
      _en ? 'Export failed: $e' : 'فشل التصدير: $e';
  String get executiveDisclaimer => _t(
        'الهامش والصافي تقديريان (تكلفة من سجل الأصناف؛ لا يشملان كل التعديلات اليدوية للمخزون).',
        'Gross and net figures are estimates (costs from product records; may not include all manual stock adjustments).',
      );

  // إمكانية الوصول والنسخ — إعدادات المتجر
  String get secUiTextScale => _t('حجم خط الواجهة', 'Interface text size');
  String get secUiTextScaleSub => _t(
        'لتسهيل القراءة (يُطبَّق بعد الحفظ).',
        'Easier reading (applies after save).',
      );
  String get secBackupFolder => _t('مجلد النسخ الاحتياطي', 'Backup folder');
  String get secBackupFolderSub => _t(
        'اختياري — إن وُجد يُحفظ فيه الملف بدل جذر القرص فقط.',
        'Optional — when set, backups go here instead of drive root only.',
      );
  String get secBackupFolderPick => _t('اختيار مجلد…', 'Choose folder…');
  String get secBackupFolderClear => _t('مسار افتراضي', 'Use default path');
  String get secBackupReminderLabel =>
      _t('تذكير بالنسخ إن مرّت (أيام)', 'Remind to back up after (days)');
  String backupReminderSnack(int days) => _en
      ? 'No backup in the last $days days. Use the Backup menu.'
      : 'لم يُسجَّل نسخ احتياطي خلال آخر $days يوماً. استخدم قائمة النسخ.';
  String get secBackupReminderOff => _t('بدون تذكير', 'No reminder');

  // سجل التدقيق — فلترة
  String get auditFilterTitle => _t('تصفية السجل', 'Filter log');
  String get auditFilterFrom => _t('من تاريخ', 'From');
  String get auditFilterTo => _t('إلى تاريخ', 'To');
  String get auditFilterEntity => _t('نوع الكيان', 'Entity type');
  String get auditFilterEntityAll => _t('الكل', 'All');
  String get auditFilterActions => _t('الإجراء', 'Action');
  String get auditFilterActionsAll => _t('كل الإجراءات', 'All actions');
  String get auditUserColumn => _t('العضو', 'Member');
  String get auditApplyFilter => _t('تطبيق', 'Apply');
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      locale.languageCode == 'ar' || locale.languageCode == 'en';

  @override
  Future<AppLocalizations> load(Locale locale) async =>
      AppLocalizations(locale);

  @override
  bool shouldReload(covariant LocalizationsDelegate<AppLocalizations> old) =>
      false;
}
