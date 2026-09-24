import 'package:flutter_test/flutter_test.dart';
import 'package:sanbo/domain/models/activity_label.dart';
import 'package:sanbo/domain/models/minute_window.dart';
import 'package:sanbo/domain/models/route_exclusion.dart';
import 'package:sanbo/domain/pipeline/segment_merger.dart';
import 'package:sanbo/domain/services/automatic_route_exclusion.dart';

MinuteWindow _window(
  DateTime start, {
  int durationS = 60,
  double maxSpeedMps = 1,
  ActivityLabel? userLabel,
  String? exclusionId,
}) {
  return MinuteWindow(
    windowStart: start,
    durationS: durationS,
    partial: false,
    sampleCount: 3,
    rawSampleCount: 3,
    distanceM: maxSpeedMps * durationS,
    avgSpeedMps: maxSpeedMps,
    maxSpeedMps: maxSpeedMps,
    stationaryRatio: 0,
    quality: WindowQuality.high,
    hypothesisLabel: ActivityLabel.walkSteady,
    hypothesisConfidence: 0.9,
    userLabel: userLabel,
    userConfirmed: userLabel != null,
    userExclusionId: exclusionId,
  );
}

void main() {
  const policy = AutomaticRouteExclusionPolicy();
  final start = DateTime.utc(2026, 9, 1, 9);
  final end = start.add(const Duration(minutes: 4));

  test('excludes a minute at exactly 10 km/h', () {
    final windows = [
      _window(start),
      _window(start.add(const Duration(minutes: 1)), maxSpeedMps: 10 / 3.6),
      _window(start.add(const Duration(minutes: 2))),
    ];

    final candidates = policy.detect(
      windows: windows,
      segments: SegmentMerger().merge(windows),
      sessionStart: start,
      sessionEnd: end,
    );

    expect(candidates, hasLength(1));
    expect(candidates.single.startAt, start.add(const Duration(minutes: 1)));
    expect(candidates.single.endAt, start.add(const Duration(minutes: 2)));
    expect(candidates.single.reason, RouteExclusionReason.highSpeed);
  });

  test('keeps a minute below the 10 km/h threshold', () {
    final windows = [_window(start, maxSpeedMps: 10 / 3.6 - 0.001)];

    expect(
      policy.detect(
        windows: windows,
        segments: SegmentMerger().merge(windows),
        sessionStart: start,
        sessionEnd: start.add(const Duration(minutes: 1)),
      ),
      isEmpty,
    );
  });

  test('does not override an explicit non-vehicle walking label', () {
    final window = _window(
      start,
      maxSpeedMps: 10 / 3.6,
      userLabel: ActivityLabel.walkBrisk,
    );

    expect(
      policy.detect(
        windows: [window],
        segments: SegmentMerger().merge([window]),
        sessionStart: start,
        sessionEnd: start.add(const Duration(minutes: 1)),
      ),
      isEmpty,
    );
  });

  test('ignores zero-duration high-speed windows', () {
    final window = _window(start, durationS: 0, maxSpeedMps: 10 / 3.6);

    expect(
      policy.detect(
        windows: [window],
        segments: SegmentMerger().merge([window]),
        sessionStart: start,
        sessionEnd: start.add(const Duration(minutes: 1)),
      ),
      isEmpty,
    );
  });

  test('ignores zero-duration vehicle segments', () {
    final window = _window(
      start,
      durationS: 0,
      userLabel: ActivityLabel.vehicle,
    );

    expect(
      policy.detect(
        windows: [window],
        segments: SegmentMerger().merge([window]),
        sessionStart: start,
        sessionEnd: start.add(const Duration(minutes: 1)),
      ),
      isEmpty,
    );
  });

  test('excludes a segment manually labelled as vehicle', () {
    final windows = [
      _window(start, userLabel: ActivityLabel.vehicle),
      _window(
        start.add(const Duration(minutes: 1)),
        maxSpeedMps: 1.2,
        userLabel: ActivityLabel.vehicle,
      ),
    ];

    final candidates = policy.detect(
      windows: windows,
      segments: SegmentMerger().merge(windows),
      sessionStart: start,
      sessionEnd: start.add(const Duration(minutes: 2)),
    );

    expect(candidates, hasLength(1));
    expect(candidates.single.startAt, start);
    expect(candidates.single.endAt, start.add(const Duration(minutes: 2)));
    expect(candidates.single.reason, RouteExclusionReason.vehicle);
  });

  test('does not duplicate an already excluded range', () {
    final windows = [
      _window(start, maxSpeedMps: 10 / 3.6, exclusionId: 'existing'),
    ];

    expect(
      policy.detect(
        windows: windows,
        segments: SegmentMerger().merge(windows),
        sessionStart: start,
        sessionEnd: start.add(const Duration(minutes: 1)),
      ),
      isEmpty,
    );
  });

  test('keeps the uncovered tail when an existing exclusion is partial', () {
    final speedWindow = _window(start, maxSpeedMps: 10 / 3.6);
    final existing = RouteExclusion(
      id: 'existing-partial',
      sessionId: 'session-1',
      startAt: start,
      endAt: start.add(const Duration(seconds: 20)),
      reason: RouteExclusionReason.vehicle,
      createdAt: start,
    );

    final candidates = policy.detect(
      windows: [speedWindow],
      segments: SegmentMerger().merge([speedWindow]),
      sessionStart: start,
      sessionEnd: start.add(const Duration(minutes: 1)),
      existingExclusions: [existing],
    );

    expect(candidates, hasLength(1));
    expect(candidates.single.startAt, start.add(const Duration(seconds: 20)));
    expect(candidates.single.endAt, start.add(const Duration(minutes: 1)));
    expect(candidates.single.reason, RouteExclusionReason.highSpeed);
  });

  test('merges adjacent speed-triggered minutes into one candidate', () {
    final windows = [
      _window(start, maxSpeedMps: 10 / 3.6),
      _window(start.add(const Duration(minutes: 1)), maxSpeedMps: 3),
      _window(start.add(const Duration(minutes: 2))),
    ];

    final candidates = policy.detect(
      windows: windows,
      segments: SegmentMerger().merge(windows),
      sessionStart: start,
      sessionEnd: end,
    );

    expect(candidates, hasLength(1));
    expect(candidates.single.startAt, start);
    expect(candidates.single.endAt, start.add(const Duration(minutes: 2)));
  });

  test('keeps the high-speed reason when a vehicle range encloses it', () {
    final windows = [
      _window(start, maxSpeedMps: 1, userLabel: ActivityLabel.vehicle),
      _window(
        start.add(const Duration(minutes: 1)),
        maxSpeedMps: 10 / 3.6,
        userLabel: ActivityLabel.vehicle,
      ),
    ];

    final candidates = policy.detect(
      windows: windows,
      segments: SegmentMerger().merge(windows),
      sessionStart: start,
      sessionEnd: start.add(const Duration(minutes: 2)),
    );

    expect(candidates, hasLength(1));
    expect(candidates.single.reason, RouteExclusionReason.highSpeed);
  });
}
