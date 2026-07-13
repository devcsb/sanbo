import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../platform/location/location_engine.dart';
import '../../shared/widgets/ui_bits.dart';
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
    final needsSystemSettings =
        live.permissionState == LocationPermissionState.deniedForever ||
            live.permissionState == LocationPermissionState.serviceDisabled;

    return Scaffold(
      appBar: AppBar(
        title: const AppBarTitle('산보', showBrand: true),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                tracking
                    ? '기록 중'
                    : recovery
                        ? '이어갈 산책'
                        : '산책을 시작할까요?',
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 6),
              Text(
                tracking
                    ? (live.statusMessage ?? '위치를 기록하고 있어요')
                    : recovery
                        ? (live.statusMessage ??
                            '끝내지 못한 기록이 있어요. 이어서 걷거나 저장할 수 있습니다.')
                        : '걸은 길과 멈춘 순간을 분 단위로 남깁니다.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (live.errorMessage != null) ...[
                const SizedBox(height: 14),
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
                  onOpenSettings: needsSystemSettings && !busy
                      ? () {
                          unawaited(
                            ref.read(locationEngineProvider).openSystemSettings(),
                          );
                        }
                      : null,
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
              ),
              const Spacer(),
              if (tracking)
                Semantics(
                  button: true,
                  label: '산책 종료',
                  child: FilledButton(
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
                      backgroundColor: theme.colorScheme.error,
                      foregroundColor: theme.colorScheme.onError,
                      minimumSize: const Size.fromHeight(52),
                    ),
                    child: busy
                        ? SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: theme.colorScheme.onError,
                            ),
                          )
                        : const Text('산책 종료'),
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
                            unawaited(
                              ref
                                  .read(sessionControllerProvider.notifier)
                                  .start(mode: mode),
                            );
                          },
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                    child: busy
                        ? SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: theme.colorScheme.onPrimary,
                            ),
                          )
                        : const Text('산책 시작'),
                  ),
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
              ] else
                const SizedBox(height: 4),
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
      LocationPermissionState.denied => '시작 시 위치 권한을 요청합니다',
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
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Padding(
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
                    visualDensity: VisualDensity.compact,
                    onPressed: onDismiss,
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
          Text(
            '미완료 기록',
            style: theme.textTheme.titleSmall,
          ),
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
            child: busy
                ? SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: theme.colorScheme.primary,
                    ),
                  )
                : const Text('저장하고 종료'),
          ),
          TextButton(
            onPressed: busy ? null : onDiscard,
            style: TextButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
            ),
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

class _LiveStats extends StatelessWidget {
  const _LiveStats({
    required this.elapsed,
    required this.distanceM,
    required this.speedMps,
    required this.active,
  });

  final Duration elapsed;
  final double distanceM;
  final double speedMps;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final km = distanceM / 1000.0;
    final kmh = speedMps * 3.6;

    return SoftPanel(
      padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 8),
      child: Column(
        children: [
          if (active)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '기록 중',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
            ),
          Semantics(
            label:
                '시간 ${_formatDuration(elapsed)}, 거리 ${km.toStringAsFixed(2)} 킬로미터, 속도 ${kmh.toStringAsFixed(1)} 시속',
            child: Row(
              children: [
                Expanded(
                  child: MetricTile(
                    label: '시간',
                    value: _formatDuration(elapsed),
                    emphasize: active,
                  ),
                ),
                _VRule(theme: theme),
                Expanded(
                  child: MetricTile(
                    label: '거리',
                    value: '${km.toStringAsFixed(2)} km',
                  ),
                ),
                _VRule(theme: theme),
                Expanded(
                  child: MetricTile(
                    label: '속도',
                    value: '${kmh.toStringAsFixed(1)} km/h',
                  ),
                ),
              ],
            ),
          ),
        ],
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

class _VRule extends StatelessWidget {
  const _VRule({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 40,
      color: theme.colorScheme.outlineVariant.withValues(alpha: 0.8),
    );
  }
}
