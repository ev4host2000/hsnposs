import 'package:flutter/material.dart';
import 'package:mizapos_mobile/l10n/app_localizations.dart';

/// بطاقة عرض أسعار MizaPos: اشتراك سنوي $70 (حاسوب + أندرويد).
class SubscriptionPlanCard extends StatelessWidget {
  const SubscriptionPlanCard({
    super.key,
    this.compact = false,
    this.rail = false,
    this.banner = false,
  });

  final bool compact;

  /// لوحة جانبية عمودية داخل حوار التفعيل (حاسوب/أفقي) — تدرّج داكن وأسعار بارزة.
  final bool rail;

  /// شريط أفقي مدمج لشاشات الجوال العمودية.
  final bool banner;

  @override
  Widget build(BuildContext context) {
    if (rail) return _planRailCard(context);
    if (banner) return _planBannerCard(context);
    final loc = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final radius = compact ? 18.0 : 22.0;
    final pad = compact ? 14.0 : 18.0;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [
            scheme.surface,
            Color.lerp(scheme.surface, scheme.primary, 0.04)!,
          ],
        ),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.45),
        ),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.06),
            blurRadius: compact ? 16 : 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _MainPlanHero(
              loc: loc,
              theme: theme,
              compact: compact,
              padding: pad,
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(pad, 0, pad, pad),
              child: Text(
                loc.subscriptionPlanFootnote,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.85),
                  height: 1.4,
                  fontSize: compact ? 11 : 11.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _planRailCard(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF0F172A),
            Color(0xFF1E3A5F),
            Color(0xFF2563EB),
            Color(0xFF6D28D9),
          ],
          stops: [0.0, 0.35, 0.72, 1.0],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.22),
                    ),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(
                      Icons.workspace_premium_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    loc.subscriptionPlanTitle,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      height: 1.2,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            _PillBadge(
              icon: Icons.bolt_rounded,
              label: loc.subscriptionPlanBadgeOneTime,
              background: Colors.white.withValues(alpha: 0.18),
              foreground: Colors.white,
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '\$',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 28,
                    height: 1,
                    color: Colors.white.withValues(alpha: 0.82),
                  ),
                ),
                Text(
                  loc.subscriptionPlanPriceAmount,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 64,
                    height: 0.9,
                    letterSpacing: -3,
                    color: Colors.white,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 10),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        loc.subscriptionPlanPriceCurrency,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          height: 1,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        loc.subscriptionPlanPriceSuffix,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.78),
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                          height: 1,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              loc.subscriptionPlanBadgeNoRecurring,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.82),
                fontWeight: FontWeight.w600,
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              loc.subscriptionPlanIncludesTitle,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.88),
                fontWeight: FontWeight.w800,
                fontSize: 12,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 10),
            _RailDeviceTiles(loc: loc),
            const SizedBox(height: 20),
            Text(
              loc.subscriptionPlanFootnote,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.62),
                fontSize: 10.5,
                height: 1.4,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// شريط تسعير أفقي للجوال — الخطة السنوية $70 (حاسوب + أندرويد).
  Widget _planBannerCard(BuildContext context) {
    final loc = AppLocalizations.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Color(0xFF0F172A),
            Color(0xFF1E3A5F),
            Color(0xFF2563EB),
            Color(0xFF6D28D9),
          ],
          stops: [0.0, 0.3, 0.7, 1.0],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x402563EB),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PillBadge(
              icon: Icons.bolt_rounded,
              label: loc.subscriptionPlanBadgeOneTime,
              background: Colors.white.withValues(alpha: 0.18),
              foreground: Colors.white,
              compact: true,
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '\$',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                    height: 1,
                    color: Colors.white.withValues(alpha: 0.82),
                  ),
                ),
                Text(
                  loc.subscriptionPlanPriceAmount,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 40,
                    height: 0.92,
                    letterSpacing: -2,
                    color: Colors.white,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 6),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        loc.subscriptionPlanPriceCurrency,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                          height: 1,
                        ),
                      ),
                      Text(
                        loc.subscriptionPlanPriceSuffix,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.78),
                          fontWeight: FontWeight.w600,
                          fontSize: 10,
                          height: 1,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              loc.subscriptionPlanPriceHeadline,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.88),
                fontWeight: FontWeight.w600,
                fontSize: 10.5,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MainPlanHero extends StatelessWidget {
  const _MainPlanHero({
    required this.loc,
    required this.theme,
    required this.compact,
    required this.padding,
  });

  final AppLocalizations loc;
  final ThemeData theme;
  final bool compact;
  final double padding;

  @override
  Widget build(BuildContext context) {
    final scheme = theme.colorScheme;
    final priceSize = compact ? 42.0 : 52.0;

    return Container(
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [
            scheme.primary.withValues(alpha: 0.10),
            scheme.primary.withValues(alpha: 0.03),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PillBadge(
            icon: Icons.bolt_rounded,
            label: loc.subscriptionPlanBadgeOneTime,
            background: scheme.primary,
            foreground: scheme.onPrimary,
          ),
          SizedBox(height: compact ? 12 : 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '\$',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: priceSize * 0.42,
                  height: 1,
                  color: scheme.primary.withValues(alpha: 0.82),
                ),
              ),
              Text(
                loc.subscriptionPlanPriceAmount,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: priceSize,
                  height: 0.95,
                  letterSpacing: -2,
                  color: scheme.primary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              SizedBox(width: compact ? 8 : 10),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      loc.subscriptionPlanPriceCurrency,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: scheme.onSurface.withValues(alpha: 0.82),
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      loc.subscriptionPlanPriceSuffix,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                        height: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? 6 : 8),
          Text(
            loc.subscriptionPlanBadgeNoRecurring,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
          SizedBox(height: compact ? 12 : 14),
          Text(
            loc.subscriptionPlanIncludesTitle,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: scheme.onSurface.withValues(alpha: 0.78),
              letterSpacing: 0.2,
            ),
          ),
          SizedBox(height: compact ? 8 : 10),
          _DeviceTiles(loc: loc, theme: theme, compact: compact),
        ],
      ),
    );
  }
}

class _DeviceTiles extends StatelessWidget {
  const _DeviceTiles({
    required this.loc,
    required this.theme,
    required this.compact,
  });

  final AppLocalizations loc;
  final ThemeData theme;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = theme.colorScheme;
    return Row(
      children: [
        Expanded(
          child: _FeatureTile(
            icon: Icons.desktop_windows_rounded,
            label: loc.subscriptionPlanDeviceWindows,
            scheme: scheme,
            compact: compact,
          ),
        ),
        SizedBox(width: compact ? 6 : 8),
        Expanded(
          child: _FeatureTile(
            icon: Icons.smartphone_rounded,
            label: loc.subscriptionPlanDeviceAndroid,
            scheme: scheme,
            compact: compact,
          ),
        ),
        SizedBox(width: compact ? 6 : 8),
        Expanded(
          child: _FeatureTile(
            icon: Icons.devices_rounded,
            label: loc.subscriptionPlanDevicesLabel,
            scheme: scheme,
            compact: compact,
            highlight: true,
          ),
        ),
      ],
    );
  }
}

class _FeatureTile extends StatelessWidget {
  const _FeatureTile({
    required this.icon,
    required this.label,
    required this.scheme,
    required this.compact,
    this.highlight = false,
  });

  final IconData icon;
  final String label;
  final ColorScheme scheme;
  final bool compact;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final bg = highlight
        ? scheme.primaryContainer.withValues(alpha: 0.55)
        : scheme.surfaceContainerHighest.withValues(alpha: 0.75);
    final fg = highlight ? scheme.primary : scheme.onSurface.withValues(alpha: 0.82);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 8 : 10,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(compact ? 12 : 14),
        border: Border.all(
          color: highlight
              ? scheme.primary.withValues(alpha: 0.22)
              : scheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: compact ? 18 : 20, color: fg),
          SizedBox(height: compact ? 4 : 6),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w700,
              fontSize: compact ? 10 : 11,
              height: 1.15,
            ),
          ),
        ],
      ),
    );
  }
}

class _PillBadge extends StatelessWidget {
  const _PillBadge({
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
    this.compact = false,
  });

  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 4 : 5,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: compact ? 12 : 13, color: foreground),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: foreground,
                fontWeight: FontWeight.w800,
                fontSize: compact ? 10.5 : 11.5,
                height: 1.15,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RailDeviceTiles extends StatelessWidget {
  const _RailDeviceTiles({required this.loc});

  final AppLocalizations loc;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _RailFeatureTile(
            icon: Icons.desktop_windows_rounded,
            label: loc.subscriptionPlanDeviceWindows,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _RailFeatureTile(
            icon: Icons.smartphone_rounded,
            label: loc.subscriptionPlanDeviceAndroid,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _RailFeatureTile(
            icon: Icons.devices_rounded,
            label: loc.subscriptionPlanDevicesLabel,
            highlight: true,
          ),
        ),
      ],
    );
  }
}

class _RailFeatureTile extends StatelessWidget {
  const _RailFeatureTile({
    required this.icon,
    required this.label,
    this.highlight = false,
  });

  final IconData icon;
  final String label;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final bg = highlight
        ? Colors.white.withValues(alpha: 0.22)
        : Colors.white.withValues(alpha: 0.1);
    final border = highlight
        ? Colors.white.withValues(alpha: 0.42)
        : Colors.white.withValues(alpha: 0.18);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: Colors.white),
          const SizedBox(height: 5),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: highlight ? 1 : 0.9),
              fontWeight: FontWeight.w700,
              fontSize: 10,
              height: 1.15,
            ),
          ),
        ],
      ),
    );
  }
}
