# 고속 이동 경고와 산책 구간 제외 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 신뢰 가능한 고속 이동이 지속되면 사용자가 기록 종료 여부를 선택하게 하고, 완료된 산책의 차량 이동 구간을 제외하거나 복원하면서 경로와 모든 통계를 일관되게 재계산한다.

**Architecture:** 순수 Dart 계층의 `RoutePartitioner`가 자동 필터, 사용자 제외 범위, GPS 공백을 한 번에 적용하고, 지도와 재생, 분 집계, 세션 집계가 그 결과만 사용한다. `WalkRepository`는 DB v4의 `route_exclusions`를 원본으로 삼아 분 기록과 세션 집계를 한 트랜잭션에서 교체하며, `SessionGuard`는 수신 시각 기반 고속 상태 머신만 담당하고 `SessionController`와 플랫폼 서비스가 typed warning, 화면, 알림을 조정한다.

**Tech Stack:** Flutter 3와 Dart 3.12.2, Riverpod 2.6.1, go_router 14.8.1, sqflite 2.4.2, flutter_map 7.0.2, Android Kotlin MethodChannel, iOS Swift UNUserNotificationCenter, Flutter test, sqflite_common_ffi.

**Spec:** `docs/superpowers/specs/2026-08-21-high-speed-guard-and-route-exclusion-design.md`

## Global Constraints

- 고속 기준은 `8.0 m/s`, 판단 창은 `120초`, 경고 누적은 `60초`, 저속 회복 기준은 `4.0 m/s`, 재활성화는 연속 `30초`로 고정한다.
- 고속 판단 최대 수평 정확도는 `150m`, 정지 판단 정확도 기준은 `80m`, 오래된 receipt 허용치는 `30초`, 미래 허용치는 `5초`, 인접 위치 공백은 기존 `trustedLocationGap`을 사용한다.
- 80m 초과 정확도 샘플이 포함된 고속 구간은 전체 순이동량이나 최근 경고 시간 절반의 rolling 순이동량 `200m` 이상을 추가로 요구해 GPS 왕복 흔들림을 경고로 오인하지 않으면서 차량 회전과 되돌림을 놓치지 않는다.
- 고속 이동만으로 기록을 자동 종료하지 않으며, 기존 정지 `20분` 경고와 `30분` 종료, 전체 `4시간 45분` 경고와 `5시간` 종료를 변경하지 않는다.
- 사용자 제외 범위는 `[startAt, endAt)` 반개구간이며, 세션 경계로 clamp하고 절대 시각으로 비교한 뒤 UTC ISO 8601 문자열로 저장한다.
- `location_samples`에는 `user_exclusion_id`를 추가하지 않고, 저장된 `is_filtered_out` 값과 행을 제외 및 복원 과정에서 변경하지 않는다.
- 사용자 제외 원본은 `route_exclusions`, `minute_windows.user_exclusion_id`는 타임라인 표시와 복원을 위한 파생 상태로 사용한다.
- 서로 겹치는 제외 범위는 거부하고 정확히 맞닿은 범위는 서로 다른 레코드로 유지한다.
- 경로와 재생, 분 집계, 세션 집계는 모두 `RoutePartitioner`가 만든 같은 fragments, includedSamples, segments를 사용한다.
- 제외된 분은 삭제하지 않고 `quality = gap`, `gap_reason = user_excluded`, 거리와 속도와 유효 샘플 수를 0으로 저장하며 `raw_sample_count`와 사용자 라벨, 메모, 확정 상태, 장소 연결을 보존한다.
- 완료 세션의 `started_at`과 `ended_at`은 변경하지 않고, `duration_s`만 전체 기록 시간에서 제외 범위 합계를 뺀 유효 시간으로 저장한다.
- 제외 및 복원은 제외 레코드, 분 기록, 세션 집계를 하나의 SQLite 트랜잭션에서 모두 반영하거나 모두 롤백한다.
- 알림 권한 요청과 표시 실패는 비치명이며 위치 권한, location engine 시작, 세션 생성과 기록을 지연하거나 실패시키지 않는다.
- 전체 백업은 schema v1과 v2를 읽고 v2를 쓰며, 단일 세션 NDJSON은 `schema_version: 2`로 내보낸다.
- 새 런타임 의존성을 추가하지 않는다.

---

### Task 1: 제외 모델, 경로 분할, 완료 기록 재계산 도메인

**Files:**
- Create: `lib/domain/models/route_exclusion.dart`
- Create: `lib/domain/pipeline/route_partitioner.dart`
- Create: `test/domain/route_partitioner_test.dart`
- Modify: `lib/domain/models/minute_window.dart`
- Modify: `lib/domain/pipeline/segment_merger.dart`
- Modify: `lib/domain/pipeline/window_aggregator.dart`
- Modify: `lib/domain/pipeline/session_rollup.dart`
- Modify: `lib/domain/services/session_pipeline.dart`
- Modify: `test/domain/segment_merger_test.dart`
- Modify: `test/domain/window_aggregator_test.dart`
- Modify: `test/domain/session_rollup_test.dart`
- Modify: `test/domain/session_pipeline_test.dart`

**Interfaces:**
- Consumes: 기존 `LocationSample.isFilteredOut`, `trustedLocationGap`, `MinuteWindow`, `WalkSession`, `ActivitySegment`.
- Produces: `RouteExclusion`, `RouteExclusionReason.vehicle`, `RouteExclusion.clampedTo(WalkSession)`, `RoutePartitioner.partition({required List<LocationSample> samples, required List<RouteExclusion> exclusions, Duration maxGap}) -> RoutePartitionResult`, `RouteFragment`, `RouteSegment`, `MinuteWindow.userExclusionId`, `MinuteWindow.isUserExcluded`, `WindowAggregator.aggregate({required RoutePartitionResult partition, required List<LocationSample> rawSamples, required List<RouteExclusion> exclusions, required DateTime sessionStart, required DateTime sessionEnd}) -> List<MinuteWindow>`, `SessionRollup.compute({required WalkSession session, required RoutePartitionResult partition, required List<RouteExclusion> exclusions, required DateTime endedAt}) -> SessionRollupResult`, `SessionProcessResult.fragments`, `SessionPipeline.recalculateCompleted({required WalkSession session, required List<LocationSample> storedSamples, required List<RouteExclusion> exclusions, required List<MinuteWindow> previousWindows}) -> CompletedSessionRecalculation`.

- [ ] **Step 1: Write the failing domain tests**

  `test/domain/route_partitioner_test.dart`에 자동 필터, 제외 내부 샘플, 제외 범위를 가로지르는 선분, GPS 공백을 하나의 테스트로 고정한다.

  ```dart
  import 'package:flutter_test/flutter_test.dart';
  import 'package:sanbo/domain/models/location_sample.dart';
  import 'package:sanbo/domain/models/route_exclusion.dart';
  import 'package:sanbo/domain/pipeline/route_partitioner.dart';

  void main() {
    test('partition never bridges filters, exclusions, or trusted gaps', () {
      final t = DateTime.utc(2026, 8, 21, 0);
      LocationSample fix(int second, double lon, {bool filtered = false}) {
        return LocationSample(
          timestamp: t.add(Duration(seconds: second)),
          latitude: 37.5,
          longitude: lon,
          accuracyM: 5,
          isFilteredOut: filtered,
        );
      }

      final result = RoutePartitioner.partition(
        samples: [
          fix(0, 127.0000),
          fix(10, 127.0001),
          fix(20, 127.0002, filtered: true),
          fix(30, 127.0003),
          fix(70, 127.0007),
          fix(80, 127.0008),
          fix(120, 127.0012),
        ],
        exclusions: [
          RouteExclusion(
            id: 'vehicle-1',
            sessionId: 'walk-1',
            startAt: t.add(const Duration(seconds: 35)),
            endAt: t.add(const Duration(seconds: 65)),
            reason: RouteExclusionReason.vehicle,
            createdAt: t,
          ),
        ],
        maxGap: const Duration(seconds: 30),
      );

      expect(result.includedSamples.map((sample) => sample.timestamp), [
        t,
        t.add(const Duration(seconds: 10)),
        t.add(const Duration(seconds: 30)),
        t.add(const Duration(seconds: 70)),
        t.add(const Duration(seconds: 80)),
        t.add(const Duration(seconds: 120)),
      ]);
      expect(result.fragments.map((fragment) => fragment.samples.length), [2, 1, 2, 1]);
      expect(result.segments, hasLength(2));
      expect(result.segments.every((segment) => segment.duration <= const Duration(seconds: 30)), isTrue);
    });

    test('an exclusion crossing a segment splits two outside endpoints', () {
      final t = DateTime.utc(2026, 8, 21, 0);
      final result = RoutePartitioner.partition(
        samples: [
          LocationSample(timestamp: t, latitude: 37.5, longitude: 127, accuracyM: 5),
          LocationSample(timestamp: t.add(const Duration(seconds: 20)), latitude: 37.5, longitude: 127.001, accuracyM: 5),
        ],
        exclusions: [
          RouteExclusion(
            id: 'vehicle-1',
            sessionId: 'walk-1',
            startAt: t.add(const Duration(seconds: 8)),
            endAt: t.add(const Duration(seconds: 12)),
            reason: RouteExclusionReason.vehicle,
            createdAt: t,
          ),
        ],
      );
      expect(result.fragments.map((fragment) => fragment.samples.length), [1, 1]);
      expect(result.segments, isEmpty);
    });

    test('normalizes instants to UTC and rejects invalid identities and ranges', () {
      final start = DateTime.parse('2026-08-21T09:00:00+09:00');
      final exclusion = RouteExclusion(
        id: 'vehicle-1',
        sessionId: 'walk-1',
        startAt: start,
        endAt: start.add(const Duration(minutes: 1)),
        reason: RouteExclusionReason.vehicle,
        createdAt: start,
      );
      expect(exclusion.startAt, DateTime.utc(2026, 8, 21));
      expect(exclusion.endAt, DateTime.utc(2026, 8, 21, 0, 1));
      expect(exclusion.createdAt.isUtc, isTrue);
      expect(
        () => RouteExclusion(
          id: ' ',
          sessionId: 'walk-1',
          startAt: start,
          endAt: start.add(const Duration(minutes: 1)),
          reason: RouteExclusionReason.vehicle,
          createdAt: start,
        ),
        throwsArgumentError,
      );
      expect(
        () => RouteExclusion(
          id: 'vehicle-2',
          sessionId: '',
          startAt: start,
          endAt: start,
          reason: RouteExclusionReason.vehicle,
          createdAt: start,
        ),
        throwsArgumentError,
      );
    });
  }
  ```

  `test/domain/session_pipeline_test.dart`에는 저장된 자동 필터를 재실행하지 않고 메타데이터를 보존하는 재계산 테스트를 추가한다.

  ```dart
  test('completed recalculation preserves stored filter and minute metadata', () {
    final start = DateTime.utc(2026, 8, 21, 0);
    final session = WalkSession(
      id: 'walk-1',
      startedAt: start,
      endedAt: start.add(const Duration(minutes: 2)),
      timezone: 'Asia/Seoul',
      trackingMode: TrackingMode.balanced,
      status: SessionStatus.completed,
    );
    final stored = [
      LocationSample(timestamp: start, latitude: 37.5, longitude: 127, accuracyM: 5),
      LocationSample(timestamp: start.add(const Duration(seconds: 30)), latitude: 37.5003, longitude: 127, accuracyM: 5),
      LocationSample(timestamp: start.add(const Duration(seconds: 60)), latitude: 37.5006, longitude: 127, accuracyM: 5, isFilteredOut: true),
      LocationSample(timestamp: start.add(const Duration(seconds: 90)), latitude: 37.5009, longitude: 127, accuracyM: 5),
    ];
    final previous = [
      MinuteWindow(
        windowStart: start,
        durationS: 60,
        partial: false,
        sampleCount: 2,
        rawSampleCount: 2,
        distanceM: 30,
        avgSpeedMps: 1,
        maxSpeedMps: 1,
        stationaryRatio: 0,
        quality: WindowQuality.high,
        userLabel: ActivityLabel.walkBrisk,
        userNote: '강변',
        userConfirmed: true,
        placeId: 7,
      ),
    ];
    final exclusion = RouteExclusion(
      id: 'vehicle-1',
      sessionId: session.id,
      startAt: start,
      endAt: start.add(const Duration(minutes: 1)),
      reason: RouteExclusionReason.vehicle,
      createdAt: start,
    );

    final result = SessionPipeline().recalculateCompleted(
      session: session,
      storedSamples: stored,
      exclusions: [exclusion],
      previousWindows: previous,
    );

    expect(stored[2].isFilteredOut, isTrue);
    expect(result.windows.first.userExclusionId, exclusion.id);
    expect(result.windows.first.gapReason, 'user_excluded');
    expect(result.windows.first.rawSampleCount, 2);
    expect(result.windows.first.userLabel, ActivityLabel.walkBrisk);
    expect(result.windows.first.userNote, '강변');
    expect(result.windows.first.placeId, 7);
    expect(result.metrics.durationS, 60);
    expect(result.metrics.totalDistanceM, 0);
    expect(result.metrics.avgSpeedMps.isFinite, isTrue);
  });

  test('live processing preserves the automatic-filter boundary', () {
    final start = DateTime.utc(2026, 8, 21);
    final raw = [
      LocationSample(timestamp: start, latitude: 37.5, longitude: 127, accuracyM: 5),
      LocationSample(timestamp: start.add(const Duration(seconds: 10)), latitude: 38.5, longitude: 127, accuracyM: 5),
      LocationSample(timestamp: start.add(const Duration(seconds: 20)), latitude: 37.5001, longitude: 127, accuracyM: 5),
    ];
    final session = WalkSession(
      id: 'live-1',
      startedAt: start,
      timezone: 'Asia/Seoul',
      trackingMode: TrackingMode.balanced,
    );
    final result = SessionPipeline().process(
      session: session,
      rawSamples: raw,
      endedAt: start.add(const Duration(seconds: 20)),
    );
    expect(result.filteredSamples.map((sample) => sample.isFilteredOut), [false, true, false]);
    expect(result.fragments.map((fragment) => fragment.samples.length), [1, 1]);
    expect(result.metrics.totalDistanceM, 0);
  });
  ```

  `test/domain/segment_merger_test.dart`에 서로 다른 제외 ID를 합치지 않는 assertion을 추가한다.

  ```dart
  test('merges only adjacent excluded windows with the same exclusion id', () {
    final start = DateTime(2026, 8, 21, 9);
    MinuteWindow excluded(int minute, String id) => MinuteWindow(
      windowStart: start.add(Duration(minutes: minute)),
      durationS: 60,
      partial: false,
      sampleCount: 0,
      rawSampleCount: 3,
      distanceM: 0,
      avgSpeedMps: 0,
      maxSpeedMps: 0,
      stationaryRatio: 1,
      quality: WindowQuality.gap,
      gapReason: 'user_excluded',
      userExclusionId: id,
    );
    final segments = SegmentMerger().merge([
      excluded(0, 'a'),
      excluded(1, 'a'),
      excluded(2, 'b'),
    ]);
    expect(segments, hasLength(2));
    expect(segments.first.userExclusionId, 'a');
    expect(segments.last.userExclusionId, 'b');
  });
  ```

- [ ] **Step 2: Run focused tests to verify RED**

  Run: `flutter test --no-pub --concurrency=1 test/domain/route_partitioner_test.dart test/domain/session_pipeline_test.dart test/domain/segment_merger_test.dart test/domain/window_aggregator_test.dart test/domain/session_rollup_test.dart`

  Expected: FAIL with missing `route_exclusion.dart`, `route_partitioner.dart`, `recalculateCompleted`, and `userExclusionId` APIs.

- [ ] **Step 3: Implement the pure domain model and shared partition path**

  Create `lib/domain/models/route_exclusion.dart` with UTC normalization, identifier validation, reason validation through the closed enum, and session clamp at the model boundary.

  ```dart
  import 'walk_session.dart';

  enum RouteExclusionReason { vehicle }

  class RouteExclusion {
    factory RouteExclusion({
      required String id,
      required String sessionId,
      required DateTime startAt,
      required DateTime endAt,
      required RouteExclusionReason reason,
      required DateTime createdAt,
    }) {
      if (id.trim().isEmpty || id != id.trim()) {
        throw ArgumentError.value(id, 'id', '비어 있거나 공백이 있는 ID입니다');
      }
      if (sessionId.trim().isEmpty || sessionId != sessionId.trim()) {
        throw ArgumentError.value(sessionId, 'sessionId', '비어 있거나 공백이 있는 세션 ID입니다');
      }
      final normalizedStart = startAt.toUtc();
      final normalizedEnd = endAt.toUtc();
      if (!normalizedStart.isBefore(normalizedEnd)) {
        throw ArgumentError('제외 시작은 종료보다 빨라야 합니다');
      }
      return RouteExclusion._(
        id: id,
        sessionId: sessionId,
        startAt: normalizedStart,
        endAt: normalizedEnd,
        reason: reason,
        createdAt: createdAt.toUtc(),
      );
    }

    const RouteExclusion._({
      required this.id,
      required this.sessionId,
      required this.startAt,
      required this.endAt,
      required this.reason,
      required this.createdAt,
    });

    final String id;
    final String sessionId;
    final DateTime startAt;
    final DateTime endAt;
    final RouteExclusionReason reason;
    final DateTime createdAt;

    RouteExclusion clampedTo(WalkSession session) {
      final endedAt = session.endedAt;
      if (session.id != sessionId || endedAt == null || session.status != SessionStatus.completed) {
        throw StateError('완료된 대상 산책과 제외 범위가 일치하지 않습니다');
      }
      final sessionStart = session.startedAt.toUtc();
      final sessionEnd = endedAt.toUtc();
      final start = startAt.isBefore(sessionStart) ? sessionStart : startAt;
      final end = endAt.isAfter(sessionEnd) ? sessionEnd : endAt;
      if (!start.isBefore(end)) throw ArgumentError('제외할 수 있는 시간 범위가 없습니다');
      return RouteExclusion(
        id: id,
        sessionId: sessionId,
        startAt: start,
        endAt: end,
        reason: reason,
        createdAt: createdAt,
      );
    }

    bool contains(DateTime value) {
      final instant = value.toUtc();
      return !instant.isBefore(startAt.toUtc()) && instant.isBefore(endAt.toUtc());
    }

    bool overlaps(DateTime start, DateTime end) {
      return start.toUtc().isBefore(endAt.toUtc()) && end.toUtc().isAfter(startAt.toUtc());
    }
  }
  ```

  Create `lib/domain/pipeline/route_partitioner.dart`. `RouteSegment` stores the only connections that downstream metrics may count.

  ```dart
  import '../models/location_sample.dart';
  import '../models/route_exclusion.dart';
  import 'geo.dart';

  class RouteSegment {
    const RouteSegment({required this.start, required this.end, required this.distanceM});
    final LocationSample start;
    final LocationSample end;
    final double distanceM;
    Duration get duration => end.timestamp.difference(start.timestamp);
    double get speedMps => distanceM / (duration.inMilliseconds / 1000);
  }

  class RouteFragment {
    const RouteFragment(this.samples);
    final List<LocationSample> samples;
  }

  class RoutePartitionResult {
    const RoutePartitionResult({
      required this.fragments,
      required this.includedSamples,
      required this.segments,
    });
    final List<RouteFragment> fragments;
    final List<LocationSample> includedSamples;
    final List<RouteSegment> segments;
  }

  abstract final class RoutePartitioner {
    static RoutePartitionResult partition({
      required List<LocationSample> samples,
      required List<RouteExclusion> exclusions,
      Duration maxGap = trustedLocationGap,
    }) {
      final orderedSamples = [...samples]
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      final orderedExclusions = [...exclusions]
        ..sort((a, b) => a.startAt.compareTo(b.startAt));
      for (var index = 1; index < orderedExclusions.length; index++) {
        if (orderedExclusions[index].startAt.isBefore(orderedExclusions[index - 1].endAt)) {
          throw ArgumentError('겹치는 제외 범위가 있습니다');
        }
      }
      final included = <LocationSample>[];
      final fragments = <RouteFragment>[];
      final segments = <RouteSegment>[];
      var current = <LocationSample>[];

      void flush() {
        if (current.isEmpty) return;
        fragments.add(RouteFragment(List.unmodifiable(current)));
        current = <LocationSample>[];
      }

      for (final sample in orderedSamples) {
        final excluded = orderedExclusions.any(
          (exclusion) => exclusion.contains(sample.timestamp),
        );
        if (sample.isFilteredOut || !_validFix(sample) || excluded) {
          flush();
          continue;
        }
        included.add(sample);
        if (current.isEmpty) {
          current = [sample];
          continue;
        }
        final previous = current.last;
        final dt = sample.timestamp.difference(previous.timestamp);
        final crossesExclusion = orderedExclusions.any(
          (exclusion) => exclusion.overlaps(previous.timestamp, sample.timestamp),
        );
        final distance = haversineMeters(
          lat1: previous.latitude,
          lon1: previous.longitude,
          lat2: sample.latitude,
          lon2: sample.longitude,
        );
        final connect = dt > Duration.zero &&
            dt <= maxGap &&
            !crossesExclusion &&
            distance.isFinite;
        if (!connect) {
          flush();
          current = [sample];
          continue;
        }
        current.add(sample);
        segments.add(RouteSegment(start: previous, end: sample, distanceM: distance));
      }
      flush();
      return RoutePartitionResult(
        fragments: List.unmodifiable(fragments),
        includedSamples: List.unmodifiable(included),
        segments: List.unmodifiable(segments),
      );
    }

    static bool _validFix(LocationSample sample) {
      return sample.timestamp.microsecondsSinceEpoch > 0 &&
          sample.latitude.isFinite &&
          sample.longitude.isFinite &&
          sample.latitude >= -90 &&
          sample.latitude <= 90 &&
          sample.longitude >= -180 &&
          sample.longitude <= 180;
    }
  }
  ```

  Add `String? userExclusionId` and `bool get isUserExcluded => userExclusionId != null` to `MinuteWindow`, carry the field through every constructor reconstruction, and add `String? get userExclusionId` to `ActivitySegment`. In `SegmentMerger._canMerge`, run this before label and gap rules.

  ```dart
  if (a.userExclusionId != b.userExclusionId) return false;
  if (a.isUserExcluded || b.isUserExcluded) {
    return a.userExclusionId == b.userExclusionId &&
        b.windowStart == a.windowStart.add(const Duration(minutes: 1));
  }
  ```

  Change `WindowAggregator.aggregate` to the exact method declaration below, then implement its body with the allocation algorithm that follows. It never scans adjacent `rawSamples` to derive a connection; `rawSamples` supplies only raw counts and exclusion-window coverage, while all distance and motion comes from `partition.segments`.

  ```dart
  List<MinuteWindow> aggregate({
    required RoutePartitionResult partition,
    required List<LocationSample> rawSamples,
    required List<RouteExclusion> exclusions,
    required DateTime sessionStart,
    required DateTime sessionEnd,
  });
  ```

  For each `RouteSegment`, walk every wall-clock minute interval that intersects `[segment.start.timestamp, segment.end.timestamp)`. Compute `overlapUs = min(segmentEnd, windowEnd) - max(segmentStart, windowStart)`, then add `segment.distanceM * overlapUs / segment.duration.inMicroseconds` to that minute. Add `overlapUs` to moving or stationary time according to the original segment speed. A fragment boundary has no `RouteSegment`, so the aggregator has nothing it can allocate across that boundary and must never reconstruct one from endpoints. Bucket `partition.includedSamples` for count, coordinates, and accuracy. Add an `excludedWindows` map keyed by local minute start and emit the exact excluded form below before inference.

  ```dart
  MinuteWindow _excludedWindow({
    required DateTime windowStart,
    required int durationS,
    required int rawSampleCount,
    required String exclusionId,
  }) => MinuteWindow(
    windowStart: windowStart,
    durationS: durationS,
    partial: durationS < 60,
    sampleCount: 0,
    rawSampleCount: rawSampleCount,
    distanceM: 0,
    avgSpeedMps: 0,
    maxSpeedMps: 0,
    stationaryRatio: 1,
    quality: WindowQuality.gap,
    gapReason: 'user_excluded',
    userExclusionId: exclusionId,
  );
  ```

  Add this boundary-allocation regression to `test/domain/window_aggregator_test.dart` before implementation:

  ```dart
  test('splits one trusted segment proportionally at a minute boundary', () {
    final start = DateTime.utc(2026, 8, 21, 0, 0, 50);
    final first = LocationSample(timestamp: start, latitude: 37.5, longitude: 127, accuracyM: 5);
    final second = LocationSample(
      timestamp: start.add(const Duration(seconds: 20)),
      latitude: 37.5,
      longitude: 127.000226,
      accuracyM: 5,
    );
    final partition = RoutePartitioner.partition(samples: [first, second], exclusions: const []);
    final windows = WindowAggregator().aggregate(
      partition: partition,
      rawSamples: [first, second],
      exclusions: const [],
      sessionStart: start,
      sessionEnd: second.timestamp,
    );
    expect(windows, hasLength(2));
    expect(windows[0].distanceM, closeTo(partition.segments.single.distanceM / 2, 0.01));
    expect(windows[1].distanceM, closeTo(partition.segments.single.distanceM / 2, 0.01));
    expect(windows[0].distanceM + windows[1].distanceM, closeTo(partition.segments.single.distanceM, 0.01));
  });

  test('does not allocate distance across a fragment boundary', () {
    final start = DateTime.utc(2026, 8, 21, 0, 0, 50);
    final before = LocationSample(timestamp: start, latitude: 37.5, longitude: 127, accuracyM: 5);
    final boundary = LocationSample(
      timestamp: start.add(const Duration(seconds: 10)),
      latitude: 37.5,
      longitude: 127.0001,
      accuracyM: 5,
      isFilteredOut: true,
    );
    final after = LocationSample(
      timestamp: start.add(const Duration(seconds: 20)),
      latitude: 37.5,
      longitude: 127.0002,
      accuracyM: 5,
    );
    final partition = RoutePartitioner.partition(samples: [before, boundary, after], exclusions: const []);
    final windows = WindowAggregator().aggregate(
      partition: partition,
      rawSamples: [before, boundary, after],
      exclusions: const [],
      sessionStart: start,
      sessionEnd: after.timestamp,
    );
    expect(partition.fragments, hasLength(2));
    expect(partition.segments, isEmpty);
    expect(windows.fold<double>(0, (sum, window) => sum + window.distanceM), 0);
  });
  ```

  Migrate both existing `window_aggregator_test.dart` calls with this exact adapter, using each test's existing `samples`, `start`, and `end` variables:

  ```dart
  final partition = RoutePartitioner.partition(
    samples: samples,
    exclusions: const [],
  );
  final windows = WindowAggregator().aggregate(
    partition: partition,
    rawSamples: samples,
    exclusions: const [],
    sessionStart: start,
    sessionEnd: end,
  );
  ```

  Change `SessionRollup.compute` to accept `RoutePartitionResult partition` and `List<RouteExclusion> exclusions`. Sum distance, moving time, stationary time from `partition.segments`, derive median accuracy and count from `partition.includedSamples`, and derive duration with this exact rule. Before subtraction, require `endedAt >= session.startedAt`, every exclusion belongs to the session and is contained in the full session interval, and sorted exclusions do not overlap. Because all values are validated, subtraction stays an `int` and needs no arbitrary upper clamp.

  ```dart
  final sessionStart = session.startedAt.toUtc();
  final sessionEnd = endedAt.toUtc();
  if (sessionEnd.isBefore(sessionStart)) {
    throw StateError('종료 시각이 시작 시각보다 빠릅니다');
  }
  final ordered = [...exclusions]..sort((a, b) => a.startAt.compareTo(b.startAt));
  for (var index = 0; index < ordered.length; index++) {
    final exclusion = ordered[index];
    if (exclusion.sessionId != session.id ||
        exclusion.startAt.isBefore(sessionStart) ||
        exclusion.endAt.isAfter(sessionEnd)) {
      throw StateError('세션 범위를 벗어난 제외 구간이 있습니다');
    }
    if (index > 0 && exclusion.startAt.isBefore(ordered[index - 1].endAt)) {
      throw StateError('겹치는 제외 구간이 있습니다');
    }
  }
  final int fullDurationS = sessionEnd.difference(sessionStart).inSeconds;
  final excludedSeconds = exclusions.fold<int>(
    0,
    (sum, exclusion) => sum + exclusion.endAt.difference(exclusion.startAt).inSeconds,
  );
  if (excludedSeconds < 0 || excludedSeconds > fullDurationS) {
    throw StateError('제외 시간이 전체 기록 시간을 벗어납니다');
  }
  final int durationS = fullDurationS - excludedSeconds;
  ```

  Migrate every existing `session_rollup_test.dart` call by creating `RoutePartitioner.partition(samples: samples, exclusions: const [])` and passing that result plus `exclusions: const []`; remove the old `samples:` argument. Add an assertion that `result.durationS` has static type `int` by assigning `final int duration = result.durationS`, and cover a 10-day completed session to prove no seven-day truncation remains.

  Add `SessionPipeline.recalculateCompleted`. It must call `RoutePartitioner` directly and must not reference `filter.apply`.

  ```dart
  CompletedSessionRecalculation recalculateCompleted({
    required WalkSession session,
    required List<LocationSample> storedSamples,
    required List<RouteExclusion> exclusions,
    required List<MinuteWindow> previousWindows,
  }) {
    final endedAt = session.endedAt;
    if (endedAt == null || session.status != SessionStatus.completed) {
      throw StateError('완료된 산책만 다시 계산할 수 있습니다');
    }
    final normalized = exclusions.map((item) => item.clampedTo(session)).toList()
      ..sort((a, b) => a.startAt.compareTo(b.startAt));
    for (var index = 1; index < normalized.length; index++) {
      if (normalized[index].startAt.isBefore(normalized[index - 1].endAt)) {
        throw StateError('겹치는 제외 범위가 있습니다');
      }
    }
    final partition = RoutePartitioner.partition(
      samples: storedSamples,
      exclusions: normalized,
    );
    final metadata = {for (final window in previousWindows) window.windowStart.toUtc(): window};
    final rebuilt = aggregator.aggregate(
      partition: partition,
      exclusions: normalized,
      rawSamples: storedSamples,
      sessionStart: session.startedAt,
      sessionEnd: endedAt,
    );
    final windows = rebuilt.map((window) => _restoreMetadata(window, metadata[window.windowStart.toUtc()])).toList();
    final metrics = rollup.compute(
      session: session,
      partition: partition,
      exclusions: normalized,
      endedAt: endedAt,
    );
    if (!_finiteMetrics(metrics)) throw StateError('재계산 결과가 올바르지 않습니다');
    return CompletedSessionRecalculation(
      windows: List.unmodifiable(windows),
      fragments: partition.fragments,
      metrics: metrics,
    );
  }
  ```

  `_restoreMetadata` copies `userLabel`, `userNote`, `userConfirmed`, and an existing `placeId`; it never restores prior derived distance, speed, quality, hypothesis, or `userExclusionId`.

  Keep the live signature `process({required WalkSession session, required List<LocationSample> rawSamples, required DateTime endedAt})`. It calls `final markedSamples = filter.apply(rawSamples)` exactly once. `SampleFilter.apply` returns every source sample in timestamp order with `isFilteredOut` marked, so pass the complete `markedSamples`, not `markedSamples.where(...)`, to `RoutePartitioner.partition(samples: markedSamples, exclusions: const [])`. Feed that partition and the same `markedSamples` to the shared aggregator and rollup, add `required List<RouteFragment> fragments` to `SessionProcessResult`, and return `filteredSamples: markedSamples` plus `fragments: partition.fragments` for persistence and tests. The completed signature remains `recalculateCompleted(... storedSamples ...)`; it passes all stored rows directly to `RoutePartitioner` and contains no `filter.apply` call. This preserves each automatic-filter boundary in both paths while preventing a later edit from changing the saved filter decision.

- [ ] **Step 4: Run focused tests to verify GREEN**

  Run: `dart format lib/domain/models/route_exclusion.dart lib/domain/models/minute_window.dart lib/domain/pipeline/route_partitioner.dart lib/domain/pipeline/segment_merger.dart lib/domain/pipeline/window_aggregator.dart lib/domain/pipeline/session_rollup.dart lib/domain/services/session_pipeline.dart test/domain/route_partitioner_test.dart test/domain/segment_merger_test.dart test/domain/window_aggregator_test.dart test/domain/session_rollup_test.dart test/domain/session_pipeline_test.dart && flutter test --no-pub --concurrency=1 test/domain/route_partitioner_test.dart test/domain/segment_merger_test.dart test/domain/window_aggregator_test.dart test/domain/session_rollup_test.dart test/domain/session_pipeline_test.dart`

  Expected: all focused domain tests PASS, including zero samples, one sample, all excluded, endpoint exclusion, offset-equivalent instants, and finite zero metrics.

- [x] **Step 5: Commit**

  ```bash
  git add lib/domain/models/route_exclusion.dart lib/domain/models/minute_window.dart lib/domain/pipeline/route_partitioner.dart lib/domain/pipeline/segment_merger.dart lib/domain/pipeline/window_aggregator.dart lib/domain/pipeline/session_rollup.dart lib/domain/services/session_pipeline.dart test/domain/route_partitioner_test.dart test/domain/segment_merger_test.dart test/domain/window_aggregator_test.dart test/domain/session_rollup_test.dart test/domain/session_pipeline_test.dart
  git commit -m "feat: add shared route exclusion pipeline"
  ```

### Task 2: DB v4와 원자적 구간 제외 및 복원

**Files:**
- Modify: `lib/data/app_database.dart`
- Modify: `lib/data/walk_repository.dart`
- Modify: `test/data/app_database_migration_test.dart`
- Modify: `test/data/walk_repository_test.dart`
- Create: `test/helpers/route_exclusion_fixture.dart`

**Interfaces:**
- Consumes: Task 1의 `RouteExclusion`, `RouteExclusionReason`, `SessionPipeline.recalculateCompleted`, `MinuteWindow.userExclusionId`, `CompletedSessionRecalculation`.
- Produces: DB `schemaVersion = 4`, `WalkRepository.getRouteExclusions(String)`, `WalkRepository.excludeRouteSegment({required String sessionId, required ActivitySegment segment, RouteExclusionReason reason = RouteExclusionReason.vehicle, DateTime? createdAt}) -> Future<RouteExclusion>`, `WalkRepository.restoreRouteExclusion({required String sessionId, required String exclusionId}) -> Future<void>`.

- [ ] **Step 1: Write failing migration and repository tests**

  Extend `test/data/app_database_migration_test.dart` with a realistic v3 fixture and schema equivalence assertions.

  ```dart
  test('v3 upgrades to v4 without changing samples or existing aggregates', () async {
    ensureSqfliteFfi();
    final path = '${Directory.systemTemp.path}/sanbo_v3_to_v4_${DateTime.now().microsecondsSinceEpoch}.db';
    addTearDown(() => databaseFactory.deleteDatabase(path));
    await createV3Fixture(path, sessionId: 'walk-1', filteredFlags: [0, 1]);

    final db = await openAppDatabase(path: path);
    addTearDown(db.close);
    expect(await db.query('route_exclusions'), isEmpty);
    final columns = await db.rawQuery('PRAGMA table_info(minute_windows)');
    expect(columns.map((row) => row['name']), contains('user_exclusion_id'));
    expect((await db.query('minute_windows')).single['user_exclusion_id'], isNull);
    expect((await db.query('location_samples')).map((row) => row['is_filtered_out']), [0, 1]);
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });
  ```

  Add an end-to-end transaction test to `test/data/walk_repository_test.dart`.

  ```dart
  test('exclude and restore atomically recalculate while preserving source rows and metadata', () async {
    final repo = await openTestRepository();
    addTearDown(repo.close);
    final fixture = await seedCompletedTwoMinuteWalk(repo);
    final beforeSamples = await repo.getSamples(fixture.session.id);

    final exclusion = await repo.excludeRouteSegment(
      sessionId: fixture.session.id,
      segment: fixture.segments.last,
      createdAt: DateTime.utc(2026, 8, 21, 1),
    );

    expect(exclusion.startAt.isUtc, isTrue);
    expect(exclusion.endAt.isUtc, isTrue);
    expect(await repo.getSamples(fixture.session.id), beforeSamples);
    final excludedWindows = await repo.getWindows(fixture.session.id);
    expect(excludedWindows.where((window) => window.userExclusionId == exclusion.id), isNotEmpty);
    expect(excludedWindows.first.userNote, fixture.windows.first.userNote);
    expect(excludedWindows.first.placeId, fixture.windows.first.placeId);
    final reduced = await repo.getSession(fixture.session.id);
    expect(reduced!.durationS, 60);

    await repo.restoreRouteExclusion(sessionId: fixture.session.id, exclusionId: exclusion.id);
    expect(await repo.getRouteExclusions(fixture.session.id), isEmpty);
    expect(await repo.getSamples(fixture.session.id), beforeSamples);
    final restored = await repo.getSession(fixture.session.id);
    expect(restored!.durationS, fixture.session.durationS);
    expect(restored.totalDistanceM, closeTo(fixture.session.totalDistanceM!, 0.001));
  });
  ```

  Add separate assertions for active session rejection, zero length, out-of-range clamp, overlap rejection, touching ranges acceptance, unknown exclusion ID, DST and offset-equivalent instants, and forced failures during exclusion insert, window replacement, and session update. Inject failures at SQLite level instead of adding production hooks. Each case uses a fresh DB path, snapshots all four tables through a second `Database` connection, installs one abort trigger, closes that connection, invokes the public repository command, then reopens the DB and compares the full snapshots.

  ```dart
  for (final failure in <({String name, String sql})>[
    (
      name: 'exclusion_insert',
      sql: '''
  CREATE TRIGGER fail_route_exclusion_insert
  BEFORE INSERT ON route_exclusions
  BEGIN SELECT RAISE(ABORT, 'forced exclusion failure'); END
  ''',
    ),
    (
      name: 'window_replacement',
      sql: '''
  CREATE TRIGGER fail_window_insert
  BEFORE INSERT ON minute_windows
  BEGIN SELECT RAISE(ABORT, 'forced window failure'); END
  ''',
    ),
    (
      name: 'session_update',
      sql: '''
  CREATE TRIGGER fail_session_rollup_update
  BEFORE UPDATE OF total_distance_m ON sessions
  BEGIN SELECT RAISE(ABORT, 'forced session failure'); END
  ''',
    ),
  ]) {
    test('${failure.name} rolls back every route-edit table', () async {
      final path = '${Directory.systemTemp.path}/sanbo_route_rollback_${failure.name}.db';
      addTearDown(() => databaseFactory.deleteDatabase(path));
      final repo = await openTestRepository(path: path);
      addTearDown(repo.close);
      final fixture = await seedCompletedTwoMinuteWalk(repo);
      final before = await snapshotRouteEditTables(path);
      final injector = await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      await injector.execute(failure.sql);
      await injector.close();

      await expectLater(
        repo.excludeRouteSegment(
          sessionId: fixture.session.id,
          segment: fixture.segments.last,
        ),
        throwsA(isA<DatabaseException>()),
      );
      expect(await snapshotRouteEditTables(path), before);
    });
  }
  ```

  `snapshotRouteEditTables(String path)` returns a deep JSON encoding of ordered queries for `route_exclusions`, `minute_windows`, `sessions`, and `location_samples`; ordering is by each table's primary key. Comparing encoded strings proves both row contents and saved `is_filtered_out` flags are unchanged.

  Create `test/helpers/route_exclusion_fixture.dart` with a reusable, fully persisted fixture. `seedCompletedTwoMinuteWalk(WalkRepository)` starts at `DateTime.utc(2026, 8, 21)`, inserts fixes every 20 seconds for 120 seconds, calls `SessionPipeline.process`, finalizes with those exact filtered samples, windows, and metrics, applies user label `ActivityLabel.vehicle`, note `차량`, and confirmed true to the second minute, then reloads and returns this record:

  ```dart
  typedef CompletedRouteFixture = ({
    WalkSession session,
    List<LocationSample> samples,
    List<MinuteWindow> windows,
    List<ActivitySegment> segments,
  });

  Future<String> snapshotRouteEditTables(String path) async {
    ensureSqfliteFfi();
    final db = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    try {
      final snapshot = <String, List<Map<String, Object?>>>{};
      for (final entry in const <String, String>{
        'route_exclusions': 'id ASC',
        'minute_windows': 'id ASC',
        'sessions': 'id ASC',
        'location_samples': 'id ASC',
      }.entries) {
        snapshot[entry.key] = await db.query(entry.key, orderBy: entry.value);
      }
      return jsonEncode(snapshot);
    } finally {
      await db.close();
    }
  }
  ```

  `seedCompletedVehicleWalk` is an alias that returns `seedCompletedTwoMinuteWalk(repo)`. `createV3Fixture` creates the schema copied verbatim from the existing realistic v2 migration test plus the v3 history index, then inserts one completed session, the requested filtered sample flags, one minute row, and one place row before closing the DB. These helpers contain no production shortcuts and all later data and widget tests import this file.

- [ ] **Step 2: Run focused tests to verify RED**

  Run: `flutter test --no-pub --concurrency=1 test/data/app_database_migration_test.dart test/data/walk_repository_test.dart`

  Expected: FAIL because schema v4, route exclusion mapping, repository commands, and DB-level rollback behavior do not exist.

- [ ] **Step 3: Implement schema v4 and one-transaction write commands**

  In `lib/data/app_database.dart`, set `schemaVersion = 4`, add this exact schema after `location_samples`, and add the nullable column and index to fresh installs.

  ```sql
  CREATE TABLE route_exclusions (
    id TEXT PRIMARY KEY NOT NULL,
    session_id TEXT NOT NULL,
    start_at TEXT NOT NULL,
    end_at TEXT NOT NULL,
    reason TEXT NOT NULL,
    created_at TEXT NOT NULL,
    FOREIGN KEY(session_id) REFERENCES sessions(id) ON DELETE CASCADE
  );
  CREATE INDEX idx_route_exclusions_session_range
  ON route_exclusions(session_id, start_at, end_at);
  ```

  Add this upgrade block after the v3 block, in this order.

  ```dart
  if (oldVersion < 4) {
    await db.execute(routeExclusionsTableSql);
    await db.execute(
      'CREATE INDEX idx_route_exclusions_session_range '
      'ON route_exclusions(session_id, start_at, end_at)',
    );
    await db.execute(
      'ALTER TABLE minute_windows ADD COLUMN user_exclusion_id TEXT '
      'REFERENCES route_exclusions(id) ON DELETE SET NULL',
    );
    await db.execute(
      'CREATE INDEX idx_windows_user_exclusion ON minute_windows(user_exclusion_id)',
    );
  }
  ```

  Do not alter `location_samples`. Update `_windowToRow` and `_windowFromRow` with `user_exclusion_id`. Add row mapping that always writes UTC.

  ```dart
  Map<String, Object?> _exclusionToRow(RouteExclusion item) => {
    'id': item.id,
    'session_id': item.sessionId,
    'start_at': item.startAt.toUtc().toIso8601String(),
    'end_at': item.endAt.toUtc().toIso8601String(),
    'reason': item.reason.name,
    'created_at': item.createdAt.toUtc().toIso8601String(),
  };
  ```

  Refactor private reads to accept `DatabaseExecutor`, so both commands read session, samples, windows, places, and exclusions through the transaction's `txn`. Implement one shared `_rewriteCompletedRoute` that invokes Task 1's recalculation and checks exact row counts.

  ```dart
  Future<RouteExclusion> excludeRouteSegment({
    required String sessionId,
    required ActivitySegment segment,
    RouteExclusionReason reason = RouteExclusionReason.vehicle,
    DateTime? createdAt,
  }) {
    return _db.transaction((txn) async {
      final snapshot = await _loadRouteEditSnapshot(txn, sessionId);
      final candidate = RouteExclusion(
        id: _uuid.v4(),
        sessionId: sessionId,
        startAt: segment.start,
        endAt: segment.endExclusive,
        reason: reason,
        createdAt: createdAt ?? DateTime.now(),
      ).clampedTo(snapshot.session);
      final storedWindowKeys = snapshot.windows
          .map((window) => window.windowStart.toUtc())
          .toSet();
      final selectedWindowKeys = segment.windows
          .map((window) => window.windowStart.toUtc())
          .toSet();
      if (selectedWindowKeys.isEmpty ||
          selectedWindowKeys.length != segment.windows.length ||
          !storedWindowKeys.containsAll(selectedWindowKeys)) {
        throw StateError('제외할 구간을 찾을 수 없습니다');
      }
      if (snapshot.exclusions.any(
        (existing) => existing.overlaps(candidate.startAt, candidate.endAt),
      )) {
        throw StateError('이미 제외한 범위와 겹칩니다');
      }
      final next = [...snapshot.exclusions, candidate]
        ..sort((a, b) => a.startAt.compareTo(b.startAt));
      final result = _pipeline.recalculateCompleted(
        session: snapshot.session,
        storedSamples: snapshot.samples,
        exclusions: next,
        previousWindows: snapshot.windows,
      );
      await txn.insert('route_exclusions', _exclusionToRow(candidate));
      await _replaceWindowsIn(txn, sessionId, result.windows);
      await _updateRollupIn(txn, snapshot.session, result.metrics);
      return candidate;
    });
  }
  ```

  `restoreRouteExclusion` loads the same snapshot, requires an exclusion with matching `sessionId` and `exclusionId`, recalculates with that one item removed, replaces windows, updates the rollup, verifies the delete count is one, and deletes the exclusion last. `_replaceWindowsIn` preserves metadata from Task 1 and validates existing `place_id` values before insert. `_updateRollupIn` updates only the seven derived columns and requires one affected session row.

- [ ] **Step 4: Run focused tests to verify GREEN**

  Run: `dart format lib/data/app_database.dart lib/data/walk_repository.dart test/data/app_database_migration_test.dart test/data/walk_repository_test.dart test/helpers/route_exclusion_fixture.dart && flutter test --no-pub --concurrency=1 test/data/app_database_migration_test.dart test/data/walk_repository_test.dart`

  Expected: all migration, validation, metadata, source-row preservation, and rollback tests PASS; `PRAGMA quick_check(1)` and `PRAGMA foreign_key_check` return clean results for fresh and upgraded DBs.

- [ ] **Step 5: Commit**

  ```bash
  git add lib/data/app_database.dart lib/data/walk_repository.dart test/data/app_database_migration_test.dart test/data/walk_repository_test.dart test/helpers/route_exclusion_fixture.dart
  git commit -m "feat: persist route exclusions atomically"
  ```

### Task 3: 전체 백업 v1 및 v2 호환성과 NDJSON v2

**Files:**
- Modify: `lib/domain/services/app_backup.dart`
- Modify: `lib/domain/services/session_export.dart`
- Modify: `lib/data/walk_repository.dart`
- Modify: `test/domain/app_backup_test.dart`
- Modify: `test/domain/walk_stats_export_test.dart`
- Modify: `test/data/walk_backup_test.dart`

**Interfaces:**
- Consumes: Task 1의 `RouteExclusion`, `MinuteWindow.userExclusionId`, Task 2의 DB v4와 `WalkRepository.getRouteExclusions`.
- Produces: `appBackupSchemaVersion = 2`, `AppBackupArchive.backupSchemaVersion`, v1 정규화 테이블, v2 `route_exclusions` 검증과 import, `SessionExport.toNdjson(..., required List<RouteExclusion> exclusions)`의 schema v2 출력.

- [ ] **Step 1: Write failing codec, round-trip, and export tests**

  In `test/domain/app_backup_test.dart`, add explicit v1 normalization and v2 required-table tests.

  ```dart
  test('v1 archive is retained and normalized without route exclusions', () {
    final raw = jsonEncode({
      'export_kind': 'sanbo_backup',
      'backup_schema_version': 1,
      'database_schema_version': 3,
      'exported_at': DateTime.utc(2026, 8, 21).toIso8601String(),
      'tables': {
        'sessions': <Object?>[],
        'location_samples': <Object?>[],
        'minute_windows': <Object?>[],
        'places': <Object?>[],
      },
    });
    final archive = AppBackupCodec.decode(raw);
    expect(archive.backupSchemaVersion, 1);
    expect(archive.table('route_exclusions'), isEmpty);
  });

  test('v2 requires route exclusions and minute exclusion keys', () {
    final raw = AppBackupCodec.encode(
      databaseSchemaVersion: 4,
      tables: const {
        'sessions': [],
        'location_samples': [],
        'minute_windows': [],
        'places': [],
        'route_exclusions': [],
      },
      exportedAt: DateTime.utc(2026, 8, 21),
    );
    final archive = AppBackupCodec.decode(raw);
    expect(archive.backupSchemaVersion, 2);
    expect(archive.tables.keys, contains('route_exclusions'));
  });
  ```

  In `test/data/walk_backup_test.dart`, seed one excluded completed session and assert full v2 round-trip plus v1 import.

  ```dart
  test('backup v2 round-trips exclusions and v1 imports as unexcluded', () async {
    final source = await openTestRepository();
    final target = await openTestRepository();
    addTearDown(source.close);
    addTearDown(target.close);
    final fixture = await seedCompletedTwoMinuteWalk(source);
    final exclusion = await source.excludeRouteSegment(
      sessionId: fixture.session.id,
      segment: fixture.segments.last,
      createdAt: DateTime.utc(2026, 8, 21, 1),
    );

    final archive = AppBackupCodec.decode(await source.createBackupJson());
    expect(archive.backupSchemaVersion, 2);
    expect(archive.table('route_exclusions').single['id'], exclusion.id);
    await target.importBackup(archive);
    expect((await target.getRouteExclusions(fixture.session.id)).single.id, exclusion.id);
    expect(
      (await target.getWindows(fixture.session.id)).any(
        (window) => window.userExclusionId == exclusion.id,
      ),
      isTrue,
    );

    final v1 = downgradeFixtureToBackupV1(await source.createBackupJson());
    final v1Target = await openTestRepository();
    addTearDown(v1Target.close);
    await v1Target.importBackupJson(v1);
    expect(await v1Target.getRouteExclusions(fixture.session.id), isEmpty);
    expect(
      (await v1Target.getWindows(fixture.session.id)).every(
        (window) => window.userExclusionId == null,
      ),
      isTrue,
    );
  });
  ```

  Add corrupt v2 fixtures that reference another session, place an excluded window outside its exclusion, overlap ranges, omit `user_exclusion_id`, or set a future version. Each must throw `FormatException` and leave all target tables empty.

  Update `test/domain/walk_stats_export_test.dart` with the NDJSON contract.

  ```dart
  final ndjson = const SessionExport().toNdjson(
    session: session,
    windows: [windowWithUserExclusionId('vehicle-1')],
    samples: samples,
    exclusions: [vehicleExclusion('vehicle-1', session.id)],
  );
  final lines = ndjson.trim().split('\n').map(jsonDecode).cast<Map<String, dynamic>>().toList();
  expect(lines.first['schema_version'], 2);
  expect(lines.where((line) => line['type'] == 'exclusion'), hasLength(1));
  expect(lines.where((line) => line['type'] == 'window').single['user_exclusion_id'], 'vehicle-1');
  expect(lines.where((line) => line['type'] == 'sample').single.containsKey('user_exclusion_id'), isFalse);
  ```

- [ ] **Step 2: Run focused tests to verify RED**

  Run: `flutter test --no-pub --concurrency=1 test/domain/app_backup_test.dart test/data/walk_backup_test.dart test/domain/walk_stats_export_test.dart`

  Expected: FAIL because archives do not retain the backup schema version, v1 and v2 cannot be decoded separately, route exclusions are absent, and NDJSON still emits schema version 1.

- [ ] **Step 3: Implement version-aware codecs and validated import order**

  In `app_backup.dart`, make version 2 current and retain the decoded version.

  ```dart
  const appBackupSchemaVersion = 2;
  const _v1Tables = {'sessions', 'location_samples', 'minute_windows', 'places'};
  const _v2Tables = {..._v1Tables, 'route_exclusions'};

  class AppBackupArchive {
    const AppBackupArchive({
      required this.backupSchemaVersion,
      required this.databaseSchemaVersion,
      required this.exportedAt,
      required this.tables,
    });
    final int backupSchemaVersion;
    final int databaseSchemaVersion;
    final DateTime exportedAt;
    final Map<String, List<Map<String, Object?>>> tables;
    List<Map<String, Object?>> table(String name) => tables[name] ?? const [];
  }
  ```

  `decode` accepts only 1 or 2, selects `_v1Tables` or `_v2Tables`, and for v1 adds an empty `route_exclusions` table and adds `user_exclusion_id: null` to every copied minute row. For v2 it requires every minute row to contain `user_exclusion_id` whose value is null or String.

  In `WalkRepository.createBackupJson`, query completed sessions, then `route_exclusions`, samples, places, and windows. Include only exclusions for those completed session IDs and verify every non-null window exclusion references an exported exclusion in the same session.

  In `importBackup`, validate all route exclusion rows before writes. Normalize times to UTC, require completed owning sessions, enforce `start < end`, session containment, no overlap, known `reason`, and same-session window references. Insert new rows in this exact transaction order:

  ```dart
  await _insertSessions(txn, validated.sessions);
  await _insertRouteExclusions(txn, validated.exclusions);
  await _insertLocationSamples(txn, validated.samples);
  final placeIdMap = await _insertOrReusePlaces(txn, validated.places);
  await _insertMinuteWindows(txn, validated.windows, placeIdMap);
  ```

  Rows for an already-existing session are omitted from all five insert sets. Preserve `location_samples` keys exactly as v1 and reject the entire transaction on any invalid exclusion reference.

  Update `SessionExport` signatures and output.

  ```dart
  String toNdjson({
    required WalkSession session,
    required List<MinuteWindow> windows,
    required List<LocationSample> samples,
    required List<RouteExclusion> exclusions,
  }) {
    final buffer = StringBuffer()
      ..writeln(jsonEncode({
        'type': 'session',
        'schema_version': 2,
        'session': toJsonDocument(
          session: session,
          windows: windows,
          exclusions: exclusions,
        )['session'],
        'window_count': windows.length,
        'sample_count': samples.length,
        'exclusion_count': exclusions.length,
      }));
    for (final exclusion in exclusions) {
      buffer.writeln(jsonEncode({'type': 'exclusion', ..._exclusionJson(exclusion)}));
    }
    for (final sample in samples) {
      buffer.writeln(jsonEncode({'type': 'sample', ..._sampleJson(sample)}));
    }
    for (final window in windows) {
      buffer.writeln(jsonEncode({'type': 'window', ..._windowJson(window)}));
    }
    return buffer.toString();
  }
  ```

  `_windowJson` includes `user_exclusion_id`; `_exclusionJson` emits id, session_id, UTC start_at, UTC end_at, reason, UTC created_at. `_sampleJson` remains unchanged.

- [ ] **Step 4: Run focused tests to verify GREEN**

  Run: `dart format lib/domain/services/app_backup.dart lib/domain/services/session_export.dart lib/data/walk_repository.dart test/domain/app_backup_test.dart test/domain/walk_stats_export_test.dart test/data/walk_backup_test.dart && flutter test --no-pub --concurrency=1 test/domain/app_backup_test.dart test/data/walk_backup_test.dart test/domain/walk_stats_export_test.dart`

  Expected: v1 normalization, v2 round-trip, duplicate-session skip, corrupt-reference rollback, future-version rejection, and NDJSON v2 tests PASS.

- [ ] **Step 5: Commit**

  ```bash
  git add lib/domain/services/app_backup.dart lib/domain/services/session_export.dart lib/data/walk_repository.dart test/domain/app_backup_test.dart test/domain/walk_stats_export_test.dart test/data/walk_backup_test.dart
  git commit -m "feat: preserve route exclusions in exports"
  ```

### Task 4: 상세 화면 제외 및 복원과 분절 지도 및 재생

**Files:**
- Modify: `lib/domain/services/route_playback.dart`
- Modify: `lib/shared/widgets/route_map.dart`
- Modify: `lib/features/session_detail/session_detail_screen.dart`
- Modify: `lib/features/session_detail/timeline_copy.dart`
- Modify: `test/domain/route_playback_test.dart`
- Modify: `test/widget/route_map_test.dart`
- Modify: `test/features/route_playback_flow_test.dart`
- Modify: `test/features/ux_history_detail_widget_test.dart`
- Modify: `test/features/ux_history_detail_structure_test.dart`

**Interfaces:**
- Consumes: Task 1의 `RoutePartitioner`, `RouteFragment`, `ActivitySegment.userExclusionId`; Task 2의 `getRouteExclusions`, `excludeRouteSegment`, `restoreRouteExclusion`; Task 3의 `SessionExport.toNdjson(... exclusions:)`; 기존 `historyTickProvider`와 `_detailCommandBusyProvider`.
- Produces: `SessionDetailData.exclusions`, `SessionDetailData.route`, `RoutePlayback.flatten(RoutePartitionResult) -> List<RoutePlaybackPoint>`, `RoutePlaybackCursor`, `RouteMap.fragments`, 포함 segment의 `산책에서 제외`, 제외 segment의 `제외 취소` 동작.

- [ ] **Step 1: Write failing route and detail widget tests**

  Replace the single-line map assertion in `test/widget/route_map_test.dart` with a fragment assertion.

  ```dart
  testWidgets('RouteMap draws each route fragment as a separate polyline', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RouteMap(
            offlinePreview: true,
            fragments: [
              [(lat: 37.5665, lon: 126.9780), (lat: 37.5670, lon: 126.9785)],
              [(lat: 37.5700, lon: 126.9810), (lat: 37.5705, lon: 126.9815)],
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    final layer = tester.widget<PolylineLayer>(find.byType(PolylineLayer));
    expect(layer.polylines.where((line) => line.strokeWidth == 3.5), hasLength(2));
    expect(layer.polylines.any((line) => line.points.length == 4), isFalse);
  });
  ```

  Add to `test/domain/route_playback_test.dart`:

  ```dart
  test('flatten keeps fragment boundaries during playback', () {
    final points = RoutePlayback.flatten(RoutePartitionResult(
      includedSamples: [a, b, c, d],
      segments: [segment(a, b), segment(c, d)],
      fragments: [RouteFragment([a, b]), RouteFragment([c, d])],
    ));
    expect(points.map((point) => point.fragmentIndex), [0, 0, 1, 1]);
    expect(points[2].startsFragment, isTrue);
  });
  ```

  Add widget flows to `test/features/ux_history_detail_widget_test.dart` using a real test repository and ProviderScope.

  ```dart
  testWidgets('vehicle segment offers exclusion and excluded segment offers restore', (tester) async {
    final repo = await openTestRepository();
    addTearDown(repo.close);
    final fixture = await seedCompletedVehicleWalk(repo);
    await tester.pumpWidget(detailApp(repo, fixture.session.id));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('구간 편집').last);
    await tester.pumpAndSettle();
    expect(find.text('산책에서 제외'), findsOneWidget);
    expect(find.text('차량 이동 구간을 산책에서 제외합니다.'), findsOneWidget);
    await tester.tap(find.text('산책에서 제외'));
    await tester.pumpAndSettle();
    expect(find.textContaining('기록 전체 통계를 다시 계산'), findsOneWidget);
    expect(await repo.getRouteExclusions(fixture.session.id), isEmpty);
    await tester.tap(find.widgetWithText(FilledButton, '차량 이동 구간 제외'));
    await tester.pumpAndSettle();

    expect(find.text('산책에서 제외됨'), findsWidgets);
    await tester.tap(find.byTooltip('구간 편집').last);
    await tester.pumpAndSettle();
    expect(find.text('제외 취소'), findsOneWidget);
  });
  ```

  Add failure and duplicate-tap cases that inject a repository throwing from `excludeRouteSegment`, then assert old metric text and map remain and the retry SnackBar is visible. Add a `textScaleFactor: 2.0`, 320dp width case and semantics assertions containing range, `산책에서 제외됨`, and `제외 취소 가능`.

- [ ] **Step 2: Run focused tests to verify RED**

  Run: `flutter test --no-pub --concurrency=1 test/domain/route_playback_test.dart test/widget/route_map_test.dart test/features/route_playback_flow_test.dart test/features/ux_history_detail_widget_test.dart test/features/ux_history_detail_structure_test.dart`

  Expected: FAIL because `RouteMap.fragments`, fragment-aware playback, exclusion data loading, and detail actions are absent.

- [ ] **Step 3: Route all detail presentation through RoutePartitioner and add commands**

  Extend the detail provider to load exclusions in the same `Future.wait`, then partition once.

  ```dart
  final loaded = await Future.wait<Object>([
    repo.getSamples(id),
    repo.getWindows(id),
    repo.getRouteExclusions(id),
  ]);
  final samples = loaded[0] as List<LocationSample>;
  final windows = loaded[1] as List<MinuteWindow>;
  final exclusions = loaded[2] as List<RouteExclusion>;
  final route = RoutePartitioner.partition(samples: samples, exclusions: exclusions);
  return SessionDetailData(
    session: session,
    samples: samples,
    windows: windows,
    exclusions: exclusions,
    route: route,
    segments: SegmentMerger().merge(windows),
  );
  ```

  Replace `RouteMap.points` with `List<List<({double lat, double lon})>> fragments`. Fit and semantics use the flattened coordinates, but base, progress, and highlight polylines remain separate by fragment. A progress value is a `RoutePlaybackCursor(fragmentIndex, pointIndex)` instead of a global point count.

  ```dart
  for (final fragment in latLngFragments)
    if (fragment.length >= 2)
      Polyline(
        points: fragment,
        color: progress == null ? theme.colorScheme.primary : theme.colorScheme.outlineVariant,
        strokeWidth: 3.5,
      ),
  ```

  Add a flattened playback value carrying its boundary.

  ```dart
  class RoutePlaybackPoint {
    const RoutePlaybackPoint({
      required this.sample,
      required this.fragmentIndex,
      required this.pointIndex,
    });
    final LocationSample sample;
    final int fragmentIndex;
    final int pointIndex;
    bool get startsFragment => pointIndex == 0;
  }

  class RoutePlaybackCursor {
    const RoutePlaybackCursor({required this.fragmentIndex, required this.pointIndex});
    final int fragmentIndex;
    final int pointIndex;
  }
  ```

  The screen caches `data.route.fragments`, passes fragment coordinates directly to `RouteMap`, and derives current and highlight paths by selecting fragments without inventing connections. On a successful edit, call `_resetRouteInteraction()` before incrementing `historyTickProvider`:

  ```dart
  void _resetRouteInteraction() {
    _playbackTimer?.cancel();
    setState(() {
      _playbackTimer = null;
      _playbackIndex = -1;
      _isPlaying = false;
      _selectedSegmentStart = null;
      _playbackSource = null;
      _playbackCache = const [];
      _pointCache = const [];
    });
  }
  ```

  Add `_SegmentAction.exclude` and `_SegmentAction.restore`. Put exclusion first for `ActivityLabel.vehicle`; include it after activity editing for other included segments. An excluded segment never offers activity or place edits.

  ```dart
  final excluded = segment.userExclusionId != null;
  if (excluded)
    ListTile(
      leading: const Icon(Icons.undo_rounded),
      title: const Text('제외 취소'),
      subtitle: const Text('이 구간을 산책 경로와 통계에 다시 포함합니다.'),
      onTap: () => Navigator.pop(ctx, _SegmentAction.restore),
    )
  else
    ListTile(
      leading: const Icon(Icons.directions_car_outlined),
      title: const Text('산책에서 제외'),
      subtitle: Text(
        segment.label == ActivityLabel.vehicle
            ? '차량 이동 구간을 산책에서 제외합니다.'
            : '잘못 포함된 이동을 산책 경로와 통계에서 제외합니다.',
      ),
      onTap: () => Navigator.pop(ctx, _SegmentAction.exclude),
    );
  ```

  `_confirmExclude` shows range and current distance, puts `취소` first with `autofocus: true`, and names the destructive action `차량 이동 구간 제외`. After confirmation, set `_detailCommandBusyProvider` before the repository call. Increment `historyTickProvider` only after success. `_restoreExclusion` follows the same busy and failure behavior and calls `restoreRouteExclusion` with `segment.userExclusionId!`.

  In `_SegmentRow`, derive `excluded`, lower opacity to 0.52, render the `산책에서 제외됨` pill before the inferred label, and set semantics to `'$range, 산책에서 제외됨, 제외 취소 가능'`. Update `timelineSegmentSubtitle` to return `통계와 경로에서 제외된 구간` for excluded segments.

  Finally pass `data.exclusions` to `SessionExport.toNdjson`; raw samples remain present for reversibility.

- [ ] **Step 4: Run focused tests to verify GREEN**

  Run: `dart format lib/domain/services/route_playback.dart lib/shared/widgets/route_map.dart lib/features/session_detail/session_detail_screen.dart lib/features/session_detail/timeline_copy.dart test/domain/route_playback_test.dart test/widget/route_map_test.dart test/features/route_playback_flow_test.dart test/features/ux_history_detail_widget_test.dart test/features/ux_history_detail_structure_test.dart && flutter test --no-pub --concurrency=1 test/domain/route_playback_test.dart test/widget/route_map_test.dart test/features/route_playback_flow_test.dart test/features/ux_history_detail_widget_test.dart test/features/ux_history_detail_structure_test.dart`

  Expected: separate polyline, fragment replay order, no-route state, confirmation-before-write, busy lock, rollback presentation, refresh, restore, narrow layout, and semantics tests PASS.

- [ ] **Step 5: Commit**

  ```bash
  git add lib/domain/services/route_playback.dart lib/shared/widgets/route_map.dart lib/features/session_detail/session_detail_screen.dart lib/features/session_detail/timeline_copy.dart test/domain/route_playback_test.dart test/widget/route_map_test.dart test/features/route_playback_flow_test.dart test/features/ux_history_detail_widget_test.dart test/features/ux_history_detail_structure_test.dart
  git commit -m "feat: edit excluded route segments"
  ```

### Task 5: SessionGuard 고속 상태 머신과 오래된 수신 방어

**Files:**
- Modify: `lib/domain/services/session_guard.dart`
- Modify: `test/domain/session_guard_test.dart`

**Interfaces:**
- Consumes: 기존 `SessionGuardPolicy`, `SessionGuard.evaluate`, `LocationSample`, `trustedLocationGap`, `haversineMeters`.
- Produces: `SessionGuardEvent.highSpeedWarning`, `SessionGuardObservation`, `SessionGuard.observe(LocationSample, {required DateTime observedAt}) -> SessionGuardObservation`, `SessionGuard.rebuildHighSpeedState({required Iterable<LocationSample> samples, required DateTime observedAt})`, `SessionGuard.dismissHighSpeedWarning()`.

- [ ] **Step 1: Write failing threshold, latch, freshness, and priority tests**

  Add a helper that moves east at a coordinate-derived speed rather than trusting `speedMps`.

  ```dart
  LocationSample movingFix(DateTime at, double meters, {double accuracy = 5, double? providerSpeed}) {
    return LocationSample(
      timestamp: at,
      latitude: 37.5665,
      longitude: 126.9780 + meters / (111320 * 0.793),
      accuracyM: accuracy,
      speedMps: providerSpeed,
    );
  }
  ```

  Add these focused tests to `test/domain/session_guard_test.dart`.

  ```dart
  test('warns once at sixty accumulated high-speed seconds in a two-minute window', () {
    final guard = SessionGuard();
    guard.observe(movingFix(start, 0), observedAt: start);
    for (var second = 10; second <= 60; second += 10) {
      final now = start.add(Duration(seconds: second));
      guard.observe(movingFix(now, second * 8.0), observedAt: now);
    }
    expect(guard.evaluate(startedAt: start, now: start.add(const Duration(seconds: 59))).event, SessionGuardEvent.none);
    expect(guard.evaluate(startedAt: start, now: start.add(const Duration(seconds: 60))).event, SessionGuardEvent.highSpeedWarning);
    expect(guard.evaluate(startedAt: start, now: start.add(const Duration(seconds: 70))).event, SessionGuardEvent.none);
  });

  test('uses overlap with observedAt window and rejects stale bundled fixes', () {
    final guard = SessionGuard();
    final received = start.add(const Duration(minutes: 10));
    for (var second = 0; second <= 90; second += 10) {
      guard.observe(
        movingFix(start.add(Duration(seconds: second)), second * 10),
        observedAt: received.add(Duration(milliseconds: second)),
      );
    }
    expect(guard.evaluate(startedAt: start, now: received).event, SessionGuardEvent.none);
  });

  test('provider speed cannot create a high-speed warning', () {
    final guard = SessionGuard();
    for (var second = 0; second <= 70; second += 10) {
      final now = start.add(Duration(seconds: second));
      guard.observe(movingFix(now, 0, providerSpeed: 40), observedAt: now);
    }
    expect(guard.evaluate(startedAt: start, now: start.add(const Duration(seconds: 70))).event, SessionGuardEvent.none);
  });

  test('thirty continuous low-speed seconds rearms but twenty-nine do not', () {
    final guard = warnedGuard(start);
    guard.dismissHighSpeedWarning();
    guard.observe(movingFix(start.add(const Duration(seconds: 70)), 560), observedAt: start.add(const Duration(seconds: 70)));
    guard.observe(movingFix(start.add(const Duration(seconds: 99)), 589), observedAt: start.add(const Duration(seconds: 99)));
    expect(guard.highSpeedArmed, isFalse);
    guard.observe(movingFix(start.add(const Duration(seconds: 100)), 590), observedAt: start.add(const Duration(seconds: 100)));
    expect(guard.highSpeedArmed, isTrue);
  });
  ```

  Add cases for 7.99m/s versus exactly 8.0m/s, split accumulation, partial overlap at the 120-second boundary, `accuracyM > 80`, filtered samples, out-of-order timestamp, zero interval, `trustedLocationGap + 1ms`, future by more than 5 seconds, observedAt regression, medium-speed reset of recovery, GPS gap reset of recovery, new-session reset, and rebuild using only fresh recent samples.

  Lock priority with a custom zero-duration policy:

  ```dart
  expect(
    guard.evaluate(startedAt: start, now: start).event,
    SessionGuardEvent.durationLimit,
  );
  ```

  Follow it with another evaluation after disabling the higher condition through separate policy instances to prove the exact order `durationLimit`, `stationaryLimit`, `durationWarning`, `stationaryWarning`, `highSpeedWarning` and prove a deferred high-speed pending event remains available.

- [ ] **Step 2: Run the guard tests to verify RED**

  Run: `flutter test --no-pub --concurrency=1 test/domain/session_guard_test.dart`

  Expected: FAIL because high-speed policy values, event, receipt validation, speed spans, latch recovery, rebuild, and priority assertions are missing.

- [ ] **Step 3: Implement the receipt-time deque and independent latch**

  Add these defaults to `SessionGuardPolicy`.

  ```dart
  this.highSpeedThresholdMps = 8.0,
  this.highSpeedWindow = const Duration(seconds: 120),
  this.highSpeedWarningAfter = const Duration(seconds: 60),
  this.lowSpeedRecoveryMps = 4.0,
  this.lowSpeedRecoveryAfter = const Duration(seconds: 30),
  this.highSpeedMaxAccuracyM = 80,
  this.maxSampleAge = const Duration(seconds: 30),
  this.maxSampleFutureSkew = const Duration(seconds: 5),
  ```

  Add `highSpeedWarning` after existing enum values and define the observation result.

  ```dart
  class SessionGuardObservation {
    const SessionGuardObservation({
      this.acceptedForHighSpeed = false,
      this.clearedStationaryWarning = false,
    });
    final bool acceptedForHighSpeed;
    final bool clearedStationaryWarning;
  }

  class _TrustedSpeedSpan {
    const _TrustedSpeedSpan({
      required this.startAt,
      required this.endAt,
      required this.speedMps,
    });
    final DateTime startAt;
    final DateTime endAt;
    final double speedMps;
  }
  ```

  Add `_speedSpans = ListQueue<_TrustedSpeedSpan>()`, `_lastHighSpeedSample`, `_lastObservedAt`, `_lowSpeedSince`, `_highSpeedWarningIssued`, and `_highSpeedPending`. Import `dart:collection`. `reset` clears every field, including old stationary and duration latches.

  Before the existing stationary logic, validate high-speed receipt freshness and append only coordinate-derived trusted spans.

  ```dart
  bool _freshAtReceipt(LocationSample sample, DateTime observedAt) {
    final age = observedAt.toUtc().difference(sample.timestamp.toUtc());
    return age <= policy.maxSampleAge && age >= -policy.maxSampleFutureSkew;
  }

  void _observeHighSpeed(LocationSample sample, DateTime observedAt) {
    final previous = _lastHighSpeedSample;
    _lastHighSpeedSample = sample;
    if (previous == null) return;
    final dt = sample.timestamp.toUtc().difference(previous.timestamp.toUtc());
    if (dt <= Duration.zero || dt > trustedLocationGap) {
      _lowSpeedSince = null;
      return;
    }
    final distance = haversineMeters(
      lat1: previous.latitude,
      lon1: previous.longitude,
      lat2: sample.latitude,
      lon2: sample.longitude,
    );
    final speed = distance / (dt.inMicroseconds / Duration.microsecondsPerSecond);
    if (!speed.isFinite) return;
    _speedSpans.add(_TrustedSpeedSpan(
      startAt: previous.timestamp.toUtc(),
      endAt: sample.timestamp.toUtc(),
      speedMps: speed,
    ));
    _trimHighSpeedWindow(observedAt);
    if (!_highSpeedWarningIssued && _highSpeedDuration(observedAt) >= policy.highSpeedWarningAfter) {
      _highSpeedWarningIssued = true;
      _highSpeedPending = true;
    }
    if (_highSpeedWarningIssued) _updateLowSpeedRecovery(speed, previous.timestamp.toUtc(), sample.timestamp.toUtc());
  }
  ```

  `_highSpeedDuration` intersects every span with `[observedAt - highSpeedWindow, observedAt]` and sums only speeds `>= 8.0`. `_updateLowSpeedRecovery` starts at a trustworthy span start when speed `<= 4.0`, rearms after 30 seconds, and clears the recovery start for speed above 4.0 or any gap. Rearming clears old spans and `_highSpeedPending`; dismissing only clears `_highSpeedPending`, never `_highSpeedWarningIssued`.

  `observe` rejects an `observedAt` older than `_lastObservedAt`, and only feeds high-speed state when both accuracy values are finite, non-negative, at most 150m, the sample is not filtered, coordinates are valid, and `_freshAtReceipt` is true. It still retains current stationary behavior for a fresh usable fix. Return `SessionGuardObservation` instead of bool.

  Update the two existing tests that assign `final cleared = guard.observe(...)` to read `guard.observe(...).clearedStationaryWarning`; all other existing callers that ignore the return value remain unchanged.

  In `evaluate`, keep the four existing branches in their current priority and return high speed last.

  ```dart
  if (_highSpeedPending) {
    _highSpeedPending = false;
    return const SessionGuardDecision(SessionGuardEvent.highSpeedWarning);
  }
  return SessionGuardDecision.none;
  ```

  `rebuildHighSpeedState` calls `reset`, sorts input by timestamp, retains only timestamps within `[observedAt - 120s, observedAt]`, and calls `observe(sample, observedAt: observedAt)` for each. Because freshness is 30 seconds, persisted old vehicle fixes cannot immediately create a warning.

- [ ] **Step 4: Run guard tests to verify GREEN**

  Run: `dart format lib/domain/services/session_guard.dart test/domain/session_guard_test.dart && flutter test --no-pub --concurrency=1 test/domain/session_guard_test.dart`

  Expected: all old stationary and duration tests plus every threshold, receipt, priority, latch, recovery, and rebuild test PASS.

- [ ] **Step 5: Commit**

  ```bash
  git add lib/domain/services/session_guard.dart test/domain/session_guard_test.dart
  git commit -m "feat: detect sustained high-speed movement"
  ```

### Task 6: Typed warning과 컨트롤러 및 홈 UI

**Files:**
- Create: `lib/domain/models/session_warning.dart`
- Modify: `lib/features/home/session_controller.dart`
- Modify: `lib/features/home/home_screen.dart`
- Modify: `test/features/session_guard_flow_test.dart`
- Modify: `test/features/ux_home_recovery_test.dart`
- Modify: `test/features/ux_busy_and_permission_test.dart`
- Modify: `test/widget_test.dart`

**Interfaces:**
- Consumes: Task 5의 `SessionGuardObservation`, `SessionGuardEvent.highSpeedWarning`, `dismissHighSpeedWarning`, `rebuildHighSpeedState`; 기존 `stop`, app foreground state, busy state.
- Produces: `SessionWarningKind`, `SessionWarningAction`, `SessionWarning`, `LiveSessionState.activeWarning`, `SessionController.continueAfterWarning()`, `SessionController.stopFromHighSpeedWarning()`, foreground 고속 경고 UI.

- [ ] **Step 1: Write failing controller and widget tests**

  Replace string-only warning assertions in `test/features/session_guard_flow_test.dart` with typed assertions and add immediate high-speed behavior.

  ```dart
  test('foreground high speed warns once and continue only dismisses its presentation', () async {
    final fixture = await liveControllerFixture(foreground: true);
    final controller = fixture.controller;
    controller.debugIngestSamples(highSpeedTrace(fixture.startedAt, seconds: 60));
    await fixture.pumpMaintenance();

    var live = fixture.container.read(sessionControllerProvider);
    expect(live.activeWarning?.kind, SessionWarningKind.highSpeed);
    expect(live.activeWarning?.actions, {
      SessionWarningAction.stopRecording,
      SessionWarningAction.continueRecording,
    });
    expect(fixture.notifications.shown, isEmpty);

    controller.continueAfterWarning();
    live = fixture.container.read(sessionControllerProvider);
    expect(live.activeWarning, isNull);
    controller.debugIngestSamples(highSpeedTrace(fixture.startedAt.add(const Duration(seconds: 70)), seconds: 30));
    await fixture.pumpMaintenance();
    expect(fixture.container.read(sessionControllerProvider).activeWarning, isNull);
  });

  test('high-speed stop action invokes the user stop flow once', () async {
    final fixture = await warnedControllerFixture();
    final ended = await fixture.controller.stopFromHighSpeedWarning();
    expect(ended, isNotNull);
    expect(await fixture.repo.listCompleted(), hasLength(1));
    expect(fixture.stopInvocations, 1);
  });
  ```

  Add background versus foreground tests. Background must call the high-speed notification once while still retaining `activeWarning`; foreground must not call it. Add recovery tests where recent samples rebuild guard state and stale samples do not. Add concurrent duration limit plus high speed assertion proving duration auto-stop wins.

  Add a `testWidgets` case rendering the real `HomeScreen` from a provider state override.

  ```dart
  expect(find.text('이동 속도가 매우 빨라요. 산책을 마쳤다면 기록을 종료해 주세요.'), findsOneWidget);
  expect(find.widgetWithText(FilledButton, '기록 종료'), findsOneWidget);
  expect(find.widgetWithText(TextButton, '계속 기록'), findsOneWidget);
  expect(tester.getSize(find.widgetWithText(TextButton, '계속 기록')).height, greaterThanOrEqualTo(48));
  ```

  At text scale 2.0 and width 320, assert no overflow exception. Inspect semantics and require a single live-region label containing the title and description, plus button labels exactly `기록 종료` and `계속 기록`.

- [ ] **Step 2: Run focused tests to verify RED**

  Run: `flutter test --no-pub --concurrency=1 test/features/session_guard_flow_test.dart test/features/ux_home_recovery_test.dart test/features/ux_busy_and_permission_test.dart test/widget_test.dart`

  Expected: FAIL because typed warnings, immediate high-speed evaluation, foreground-only presentation rules, and the two-action banner do not exist.

- [ ] **Step 3: Add typed warnings and connect guard decisions without automatic high-speed stop**

  Create `session_warning.dart`.

  ```dart
  enum SessionWarningKind { stationary, duration, highSpeed }
  enum SessionWarningAction { stopRecording, continueRecording }

  class SessionWarning {
    const SessionWarning({
      required this.kind,
      required this.title,
      required this.message,
      required this.actions,
      this.remaining,
    });
    final SessionWarningKind kind;
    final String title;
    final String message;
    final Set<SessionWarningAction> actions;
    final Duration? remaining;
  }
  ```

  Replace `autoStopWarning` and `canContinueAfterWarning` in `LiveSessionState` with `SessionWarning? activeWarning`. Add `clearActiveWarning` to `copyWith`; do not use nullable coalescing to clear this field.

  In `_onSample`, call guard only after incremental `SampleFilter` accepts `marked`, then immediately schedule an evaluation for the current generation.

  ```dart
  final observation = _sessionGuard.observe(marked, observedAt: _clock());
  if (observation.clearedStationaryWarning &&
      state.activeWarning?.kind == SessionWarningKind.stationary) {
    state = state.copyWith(clearActiveWarning: true, statusMessage: '기록 중');
    unawaited(_notifications.cancelWarning());
  }
  unawaited(_evaluateSessionGuard(_clock(), generation: _sessionGeneration));
  ```

  Map existing warnings to typed values. The high-speed branch must contain no `_autoStop` call.

  ```dart
  case SessionGuardEvent.highSpeedWarning:
    const warning = SessionWarning(
      kind: SessionWarningKind.highSpeed,
      title: '산책 기록을 계속할까요?',
      message: '이동 속도가 매우 빨라요. 산책을 마쳤다면 기록을 종료해 주세요.',
      actions: {
        SessionWarningAction.stopRecording,
        SessionWarningAction.continueRecording,
      },
    );
    state = state.copyWith(activeWarning: warning, statusMessage: '기록 종료 확인 중');
    if (!_appForeground) {
      await _notifications.showWarning(title: warning.title, body: warning.message);
    }
    return;
  ```

  `continueAfterWarning` switches on `warning.kind`: stationary calls `continueStationaryTracking`, high speed calls `dismissHighSpeedWarning`, duration has no continue action. It clears the visible warning and calls the existing `cancelWarning` API. `stopFromHighSpeedWarning` requires the current kind to be high speed, cancels the current warning, then calls existing `stop()` once. Task 7 replaces the single warning cancellation with per-kind cancellation.

  During active-session recovery, call `rebuildHighSpeedState(samples: existing, observedAt: _clock())`, then evaluate only after `isTracking` becomes true during resume. Never manufacture a warning from stale samples. Keep a separate `restorePendingNotificationTap` hook for Task 7 to apply after recovery.

  Replace `_AutoStopBanner` with `_SessionWarningBanner`. Use `Semantics(container: true, liveRegion: true, label: '${warning.title}. ${warning.message}', excludeSemantics: true)` and `Wrap` for actions. Render `기록 종료` as a FilledButton only when the action exists and `계속 기록` as a TextButton. Disable both when `busy`.

- [ ] **Step 4: Run focused tests to verify GREEN**

  Run: `dart format lib/domain/models/session_warning.dart lib/features/home/session_controller.dart lib/features/home/home_screen.dart test/features/session_guard_flow_test.dart test/features/ux_home_recovery_test.dart test/features/ux_busy_and_permission_test.dart test/widget_test.dart && flutter test --no-pub --concurrency=1 test/features/session_guard_flow_test.dart test/features/ux_home_recovery_test.dart test/features/ux_busy_and_permission_test.dart test/widget_test.dart`

  Expected: typed stationary and duration regressions, foreground high-speed UI, background notification dispatch, continue latch behavior, stop-once behavior, recovery freshness, accessibility, and constrained layout tests PASS.

- [ ] **Step 5: Commit**

  ```bash
  git add lib/domain/models/session_warning.dart lib/features/home/session_controller.dart lib/features/home/home_screen.dart test/features/session_guard_flow_test.dart test/features/ux_home_recovery_test.dart test/features/ux_busy_and_permission_test.dart test/widget_test.dart
  git commit -m "feat: present typed session warnings"
  ```

### Task 7: Android와 iOS 알림 종류, 비치명 권한, warm 및 cold tap routing

**Files:**
- Modify: `lib/platform/notifications/session_notification_service.dart`
- Modify: `lib/features/home/session_controller.dart`
- Modify: `lib/app/bootstrap.dart`
- Modify: `lib/app.dart`
- Modify: `android/app/src/main/kotlin/com/sanbo/sanbo/MainActivity.kt`
- Create: `android/app/src/test/kotlin/com/sanbo/sanbo/NotificationIntentContractTest.kt`
- Modify: `ios/Runner/AppDelegate.swift`
- Modify: `ios/Runner/SceneDelegate.swift`
- Modify: `ios/RunnerTests/RunnerTests.swift`
- Create: `test/platform/session_notification_service_test.dart`
- Modify: `test/features/session_guard_flow_test.dart`
- Modify: `test/features/ux_busy_and_permission_test.dart`

**Interfaces:**
- Consumes: Task 6의 `SessionWarning`, `SessionWarningKind`, `SessionController` recovery and foreground state; 기존 MethodChannel `sanbo/session_notifications`; `routerProvider`.
- Produces: `NotificationPermissionResult`, `SessionNotificationTap`, `SessionNotificationService.requestPermission()`, `initialize()`, `taps`, `showWarning(SessionWarning)`, `cancel({required SessionWarningKind kind})`, native payload `kind: highSpeed`, Dart `notificationTapped({kind: highSpeed})`, one-item cold-start buffer and home routing.

- [ ] **Step 1: Write failing Dart channel, non-blocking start, and tap tests**

  Create `test/platform/session_notification_service_test.dart` around the real `PlatformSessionNotificationService` and the test binary messenger.

  ```dart
  import 'package:flutter/services.dart';
  import 'package:flutter_test/flutter_test.dart';
  import 'package:sanbo/domain/models/session_warning.dart';
  import 'package:sanbo/platform/notifications/session_notification_service.dart';

  void main() {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('sanbo/session_notifications');

    test('high-speed show and cancel send isolated kind and id', () async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return null;
          });
      addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null));
      final service = PlatformSessionNotificationService();
      await service.initialize();
      await service.showWarning(const SessionWarning(
        kind: SessionWarningKind.highSpeed,
        title: '산책 기록을 계속할까요?',
        message: '이동 속도가 매우 빨라요. 산책을 마쳤다면 기록을 종료해 주세요.',
        actions: {SessionWarningAction.stopRecording, SessionWarningAction.continueRecording},
      ));
      await service.cancel(kind: SessionWarningKind.highSpeed);
      expect(calls[0].arguments, containsPair('kind', 'highSpeed'));
      expect(calls[0].arguments, containsPair('id', 4103));
      expect(calls[1].arguments, containsPair('id', 4103));
    });

    test('notificationTapped is emitted exactly once', () async {
      final service = PlatformSessionNotificationService();
      await service.initialize();
      final received = <SessionNotificationTap>[];
      final subscription = service.taps.listen(received.add);
      addTearDown(subscription.cancel);
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
        channel.name,
        channel.codec.encodeMethodCall(
          const MethodCall('notificationTapped', {'kind': 'highSpeed'}),
        ),
        (_) {},
      );
      await pumpEventQueue();
      expect(received.map((event) => event.kind), [SessionWarningKind.highSpeed]);
    });
  }
  ```

  Add to `test/features/ux_busy_and_permission_test.dart` a notification fake whose permission future never completes.

  ```dart
  test('notification permission never blocks a granted location start', () async {
    final notifications = NeverCompletingPermissionNotifications();
    final fixture = await controllerFixture(notifications: notifications);
    final startFuture = fixture.controller.start();
    await startFuture.timeout(const Duration(seconds: 1));
    expect(fixture.container.read(sessionControllerProvider).isTracking, isTrue);
    expect(notifications.permissionRequests, 1);
  });
  ```

  Add warm and cold tap flow tests to `test/features/session_guard_flow_test.dart`.

  ```dart
  test('warm high-speed tap routes home and keeps the active warning actions', () async {
    final fixture = await warnedControllerFixture(background: true);
    fixture.notifications.emitTap(SessionWarningKind.highSpeed);
    await pumpEventQueue();
    expect(fixture.navigation.location, '/');
    expect(fixture.container.read(sessionControllerProvider).activeWarning?.kind, SessionWarningKind.highSpeed);
  });

  test('cold high-speed tap waits for recovery and ignores ended sessions', () async {
    final fixture = await coldStartFixture(pendingTap: SessionWarningKind.highSpeed);
    await fixture.controller.restoreIfNeeded();
    expect(fixture.navigation.location, '/');
    expect(fixture.container.read(sessionControllerProvider).activeWarning, isNull);
  });
  ```

  In `RunnerTests.swift`, replace the placeholder with pure payload buffer assertions. In the Android JVM test, call a package-visible `notificationKind(intent)` helper and assert `highSpeed` survives an Intent round-trip. These tests avoid launching a device while locking the native payload contract.

- [ ] **Step 2: Run focused tests to verify RED**

  Run: `flutter test --no-pub --concurrency=1 test/platform/session_notification_service_test.dart test/features/session_guard_flow_test.dart test/features/ux_busy_and_permission_test.dart && (cd android && ./gradlew app:testDebugUnitTest) && xcodebuild test -workspace ios/Runner.xcworkspace -scheme Runner -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO`

  Expected: Dart tests FAIL on missing typed channel and tap APIs; native tests FAIL on missing kind parsing and one-item pending-tap storage.

- [ ] **Step 3: Implement typed native notifications and ordered cold-start handling**

  In Dart, use stable IDs without reusing current warning or completion IDs.

  ```dart
  enum NotificationPermissionResult { granted, denied, unsupported, failed }

  class SessionNotificationTap {
    const SessionNotificationTap(this.kind);
    final SessionWarningKind kind;
  }

  abstract class SessionNotificationService {
    Future<void> initialize();
    Future<NotificationPermissionResult> requestPermission();
    Stream<SessionNotificationTap> get taps;
    Future<void> showWarning(SessionWarning warning);
    Future<void> showCompletion({required String title, required String body});
    Future<void> cancel({required SessionWarningKind kind});
  }
  ```

  `PlatformSessionNotificationService` owns one broadcast controller and installs one MethodChannel handler in `initialize`. Map stationary to 4101, duration to 4101, completion to 4102, and high speed to 4103. Send `kind: warning.kind.name`; translate native `highSpeed` only. Catch `MissingPluginException` and `PlatformException` in request, show, and cancel, returning `unsupported` or `failed` and never rethrowing.

  At the beginning of `SessionController.start`, after the busy guard but before awaiting location permission, invoke and intentionally do not await:

  ```dart
  unawaited(_notifications.requestPermission());
  ```

  Add `SessionController.handleNotificationTap(SessionNotificationTap tap)`. It queues at most one high-speed tap while `restoreIfNeeded` is running. After recovery finishes, if a queued tap exists and an active session still exists, set the high-speed `SessionWarning`; if no active session exists, discard the warning request.

  In `bootstrap.dart`, construct one `PlatformSessionNotificationService`, await only `initialize`, and override `sessionNotificationServiceProvider` with that instance before scheduling `restoreIfNeeded`. Do not request permission in bootstrap. In `_SanboAppState.initState`, subscribe to `ref.read(sessionNotificationServiceProvider).taps`; for every tap call `SessionController.handleNotificationTap` and `ref.read(routerProvider).go('/')`. Cancel this subscription in `dispose`. This makes both warm and flushed cold taps use the existing home route without adding a second router.

  In Android `MainActivity`, add `notificationKind = "sanbo_notification_kind"`, retain one `pendingKind`, and handle both the launch Intent and `onNewIntent`.

  ```kotlin
  internal fun notificationKind(intent: Intent?): String? =
      intent?.getStringExtra(notificationKindExtra)?.takeIf { it == "highSpeed" }

  private fun deliverOrQueueTap(intent: Intent?) {
      val kind = notificationKind(intent) ?: return
      val channel = notificationMethodChannel
      if (channel == null) pendingKind = kind
      else channel.invokeMethod("notificationTapped", mapOf("kind" to kind))
      intent?.removeExtra(notificationKindExtra)
  }
  ```

  `showNotification` receives `kind`, writes it into `openAppIntent`, uses request code `id`, and leaves existing notifications untouched. After installing the MethodChannel handler in `configureFlutterEngine`, deliver `pendingKind` once and clear it. The Dart `show` branch validates `kind` and accepts only current supported kinds.

  In iOS, import `UserNotifications`. Add a package-visible `NotificationTapBuffer` with one pending String and `take()` clearing it. `AppDelegate` conforms to `UNUserNotificationCenterDelegate`, requests authorization through MethodChannel `requestPermission`, shows `UNNotificationRequest` with identifier `String(id)` and `userInfo["kind"]`, cancels only the requested identifier, suppresses foreground banners by returning `[]`, and routes tap payloads through the buffer when the Flutter channel is unavailable.

  ```swift
  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let kind = response.notification.request.content.userInfo["kind"] as? String
    deliverOrBuffer(kind: kind)
    completionHandler()
  }
  ```

  Register the MethodChannel in `didInitializeImplicitFlutterEngine`, set the notification center delegate, and flush one pending `highSpeed` tap after the handler is ready. Keep `SceneDelegate` free of a second channel so one native tap cannot emit twice.

- [ ] **Step 4: Run focused tests to verify GREEN**

  Run: `dart format lib/platform/notifications/session_notification_service.dart lib/features/home/session_controller.dart lib/app/bootstrap.dart lib/app.dart test/platform/session_notification_service_test.dart test/features/session_guard_flow_test.dart test/features/ux_busy_and_permission_test.dart && flutter test --no-pub --concurrency=1 test/platform/session_notification_service_test.dart test/features/session_guard_flow_test.dart test/features/ux_busy_and_permission_test.dart && (cd android && ./gradlew app:testDebugUnitTest) && xcodebuild test -workspace ios/Runner.xcworkspace -scheme Runner -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO`

  Expected: typed IDs, non-blocking permission, nonfatal failures, foreground suppression, warm tap, one-shot cold tap, ended-session stale tap, Android Intent, and iOS buffer tests PASS.

- [ ] **Step 5: Commit**

  ```bash
  git add lib/platform/notifications/session_notification_service.dart lib/features/home/session_controller.dart lib/app/bootstrap.dart lib/app.dart android/app/src/main/kotlin/com/sanbo/sanbo/MainActivity.kt android/app/src/test/kotlin/com/sanbo/sanbo/NotificationIntentContractTest.kt ios/Runner/AppDelegate.swift ios/Runner/SceneDelegate.swift ios/RunnerTests/RunnerTests.swift test/platform/session_notification_service_test.dart test/features/session_guard_flow_test.dart test/features/ux_busy_and_permission_test.dart
  git commit -m "feat: route high-speed notifications"
  ```

### Task 8: PRD 및 TRD 동기화와 전체 회귀 및 빌드

**Files:**
- Modify: `docs/PRD.md`
- Modify: `docs/TRD.md`
- Modify: `docs/DEVICE_VALIDATION.md`
- Create: `test/features/high_speed_route_exclusion_docs_test.dart`
- Verify: all files changed in Tasks 1 through 7

**Interfaces:**
- Consumes: Tasks 1 through 7의 최종 public types, DB v4 schema, backup v2, 사용자 문구, native payload contract.
- Produces: PRD 성공 기준, TRD 계산 및 저장 규칙, 실제 기기 점검표, 문서 구조 테스트, 전체 analyzer, test, Android build, iOS build 결과.

- [x] **Step 1: Write the failing documentation contract test**

  Create `test/features/high_speed_route_exclusion_docs_test.dart` so the active product and technical docs cannot silently drift from shipped constants and storage names.

  ```dart
  import 'dart:io';

  import 'package:flutter_test/flutter_test.dart';

  void main() {
    test('PRD and TRD document high-speed warning and reversible exclusion contracts', () {
      final prd = File('docs/PRD.md').readAsStringSync();
      final trd = File('docs/TRD.md').readAsStringSync();
      expect(prd, contains('28.8km/h'));
      expect(prd, contains('60초'));
      expect(prd, contains('기록 종료'));
      expect(prd, contains('계속 기록'));
      expect(prd, contains('산책에서 제외'));
      expect(prd, contains('제외 취소'));
      expect(trd, contains('route_exclusions'));
      expect(trd, contains('user_exclusion_id'));
      expect(trd, contains('RoutePartitioner'));
      expect(trd, contains('backup_schema_version: 2'));
      expect(trd, contains('notificationTapped({kind: highSpeed})'));
    });
  }
  ```

- [x] **Step 2: Run the documentation checks to verify RED**

  Run: `flutter test --no-pub --concurrency=1 test/features/high_speed_route_exclusion_docs_test.dart && python scripts/verify_prd_trd.py`

  Expected: the Dart test FAILS because the current PRD and TRD omit the new terms; the structural verifier remains useful but cannot prove feature coverage yet.

- [x] **Step 3: Update product, technical, and device verification documents with exact shipped contracts**

  Add one PRD functional requirement for sustained high-speed confirmation with these exact values and copy: `28.8km/h`, latest `120초`, accumulated `60초`, recovery `14.4km/h` for `30초`, `기록 종료`, `계속 기록`, and no automatic high-speed stop. Add another requirement for completed-segment `산책에서 제외` and `제외 취소`, stating that maps, session totals, history totals, and daily totals refresh together.

  ```markdown
  ### FR: 고속 이동 종료 확인과 기록 구간 제외

  - 최근 120초 안에서 신뢰 가능한 28.8km/h 이상 이동이 누적 60초가 되면 자동 종료하지 않고 종료 여부를 확인한다.
  - 사용자는 `기록 종료` 또는 `계속 기록`을 선택하며, 14.4km/h 이하 이동이 연속 30초 이어지기 전에는 같은 이동으로 다시 알리지 않는다.
  - 완료 기록의 연속 구간에는 `산책에서 제외`를, 제외된 구간에는 `제외 취소`를 제공한다.
  - 편집 성공 뒤 지도, 세션 통계, 기록 화면 합계와 일별 합계를 함께 새로 읽는다.
  ```

  Add TRD sections with the exact public signatures from Tasks 1, 2, 5, 6, and 7. Include DB v4 SQL, `location_samples.is_filtered_out` preservation, no `location_samples.user_exclusion_id`, UTC half-open intervals, transaction write order, `RoutePartitioner` fragment invariants, backup schema v1 and v2 compatibility, NDJSON v2, warning priority, receipt freshness, and `notificationTapped({kind: highSpeed})` warm and cold flow. Write the literal line `backup_schema_version: 2` in the backup section so the documentation test remains precise.

  ```markdown
  ### 고속 guard와 경로 제외 계약

  `SessionGuard`는 `observedAt` 기준 freshness를 검사하고 `RoutePartitioner`는 저장된 `location_samples.is_filtered_out`, UTC `[startAt, endAt)` 제외, `trustedLocationGap`을 적용한다. `location_samples.user_exclusion_id` 열은 만들지 않는다. 경고 우선순위는 duration limit, stationary limit, duration warning, stationary warning, high-speed warning 순서다.

  DB v4는 `route_exclusions`와 `minute_windows.user_exclusion_id`를 추가한다. 제외, 분 기록 교체, 세션 집계 갱신은 한 트랜잭션에서 실행한다.

  전체 백업 출력은 `backup_schema_version: 2`이며 v1과 v2를 입력으로 지원한다. NDJSON은 schema version 2에서 원시 샘플, 제외 레코드, 분 기록 제외 ID를 보존한다.

  알림 탭은 `notificationTapped({kind: highSpeed})`로 전달하며 warm start는 즉시 홈으로 이동하고 cold start는 세션 복구 뒤 경고를 재구성한다.
  ```

  Add to `docs/DEVICE_VALIDATION.md` an unchecked Android and iOS matrix with these exact rows: foreground warning without system banner, background notification, screen-off notification, warm tap, killed-app cold tap, notification denied, notification API failure, continued background location, route exclusion, all-points exclusion, restore, and app restart persistence. Each row records device and OS, permission state, expected state, observed result, and pass or fail.

  Then run formatting and the doc contract:

  Run: `dart format test/features/high_speed_route_exclusion_docs_test.dart && flutter test --no-pub --concurrency=1 test/features/high_speed_route_exclusion_docs_test.dart && python scripts/verify_prd_trd.py`

  Expected: the documentation contract PASS and `verify_prd_trd.py` exits 0.

- [x] **Step 4: Run the complete automated completion audit**

  Run these commands independently so a failure cannot hide later evidence:

  ```bash
  flutter analyze --no-pub
  flutter test --no-pub --concurrency=1
  flutter build apk --debug
  flutter build ios --debug --no-codesign
  python scripts/verify_prd_trd.py
  (cd android && ./gradlew app:testDebugUnitTest)
  xcodebuild test -workspace ios/Runner.xcworkspace -scheme Runner -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO
  git diff --check
  rg -n "autoStopWarning|canContinueAfterWarning|RouteMap\\(.*points|schema_version.: 1|appBackupSchemaVersion = 1|user_exclusion_id.*location_samples" lib android ios
  git status --short
  ```

  Expected: analyzer reports no issues; all Flutter, Android, and iOS tests PASS; both debug builds succeed; PRD and TRD verification exits 0; `git diff --check` is clean; the legacy API and schema search returns exit code 1 with no matches in active code or tests; status contains only files named in this plan. If no iPhone 16 simulator exists, run `xcrun simctl list devices available`, select one available iOS simulator by its exact name, rerun the same `xcodebuild test`, and record that exact destination in the commit notes.

- [x] **Step 5: Commit**

  ```bash
  git add docs/PRD.md docs/TRD.md docs/DEVICE_VALIDATION.md test/features/high_speed_route_exclusion_docs_test.dart docs/superpowers/plans/2026-08-21-high-speed-guard-and-route-exclusion-plan.md
  git commit -m "docs: specify route exclusion and speed alerts"
  ```

  After the commit, perform the manual device matrix from `docs/DEVICE_VALIDATION.md`. Do not claim Android and iOS notification delivery verified until real-device rows contain device model, OS version, observed result, and pass status.
