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

final sessionDetailProvider =
    FutureProvider.family<SessionDetailData?, String>((ref, id) async {
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
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('산책 요약'),
        actions: [
          IconButton(
            tooltip: '삭제',
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: () => _confirmDelete(context, ref),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const EmptyStateView(
          icon: Icons.error_outline_rounded,
          title: '요약을 불러오지 못했어요',
          message: '잠시 후 다시 시도해 주세요.',
        ),
        data: (data) {
          if (data == null) {
            return const EmptyStateView(
              icon: Icons.search_off_rounded,
              title: '기록을 찾을 수 없어요',
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

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            children: [
              RouteMap(
                points: points,
                height: 200,
                offlinePreview: !kIsWeb &&
                    Platform.environment.containsKey('FLUTTER_TEST'),
              ),
              const SizedBox(height: 16),
              Text(
                dateFmt.format(session.startedAt),
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              SoftPanel(
                padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: MetricTile(
                        label: '거리',
                        value: '${km.toStringAsFixed(2)} km',
                      ),
                    ),
                    _vRule(theme),
                    Expanded(
                      child: MetricTile(label: '시간', value: _fmt(dur)),
                    ),
                    _vRule(theme),
                    Expanded(
                      child: MetricTile(
                        label: '평균 속도',
                        value: '${kmh.toStringAsFixed(1)} km/h',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              const SectionLabel('시간대별 활동'),
              Text(
                '탭하면 활동을 수정할 수 있어요',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
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
                          onTap: () => _editLabel(
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
          );
        },
      ),
    );
  }

  Widget _vRule(ThemeData theme) {
    return Container(
      width: 1,
      height: 40,
      color: theme.colorScheme.outlineVariant.withValues(alpha: 0.8),
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
    if (ok == true) {
      await ref.read(walkRepositoryProvider).deleteSession(sessionId);
      ref.read(historyTickProvider.notifier).state++;
      if (context.mounted) context.go('/history');
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
                child: Text(
                  '활동 선택',
                  style: theme.textTheme.titleMedium,
                ),
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
    await ref.read(walkRepositoryProvider).updateWindowUserLabel(
          sessionId: sessionId,
          windowStart: w.windowStart,
          userLabel: selected,
        );
    ref.read(historyTickProvider.notifier).state++;
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) return '${d.inHours}:$m:$s';
    return '$m:$s';
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.window, required this.onTap});

  final MinuteWindow window;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final time = DateFormat('HH:mm').format(window.windowStart);
    final confirmed = window.userConfirmed;
    final label = window.displayLabel.labelKo;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
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
                      Flexible(
                        child: Text(
                          label,
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      if (!confirmed) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary
                                .withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '추정',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ] else ...[
                        const SizedBox(width: 8),
                        Text(
                          '확정',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
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
            Icon(
              Icons.edit_outlined,
              size: 18,
              color: theme.colorScheme.outline,
            ),
          ],
        ),
      ),
    );
  }
}
