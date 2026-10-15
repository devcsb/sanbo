# 산보 측정 표시 일관성 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 복구 거리, 현재 속도 최신성, 재생 시간대, 완료 export와 건강 데이터 안내를 승인된 MR-02~06에 맞춘다.

**Architecture:** 기존 RoutePartitioner와 완료 평균 helper, 세션 IANA 시간대 함수를 재사용한다. 현재 속도의 표시 가능 여부만 순수 함수로 분리하고 controller는 기존 증분 수집과 저장을 유지한다. Health 설정 capability에 사용 가능 여부를 명시한다.

**Tech Stack:** Flutter 3.47.1, Dart/Riverpod, sqflite, 기존 geolocator/health adapters, Flutter unit/widget tests.

**Spec:** [승인된 1차 설계](../specs/2026-10-13-measurement-consistency-and-backup-design.md). 사용자 승인일 2026-10-14. 실행은 현재 세션에서 직접 수행한다.

## Global Constraints

- SQLite v6, 전체 백업 v2, 세션 export v2를 유지하고 과거 기록을 자동 재작성하지 않는다.
- 공통 경로 연결 상한은 60초, 거리 하한은 1.5m를 유지한다.
- GPS 품질 maxAge=30초, maxFutureSkew=5초를 기존 LocationQualityPolicy에서 받아 사용한다.
- 현재 숫자의 smoothing, 위치 간격, 정확도 상한, 정지/5시간 종료, 자동 제외 정책은 이 계획에서 바꾸지 않는다.
- 원본 샘플과 filter flag, 사용자 라벨/메모/장소/제외 복원을 유지한다.
- 정상 callback의 거리 갱신은 O(1), 복구의 경로 재계산은 O(n)으로 유지한다.
- 타임스탬프는 저장/수학에서 UTC, 표시에서 session.timezone을 사용한다.
- 제품 dependency나 서버, 새 원격 진단을 추가하지 않는다.
- Native 실행 방식이 정해져 있다. 재위임하지 않고 최종 여러 파일 변경의 교차 검토는 사용자 PR 검토로 받는다.

## Review Focus

- 마지막 저장 샘플이 filtered인 복구에서 첫 새 샘플을 이전 fragment에 연결하지 않는다. Task 1에 tail-filtered 회귀를 둔다.
- 수신된 좌표를 거절했거나 허용된 미래 5초 샘플을 받은 경우 속도의 최신 여부가 잘못 갱신되지 않는다. Task 2에 경계 테스트를 둔다.
- background에서 시각이 흘렀다가 복귀해도 이전 속도를 현재 측정으로 읽지 않는다. Task 2에 resume 및 Semantics 회귀를 둔다.
- 기기 zone과 산책 zone이 다르거나 DST의 01:30이 두 번 발생해도 재생 시각이 같은 순간을 나타낸다. Task 3에 fold와 UTC fixture를 둔다.
- HealthKit 설정 opener가 없거나 건강 데이터가 0/오류/부분이면 Android 전용 action 또는 fabricated zero를 보여주지 않는다. Task 5에 source/coverage/capability 조합 테스트를 둔다.

## 파일 구조

| 파일 | 책임 |
|---|---|
| `lib/features/home/session_controller.dart` | 복구 경로 경계와 최신 측정 상태를 UI state에 전달 |
| 새 `lib/domain/services/live_speed_availability.dart` | last usable instant, clock, speed evidence로 표시 가능 여부 계산 |
| `lib/features/home/home_screen.dart` | 현재 속도/측정 대기/중단과 유효 위치 상태 표시 |
| `lib/features/session_detail/session_detail_screen.dart` | playback 시각을 세션 zone으로 표시 |
| `lib/domain/services/session_export.dart` | 완료 JSON/NDJSON 평균을 canonical helper에서 계산 |
| `lib/data/activity_data_source.dart` | 기존 settings opener capability의 실제 지원 여부 |
| `lib/features/history/daily_activity_panel.dart` | 건강 데이터 상태별 수치, 재시도/설정 action |

controller/repository 전체 분해는 하지 않는다. 새 순수 함수는 측정 가용성 하나만 담당한다.

### Task 1: 복구와 완료의 경로 경계 통일

**Files**
- Modify: `lib/features/home/session_controller.dart`, `_recomputeLiveMetricsFromBuffer`, `_onSample`, reset paths.
- Test: `test/features/session_flow_test.dart`.
- Read: `lib/domain/pipeline/route_partitioner.dart`, `test/helpers/test_db.dart`.

**Interfaces**
- Consumes: `RoutePartitioner.partition(samples:, exclusions:, sessionStart:, sessionEnd:) -> RoutePartitionResult`.
- Produces: 같은 필터 목록의 복구/완료 `liveDistanceM` 일치, 마지막 fragment 안에서만 재구성한 live speed.
- Adds private `bool _liveRouteInterrupted = false` to keep route continuity distinct from the filter's jump anchor.

- [x] Step 1: 아래 회귀를 기존 session_flow_test에 추가한다. 기존 imports에 SessionPipeline과 RoutePartitioner를 필요할 때만 추가한다.

```dart
test('recovery preserves filtered route boundaries', () async {
  final repo = await openTestRepository();
  addTearDown(repo.close);
  final t = DateTime.utc(2026, 10, 14);
  final session = await repo.startSession(startedAt: t);
  LocationSample p(int seconds, double meters, {bool filtered = false}) =>
      LocationSample(
        timestamp: t.add(Duration(seconds: seconds)),
        latitude: meters / 111194.92664455874,
        longitude: 0,
        accuracyM: filtered ? 200 : 5,
        isFilteredOut: filtered,
      );
  final samples = [p(0, 0), p(10, 10), p(20, 20, filtered: true), p(30, 30)];
  await repo.insertSamples(session.id, samples);
  var now = t.add(const Duration(seconds: 30));
  final container = ProviderContainer(overrides: [
    walkRepositoryProvider.overrideWithValue(repo),
    locationEngineProvider.overrideWithValue(
      SyntheticLocationEngine(permission: LocationPermissionState.granted),
    ),
    sessionClockProvider.overrideWithValue(() => now),
  ]);
  addTearDown(container.dispose);
  final controller = container.read(sessionControllerProvider.notifier);
  await controller.restoreIfNeeded();
  expect(controller.state.liveDistanceM, closeTo(10, 0.01));
  await controller.resumeRecoveredSession();
  now = t.add(const Duration(seconds: 40));
  controller.debugIngestSamples([p(40, 40)]);
  expect(controller.state.liveDistanceM, closeTo(20, 0.01));
  final completed = await controller.stop();
  expect(completed!.totalDistanceM, closeTo(20, 0.01));
});
```

- [x] Step 2: 마지막 샘플이 filtered인 별도 회귀를 추가한다.

```dart
test('recovery does not bridge a filtered tail', () async {
  final repo = await openTestRepository();
  addTearDown(repo.close);
  final t = DateTime.utc(2026, 10, 14);
  final session = await repo.startSession(startedAt: t);
  LocationSample p(int seconds, double meters, {bool filtered = false}) =>
      LocationSample(
        timestamp: t.add(Duration(seconds: seconds)),
        latitude: meters / 111194.92664455874, longitude: 0,
        accuracyM: filtered ? 200 : 5, isFilteredOut: filtered,
      );
  await repo.insertSamples(session.id,
      [p(0, 0), p(10, 10), p(20, 20, filtered: true)]);
  var now = t.add(const Duration(seconds: 20));
  final container = ProviderContainer(overrides: [
    walkRepositoryProvider.overrideWithValue(repo),
    locationEngineProvider.overrideWithValue(
      SyntheticLocationEngine(permission: LocationPermissionState.granted),
    ),
    sessionClockProvider.overrideWithValue(() => now),
  ]);
  addTearDown(container.dispose);
  final controller = container.read(sessionControllerProvider.notifier);
  await controller.restoreIfNeeded();
  await controller.resumeRecoveredSession();
  now = t.add(const Duration(seconds: 30));
  controller.debugIngestSamples([p(30, 30)]);
  expect(controller.state.liveDistanceM, closeTo(10, 0.01));
  now = t.add(const Duration(seconds: 40));
  controller.debugIngestSamples([p(40, 40)]);
  expect(controller.state.liveDistanceM, closeTo(20, 0.01));
  final completed = await controller.stop();
  expect(completed!.totalDistanceM, closeTo(20, 0.01));
});
```

- [x] Step 3: `flutter test --no-pub --concurrency=1 test/features/session_flow_test.dart --plain-name 'recovery preserves filtered route boundaries'`를 실행해 기존30m와 기대10m의 차이로 실패하는지 확인한다. tail test도 단독 실행한다.

- [x] Step 4: 다음 계산을 복구 재계산에 넣고 평탄화된 valid 목록으로 거리/속도를 만드는 두 helper 호출을 교체한다.

```dart
final filtered = _liveFilter.apply(bounded);
final route = RoutePartitioner.partition(samples: filtered, exclusions: const []);
_liveDistanceM = route.segments
    .where((s) => s.distanceM >= minMeaningfulSegmentDistanceM)
    .fold(0.0, (sum, s) => sum + s.distanceM);
_validSampleCount = route.includedSamples.length;
_lastValidSample = route.includedSamples.isEmpty ? null : route.includedSamples.last;
_liveRouteInterrupted = filtered.isNotEmpty && filtered.last.isFilteredOut;
final latestFragment = route.fragments.isEmpty
    ? const <LocationSample>[] : route.fragments.last.samples;
_liveSpeedMps = _liveSpeedFromSamples(latestFragment);
```

filter는 이전 usable anchor를 필요로 하므로 `_lastValidSample`을 곧바로 지우지 않는다.
대신 `_onSample`에서 거리 연결 조건에 `!_liveRouteInterrupted`를 넣고, 거절 시 true,
accepted sample을 새 anchor로 처리한 뒤 false로 만든다. 기존 jump follow-up probe는
원시 rejected sample과 함께 유지한다. 복구한 마지막 raw jump가 filter에서 거절됐다면
`_lastJumpRejectedSample`은 표시된 filtered 복사본이 아니라 원래 bounded sample로
복원해 두 연속 위치로 새 fragment를 확인하는 기존 계약을 유지한다.

```dart
if (prev != null && !startsNewFragment && !_liveRouteInterrupted) {
  // 기존 dt/distance/gap 검사와 O(1) 거리 합계를 실행한다.
}
if (acceptedByIncrementalFilter) {
  _liveRouteInterrupted = false;
} else {
  _liveRouteInterrupted = true;
}
```

- [x] Step 5: start/stop/discard/failure cleanup의 기존 private counter reset에서 새 flag도 false로 초기화한다. 마지막 filtered point 종류별로 jump, stale, soft accuracy, malformed를 기존 fixture에 추가해 새 anchor를 임의로 연결하지 않는지 확인한다. 60초 경계와 60초 초과 공백은 기존 route partition 테스트 계약을 재사용한다.
- [x] Step 6: `flutter test --no-pub --concurrency=1 test/features/session_flow_test.dart test/domain/route_partitioner_test.dart test/domain/session_pipeline_test.dart`를 실행한다. 승인된 수학 하한이 변하지 않았는지 diff로 확인한다.
- [x] Step 7: 두 task 파일만 커밋한다. 메시지는 `fix: 복구 거리에서 필터 경계 연결 차단`.

### Task 2: 현재 속도 최신성 및 Home 안내

**Files**
- Create: `lib/domain/services/live_speed_availability.dart`.
- Modify: `lib/features/home/session_controller.dart`, `lib/features/home/home_screen.dart`.
- Create: `test/domain/live_speed_availability_test.dart`.
- Test: `test/features/session_flow_test.dart`, `test/features/ux_nav_tracking_test.dart`, `test/features/ux_home_recovery_test.dart`.

**Interfaces**
- Produces: `enum LiveSpeedAvailability { waiting, available, stale }`.
- Produces: `liveSpeedAvailability({DateTime? lastUsableFixAt, required DateTime now, required bool hasSpeedEvidence, required Duration maxAge, required Duration maxFutureSkew}) -> LiveSpeedAvailability`.
- LiveSessionState adds `LiveSpeedAvailability speedAvailability = waiting` and nullable `DateTime? lastUsableFixAt`. Existing double `liveSpeedMps` stays for numeric compatibility; UI consumes it only when available.
- Controller adds private `bool _hasLiveSpeedEvidence = false` and `DateTime? _lastUsableFixAt`, reset with the existing metrics. Background callbacks update these private fields even while UI publication is paused. New availability fields are display state, not DB fields.
- `LiveSessionState.copyWith` adds `bool clearLastUsableFixAt = false` so reset can clear a nullable instant rather than retaining it through `??`.

- [x] Step 1: 순수 함수에 아래 경계 테스트를 작성하고 import 미존재로 RED를 확인한다.

```dart
test('availability separates waiting, zero speed and stale data', () {
  final t = DateTime.utc(2026, 10, 14);
  LiveSpeedAvailability at(Duration age, {bool evidence = true}) =>
      liveSpeedAvailability(
        lastUsableFixAt: t, now: t.add(age), hasSpeedEvidence: evidence,
        maxAge: const Duration(seconds: 30),
        maxFutureSkew: const Duration(seconds: 5),
      );
  expect(at(Duration.zero, evidence: false), LiveSpeedAvailability.waiting);
  expect(at(Duration.zero), LiveSpeedAvailability.available);
  expect(at(const Duration(seconds: 30)), LiveSpeedAvailability.available);
  expect(at(const Duration(milliseconds: 30001)), LiveSpeedAvailability.stale);
  expect(at(const Duration(seconds: -5)), LiveSpeedAvailability.available);
  expect(at(const Duration(milliseconds: -5001)), LiveSpeedAvailability.stale);
});
```

null instant도 별도로 waiting인지 검사한다. `hasSpeedEvidence=true`에는 유효한 0m/s도
포함하며 숫자값만으로 available을 추정하지 않는다.

- [x] Step 2: 다음 순수 함수를 구현한다.

```dart
enum LiveSpeedAvailability { waiting, available, stale }

LiveSpeedAvailability liveSpeedAvailability({
  DateTime? lastUsableFixAt,
  required DateTime now,
  required bool hasSpeedEvidence,
  required Duration maxAge,
  required Duration maxFutureSkew,
}) {
  if (lastUsableFixAt == null) return LiveSpeedAvailability.waiting;
  final age = now.toUtc().difference(lastUsableFixAt.toUtc());
  if (age > maxAge || age < -maxFutureSkew) return LiveSpeedAvailability.stale;
  return hasSpeedEvidence
      ? LiveSpeedAvailability.available : LiveSpeedAvailability.waiting;
}
```

- [x] Step 3: 기존 clock override fixture로 last fix=t+8s에 대해 now=t+38s는available,
now=t+38.001s는stale인 controller 회귀를 추가한다. Widget test에서는 DB/start를
`tester.runAsync` 안에서 실행하고, clock을 바꾼 뒤 `tester.pump(Duration(seconds:1))`
한 번으로 기존 ticker를 실행한다. raw sample을 그대로 두고 availability만 바뀌어야 한다.

```dart
testWidgets('ticker expires speed without changing the recorded distance', (tester) async {
  late WalkRepository repo;
  var now = DateTime.utc(2026, 10, 14);
  await tester.runAsync(() async { repo = await openTestRepository(); });
  addTearDown(() => tester.runAsync(repo.close));
  final container = ProviderContainer(overrides: [
    walkRepositoryProvider.overrideWithValue(repo),
    locationEngineProvider.overrideWithValue(
      SyntheticLocationEngine(permission: LocationPermissionState.granted)),
    sessionClockProvider.overrideWithValue(() => now),
  ]);
  addTearDown(container.dispose);
  final controller = container.read(sessionControllerProvider.notifier);
  await tester.runAsync(controller.start);
  controller.debugIngestSamples([
    LocationSample(timestamp: now, latitude: 37.5, longitude: 127,
      accuracyM: 5, speedMps: 1),
  ]);
  final lastFix = now;
  final measuredDistance = controller.state.liveDistanceM;
  expect(controller.state.speedAvailability, LiveSpeedAvailability.available);
  now = lastFix.add(const Duration(seconds: 30));
  await tester.pump(const Duration(seconds: 1));
  expect(controller.state.speedAvailability, LiveSpeedAvailability.available);
  now = lastFix.add(const Duration(milliseconds: 30001));
  await tester.pump(const Duration(seconds: 1));
  expect(controller.state.speedAvailability, LiveSpeedAvailability.stale);
  expect(controller.state.liveDistanceM, measuredDistance);
  await tester.runAsync(controller.stop);
});
```

같은 test setup에서 거절된 callback은 lastUsableFixAt를 바꾸지 않음, 첫 좌표에
provider speed가 없으면 waiting, 유효한 정지 선분/유효 provider speed 0은 available,
background 전환 후 resume는 ticker를 기다리지 않고 stale을 동기화함을 각 test로 고정한다.

- [x] Step 4: `_onSample`에서 accepted sample만 lastUsableFixAt를 갱신하고, 신뢰 가능한
선분 또는 finite/non-negative provider speed가 있을 때 evidence=true로 만든다.
Task 1의 interrupted fragment에서는 이전 fragment 속도 evidence를 가져오지 않는다.
각 accepted sample마다 현재 선분/provider의 근거를 다시 판정한다. 선분 시간은
양수이며 60초 이하여야 한다. 같은 fragment의 유효 정지 관측은 0을 허용하고,
공백 뒤 단일 좌표에 provider speed도 없으면 evidence=false다. 기존 provider
speed의 `> 0` 조건은 `>= 0`으로 바꿔 유효한 정지 값을 상태에 반영한다.
복구 및 resume에서 같은 함수에 `_clock()`, `_locationQuality.maxAge/maxFutureSkew`를
전달한다. 기존 copyWith에 필드를 추가하고 session reset이 instant/evidence도 초기화한다.
저장된 cold-recovery/resume에서는 evidence를 false로 시작해 새 accepted fix 전에는
과거 provider speed를 현재 측정처럼 표시하지 않는다. warm foreground 복귀는
백그라운드에서 실제 수신한 최신 fix/evidence를 유지하고 신선도만 다시 판정한다.

```dart
state = state.copyWith(
  elapsed: _elapsedSince(startedAt),
  speedAvailability: liveSpeedAvailability(
    lastUsableFixAt: _lastUsableFixAt, now: _clock(),
    hasSpeedEvidence: _hasLiveSpeedEvidence,
    maxAge: _locationQuality.maxAge,
    maxFutureSkew: _locationQuality.maxFutureSkew,
  ),
  lastUsableFixAt: _lastUsableFixAt,
  clearLastUsableFixAt: _lastUsableFixAt == null,
  statusMessage: state.statusMessage,
);
```

ticker, onSample, foreground catch-up snapshot 모두 같은 표시 계약을 쓴다.
백그라운드 ticker 중단과 권한 재검증 흐름은 유지한다.

- [x] Step 5: Home 현재 속도 표시를 다음 switch로 바꾸고 Semantics도 같은 문자열을
사용한다. idle 화면의0 표시에는 active freshness 문구를 붙이지 않는다.

```dart
final speedText = switch (live.speedAvailability) {
  LiveSpeedAvailability.available => '${kmh.toStringAsFixed(1)} km/h',
  LiveSpeedAvailability.waiting => '측정 대기',
  LiveSpeedAvailability.stale => '측정 중단',
};
```

label은 `현재 속도`, active status pill은 raw count 대신 유효 위치와 freshness를 쓴다.
오래된 값을 읽는 Semantics를 제거하고 기존 warning/permission 메시지는 덮어쓰지 않는다.
큰 글자 및 320dp 화면에서는 기존 MetricStrip 반응형 구조를 유지한다.

- [x] Step 6: focused controller/domain/Home tests를 실행하고, 기존 synthetic fixture가
LiveSessionState만 override한다면 새 availability를 명시해 측정 의도를 유지한다.
명령은 `flutter test --no-pub --concurrency=1 test/domain/live_speed_availability_test.dart test/features/session_flow_test.dart test/features/ux_nav_tracking_test.dart test/features/ux_home_recovery_test.dart`.
- [x] Step 7: 해당 파일만 `fix: 현재 속도의 측정 대기와 신호 공백 표시`로 커밋한다.

### Task 3: 재생 시각을 산책 시간대로 표시

**Files**
- Modify: `lib/features/session_detail/session_detail_screen.dart`.
- Test: `test/features/route_playback_flow_test.dart`, `test/domain/utc_minute_window_test.dart`.

**Interfaces**
- `_RoutePlaybackControls` adds required `String timezone`, passed from `session.timezone`.
- Every clock label uses existing `asLocal(DateTime, timezone:)`. Elapsed duration and slider indices remain instant based.

- [x] Step 1: 기존 route playback widget test와 같은 실제 repository setup에서 UTC00:00~00:03
샘플, Asia/Seoul session을 생성한다. 기존 `_settle(tester)` helper로 detail을 로드한 뒤
끝점09:00/09:03, 현재09:03:00, slider Semantics09:03:00을 assert한다. 이전 구현의
00:03:00이 표시되는 실패를 확인한다.

```dart
testWidgets('playback clocks use the session timezone', (tester) async {
  late WalkRepository repo;
  late String sessionId;
  await tester.runAsync(() async {
    repo = await openTestRepository();
    final start = DateTime.utc(2026, 10, 14);
    final end = start.add(const Duration(minutes: 3));
    final session = await repo.startSession(startedAt: start, timezone: 'Asia/Seoul');
    sessionId = session.id;
    final samples = buildWalkTrace(start: start,
      duration: const Duration(minutes: 3));
    final result = SessionPipeline().process(
      session: session, rawSamples: samples, endedAt: end);
    await repo.finalizeSession(session: session, samples: result.filteredSamples,
      windows: result.windows, endedAt: end,
      totalDistanceM: result.metrics.totalDistanceM,
      durationS: result.metrics.durationS, movingTimeS: result.metrics.movingTimeS,
      stationaryTimeS: result.metrics.stationaryTimeS,
      avgSpeedMps: result.metrics.avgSpeedMps,
      validSampleCount: result.metrics.validSampleCount,
      medianAccuracyM: result.metrics.medianAccuracyM);
  });
  addTearDown(() => tester.runAsync(repo.close));
  final semantics = tester.ensureSemantics();
  addTearDown(semantics.dispose);
  await tester.pumpWidget(ProviderScope(overrides: [
    walkRepositoryProvider.overrideWithValue(repo),
  ], child: MaterialApp(home: SessionDetailScreen(sessionId: sessionId))));
  await _settle(tester);
  await _settle(tester);
  expect(find.text('09:00'), findsWidgets);
  expect(find.text('09:03'), findsWidgets);
  expect(find.bySemanticsLabel('경로 재생 위치 09:03:00'), findsOneWidget);
});
```

- [x] Step 2: 파일에 geo import를 추가하고 timezone을 부모에서 전달한다. 현재 sample,
firstTimestamp, lastTimestamp와 Semantics의 네 포맷을 모두 다음과 같이 바꾼다.

```dart
DateFormat('HH:mm:ss').format(asLocal(sample.timestamp, timezone: timezone));
DateFormat('HH:mm').format(asLocal(firstTimestamp, timezone: timezone));
DateFormat('HH:mm').format(asLocal(lastTimestamp, timezone: timezone));
```

- [x] Step 3: America/New_York의2026-11-01T05:30Z와06:30Z는 모두01:30이지만 elapsed는
1시간인 fixture를 추가한다. session timezone만 바꾸고 기기 timezone에 기대지 않도록
UTC input과 IANA 변환을 테스트한다. 잘못된 zone은 기존 asLocal fallback을 깨지 않는다.

```dart
final a = DateTime.utc(2026, 11, 1, 5, 30);
final b = DateTime.utc(2026, 11, 1, 6, 30);
expect(asLocal(a, timezone: 'America/New_York').hour, 1);
expect(asLocal(b, timezone: 'America/New_York').hour, 1);
expect(b.difference(a), const Duration(hours: 1));
```

- [x] Step 4: `flutter test --no-pub --concurrency=1 test/features/route_playback_flow_test.dart test/domain/utc_minute_window_test.dart`를 실행한다.
- [x] Step 5: `fix: 경로 재생 시각을 산책 시간대로 표시`로 커밋한다.

### Task 4: 완료 JSON/NDJSON 평균 속도 통일

**Files**
- Modify: `lib/domain/services/session_export.dart`.
- Test: `test/domain/walk_stats_export_test.dart`, `test/domain/completed_walk_metrics_test.dart`.

**Interfaces**
- Consumes existing `completedAverageSpeedMps({required double? totalDistanceM, required int? movingTimeS}) -> double?`.
- Completed session export field `avg_speed_mps` is canonical, or null when unavailable. Active session export retains its existing meaning.

- [x] Step 1: 실제 helper와 JSON 구조를 검사하는 아래 test를 작성한다. NDJSON의 첫
session line도 decode해 같은1m/s인지 assert한다.

```dart
test('completed JSON uses the same average as the human summary', () {
  final t = DateTime.utc(2026, 10, 14);
  final session = WalkSession(
    id: 'canonical-export', startedAt: t,
    endedAt: t.add(const Duration(seconds: 110)),
    status: SessionStatus.completed, trackingMode: TrackingMode.balanced,
    timezone: 'Asia/Seoul', totalDistanceM: 100, movingTimeS: 100,
    durationS: 110, stationaryTimeS: 10, avgSpeedMps: 9,
  );
  const export = SessionExport();
  final doc = export.toJsonDocument(session: session, windows: const []);
  expect((doc['session'] as Map)['avg_speed_mps'], 1);
  final ndjson = export.toNdjson(
    session: session, windows: const [], samples: const [], exclusions: const [],
  );
  final meta = jsonDecode(ndjson.split('\n').first) as Map;
  expect((meta['session'] as Map)['avg_speed_mps'], 1);
  expect(export.humanSummary(session: session), contains('3.6 km/h'));
});
```

- [x] Step 2: focused test를 실행해 저장값9가 출력되는 RED를 확인한다. 완료
metadata의 `avg_speed_mps`를 다음 식으로 교체하고 계산식을 중복하지 않는다.

```dart
'avg_speed_mps': session.status == SessionStatus.completed
    ? completedAverageSpeedMps(
        totalDistanceM: session.totalDistanceM, movingTimeS: session.movingTimeS,
      )
    : session.avgSpeedMps,
```

- [x] Step 3: distance0/missing, movingTime0/missing, non-finite distance는
toJsonDocument의 평균 field가null인지 검사한다. 비유한 값 fixture의 전체 JSON
인코딩 성공으로 일반화하지 않는다. 전체 백업의 영속값은 바꾸지 않고 active
session export는 기존 저장값을 유지하는 회귀를 추가한다.
- [x] Step 4: `flutter test --no-pub --concurrency=1 test/domain/walk_stats_export_test.dart test/domain/completed_walk_metrics_test.dart`를 실행한다.
- [x] Step 5: `fix: 완료 기록 내보내기의 평균 속도 기준 통일`로 커밋한다.

### Task 5: 건강 데이터 오류와 지원 설정 구분

**Files**
- Modify: `lib/data/activity_data_source.dart`, `lib/features/history/daily_activity_panel.dart`.
- Test: `test/data/activity_data_source_test.dart`, `test/features/daily_activity_panel_test.dart`.
- Read: `lib/platform/activity/health_activity_data_source.dart`.

**Interfaces**
- Adds `bool get canOpenSettings` to existing `ActivityDataSourceSettingsOpener`.
- HealthActivityDataSource returns `_settingsOpener != null`; existing Android opener remains available and iOS factory's null opener remains unsupported.
- Test `_SettingsActivitySource` implements the new getter with true, with a false variant for unavailable capability.

- [x] Step 1: 실제 source의 iOS처럼null opener와 Android처럼non-null opener가 각각false/true인
test를 작성한다. 기존 reader fake를 재사용하고 source capability 타입만으로 지원을
판정하지 않는 아래 assertion을 추가한다.

```dart
test('settings capability reflects an installed opener', () {
  final reader = _FakeDailyStepsReader(sourceKind: ActivitySourceKind.healthKit);
  final noSettings = HealthActivityDataSource(reader);
  expect(noSettings.canOpenSettings, isFalse);
  final withSettings = HealthActivityDataSource(reader, settingsOpener: () async => true);
  expect(withSettings.canOpenSettings, isTrue);
});
```

- [x] Step 2: Daily panel fixture에서 source=error/coverage=unavailable/steps=null은
`불러오기 실패`와`다시 불러오기`, denied는`권한 필요`, unavailable은`연결 전`,
partial은기존`일부 기간만 확인됨`, complete steps0은`0걸음`인지 table test를 추가한다.
false capability에서 `Health Connect 설정 열기`가 없어야 하고 true Android fixture는
기존 action을 유지해야 한다. 기존 `_pumpPanel`/snapshot setup을 그대로 쓴다.

`_pumpPanel`에 nullable `DailyStepSnapshot? steps`와 `ActivityDataSource? source`를
추가한다. source override와 steps map은 아래처럼 기존 snapshot에 전달한다.
`_SettingsActivitySource`는 생성자에서 `this.canOpenSettings = true`를 받고
`@override final bool canOpenSettings` 필드를 노출한다.

```dart
if (source != null) activityDataSourceProvider.overrideWithValue(source),
dailyActivityProvider.overrideWith((ref) async => DailyActivitySnapshot(
  days: days, weekStart: days.first.date, weekEnd: days.last.date,
  stepsByDate: steps == null ? const {} : {steps.date: steps},
)),
```

기존 `_days()`와 확장한 `_pumpPanel`을 사용하는 실제 상태 표 테스트다.

```dart
for (final row in <(ActivitySourceKind, ActivityCoverage, int?, String)>[
  (ActivitySourceKind.error, ActivityCoverage.unavailable, null, '불러오기 실패'),
  (ActivitySourceKind.denied, ActivityCoverage.unavailable, null, '권한 필요'),
  (ActivitySourceKind.unavailable, ActivityCoverage.unavailable, null, '연결 전'),
  (ActivitySourceKind.healthKit, ActivityCoverage.partial, 5, '일부 기간만 확인됨'),
  (ActivitySourceKind.healthKit, ActivityCoverage.complete, 0, '0걸음'),
]) {
  testWidgets('step status is ${row.$4}', (tester) async {
    final days = _days();
    final date = days.last.date;
    await _pumpPanel(tester, days, selected: date,
      source: _SettingsActivitySource(canOpenSettings: false),
      steps: DailyStepSnapshot(date: date, steps: row.$3,
        source: row.$1, coverage: row.$2));
    expect(find.text(row.$4), findsWidgets);
    expect(find.text('Health Connect 설정 열기'), findsNothing);
    if (row.$1 == ActivitySourceKind.error) {
      expect(find.text('다시 불러오기'), findsOneWidget);
    }
  });
}
```

- [x] Step 3: interface와 getter를 추가하고 수치의 switch를 source 우선 판정으로 바꾼다.

```dart
// ActivityDataSourceSettingsOpener의 공개 계약에 추가한다.
bool get canOpenSettings;

// HealthActivityDataSource에서 구현한다.
@override
bool get canOpenSettings => _settingsOpener != null;
```

panel의 기존 `steps`와 `settingsOpener`를 사용하는 표시 코드다.

```dart
final stepsValue = switch (steps) {
  DailyStepSnapshot(source: ActivitySourceKind.error) => '불러오기 실패',
  DailyStepSnapshot(source: ActivitySourceKind.denied) => '권한 필요',
  DailyStepSnapshot(coverage: ActivityCoverage.partial) => '일부 기간만 확인됨',
  DailyStepSnapshot(coverage: ActivityCoverage.complete, steps: final int total) =>
    '${NumberFormat.decimalPattern('ko').format(total)}걸음',
  _ => '연결 전',
};
final opener = settingsOpener?.canOpenSettings == true ? settingsOpener : null;
```

error에서는 `ref.invalidate(dailyActivityProvider)`를 호출하는 재조회 버튼을 제공한다.
부모 ConsumerWidget에서 아래 callback을 전달하고 `_DailyActivityLoaded`의 생성자와
필드에 `required VoidCallback onRetry`를 추가한다. 읽기 실패 상태에서만 버튼을 보인다.

```dart
onRetry: () => ref.invalidate(dailyActivityProvider),
```

```dart
if (steps.source == ActivitySourceKind.error)
  OutlinedButton.icon(
    onPressed: onRetry,
    icon: const Icon(Icons.refresh_rounded),
    label: const Text('다시 불러오기'),
  ),
```

HealthKit의 읽기 권한 불확실성 때문에 필요한 연결 확인 action 자체를 숨기지 않으며,
재조회와 권한 연결의 문구를 구분한다. GPS 통계와 5분 cache/resume invalidation은 유지한다.

- [x] Step 4: `flutter test --no-pub --concurrency=1 test/data/activity_data_source_test.dart test/features/daily_activity_panel_test.dart test/features/daily_activity_provider_test.dart`를 실행한다.
- [x] Step 5: `fix: 건강 데이터 오류와 설정 지원 여부 구분`으로 커밋한다.

## 이 계획의 종료 증거

Task 1~5의 focused tests가 각각 원래 오류로 RED가 되고 수정 후GREEN이 되어야 한다.
전체 gate는 [통합 계획](2026-10-14-maintenance-stage1.md)의 마지막 검증에서 한 번 실행한다.
baseline439개 통과는 새 코드의 검증으로 재사용하지 않는다. 제품 구현 승인은 통합 계획
검토 이후이며, 이 문서 작성 자체는 구현 완료가 아니다.

작업 1~5의 회귀와 수정은 커밋했습니다. 전체 gate와 남은 실제 플랫폼 검증 상태는
[구현 검증 기록](../verification/2026-10-14-maintenance-stage1.md)을 따릅니다.
