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
  var _saveFailed = false;

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
                    top: -56,
                    right: -48,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: AppTheme.brandTeal.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const SizedBox(width: 196, height: 196),
                      ),
                    ),
                  ),
                  Positioned(
                    left: -64,
                    bottom: 104,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          shape: BoxShape.circle,
                        ),
                        child: const SizedBox(width: 148, height: 148),
                      ),
                    ),
                  ),
                  SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(
                      AppTheme.pagePadding,
                      24,
                      AppTheme.pagePadding,
                      20,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight > 44
                              ? constraints.maxHeight - 44
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
                                child: const Center(
                                  child: BrandMark(size: 112),
                                ),
                              ),
                              const SizedBox(height: 28),
                              Semantics(
                                header: true,
                                child: Text(
                                  AppInfo.nameKo,
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.displaySmall?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.8,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                AppInfo.tagline,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.titleLarge?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.9),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                '걸음을 기록하고, 하루의 흐름을 돌아보세요.',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.76),
                                ),
                              ),
                              if (_saveFailed) ...[
                                const SizedBox(height: 16),
                                Semantics(
                                  liveRegion: true,
                                  child: Text(
                                    '저장하지 못했어요. 다시 시도해 주세요.',
                                    textAlign: TextAlign.center,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: Colors.white.withValues(
                                        alpha: 0.9,
                                      ),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                              const Spacer(flex: 2),
                              Semantics(
                                button: true,
                                enabled: !_isContinuing,
                                label: '산보 시작하기',
                                child: FilledButton(
                                  onPressed: _isContinuing ? null : _continue,
                                  style: FilledButton.styleFrom(
                                    minimumSize: const Size.fromHeight(54),
                                    backgroundColor: AppTheme.brandTeal,
                                    foregroundColor: AppTheme.brandNavy,
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
      _saveFailed = false;
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
        _saveFailed = true;
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
