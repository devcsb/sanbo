import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sanbo/data/walk_repository.dart';
import 'package:sanbo/domain/fixtures/synthetic_trace.dart';
import 'package:sanbo/domain/models/activity_label.dart';
import 'package:sanbo/domain/models/route_exclusion.dart';
import 'package:sanbo/domain/models/tracking_mode.dart';
import 'package:sanbo/domain/pipeline/segment_merger.dart';
import 'package:sanbo/domain/services/session_pipeline.dart';
import 'package:sanbo/features/history/history_screen.dart';
import 'package:sanbo/features/history/history_providers.dart';
import 'package:sanbo/features/home/session_controller.dart';
import 'package:sanbo/features/session_detail/session_detail_screen.dart';
import 'package:sanbo/platform/location/location_engine.dart';
import 'package:sanbo/platform/location/synthetic_location_engine.dart';
import 'package:sanbo/shared/widgets/route_map.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/test_db.dart';
import '../helpers/route_exclusion_fixture.dart';

Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1));
}

Future<void> waitForDetailReload(WidgetTester tester, String sessionId) async {
  final container = ProviderScope.containerOf(
    tester.element(find.byType(SessionDetailScreen)),
    listen: false,
  );
  await tester.runAsync(() async {
    await container.read(sessionDetailProvider(sessionId).future);
  });
  await tester.pump();
}

Widget detailApp(
  WalkRepository repository,
  String sessionId, {
  MediaQueryData? mediaQueryData,
}) {
  final detail = SessionDetailScreen(sessionId: sessionId);
  return ProviderScope(
    overrides: [walkRepositoryProvider.overrideWithValue(repository)],
    child: MaterialApp(
      home: mediaQueryData == null
          ? detail
          : MediaQuery(data: mediaQueryData, child: detail),
    ),
  );
}

Widget detailRouteApp(WalkRepository repository, String sessionId) {
  return ProviderScope(
    overrides: [walkRepositoryProvider.overrideWithValue(repository)],
    child: MaterialApp(
      home: Navigator(
        onGenerateInitialRoutes: (_, _) => [
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: SizedBox.shrink()),
          ),
          MaterialPageRoute<void>(
            builder: (_) => SessionDetailScreen(sessionId: sessionId),
          ),
        ],
      ),
    ),
  );
}

class _DelayedFailingExcludeRepository extends WalkRepository {
  _DelayedFailingExcludeRepository(super.db);

  final writeStarted = Completer<void>();
  final releaseFailure = Completer<void>();
  var attempts = 0;

  @override
  Future<RouteExclusion> excludeRouteSegment({
    required String sessionId,
    required ActivitySegment segment,
    RouteExclusionReason reason = RouteExclusionReason.vehicle,
    DateTime? createdAt,
  }) async {
    attempts++;
    writeStarted.complete();
    await releaseFailure.future;
    throw StateError('write failed');
  }
}

class _DelayedSuccessfulExcludeRepository extends WalkRepository {
  _DelayedSuccessfulExcludeRepository(super.db);

  final writeStarted = Completer<void>();
  final releaseWrite = Completer<void>();
  final writeFinished = Completer<void>();
  var attempts = 0;

  @override
  Future<RouteExclusion> excludeRouteSegment({
    required String sessionId,
    required ActivitySegment segment,
    RouteExclusionReason reason = RouteExclusionReason.vehicle,
    DateTime? createdAt,
  }) async {
    attempts++;
    writeStarted.complete();
    await releaseWrite.future;
    final exclusion = await super.excludeRouteSegment(
      sessionId: sessionId,
      segment: segment,
      reason: reason,
      createdAt: createdAt,
    );
    writeFinished.complete();
    return exclusion;
  }
}

class _DelayedSuccessfulRestoreRepository extends WalkRepository {
  _DelayedSuccessfulRestoreRepository(super.db);

  final writeStarted = Completer<void>();
  final releaseWrite = Completer<void>();
  final writeFinished = Completer<void>();
  var attempts = 0;

  @override
  Future<void> restoreRouteExclusion({
    required String sessionId,
    required String exclusionId,
  }) async {
    attempts++;
    writeStarted.complete();
    await releaseWrite.future;
    await super.restoreRouteExclusion(
      sessionId: sessionId,
      exclusionId: exclusionId,
    );
    writeFinished.complete();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeDateFormatting('ko');
  });

  testWidgets('empty HistoryScreen CTA navigates home via go_router', (
    tester,
  ) async {
    late WalkRepository repo;
    await tester.runAsync(() async {
      repo = await openTestRepository();
      expect(await repo.listCompleted(), isEmpty);
    });
    addTearDown(() async {
      await tester.runAsync(() => repo.close());
    });

    final engine = SyntheticLocationEngine(
      permission: LocationPermissionState.granted,
    );
    final container = ProviderContainer(
      overrides: [
        walkRepositoryProvider.overrideWithValue(repo),
        locationEngineProvider.overrideWithValue(engine),
      ],
    );
    addTearDown(container.dispose);

    final router = GoRouter(
      initialLocation: '/history',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: Text('HOME_MARK')),
        ),
        GoRoute(path: '/history', builder: (_, _) => const HistoryScreen()),
      ],
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await settle(tester);
    await settle(tester);

    expect(find.byType(HistoryScreen), findsOneWidget);
    expect(find.textContaining('아직 기록이 없어요'), findsOneWidget);
    expect(find.text('산책 시작하기'), findsOneWidget);

    await tester.tap(find.text('산책 시작하기'));
    await settle(tester);
    expect(find.text('HOME_MARK'), findsOneWidget);
  });

  testWidgets('daily selection changes totals while recent history remains', (
    tester,
  ) async {
    late WalkRepository repo;
    await tester.runAsync(() async {
      repo = await openTestRepository();
      final start = DateTime(2026, 8, 12, 9);
      final session = await repo.startSession(startedAt: start);
      await repo.completeSession(
        sessionId: session.id,
        endedAt: start.add(const Duration(minutes: 10)),
        totalDistanceM: 1000,
        durationS: 600,
        movingTimeS: 600,
        stationaryTimeS: 0,
        avgSpeedMps: 1.6,
        validSampleCount: 1,
      );
    });
    addTearDown(() async {
      await tester.runAsync(() => repo.close());
    });

    final container = ProviderContainer(
      overrides: [
        walkRepositoryProvider.overrideWithValue(repo),
        dailyWeekEndProvider.overrideWith((_) => DateTime(2026, 8, 15)),
        dailySelectedDayProvider.overrideWith((_) => DateTime(2026, 8, 15)),
      ],
    );
    addTearDown(container.dispose);
    final router = GoRouter(
      initialLocation: '/history',
      routes: [
        GoRoute(path: '/history', builder: (_, _) => const HistoryScreen()),
      ],
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await settle(tester);
    await settle(tester);

    expect(find.text('일별 운동량'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel(RegExp(r'^8월 12일')));
    await tester.pump();
    expect(find.text('1.00 km'), findsAtLeastNWidgets(1));
    await tester.drag(find.byType(ListView).last, const Offset(0, -500));
    await tester.pump();
    expect(find.text('소요 시간 10:00'), findsOneWidget);
  });

  testWidgets('SessionDetailScreen delete dialog then go /history', (
    tester,
  ) async {
    late WalkRepository repo;
    late String sessionId;

    await tester.runAsync(() async {
      repo = await openTestRepository();
      final start = DateTime(2026, 7, 12, 9, 0, 0);
      final session = await repo.startSession(
        mode: TrackingMode.balanced,
        startedAt: start,
      );
      sessionId = session.id;
      final samples = buildWalkTrace(
        start: start,
        duration: const Duration(minutes: 2),
        step: const Duration(seconds: 4),
      );
      await repo.insertSamples(session.id, samples);
      final endedAt = start.add(const Duration(minutes: 2, seconds: 5));
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
    addTearDown(() async {
      await tester.runAsync(() => repo.close());
    });

    final engine = SyntheticLocationEngine(
      permission: LocationPermissionState.granted,
    );
    final container = ProviderContainer(
      overrides: [
        walkRepositoryProvider.overrideWithValue(repo),
        locationEngineProvider.overrideWithValue(engine),
      ],
    );
    addTearDown(container.dispose);

    final router = GoRouter(
      initialLocation: '/history/$sessionId',
      routes: [
        GoRoute(
          path: '/history',
          builder: (_, _) => const Scaffold(body: Text('HISTORY_LIST_MARK')),
          routes: [
            GoRoute(
              path: ':sessionId',
              builder: (context, state) => SessionDetailScreen(
                sessionId: state.pathParameters['sessionId']!,
              ),
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await settle(tester);
    await settle(tester);

    expect(find.byType(SessionDetailScreen), findsOneWidget);
    expect(find.text('산책 요약'), findsOneWidget);

    await tester.tap(find.byTooltip('삭제'));
    await tester.pump();
    expect(find.byType(AlertDialog), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '삭제'));
    await settle(tester);
    await settle(tester);
    await settle(tester);

    final gone = await tester.runAsync<Object?>(
      () => repo.getSession(sessionId),
    );
    expect(gone, isNull);
    // Shipped code calls context.go('/history') after delete.
    expect(find.text('HISTORY_LIST_MARK'), findsOneWidget);
  });

  testWidgets(
    'vehicle segment offers exclusion and excluded segment offers restore',
    (tester) async {
      late WalkRepository repo;
      late CompletedRouteFixture fixture;
      await tester.runAsync(() async {
        repo = await openTestRepository();
        fixture = await seedCompletedVehicleWalk(repo);
      });
      addTearDown(() => tester.runAsync(repo.close));
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(detailApp(repo, fixture.session.id));
      await settle(tester);
      await settle(tester);
      await settle(tester);
      final oldDistanceM = fixture.session.totalDistanceM ?? 0;
      final oldMap = tester.widget<RouteMap>(find.byType(RouteMap));
      final scrollable = find
          .descendant(
            of: find.byType(ListView).first,
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.text('활동 흐름'),
        300,
        scrollable: scrollable,
      );

      final vehicleSegment = fixture.segments.last;
      final selectFinder = find.byKey(
        ValueKey('segment-select-${vehicleSegment.start.toIso8601String()}'),
      );
      await tester.scrollUntilVisible(
        selectFinder,
        300,
        scrollable: scrollable,
      );
      await tester.ensureVisible(selectFinder);
      await tester.pump();
      await tester.tap(selectFinder);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<RouteMap>(find.byType(RouteMap, skipOffstage: false))
            .highlightedFragments
            .expand((fragment) => fragment),
        isNotEmpty,
      );

      final editFinder = find.byTooltip(RegExp('구간 편집'));
      await tester.scrollUntilVisible(
        find.text('활동 흐름'),
        300,
        scrollable: scrollable,
      );
      await tester.scrollUntilVisible(
        editFinder.last,
        300,
        scrollable: scrollable,
      );
      await tester.ensureVisible(editFinder.last);
      await tester.pump();
      await tester.tap(editFinder.last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('산책에서 제외'), findsOneWidget);
      expect(find.text('차량 이동 구간을 산책에서 제외합니다.'), findsOneWidget);

      await tester.tap(find.text('산책에서 제외'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('기록 전체 통계를 다시 계산'), findsOneWidget);
      expect(
        await tester.runAsync(
          () => repo.getRouteExclusions(fixture.session.id),
        ),
        isEmpty,
      );

      await tester.tap(find.widgetWithText(FilledButton, '차량 이동 구간 제외'));
      await settle(tester);
      await settle(tester);
      await settle(tester);
      await settle(tester);
      await waitForDetailReload(tester, fixture.session.id);

      final updatedSession = await tester.runAsync(
        () => repo.getSession(fixture.session.id),
      );
      expect(updatedSession, isNotNull);
      expect(updatedSession!.totalDistanceM, lessThan(oldDistanceM));
      expect(
        await tester.runAsync(
          () => repo.getRouteExclusions(fixture.session.id),
        ),
        hasLength(1),
      );
      expect(
        find.text(
          '${((updatedSession.totalDistanceM ?? 0) / 1000).toStringAsFixed(2)} km',
        ),
        findsWidgets,
      );
      final updatedMap = tester.widget<RouteMap>(
        find.byType(RouteMap, skipOffstage: false),
      );
      expect(
        updatedMap.fragments.expand((fragment) => fragment).length,
        lessThan(oldMap.fragments.expand((fragment) => fragment).length),
      );
      expect(
        updatedMap.highlightedFragments.expand((fragment) => fragment),
        isEmpty,
      );
      expect(updatedMap.progress, isNotNull);
      expect(
        updatedMap.progress!.pointIndex,
        updatedMap.fragments[updatedMap.progress!.fragmentIndex].length - 1,
      );
      await tester.scrollUntilVisible(
        find.text('산책에서 제외됨'),
        300,
        scrollable: scrollable,
      );
      expect(find.text('산책에서 제외됨'), findsWidgets);
      await tester.scrollUntilVisible(
        editFinder.last,
        300,
        scrollable: scrollable,
      );
      await tester.ensureVisible(editFinder.last);
      await tester.pump();
      await tester.tap(editFinder.last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('제외 취소'), findsOneWidget);
      await tester.tap(find.text('제외 취소'));
      await settle(tester);
      await settle(tester);
      await waitForDetailReload(tester, fixture.session.id);
      expect(
        await tester.runAsync(
          () => repo.getRouteExclusions(fixture.session.id),
        ),
        isEmpty,
      );
    },
  );

  testWidgets('a non-vehicle segment still offers manual exclusion', (
    tester,
  ) async {
    late WalkRepository repo;
    late CompletedRouteFixture fixture;
    await tester.runAsync(() async {
      repo = await openTestRepository();
      fixture = await seedCompletedVehicleWalk(repo);
      final windows = await repo.getWindows(fixture.session.id);
      await repo.updateWindowUserLabel(
        sessionId: fixture.session.id,
        windowStart: windows.last.windowStart,
        userLabel: ActivityLabel.walkSteady,
        note: '실수로 포함된 이동',
        confirmed: true,
      );
    });
    addTearDown(() => tester.runAsync(repo.close));
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(detailApp(repo, fixture.session.id));
    await settle(tester);
    await settle(tester);
    final windows = await tester.runAsync(
      () => repo.getWindows(fixture.session.id),
    );
    final segments = SegmentMerger().merge(
      windows!,
      sessionId: fixture.session.id,
      sessionStart: fixture.session.startedAt,
      sessionEnd: fixture.session.endedAt,
    );
    final segment = segments.last;
    final edit = find.byKey(
      ValueKey('segment-edit-${segment.start.toIso8601String()}'),
    );
    final scrollable = find
        .descendant(
          of: find.byType(ListView).first,
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(edit, 300, scrollable: scrollable);
    await tester.ensureVisible(edit);
    await tester.pump();
    await tester.tap(edit);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('산책에서 제외'), findsWidgets);
    expect(find.text('잘못 포함된 이동을 산책 경로와 통계에서 제외합니다.'), findsWidgets);
    await tester.tap(find.text('산책에서 제외').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.widgetWithText(FilledButton, '이 구간 제외'), findsOneWidget);
  });

  testWidgets(
    'failed duplicate exclusion keeps the previous presentation and offers retry',
    (tester) async {
      late CompletedRouteFixture fixture;
      late _DelayedFailingExcludeRepository repo;
      await tester.runAsync(() async {
        final path =
            '${DateTime.now().microsecondsSinceEpoch}_detail_exclusion_failure.db';
        final seed = await openTestRepository(path: path);
        fixture = await seedCompletedVehicleWalk(seed);
        await seed.close();
        repo = _DelayedFailingExcludeRepository(
          await databaseFactory.openDatabase(path),
        );
      });
      addTearDown(() => tester.runAsync(repo.close));
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(detailApp(repo, fixture.session.id));
      await settle(tester);
      await settle(tester);
      await settle(tester);
      final oldMetric = find.text(
        '${((fixture.session.totalDistanceM ?? 0) / 1000).toStringAsFixed(2)} km',
      );
      final oldMap = tester.widget<RouteMap>(find.byType(RouteMap));

      await tester.scrollUntilVisible(
        find.text('활동 흐름'),
        300,
        scrollable: find
            .descendant(
              of: find.byType(ListView).first,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      final editFinder = find.byTooltip(RegExp('구간 편집'));
      await tester.scrollUntilVisible(
        editFinder.last,
        300,
        scrollable: find
            .descendant(
              of: find.byType(ListView).first,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.ensureVisible(editFinder.last);
      await tester.pump();
      await tester.tap(editFinder.last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('산책에서 제외'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.widgetWithText(FilledButton, '차량 이동 구간 제외'));
      await tester.runAsync(() => repo.writeStarted.future);
      await tester.pump();
      expect(repo.attempts, 1);
      await tester.tap(
        find.byKey(
          ValueKey(
            'segment-edit-${fixture.segments.last.start.toIso8601String()}',
          ),
        ),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(repo.attempts, 1);

      repo.releaseFailure.complete();
      await settle(tester);
      expect(oldMetric, findsOneWidget);
      await tester.drag(find.byType(ListView).first, const Offset(0, 1000));
      await tester.pump();
      expect(
        tester.widget<RouteMap>(find.byType(RouteMap)).fragments,
        oldMap.fragments,
      );
      expect(find.text('경로를 제외하지 못했어요. 다시 시도해 주세요.'), findsOneWidget);
    },
  );

  testWidgets(
    'completed exclusion after detail pop refreshes history without widget errors',
    (tester) async {
      late CompletedRouteFixture fixture;
      late _DelayedSuccessfulExcludeRepository repo;
      await tester.runAsync(() async {
        final path =
            '${DateTime.now().microsecondsSinceEpoch}_detail_exclusion_pop.db';
        final seed = await openTestRepository(path: path);
        fixture = await seedCompletedVehicleWalk(seed);
        await seed.close();
        repo = _DelayedSuccessfulExcludeRepository(
          await databaseFactory.openDatabase(path),
        );
      });
      addTearDown(() => tester.runAsync(repo.close));
      tester.view.physicalSize = const Size(1200, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(detailRouteApp(repo, fixture.session.id));
      await settle(tester);
      await settle(tester);
      await settle(tester);

      final scrollable = find
          .descendant(
            of: find.byType(ListView).first,
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.text('활동 흐름'),
        300,
        scrollable: scrollable,
      );
      final editFinder = find.byKey(
        ValueKey(
          'segment-edit-${fixture.segments.last.start.toIso8601String()}',
        ),
      );
      await tester.scrollUntilVisible(editFinder, 300, scrollable: scrollable);
      await tester.drag(scrollable, const Offset(0, -500));
      await tester.pump();
      await tester.tap(editFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('산책에서 제외'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.widgetWithText(FilledButton, '차량 이동 구간 제외'));
      await tester.runAsync(() => repo.writeStarted.future);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(SessionDetailScreen)),
      );
      Navigator.of(tester.element(find.byType(SessionDetailScreen))).pop();
      await tester.pumpAndSettle();
      expect(find.byType(SessionDetailScreen), findsNothing);
      repo.releaseWrite.complete();
      await tester.runAsync(() => repo.writeFinished.future);
      await tester.pump();

      expect(repo.attempts, 1);
      expect(container.read(historyTickProvider), 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'completed restore after detail pop refreshes history without widget errors',
    (tester) async {
      late CompletedRouteFixture fixture;
      late _DelayedSuccessfulRestoreRepository repo;
      await tester.runAsync(() async {
        final path =
            '${DateTime.now().microsecondsSinceEpoch}_detail_restore_pop.db';
        final seed = await openTestRepository(path: path);
        fixture = await seedCompletedVehicleWalk(seed);
        await seed.excludeRouteSegment(
          sessionId: fixture.session.id,
          segment: fixture.segments.last,
        );
        await seed.close();
        repo = _DelayedSuccessfulRestoreRepository(
          await databaseFactory.openDatabase(path),
        );
      });
      addTearDown(() => tester.runAsync(repo.close));
      tester.view.physicalSize = const Size(1200, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(detailRouteApp(repo, fixture.session.id));
      await settle(tester);
      await settle(tester);
      await settle(tester);

      final scrollable = find
          .descendant(
            of: find.byType(ListView).first,
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.text('활동 흐름'),
        300,
        scrollable: scrollable,
      );
      final editFinder = find.byKey(
        ValueKey(
          'segment-edit-${fixture.segments.last.start.toIso8601String()}',
        ),
      );
      await tester.scrollUntilVisible(editFinder, 300, scrollable: scrollable);
      await tester.drag(scrollable, const Offset(0, -500));
      await tester.pump();
      await tester.tap(editFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('제외 취소'));
      await tester.runAsync(() => repo.writeStarted.future);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(SessionDetailScreen)),
      );
      Navigator.of(tester.element(find.byType(SessionDetailScreen))).pop();
      await tester.pumpAndSettle();
      expect(find.byType(SessionDetailScreen), findsNothing);
      repo.releaseWrite.complete();
      await tester.runAsync(() => repo.writeFinished.future);
      await tester.pump();

      expect(repo.attempts, 1);
      expect(container.read(historyTickProvider), 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'excluded segment remains usable at large text and exposes restore semantics',
    (tester) async {
      late WalkRepository repo;
      late CompletedRouteFixture fixture;
      await tester.runAsync(() async {
        repo = await openTestRepository();
        fixture = await seedCompletedVehicleWalk(repo);
        await repo.excludeRouteSegment(
          sessionId: fixture.session.id,
          segment: fixture.segments.last,
        );
      });
      addTearDown(() => tester.runAsync(repo.close));
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        detailApp(
          repo,
          fixture.session.id,
          mediaQueryData: const MediaQueryData(
            textScaler: TextScaler.linear(2),
          ),
        ),
      );
      await settle(tester);
      await settle(tester);

      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.text('산책에서 제외됨'),
        300,
        scrollable: find
            .descendant(
              of: find.byType(ListView).first,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('산책에서 제외됨'), findsWidgets);
      expect(
        find.bySemanticsLabel(RegExp(r'.*, 산책에서 제외됨, 제외 취소 가능')),
        findsOneWidget,
      );
    },
  );
}
