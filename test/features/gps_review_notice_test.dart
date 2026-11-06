import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sanbo/core/theme/app_theme.dart';
import 'package:sanbo/domain/models/minute_window.dart';
import 'package:sanbo/domain/models/route_exclusion.dart';
import 'package:sanbo/domain/models/tracking_mode.dart';
import 'package:sanbo/domain/models/walk_session.dart';
import 'package:sanbo/domain/pipeline/route_partitioner.dart';
import 'package:sanbo/features/session_detail/session_detail_screen.dart';
import 'package:sanbo/features/session_detail/session_week_provider.dart';
import 'package:sanbo/features/session_detail/timeline_copy.dart';

MinuteWindow window({bool confirmed = false, bool excluded = false}) =>
    MinuteWindow(
      windowStart: DateTime.utc(2026, 11, 7),
      durationS: 60,
      partial: false,
      sampleCount: 6,
      rawSampleCount: 6,
      distanceM: 100,
      avgSpeedMps: 2,
      maxSpeedMps: 2,
      stationaryRatio: 0,
      quality: WindowQuality.medium,
      evidence: const [MinuteWindow.gpsJitterEvidence],
      userConfirmed: confirmed,
      userExclusionId: excluded ? 'excluded' : null,
    );
void main() {
  setUpAll(() => initializeDateFormatting('ko'));
  test('timeline shows a human warning without internal evidence codes', () {
    expect(timelineWindowSubtitle(window()), contains('GPS 확인 필요'));
    expect(timelineWindowSubtitle(window()), isNot(contains('gps_signal:')));
    expect(
      timelineWindowSubtitle(window(confirmed: true)),
      isNot(contains('GPS 확인 필요')),
    );
  });
  for (final mode in ['review', 'confirmed', 'excluded', 'combined']) {
    testWidgets('GPS notice is actionable and respects $mode at large text', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(320, 740));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final start = DateTime.utc(2026, 11, 7);
      final data = SessionDetailData(
        session: WalkSession(
          id: 'review',
          startedAt: start,
          endedAt: start.add(const Duration(minutes: 2)),
          timezone: 'UTC',
          trackingMode: TrackingMode.balanced,
          status: SessionStatus.completed,
          totalDistanceM: 100,
          durationS: 120,
          movingTimeS: 50,
        ),
        samples: const [],
        windows: [
          window(confirmed: mode == 'confirmed', excluded: mode == 'excluded'),
        ],
        exclusions: mode == 'combined'
            ? [
                RouteExclusion(
                  id: 'auto',
                  sessionId: 'review',
                  startAt: start.add(const Duration(minutes: 1)),
                  endAt: start.add(const Duration(minutes: 2)),
                  reason: RouteExclusionReason.highSpeed,
                  createdAt: start,
                ),
              ]
            : const [],
        route: RoutePartitioner.partition(
          samples: const [],
          exclusions: const [],
        ),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionDetailProvider.overrideWith((ref, id) async => data),
            sessionWeekSummaryProvider.overrideWith((ref, id) async => null),
          ],
          child: MaterialApp(
            theme: mode == 'combined' ? AppTheme.dark() : AppTheme.light(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(2),
                disableAnimations: true,
              ),
              child: child!,
            ),
            home: const SessionDetailScreen(sessionId: 'review'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final shown = mode == 'review' || mode == 'combined';
      expect(
        find.text('GPS 확인이 필요한 구간이 있어요'),
        shown ? findsOneWidget : findsNothing,
      );
      if (shown) {
        await tester.ensureVisible(find.text('구간 살펴보기'));
        await tester.pumpAndSettle();
        expect(find.text('구간 살펴보기').hitTestable(), findsOneWidget);
        expect(
          tester.getSize(find.widgetWithText(TextButton, '구간 살펴보기')).height,
          greaterThanOrEqualTo(48),
        );
        await tester.tap(find.text('구간 살펴보기'));
        await tester.pumpAndSettle();
        expect(find.text('활동 흐름').hitTestable(), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
