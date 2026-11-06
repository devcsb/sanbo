import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sanbo/domain/models/walk_session.dart';
import 'package:sanbo/domain/models/activity_label.dart';
import 'package:sanbo/domain/models/route_exclusion.dart';
import 'package:sanbo/domain/pipeline/segment_merger.dart';
import 'package:sanbo/domain/models/tracking_mode.dart';
import 'package:sanbo/domain/pipeline/route_partitioner.dart';
import 'package:sanbo/features/session_detail/session_detail_screen.dart';
import 'package:sanbo/features/session_detail/session_week_provider.dart';
import 'package:sanbo/features/session_detail/session_summary_panels.dart';
import 'package:sanbo/features/history/history_providers.dart';
import 'package:sanbo/domain/services/session_week_summary.dart';
import 'package:sanbo/shared/widgets/route_map.dart';

SessionDetailData fixture(String id, {int? moving = 600}) => SessionDetailData(
  session: WalkSession(
    id: id,
    startedAt: DateTime.utc(2026, 10, 27),
    endedAt: DateTime.utc(2026, 10, 27, 0, 20),
    timezone: 'Asia/Seoul',
    trackingMode: TrackingMode.values.first,
    status: SessionStatus.completed,
    totalDistanceM: moving == 600 ? 2000 : 1000,
    durationS: 1200,
    movingTimeS: moving,
  ),
  samples: const [],
  windows: const [],
  exclusions: const [],
  route: RoutePartitioner.partition(samples: const [], exclusions: const []),
);

void main() {
  setUpAll(() => initializeDateFormatting('ko'));
  testWidgets(
    'weekly failure keeps current metrics notes export and separate map available',
    (tester) async {
      var weeklyReads = 0;
      final session = WalkSession(
        id: 'a',
        startedAt: DateTime.utc(2026, 10, 27),
        endedAt: DateTime.utc(2026, 10, 27, 0, 20),
        timezone: 'Asia/Seoul',
        trackingMode: TrackingMode.values.first,
        status: SessionStatus.completed,
        totalDistanceM: 2000,
        durationS: 1200,
        movingTimeS: 600,
      );
      final detail = SessionDetailData(
        session: session,
        samples: const [],
        windows: const [],
        exclusions: const [],
        route: RoutePartitioner.partition(
          samples: const [],
          exclusions: const [],
        ),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionDetailProvider.overrideWith((ref, id) async => detail),
            sessionWeekSummaryProvider.overrideWith((ref, id) async {
              weeklyReads++;
              throw StateError('offline');
            }),
          ],
          child: const MaterialApp(home: SessionDetailScreen(sessionId: 'a')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('포함 거리'), findsOneWidget);
      expect(find.text('2.00 km'), findsOneWidget);
      expect(find.text('10분'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('summary-tab-1')));
      await tester.tap(find.byKey(const ValueKey('summary-tab-1')));
      await tester.pumpAndSettle();
      expect(find.text('주간 기록을 불러오지 못했어요'), findsOneWidget);
      expect(find.byTooltip('원본 파일 저장'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('메모 저장'),
        350,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('메모 저장'), findsOneWidget);
      await tester.drag(find.byType(ListView).first, const Offset(0, 1200));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('summary-tab-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('summary-tab-0')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('지도 크게 보기'));
      await tester.tap(find.text('지도 크게 보기'));
      await tester.pumpAndSettle();
      expect(
        find.byType(RouteMap),
        findsOneWidget,
      ); // summary tile client removed
      await tester.pageBack();
      await tester.pump();
      expect(find.byType(RouteMap, skipOffstage: false), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(RouteMap, skipOffstage: false), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.byType(RouteMap, skipOffstage: false), findsOneWidget);
      expect(weeklyReads, 1);
    },
  );
  testWidgets('same id refresh preserves selection and another id resets it', (
    tester,
  ) async {
    final id = ValueNotifier('a');
    addTearDown(id.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionDetailProvider.overrideWith((ref, id) async => fixture(id)),
          sessionWeekSummaryProvider.overrideWith((ref, id) async => null),
        ],
        child: MaterialApp(
          home: ValueListenableBuilder(
            valueListenable: id,
            builder: (_, value, _) => SessionDetailScreen(sessionId: value),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('summary-tab-1')));
    await tester.tap(find.byKey(const ValueKey('summary-tab-1')));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SessionDetailScreen)),
    );
    container.invalidate(sessionDetailProvider('a'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SessionSummaryPanels>(find.byType(SessionSummaryPanels))
          .index,
      1,
    );
    id.value = 'b';
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SessionSummaryPanels>(find.byType(SessionSummaryPanels))
          .index,
      0,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'weekly refresh does not mix new weekly values with old detail values',
    (tester) async {
      final reload = Completer<SessionDetailData?>();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionDetailProvider.overrideWith((ref, id) {
              final tick = ref.watch(historyTickProvider);
              return tick == 0 ? Future.value(fixture(id)) : reload.future;
            }),
            sessionWeekSummaryProvider.overrideWith((ref, id) async {
              final tick = ref.watch(historyTickProvider);
              final session = fixture(
                id,
                moving: tick == 0 ? 600 : 300,
              ).session;
              return summarizeSessionWeek(
                reference: session,
                sessions: [session],
              );
            }),
          ],
          child: const MaterialApp(home: SessionDetailScreen(sessionId: 'a')),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('summary-tab-1')));
      await tester.tap(find.byKey(const ValueKey('summary-tab-1')));
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(SessionDetailScreen)),
      );
      container.read(historyTickProvider.notifier).state++;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      expect(find.text('주간 기록을 갱신하고 있어요'), findsOneWidget);
      expect(find.text('이번 산책이 더한 시간 5분'), findsNothing);
      reload.complete(fixture('a', moving: 300));
      await tester.pumpAndSettle();
      expect(find.text('이번 산책이 더한 시간 5분'), findsOneWidget);
      expect(
        tester
            .widget<SessionSummaryPanels>(find.byType(SessionSummaryPanels))
            .index,
        1,
      );
    },
  );
  for (final dark in [false, true]) {
    testWidgets(
      'actual detail at 320px double text supports loading partial empty and records dark=$dark',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(320, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final pending = Completer<SessionWeekSummary?>();
        final data = fixture('a', moving: null);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sessionDetailProvider.overrideWith((ref, id) async => data),
              sessionWeekSummaryProvider.overrideWith(
                (ref, id) => pending.future,
              ),
            ],
            child: MaterialApp(
              theme: ThemeData(
                brightness: dark ? Brightness.dark : Brightness.light,
              ),
              home: const MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(2)),
                child: SessionDetailScreen(sessionId: 'a'),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('summary-tab-1')),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('summary-tab-1')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byKey(const ValueKey('week-loading')), findsOneWidget);
        pending.complete(
          summarizeSessionWeek(
            reference: data.session,
            sessions: [data.session],
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('week-partial')), findsOneWidget);
        expect(find.text('집계할 수 없음'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('주간 기록 보기'),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('주간 기록 보기'));
        await tester.pumpAndSettle();
        expect(find.text('합산하지 못한 기록'), findsOneWidget);
        expect(find.text('기록 살펴보기'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        final empty = summarizeSessionWeek(
          reference: fixture('a').session,
          sessions: [],
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sessionDetailProvider.overrideWith(
                (ref, id) async => fixture(id),
              ),
              sessionWeekSummaryProvider.overrideWith((ref, id) async => empty),
            ],
            child: const MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(2)),
                child: SessionDetailScreen(sessionId: 'a'),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('summary-tab-1')),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('summary-tab-1')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('week-empty')), findsOneWidget);
        expect(find.text('합산할 이동 기록이 없어요. 이동하지 않았다는 뜻은 아니에요.'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'weekly records open actual included sessions and short movement uses seconds',
    (tester) async {
      final data = fixture('a', moving: 20);
      final summary = summarizeSessionWeek(
        reference: data.session,
        sessions: [data.session],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionDetailProvider.overrideWith(
              (ref, id) async => fixture(id, moving: 20),
            ),
            sessionWeekSummaryProvider.overrideWith((ref, id) async => summary),
          ],
          child: const MaterialApp(home: SessionDetailScreen(sessionId: 'a')),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('summary-tab-1')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('summary-tab-1')));
      await tester.pumpAndSettle();
      expect(find.text('20초'), findsNWidgets(3));
      expect(find.text('범위 밖'), findsWidgets);
      await tester.ensureVisible(find.text('주간 기록 보기'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('주간 기록 보기'));
      await tester.pumpAndSettle();
      expect(find.text('10월 27일 (화) 09:00'), findsOneWidget);
      await tester.tap(find.text('10월 27일 (화) 09:00'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<SessionDetailScreen>(find.byType(SessionDetailScreen))
            .sessionId,
        'a',
      );
      expect(
        tester
            .widget<SessionSummaryPanels>(find.byType(SessionSummaryPanels))
            .index,
        0,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('review link reaches the first segment in a long timeline', (
    tester,
  ) async {
    final base = fixture('a');
    final start = base.session.startedAt;
    final data = SessionDetailData(
      session: base.session.copyWith(
        endedAt: start.add(const Duration(minutes: 90)),
      ),
      samples: const [],
      windows: const [],
      route: base.route,
      exclusions: [
        RouteExclusion(
          id: 'excluded',
          sessionId: 'a',
          startAt: start,
          endAt: start.add(const Duration(minutes: 1)),
          reason: RouteExclusionReason.highSpeed,
          createdAt: start,
        ),
      ],
      segments: [
        for (var i = 0; i < 90; i++)
          ActivitySegment(
            start: start.add(Duration(minutes: i)),
            endInclusive: start.add(Duration(minutes: i)),
            label: i.isEven
                ? ActivityLabel.walkSteady
                : ActivityLabel.stationary,
            confidenceMin: 0.8,
            distanceM: 10,
            sampleCount: 3,
            durationS: 60,
            userConfirmed: false,
            windows: const [],
          ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionDetailProvider.overrideWith((ref, id) async => data),
          sessionWeekSummaryProvider.overrideWith((ref, id) async => null),
        ],
        child: const MaterialApp(home: SessionDetailScreen(sessionId: 'a')),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('구간 살펴보기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('구간 살펴보기'));
    await tester.pumpAndSettle();
    expect(find.text('활동 흐름').hitTestable(), findsOneWidget);
    final first = find.byKey(
      ValueKey('segment-select-${start.toIso8601String()}'),
    );
    expect(first.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'contribution copy precedes metrics with line spacing and date has no duplicate time',
    (tester) async {
      final data = fixture('a');
      final summary = summarizeSessionWeek(
        reference: data.session,
        sessions: [data.session],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionDetailProvider.overrideWith((ref, id) async => data),
            sessionWeekSummaryProvider.overrideWith((ref, id) async => summary),
          ],
          child: const MaterialApp(home: SessionDetailScreen(sessionId: 'a')),
        ),
      );
      await tester.pumpAndSettle();
      final copy = find.textContaining('이번 산책의 10분도 차곡차곡.');
      final text = tester.widget<Text>(copy);
      expect(text.data, contains('차곡차곡.\n'));
      expect(text.style?.height, 1.5);
      expect(
        tester.getBottomLeft(copy).dy + 12,
        lessThanOrEqualTo(tester.getTopLeft(find.text('포함 거리')).dy),
      );
      expect(find.text('2026.10.27\n09:00 시작 · 09:20 종료'), findsOneWidget);
    },
  );
}
