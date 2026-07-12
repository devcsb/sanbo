import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// 3-tab shell: 홈 · 기록 · 설정
class ScaffoldWithNavBar extends StatelessWidget {
  const ScaffoldWithNavBar(this.navigationShell, {super.key});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.navigationBarTheme.backgroundColor ??
              theme.colorScheme.surface,
          border: Border(
            top: BorderSide(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.55),
            ),
          ),
        ),
        child: NavigationBar(
          selectedIndex: navigationShell.currentIndex,
          onDestinationSelected: (index) {
            navigationShell.goBranch(
              index,
              initialLocation: index == navigationShell.currentIndex,
            );
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.directions_walk_outlined),
              selectedIcon: Icon(Icons.directions_walk_rounded),
              label: '홈',
            ),
            NavigationDestination(
              icon: Icon(Icons.history_outlined),
              selectedIcon: Icon(Icons.history_rounded),
              label: '기록',
            ),
            NavigationDestination(
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
