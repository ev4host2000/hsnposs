import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:mizapos_desktop/config/remote_signup_config.dart';
import 'package:mizapos_desktop/l10n/app_localizations.dart';
import 'package:mizapos_desktop/services/database_service.dart';
import 'package:mizapos_desktop/services/voucher_api.dart';
import 'package:mizapos_desktop/services/voucher_session_manager.dart';
import 'package:mizapos_desktop/theme/app_design.dart';
import 'package:mizapos_desktop/ui/country_flag.dart';
import 'package:mizapos_desktop/ui/dial_code_picker_field.dart';
import 'package:mizapos_desktop/ui/subscription_plan_card.dart';

/// حوار تفعيل الاشتراك بقسيمة (Miza-XXXX-XXXX-XXXX).
///
/// التدفّق:
/// 1. لا توجد جلسة → تسجيل / دخول حساب المشترك.
/// 2. توجد جلسة لكن لا قسيمة → الصق الكود + زر تفعيل.
/// 3. مُفعَّل بقسيمة → ملخّص الاستهلاك + خيار تحرير الجهاز.
///
/// [allowSubscriberManagement]: عندما تكون `false` (مثلاً عضو فريق عمل)،
/// تختفي إجراءات إدارة الجلسة وتحرير الجهاز، وتظهر ملاحظة بأنّها
/// محصورة بصاحب الاشتراك.
Future<VoucherStatus?> showVoucherActivationDialog(
  BuildContext context, {
  bool allowSubscriberManagement = true,
}) {
  return showDialog<VoucherStatus>(
    context: context,
    barrierDismissible: true,
    builder: (_) => _VoucherActivationDialog(
      allowSubscriberManagement: allowSubscriberManagement,
    ),
  );
}

/// ترحيب بالمشترك بعد إنشاء حساب جديد.
///
/// يُعيد `'try'` لإغلاق حوار التفعيل وتجربة البرنامج، أو `'activate'`
/// للانتقال إلى خطوة إدخال رمز القسيمة.
Future<String?> showSubscriberRegistrationWelcomeDialog(
  BuildContext context, {
  required String fullName,
}) {
  final loc = AppLocalizations.of(context);
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    barrierColor: Colors.black.withValues(alpha: 0.42),
    builder: (ctx) {
      final theme = Theme.of(ctx);
      final cs = theme.colorScheme;
      final name = fullName.trim();
      final greeting = name.isEmpty
          ? loc.authSignupCelebrationSubtitle
          : loc.authSignupCelebrationPersonalized(name);
      final accentEnd =
          Color.lerp(cs.primary, cs.tertiary, 0.45) ?? cs.primary;

      return Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: Material(
            color: cs.surface,
            elevation: 12,
            shadowColor: cs.shadow.withValues(alpha: 0.22),
            borderRadius: AppDesign.borderRadiusXl,
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: AlignmentDirectional.centerStart,
                      end: AlignmentDirectional.centerEnd,
                      colors: [
                        cs.primary.withValues(alpha: 0.92),
                        accentEnd.withValues(alpha: 0.88),
                      ],
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
                    child: Row(
                      children: [
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.18),
                            borderRadius: AppDesign.borderRadiusMd,
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.28),
                            ),
                          ),
                          child: const Padding(
                            padding: EdgeInsets.all(9),
                            child: Icon(
                              Icons.celebration_rounded,
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                greeting,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  height: 1.25,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                loc.authSignupCelebrationTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.88),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        loc.authSubscriberWelcomeBody,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurface.withValues(alpha: 0.72),
                          height: 1.45,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          minimumSize:
                              const Size.fromHeight(AppDesign.buttonHeight),
                          shape: RoundedRectangleBorder(
                            borderRadius: AppDesign.borderRadiusMd,
                          ),
                        ),
                        onPressed: () => Navigator.pop(ctx, 'activate'),
                        icon: const Icon(Icons.confirmation_number_outlined,
                            size: 20),
                        label: Text(loc.authSubscriberWelcomeActivateVoucher),
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          minimumSize:
                              const Size.fromHeight(AppDesign.buttonHeight - 4),
                          foregroundColor: cs.primary,
                        ),
                        onPressed: () => Navigator.pop(ctx, 'try'),
                        icon: const Icon(Icons.play_circle_outline_rounded,
                            size: 20),
                        label: Text(loc.authSubscriberWelcomeTryApp),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _VoucherActivationDialog extends StatefulWidget {
  const _VoucherActivationDialog({required this.allowSubscriberManagement});

  final bool allowSubscriberManagement;

  @override
  State<_VoucherActivationDialog> createState() =>
      _VoucherActivationDialogState();
}

class _VoucherActivationDialogState extends State<_VoucherActivationDialog> {
  final _mgr = VoucherSessionManager.instance;

  /// بعد إنشاء حساب جديد تُحدَّث الجلسة فوراً؛ نؤجّل لوحة القسيمة حتى
  /// يُغلق حوار الترحيب.
  bool _holdRedeemForWelcome = false;

  void _clearRegisterWelcomeHold() {
    if (_holdRedeemForWelcome) {
      setState(() => _holdRedeemForWelcome = false);
    }
  }

  Future<void> _handleRegisterSuccess(String fullName) async {
    try {
      final welcomeAction = await showSubscriberRegistrationWelcomeDialog(
        context,
        fullName: fullName,
      );
      if (!mounted) return;
      if (welcomeAction == 'try') {
        Navigator.of(context).pop(_mgr.statusNotifier.value);
      }
    } finally {
      if (mounted) _clearRegisterWelcomeHold();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final wide = MediaQuery.sizeOf(context).width >= 760;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: EdgeInsets.symmetric(
        horizontal: wide ? 48 : 20,
        vertical: 28,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: wide ? 940 : 520,
          maxHeight: math.min(
            MediaQuery.sizeOf(context).height * 0.92,
            wide ? 660 : 820,
          ),
        ),
        child: Material(
          color: cs.surface,
          elevation: 24,
          shadowColor: cs.shadow.withValues(alpha: 0.22),
          borderRadius: AppDesign.borderRadiusXl,
          clipBehavior: Clip.antiAlias,
          child: ValueListenableBuilder<SubscriberAuthSession?>(
            valueListenable: _mgr.sessionNotifier,
            builder: (context, session, _) {
              return ValueListenableBuilder<VoucherStatus>(
                valueListenable: _mgr.statusNotifier,
                builder: (context, status, _) {
                  final body = _buildDialogBody(
                    session: session,
                    status: status,
                    embedPlan: !wide,
                    wide: wide,
                  );

                  void closeDialog() =>
                      Navigator.of(context).maybePop(_mgr.status);

                  if (wide) {
                    return IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(
                            width: 340,
                            child: SubscriptionPlanCard(rail: true),
                          ),
                          VerticalDivider(
                            width: 1,
                            thickness: 1,
                            color: cs.outlineVariant.withValues(alpha: 0.35),
                          ),
                          Expanded(
                            child: _DialogScrollColumn(
                              session: session,
                              showLogout: widget.allowSubscriberManagement,
                              onClose: closeDialog,
                              wide: true,
                              ownerOnlyNote: !widget.allowSubscriberManagement &&
                                  session != null,
                              child: body,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return _DialogScrollColumn(
                    session: session,
                    showLogout: widget.allowSubscriberManagement,
                    onClose: closeDialog,
                    wide: false,
                    ownerOnlyNote:
                        !widget.allowSubscriberManagement && session != null,
                    child: body,
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildDialogBody({
    required SubscriberAuthSession? session,
    required VoucherStatus status,
    required bool embedPlan,
    required bool wide,
  }) {
    if (session == null) {
      return _SignInOrRegisterPanel(
        embedPlan: embedPlan,
        wide: wide,
        onDone: () => setState(() {}),
        onRegisterStarted: () {
          setState(() => _holdRedeemForWelcome = true);
        },
        onRegisterFailed: _clearRegisterWelcomeHold,
        onRegisterSuccess: _handleRegisterSuccess,
      );
    }
    if (status.isActive) {
      return _ActiveSubscriptionPanel(
        status: status,
        session: session,
        wide: wide,
        allowReleaseDevice: widget.allowSubscriberManagement,
        onChanged: () => setState(() {}),
      );
    }
    if (_holdRedeemForWelcome) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return _RedeemVoucherPanel(
      embedPlan: embedPlan,
      onSuccess: () => setState(() {}),
    );
  }
}

class _DialogScrollColumn extends StatelessWidget {
  const _DialogScrollColumn({
    required this.session,
    required this.showLogout,
    required this.onClose,
    required this.wide,
    required this.child,
    required this.ownerOnlyNote,
  });

  final SubscriberAuthSession? session;
  final bool showLogout;
  final VoidCallback onClose;
  final bool wide;
  final Widget child;
  final bool ownerOnlyNote;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(wide ? 22 : 20, wide ? 20 : 18, wide ? 22 : 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _DialogHeader(
            session: session,
            showLogout: showLogout,
            onClose: onClose,
          ),
          const SizedBox(height: 14),
          child,
          if (ownerOnlyNote) ...[
            const SizedBox(height: 10),
            _OwnerOnlyHint(),
          ],
          if (!wide) ...[
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                onPressed: onClose,
                child: Text(loc.close),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DialogHeader extends StatelessWidget {
  const _DialogHeader({
    this.session,
    this.showLogout = true,
    this.onClose,
  });
  final SubscriberAuthSession? session;
  final bool showLogout;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                cs.primary.withValues(alpha: 0.14),
                cs.primary.withValues(alpha: 0.06),
              ],
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cs.primary.withValues(alpha: 0.18)),
          ),
          child: Icon(Icons.confirmation_number_outlined, color: cs.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                loc.voucherDialogTitle,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                loc.subscriptionPlanPriceShort,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
        ),
        if (session != null && showLogout)
          IconButton(
            tooltip: loc.voucherLogout,
            icon: const Icon(Icons.logout, size: 20),
            onPressed: () async {
              await VoucherSessionManager.instance.logout();
            },
          ),
        if (onClose != null)
          IconButton(
            tooltip: loc.close,
            icon: const Icon(Icons.close_rounded, size: 20),
            onPressed: onClose,
          ),
      ],
    );
  }
}

class _OwnerOnlyHint extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outline.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.shield_moon_outlined, size: 18, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              loc.subscriberAccountOwnerOnlyNote,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    height: 1.45,
                    color: cs.onSurface.withValues(alpha: 0.86),
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

/* ---------------- Sign in / Register ---------------- */

class _SignInOrRegisterPanel extends StatefulWidget {
  const _SignInOrRegisterPanel({
    required this.onDone,
    required this.onRegisterStarted,
    required this.onRegisterFailed,
    required this.onRegisterSuccess,
    this.embedPlan = true,
    this.wide = false,
  });
  final VoidCallback onDone;
  final VoidCallback onRegisterStarted;
  final VoidCallback onRegisterFailed;
  final Future<void> Function(String fullName) onRegisterSuccess;
  final bool embedPlan;
  final bool wide;

  @override
  State<_SignInOrRegisterPanel> createState() => _SignInOrRegisterPanelState();
}

class _SignInOrRegisterPanelState extends State<_SignInOrRegisterPanel>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.embedPlan) ...[
          const SubscriptionPlanCard(compact: true),
          const SizedBox(height: 14),
        ],
        DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(12),
          ),
          child: TabBar(
            controller: _tabs,
            indicatorSize: TabBarIndicatorSize.tab,
            dividerColor: Colors.transparent,
            tabs: [
              Tab(text: loc.voucherTabLogin),
              Tab(text: loc.voucherTabRegister),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: widget.wide ? 390 : 430,
          child: TabBarView(
            controller: _tabs,
            children: [
              _LoginForm(onDone: widget.onDone),
              _RegisterForm(
                onDone: widget.onDone,
                onRegisterStarted: widget.onRegisterStarted,
                onRegisterFailed: widget.onRegisterFailed,
                onRegisterSuccess: widget.onRegisterSuccess,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LoginForm extends StatefulWidget {
  const _LoginForm({required this.onDone});
  final VoidCallback onDone;

  @override
  State<_LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<_LoginForm> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  bool _rememberLogin = true;
  String? _error;

  /// البريد المحفوظ في كاش الدخول المحلي (للسماح بالدخول دون إنترنت بعد
  /// أول دخول ناجح). يظهر تلميح هادئ تحت الزرّ يخبر المستخدم بهذه الميزة.
  String _cachedOfflineEmail = '';

  @override
  void initState() {
    super.initState();
    final mgr = VoucherSessionManager.instance;
    mgr.rememberLoginEnabled().then((remember) async {
      if (!mounted) return;
      setState(() => _rememberLogin = remember);
      if (remember) {
        final e = await mgr.readRememberedEmail();
        if (mounted && e.isNotEmpty) _email.text = e;
      }
    });
    mgr.offlineCachedEmail().then((e) {
      if (mounted && e.isNotEmpty) {
        setState(() => _cachedOfflineEmail = e);
      }
    });
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final loc = AppLocalizations.of(context);
    final email = _email.text.trim();
    final pwd = _password.text;
    if (!email.contains('@') || pwd.length < 4) {
      setState(() => _error = loc.voucherValidationCredentials);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final mgr = VoucherSessionManager.instance;
    try {
      final result = await mgr.loginResilient(
        email: email,
        password: pwd,
        rememberLogin: _rememberLogin,
      );
      try {
        await mgr.refreshStatus();
      } on Object catch (e) {
        if (kDebugMode) {
          debugPrint('refreshStatus after login ignored: $e');
        }
      }
      if (!mounted) return;
      if (result.usedOffline) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(loc.voucherOfflineLoginSuccess),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      widget.onDone();
    } on VoucherOfflineException {
      if (!mounted) return;
      setState(() => _error = _connectionErrorMessage(loc));
    } on VoucherApiException catch (e) {
      if (!mounted) return;
      final cachedHint = _cachedOfflineEmail.isNotEmpty
          ? _cachedOfflineEmail
          : await mgr.offlineCachedEmail();
      final msg = switch (e.code) {
        'no_offline_cache' => loc.voucherOfflineNoCache,
        'offline_email_mismatch' =>
          loc.voucherOfflineEmailMismatch(cachedHint),
        _ => _humanError(loc, e.code),
      };
      setState(() => _error = msg);
    } on FormatException catch (e, st) {
      if (!mounted) return;
      if (kDebugMode) {
        debugPrint('Voucher login FormatException: $e\n$st');
      }
      // الدخول على السيرفر قد يكون نجح والجلسة حُفظت رغم خطأ لاحق في التخزين المحلي.
      if (mgr.hasSession) {
        widget.onDone();
        return;
      }
      setState(() => _error = loc.voucherErrorInvalidResponse);
    } catch (e, st) {
      if (!mounted) return;
      if (kDebugMode) {
        debugPrint('Voucher login unexpected: $e\n$st');
      }
      setState(() => _error = _connectionErrorMessage(loc));
    } finally {
      if (mounted) setState(() => _busy = false);
      try {
        final hint = await mgr.offlineCachedEmail();
        if (mounted && hint.isNotEmpty) {
          setState(() => _cachedOfflineEmail = hint);
        }
      } on Object {
        /* ignore */
      }
    }
  }

  Future<void> _forgotPassword() async {
    final loc = AppLocalizations.of(context);
    final emailCtrl = TextEditingController(text: _email.text.trim());
    var busy = false;
    String? dialogError;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          Future<void> submit() async {
            final em = emailCtrl.text.trim();
            if (!em.contains('@')) {
              setDialogState(() => dialogError = loc.authErrEmailInvalid);
              return;
            }
            setDialogState(() {
              busy = true;
              dialogError = null;
            });
            try {
              await VoucherSessionManager.instance.requestPasswordReset(
                email: em,
              );
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              if (!mounted) return;
              await showDialog<void>(
                context: context,
                builder: (dCtx) => AlertDialog(
                  title: Text(loc.authResetSentTitle),
                  content: Text(loc.authResetSentBody),
                  actions: [
                    FilledButton(
                      onPressed: () => Navigator.pop(dCtx),
                      child: Text(loc.close),
                    ),
                  ],
                ),
              );
            } on VoucherOfflineException {
              setDialogState(() => dialogError = loc.voucherErrorOffline);
            } on VoucherApiException catch (e) {
              setDialogState(() => dialogError = _humanError(loc, e.code));
            } on Object {
              setDialogState(() => dialogError = loc.authResetFail);
            } finally {
              if (ctx.mounted) setDialogState(() => busy = false);
            }
          }

          return AlertDialog(
            title: Text(loc.authResetPasswordTitle),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(loc.authResetPasswordHelp),
                  const SizedBox(height: 12),
                  TextField(
                    controller: emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: loc.voucherFieldEmail,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  if (dialogError != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      dialogError!,
                      style: TextStyle(color: Colors.red.shade800),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: busy ? null : () => Navigator.pop(ctx),
                child: Text(loc.cancel),
              ),
              FilledButton(
                onPressed: busy ? null : submit,
                child: busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(loc.authResetSubmit),
              ),
            ],
          );
        },
      ),
    );
    emailCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.username, AutofillHints.email],
            decoration: InputDecoration(
              labelText: loc.voucherFieldEmail,
              prefixIcon: const Icon(Icons.alternate_email),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            obscureText: _obscure,
            autofillHints: const [AutofillHints.password],
            decoration: InputDecoration(
              labelText: loc.voucherFieldPassword,
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 4),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(
              loc.voucherRememberLogin,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            value: _rememberLogin,
            onChanged: _busy
                ? null
                : (v) => setState(() => _rememberLogin = v ?? false),
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: _busy ? null : _forgotPassword,
              child: Text(loc.authForgotPassword),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                border: Border.all(color: Colors.red.shade200),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(_error!, style: TextStyle(color: Colors.red.shade900)),
            ),
          ],
          const SizedBox(height: 14),
          FilledButton.icon(
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.login),
            label: Text(loc.voucherActionLogin),
            onPressed: _busy ? null : _submit,
          ),
          if (_cachedOfflineEmail.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  Icons.wifi_off_rounded,
                  size: 14,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.55),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    loc.voucherOfflineHintAvailable(_cachedOfflineEmail),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.62),
                          height: 1.35,
                        ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _RegisterForm extends StatefulWidget {
  const _RegisterForm({
    required this.onDone,
    required this.onRegisterStarted,
    required this.onRegisterFailed,
    required this.onRegisterSuccess,
  });
  final VoidCallback onDone;
  final VoidCallback onRegisterStarted;
  final VoidCallback onRegisterFailed;
  final Future<void> Function(String fullName) onRegisterSuccess;

  @override
  State<_RegisterForm> createState() => _RegisterFormState();
}

class _RegisterFormState extends State<_RegisterForm> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _password2 = TextEditingController();
  final _fullName = TextEditingController();
  final _phone = TextEditingController();
  String _dialCode = '+970';
  bool _busy = false;
  bool _obscure = true;
  String? _error;
  String? _orgId;

  @override
  void initState() {
    super.initState();
    _loadOrgId();
  }

  Future<void> _loadOrgId() async {
    try {
      final db = await DatabaseService().database;
      final rows = await db.query('organizations', limit: 1);
      if (!mounted) return;
      setState(() {
        _orgId = rows.isEmpty ? null : (rows.first['id'] as String? ?? '');
      });
    } on Object {
      /* ignore */
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _password2.dispose();
    _fullName.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final loc = AppLocalizations.of(context);
    final email = _email.text.trim();
    final pwd = _password.text;
    final pwd2 = _password2.text;
    if (!email.contains('@') || pwd.length < 4) {
      setState(() => _error = loc.voucherValidationCredentials);
      return;
    }
    if (pwd != pwd2) {
      setState(() => _error = loc.voucherErrorPasswordMismatch);
      return;
    }
    final org = (_orgId ?? '').trim();
    if (org.isEmpty) {
      setState(() => _error = loc.voucherErrorMissingOrg);
      return;
    }
    final phoneDigits = _phone.text.replaceAll(RegExp(r'\D'), '');
    if (phoneDigits.length < 6) {
      setState(() => _error = loc.authErrPhoneInvalid);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final displayName = _fullName.text.trim();
    widget.onRegisterStarted();
    try {
      await VoucherSessionManager.instance.register(
        organizationId: org,
        email: email,
        password: pwd,
        fullName: displayName,
        phone: _phone.text.trim(),
        dialCode: _dialCode,
      );
      try {
        await VoucherSessionManager.instance.refreshStatus();
      } on Object catch (e) {
        if (kDebugMode) {
          debugPrint('refreshStatus after register ignored: $e');
        }
      }
      final name = displayName.isNotEmpty
          ? displayName
          : (VoucherSessionManager.instance.session?.fullName ?? '');
      await widget.onRegisterSuccess(name);
    } on VoucherOfflineException {
      widget.onRegisterFailed();
      if (!mounted) return;
      setState(() => _error = loc.voucherErrorOffline);
    } on VoucherApiException catch (e) {
      widget.onRegisterFailed();
      if (!mounted) return;
      setState(() => _error = _humanError(loc, e.code));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              labelText: loc.voucherFieldEmail,
              prefixIcon: const Icon(Icons.alternate_email),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _fullName,
            decoration: InputDecoration(
              labelText: loc.voucherFieldFullName,
              prefixIcon: const Icon(Icons.person_outline),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 4,
                child: DialCodePickerField(
                  dialCode: _dialCode,
                  onDialCodeChanged: (v) => setState(() => _dialCode = v),
                  labelText: loc.authDialCodeLabel,
                  enabled: !_busy,
                  showCountryNameInField: false,
                  englishUi:
                      Localizations.localeOf(context).languageCode == 'en',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 6,
                child: TextField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9\s\-]')),
                  ],
                  decoration: InputDecoration(
                    labelText: loc.voucherFieldPhone,
                    prefixIcon: const Icon(Icons.phone_outlined),
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _password,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: loc.voucherFieldPassword,
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _password2,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: loc.voucherFieldPasswordConfirm,
              prefixIcon: const Icon(Icons.lock_reset),
              border: const OutlineInputBorder(),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                border: Border.all(color: Colors.red.shade200),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(_error!, style: TextStyle(color: Colors.red.shade900)),
            ),
          ],
          const SizedBox(height: 14),
          FilledButton.icon(
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.person_add_alt),
            label: Text(loc.voucherActionRegister),
            onPressed: _busy ? null : _submit,
          ),
        ],
      ),
    );
  }
}

/* ---------------- Redeem voucher ---------------- */

class _RedeemVoucherPanel extends StatefulWidget {
  const _RedeemVoucherPanel({
    required this.onSuccess,
    this.embedPlan = true,
  });
  final VoidCallback onSuccess;
  final bool embedPlan;

  @override
  State<_RedeemVoucherPanel> createState() => _RedeemVoucherPanelState();
}

class _RedeemVoucherPanelState extends State<_RedeemVoucherPanel> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _pasteClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final t = (data?.text ?? '').trim();
    if (t.isEmpty) return;
    _code.text = t;
  }

  Future<void> _submit() async {
    final loc = AppLocalizations.of(context);
    final code = _code.text.trim();
    if (code.length < 12) {
      setState(() => _error = loc.voucherErrorInvalidCode);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await VoucherSessionManager.instance.redeem(code);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.voucherRedeemSuccess)),
      );
      widget.onSuccess();
    } on VoucherOfflineException {
      if (!mounted) return;
      setState(() => _error = loc.voucherErrorOffline);
    } on VoucherApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = _humanError(loc, e.code));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.embedPlan) ...[
          const SubscriptionPlanCard(compact: true),
          const SizedBox(height: 14),
        ],
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline,
                  color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  loc.voucherRedeemHint,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _code,
          textCapitalization: TextCapitalization.characters,
          style: const TextStyle(
            fontFamily: 'monospace',
            letterSpacing: 1.5,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
          decoration: InputDecoration(
            labelText: loc.voucherFieldCode,
            hintText: 'Miza-XXXX-XXXX-XXXX',
            prefixIcon: const Icon(Icons.confirmation_number_outlined),
            suffixIcon: IconButton(
              tooltip: loc.voucherPasteFromClipboard,
              icon: const Icon(Icons.content_paste),
              onPressed: _pasteClipboard,
            ),
            border: const OutlineInputBorder(),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              border: Border.all(color: Colors.red.shade200),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(_error!, style: TextStyle(color: Colors.red.shade900)),
          ),
        ],
        const SizedBox(height: 14),
        FilledButton.icon(
          icon: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check_circle_outline),
          label: Text(loc.voucherActionRedeem),
          onPressed: _busy ? null : _submit,
        ),
      ],
    );
  }
}

/* ---------------- Active subscription ---------------- */

class _ActiveSubscriptionPanel extends StatefulWidget {
  const _ActiveSubscriptionPanel({
    required this.status,
    required this.onChanged,
    this.session,
    this.allowReleaseDevice = true,
    this.wide = false,
  });
  final VoucherStatus status;
  final SubscriberAuthSession? session;
  final VoidCallback onChanged;
  final bool allowReleaseDevice;
  final bool wide;

  @override
  State<_ActiveSubscriptionPanel> createState() =>
      _ActiveSubscriptionPanelState();
}

class _ActiveSubscriptionPanelState extends State<_ActiveSubscriptionPanel> {
  Future<void> _copyCode() async {
    final loc = AppLocalizations.of(context);
    await Clipboard.setData(ClipboardData(text: widget.status.code));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        content: Text(loc.voucherActiveCopiedCode),
      ),
    );
  }

  Future<void> _openTransferFlow() async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DeviceTransferDialog(status: widget.status),
    );
    if (!mounted) return;
    if (ok == true) widget.onChanged();
  }

  List<Widget> _activeDetailsWidgets(VoucherStatus s) {
    return [
      _VoucherCodeCard(code: s.code, onCopy: _copyCode),
      const SizedBox(height: 12),
      _DeviceUsageCard(used: s.usedDevices, max: s.maxDevices),
      if (s.redeemedAt.isNotEmpty) ...[
        const SizedBox(height: 10),
        _RedeemedAtChip(value: s.redeemedAt),
      ],
      if (widget.allowReleaseDevice) ...[
        const SizedBox(height: 16),
        _TransferDeviceButton(onPressed: _openTransferFlow),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.status;
    final details = _activeDetailsWidgets(s);

    if (widget.wide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _ActivatedHeroCard(status: s, session: widget.session),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: details,
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _ActivatedHeroCard(status: s, session: widget.session),
        const SizedBox(height: 14),
        ...details,
      ],
    );
  }
}

/// بطاقة Hero الكبيرة لإظهار حالة «مُفعَّل» بشكل جذّاب وعصري.
///
/// • متدرّج لوني أخضر مع وهج ناعم.
/// • أيقونة تحقّق متحركة بنبض ولمعان شفاف.
/// • اسم المشترك + بريده.
class _ActivatedHeroCard extends StatefulWidget {
  const _ActivatedHeroCard({required this.status, this.session});
  final VoucherStatus status;
  final SubscriberAuthSession? session;

  @override
  State<_ActivatedHeroCard> createState() => _ActivatedHeroCardState();
}

class _ActivatedHeroCardState extends State<_ActivatedHeroCard>
    with TickerProviderStateMixin {
  late final AnimationController _entry = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  )..forward();
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _entry.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final session = widget.session;
    final subscriberName = (session?.fullName.trim().isNotEmpty == true)
        ? session!.fullName.trim()
        : (session?.email ?? '');
    final subEmail = session?.email ?? widget.status.email;
    final entry = CurvedAnimation(parent: _entry, curve: Curves.easeOutCubic);

    return FadeTransition(
      opacity: entry,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.06),
          end: Offset.zero,
        ).animate(entry),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF059669),
                Color(0xFF10B981),
                Color(0xFF34D399),
              ],
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: const [
              BoxShadow(
                color: Color(0x4010B981),
                blurRadius: 28,
                spreadRadius: 1,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _PulsingCheck(animation: _pulse),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.55),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.shield_rounded,
                                size: 13,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                loc.voucherActiveHeroBadge,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 11.5,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          loc.voucherActiveTitle,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                            height: 1.25,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                loc.voucherActiveHeroSubtitle,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  height: 1.45,
                ),
              ),
              if (subscriberName.isNotEmpty || subEmail.isNotEmpty) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    children: [
                      _SubscriberAvatarWithFlag(
                        letter: _initialFor(subscriberName.isNotEmpty
                            ? subscriberName
                            : subEmail),
                        dialCode: session?.dialCode ?? '',
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              loc.voucherActiveSubscriberLabel,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.85),
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.3,
                              ),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              subscriberName.isNotEmpty
                                  ? subscriberName
                                  : subEmail,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 13.5,
                              ),
                            ),
                            if (subscriberName.isNotEmpty &&
                                subEmail.isNotEmpty &&
                                subscriberName != subEmail)
                              Text(
                                subEmail,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.82),
                                  fontWeight: FontWeight.w500,
                                  fontSize: 11.5,
                                ),
                              ),
                            if (countryFromDial(session?.dialCode) !=
                                null) ...[
                              const SizedBox(height: 4),
                              _ActivatedCountryChip(
                                country: countryFromDial(session!.dialCode)!,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _initialFor(String s) {
    final t = s.trim();
    if (t.isEmpty) return '·';
    final ch = t.runes.isEmpty ? '·' : String.fromCharCode(t.runes.first);
    return ch.toUpperCase();
  }
}

/// أفاتار مصغّر داخل بطاقة «مفعَّل» مع شارة علم دولة المشترك في الزاوية.
/// عند عدم توفّر `dialCode` (جلسة قديمة) تُخفى الشارة فقط دون كسر التخطيط.
class _SubscriberAvatarWithFlag extends StatelessWidget {
  const _SubscriberAvatarWithFlag({
    required this.letter,
    required this.dialCode,
  });

  final String letter;
  final String dialCode;

  @override
  Widget build(BuildContext context) {
    final hasFlag = countryFromDial(dialCode) != null;
    return SizedBox(
      width: 40,
      height: 40,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                letter,
                style: const TextStyle(
                  color: Color(0xFF047857),
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                ),
              ),
            ),
          ),
          if (hasFlag)
            PositionedDirectional(
              bottom: -4,
              end: -4,
              child: CountryFlag(
                dialCode: dialCode,
                size: 18,
                shape: CountryFlagShape.circle,
                borderWidth: 2,
              ),
            ),
        ],
      ),
    );
  }
}

/// شريحة مدمجة لاسم دولة المشترك مع علم صغير. تظهر داخل بطاقة «مفعَّل»
/// أسفل اسم/بريد المشترك مباشرة.
class _ActivatedCountryChip extends StatelessWidget {
  const _ActivatedCountryChip({required this.country});
  final CountryInfo country;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(4, 2, 8, 2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.32)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CountryFlag(
            dialCode: country.dialCode,
            size: 14,
            shape: CountryFlagShape.circle,
            borderWidth: 1,
            showShadow: false,
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              '${country.name(loc.isEnglish)}  ${country.dialCode}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 10.5,
                letterSpacing: 0.1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Check mark dispatched with a soft pulsing ring (no shaders required).
class _PulsingCheck extends StatelessWidget {
  const _PulsingCheck({required this.animation});
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final t = animation.value;
        final ringSize = 50 + (t * 6);
        final ringOpacity = (1 - t) * 0.55;
        return SizedBox(
          width: 60,
          height: 60,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: ringSize,
                height: ringSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: ringOpacity * 0.4),
                ),
              ),
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.check_rounded,
                  color: Color(0xFF059669),
                  size: 30,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _VoucherCodeCard extends StatelessWidget {
  const _VoucherCodeCard({required this.code, required this.onCopy});
  final String code;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.confirmation_number_outlined,
            color: cs.primary,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  loc.voucherActiveCodeLabel,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: cs.onSurfaceVariant,
                        letterSpacing: 0.4,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  code,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w800,
                    fontSize: 14.5,
                    letterSpacing: 1.4,
                    color: cs.onSurface,
                  ),
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: onCopy,
            icon: const Icon(Icons.copy_rounded, size: 16),
            label: Text(loc.voucherCopyAction),
            style: TextButton.styleFrom(
              foregroundColor: cs.primary,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              minimumSize: const Size(0, 36),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeviceUsageCard extends StatelessWidget {
  const _DeviceUsageCard({required this.used, required this.max});
  final int used;
  final int max;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final clampedMax = max <= 0 ? 1 : max;
    final ratio = (used / clampedMax).clamp(0.0, 1.0);
    final remaining = (max - used).clamp(0, max);
    Color barColor;
    if (ratio >= 1) {
      barColor = cs.error;
    } else if (ratio >= 0.66) {
      barColor = const Color(0xFFF59E0B);
    } else {
      barColor = const Color(0xFF10B981);
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.devices_other_rounded,
                  size: 18, color: cs.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  loc.voucherActiveDevicesUsedOfMax,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: cs.onSurfaceVariant,
                      ),
                ),
              ),
              Text(
                '$used / $max',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 14.5,
                  color: cs.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: ratio),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) {
                return LinearProgressIndicator(
                  value: value,
                  minHeight: 8,
                  backgroundColor: cs.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation<Color>(barColor),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.bolt_rounded,
                  size: 14,
                  color: const Color(0xFF10B981).withValues(alpha: 0.85)),
              const SizedBox(width: 4),
              Text(
                '${loc.voucherActiveSlotsFreeLabel}: $remaining',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: cs.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RedeemedAtChip extends StatelessWidget {
  const _RedeemedAtChip({required this.value});
  final String value;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.event_available_rounded,
            size: 16, color: cs.onSurfaceVariant),
        const SizedBox(width: 6),
        Text(
          '${loc.voucherActiveRedeemedAt}: ',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
        ),
        Flexible(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
        ),
      ],
    );
  }
}

class _TransferDeviceButton extends StatelessWidget {
  const _TransferDeviceButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        icon: const Icon(Icons.swap_horiz_rounded),
        label: Text(loc.voucherTransferOpenButton),
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: cs.primary,
          side: BorderSide(color: cs.primary.withValues(alpha: 0.65), width: 1.4),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 13.5,
          ),
        ),
      ),
    );
  }
}

/* ---------------- Secure device transfer dialog ---------------- */

/// حوار آمن وحديث لنقل التفعيل من هذا الجهاز إلى جهاز آخر.
///
/// المراحل:
///  1. شرح خطوات النقل (3 خطوات).
///  2. إعادة إدخال كلمة المرور للمشترك (طبقة أمان).
///  3. تحرير الجهاز ثم عرض رمز القسيمة جاهزاً للنسخ.
///
/// يُرجع `true` عند نجاح التحرير (لتُحدِّث الواجهة الأم حالة الاشتراك).
class _DeviceTransferDialog extends StatefulWidget {
  const _DeviceTransferDialog({required this.status});
  final VoucherStatus status;

  @override
  State<_DeviceTransferDialog> createState() => _DeviceTransferDialogState();
}

enum _TransferStage { intro, releasing, done }

class _DeviceTransferDialogState extends State<_DeviceTransferDialog> {
  final _passwordCtrl = TextEditingController();
  final _passwordFocus = FocusNode();
  bool _obscure = true;
  bool _busy = false;
  String? _error;
  _TransferStage _stage = _TransferStage.intro;

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _confirmAndRelease() async {
    final loc = AppLocalizations.of(context);
    final mgr = VoucherSessionManager.instance;
    final session = mgr.session;
    final pwd = _passwordCtrl.text;
    if (session == null) {
      setState(() => _error = loc.voucherErrorGeneric);
      return;
    }
    if (pwd.length < 4) {
      setState(() => _error = loc.voucherValidationCredentials);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _stage = _TransferStage.releasing;
    });
    try {
      // طبقة الأمان: نُعيد المصادقة بكلمة المرور قبل تحرير الجهاز.
      // هذا يحمي من سيناريو وصول شخص ما إلى الجهاز لجلسةٍ ضائعة.
      await mgr.login(
        email: session.email,
        password: pwd,
        organizationId: session.organizationId,
      );
      await mgr.releaseThisDevice();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _stage = _TransferStage.done;
      });
    } on VoucherOfflineException {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _stage = _TransferStage.intro;
        _error = loc.voucherTransferOnlineRequired;
      });
    } on VoucherApiException catch (e) {
      if (!mounted) return;
      final isPwd =
          e.code == 'unauthorized' || e.code == 'invalid_credentials';
      setState(() {
        _busy = false;
        _stage = _TransferStage.intro;
        _error = isPwd
            ? loc.voucherTransferWrongPassword
            : _humanError(loc, e.code);
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _stage = _TransferStage.intro;
        _error = loc.voucherErrorGeneric;
      });
    }
  }

  Future<void> _copyCode() async {
    final loc = AppLocalizations.of(context);
    await Clipboard.setData(ClipboardData(text: widget.status.code));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        content: Text(loc.voucherActiveCopiedCode),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
            child: _stage == _TransferStage.done
                ? _buildDoneStage(loc, cs)
                : _buildIntroStage(loc, cs),
          ),
        ),
      ),
    );
  }

  Widget _buildIntroStage(AppLocalizations loc, ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.swap_horiz_rounded, color: cs.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    loc.voucherTransferTitle,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    loc.voucherTransferIntro,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          height: 1.45,
                        ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: loc.cancel,
              icon: const Icon(Icons.close_rounded),
              onPressed: _busy ? null : () => Navigator.of(context).pop(false),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _StepsCard(steps: [
          loc.voucherTransferStep1,
          loc.voucherTransferStep2,
          loc.voucherTransferStep3,
        ]),
        const SizedBox(height: 14),
        Text(
          loc.voucherTransferConfirmPasswordHint,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                height: 1.45,
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _passwordCtrl,
          focusNode: _passwordFocus,
          obscureText: _obscure,
          enabled: !_busy,
          autofocus: true,
          autofillHints: const [AutofillHints.password],
          onSubmitted: (_) => _confirmAndRelease(),
          decoration: InputDecoration(
            labelText: loc.voucherTransferConfirmPasswordLabel,
            prefixIcon: const Icon(Icons.lock_outline_rounded),
            suffixIcon: IconButton(
              icon: Icon(_obscure
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
            border: const OutlineInputBorder(),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          _ErrorBanner(text: _error!),
        ],
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: cs.tertiaryContainer.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: cs.tertiary.withValues(alpha: 0.25), width: 1),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.lock_person_rounded,
                  size: 18, color: cs.tertiary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  loc.voucherTransferSecurityNote,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        height: 1.45,
                        fontWeight: FontWeight.w600,
                        color: cs.onTertiaryContainer,
                      ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed:
                    _busy ? null : () => Navigator.of(context).pop(false),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(loc.cancel),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                onPressed: _busy ? null : _confirmAndRelease,
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.swap_horiz_rounded),
                label: Text(loc.voucherTransferCta),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  textStyle: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 13.5),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDoneStage(AppLocalizations loc, ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.6, end: 1),
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutBack,
            builder: (context, value, _) {
              return Transform.scale(
                scale: value,
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [Color(0xFF10B981), Color(0xFF059669)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Color(0x4010B981),
                        blurRadius: 20,
                        spreadRadius: 1,
                        offset: Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.check_rounded,
                      color: Colors.white, size: 42),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 14),
        Text(
          loc.voucherTransferDoneTitle,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
        ),
        const SizedBox(height: 6),
        Text(
          loc.voucherTransferDoneSubtitle,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                height: 1.5,
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cs.outline.withValues(alpha: 0.3)),
          ),
          child: Column(
            children: [
              Text(
                widget.status.code,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  letterSpacing: 2.4,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                onPressed: _copyCode,
                icon: const Icon(Icons.copy_rounded, size: 16),
                label: Text(loc.voucherCopyAction),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline_rounded,
                size: 16, color: cs.onSurfaceVariant),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                loc.voucherTransferCodeCopyHint,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      height: 1.5,
                    ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(true),
          icon: const Icon(Icons.check_circle_outline_rounded),
          label: Text(loc.voucherTransferDoneFinish),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: const TextStyle(
                fontWeight: FontWeight.w800, fontSize: 13.5),
          ),
        ),
      ],
    );
  }
}

class _StepsCard extends StatelessWidget {
  const _StepsCard({required this.steps});
  final List<String> steps;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.menu_book_rounded, size: 16, color: cs.primary),
              const SizedBox(width: 6),
              Text(
                loc.voucherTransferStepsTitle,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: cs.primary,
                  fontSize: 12.5,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < steps.length; i++) ...[
            _NumberedStep(index: i + 1, text: steps[i]),
            if (i < steps.length - 1) const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _NumberedStep extends StatelessWidget {
  const _NumberedStep({required this.index, required this.text});
  final int index;
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: cs.primary,
          ),
          child: Text(
            '$index',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 12.5,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    height: 1.5,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded,
              size: 18, color: Colors.red.shade700),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: Colors.red.shade800,
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _connectionErrorMessage(AppLocalizations loc) {
  final base = RemoteSignupConfig.apiBaseUrl;
  if (base.isEmpty) {
    return loc.voucherErrorServerDisabled;
  }
  if (kDebugMode) {
    return '${loc.voucherErrorOffline}\n($base)';
  }
  return loc.voucherErrorOffline;
}

String _humanError(AppLocalizations loc, String code) {
  switch (code) {
    case 'invalid_credentials':
    case 'unauthorized':
      return loc.voucherErrorWrongCredentials;
    case 'invalid_voucher':
    case 'voucher_not_found':
      return loc.voucherErrorInvalidCode;
    case 'voucher_revoked':
      return loc.voucherErrorRevoked;
    case 'voucher_bound_to_other':
      return loc.voucherErrorBoundToOther;
    case 'devices_limit_reached':
      return loc.voucherErrorMaxDevices;
    case 'desktop_limit_reached':
      return loc.voucherErrorDesktopLimit;
    case 'android_limit_reached':
      return loc.voucherErrorAndroidLimit;
    case 'validation':
      return loc.authErrPhoneInvalid;
    case 'weak_password':
      return loc.voucherErrorWeakPassword;
    case 'wrong_password':
      return loc.voucherErrorWrongPassword;
    case 'activation_server_disabled':
      return loc.voucherErrorServerDisabled;
    case 'forbidden':
      return loc.voucherErrorForbidden;
    case 'invalid_response':
      return loc.voucherErrorInvalidResponse;
    case 'invalid_api_url':
      return loc.voucherErrorWrongApiUrl;
    case 'voucher_offline':
      return loc.voucherErrorOffline;
    case 'email_not_found':
      return loc.authResetEmailNotFound;
    case 'smtp_missing':
      return loc.authResetSmtpMissing;
    case 'mail_failed':
      return loc.authResetFail;
    default:
      return loc.voucherErrorGeneric;
  }
}
