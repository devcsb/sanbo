import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_info.dart';
import '../../core/theme/app_theme.dart';
import 'intro_providers.dart';

/// First-run brand intro.
class IntroScreen extends ConsumerWidget {
  const IntroScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: AppTheme.brandNavy,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            AppInfo.brandMainAsset,
            fit: BoxFit.cover,
            alignment: Alignment.center,
            errorBuilder: (_, _, _) =>
                const ColoredBox(color: AppTheme.brandNavy),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x000B1B33),
                  Color(0x550B1B33),
                  Color(0xF00B1B33),
                ],
                stops: [0.4, 0.68, 1],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Spacer(flex: 4),
                  Text(
                    AppInfo.nameKo,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    AppInfo.tagline,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: Colors.white.withValues(alpha: 0.88),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(flex: 1),
                  FilledButton(
                    onPressed: () => _continue(context, ref),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      backgroundColor: AppTheme.brandTeal,
                      foregroundColor: AppTheme.brandNavy,
                    ),
                    child: const Text('시작하기'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _continue(BuildContext context, WidgetRef ref) async {
    await ref.read(appFlagsStoreProvider).setHasSeenIntro(true);
    ref.read(introSeenProvider.notifier).state = true;
    if (context.mounted) context.go('/');
  }
}
