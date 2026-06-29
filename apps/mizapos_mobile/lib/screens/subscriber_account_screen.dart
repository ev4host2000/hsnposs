import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:mizapos_mobile/l10n/app_localizations.dart';
import 'package:mizapos_mobile/services/voucher_api.dart';
import 'package:mizapos_mobile/services/voucher_session_manager.dart';
import 'package:mizapos_mobile/theme/app_design.dart';
import 'package:mizapos_mobile/ui/country_flag.dart';
import 'package:mizapos_mobile/ui/subscription_plan_card.dart';

/// صفحة «حسابي» الحديثة: تعرض بيانات المشترك الحالي (الاسم، البريد،
/// المؤسسة، القسيمة، الأجهزة) مع زر تسجيل خروج يسمح لفريق العمل بالدخول لاحقاً.
///
/// مرتبطة كلياً بجلسة [VoucherSessionManager]. عند تسجيل الخروج تُمسح
/// الجلسة محلياً (الكتالوج والمعاملات تبقى) ويعود البرنامج لوضع زائر.
class SubscriberAccountScreen extends StatefulWidget {
  const SubscriberAccountScreen({
    super.key,
    this.onManageVoucher,
    this.onStaffLogin,
    this.onSignedOut,
    this.allowSubscriberManagement = true,
  });

  /// اختياري: عند الضغط على «إدارة القسيمة والأجهزة» نفتح حوار التفعيل القديم.
  final Future<void> Function()? onManageVoucher;

  /// اختياري: يفتح شاشة دخول فريق العمل (موظفين) المستقلّة عن حساب المشترك.
  final Future<void> Function()? onStaffLogin;

  /// اختياري: يُستدعى بعد نجاح تسجيل الخروج من جلسة المشترك.
  final Future<void> Function()? onSignedOut;

  /// عندما تكون `false` (مثلاً عضو فريق عمل):
  /// تُخفى أزرار إدارة القسيمة وتسجيل خروج المشترك، وتظهر ملاحظة
  /// بأنها لمالك الاشتراك فقط. تبقى البيانات قابلة للعرض/النسخ.
  final bool allowSubscriberManagement;

  @override
  State<SubscriberAccountScreen> createState() =>
      _SubscriberAccountScreenState();
}

class _SubscriberAccountScreenState extends State<SubscriberAccountScreen> {
  final _mgr = VoucherSessionManager.instance;
  bool _signingOut = false;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(loc.subscriberAccountTitle),
      ),
      body: ValueListenableBuilder<SubscriberAuthSession?>(
        valueListenable: _mgr.sessionNotifier,
        builder: (context, session, _) {
          return ValueListenableBuilder<VoucherStatus>(
            valueListenable: _mgr.statusNotifier,
            builder: (context, status, __) {
              if (session == null) {
                return _NoSessionView(
                  onOpenSignIn: widget.allowSubscriberManagement
                      ? widget.onManageVoucher
                      : null,
                  onStaffLogin: widget.onStaffLogin,
                );
              }
              return _SignedInBody(
                session: session,
                status: status,
                busy: _signingOut,
                allowSubscriberManagement:
                    widget.allowSubscriberManagement,
                onManageVoucher: widget.allowSubscriberManagement
                    ? widget.onManageVoucher
                    : null,
                onStaffLogin: widget.onStaffLogin,
                onSignOut: widget.allowSubscriberManagement
                    ? (_signingOut ? null : _confirmAndSignOut)
                    : null,
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _confirmAndSignOut() async {
    final loc = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) {
        final dlgLoc = AppLocalizations.of(dialogCtx);
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDesign.radiusLg),
          ),
          icon: Icon(
            Icons.logout_rounded,
            color: Theme.of(dialogCtx).colorScheme.error,
            size: 36,
          ),
          title: Text(dlgLoc.subscriberAccountSignOutConfirmTitle),
          content: Text(dlgLoc.subscriberAccountSignOutConfirmBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(false),
              child: Text(dlgLoc.cancel),
            ),
            FilledButton.tonalIcon(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(dialogCtx)
                    .colorScheme
                    .errorContainer,
                foregroundColor: Theme.of(dialogCtx)
                    .colorScheme
                    .onErrorContainer,
              ),
              icon: const Icon(Icons.logout_rounded),
              label: Text(dlgLoc.logout),
              onPressed: () => Navigator.of(dialogCtx).pop(true),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;

    setState(() => _signingOut = true);
    try {
      await _mgr.logout();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.logout)),
      );
      if (widget.onSignedOut != null) {
        await widget.onSignedOut!();
      }
      if (!mounted) return;
      Navigator.of(context).maybePop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }
}

/* ------------------------- Body ------------------------- */

class _SignedInBody extends StatefulWidget {
  const _SignedInBody({
    required this.session,
    required this.status,
    required this.busy,
    required this.allowSubscriberManagement,
    required this.onManageVoucher,
    required this.onStaffLogin,
    required this.onSignOut,
  });

  final SubscriberAuthSession session;
  final VoucherStatus status;
  final bool busy;
  final bool allowSubscriberManagement;
  final Future<void> Function()? onManageVoucher;
  final Future<void> Function()? onStaffLogin;
  final Future<void> Function()? onSignOut;

  @override
  State<_SignedInBody> createState() => _SignedInBodyState();
}

class _SignedInBodyState extends State<_SignedInBody> {
  // متحكّم تمرير صريح يُمرَّر إلى ListView و Scrollbar في آنٍ معاً. على ويندوز
  // كانت حالات «التراك باد لا يُمرِّر» سببها الأساسي أن Scrollbar الافتراضي
  // يستخدم PrimaryScrollController بينما SingleChildScrollView ينشئ متحكّماً
  // ضمنياً جديداً، فيختلّ الربط ويفشل تحويل عجلة/سحب التراك باد. وجود مرجع
  // مشترك يحلّ هذا تماماً.
  final ScrollController _scrollCtrl = ScrollController();

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final mq = MediaQuery.sizeOf(context);
    final maxW = math.min(720.0, mq.width - AppDesign.spaceMd * 2)
        .clamp(280.0, 720.0);

    final session = widget.session;
    final status = widget.status;
    final busy = widget.busy;
    final allowSubscriberManagement = widget.allowSubscriberManagement;
    final onManageVoucher = widget.onManageVoucher;
    final onStaffLogin = widget.onStaffLogin;
    final onSignOut = widget.onSignOut;

    // عناصر الجسم — نُولّدها كقائمة لنُمرّرها إلى ListView (أكثر متانة من
    // SingleChildScrollView مع التراك باد على الديسكتوب).
    final items = <Widget>[
      // 1. Hero (شارة الحالة + الاسم + سطر شرحيّ مختصر).
      _HeroCard(session: session, status: status),

      // 2. Quick Glance: رمز القسيمة، عدّاد الأجهزة، علم الدولة.
      const SizedBox(height: AppDesign.spaceMd),
      _QuickGlanceGrid(session: session, status: status, loc: loc),

      // 3. دخول الموظفين — منفصل عن تفاصيل الاشتراك لتجنب الخلط مع إدارة الفريق.
      if (onStaffLogin != null) ...[
        const SizedBox(height: AppDesign.spaceMd),
        _StaffLoginCard(
          onPressed: busy ? null : () => onStaffLogin(),
        ),
      ],

      // 4. الإجراء الرئيسيّ (CTA).
      if (allowSubscriberManagement && onManageVoucher != null) ...[
        const SizedBox(height: AppDesign.spaceMd),
        _PrimaryActionButton(
          icon: Icons.confirmation_number_rounded,
          label: loc.subscriberAccountActionManageVoucher,
          busy: busy,
          onPressed: busy ? null : () => onManageVoucher(),
        ),
      ],

      // 5. تسجيل خروج المشترك — أعلى التفاصيل ليكون ظاهراً على الجوال.
      if (allowSubscriberManagement) ...[
        const SizedBox(height: AppDesign.spaceMd),
        _SignOutFooter(
          busy: busy,
          onSignOut: onSignOut,
        ),
      ],

      // 6. تفاصيل المشترك.
      const SizedBox(height: AppDesign.spaceLg),
      _SectionTitle(loc.subscriberAccountSectionDetails),
      const SizedBox(height: AppDesign.spaceSm),
      _InfoCard(rows: _detailsRows(session, loc)),

      // 7. ملاحظة للموظفين غير المخوّلين.
      if (!allowSubscriberManagement) ...[
        const SizedBox(height: AppDesign.spaceLg),
        _OwnerOnlyNotice(),
      ],
    ];

    return Scrollbar(
      controller: _scrollCtrl,
      thumbVisibility: true,
      interactive: true,
      child: ListView(
        controller: _scrollCtrl,
        // primary: false مطلوب صراحةً عند تمرير controller، وإلّا قد يحاول
        // Flutter ربطه أيضاً بـ PrimaryScrollController فيرفع تحذيراً عند
        // التركيب على بعض الأجهزة.
        primary: false,
        physics: const AlwaysScrollableScrollPhysics(
          parent: ClampingScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(
          AppDesign.spaceMd,
          AppDesign.spaceMd,
          AppDesign.spaceMd,
          AppDesign.spaceXl,
        ),
        children: [
          // محاذاة المحتوى أفقياً مع حدّ أقصى لعرض القائمة (نفس فكرة
          // ConstrainedBox+Align السابقة، لكن داخل بنود ListView).
          Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxW),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: items,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// صفوف تفاصيل المشترك بعد إزالة ما ينعكس في Hero/Quick Glance.
  /// يبقى: الاسم، البريد، الهاتف (إن وُجد)، المؤسسة (إن وُجد).
  List<_InfoRowData> _detailsRows(
    SubscriberAuthSession session,
    AppLocalizations loc,
  ) {
    return [
      _InfoRowData(
        icon: Icons.person_rounded,
        label: loc.subscriberAccountFieldName,
        value: _resolveName(session, loc),
      ),
      _InfoRowData(
        icon: Icons.alternate_email_rounded,
        label: loc.subscriberAccountFieldEmail,
        value: session.email.isEmpty ? '—' : session.email,
        copyable: session.email.isNotEmpty,
      ),
      if (session.phone.isNotEmpty)
        _InfoRowData(
          icon: Icons.phone_rounded,
          label: loc.subscriberAccountFieldPhone,
          value: session.dialCode.isNotEmpty
              ? '${session.dialCode} ${session.phone}'
              : session.phone,
          copyable: true,
          monospace: true,
        ),
      if (session.organizationId.isNotEmpty)
        _InfoRowData(
          icon: Icons.apartment_rounded,
          label: loc.subscriberAccountFieldOrg,
          value: session.organizationId,
          copyable: true,
          monospace: true,
        ),
    ];
  }

  String _resolveName(SubscriberAuthSession s, AppLocalizations loc) {
    final n = s.fullName.trim();
    if (n.isNotEmpty) return n;
    final email = s.email.trim();
    if (email.contains('@')) return email.split('@').first;
    return loc.subscriberAccountFieldName;
  }
}

/* ------------------------- Hero header ------------------------- */

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.session, required this.status});
  final SubscriberAuthSession session;
  final VoucherStatus status;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final isActive = status.isActive;
    final isRevoked = status.isRevoked;

    final Color g1;
    final Color g2;
    final Color g3;
    if (isRevoked) {
      g1 = scheme.error;
      g2 = Color.lerp(scheme.error, scheme.tertiary, 0.45)!;
      g3 = Color.lerp(scheme.error, scheme.secondary, 0.25)!;
    } else if (isActive) {
      g1 = scheme.primary;
      g2 = Color.lerp(scheme.primary, scheme.tertiary, 0.55)!;
      g3 = Color.lerp(scheme.tertiary, scheme.secondary, 0.25)!;
    } else {
      g1 = scheme.secondary;
      g2 = Color.lerp(scheme.secondary, scheme.tertiary, 0.55)!;
      g3 = Color.lerp(scheme.tertiary, scheme.primary, 0.20)!;
    }

    final onP = scheme.onPrimary;

    final fullName = session.fullName.trim();
    final email = session.email.trim();
    final dialCode = session.dialCode.trim();
    final displayName = fullName.isNotEmpty
        ? fullName
        : (email.contains('@') ? email.split('@').first : email);
    final letterChar = displayName.isEmpty
        ? '?'
        : String.fromCharCode(displayName.runes.first).toUpperCase();

    final badgeText = isRevoked
        ? loc.subscriberAccountHeroBadgeRevoked
        : (isActive
            ? loc.subscriberAccountHeroBadge
            : loc.subscriberAccountHeroBadgePending);
    final badgeIcon = isRevoked
        ? Icons.warning_amber_rounded
        : (isActive ? Icons.verified_rounded : Icons.hourglass_top_rounded);
    final subtitle = isActive
        ? loc.subscriberAccountHeroSubtitleActive
        : (isRevoked
            ? loc.voucherReadOnlyBannerBody
            : loc.subscriberAccountHeroSubtitleInactive);

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppDesign.radiusXl),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: AlignmentDirectional.topStart,
            end: AlignmentDirectional.bottomEnd,
            colors: [g1, g2, g3],
          ),
          boxShadow: [
            BoxShadow(
              blurRadius: 28,
              offset: const Offset(0, 14),
              color: g1.withValues(alpha: 0.32),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              right: -28,
              top: -32,
              child: Icon(
                Icons.workspace_premium_rounded,
                size: 180,
                color: onP.withValues(alpha: 0.08),
              ),
            ),
            Positioned(
              left: -18,
              bottom: -22,
              child: Icon(
                Icons.blur_circular_rounded,
                size: 130,
                color: onP.withValues(alpha: 0.06),
              ),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                AppDesign.spaceLg,
                AppDesign.spaceLg,
                AppDesign.spaceLg,
                AppDesign.spaceLg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _AvatarWithFlag(
                        letter: letterChar,
                        scheme: scheme,
                        dialCode: dialCode,
                      ),
                      const SizedBox(width: AppDesign.spaceMd),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _StatusChip(
                              text: badgeText,
                              icon: badgeIcon,
                              onPrimary: onP,
                            ),
                            const SizedBox(height: AppDesign.spaceSm),
                            Text(
                              displayName.isEmpty
                                  ? loc.subscriberAccountFieldName
                                  : displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleLarge?.copyWith(
                                color: onP,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.2,
                                height: 1.1,
                              ),
                            ),
                            const SizedBox(height: 4),
                            // سطر شرحيّ مختصر تحت الاسم. لا صندوق منفصل ولا
                            // أيقونة كبيرة — يكفي نصّ ناعم لتفسير حالة الجلسة.
                            Text(
                              subtitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: onP.withValues(alpha: 0.88),
                                fontWeight: FontWeight.w500,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// أفاتار المشترك مع شارة علم الدولة في الزاوية السفلى.
/// عند تعذّر التعرّف على الدولة (لا dialCode أو دولة غير معروفة) تُخفى الشارة
/// تلقائياً دون كسر التخطيط.
class _AvatarWithFlag extends StatelessWidget {
  const _AvatarWithFlag({
    required this.letter,
    required this.scheme,
    required this.dialCode,
  });

  final String letter;
  final ColorScheme scheme;
  final String dialCode;

  @override
  Widget build(BuildContext context) {
    final country = countryFromDial(dialCode);
    return SizedBox(
      width: 80,
      height: 80,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.85),
                  width: 3,
                ),
                boxShadow: [
                  BoxShadow(
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                    color: Colors.black.withValues(alpha: 0.18),
                  ),
                ],
              ),
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      scheme.primaryContainer,
                      scheme.tertiaryContainer,
                    ],
                  ),
                ),
                child: Text(
                  letter,
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    color: scheme.primary,
                  ),
                ),
              ),
            ),
          ),
          if (country != null)
            PositionedDirectional(
              bottom: -2,
              end: -4,
              child: CountryFlag(
                dialCode: dialCode,
                size: 30,
                shape: CountryFlagShape.circle,
                borderWidth: 2.5,
              ),
            ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.text,
    required this.icon,
    required this.onPrimary,
  });
  final String text;
  final IconData icon;
  final Color onPrimary;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: onPrimary.withValues(alpha: 0.20),
        borderRadius: BorderRadius.circular(AppDesign.radiusMd),
        border: Border.all(color: onPrimary.withValues(alpha: 0.40)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 4,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: onPrimary),
            const SizedBox(width: AppDesign.spaceXs),
            Text(
              text,
              style: TextStyle(
                color: onPrimary,
                fontWeight: FontWeight.w800,
                fontSize: 12.5,
                letterSpacing: -0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/* ------------------------- Quick Glance ------------------------- */

/// شبكة «نظرة سريعة» تعرض المعلومات الحرجة بعد Hero مباشرة:
///   • رمز القسيمة + نسخ
///   • عدّاد الأجهزة + الدولة في بطاقة واحدة لتخفيف الازدحام على الجوال
class _QuickGlanceGrid extends StatelessWidget {
  const _QuickGlanceGrid({
    required this.session,
    required this.status,
    required this.loc,
  });

  final SubscriberAuthSession session;
  final VoucherStatus status;
  final AppLocalizations loc;

  @override
  Widget build(BuildContext context) {
    final country = countryFromDial(session.dialCode);
    final hasVoucher = status.code.isNotEmpty;
    final hasDevices = status.maxDevices > 0;
    final hasCountry = country != null;
    if (!hasVoucher && !hasDevices && !hasCountry) {
      return const SizedBox.shrink();
    }

    final voucherTile = hasVoucher
        ? _VoucherCodeTile(code: status.code, loc: loc)
        : null;
    final devicesCountryTile = (hasDevices || hasCountry)
        ? _DevicesCountryGlanceTile(
            used: status.usedDevices,
            max: status.maxDevices,
            country: country,
            englishUi: loc.isEnglish,
            loc: loc,
            showDevices: hasDevices,
            showCountry: hasCountry,
          )
        : null;

    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= 520;
        if (wide && voucherTile != null && devicesCountryTile != null) {
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: voucherTile),
                const SizedBox(width: AppDesign.spaceSm + 2),
                Expanded(child: devicesCountryTile),
              ],
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (voucherTile != null) voucherTile,
            if (voucherTile != null && devicesCountryTile != null)
              const SizedBox(height: AppDesign.spaceSm + 2),
            if (devicesCountryTile != null) devicesCountryTile,
          ],
        );
      },
    );
  }
}

/// بلاطة عرض رمز القسيمة في شبكة Quick Glance مع زرّ نسخ.
class _VoucherCodeTile extends StatelessWidget {
  const _VoucherCodeTile({required this.code, required this.loc});
  final String code;
  final AppLocalizations loc;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _GlanceShell(
      accent: scheme.primary,
      icon: Icons.confirmation_number_rounded,
      label: loc.subscriberAccountFieldVoucher,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: SelectableText(
              code,
              maxLines: 1,
              style: TextStyle(
                fontFamily: 'monospace',
                fontWeight: FontWeight.w900,
                fontSize: 15,
                letterSpacing: 0.6,
                color: scheme.onSurface,
              ),
            ),
          ),
          IconButton(
            tooltip: loc.subscriberAccountCopyTooltip,
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.copy_rounded,
                size: 18, color: scheme.primary),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              await Clipboard.setData(ClipboardData(text: code));
              messenger.showSnackBar(SnackBar(
                content: Text(loc.subscriberAccountCopiedToClipboard),
                behavior: SnackBarBehavior.floating,
              ));
            },
          ),
        ],
      ),
    );
  }
}

/// بطاقة موحّدة: عدّاد الأجهزة بجانب الدولة لتقليل الازدحام على الجوال.
class _DevicesCountryGlanceTile extends StatelessWidget {
  const _DevicesCountryGlanceTile({
    required this.used,
    required this.max,
    required this.country,
    required this.englishUi,
    required this.loc,
    required this.showDevices,
    required this.showCountry,
  });

  final int used;
  final int max;
  final CountryInfo? country;
  final bool englishUi;
  final AppLocalizations loc;
  final bool showDevices;
  final bool showCountry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ratio = max <= 0 ? 0.0 : (used / max).clamp(0.0, 1.0);
    final progressColor = ratio >= 0.9
        ? scheme.error
        : (ratio >= 0.7 ? scheme.tertiary : scheme.primary);

    final label = showDevices && showCountry
        ? '${loc.subscriberAccountFieldDevices} · ${loc.subscriberAccountFieldCountry}'
        : (showDevices
            ? loc.subscriberAccountFieldDevices
            : loc.subscriberAccountFieldCountry);

    return _GlanceShell(
      accent: showDevices ? progressColor : scheme.tertiary,
      icon: showDevices ? Icons.devices_rounded : Icons.public_rounded,
      label: label,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (showDevices) ...[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        '$used',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 22,
                          height: 1.0,
                          color: scheme.onSurface,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '/ $max',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: scheme.onSurface.withValues(alpha: 0.62),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: ratio,
                      minHeight: 5,
                      backgroundColor:
                          scheme.outline.withValues(alpha: 0.18),
                      valueColor:
                          AlwaysStoppedAnimation<Color>(progressColor),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (showDevices && showCountry) ...[
            const SizedBox(width: 12),
            Container(
              width: 1,
              height: 52,
              color: scheme.outline.withValues(alpha: 0.16),
            ),
            const SizedBox(width: 12),
          ],
          if (showCountry && country != null)
            Expanded(
              child: Row(
                children: [
                  CountryFlag(
                    dialCode: country!.dialCode,
                    size: 30,
                    shape: CountryFlagShape.rounded,
                    borderColor: scheme.outline.withValues(alpha: 0.35),
                    borderWidth: 1.2,
                    showShadow: false,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          country!.name(englishUi),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13.5,
                            height: 1.15,
                            color: scheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          country!.dialCode,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w700,
                            fontSize: 11.5,
                            color: scheme.onSurface.withValues(alpha: 0.62),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// الغلاف الموحَّد لبلاطات Quick Glance: حدّ ناعم + شارة أيقونة بلون
/// محوريّ في الزاوية + عنوان صغير أعلى المحتوى.
class _GlanceShell extends StatelessWidget {
  const _GlanceShell({
    required this.accent,
    required this.icon,
    required this.label,
    required this.child,
  });

  final Color accent;
  final IconData icon;
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      elevation: 0.5,
      shadowColor: scheme.shadow.withValues(alpha: 0.06),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDesign.radiusLg),
        side: BorderSide(color: scheme.outline.withValues(alpha: 0.14)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppDesign.spaceMd,
          AppDesign.spaceSm + 4,
          AppDesign.spaceSm + 4,
          AppDesign.spaceMd,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 16, color: accent),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 11.5,
                      letterSpacing: 0.2,
                      color: scheme.onSurface.withValues(alpha: 0.62),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

/* ------------------------- Primary CTA & Sign Out ------------------------- */

/// زرّ الفعل الرئيسيّ الواضح في الصفحة (إدارة القسيمة والأجهزة). يستخدم
/// `FilledButton.icon` بنمط مرتفع داخل صفّ المعلومات لتمييزه عن البقيّة.
class _PrimaryActionButton extends StatelessWidget {
  const _PrimaryActionButton({
    required this.icon,
    required this.label,
    required this.busy,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      icon: busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            )
          : Icon(icon),
      label: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: AppDesign.spaceMd),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDesign.radiusLg),
        ),
      ),
    );
  }
}

/// تذييل تسجيل الخروج بأسلوب هادئ: تلميح صغير + زرّ outlined بلون الخطأ
/// بدلاً من الزرّ الأحمر الممتلئ الذي كان سابقاً. أقلّ عدوانية ويتناسب
/// أكثر مع كونها صفحة إعدادات لا منطقة خطر.
class _SignOutFooter extends StatelessWidget {
  const _SignOutFooter({required this.busy, required this.onSignOut});

  final bool busy;
  final Future<void> Function()? onSignOut;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          loc.subscriberAccountSignOutHint,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.62),
            height: 1.45,
          ),
        ),
        const SizedBox(height: AppDesign.spaceSm),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            icon: busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  )
                : const Icon(Icons.logout_rounded, size: 20),
            label: Text(loc.subscriberAccountActionSignOut),
            onPressed: onSignOut == null ? null : () => onSignOut!(),
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
              side: BorderSide(
                color: theme.colorScheme.error.withValues(alpha: 0.55),
                width: 1.2,
              ),
              padding: const EdgeInsets.symmetric(
                vertical: AppDesign.spaceSm + 4,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppDesign.radiusLg),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/* ------------------------- Sections ------------------------- */

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.only(
        start: AppDesign.spaceXs,
        end: AppDesign.spaceXs,
      ),
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.1,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.78),
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.rows});
  final List<_InfoRowData> rows;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      elevation: 1,
      shadowColor: scheme.shadow.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDesign.radiusLg),
        side: BorderSide(color: scheme.outline.withValues(alpha: 0.12)),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            _InfoTile(data: rows[i]),
            if (i != rows.length - 1)
              Divider(
                height: 1,
                thickness: 1,
                indent: AppDesign.spaceMd,
                endIndent: AppDesign.spaceMd,
                color: scheme.outline.withValues(alpha: 0.12),
              ),
          ],
        ],
      ),
    );
  }
}

/* ------------------------- Rows ------------------------- */

class _InfoRowData {
  const _InfoRowData({
    required this.icon,
    required this.label,
    required this.value,
    this.copyable = false,
    this.monospace = false,
  });
  final IconData icon;
  final String label;
  final String value;
  final bool copyable;
  final bool monospace;
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.data});
  final _InfoRowData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppDesign.spaceMd,
        AppDesign.spaceSm + 4,
        AppDesign.spaceSm,
        AppDesign.spaceSm + 4,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppDesign.radiusMd),
            ),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Icon(data.icon, size: 20, color: scheme.primary),
            ),
          ),
          const SizedBox(width: AppDesign.spaceSm + 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.58),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                SelectableText(
                  data.value,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    height: 1.22,
                    fontFamily: data.monospace ? 'monospace' : null,
                    letterSpacing: data.monospace ? 0.6 : null,
                  ),
                ),
              ],
            ),
          ),
          if (data.copyable && data.value.isNotEmpty)
            IconButton(
              tooltip: AppLocalizations.of(context).subscriberAccountCopyTooltip,
              icon: const Icon(Icons.copy_rounded, size: 18),
              onPressed: () async {
                final loc = AppLocalizations.of(context);
                final messenger = ScaffoldMessenger.of(context);
                await Clipboard.setData(ClipboardData(text: data.value));
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(loc.subscriberAccountCopiedToClipboard),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

/* ------------------------- Owner-only notice ------------------------- */

class _OwnerOnlyNotice extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppDesign.spaceMd),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppDesign.radiusLg),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.16)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.shield_moon_outlined, color: scheme.primary, size: 20),
          const SizedBox(width: AppDesign.spaceSm + 4),
          Expanded(
            child: Text(
              loc.subscriberAccountOwnerOnlyNote,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    height: 1.5,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface.withValues(alpha: 0.85),
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

/* ------------------------- Staff login card ------------------------- */

class _StaffLoginCard extends StatelessWidget {
  const _StaffLoginCard({required this.onPressed});
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.tertiaryContainer.withValues(alpha: 0.55),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDesign.radiusLg),
        side: BorderSide(
          color: scheme.tertiary.withValues(alpha: 0.35),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppDesign.spaceMd),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.tertiary.withValues(alpha: 0.18),
              ),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Icon(
                  Icons.badge_rounded,
                  color: scheme.tertiary,
                ),
              ),
            ),
            const SizedBox(width: AppDesign.spaceSm + 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    loc.subscriberAccountStaffLoginCardTitle,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: scheme.onTertiaryContainer,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    loc.subscriberAccountStaffLoginCardBody,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onTertiaryContainer
                          .withValues(alpha: 0.85),
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: AppDesign.spaceSm + 2),
                  FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      backgroundColor: scheme.tertiary,
                      foregroundColor: scheme.onTertiary,
                    ),
                    icon: const Icon(Icons.login_rounded, size: 18),
                    label: Text(loc.subscriberAccountStaffLoginCta),
                    onPressed: onPressed,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/* ------------------------- No session view ------------------------- */

class _NoSessionView extends StatefulWidget {
  const _NoSessionView({
    required this.onOpenSignIn,
    required this.onStaffLogin,
  });
  final Future<void> Function()? onOpenSignIn;
  final Future<void> Function()? onStaffLogin;

  @override
  State<_NoSessionView> createState() => _NoSessionViewState();
}

class _NoSessionViewState extends State<_NoSessionView> {
  final ScrollController _scrollCtrl = ScrollController();

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    // محتوى قابل للتمرير لكي لا ينقطع على الشاشات القصيرة (لابتوبات 13").
    // نستخدم ListView مع ScrollController صريح ومشترك مع Scrollbar لضمان
    // عمل عجلة الفأرة والتراك باد على ويندوز بشكل موثوق (راجع _SignedInBody).
    return Scrollbar(
      controller: _scrollCtrl,
      thumbVisibility: true,
      interactive: true,
      child: ListView(
        controller: _scrollCtrl,
        primary: false,
        physics: const AlwaysScrollableScrollPhysics(
          parent: ClampingScrollPhysics(),
        ),
        padding: const EdgeInsets.all(AppDesign.spaceLg),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.account_circle_outlined,
                    size: 72,
                    color: scheme.primary.withValues(alpha: 0.65),
                  ),
                  const SizedBox(height: AppDesign.spaceSm),
                  Text(
                    loc.subscriberAccountNoSubscription,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: AppDesign.spaceMd),
                  // بطاقة السعر تظهر هنا حتى يطّلع المستخدم على التكلفة
                  // قبل الضغط على زرّ التسجيل/التفعيل.
                  const SubscriptionPlanCard(),
                  const SizedBox(height: AppDesign.spaceMd),
                  FilledButton.icon(
                    icon: const Icon(Icons.key_rounded),
                    label: Text(loc.voucherDialogTitle),
                    onPressed: widget.onOpenSignIn == null
                        ? null
                        : () => widget.onOpenSignIn!(),
                  ),
                  if (widget.onStaffLogin != null) ...[
                    const SizedBox(height: AppDesign.spaceLg),
                    _StaffLoginCard(
                      onPressed: () => widget.onStaffLogin!(),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
