import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Shared motion tokens for calm, predictable transitions.
///
/// Motion is intentionally short and fade-only for asynchronous state changes:
/// the content itself remains stable while loading, error, and data states are
/// swapped.  [MediaQueryData.disableAnimations] is honoured so the same
/// components are safe for reduced-motion users and widget tests.
abstract final class AppMotion {
  static const standard = AppTheme.motionStandard;
  static const expand = AppTheme.motionExpand;
  static const feedback = AppTheme.motionFeedback;
  static const curve = AppTheme.motionCurve;

  static Duration duration(BuildContext context, Duration value) {
    return MediaQuery.maybeOf(context)?.disableAnimations == true
        ? Duration.zero
        : value;
  }
}

/// A keyed, fade-only switcher for asynchronous UI states.
///
/// The identity belongs to the state being shown (for example
/// `loading`, `error`, or `data:2026-08-29`), not to the widget instance. This
/// prevents stale asynchronous content from being reused across transitions.
class SmoothSwitcher extends StatelessWidget {
  const SmoothSwitcher({
    required this.transitionKey,
    required this.child,
    this.duration = AppMotion.standard,
    super.key,
  });

  final Object transitionKey;
  final Widget child;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: AppMotion.duration(context, duration),
      reverseDuration: AppMotion.duration(context, duration),
      switchInCurve: AppMotion.curve,
      switchOutCurve: AppMotion.curve,
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          alignment: Alignment.topCenter,
          children: <Widget>[
            ...previousChildren,
            if (currentChild != null) currentChild,
          ],
        );
      },
      transitionBuilder: (child, animation) {
        return FadeTransition(opacity: animation, child: child);
      },
      child: KeyedSubtree(key: ValueKey<Object>(transitionKey), child: child),
    );
  }
}
