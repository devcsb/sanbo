import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_info.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/ui_bits.dart';
import 'intro_providers.dart';

/// First-run brand intro.
class IntroScreen extends ConsumerStatefulWidget {
  const IntroScreen({super.key});

  @override
  ConsumerState<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends ConsumerState<IntroScreen> {
  var _isContinuing = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: AppTheme.brandNavy,
      ),
      child: Scaffold(
        backgroundColor: AppTheme.brandNavy,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Stack(
                children: [
                  Positioned(
                    top: -80,
                    right: -60,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            colors: [
                              AppTheme.brandTeal.withValues(alpha: 0.28),
                              AppTheme.brandTeal.withValues(alpha: 0.0),
                            ],
                          ),
                        ),
                        child: const SizedBox(width: 280, height: 280),
                      ),
                    ),
                  ),
                  Positioned(
                    left: -90,
                    bottom: 80,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            colors: [
                              AppTheme.brandCoral.withValues(alpha: 0.14),
                              Colors.transparent,
                            ],
                          ),
                        ),
                        child: const SizedBox(width: 240, height: 240),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 40,
                    top: 120,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.04),
                          shape: BoxShape.circle,
                        ),
                        child: const SizedBox(width: 90, height: 90),
                      ),
                    ),
                  ),
                  SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(
                      AppTheme.pagePadding,
                      28,
                      AppTheme.pagePadding,
                      24,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight > 52
                              ? constraints.maxHeight - 52
                              : 0,
                          maxWidth: AppTheme.pageMaxWidth,
                        ),
                        child: IntrinsicHeight(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Spacer(),
                              Semantics(
                                image: true,
                                label: '산보 로고',
                                child: Center(
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(36),
                                      boxShadow: [
                                        BoxShadow(
                                          color: AppTheme.brandTeal
                                              .withValues(alpha: 0.28),
                                          blurRadius: 36,
                                          offset: const Offset(0, 14),
                                        ),
                                      ],
                                    ),
                                    child: const BrandMark(size: 118),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 32),
                              Semantics(
                                header: true,
                                child: Text(
                                  AppInfo.nameKo,
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.displaySmall?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -1.0,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                AppInfo.tagline,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.titleLarge?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.92),
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                '걸음을 기록하고, 하루의 흐름을 돌아보세요.',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.72),
                                  height: 1.55,
                                ),
                              ),
                              const Spacer(flex: 2),
                              Semantics(
                                button: true,
                                enabled: !_isContinuing,
                                label: '산보 시작하기',
                                child: FilledButton(
                                  onPressed: _isContinuing ? null : _continue,
                                  style: FilledButton.styleFrom(
                                    minimumSize: const Size.fromHeight(56),
                                    backgroundColor: AppTheme.brandTeal,
                                    foregroundColor: AppTheme.brandNavy,
                                    disabledBackgroundColor: AppTheme.brandTeal
                                        .withValues(alpha: 0.55),
                                    disabledForegroundColor: AppTheme.brandNavy
                                        .withValues(alpha: 0.7),
                                  ),
                                  child: _isContinuing
                                      ? const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(
                                                color: AppTheme.brandNavy,
                                                strokeWidth: 2,
                                              ),
                                            ),
                                            SizedBox(width: 10),
                                            Text('저장 중…'),
                                          ],
                                        )
                                      : const Text('시작하기'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _continue() async {
    if (_isContinuing) return;

    setState(() {
      _isContinuing = true;
    });
    try {
      await ref.read(appFlagsStoreProvider).setHasSeenIntro(true);
      if (!mounted) return;
      ref.read(introSeenProvider.notifier).state = true;
      context.go('/');
    } on Object {
      if (!mounted) return;
      setState(() {
        _isContinuing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('시작 정보를 저장하지 못했어요. 다시 시도해 주세요.'),
          action: SnackBarAction(
            label: '다시 시도',
            onPressed: () => unawaited(_continue()),
          ),
        ),
      );
    }
  }
}
