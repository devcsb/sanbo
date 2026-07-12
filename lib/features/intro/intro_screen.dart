import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_info.dart';
import 'intro_providers.dart';

/// First-run brand intro using [assets/branding/sanbo-main.jpg].
class IntroScreen extends ConsumerWidget {
  const IntroScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final bottom = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: const Color(0xFF0B1B33),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Full-bleed brand art
          Image.asset(
            AppInfo.brandMainAsset,
            fit: BoxFit.cover,
            alignment: Alignment.center,
            errorBuilder: (_, _, _) => const ColoredBox(
              color: Color(0xFF0B1B33),
            ),
          ),
          // Soft bottom gradient so CTA stays readable on any crop
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x000B1B33),
                  Color(0x660B1B33),
                  Color(0xE60B1B33),
                ],
                stops: [0.45, 0.7, 1.0],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(24, 16, 24, 16 + bottom * 0.25),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Spacer(flex: 3),
                  Text(
                    AppInfo.nameKo,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
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
                  const SizedBox(height: 12),
                  Text(
                    '산책의 그때 그 순간을 분 단위로 남기는\n개인 로그',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.white.withValues(alpha: 0.72),
                      height: 1.45,
                    ),
                  ),
                  const Spacer(flex: 1),
                  FilledButton(
                    onPressed: () => _continue(context, ref),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(54),
                      backgroundColor: const Color(0xFF2EC4B6),
                      foregroundColor: const Color(0xFF0B1B33),
                      textStyle: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
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
    if (context.mounted) {
      context.go('/');
    }
  }
}
