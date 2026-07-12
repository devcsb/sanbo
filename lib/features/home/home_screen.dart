import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../platform/location/location_engine.dart';
import '../history/history_providers.dart';
import '../settings/settings_screen.dart';
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

    return Scaffold(
      appBar: AppBar(title: const Text('산보')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                tracking
                    ? '산책 기록 중'
                    : recovery
                        ? '이어갈 산책이 있어요'
                        : '오늘의 산책을 남겨 볼까요?',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                tracking
                    ? (live.statusMessage ?? '위치를 기록하고 있어요')
                    : recovery
                        ? (live.statusMessage ??
                            '이전에 끝내지 못한 산책입니다. 이어서 기록하거나 저장·삭제할 수 있어요.')
                        : '걸은 길, 멈춘 순간, 분 단위 활동을\n지도와 함께 이 기기에만 저장합니다.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (live.errorMessage != null) ...[
                const SizedBox(height: 12),
                _ErrorBanner(
                  message: live.errorMessage!,
                  onDismiss: () =>
                      ref.read(sessionControllerProvider.notifier).clearError(),
                  onRetry: busy
                      ? null
                      : () {
                          unawaited(
                            ref
                                .read(sessionControllerProvider.notifier)
                                .start(mode: mode),
                          );
                        },
                ),
              ],
              if (recovery) ...[
                const SizedBox(height: 16),
                _RecoveryCard(
                  busy: busy,
                  onContinue: () {
                    unawaited(
                      ref
                          .read(sessionControllerProvider.notifier)
                          .start(mode: mode),
                    );
                  },
                  onSaveAndEnd: () async {
                    final ended = await ref
                        .read(sessionControllerProvider.notifier)
                        .stop();
                    if (!context.mounted) return;
                    ref.read(historyTickProvider.notifier).state++;
                    if (ended != null) {
                      context.go('/history/${ended.id}');
                    }
                  },
                  onDiscard: () => _confirmDiscard(context, ref),
                ),
              ],
              const Spacer(),
              _LiveStats(
                elapsed: live.elapsed,
                distanceM: live.liveDistanceM,
                speedMps: live.liveSpeedMps,
                active: tracking,
                sampleCount: live.sampleCount,
              ),
              const Spacer(),
              // Primary CTA hierarchy (AST-H1): one dominant action.
              if (tracking)
                FilledButton(
                  onPressed: busy
                      ? null
                      : () async {
                          final ended = await ref
                              .read(sessionControllerProvider.notifier)
                              .stop();
                          if (!context.mounted) return;
                          ref.read(historyTickProvider.notifier).state++;
                          if (ended != null) {
                            context.go('/history/${ended.id}');
                          }
                        },
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                    backgroundColor: theme.colorScheme.error,
                    foregroundColor: theme.colorScheme.onError,
                  ),
                  child: busy
                      ? SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: theme.colorScheme.onError,
                          ),
                        )
                      : const Text('산책 종료'),
                )
              else if (!recovery)
                FilledButton(
                  onPressed: busy
                      ? null
                      : () {
                          unawaited(
                            ref
                                .read(sessionControllerProvider.notifier)
                                .start(mode: mode),
                          );
                        },
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                  ),
                  child: busy
                      ? SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: theme.colorScheme.onPrimary,
                          ),
                        )
                      : const Text('산책 시작'),
                ),
              if (_shouldShowPermissionHint(live.permissionState)) ...[
                const SizedBox(height: 12),
                Text(
                  _permissionHint(live.permissionState),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
              const SizedBox(height: 8),
            ],
          ),
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

  bool _shouldShowPermissionHint(LocationPermissionState p) {
    return p != LocationPermissionState.granted &&
        p != LocationPermissionState.unknown;
  }

  String _permissionHint(LocationPermissionState p) {
    return switch (p) {
      LocationPermissionState.granted => '',
      LocationPermissionState.denied => '시작을 누르면 위치 권한을 요청합니다',
      LocationPermissionState.deniedForever => '설정에서 위치 권한을 허용해 주세요',
      LocationPermissionState.serviceDisabled => '기기의 위치 서비스를 켜 주세요',
      LocationPermissionState.unknown => '',
    };
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({
    required this.message,
    required this.onDismiss,
    this.onRetry,
  });

  final String message;
  final VoidCallback onDismiss;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.errorContainer,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 4, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 20,
                  color: theme.colorScheme.onErrorContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    message,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onErrorContainer,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '닫기',
                  onPressed: onDismiss,
                  icon: Icon(
                    Icons.close,
                    size: 20,
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
              ],
            ),
            if (onRetry != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: onRetry,
                  child: Text(
                    '다시 시도',
                    style: TextStyle(color: theme.colorScheme.onErrorContainer),
                  ),
                ),
              ),
          ],
        ),
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '미완료 산책',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '이어서 걸을지, 지금까지를 저장할지 선택하세요.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: busy ? null : onContinue,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              child: busy
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('이어서 기록'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: busy
                  ? null
                  : () {
                      unawaited(onSaveAndEnd());
                    },
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              child: const Text('저장하고 종료'),
            ),
            TextButton(
              onPressed: busy ? null : onDiscard,
              child: Text(
                '이 기록 지우기',
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LiveStats extends StatelessWidget {
  const _LiveStats({
    required this.elapsed,
    required this.distanceM,
    required this.speedMps,
    required this.active,
    required this.sampleCount,
  });

  final Duration elapsed;
  final double distanceM;
  final double speedMps;
  final bool active;
  final int sampleCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final km = distanceM / 1000.0;
    final kmh = speedMps * 3.6;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _Stat(
                    label: '시간',
                    value: _formatDuration(elapsed),
                    emphasize: active,
                  ),
                ),
                Container(
                  width: 1,
                  height: 48,
                  color: theme.colorScheme.outlineVariant,
                ),
                Expanded(
                  child: _Stat(
                    label: '거리',
                    value: '${km.toStringAsFixed(2)} km',
                  ),
                ),
                Container(
                  width: 1,
                  height: 48,
                  color: theme.colorScheme.outlineVariant,
                ),
                Expanded(
                  child: _Stat(
                    label: '속도',
                    value: '${kmh.toStringAsFixed(1)} km/h',
                  ),
                ),
              ],
            ),
            if (active && sampleCount > 0) ...[
              const SizedBox(height: 12),
              Text(
                '위치 $sampleCount곳 기록됨',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (h > 0) return '$h:$m:$s';
    return '$m:$s';
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: emphasize ? theme.colorScheme.primary : null,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}
