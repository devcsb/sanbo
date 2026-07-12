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
import '../../domain/models/tracking_mode.dart';
import '../../domain/models/walk_session.dart';
import '../../shared/widgets/route_map.dart';
import '../history/history_providers.dart';
import '../settings/settings_screen.dart';
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
    final tile = ref.watch(tileSourceSettingProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('산책 요약'),
        actions: [
          IconButton(
            tooltip: '삭제',
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) {
                  final scheme = Theme.of(ctx).colorScheme;
                  return AlertDialog(
                    title: const Text('기록 삭제'),
                    content: const Text(
                      '이 산책 기록을 삭제합니다. 되돌릴 수 없습니다.',
                    ),
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
                if (context.mounted) {
                  context.go('/history');
                }
              }
            },
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('오류: $e')),
        data: (data) {
          if (data == null) {
            return const Center(child: Text('기록을 찾을 수 없습니다'));
          }
          final session = data.session;
          final dateFmt = DateFormat('yyyy.MM.dd HH:mm', 'ko');
          final km = (session.totalDistanceM ?? 0) / 1000.0;
          final dur = Duration(seconds: session.durationS ?? 0);
          final kmh = (session.avgSpeedMps ?? 0) * 3.6;
          final points = data.samples
              .where((s) => !s.isFilteredOut)
              .map((s) => (lat: s.latitude, lon: s.longitude))
              .toList();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              RouteMap(
                points: points,
                tileSource: tile,
                // Avoid hanging on tile HTTP during `flutter test`.
                offlinePreview: !kIsWeb &&
                    Platform.environment.containsKey('FLUTTER_TEST'),
              ),
              const SizedBox(height: 16),
              Text(
                dateFmt.format(session.startedAt),
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _MetricChip(
                    label: '거리',
                    value: '${km.toStringAsFixed(2)} km',
                  ),
                  _MetricChip(label: '시간', value: _fmt(dur)),
                  _MetricChip(
                    label: '평균 속도',
                    value: '${kmh.toStringAsFixed(1)} km/h',
                  ),
                  _MetricChip(
                    label: '포인트',
                    value: '${session.validSampleCount ?? points.length}',
                  ),
                  _MetricChip(
                    label: '모드',
                    value: session.trackingMode.labelKo,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text('분 단위 타임라인', style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(
                '활동은 추정입니다. 탭하면 수정·확정할 수 있어요.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              if (data.windows.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      '시간대별 구간이 없습니다. 짧은 산책이거나 위치 기록이 부족했을 수 있어요.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                )
              else
                ...data.windows.map((w) {
                  final prefix = w.userConfirmed ? '' : '추정 · ';
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      title: Text(
                        '${DateFormat('HH:mm').format(w.windowStart)} · '
                        '$prefix${w.displayLabel.labelKo}'
                        '${w.userConfirmed ? ' (확정)' : ''}',
                      ),
                      subtitle: Text(timelineWindowSubtitle(w)),
                      onTap: () => _editLabel(context, ref, sessionId, w),
                    ),
                  );
                }),
            ],
          );
        },
      ),
    );
  }

  Future<void> _editLabel(
    BuildContext context,
    WidgetRef ref,
    String sessionId,
    MinuteWindow w,
  ) async {
    final selected = await showModalBottomSheet<ActivityLabel>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(title: Text('활동 수정 (추정 → 내 기록)')),
              for (final label in ActivityLabel.values)
                ListTile(
                  title: Text(label.labelKo),
                  trailing: w.displayLabel == label
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () => Navigator.pop(ctx, label),
                ),
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

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            value,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
