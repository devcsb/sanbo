import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../data/walk_repository.dart';
import '../../domain/models/activity_label.dart';
import '../../domain/models/location_sample.dart';
import '../../domain/models/minute_window.dart';
import '../../domain/models/walk_session.dart';
import '../../shared/widgets/route_map.dart';
import '../../shared/widgets/ui_bits.dart';
import '../history/history_providers.dart';
import 'timeline_copy.dart';

final sessionDetailProvider = FutureProvider.autoDispose
    .family<SessionDetailData?, String>((ref, id) async {
      ref.watch(historyTickProvider);
      final repo = ref.watch(walkRepositoryProvider);
      final session = await repo.getSession(id);
      if (session == null) return null;
      final samples = await repo.getSamples(id);
      final windows = await repo.getWindows(id);
      return SessionDetailData(
        session: session,
        samples: samples,
        windows: windows,
      );
    });

final _detailCommandBusyProvider = StateProvider.autoDispose
    .family<bool, String>((ref, id) => false);

class SessionDetailData {
  const SessionDetailData({
    required this.session,
    required this.samples,
    required this.windows,
  });

  final WalkSession session;
  final List<LocationSample> samples;
  final List<MinuteWindow> windows;
}

class SessionDetailScreen extends ConsumerWidget {
  const SessionDetailScreen({required this.sessionId, super.key});

  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(sessionDetailProvider(sessionId));
    final commandBusy = ref.watch(_detailCommandBusyProvider(sessionId));
    final hasLoadedData = async.hasValue && async.valueOrNull != null;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const AppBarTitle('산책 요약'),
        actions: [
          if (hasLoadedData)
            IconButton(
              tooltip: '삭제',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: commandBusy
                  ? null
                  : () => _confirmDelete(context, ref),
            ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => EmptyStateView(
          icon: Icons.error_outline_rounded,
          title: '요약을 불러오지 못했어요',
          message: '잠시 후 다시 시도해 주세요.',
          actionLabel: '다시 시도',
          onAction: () => ref.invalidate(sessionDetailProvider(sessionId)),
        ),
        data: (data) {
          if (data == null) {
            return EmptyStateView(
              icon: Icons.search_off_rounded,
              title: '기록을 찾을 수 없어요',
              message: '삭제되었거나 잘못된 주소일 수 있어요.',
              actionLabel: '기록으로',
              onAction: () => context.go('/history'),
            );
          }

          final session = data.session;
          final dateFmt = DateFormat('yyyy.MM.dd  HH:mm', 'ko');
          final km = (session.totalDistanceM ?? 0) / 1000.0;
          final dur = Duration(seconds: session.durationS ?? 0);
          final kmh = (session.avgSpeedMps ?? 0) * 3.6;
          final points = data.samples
              .where((s) => !s.isFilteredOut)
              .map((s) => (lat: s.latitude, lon: s.longitude))
              .toList();

          return PageFrame(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                PageIntro(
                  eyebrow: '산책 기록',
                  title: dateFmt.format(session.startedAt),
                  description: '경로와 활동 흐름을 차분히 돌아보세요.',
                ),
                const SizedBox(height: 24),
                const SectionLabel('산책 경로'),
                RouteMap(
                  points: points,
                  height: 220,
                  offlinePreview:
                      !kIsWeb &&
                      Platform.environment.containsKey('FLUTTER_TEST'),
                ),
                const SizedBox(height: 24),
                const SectionLabel('핵심 기록'),
                MetricStrip(
                  metrics: [
                    MetricData(
                      label: '거리',
                      value: '${km.toStringAsFixed(2)} km',
                      emphasize: true,
                    ),
                    MetricData(label: '시간', value: _fmt(dur)),
                    MetricData(
                      label: '평균 속도',
                      value: '${kmh.toStringAsFixed(1)} km/h',
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const SectionLabel('기록 세부 정보'),
                _SecondaryMetricStrip(
                  metrics: [
                    MetricData(
                      label: '이동 시간',
                      value: _optionalDuration(session.movingTimeS),
                    ),
                    MetricData(
                      label: '정지 시간',
                      value: _optionalDuration(session.stationaryTimeS),
                    ),
                    MetricData(
                      label: 'GPS 유효 좌표',
                      value: session.validSampleCount == null
                          ? '측정되지 않음'
                          : '${session.validSampleCount}개',
                    ),
                    MetricData(
                      label: '중앙 정확도',
                      value: session.medianAccuracyM == null
                          ? '측정되지 않음'
                          : '±${session.medianAccuracyM!.toStringAsFixed(1)} m',
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                const SectionLabel('시간대별 활동'),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const StatusPill(
                      label: '탭하여 수정',
                      icon: Icons.edit_outlined,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '탭하면 활동을 수정할 수 있어요',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (data.windows.isEmpty)
                  SoftPanel(
                    child: Text(
                      '구간이 없어요. 짧은 산책이거나 위치 기록이 부족했을 수 있습니다.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                else
                  SoftPanel(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (var i = 0; i < data.windows.length; i++) ...[
                          if (i > 0)
                            Divider(
                              height: 1,
                              indent: 16,
                              endIndent: 16,
                              color: theme.colorScheme.outlineVariant
                                  .withValues(alpha: 0.6),
                            ),
                          _TimelineRow(
                            window: data.windows[i],
                            onTap: commandBusy
                                ? null
                                : () => _editLabel(
                                    context,
                                    ref,
                                    sessionId,
                                    data.windows[i],
                                  ),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        return AlertDialog(
          title: const Text('기록 삭제'),
          content: const Text('이 산책을 삭제합니다. 되돌릴 수 없어요.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: scheme.error,
                foregroundColor: scheme.onError,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('삭제'),
            ),
          ],
        );
      },
    );
    if (ok != true) return;

    ref.read(_detailCommandBusyProvider(sessionId).notifier).state = true;
    try {
      await ref.read(walkRepositoryProvider).deleteSession(sessionId);
      ref.read(historyTickProvider.notifier).state++;
      ref.read(_detailCommandBusyProvider(sessionId).notifier).state = false;
      if (context.mounted) context.go('/history');
    } on Object {
      ref.read(_detailCommandBusyProvider(sessionId).notifier).state = false;
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('기록을 삭제하지 못했어요. 다시 시도해 주세요.')),
        );
      }
    }
  }

  Future<void> _editLabel(
    BuildContext context,
    WidgetRef ref,
    String sessionId,
    MinuteWindow w,
  ) async {
    final selected = await showModalBottomSheet<ActivityLabel>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Text('활동 선택', style: theme.textTheme.titleMedium),
              ),
              for (final label in ActivityLabel.values)
                ListTile(
                  title: Text(label.labelKo),
                  trailing: w.displayLabel == label
                      ? Icon(
                          Icons.check_rounded,
                          color: theme.colorScheme.primary,
                        )
                      : null,
                  onTap: () => Navigator.pop(ctx, label),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (selected == null) return;
    ref.read(_detailCommandBusyProvider(sessionId).notifier).state = true;
    try {
      await ref
          .read(walkRepositoryProvider)
          .updateWindowUserLabel(
            sessionId: sessionId,
            windowStart: w.windowStart,
            userLabel: selected,
          );
      ref.read(historyTickProvider.notifier).state++;
    } on Object {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('활동을 저장하지 못했어요. 다시 시도해 주세요.')),
        );
      }
    } finally {
      ref.read(_detailCommandBusyProvider(sessionId).notifier).state = false;
    }
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) return '${d.inHours}:$m:$s';
    return '$m:$s';
  }

  String _optionalDuration(int? seconds) {
    if (seconds == null) return '측정되지 않음';
    return _fmt(Duration(seconds: seconds));
  }
}

class _SecondaryMetricStrip extends StatelessWidget {
  const _SecondaryMetricStrip({required this.metrics});

  final List<MetricData> metrics;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SoftPanel(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stackMetrics =
              constraints.maxWidth < 300 ||
              MediaQuery.textScalerOf(context).scale(16) > 20;
          final itemWidth = stackMetrics
              ? constraints.maxWidth
              : (constraints.maxWidth - 16) / 2;
          return Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              for (final metric in metrics)
                SizedBox(
                  width: itemWidth,
                  child: Semantics(
                    label: '${metric.label} ${metric.value}',
                    excludeSemantics: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          metric.label,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          metric.value,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.window, required this.onTap});

  final MinuteWindow window;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final time = DateFormat('HH:mm').format(window.windowStart);
    final confirmed = window.userConfirmed;
    final label = window.displayLabel.labelKo;
    final status = StatusPill(
      label: confirmed ? '확정' : '추정',
      color: confirmed
          ? theme.colorScheme.primary
          : theme.colorScheme.secondary,
    );
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.titleSmall),
        const SizedBox(height: 2),
        Text(
          timelineWindowSubtitle(window),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );

    return Semantics(
      button: true,
      label: '$time $label${confirmed ? ' 확정' : ' 추정'}. 탭하여 수정',
      enabled: onTap != null,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final useStackedLayout =
                    constraints.maxWidth < 280 ||
                    MediaQuery.textScalerOf(context).scale(14) > 20;
                if (useStackedLayout) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            time,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                          status,
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: details),
                          const SizedBox(width: 12),
                          Icon(
                            Icons.edit_outlined,
                            size: 20,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 48,
                      child: Text(
                        time,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  label,
                                  style: theme.textTheme.titleSmall,
                                ),
                              ),
                              const SizedBox(width: 8),
                              status,
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            timelineWindowSubtitle(window),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Icon(
                      Icons.edit_outlined,
                      size: 20,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
