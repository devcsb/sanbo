import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../features/home/session_controller.dart';

/// 3-tab shell: 홈 · 기록 · 설정
///
/// While a walk is actively recording, leaving the Home tab shows a gentle
/// reminder that tracking continues in the background (FGS).
class ScaffoldWithNavBar extends ConsumerWidget {
  const ScaffoldWithNavBar(this.navigationShell, {super.key});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final live = ref.watch(sessionControllerProvider);
    final tracking = live.isTracking;
    final theme = Theme.of(context);
    final surfaces = SanboSurfaces.of(context);

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLowest.withValues(
            alpha: theme.brightness == Brightness.dark ? 0.96 : 0.98,
          ),
          border: Border(
            top: BorderSide(color: surfaces.panelBorder),
          ),
          boxShadow: [
            BoxShadow(
              color: Color.fromRGBO(
                5,
                30,
                50,
                theme.brightness == Brightness.dark ? 0.28 : 0.06,
              ),
              offset: const Offset(0, -4),
              blurRadius: 18,
            ),
          ],
        ),
        child: NavigationBar(
          selectedIndex: navigationShell.currentIndex,
          onDestinationSelected: (index) {
            final leavingHome =
                navigationShell.currentIndex == 0 && index != 0 && tracking;
            navigationShell.goBranch(
              index,
              initialLocation: index == navigationShell.currentIndex,
            );
            if (leavingHome && context.mounted) {
              ScaffoldMessenger.of(context).clearSnackBars();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('산책 기록은 계속됩니다. 홈에서 종료할 수 있어요.'),
                  duration: Duration(seconds: 3),
                ),
              );
            }
          },
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.directions_walk_outlined),
              selectedIcon: const Icon(Icons.directions_walk_rounded),
              label: tracking ? '기록 중' : '홈',
            ),
            const NavigationDestination(
              icon: Icon(Icons.history_outlined),
              selectedIcon: Icon(Icons.history_rounded),
              label: '기록',
            ),
            const NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings_rounded),
              label: '설정',
            ),
          ],
        ),
      ),
    );
  }
}
