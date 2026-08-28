import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sanbo/data/walk_repository.dart';
import 'package:sanbo/domain/models/activity_label.dart';
import 'package:sanbo/domain/models/minute_window.dart';
import 'package:sanbo/features/session_detail/session_detail_screen.dart';
import 'package:sanbo/platform/place/place_lookup.dart';

import '../helpers/test_db.dart';

class _FakePlaceLookup implements PlaceLookup {
  var callCount = 0;

  @override
  Future<PlaceLookupResult?> lookup({
    required double latitude,
    required double longitude,
  }) async {
    callCount++;
    return const PlaceLookupResult(
      suggestedName: '세종대로 쉼터',
      address: '서울특별시 중구 세종대로',
    );
  }
}

Future<void> _waitForDetail(
  WidgetTester tester,
  ProviderContainer container,
  String sessionId, {
  String? expectedPlaceName,
}) async {
  for (var attempt = 0; attempt < 200; attempt++) {
    await tester.pump();
    final state = container.read(sessionDetailProvider(sessionId));
    final detail = state.valueOrNull;
    final placeReady =
        expectedPlaceName == null ||
        (detail != null &&
            detail.windows.every(
              (window) => window.placeName == expectedPlaceName,
            ));
    if (detail != null && placeReady) return;
    if (state.hasError) {
      throw StateError('session detail provider failed: ${state.error}');
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
  }
  throw StateError('session detail provider did not settle');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() => initializeDateFormatting('ko'));

  testWidgets('stay segment can save and display a local place name', (
    tester,
  ) async {
    late WalkRepository repo;
    late String sessionId;
    final lookup = _FakePlaceLookup();
    await tester.runAsync(() async {
      repo = await openTestRepository();
      final start = DateTime(2026, 7, 20, 14);
      final session = await repo.startSession(startedAt: start);
      sessionId = session.id;
      final windows = [
        for (var minute = 0; minute < 3; minute++)
          MinuteWindow(
            windowStart: start.add(Duration(minutes: minute)),
            durationS: 60,
            partial: false,
            sampleCount: 8,
            rawSampleCount: 8,
            distanceM: 2,
            avgSpeedMps: 0.05,
            maxSpeedMps: 0.1,
            stationaryRatio: 0.95,
            quality: WindowQuality.high,
            centroidLat: 37.5665,
            centroidLon: 126.978,
            hypothesisLabel: ActivityLabel.placeStay,
            hypothesisConfidence: 0.7,
          ),
      ];
      await repo.replaceWindows(session.id, windows);
      await repo.completeSession(
        sessionId: session.id,
        endedAt: start.add(const Duration(minutes: 3)),
        totalDistanceM: 6,
        durationS: 180,
        movingTimeS: 0,
        stationaryTimeS: 180,
        avgSpeedMps: 0,
        validSampleCount: 24,
      );
    });
    addTearDown(() => tester.runAsync(repo.close));

    final container = ProviderContainer(
      overrides: [
        walkRepositoryProvider.overrideWithValue(repo),
        placeLookupProvider.overrideWithValue(lookup),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: SessionDetailScreen(sessionId: sessionId)),
      ),
    );
    await _waitForDetail(tester, container, sessionId);

    await tester.scrollUntilVisible(
      find.text('한곳 체류'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('한곳 체류'), findsOneWidget);
    await tester.tap(find.byTooltip(RegExp('구간 편집')).first);
    await tester.pumpAndSettle();
    expect(find.text('장소 이름 남기기'), findsOneWidget);

    await tester.tap(find.text('장소 이름 남기기'));
    await tester.pumpAndSettle();
    expect(find.text('장소 기억'), findsOneWidget);

    await tester.tap(find.text('현재 위치에서 주소 제안'));
    await tester.pumpAndSettle();
    expect(lookup.callCount, 1);
    expect(find.text('세종대로 쉼터'), findsOneWidget);
    expect(find.text('서울특별시 중구 세종대로'), findsOneWidget);

    await tester.tap(find.text('장소 이름 저장'));
    await _waitForDetail(
      tester,
      container,
      sessionId,
      expectedPlaceName: '세종대로 쉼터',
    );
    await tester.scrollUntilVisible(
      find.text('세종대로 쉼터'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('세종대로 쉼터'), findsOneWidget);

    final windows = await tester.runAsync(() => repo.getWindows(sessionId));
    expect(windows, isNotNull);
    expect(windows!.every((window) => window.placeName == '세종대로 쉼터'), isTrue);
  });

  test(
    'detail provider reuses a nearby local place without geocoding',
    () async {
      final repo = await openTestRepository();
      addTearDown(repo.close);
      final lookup = _FakePlaceLookup();

      final firstStart = DateTime(2026, 7, 21, 10);
      final first = await repo.startSession(startedAt: firstStart);
      final firstWindow = MinuteWindow(
        windowStart: firstStart,
        durationS: 60,
        partial: false,
        sampleCount: 8,
        rawSampleCount: 8,
        distanceM: 1,
        avgSpeedMps: 0.05,
        maxSpeedMps: 0.1,
        stationaryRatio: 0.95,
        quality: WindowQuality.high,
        centroidLat: 37.5665,
        centroidLon: 126.978,
        hypothesisLabel: ActivityLabel.placeStay,
        hypothesisConfidence: 0.7,
      );
      await repo.replaceWindows(first.id, [firstWindow]);
      await repo.completeSession(
        sessionId: first.id,
        endedAt: firstStart.add(const Duration(minutes: 1)),
        totalDistanceM: 1,
        durationS: 60,
        movingTimeS: 0,
        stationaryTimeS: 60,
        avgSpeedMps: 0,
        validSampleCount: 8,
      );
      await repo.rememberPlaceForWindows(
        sessionId: first.id,
        windowStarts: [firstWindow.windowStart],
        latitude: 37.5665,
        longitude: 126.978,
        name: '기억한 벤치',
      );

      final secondStart = DateTime(2026, 7, 22, 10);
      final second = await repo.startSession(startedAt: secondStart);
      final secondWindow = MinuteWindow(
        windowStart: secondStart,
        durationS: 60,
        partial: false,
        sampleCount: 8,
        rawSampleCount: 8,
        distanceM: 1,
        avgSpeedMps: 0.05,
        maxSpeedMps: 0.1,
        stationaryRatio: 0.95,
        quality: WindowQuality.high,
        centroidLat: 37.56658,
        centroidLon: 126.978,
        hypothesisLabel: ActivityLabel.placeStay,
        hypothesisConfidence: 0.7,
      );
      await repo.replaceWindows(second.id, [secondWindow]);
      await repo.completeSession(
        sessionId: second.id,
        endedAt: secondStart.add(const Duration(minutes: 1)),
        totalDistanceM: 1,
        durationS: 60,
        movingTimeS: 0,
        stationaryTimeS: 60,
        avgSpeedMps: 0,
        validSampleCount: 8,
      );

      final container = ProviderContainer(
        overrides: [
          walkRepositoryProvider.overrideWithValue(repo),
          placeLookupProvider.overrideWithValue(lookup),
        ],
      );
      addTearDown(container.dispose);
      final detail = await container.read(
        sessionDetailProvider(second.id).future,
      );

      expect(detail?.windows.single.placeName, '기억한 벤치');
      expect(lookup.callCount, 0);
      // Opening a detail is read-only; reuse is a display overlay until the
      // user explicitly edits or saves a place.
      final persisted = await repo.getWindows(second.id);
      expect(persisted.single.placeId, isNull);
    },
  );
}
