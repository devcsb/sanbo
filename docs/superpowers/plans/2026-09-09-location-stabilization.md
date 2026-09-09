# Android Location Stabilization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Prevent stale, malformed, approximate, and unusably inaccurate Android fixes from becoming route anchors or live metrics.

**Architecture:** Add one pure LocationQualityPolicy. The geolocator adapter marks rejected samples while retaining them for audit, and advances the watchdog only for accepted fresh fixes. SessionController reuses the policy for live ingestion and preserves the decision through recovery and finalization. SampleFilter continues to own jump, soft-accuracy, and path-geometry rules.

**Tech Stack:** Flutter/Dart, geolocator 13.0.4, Riverpod, Flutter tests, SQLite repository, and the existing session pipeline.

**Spec:** docs/superpowers/specs/2026-09-09-android-location-health-stabilization-design.md

## Global Constraints

- Keep maxAge at 30 seconds, maxFutureSkew at 5 seconds, and hardMaxAccuracyM at 500.
- Preserve fused stream, LocationManager fallback, foreground service, notifications, persistence retry, and raw sample retention.
- Rejected samples stay as audit rows with isFilteredOut=true and cannot affect route, speed, valid count, stationary state, or high-speed continuity.
- Diagnostics can contain aggregate counts only; never coordinates or health values.
- Do not rewrite the user-owned automatic route-exclusion changes.
- Every task is RED, GREEN, refactor, regression test, and focused commit.

## File Map

- Create lib/domain/services/location_quality_policy.dart and its unit test.
- Modify lib/platform/location/location_engine.dart and geolocator_location_engine.dart.
- Modify test/platform/geolocator_location_engine_policy_test.dart.
- Modify lib/features/home/session_controller.dart and home_screen.dart.
- Modify the existing session and Home permission widget tests.
- Create a verification note without raw location data.

### Task 1: Add the pure quality policy

**Files:**
- Create: lib/domain/services/location_quality_policy.dart
- Create: test/domain/location_quality_policy_test.dart

**Interfaces:**
- Consumes LocationSample.
- Produces LocationQualityRejection, LocationQualityDecision, and LocationQualityPolicy.evaluate.

- [ ] Step 1: Write the failing tests.

~~~dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sanbo/domain/models/location_sample.dart';
import 'package:sanbo/domain/services/location_quality_policy.dart';

void main() {
  const policy = LocationQualityPolicy();
  final now = DateTime.utc(2026, 9, 9, 12);

  LocationSample make(DateTime time, {double lat = 37.5, double acc = 10}) =>
      LocationSample(
        timestamp: time,
        latitude: lat,
        longitude: 127,
        accuracyM: acc,
      );

  test('accepts a fresh cold fix', () {
    final result = policy.evaluate(sample: make(now), observedAt: now);
    expect(result.accepted, isTrue);
  });

  test('rejects malformed, stale, future, and inaccurate fixes', () {
    expect(
      policy.evaluate(sample: make(now, lat: double.nan), observedAt: now)
          .rejection,
      LocationQualityRejection.invalidCoordinate,
    );
    expect(
      policy.evaluate(
        sample: make(now, acc: 500.1),
        observedAt: now,
      ).rejection,
      LocationQualityRejection.excessiveAccuracy,
    );
    expect(
      policy.evaluate(
        sample: make(now.subtract(const Duration(seconds: 31))),
        observedAt: now,
      ).rejection,
      LocationQualityRejection.staleTimestamp,
    );
    expect(
      policy.evaluate(
        sample: make(now.add(const Duration(seconds: 6))),
        observedAt: now,
      ).rejection,
      LocationQualityRejection.futureTimestamp,
    );
  });

  test('rejects pre-session and out-of-order samples', () {
    final start = now.subtract(const Duration(seconds: 10));
    expect(
      policy.evaluate(
        sample: make(start.subtract(const Duration(milliseconds: 1))),
        observedAt: now,
        sessionStart: start,
      ).rejection,
      LocationQualityRejection.beforeSession,
    );
    expect(
      policy.evaluate(
        sample: make(now.subtract(const Duration(seconds: 1))),
        observedAt: now,
        previousAccepted: now,
      ).rejection,
      LocationQualityRejection.outOfOrder,
    );
  });
}
~~~

- [ ] Step 2: Run the focused test.

Run: flutter test --no-pub --concurrency=1 test/domain/location_quality_policy_test.dart

Expected: FAIL because the policy types do not exist.

- [ ] Step 3: Implement the minimal policy.

~~~dart
import '../models/location_sample.dart';

enum LocationQualityRejection {
  invalidCoordinate,
  invalidTimestamp,
  staleTimestamp,
  futureTimestamp,
  excessiveAccuracy,
  beforeSession,
  outOfOrder,
}

class LocationQualityDecision {
  const LocationQualityDecision.accepted() : rejection = null;
  const LocationQualityDecision.rejected(this.rejection);

  final LocationQualityRejection? rejection;
  bool get accepted => rejection == null;
}

class LocationQualityPolicy {
  const LocationQualityPolicy({
    this.maxAge = const Duration(seconds: 30),
    this.maxFutureSkew = const Duration(seconds: 5),
    this.hardMaxAccuracyM = 500,
  });

  final Duration maxAge;
  final Duration maxFutureSkew;
  final double hardMaxAccuracyM;

  LocationQualityDecision evaluate({
    required LocationSample sample,
    required DateTime observedAt,
    DateTime? sessionStart,
    DateTime? previousAccepted,
  }) {
    final lat = sample.latitude;
    final lon = sample.longitude;
    if (!lat.isFinite || !lon.isFinite || lat < -90 || lat > 90 ||
        lon < -180 || lon > 180) {
      return const LocationQualityDecision.rejected(
        LocationQualityRejection.invalidCoordinate,
      );
    }
    final accuracy = sample.accuracyM;
    if (accuracy != null &&
        (!accuracy.isFinite || accuracy < 0 || accuracy > hardMaxAccuracyM)) {
      return const LocationQualityDecision.rejected(
        LocationQualityRejection.excessiveAccuracy,
      );
    }
    final timestamp = sample.timestamp.toUtc();
    final observed = observedAt.toUtc();
    if (sessionStart != null && timestamp.isBefore(sessionStart.toUtc())) {
      return const LocationQualityDecision.rejected(
        LocationQualityRejection.beforeSession,
      );
    }
    if (timestamp.isBefore(observed.subtract(maxAge))) {
      return const LocationQualityDecision.rejected(
        LocationQualityRejection.staleTimestamp,
      );
    }
    if (timestamp.isAfter(observed.add(maxFutureSkew))) {
      return const LocationQualityDecision.rejected(
        LocationQualityRejection.futureTimestamp,
      );
    }
    if (previousAccepted != null &&
        !timestamp.isAfter(previousAccepted.toUtc())) {
      return const LocationQualityDecision.rejected(
        LocationQualityRejection.outOfOrder,
      );
    }
    return const LocationQualityDecision.accepted();
  }
}
~~~

Keep invalidTimestamp in the vocabulary for platform adapters; do not create an impossible invalid DateTime in tests.

- [ ] Step 4: Run format, test, and analyzer.

~~~bash
dart format lib/domain/services/location_quality_policy.dart test/domain/location_quality_policy_test.dart
flutter test --no-pub --concurrency=1 test/domain/location_quality_policy_test.dart
flutter analyze --no-pub
~~~

- [ ] Step 5: Commit.

~~~bash
git add lib/domain/services/location_quality_policy.dart test/domain/location_quality_policy_test.dart
git commit -m "feat: add shared location quality policy"
~~~

### Task 2: Detect reduced accuracy and harden the provider boundary

**Files:**
- Modify: lib/platform/location/location_engine.dart
- Modify: lib/platform/location/geolocator_location_engine.dart
- Modify: test/platform/geolocator_location_engine_policy_test.dart

**Interfaces:**
- Consumes Task 1 policy and geolocator LocationAccuracyStatus.
- Produces LocationPermissionState.reducedAccuracy and a testable permission mapper.

- [ ] Step 1: Write failing tests.

~~~dart
test('approximate Android permission maps to reducedAccuracy', () {
  expect(
    GeolocatorLocationEngine.mapPermissionState(
      permission: LocationPermission.whileInUse,
      accuracy: LocationAccuracyStatus.reduced,
    ),
    LocationPermissionState.reducedAccuracy,
  );
  expect(
    GeolocatorLocationEngine.mapPermissionState(
      permission: LocationPermission.whileInUse,
      accuracy: LocationAccuracyStatus.precise,
    ),
    LocationPermissionState.granted,
  );
});

test('denied permission is not changed by reduced accuracy', () {
  expect(
    GeolocatorLocationEngine.mapPermissionState(
      permission: LocationPermission.denied,
      accuracy: LocationAccuracyStatus.reduced,
    ),
    LocationPermissionState.denied,
  );
});
~~~

- [ ] Step 2: Run the focused test.

Run: flutter test --no-pub --concurrency=1 test/platform/geolocator_location_engine_policy_test.dart

Expected: FAIL because the enum member and mapper do not exist.

- [ ] Step 3: Add the state and mapper.

~~~dart
enum LocationPermissionState {
  granted,
  grantedForegroundOnly,
  reducedAccuracy,
  denied,
  deniedForever,
  serviceDisabled,
  unknown,
}

@visibleForTesting
static LocationPermissionState mapPermissionState({
  required LocationPermission permission,
  required LocationAccuracyStatus? accuracy,
}) {
  final state = switch (permission) {
    LocationPermission.always || LocationPermission.whileInUse =>
      LocationPermissionState.granted,
    LocationPermission.denied => LocationPermissionState.denied,
    LocationPermission.deniedForever => LocationPermissionState.deniedForever,
    LocationPermission.unableToDetermine => LocationPermissionState.unknown,
  };
  if (state == LocationPermissionState.granted &&
      Platform.isAndroid &&
      accuracy == LocationAccuracyStatus.reduced) {
    return LocationPermissionState.reducedAccuracy;
  }
  return state;
}
~~~

Add LocationFailureKind.reducedAccuracy. Route checkPermission, requestPermission, and the direct start guard through an async helper that calls getLocationAccuracy only for a granted foreground permission. Preserve the existing iOS Always upgrade.

- [ ] Step 4: Mark provider samples at the adapter boundary.

Add LocationSample? _lastAcceptedSample. After Position conversion, evaluate with LocationQualityPolicy using DateTime.now and the last accepted timestamp. Emit the sample with isFilteredOut equal to the inverse decision. Update _lastEmitAt and _lastAcceptedSample only for accepted samples. Retain rejected samples on the stream. Do not log coordinates. If stream arming needs a silence baseline, store it separately from _lastEmitAt.

~~~dart
final decision = const LocationQualityPolicy().evaluate(
  sample: sample,
  observedAt: DateTime.now(),
  previousAccepted: _lastAcceptedSample?.timestamp,
);
final emitted = sample.copyWith(isFilteredOut: !decision.accepted);
if (decision.accepted) {
  _lastAcceptedSample = emitted;
  _lastEmitAt = DateTime.now();
}
_controller.add(emitted);
~~~

- [ ] Step 5: Run focused regressions and commit.

~~~bash
dart format lib/platform/location/location_engine.dart lib/platform/location/geolocator_location_engine.dart test/platform/geolocator_location_engine_policy_test.dart
flutter test --no-pub --concurrency=1 test/platform/geolocator_location_engine_policy_test.dart test/domain/location_quality_policy_test.dart
git add lib/platform/location/location_engine.dart lib/platform/location/geolocator_location_engine.dart test/platform/geolocator_location_engine_policy_test.dart
git commit -m "fix: reject stale Android location fixes at provider boundary"
~~~

### Task 3: Reuse the policy in the controller and Home UI

**Files:**
- Modify: lib/features/home/session_controller.dart
- Modify: lib/features/home/home_screen.dart
- Modify: test/features/session_guard_flow_test.dart
- Modify: the existing Home permission/error widget test

**Interfaces:**
- Consumes Tasks 1 and 2.
- Produces reduced-accuracy gating, stored boundary decisions, and precise-location guidance.

- [ ] Step 1: Write failing tests.

~~~dart
test('reduced accuracy never creates a walk session', () async {
  final repo = await openTestRepository();
  addTearDown(repo.close);
  final engine = SyntheticLocationEngine(
    permission: LocationPermissionState.reducedAccuracy,
  );
  final container = ProviderContainer(
    overrides: [
      walkRepositoryProvider.overrideWithValue(repo),
      locationEngineProvider.overrideWithValue(engine),
    ],
  );
  addTearDown(container.dispose);

  final controller = container.read(sessionControllerProvider.notifier);
  await controller.start();

  expect(controller.state.session, isNull);
  expect(controller.state.isTracking, isFalse);
  expect(
    controller.state.permissionState,
    LocationPermissionState.reducedAccuracy,
  );
  expect(controller.state.errorMessage, contains('정확한 위치'));
});
~~~

Add a stale callback to the existing debugIngestSamples fixture and assert the raw count increases while validSampleCount, liveDistanceM, and liveSpeedMps do not. Add a Home widget assertion for the existing settings action.

- [ ] Step 2: Run focused tests and verify the missing behavior.

Run: flutter test --no-pub --concurrency=1 test/features/session_guard_flow_test.dart test/features/ux_home_permission_test.dart

Expected: FAIL because the controller currently falls through to the generic permission branch. Select the existing Home permission test path with rg -l if its filename differs.

- [ ] Step 3: Replace duplicated controller boundary logic.

Add a const LocationQualityPolicy field. In _onSample, evaluate with receiptNow, sessionStart, and _lastValidSample timestamp; store a filtered copy when rejected. Preserve the existing SampleFilter probe. During recovery and finalization, preserve stored isFilteredOut and use the same session-start/future limits; do not apply receipt freshness to historical rows. Add a stop-path assertion that the stale audit row remains but creates no fragment or metric.

- [ ] Step 4: Gate session creation and update guidance.

~~~dart
if (perm == LocationPermissionState.reducedAccuracy) {
  state = state.copyWith(
    isBusy: false,
    errorMessage: '산책 경로를 기록하려면 산보의 정확한 위치 권한을 허용해 주세요. 설정에서 정확한 위치를 켤 수 있어요.',
    errorCode: SessionErrorCode.permission,
  );
  return;
}
~~~

Add reducedAccuracy cases to location error message/code. Include reducedAccuracy in Home settings and hint predicates. Preserve denied, deniedForever, serviceDisabled, and iOS foreground-only behavior.

- [ ] Step 5: Run regressions, analyzer, and commit.

~~~bash
dart format lib/features/home/session_controller.dart lib/features/home/home_screen.dart test/features/session_guard_flow_test.dart
flutter test --no-pub --concurrency=1 test/features/session_guard_flow_test.dart test/platform/geolocator_location_engine_policy_test.dart
flutter analyze --no-pub
git add lib/features/home/session_controller.dart lib/features/home/home_screen.dart test/features/session_guard_flow_test.dart
git commit -m "fix: gate walks on precise location and shared sample quality"
~~~

### Task 4: Verify the complete location contract

**Files:**
- Create: docs/superpowers/verification/2026-09-09-location-stabilization.md
- Modify docs/DEVICE_VALIDATION.md only if its checklist lacks the required cases.

- [ ] Step 1: Record the manual matrix: approximate to precise permission, outdoor cold start, screen lock, background recording, provider off/on, stale callback, malformed callback, and fused to LocationManager recovery. Do not invent device results.
- [ ] Step 2: Run the full verification.

~~~bash
flutter test --no-pub --concurrency=1
flutter analyze --no-pub
git diff --check
cd android && ./gradlew :app:testDebugUnitTest :app:assembleDebug
adb devices
~~~

- [ ] Step 3: Record output, commit ids, and device availability. An empty adb result means physical validation was not performed. Do not include raw coordinates or health values.
- [ ] Step 4: Commit the evidence.

~~~bash
git add docs/superpowers/verification/2026-09-09-location-stabilization.md docs/DEVICE_VALIDATION.md
git commit -m "test: record Android location stabilization verification"
~~~

## Plan Self-Review

- Spec coverage: reduced accuracy, provider freshness, malformed coordinates, raw-row retention, shared controller boundaries, recovery, finalization, and device evidence are covered by Tasks 1 through 4.
- Placeholder scan: every step has concrete interfaces, test code, commands, and expected results.
- Type consistency: Task 1 defines the policy; Task 2 defines the reduced permission state; Task 3 consumes both; Task 4 consumes completed artifacts.
- Regression boundary: commits stage only this plan’s files and leave automatic route-exclusion changes unstaged.
