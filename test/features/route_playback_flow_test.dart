import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sanbo/data/walk_repository.dart';
import 'package:sanbo/domain/fixtures/synthetic_trace.dart';
import 'package:sanbo/domain/services/session_pipeline.dart';
import 'package:sanbo/features/session_detail/session_detail_screen.dart';
import 'package:sanbo/shared/widgets/route_map.dart';

import '../helpers/test_db.dart';

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 40)),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() => initializeDateFormatting('ko'));

  testWidgets('route playback, segment selection, and editing stay separate', (
    tester,
  ) async {
    late WalkRepository repo;
    late String sessionId;
    await tester.runAsync(() async {
      repo = await openTestRepository();
      final start = DateTime(2026, 7, 31, 9);
      final session = await repo.startSession(startedAt: start);
      sessionId = session.id;
      final samples = buildWalkTrace(
        start: start,
        duration: const Duration(minutes: 3),
        step: const Duration(seconds: 4),
      );
      await repo.insertSamples(session.id, samples);
      final endedAt = start.add(const Duration(minutes: 3));
      final result = SessionPipeline().process(
        session: session,
        rawSamples: samples,
        endedAt: endedAt,
      );
      await repo.replaceWindows(session.id, result.windows);
      await repo.completeSession(
        sessionId: session.id,
        endedAt: endedAt,
        totalDistanceM: result.metrics.totalDistanceM,
        durationS: result.metrics.durationS,
        movingTimeS: result.metrics.movingTimeS,
        stationaryTimeS: result.metrics.stationaryTimeS,
        avgSpeedMps: result.metrics.avgSpeedMps,
        validSampleCount: result.metrics.validSampleCount,
        medianAccuracyM: result.metrics.medianAccuracyM,
      );
    });
    addTearDown(() => tester.runAsync(repo.close));

    final container = ProviderContainer(
      overrides: [walkRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: SessionDetailScreen(sessionId: sessionId)),
      ),
    );
    await _settle(tester);
    await _settle(tester);

    final sliderFinder = find.byKey(const ValueKey('route-playback-slider'));
    expect(sliderFinder, findsOneWidget);
    expect(find.byTooltip('경로 재생'), findsOneWidget);
    final initialMap = tester.widget<RouteMap>(find.byType(RouteMap));
    expect(initialMap.progressPointCount, initialMap.points.length);

    await tester.tap(find.byTooltip('경로 재생'));
    await tester.pump();
    expect(find.byTooltip('경로 재생 일시정지'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 850));
    final advancedSlider = tester.widget<Slider>(sliderFinder);
    expect(advancedSlider.value, greaterThan(0));

    final segmentFinder = find.byWidgetPredicate((widget) {
      final key = widget.key;
      return key is ValueKey<String> && key.value.startsWith('segment-select-');
    }, skipOffstage: false);
    await tester.scrollUntilVisible(
      find.text('활동 흐름'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    if (segmentFinder.evaluate().isEmpty) {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
      await tester.pump();
    }
    expect(segmentFinder, findsWidgets);
    await tester.ensureVisible(segmentFinder.first);
    await tester.pumpAndSettle();
    await tester.tap(segmentFinder.first);
    await tester.pumpAndSettle();
    final selectedMap = tester.widget<RouteMap>(
      find.byType(RouteMap, skipOffstage: false),
    );
    expect(selectedMap.highlightedPoints, isNotEmpty);

    final editFinder = find.byTooltip(RegExp('구간 편집'));
    await tester.scrollUntilVisible(
      find.text('활동 흐름'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    expect(editFinder, findsWidgets);
    await tester.ensureVisible(editFinder.first);
    await tester.pumpAndSettle();
    await tester.tap(editFinder.first);
    await tester.pumpAndSettle();
    expect(find.text('활동 수정'), findsOneWidget);
  });
}
