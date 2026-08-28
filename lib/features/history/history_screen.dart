import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/services/walk_stats.dart';
import '../../shared/widgets/app_motion.dart';
import '../../shared/widgets/ui_bits.dart';
import 'daily_activity_panel.dart';
import 'history_providers.dart';

final completedSessionsProvider = FutureProvider<HistorySnapshot>((ref) async {
  ref.watch(historyTickProvider);
  return ref.watch(completedHistoryProvider.future);
});

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(completedSessionsProvider);
    final theme = Theme.of(context);
    final dateFmt = DateFormat('M월 d일 (E) · HH:mm', 'ko');
    final transitionKey = _historyTransitionKey(async);

    return Scaffold(
      appBar: AppBar(title: const AppBarTitle('기록')),
      body: SmoothSwitcher(
        transitionKey: transitionKey,
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => EmptyStateView(
            icon: Icons.inventory_2_outlined,
            title: '기록을 불러오지 못했어요',
            message: '잠시 후 다시 시도해 주세요.',
            actionLabel: '다시 시도',
            onAction: () => ref.invalidate(completedSessionsProvider),
          ),
          data: (snapshot) {
            final sessions = snapshot.sessions;
            if (sessions.isEmpty) {
              return EmptyStateView(
                icon: Icons.directions_walk_rounded,
                title: '아직 기록이 없어요',
                message: '홈에서 산책을 시작하면\n여기에 모입니다.',
                actionLabel: '산책 시작하기',
                onAction: () => context.go('/'),
              );
            }

            return PageFrame(
              child: ListView.separated(
                padding: EdgeInsets.zero,
                itemCount: sessions.length + (snapshot.hasMore ? 2 : 1),
                separatorBuilder: (_, index) =>
                    SizedBox(height: index == 0 ? 20 : 10),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    final stats = snapshot.stats;
                    final milestones = stats.satisfied().take(3).toList();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const PageIntro(
                          title: '산책 기록',
                          description: '걸었던 길과 시간을 차분히 돌아보세요.',
                        ),
                        const SizedBox(height: 16),
                        SoftPanel(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 16,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('나의 흐름', style: theme.textTheme.titleSmall),
                              const SizedBox(height: 6),
                              Text(
                                stats.summaryLine(),
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 14),
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  final stack =
                                      constraints.maxWidth < 300 ||
                                      MediaQuery.textScalerOf(
                                            context,
                                          ).scale(14) >
                                          18;
                                  final tiles = [
                                    _StatChip(
                                      label: '산책',
                                      value: '${stats.walkCount}',
                                    ),
                                    _StatChip(
                                      label: '누적',
                                      value:
                                          '${stats.totalDistanceKm.toStringAsFixed(stats.totalDistanceKm >= 10 ? 0 : 1)} km',
                                    ),
                                    _StatChip(
                                      label: '최장',
                                      value: formatDurationCompact(
                                        stats.longestDuration,
                                      ),
                                    ),
                                  ];
                                  if (stack) {
                                    return Column(
                                      children: [
                                        for (
                                          var i = 0;
                                          i < tiles.length;
                                          i++
                                        ) ...[
                                          if (i > 0) const SizedBox(height: 8),
                                          tiles[i],
                                        ],
                                      ],
                                    );
                                  }
                                  return Row(
                                    children: [
                                      for (
                                        var i = 0;
                                        i < tiles.length;
                                        i++
                                      ) ...[
                                        if (i > 0) const SizedBox(width: 8),
                                        Expanded(child: tiles[i]),
                                      ],
                                    ],
                                  );
                                },
                              ),
                              if (milestones.isNotEmpty) ...[
                                const SizedBox(height: 14),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    for (final m in milestones)
                                      StatusPill(
                                        label: m.title,
                                        icon: Icons.auto_awesome_rounded,
                                      ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        const DailyActivityPanel(),
                        const SizedBox(height: 20),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            const SectionLabel('최근 산책'),
                            StatusPill(
                              label: '${snapshot.stats.walkCount}개의 산책',
                              icon: Icons.directions_walk_rounded,
                            ),
                          ],
                        ),
                      ],
                    );
                  }

                  if (index == sessions.length + 1) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 4, bottom: 24),
                      child: snapshot.hasMore
                          ? OutlinedButton(
                              onPressed: () {
                                ref.read(historyPageProvider.notifier).state++;
                              },
                              child: const Text('더 많은 기록 보기'),
                            )
                          : const SizedBox.shrink(),
                    );
                  }

                  final s = sessions[index - 1];
                  final km = (s.totalDistanceM ?? 0) / 1000.0;
                  final dur = Duration(seconds: s.durationS ?? 0);
                  final title = dateFmt.format(s.startedAt);
                  final subtitle =
                      '${km.toStringAsFixed(2)} km  ·  ${_fmt(dur)}';
                  return Semantics(
                    button: true,
                    label: '$title, $subtitle. 상세 보기',
                    excludeSemantics: true,
                    child: SoftPanel(
                      padding: EdgeInsets.zero,
                      child: InkWell(
                        onTap: () => context.go('/history/${s.id}'),
                        borderRadius: BorderRadius.circular(
                          AppTheme.radiusMedium,
                        ),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 76),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
                            child: Row(
                              children: [
                                const TonalIcon(
                                  icon: Icons.directions_walk_rounded,
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        title,
                                        style: theme.textTheme.labelLarge
                                            ?.copyWith(
                                              color: theme
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                            ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${km.toStringAsFixed(2)} km',
                                        style: theme.textTheme.titleMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: -0.3,
                                            ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        '소요 시간 ${_fmt(dur)}',
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color: theme
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Icon(
                                  Icons.chevron_right_rounded,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }

  Object _historyTransitionKey(AsyncValue<HistorySnapshot> async) {
    if (async.hasValue) {
      final snapshot = async.valueOrNull;
      if (snapshot == null) return 'data:empty';
      final first = snapshot.sessions.isEmpty ? '' : snapshot.sessions.first.id;
      final last = snapshot.sessions.isEmpty ? '' : snapshot.sessions.last.id;
      return 'data:${snapshot.sessions.length}:$first:$last:${snapshot.hasMore}';
    }
    if (async.hasError) return 'error';
    return 'loading';
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (h > 0) return '$h:$m:$s';
    return '$m:$s';
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
