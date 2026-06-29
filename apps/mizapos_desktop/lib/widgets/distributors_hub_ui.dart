import 'package:flutter/material.dart';
import 'package:mizapos_desktop/screens/shared/ui_style_tokens.dart';

/// ألوان وتدرجات لواجهة منظومة الموزعون.
abstract final class DistributorsHubPalette {
  static const fieldOrders = [Color(0xFF60A5FA), Color(0xFF2563EB)];
  static const movements = [Color(0xFF94A3B8), Color(0xFF475569)];
  static const loadTruck = [Color(0xFF34D399), Color(0xFF059669)];
  static const publish = [Color(0xFF2DD4BF), Color(0xFF0D9488)];
  static const returns = [Color(0xFFF87171), Color(0xFFDC2626)];
  static const expenses = [Color(0xFF4ADE80), Color(0xFF16A34A)];
  static const reports = [Color(0xFFA78BFA), Color(0xFF7C3AED)];
  static const notes = [Color(0xFFF9A8D4), Color(0xFFEC4899)];
  static const sync = [Color(0xFFCBD5E1), Color(0xFF64748B)];
  static const hubHero = [Color(0xFF1E3A5F), Color(0xFF1D4ED8), Color(0xFF6D28D9)];
  static const intro = Color(0xFF3B82F6);

  static const statIndigo = Color(0xFF6366F1);
  static const statAmber = Color(0xFFF59E0B);
  static const statEmerald = Color(0xFF10B981);
  static const statViolet = Color(0xFF8B5CF6);

  static Color tint(Color c, {double alpha = 0.1}) =>
      c.withValues(alpha: alpha);

  static LinearGradient gradient(List<Color> colors) => LinearGradient(
        begin: AlignmentDirectional.topStart,
        end: AlignmentDirectional.bottomEnd,
        colors: colors.length >= 2 ? colors : [colors.first, colors.first],
      );
}

/// مقاس موحّد لبطاقات الإحصائيات ومربع التقارير في صفحة الموزعون.
const double kDistributorsHubStatTileWidth = 176;
const double kDistributorsHubStatTileHeight = 118;

class DistributorsGradientAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  const DistributorsGradientAppBar({
    super.key,
    required this.title,
    this.subtitle,
    this.gradientColors = DistributorsHubPalette.hubHero,
    this.actions,
    this.leading,
  });

  final String title;
  final String? subtitle;
  final List<Color> gradientColors;
  final List<Widget>? actions;
  final Widget? leading;

  @override
  Size get preferredSize => Size.fromHeight(subtitle == null ? 56 : 64);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      leading: leading,
      actions: actions,
      backgroundColor: ModuleScreenChrome.neutralAppBar,
      foregroundColor: ModuleScreenChrome.neutralTitle,
      iconTheme: const IconThemeData(color: ModuleScreenChrome.neutralTitle),
      shape: Border(
        bottom: BorderSide(
          color: Color.lerp(
            ModuleScreenChrome.neutralAppBar,
            ModuleScreenChrome.neutralBody,
            0.72,
          )!,
          width: 1,
        ),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 17,
              color: ModuleScreenChrome.neutralTitle,
            ),
          ),
          if (subtitle != null)
            Text(
              subtitle!,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.white.withValues(alpha: 0.78),
              ),
            ),
        ],
      ),
    );
  }
}

class DistributorsHubTile extends StatelessWidget {
  const DistributorsHubTile({
    super.key,
    required this.gradient,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge,
    this.busy = false,
  });

  final List<Color> gradient;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final int? badge;
  final bool busy;

  Color get _accent => gradient.last;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.55)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: busy ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: DistributorsHubPalette.tint(_accent, alpha: 0.12),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: busy
                    ? Padding(
                        padding: const EdgeInsets.all(10),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: _accent,
                        ),
                      )
                    : Icon(icon, color: _accent, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            height: 1.35,
                          ),
                    ),
                  ],
                ),
              ),
              if (badge != null && badge! > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: scheme.errorContainer.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$badge',
                    style: TextStyle(
                      color: scheme.onErrorContainer,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 4),
              Icon(
                Directionality.of(context) == TextDirection.rtl
                    ? Icons.chevron_left_rounded
                    : Icons.chevron_right_rounded,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.45),
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DistributorsHeroBanner extends StatelessWidget {
  const DistributorsHeroBanner({
    super.key,
    required this.title,
    required this.body,
    required this.badgeLabel,
  });

  final String title;
  final String body;
  final String badgeLabel;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: BoxDecoration(
          gradient: DistributorsHubPalette.gradient(
            DistributorsHubPalette.hubHero,
          ),
          boxShadow: [
            BoxShadow(
              color: DistributorsHubPalette.hubHero.last.withValues(alpha: 0.28),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              right: -24,
              top: -28,
              child: Icon(
                Icons.local_shipping_rounded,
                size: 140,
                color: Colors.white.withValues(alpha: 0.07),
              ),
            ),
            Positioned(
              left: -18,
              bottom: -22,
              child: Icon(
                Icons.route_rounded,
                size: 100,
                color: Colors.white.withValues(alpha: 0.05),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.28),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.hub_rounded,
                          size: 14,
                          color: Colors.white.withValues(alpha: 0.95),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          badgeLabel,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.95),
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    title,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          height: 1.15,
                          letterSpacing: -0.3,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    body,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.88),
                          height: 1.55,
                          fontWeight: FontWeight.w500,
                        ),
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

/// عنوان قسم في صفحة الموزعون.
class DistributorsSectionHeader extends StatelessWidget {
  const DistributorsSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
  });

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
              ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.4,
                ),
          ),
        ],
      ],
    );
  }
}

class DistributorsSyncFlowCard extends StatelessWidget {
  const DistributorsSyncFlowCard({
    super.key,
    required this.title,
    required this.hint,
    required this.desktopLabel,
    required this.serverLabel,
    required this.mobileLabel,
    required this.desktopCaption,
    required this.serverCaption,
    required this.mobileCaption,
  });

  final String title;
  final String hint;
  final String desktopLabel;
  final String serverLabel;
  final String mobileLabel;
  final String desktopCaption;
  final String serverCaption;
  final String mobileCaption;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DistributorsModernPanel(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            hint,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.45,
                ),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, c) {
              final vertical = c.maxWidth < 520;
              if (vertical) {
                return Column(
                  children: [
                    _SyncNode(
                      icon: Icons.desktop_windows_outlined,
                      label: desktopLabel,
                      caption: desktopCaption,
                    ),
                    _SyncArrow(down: true),
                    _SyncNode(
                      icon: Icons.cloud_outlined,
                      label: serverLabel,
                      caption: serverCaption,
                    ),
                    _SyncArrow(down: true),
                    _SyncNode(
                      icon: Icons.smartphone_outlined,
                      label: mobileLabel,
                      caption: mobileCaption,
                    ),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(
                    child: _SyncNode(
                      icon: Icons.desktop_windows_outlined,
                      label: desktopLabel,
                      caption: desktopCaption,
                    ),
                  ),
                  const _SyncArrow(),
                  Expanded(
                    child: _SyncNode(
                      icon: Icons.cloud_outlined,
                      label: serverLabel,
                      caption: serverCaption,
                    ),
                  ),
                  const _SyncArrow(),
                  Expanded(
                    child: _SyncNode(
                      icon: Icons.smartphone_outlined,
                      label: mobileLabel,
                      caption: mobileCaption,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SyncNode extends StatelessWidget {
  const _SyncNode({
    required this.icon,
    required this.label,
    required this.caption,
  });

  final IconData icon;
  final String label;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Icon(icon, color: scheme.onSurfaceVariant, size: 26),
        const SizedBox(height: 6),
        Text(
          label,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 2),
        Text(
          caption,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.3,
                fontSize: 11,
              ),
        ),
      ],
    );
  }
}

class _SyncArrow extends StatelessWidget {
  const _SyncArrow({this.down = false});

  final bool down;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.35);
    if (down) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Icon(Icons.more_vert_rounded, color: c, size: 18),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Icon(Icons.more_horiz_rounded, color: c, size: 18),
    );
  }
}

class DistributorsSectionTitle extends StatelessWidget {
  const DistributorsSectionTitle({
    super.key,
    required this.title,
    this.subtitle,
  });

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          if (subtitle != null)
            Text(
              subtitle!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
        ],
      ),
    );
  }
}

class DistributorsStatCard extends StatelessWidget {
  const DistributorsStatCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.accentColor,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color accentColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final child = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                accentColor.withValues(alpha: 0.18),
                accentColor.withValues(alpha: 0.08),
              ],
            ),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, size: 20, color: accentColor),
        ),
        const Spacer(),
        Text(
          value,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
                height: 1.0,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontSize: 11.5,
                height: 1.3,
                fontWeight: FontWeight.w600,
              ),
        ),
      ],
    );
    final box = SizedBox(
      width: kDistributorsHubStatTileWidth,
      height: kDistributorsHubStatTileHeight,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: onTap != null
                ? accentColor.withValues(alpha: 0.22)
                : scheme.outlineVariant.withValues(alpha: 0.35),
          ),
          boxShadow: [
            BoxShadow(
              color: accentColor.withValues(alpha: 0.08),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
            BoxShadow(
              color: scheme.shadow.withValues(alpha: 0.04),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: child,
      ),
    );
    if (onTap == null) return box;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        hoverColor: accentColor.withValues(alpha: 0.06),
        child: box,
      ),
    );
  }
}

enum DistributorsConnectionLevel { ok, warning, offline }

class DistributorsConnectionStatusBar extends StatelessWidget {
  const DistributorsConnectionStatusBar({
    super.key,
    required this.level,
    required this.title,
    required this.subtitle,
    required this.desktopLabel,
    required this.serverLabel,
    required this.mobileLabel,
    required this.publishDetail,
  });

  final DistributorsConnectionLevel level;
  final String title;
  final String subtitle;
  final String desktopLabel;
  final String serverLabel;
  final String mobileLabel;
  final String publishDetail;

  Color _accent(ColorScheme scheme) {
    switch (level) {
      case DistributorsConnectionLevel.ok:
        return const Color(0xFF16A34A);
      case DistributorsConnectionLevel.warning:
        return const Color(0xFFD97706);
      case DistributorsConnectionLevel.offline:
        return scheme.error;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = _accent(scheme);
    return Container(
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.28)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                level == DistributorsConnectionLevel.offline
                    ? Icons.cloud_off_outlined
                    : Icons.cloud_done_outlined,
                color: accent,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            height: 1.4,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _StatusChip(
                icon: Icons.computer_rounded,
                label: desktopLabel,
                active: true,
                accent: accent,
              ),
              Icon(Icons.chevron_right_rounded,
                  size: 16, color: scheme.onSurfaceVariant.withValues(alpha: 0.45)),
              _StatusChip(
                icon: Icons.dns_outlined,
                label: serverLabel,
                active: level != DistributorsConnectionLevel.offline,
                accent: accent,
              ),
              Icon(Icons.chevron_right_rounded,
                  size: 16, color: scheme.onSurfaceVariant.withValues(alpha: 0.45)),
              _StatusChip(
                icon: Icons.smartphone_outlined,
                label: mobileLabel,
                active: level == DistributorsConnectionLevel.ok,
                accent: accent,
              ),
            ],
          ),
          if (publishDetail.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              publishDetail,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.icon,
    required this.label,
    required this.active,
    required this.accent,
  });

  final IconData icon;
  final String label;
  final bool active;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: active
            ? accent.withValues(alpha: 0.12)
            : scheme.surfaceContainerHighest.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: active
              ? accent.withValues(alpha: 0.35)
              : scheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: active ? accent : scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: active ? accent : scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class DistributorsTodayActivityPanel extends StatelessWidget {
  const DistributorsTodayActivityPanel({
    super.key,
    required this.title,
    required this.emptyMessage,
    required this.viewAllLabel,
    required this.items,
    required this.movementLabel,
    required this.onViewAll,
    this.onItemTap,
  });

  final String title;
  final String emptyMessage;
  final String viewAllLabel;
  final List<DistributorsActivityItem> items;
  final String Function(DistributorsActivityItem item) movementLabel;
  final VoidCallback onViewAll;
  final ValueChanged<DistributorsActivityItem>? onItemTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DistributorsModernPanel(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              TextButton(
                onPressed: onViewAll,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: Text(viewAllLabel),
              ),
            ],
          ),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                emptyMessage,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            )
          else
            ...[
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 1,
                    color: scheme.outlineVariant.withValues(alpha: 0.35),
                  ),
                InkWell(
                  onTap: onItemTap == null ? null : () => onItemTap!(items[i]),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: Row(
                      children: [
                        Icon(
                          items[i].icon,
                          size: 18,
                          color: scheme.primary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                movementLabel(items[i]),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${items[i].distributorName} · ${items[i].productName}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          items[i].qtyLabel,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
        ],
      ),
    );
  }
}

class DistributorsActivityItem {
  const DistributorsActivityItem({
    required this.movementType,
    required this.distributorName,
    required this.productName,
    required this.qtyLabel,
    required this.icon,
  });

  final String movementType;
  final String distributorName;
  final String productName;
  final String qtyLabel;
  final IconData icon;
}

class DistributorsReportsDropdownCard extends StatelessWidget {
  const DistributorsReportsDropdownCard({
    super.key,
    required this.title,
    required this.hint,
    required this.accentColor,
    required this.items,
  });

  final String title;
  final String hint;
  final Color accentColor;
  final List<({String value, String label, VoidCallback onSelect})> items;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final labelStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant,
          fontSize: 11.5,
          height: 1.3,
          fontWeight: FontWeight.w600,
        );
    return SizedBox(
      width: kDistributorsHubStatTileWidth,
      height: kDistributorsHubStatTileHeight,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: accentColor.withValues(alpha: 0.22),
          ),
          boxShadow: [
            BoxShadow(
              color: accentColor.withValues(alpha: 0.08),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    accentColor.withValues(alpha: 0.18),
                    accentColor.withValues(alpha: 0.08),
                  ],
                ),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(
                Icons.summarize_rounded,
                size: 20,
                color: accentColor,
              ),
            ),
            const Spacer(),
            DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                isDense: true,
                hint: Text(
                  hint,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                ),
                icon: Icon(
                  Icons.expand_more_rounded,
                  color: accentColor,
                  size: 22,
                ),
                items: [
                  for (final item in items)
                    DropdownMenuItem<String>(
                      value: item.value,
                      child: Text(
                        item.label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  for (final item in items) {
                    if (item.value == value) {
                      item.onSelect();
                      break;
                    }
                  }
                },
              ),
            ),
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: labelStyle),
          ],
        ),
      ),
    );
  }
}

class DistributorsOperationBox extends StatefulWidget {
  const DistributorsOperationBox({
    super.key,
    required this.gradient,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge,
    this.busy = false,
  });

  final List<Color> gradient;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final int? badge;
  final bool busy;

  @override
  State<DistributorsOperationBox> createState() =>
      _DistributorsOperationBoxState();
}

class _DistributorsOperationBoxState extends State<DistributorsOperationBox> {
  bool _hovered = false;

  Color get _accent => widget.gradient.last;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final elevated = _hovered && widget.onTap != null && !widget.busy;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: _accent.withValues(alpha: elevated ? 0.22 : 0.1),
              blurRadius: elevated ? 22 : 14,
              offset: Offset(0, elevated ? 10 : 6),
            ),
            BoxShadow(
              color: scheme.shadow.withValues(alpha: 0.05),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Material(
          color: scheme.surface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(
              color: _accent.withValues(alpha: elevated ? 0.35 : 0.18),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.busy ? null : widget.onTap,
            hoverColor: _accent.withValues(alpha: 0.05),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  height: 4,
                  decoration: BoxDecoration(
                    gradient: DistributorsHubPalette.gradient(widget.gradient),
                  ),
                ),
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                gradient: DistributorsHubPalette.gradient(
                                  widget.gradient,
                                ),
                                borderRadius: BorderRadius.circular(18),
                                boxShadow: [
                                  BoxShadow(
                                    color: _accent.withValues(alpha: 0.28),
                                    blurRadius: 12,
                                    offset: const Offset(0, 5),
                                  ),
                                ],
                              ),
                              child: widget.busy
                                  ? const Padding(
                                      padding: EdgeInsets.all(18),
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                        color: Colors.white,
                                      ),
                                    )
                                  : Icon(
                                      widget.icon,
                                      color: Colors.white,
                                      size: 32,
                                    ),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              widget.title,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    height: 1.2,
                                  ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              widget.subtitle,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                    height: 1.35,
                                    fontSize: 11.5,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      if (widget.badge != null && widget.badge! > 0)
                        PositionedDirectional(
                          top: 10,
                          end: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.error,
                              borderRadius: BorderRadius.circular(999),
                              boxShadow: [
                                BoxShadow(
                                  color: scheme.error.withValues(alpha: 0.35),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Text(
                              '${widget.badge}',
                              style: TextStyle(
                                color: scheme.onError,
                                fontWeight: FontWeight.w800,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class DistributorsReportCard extends StatelessWidget {
  const DistributorsReportCard({
    super.key,
    required this.gradient,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onOpen,
  });

  final List<Color> gradient;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = gradient.last;
    return Material(
      color: scheme.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.55)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: DistributorsHubPalette.tint(accent, alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: accent, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            height: 1.35,
                          ),
                    ),
                  ],
                ),
              ),
              Icon(
                Directionality.of(context) == TextDirection.rtl
                    ? Icons.chevron_left_rounded
                    : Icons.chevron_right_rounded,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.45),
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DistributorsModernPanel extends StatelessWidget {
  const DistributorsModernPanel({
    super.key,
    required this.child,
    this.accent,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final Color? accent;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      padding: padding,
      child: child,
    );
  }
}

/// تنويه أسفل صفحة الموزعين — ضرورة الإنترنت للربط مع الجوال.
class DistributorsInternetNotice extends StatelessWidget {
  const DistributorsInternetNotice({
    super.key,
    required this.title,
    required this.body,
    required this.desktopLabel,
    required this.serverLabel,
    required this.mobileLabel,
  });

  final String title;
  final String body;
  final String desktopLabel;
  final String serverLabel;
  final String mobileLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: DistributorsHubPalette.intro.withValues(alpha: 0.18),
        ),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  DistributorsHubPalette.intro.withValues(alpha: 0.2),
                  DistributorsHubPalette.intro.withValues(alpha: 0.08),
                ],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.wifi_tethering_rounded,
              size: 22,
              color: DistributorsHubPalette.intro,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  body,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.55,
                      ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _LinkChip(
                      icon: Icons.desktop_windows_outlined,
                      label: desktopLabel,
                    ),
                    Icon(
                      Icons.arrow_forward_rounded,
                      size: 14,
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                    ),
                    _LinkChip(
                      icon: Icons.cloud_outlined,
                      label: serverLabel,
                    ),
                    Icon(
                      Icons.arrow_forward_rounded,
                      size: 14,
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                    ),
                    _LinkChip(
                      icon: Icons.smartphone_outlined,
                      label: mobileLabel,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LinkChip extends StatelessWidget {
  const _LinkChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: scheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

/// @deprecated — أُزيل شريط الخطوات الملوّن؛ يُبقى للتوافق إن وُجد استدعاء.
class DistributorsWorkflowStrip extends StatelessWidget {
  const DistributorsWorkflowStrip({super.key, required this.steps});

  final List<({IconData icon, String label, Color color})> steps;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
