import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/history/history_screen.dart';
import '../features/home/home_screen.dart';
import '../features/intro/intro_providers.dart';
import '../features/intro/intro_screen.dart';
import '../features/session_detail/session_detail_screen.dart';
import '../features/settings/settings_screen.dart';
import '../shared/widgets/app_bottom_nav.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final introSeen = ref.watch(introSeenProvider);

  return GoRouter(
    initialLocation: introSeen ? '/' : '/intro',
    redirect: (context, state) {
      final atIntro = state.matchedLocation == '/intro';
      if (!introSeen && !atIntro) return '/intro';
      if (introSeen && atIntro) return '/';
      return null;
    },
    routes: [
      GoRoute(
        path: '/intro',
        builder: (context, state) => const IntroScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return ScaffoldWithNavBar(navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/',
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/history',
                builder: (context, state) => const HistoryScreen(),
                routes: [
                  GoRoute(
                    path: ':sessionId',
                    builder: (context, state) {
                      final id = state.pathParameters['sessionId']!;
                      return SessionDetailScreen(sessionId: id);
                    },
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                builder: (context, state) => const SettingsScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
