import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/router.dart';
import 'core/theme/app_theme.dart';
import 'features/home/session_controller.dart';
import 'platform/notifications/session_notification_service.dart';

class SanboApp extends ConsumerStatefulWidget {
  const SanboApp({super.key});

  @override
  ConsumerState<SanboApp> createState() => _SanboAppState();
}

class _SanboAppState extends ConsumerState<SanboApp> {
  late final AppLifecycleListener _lifecycleListener;
  late final StreamSubscription<SessionNotificationTap> _notificationTapSub;

  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(
      onResume: () {
        unawaited(
          ref.read(sessionNotificationServiceProvider).initialize(),
        );
        ref.read(sessionControllerProvider.notifier).setAppForeground(true);
      },
      onInactive: () =>
          ref.read(sessionControllerProvider.notifier).setAppInactive(),
      onPause: () =>
          ref.read(sessionControllerProvider.notifier).setAppForeground(false),
      onHide: () =>
          ref.read(sessionControllerProvider.notifier).setAppForeground(false),
    );
    _notificationTapSub = ref
        .read(sessionNotificationServiceProvider)
        .taps
        .listen((tap) {
          ref
              .read(sessionControllerProvider.notifier)
              .handleNotificationTap(tap);
          ref.read(routerProvider).go('/');
        });
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    _notificationTapSub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: '산보',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      routerConfig: router,
      locale: const Locale('ko', 'KR'),
      supportedLocales: const [Locale('ko', 'KR')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }
}
