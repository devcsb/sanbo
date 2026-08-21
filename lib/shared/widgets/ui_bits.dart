import 'package:flutter/material.dart';

import '../../app/app_info.dart';
import '../../core/theme/app_theme.dart';

/// Compact brand mark for app bars and settings.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 28});

  final double size;

  @override
  Widget build(BuildContext context) {
    final cacheSize = (size * MediaQuery.devicePixelRatioOf(context)).round();
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.3),
        boxShadow: AppTheme.elevationLow(Theme.of(context).brightness)
            .map(
              (s) => BoxShadow(
                color: s.color.withValues(alpha: s.color.a * 0.55),
                offset: s.offset,
                blurRadius: s.blurRadius,
              ),
            )
            .toList(),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.3),
        child: Image.asset(
          AppInfo.brandIconAsset,
          width: size,
          height: size,
          fit: BoxFit.cover,
          cacheWidth: cacheSize,
          cacheHeight: cacheSize,
          excludeFromSemantics: true,
          errorBuilder: (_, _, _) => Icon(
            Icons.layers_rounded,
            size: size * 0.85,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
    );
  }
}

class AppBarTitle extends StatelessWidget {
  const AppBarTitle(this.label, {super.key, this.showBrand = false});

  final String label;
  final bool showBrand;

  @override
  Widget build(BuildContext context) {
    if (!showBrand) return Text(label);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const BrandMark(size: 28),
        const SizedBox(width: 10),
        Text(label),
      ],
    );
  }
}

/// Centers page content and keeps it readable on tablets and desktop windows.
class PageFrame extends StatelessWidget {
  const PageFrame({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(
      AppTheme.pagePadding,
      10,
      AppTheme.pagePadding,
      36,
    ),
    this.maxWidth = AppTheme.pageMaxWidth,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: SizedBox(
          width: double.infinity,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Consistent hierarchy for the first content block on top-level screens.
class PageIntro extends StatelessWidget {
  const PageIntro({
    super.key,
    required this.title,
    required this.description,
    this.eyebrow,
  });

  final String title;
  final String description;
  final String? eyebrow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (eyebrow != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppTheme.radiusPill),
            ),
            child: Text(
              eyebrow!,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.15,
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        Semantics(
          header: true,
          child: Text(title, style: theme.textTheme.headlineSmall),
        ),
        const SizedBox(height: 10),
        Text(
          description,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.55,
          ),
        ),
      ],
    );
  }
}

/// Quiet section label used across list screens.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 12),
      child: Semantics(
        header: true,
        child: Text(
          text,
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }
}

/// Brand-colored icon surface used in cards, rows, and empty states.
class TonalIcon extends StatelessWidget {
  const TonalIcon({
    super.key,
    required this.icon,
    this.color,
    this.size = 46,
    this.iconSize = 22,
  });

  final IconData icon;
  final Color? color;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = _tonalColors(theme.colorScheme, color);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall + 2),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: iconSize, color: colors.foreground),
    );
  }
}

/// Text-backed state indicator; meaning never relies on color alone.
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label, this.icon, this.color});

  final String label;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = _tonalColors(theme.colorScheme, color);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        border: Border.all(color: colors.foreground.withValues(alpha: 0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        child: Wrap(
          spacing: icon == null ? 0 : 5,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (icon != null) Icon(icon, size: 15, color: colors.foreground),
            Text(
              label,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelMedium?.copyWith(
                color: colors.foreground,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

({Color background, Color foreground}) _tonalColors(
  ColorScheme scheme,
  Color? requested,
) {
  final color = requested ?? scheme.primary;
  if (color == scheme.secondary) {
    return (
      background: scheme.secondaryContainer,
      foreground: scheme.onSecondaryContainer,
    );
  }
  if (color == scheme.tertiary) {
    return (
      background: scheme.tertiaryContainer,
      foreground: scheme.onTertiaryContainer,
    );
  }
  if (color == scheme.error) {
    return (
      background: scheme.errorContainer,
      foreground: scheme.onErrorContainer,
    );
  }
  if (requested != null && color != scheme.primary) {
    return (background: scheme.surfaceContainerHighest, foreground: color);
  }
  return (
    background: scheme.primaryContainer,
    foreground: scheme.onPrimaryContainer,
  );
}

/// Centered empty or error state with an explicit recovery action.
class EmptyStateView extends StatelessWidget {
  const EmptyStateView({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight:
                  constraints.hasBoundedHeight && constraints.maxHeight > 48
                  ? constraints.maxHeight - 48
                  : 0,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TonalIcon(icon: icon, size: 80, iconSize: 36),
                    const SizedBox(height: 22),
                    Semantics(
                      header: true,
                      child: Text(
                        title,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                    if (message != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        message!,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.55,
                        ),
                      ),
                    ],
                    if (actionLabel != null && onAction != null) ...[
                      const SizedBox(height: 26),
                      FilledButton(
                        onPressed: onAction,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(200, 52),
                        ),
                        child: Text(actionLabel!),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Soft elevated surface used to group settings, summaries, and related actions.
class SoftPanel extends StatelessWidget {
  const SoftPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.color,
    this.elevated = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surfaces = SanboSurfaces.of(context);
    final bg =
        color ??
        (theme.brightness == Brightness.dark
            ? theme.colorScheme.surfaceContainerLow
            : theme.colorScheme.surfaceContainerLowest);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: surfaces.panelBorder),
        boxShadow: elevated ? surfaces.panelShadow : const [],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        child: Material(
          type: MaterialType.transparency,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class MetricData {
  const MetricData({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final bool emphasize;
}

/// Responsive metric group shared by live and completed walk summaries.
class MetricStrip extends StatelessWidget {
  const MetricStrip({
    super.key,
    required this.metrics,
    this.header,
    this.padding = const EdgeInsets.symmetric(vertical: 22, horizontal: 12),
  });

  final List<MetricData> metrics;
  final Widget? header;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    assert(metrics.isNotEmpty);
    return SoftPanel(
      padding: padding,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scaledBody = MediaQuery.textScalerOf(context).scale(16);
          final stackMetrics = constraints.maxWidth < 280 || scaledBody > 22;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (header != null) ...[header!, const SizedBox(height: 18)],
              if (stackMetrics)
                _StackedMetrics(metrics: metrics)
              else
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < metrics.length; i++) ...[
                        if (i > 0) const _MetricDivider(),
                        Expanded(
                          child: MetricTile(
                            label: metrics[i].label,
                            value: metrics[i].value,
                            emphasize: metrics[i].emphasize,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _StackedMetrics extends StatelessWidget {
  const _StackedMetrics({required this.metrics});

  final List<MetricData> metrics;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < metrics.length; i++) ...[
          if (i > 0) const Divider(height: 25),
          MetricTile(
            label: metrics[i].label,
            value: metrics[i].value,
            emphasize: metrics[i].emphasize,
            horizontal: true,
          ),
        ],
      ],
    );
  }
}

class _MetricDivider extends StatelessWidget {
  const _MetricDivider();

  @override
  Widget build(BuildContext context) {
    return VerticalDivider(
      width: 1,
      thickness: 1,
      color: Theme.of(context).dividerColor,
    );
  }
}

class MetricTile extends StatelessWidget {
  const MetricTile({
    super.key,
    required this.label,
    required this.value,
    this.emphasize = false,
    this.horizontal = false,
  });

  final String label;
  final String value;
  final bool emphasize;
  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelWidget = Text(
      label,
      style: theme.textTheme.labelMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w600,
      ),
    );
    final valueWidget = Text(
      value,
      maxLines: horizontal ? null : 1,
      textAlign: horizontal ? TextAlign.end : TextAlign.center,
      style: theme.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        color: emphasize ? theme.colorScheme.primary : null,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );

    return Semantics(
      label: '$label $value',
      excludeSemantics: true,
      child: horizontal
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: labelWidget),
                const SizedBox(width: 16),
                Flexible(child: valueWidget),
              ],
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                labelWidget,
                const SizedBox(height: 8),
                FittedBox(fit: BoxFit.scaleDown, child: valueWidget),
              ],
            ),
    );
  }
}
