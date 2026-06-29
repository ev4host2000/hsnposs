import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mizapos_mobile/l10n/app_localizations.dart';
import 'package:mizapos_mobile/theme/app_design.dart';

typedef SessionRoleColors = ({Color bg, Color fg});

/// ألوان وأيقونات أدوار فريق العمل (موحّدة في الواجهة).
abstract final class SessionRolePalette {
  static SessionRoleColors colorsFor(String role) {
    switch (role.trim().toLowerCase()) {
      case 'owner':
        return (bg: const Color(0xFFFFF7ED), fg: const Color(0xFFC2410C));
      case 'branch_manager':
        return (bg: const Color(0xFFE0F2FE), fg: const Color(0xFF075985));
      case 'accountant':
        return (bg: const Color(0xFFEDE9FE), fg: const Color(0xFF5B21B6));
      case 'distributor':
        return (bg: const Color(0xFFFFE4E6), fg: const Color(0xFFBE123C));
      case 'guest':
        return (bg: const Color(0xFFF1F5F9), fg: const Color(0xFF475569));
      default:
        return (bg: const Color(0xFFDCFCE7), fg: const Color(0xFF166534));
    }
  }

  static IconData iconFor(String role) {
    switch (role.trim().toLowerCase()) {
      case 'owner':
        return Icons.admin_panel_settings_rounded;
      case 'branch_manager':
        return Icons.store_rounded;
      case 'accountant':
        return Icons.calculate_rounded;
      case 'distributor':
        return Icons.local_shipping_rounded;
      case 'guest':
        return Icons.person_outline_rounded;
      default:
        return Icons.point_of_sale_rounded;
    }
  }

  static const staffRoles = [
    'owner',
    'accountant',
    'cashier',
    'distributor',
  ];
}

/// شارة الدور (مدير، محاسب، …).
class SessionRoleChip extends StatelessWidget {
  const SessionRoleChip({
    super.key,
    required this.role,
    required this.loc,
    this.compact = false,
    this.lightOnDark = false,
  });

  final String role;
  final AppLocalizations loc;
  final bool compact;
  final bool lightOnDark;

  @override
  Widget build(BuildContext context) {
    final colors = SessionRolePalette.colorsFor(role);
    final label = role.trim().toLowerCase() == 'guest'
        ? loc.sessionIdentityGuestLabel
        : loc.securityRole(role);

    if (lightOnDark) {
      final colors = SessionRolePalette.colorsFor(role);
      return Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 6 : 7,
          vertical: compact ? 2 : 3,
        ),
        decoration: BoxDecoration(
          color: colors.bg.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: colors.fg.withValues(alpha: 0.22)),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: compact ? 9.5 : 10,
            fontWeight: FontWeight.w800,
            color: colors.fg,
            height: 1.1,
          ),
        ),
      );
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: colors.bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: compact ? 11 : 12,
          fontWeight: FontWeight.w700,
          color: colors.fg,
          height: 1.1,
        ),
      ),
    );
  }
}

/// شريط مضغوط: اسم المستخدم + الدور (للشريط العلوي).
class SessionIdentityBar extends StatelessWidget {
  const SessionIdentityBar({
    super.key,
    required this.displayName,
    required this.role,
    required this.loc,
    required this.onTap,
    this.compact = false,
    this.lightOnDark = false,
    /// إخفاء الكنية (الجوال — تُعرض في قائمة ⋮).
    this.hideRole = false,
    /// الاسم والكنية في سطر واحد (الحاسوب).
    this.inlineRole = false,
    /// بدون إطار/خلفية (شريط ويندوز العلوي).
    this.borderless = false,
  });

  final String displayName;
  final String role;
  final AppLocalizations loc;
  final VoidCallback onTap;
  final bool compact;
  final bool lightOnDark;
  final bool hideRole;
  final bool inlineRole;
  final bool borderless;

  @override
  Widget build(BuildContext context) {
    final name = displayName.trim().isEmpty ? '—' : displayName.trim();
    final initialRunes = name.runes;
    final initial = initialRunes.isEmpty
        ? '?'
        : String.fromCharCode(initialRunes.first).toUpperCase();

    final bg = lightOnDark
        ? Colors.white.withValues(alpha: 0.14)
        : Theme.of(context).colorScheme.surfaceContainerHighest;
    final border = lightOnDark
        ? Colors.white.withValues(alpha: 0.28)
        : Theme.of(context).colorScheme.outline.withValues(alpha: 0.18);
    final nameColor = lightOnDark
        ? Colors.white
        : Theme.of(context).colorScheme.onSurface;
    final chevronColor = lightOnDark
        ? Colors.white.withValues(alpha: 0.75)
        : Theme.of(context).colorScheme.onSurfaceVariant;

    final roleColors = SessionRolePalette.colorsFor(role);

    final content = Row(
      mainAxisSize: borderless ? MainAxisSize.min : MainAxisSize.max,
      children: [
        if (!borderless) ...[
          CircleAvatar(
            radius: compact ? 12 : (lightOnDark ? 13 : 15),
            backgroundColor: lightOnDark
                ? roleColors.bg.withValues(alpha: 0.95)
                : roleColors.bg,
            child: Text(
              initial,
              style: TextStyle(
                fontSize: compact ? 10.5 : 12,
                fontWeight: FontWeight.w800,
                color: roleColors.fg,
              ),
            ),
          ),
          SizedBox(width: compact ? 5 : 7),
        ],
        if (borderless)
          Flexible(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: nameColor,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SessionRoleChip(
                  role: role,
                  loc: loc,
                  compact: true,
                  lightOnDark: lightOnDark,
                ),
              ],
            ),
          )
        else
          Expanded(
            child: hideRole
                ? Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: nameColor,
                      fontSize: compact ? 10 : 11,
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                    ),
                  )
                : inlineRole
                    ? Row(
                        children: [
                          Flexible(
                            child: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: nameColor,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                height: 1.1,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: SessionRoleChip(
                              role: role,
                              loc: loc,
                              compact: true,
                              lightOnDark: lightOnDark,
                            ),
                          ),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: nameColor,
                              fontSize: compact ? 10 : 11,
                              fontWeight: FontWeight.w700,
                              height: 1.1,
                            ),
                          ),
                          const SizedBox(height: 2),
                          SessionRoleChip(
                            role: role,
                            loc: loc,
                            compact: true,
                            lightOnDark: lightOnDark,
                          ),
                        ],
                      ),
          ),
        const SizedBox(width: 4),
        Icon(
          Icons.expand_more_rounded,
          size: borderless ? 18 : (compact ? 15 : 17),
          color: chevronColor,
        ),
      ],
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(borderless ? 8 : 10),
        child: Tooltip(
          message: loc.sessionIdentityTapTooltip,
          child: borderless
              ? Padding(
                  padding: const EdgeInsetsDirectional.only(
                    start: 8,
                    end: 4,
                    top: 6,
                    bottom: 6,
                  ),
                  child: content,
                )
              : Container(
                  constraints: BoxConstraints(
                    maxWidth: hideRole
                        ? (compact ? 112 : 140)
                        : (inlineRole ? 300 : (compact ? 148 : 200)),
                    minHeight: lightOnDark ? 40 : 0,
                  ),
                  padding: EdgeInsetsDirectional.only(
                    start: lightOnDark ? 6 : (compact ? 4 : 6),
                    end: lightOnDark ? 4 : (compact ? 4 : 6),
                    top: lightOnDark ? 5 : (compact ? 4 : 5),
                    bottom: lightOnDark ? 5 : (compact ? 4 : 5),
                  ),
                  decoration: BoxDecoration(
                    color: lightOnDark
                        ? Colors.white.withValues(alpha: 0.14)
                        : bg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: lightOnDark
                          ? Colors.white.withValues(alpha: 0.32)
                          : border,
                    ),
                  ),
                  child: content,
                ),
        ),
      ),
    );
  }
}

/// بطاقة ترحيب أكبر (مثلاً في مركز الموزّع).
class SessionIdentityBanner extends StatelessWidget {
  const SessionIdentityBanner({
    super.key,
    required this.displayName,
    required this.role,
    required this.loc,
    required this.onTap,
  });

  final String displayName;
  final String role;
  final AppLocalizations loc;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name = displayName.trim().isEmpty ? '—' : displayName.trim();
    final colors = SessionRolePalette.colorsFor(role);
    final initialRunes = name.runes;
    final initial = initialRunes.isEmpty
        ? '?'
        : String.fromCharCode(initialRunes.first).toUpperCase();

    return Material(
      color: scheme.surfaceContainerLow,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDesign.radiusLg),
        side: BorderSide(color: scheme.outline.withValues(alpha: 0.12)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppDesign.radiusLg),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: colors.bg,
                child: Text(
                  initial,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: colors.fg,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 4),
                    SessionRoleChip(role: role, loc: loc),
                  ],
                ),
              ),
              Icon(Icons.swap_horiz_rounded, color: scheme.primary),
            ],
          ),
        ),
      ),
    );
  }
}

enum SessionIdentitySheetAction {
  switchAccount,
  signOut,
  openMyAccount,
}

/// نتيجة لوحة الهوية: إجراء قائمة أو اختيار دور للدخول السريع.
class SessionIdentityPick {
  const SessionIdentityPick._({this.action, this.role});

  final SessionIdentitySheetAction? action;
  final String? role;

  factory SessionIdentityPick.menu(SessionIdentitySheetAction action) =>
      SessionIdentityPick._(action: action);

  factory SessionIdentityPick.role(String role) =>
      SessionIdentityPick._(role: role.trim().toLowerCase());
}

Future<SessionIdentityPick?> showSessionIdentitySheet({
  required BuildContext context,
  required AppLocalizations loc,
  required String displayName,
  required String role,
  required bool isStaffSignedIn,
  bool showSwitchAccount = true,
}) {
  final mq = MediaQuery.sizeOf(context);
  final maxW = math.min(460.0, mq.width - 20);

  return showModalBottomSheet<SessionIdentityPick>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetCtx) {
      final scheme = Theme.of(sheetCtx).colorScheme;
      final name = displayName.trim().isEmpty ? '—' : displayName.trim();
      final colors = SessionRolePalette.colorsFor(role);
      final initialRunes = name.runes;
      final initial = initialRunes.isEmpty
          ? '?'
          : String.fromCharCode(initialRunes.first).toUpperCase();

      Widget staffAction({
        required IconData icon,
        required String label,
        required SessionIdentitySheetAction value,
        Color? tint,
      }) {
        final c = tint ?? scheme.primary;
        return Expanded(
          child: Material(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              onTap: () => Navigator.of(sheetCtx)
                  .pop(SessionIdentityPick.menu(value)),
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, color: c, size: 28),
                    const SizedBox(height: 8),
                    Text(
                      label,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: c,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }

      return Padding(
        padding: EdgeInsets.only(
          left: 10,
          right: 10,
          bottom: MediaQuery.viewInsetsOf(sheetCtx).bottom + 12,
        ),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxW),
            child: Material(
              color: scheme.surface,
              elevation: 16,
              shadowColor: Colors.black.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(24),
              clipBehavior: Clip.antiAlias,
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 10),
                    Container(
                      width: 44,
                      height: 4,
                      decoration: BoxDecoration(
                        color: scheme.outline.withValues(alpha: 0.28),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: AlignmentDirectional.topStart,
                          end: AlignmentDirectional.bottomEnd,
                          colors: [
                            Color.lerp(colors.bg, colors.fg, 0.24)!,
                            Color.lerp(colors.bg, colors.fg, 0.10)!,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: colors.fg.withValues(alpha: 0.18),
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          CircleAvatar(
                            radius: 32,
                            backgroundColor:
                                scheme.surface.withValues(alpha: 0.72),
                            child: Text(
                              initial,
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                color: colors.fg,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            isStaffSignedIn
                                ? name
                                : loc.sessionIdentityGuestPrompt,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(sheetCtx)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 8),
                          SessionRoleChip(role: role, loc: loc),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
                      child: Text(
                        isStaffSignedIn
                            ? (showSwitchAccount
                                ? loc.sessionIdentitySwitchHint
                                : loc.sessionIdentitySignOutOnlyHint)
                            : loc.sessionIdentityPickRoleHint,
                        textAlign: TextAlign.center,
                        style: Theme.of(sheetCtx).textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                              height: 1.4,
                            ),
                      ),
                    ),
                    if (isStaffSignedIn) ...[
                      const SizedBox(height: 14),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: Row(
                          children: [
                            staffAction(
                              icon: Icons.manage_accounts_rounded,
                              label: loc.menuSignedInAccountEntry,
                              value: SessionIdentitySheetAction.openMyAccount,
                            ),
                            if (showSwitchAccount) ...[
                              const SizedBox(width: 8),
                              staffAction(
                                icon: Icons.swap_horiz_rounded,
                                label: loc.accountSwitchAccountButton,
                                value: SessionIdentitySheetAction.switchAccount,
                              ),
                            ],
                            const SizedBox(width: 8),
                            staffAction(
                              icon: Icons.logout_rounded,
                              label: loc.logout,
                              value: SessionIdentitySheetAction.signOut,
                              tint: scheme.error,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                    ],
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            loc.sessionIdentityRolesLegend,
                            textAlign: TextAlign.center,
                            style: Theme.of(sheetCtx)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 12),
                          GridView.count(
                            crossAxisCount: 2,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            mainAxisSpacing: 10,
                            crossAxisSpacing: 10,
                            childAspectRatio: 1.15,
                            children: [
                              for (final r in SessionRolePalette.staffRoles)
                                _RolePickTile(
                                  role: r,
                                  loc: loc,
                                  onTap: () => Navigator.of(sheetCtx)
                                      .pop(SessionIdentityPick.role(r)),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _RolePickTile extends StatelessWidget {
  const _RolePickTile({
    required this.role,
    required this.loc,
    required this.onTap,
  });

  final String role;
  final AppLocalizations loc;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = SessionRolePalette.colorsFor(role);
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [
                colors.bg,
                Color.lerp(colors.bg, scheme.surface, 0.35)!,
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.fg.withValues(alpha: 0.14)),
            boxShadow: [
              BoxShadow(
                color: colors.fg.withValues(alpha: 0.08),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: scheme.surface.withValues(alpha: 0.75),
                  child: Icon(
                    SessionRolePalette.iconFor(role),
                    color: colors.fg,
                    size: 28,
                  ),
                ),
                const Spacer(),
                Text(
                  loc.securityRole(role),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: colors.fg,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      loc.settingsLoginCardTitle,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: colors.fg.withValues(alpha: 0.75),
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      Icons.arrow_forward_rounded,
                      size: 14,
                      color: colors.fg.withValues(alpha: 0.75),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
