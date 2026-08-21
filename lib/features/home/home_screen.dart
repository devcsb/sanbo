import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../platform/location/location_engine.dart';
import '../../data/walk_repository.dart';
import '../../domain/models/session_warning.dart';
import '../../domain/models/walk_session.dart';
import '../../shared/widgets/ui_bits.dart';
import '../history/history_providers.dart';
import '../intro/intro_providers.dart';
import '../settings/tracking_mode_setting.dart';
import 'discard_confirm.dart';
import 'session_controller.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final live = ref.watch(sessionControllerProvider);
    final theme = Theme.of(context);
    final tracking = live.isTracking;
    final busy = live.isBusy;
    final recovery = live.needsRecovery && live.session != null && !tracking;
    final mode = ref.watch(trackingModeSettingProvider);
    final startMode = recovery ? live.session!.trackingMode : mode;
    final needsSystemSettings =
        live.permissionState == LocationPermissionState.deniedForever ||
        live.permissionState == LocationPermissionState.serviceDisabled ||
        (live.errorMessage != null &&
            (live.errorMessage!.contains('설정') ||
                live.errorMessage!.contains('알림') ||
                live.errorMessage!.contains('권한')));
    final km = live.liveDistanceM / 1000.0;
    final kmh = live.liveSpeedMps * 3.6;

    return Scaffold(
      appBar: AppBar(title: const AppBarTitle('산보', showBrand: true)),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AppTheme.pagePadding,
                10,
                AppTheme.pagePadding,
                36,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: AppTheme.pageMaxWidth,
                    minHeight: constraints.maxHeight > 40
                        ? constraints.maxHeight - 40
                        : 0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      PageIntro(
                        title: tracking
                            ? '기록 중'
                            : recovery
                            ? '이어갈 산책'
                            : '산책을 시작할까요?',
                        description: tracking
                            ? _trackingDescription(live)
                            : recovery
                            ? (live.statusMessage ??
                                  '끝내지 못한 기록이 있어요. 이어서 걷거나 저장할 수 있습니다.')
                            : '걸은 길과 멈춘 순간을 시간 흐름으로 남깁니다.',
                      ),
                      if (live.errorMessage != null) ...[
                        const SizedBox(height: 14),
                        _ErrorBanner(
                          message: live.errorMessage!,
                          onDismiss: () => ref
                              .read(sessionControllerProvider.notifier)
                              .clearError(),
                          onRetry: busy
                              ? null
                              : () {
                                  final controller = ref.read(
                                    sessionControllerProvider.notifier,
                                  );
                                  unawaited(
                                    live.canRetryRecovery
                                        ? controller.retryRecovery()
                                        : controller.start(mode: startMode),
                                  );
                                },
                          onOpenSettings: needsSystemSettings && !busy
                              ? () {
                                  unawaited(
                                    ref
                                        .read(locationEngineProvider)
                                        .openSystemSettings(),
                                  );
                                }
                              : null,
                        ),
                      ],
                      if (!tracking &&
                          !recovery &&
                          live.errorMessage == null &&
                          live.notice != null) ...[
                        const SizedBox(height: 14),
                        _NoticeBanner(
                          message: live.notice!,
                          onDismiss: () => ref
                              .read(sessionControllerProvider.notifier)
                              .clearNotice(),
                        ),
                      ],
                      if ((tracking || recovery) &&
                          live.activeWarning != null) ...[
                        const SizedBox(height: 14),
                        _SessionWarningBanner(
                          warning: live.activeWarning!,
                          busy: busy,
                          onContinue: () {
                            unawaited(
                              ref
                                  .read(sessionControllerProvider.notifier)
                                  .continueAfterWarning(),
                            );
                          },
                          onStop: () => _finishAndOpenSummary(
                            context,
                            ref,
                            ref
                                .read(sessionControllerProvider.notifier)
                                .stopFromHighSpeedWarning,
                          ),
                        ),
                      ],
                      if (recovery) ...[
                        const SizedBox(height: 16),
                        _RecoveryCard(
                          busy: busy,
                          onContinue: () {
                            unawaited(HapticFeedback.selectionClick());
                            unawaited(
                              ref
                                  .read(sessionControllerProvider.notifier)
                                  .start(mode: startMode),
                            );
                          },
                          onSaveAndEnd: () => _finishAndOpenSummary(
                            context,
                            ref,
                            ref.read(sessionControllerProvider.notifier).stop,
                          ),
                          onDiscard: () => _confirmDiscard(context, ref),
                        ),
                      ],
                      const SizedBox(height: 24),
                      Semantics(
                        // Idle metrics are all zeros — skip the concatenated
                        // announcement so a screen reader isn't read a wall of
                        // meaningless "0" before reaching the start button.
                        label: (tracking || recovery)
                            ? '시간 ${_formatDuration(live.elapsed)}, 거리 ${km.toStringAsFixed(2)} 킬로미터, 속도 ${kmh.toStringAsFixed(1)} 시속, 위치 ${live.sampleCount}개'
                            : null,
                        excludeSemantics: tracking || recovery,
                        child: MetricStrip(
                          header: tracking
                              ? Align(
                                  alignment: Alignment.center,
                                  child: StatusPill(
                                    label: live.sampleCount == 0
                                        ? 'GPS 잡는 중'
                                        : '기록 중 · 위치 ${live.sampleCount}',
                                    icon: Icons.fiber_manual_record_rounded,
                                    color: theme.colorScheme.tertiary,
                                  ),
                                )
                              : null,
                          metrics: [
                            MetricData(
                              label: '시간',
                              value: _formatDuration(live.elapsed),
                              emphasize: tracking,
                            ),
                            MetricData(
                              label: '거리',
                              value: '${km.toStringAsFixed(2)} km',
                            ),
                            MetricData(
                              label: '속도',
                              value: '${kmh.toStringAsFixed(1)} km/h',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      if (tracking)
                        Semantics(
                          button: true,
                          label: '산책 종료',
                          child: FilledButton(
                            onPressed: busy
                                ? null
                                : () {
                                    unawaited(HapticFeedback.mediumImpact());
                                    unawaited(
                                      _finishAndOpenSummary(
                                        context,
                                        ref,
                                        ref
                                            .read(
                                              sessionControllerProvider
                                                  .notifier,
                                            )
                                            .stop,
                                      ),
                                    );
                                  },
                            style: FilledButton.styleFrom(
                              backgroundColor: theme.colorScheme.tertiary,
                              foregroundColor: theme.colorScheme.onTertiary,
                              minimumSize: const Size.fromHeight(52),
                            ),
                            child: _BusyButtonContent(
                              label: '산책 종료',
                              busy: busy,
                              progressColor: theme.colorScheme.onTertiary,
                            ),
                          ),
                        )
                      else if (!recovery)
                        Semantics(
                          button: true,
                          label: '산책 시작',
                          child: FilledButton(
                            onPressed: busy
                                ? null
                                : () {
                                    unawaited(HapticFeedback.mediumImpact());
                                    unawaited(
                                      ref
                                          .read(
                                            sessionControllerProvider.notifier,
                                          )
                                          .start(mode: mode),
                                    );
                                  },
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(52),
                            ),
                            child: _BusyButtonContent(
                              label: '산책 시작',
                              busy: busy,
                              progressColor: theme.colorScheme.onPrimary,
                            ),
                          ),
                        ),
                      if (_shouldShowPermissionHint(live.permissionState)) ...[
                        const SizedBox(height: 12),
                        Text(
                          _permissionHint(live.permissionState),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ] else
                        const SizedBox(height: 4),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _confirmDiscard(BuildContext context, WidgetRef ref) async {
    final ok = await confirmDiscardIncompleteWalk(context);
    if (ok) {
      await ref.read(sessionControllerProvider.notifier).discardActive();
    }
  }

  String _trackingDescription(LiveSessionState live) {
    if (live.sampleCount == 0) {
      final elapsed = live.elapsed.inSeconds;
      if (elapsed >= 15) {
        return '아직 GPS가 안 잡히고 있어요. 정확한 위치 권한과 기기 위치 서비스가 켜져 있는지 확인해 주세요.';
      }
      return 'GPS를 잡는 중이에요. 첫 신호까지 수 초~1분 걸릴 수 있어요.';
    }
    if (live.validSampleCount == 0) {
      final acc = live.lastAccuracyM;
      if (acc != null) {
        return '위치를 받는 중이에요 (정확도 ±${acc.toStringAsFixed(0)} m). 야외에서 더 잘 잡힙니다.';
      }
      return '위치를 받는 중이에요. 야외에서 더 잘 잡힙니다.';
    }
    return live.statusMessage ?? '위치를 기록하고 있어요';
  }

  bool _shouldShowPermissionHint(LocationPermissionState p) {
    return p != LocationPermissionState.granted &&
        p != LocationPermissionState.unknown;
  }

  String _permissionHint(LocationPermissionState p) {
    return switch (p) {
      LocationPermissionState.granted => '',
      LocationPermissionState.denied => '시작 시 위치 권한을 요청합니다',
      LocationPermissionState.deniedForever => '설정에서 위치 권한을 허용해 주세요',
      LocationPermissionState.serviceDisabled => '기기의 위치 서비스를 켜 주세요',
      LocationPermissionState.unknown => '',
    };
  }
}

Future<void> _finishAndOpenSummary(
  BuildContext context,
  WidgetRef ref,
  Future<WalkSession?> Function() stop,
) async {
  final ended = await stop();
  if (ended == null || !context.mounted) return;
  ref.read(historyTickProvider.notifier).state++;
  context.go('/history/${ended.id}');
  unawaited(_celebrateMilestones(context, ref, ended));
}

Future<void> _celebrateMilestones(
  BuildContext context,
  WidgetRef ref,
  WalkSession ended,
) async {
  try {
    final stats = await ref.read(walkRepositoryProvider).completedStats();
    final flagsStore = ref.read(appFlagsStoreProvider);
    final flags = await flagsStore.load();
    final newly = stats.newlyUnlocked(flags.unlockedMilestones, latest: ended);
    if (newly.isEmpty) return;
    await flagsStore.unlockMilestones(newly.map((m) => m.id));
    if (!context.mounted) return;
    final first = newly.first;
    final more = newly.length > 1 ? ' 외 ${newly.length - 1}개' : '';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${first.title}$more'),
        duration: const Duration(seconds: 3),
      ),
    );
  } on Object {
    // Quiet: milestones are optional delight, never block navigation.
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({
    required this.message,
    required this.onDismiss,
    this.onRetry,
    this.onOpenSettings,
  });

  final String message;
  final VoidCallback onDismiss;
  final VoidCallback? onRetry;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      liveRegion: true,
      child: SoftPanel(
        elevated: false,
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.92),
        padding: const EdgeInsets.fromLTRB(14, 12, 4, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  size: 20,
                  color: theme.colorScheme.onErrorContainer,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    message,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onErrorContainer,
                      height: 1.4,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '닫기',
                  onPressed: onDismiss,
                  style: IconButton.styleFrom(
                    minimumSize: const Size.square(48),
                  ),
                  icon: Icon(
                    Icons.close_rounded,
                    size: 20,
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
              ],
            ),
            if (onRetry != null || onOpenSettings != null)
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  spacing: 4,
                  children: [
                    if (onOpenSettings != null)
                      TextButton(
                        onPressed: onOpenSettings,
                        child: Text(
                          '설정 열기',
                          style: TextStyle(
                            color: theme.colorScheme.onErrorContainer,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    if (onRetry != null)
                      TextButton(
                        onPressed: onRetry,
                        child: Text(
                          '다시 시도',
                          style: TextStyle(
                            color: theme.colorScheme.onErrorContainer,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Calm neutral note for benign outcomes (e.g. "walk too short, not saved").
/// Deliberately not the red [_ErrorBanner] — the outcome is expected, not a fault.
class _NoticeBanner extends StatelessWidget {
  const _NoticeBanner({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      liveRegion: true,
      child: SoftPanel(
        elevated: false,
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.9),
        padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.info_outline_rounded,
              size: 20,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface,
                  height: 1.4,
                ),
              ),
            ),
            IconButton(
              tooltip: '닫기',
              onPressed: onDismiss,
              style: IconButton.styleFrom(minimumSize: const Size.square(48)),
              icon: Icon(
                Icons.close_rounded,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionWarningBanner extends StatelessWidget {
  const _SessionWarningBanner({
    required this.warning,
    required this.busy,
    required this.onContinue,
    required this.onStop,
  });

  final SessionWarning warning;
  final bool busy;
  final VoidCallback onContinue;
  final Future<void> Function() onStop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SoftPanel(
      elevated: false,
      color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.92),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            container: true,
            liveRegion: true,
            label: '${warning.title}. ${warning.message}',
            excludeSemantics: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.timer_outlined,
                  size: 20,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        warning.title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.onSecondaryContainer,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        warning.message,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSecondaryContainer,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (warning.actions.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 4,
              children: [
                if (warning.actions.contains(
                  SessionWarningAction.stopRecording,
                ))
                  FilledButton(
                    onPressed: busy
                        ? null
                        : () {
                            unawaited(onStop());
                          },
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(48, 48),
                    ),
                    child: const Text('기록 종료'),
                  ),
                if (warning.actions.contains(
                  SessionWarningAction.continueRecording,
                ))
                  TextButton(
                    onPressed: busy ? null : onContinue,
                    style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.onSecondaryContainer,
                      minimumSize: const Size(48, 48),
                    ),
                    child: const Text('계속 기록'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _RecoveryCard extends StatelessWidget {
  const _RecoveryCard({
    required this.busy,
    required this.onContinue,
    required this.onSaveAndEnd,
    required this.onDiscard,
  });

  final bool busy;
  final VoidCallback onContinue;
  final Future<void> Function() onSaveAndEnd;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SoftPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('미완료 기록', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            '이어서 걷거나, 지금까지를 저장하세요.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: busy ? null : onContinue,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
            child: _BusyButtonContent(
              label: '이어서 기록',
              busy: busy,
              progressColor: theme.colorScheme.onPrimary,
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: busy
                ? null
                : () {
                    unawaited(onSaveAndEnd());
                  },
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
            child: _BusyButtonContent(
              label: '저장하고 종료',
              busy: busy,
              progressColor: theme.colorScheme.primary,
            ),
          ),
          TextButton(
            onPressed: busy ? null : onDiscard,
            style: TextButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            child: Text(
              '기록 지우기',
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
        ],
      ),
    );
  }
}

class _BusyButtonContent extends StatelessWidget {
  const _BusyButtonContent({
    required this.label,
    required this.busy,
    required this.progressColor,
  });

  final String label;
  final bool busy;
  final Color progressColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (busy) ...[
          SizedBox(
            height: 18,
            width: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: progressColor,
            ),
          ),
          const SizedBox(width: 8),
        ],
        Text(label),
      ],
    );
  }
}

String _formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (h > 0) return '$h:$m:$s';
  return '$m:$s';
}
