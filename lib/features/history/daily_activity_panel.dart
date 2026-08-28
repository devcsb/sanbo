import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../data/activity_data_source.dart';
import '../../domain/services/daily_walk_stats.dart';
import '../../domain/services/walk_stats.dart';
import '../../shared/widgets/app_motion.dart';
import '../../shared/widgets/ui_bits.dart';
import 'history_providers.dart';

class DailyActivityPanel extends ConsumerWidget {
  const DailyActivityPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(dailyActivityProvider);
    final source = ref.watch(activityDataSourceProvider);
    final ActivityDataSourceConnector? connector =
        source is ActivityDataSourceConnector
        ? source as ActivityDataSourceConnector
        : null;
    return SmoothSwitcher(
      transitionKey: _activityTransitionKey(async),
      child: async.when(
        loading: () => const SoftPanel(
          child: SizedBox(
            height: 140,
            child: Center(child: CircularProgressIndicator()),
          ),
        ),
        error: (_, _) => SoftPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('일별 운동량'),
              const SizedBox(height: 8),
              Text(
                '일별 운동량을 불러오지 못했어요',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: () => ref.invalidate(dailyActivityProvider),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('다시 시도'),
              ),
            ],
          ),
        ),
        data: (snapshot) => _DailyActivityLoaded(
          snapshot: snapshot,
          connector: connector,
          onConnect: connector == null
              ? null
              : () async {
                  final result = await connector.requestAccess();
                  ref.invalidate(dailyActivityProvider);
                  return result;
                },
          selectedDay: ref.watch(dailySelectedDayProvider),
          onSelectDay: (day) {
            ref.read(dailySelectedDayProvider.notifier).state = day;
          },
          onMoveWeek: (weekEnd) {
            ref.read(dailyWeekEndProvider.notifier).state = weekEnd;
            ref.read(dailySelectedDayProvider.notifier).state = weekEnd;
          },
        ),
      ),
    );
  }

  Object _activityTransitionKey(AsyncValue<DailyActivitySnapshot> async) {
    if (async.hasValue) {
      final snapshot = async.valueOrNull;
      if (snapshot == null) return 'data:empty';
      return 'data:${snapshot.weekStart.toIso8601String()}:'
          '${snapshot.weekEnd.toIso8601String()}';
    }
    if (async.hasError) return 'error';
    return 'loading';
  }
}

class _DailyActivityLoaded extends StatelessWidget {
  const _DailyActivityLoaded({
    required this.snapshot,
    required this.connector,
    required this.onConnect,
    required this.selectedDay,
    required this.onSelectDay,
    required this.onMoveWeek,
  });

  final DailyActivitySnapshot snapshot;
  final ActivityDataSourceConnector? connector;
  final Future<ActivityAccessState> Function()? onConnect;
  final DateTime selectedDay;
  final ValueChanged<DateTime> onSelectDay;
  final ValueChanged<DateTime> onMoveWeek;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = localDateOnly(selectedDay);
    final selectedStats = snapshot.days.firstWhere(
      (day) => day.date == selected,
      orElse: () => DailyWalkStats.zero(selected),
    );
    final today = localDateOnly(DateTime.now());
    final canMoveForward = addLocalCalendarDays(
      snapshot.weekEnd,
      7,
    ).isBefore(addLocalCalendarDays(today, 1));
    final dateFormat = DateFormat('M월 d일', 'ko');
    final steps =
        snapshot.stepsByDate[selected] ??
        DailyStepSnapshot.unavailable(selected);
    final stepsValue = switch (steps.coverage) {
      ActivityCoverage.partial => '일부 기간만 확인됨',
      ActivityCoverage.complete when steps.steps != null =>
        '${NumberFormat.decimalPattern('ko').format(steps.steps)}걸음',
      ActivityCoverage.complete || ActivityCoverage.unavailable => '연결되지 않음',
    };
    final sourceLabel = switch (steps.source) {
      ActivitySourceKind.healthConnect => 'Health Connect에서 가져옴',
      ActivitySourceKind.healthKit => 'Apple 건강에서 가져옴',
      ActivitySourceKind.denied => '건강 데이터 권한이 필요해요',
      ActivitySourceKind.unavailable => '건강 데이터 연결 전',
      ActivitySourceKind.error => '건강 데이터를 불러오지 못했어요',
    };
    final stepsStatus = steps.coverage == ActivityCoverage.partial
        ? '일부 기간만 확인됨 · $sourceLabel'
        : sourceLabel;
    final showConnectAction = connector != null && steps.steps == null;

    return SoftPanel(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('일별 운동량', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 4),
                    Text(
                      '${dateFormat.format(snapshot.weekStart)} ~ ${dateFormat.format(snapshot.weekEnd)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '이전 7일',
                onPressed: () =>
                    onMoveWeek(addLocalCalendarDays(snapshot.weekEnd, -7)),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              IconButton(
                tooltip: '다음 7일',
                onPressed: canMoveForward
                    ? () =>
                          onMoveWeek(addLocalCalendarDays(snapshot.weekEnd, 7))
                    : null,
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 66,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: snapshot.days.length,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: (context, index) {
                final day = snapshot.days[index];
                final isSelected = day.date == selected;
                final isToday = day.date == today;
                final label =
                    '${DateFormat('M월 d일 (E)', 'ko').format(day.date)}, 산책 ${day.walkCount}회${isSelected ? ', 선택됨' : ''}';
                final background = isSelected
                    ? theme.colorScheme.primaryContainer
                    : theme.colorScheme.surfaceContainerHighest.withValues(
                        alpha: 0.55,
                      );
                return Semantics(
                  button: true,
                  selected: isSelected,
                  label: label,
                  child: Material(
                    color: background,
                    borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                      onTap: () => onSelectDay(day.date),
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 48),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        alignment: Alignment.center,
                        child: ExcludeSemantics(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                DateFormat('d', 'ko').format(day.date),
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                isToday
                                    ? '오늘'
                                    : DateFormat('E', 'ko').format(day.date),
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  fontWeight: isToday ? FontWeight.w700 : null,
                                ),
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
          ),
          const SizedBox(height: 12),
          MetricStrip(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
            metrics: [
              MetricData(
                label: '거리',
                value: '${selectedStats.totalDistanceKm.toStringAsFixed(2)} km',
                emphasize: true,
              ),
              MetricData(
                label: '시간',
                value: formatDurationCompact(selectedStats.totalDuration),
              ),
              MetricData(label: '산책', value: '${selectedStats.walkCount}회'),
            ],
          ),
          const SizedBox(height: 12),
          Semantics(
            container: true,
            label: '걸음 수와 데이터 상태',
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.55,
                ),
                borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.directions_walk_rounded,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('걸음 수', style: theme.textTheme.labelLarge),
                              const SizedBox(height: 2),
                              Text(
                                stepsValue,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Flexible(
                          child: Text(
                            stepsStatus,
                            textAlign: TextAlign.end,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (showConnectAction) ...[
                      const SizedBox(height: 8),
                      _ActivityConnectButton(onConnect: onConnect!),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityConnectButton extends StatefulWidget {
  const _ActivityConnectButton({required this.onConnect});

  final Future<ActivityAccessState> Function() onConnect;

  @override
  State<_ActivityConnectButton> createState() => _ActivityConnectButtonState();
}

class _ActivityConnectButtonState extends State<_ActivityConnectButton> {
  bool _busy = false;
  String? _message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextButton.icon(
          onPressed: _busy ? null : _connect,
          icon: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.link_rounded),
          label: Text(_busy ? '연결 확인 중…' : '건강 데이터 연결'),
        ),
        if (_message != null)
          Text(
            _message!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }

  Future<void> _connect() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    ActivityAccessState result;
    try {
      result = await widget.onConnect();
    } catch (_) {
      // A connector is expected to normalize platform errors, but keep the
      // button recoverable if a future adapter violates that contract.
      result = ActivityAccessState.error;
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = switch (result) {
        ActivityAccessState.connected => '연결했어요. 최신 걸음 수를 불러옵니다.',
        ActivityAccessState.denied => '권한을 허용하지 않아 연결하지 못했어요.',
        ActivityAccessState.unavailable => '건강 데이터 앱을 준비한 뒤 다시 시도해 주세요.',
        ActivityAccessState.error => '연결 상태를 확인하지 못했어요. 잠시 후 다시 시도해 주세요.',
      };
    });
  }
}
