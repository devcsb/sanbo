# Sanbo Experience Battery UX v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (\`- [ ]\`) syntax for tracking.

**Goal:** Make the walk recorder easier to change, gentler on battery, and smoother to use while preserving local data, GPS reliability, and non-clinical recall UX.

**Architecture:** Keep \`SessionController\` as a compatibility facade while extracting pure policies and narrow coordinators behind injectable interfaces. Add shared motion and provenance-aware daily activity services; do not rewrite SQLite or replace GPS with an unreliable sensor path.

**Tech Stack:** Flutter 3.47, Dart 3.12, Riverpod, SQLite/sqflite, geolocator, \`health\`, Flutter widget tests, Android Gradle tests, iOS XCTest.

**Spec:** \`docs/superpowers/specs/2026-08-29-sanbo-experience-battery-ux-v1-design.md\`

## Global Constraints

- GPS remains the primary route recorder; Health Connect/HealthKit steps are read-only, separate, and never added to GPS distance.
- Existing SQLite v6 schema, backup schema, and public \`SessionController\` methods remain compatible.
- Profiles remain saver 20s/10m/medium, balanced 8s/5m/high, precision 4s/2m/bestForNavigation; wake lock only for precision.
- Stationary warning/auto-stop remains 20/30 minutes; duration warning/auto-stop remains 4h45m/5h.
- No first-screen health permission prompt, background health polling, diagnosis, mood inference, streak pressure, or social comparison.
- Every asynchronous UI write checks \`mounted\` or generation; destructive data operations remain transactional.
- Primary controls are at least 48dp; large text, screen readers, and \`disableAnimations\` are release requirements.
- Battery percentages are measured on physical devices and never presented as universal guarantees.

### Task 1: Shared motion and transition primitives

**Files:**
- Create: \`lib/shared/widgets/app_motion.dart\`
- Modify: \`lib/core/theme/app_theme.dart\`
- Test: \`test/shared/app_motion_test.dart\`

**Interfaces:**
- Produces \`AppMotion.duration(BuildContext, Duration)\`, \`AppMotion.curve\`, and \`SmoothSwitcher({required Object transitionKey, required Widget child, Duration duration})\`.

- [ ] **Step 1: Write the failing test**

~~~~dart
testWidgets('motion duration is zero when animations are disabled', (tester) async {
  await tester.pumpWidget(const MediaQuery(
    data: MediaQueryData(disableAnimations: true),
    child: MaterialApp(home: SizedBox()),
  ));
  expect(AppMotion.duration(
    tester.element(find.byType(SizedBox)),
    AppMotion.standard,
  ), Duration.zero);
});
~~~~

- [ ] **Step 2: Run and verify failure**

Run: \`flutter test --no-pub test/shared/app_motion_test.dart\`

Expected: FAIL because \`AppMotion\` does not exist.

- [ ] **Step 3: Implement minimal primitives**

~~~~dart
abstract final class AppMotion {
  static const standard = Duration(milliseconds: 180);
  static const expand = Duration(milliseconds: 240);
  static const feedback = Duration(milliseconds: 120);
  static const curve = Curves.easeOutCubic;

  static Duration duration(BuildContext context, Duration value) =>
      MediaQuery.maybeOf(context)?.disableAnimations == true
          ? Duration.zero
          : value;
}
~~~~

\`SmoothSwitcher\` must use stable \`ValueKey(transitionKey)\`, fade only, and \`AppMotion.duration\`.

- [ ] **Step 4: Run focused tests**

Run: \`flutter test --no-pub test/shared/app_motion_test.dart\`

Expected: PASS with no exception.

- [ ] **Step 5: Commit**

~~~~bash
git add lib/shared/widgets/app_motion.dart test/shared/app_motion_test.dart
git commit -m "feat: add accessible shared motion primitives"
~~~~

### Task 2: Wire stable transitions into async screens

**Files:**
- Modify: \`lib/features/history/history_screen.dart\`
- Modify: \`lib/features/history/daily_activity_panel.dart\`
- Modify: \`lib/features/session_detail/session_detail_screen.dart\`
- Test: \`test/features/ux_transition_test.dart\`

**Interfaces:**
- Consumes \`SmoothSwitcher\`.
- Produces keyed \`loading\`, \`error\`, and \`data:<identity>\` states without changing public providers.

- [ ] **Step 1: Write tests**

~~~~dart
testWidgets('loading to data keeps layout stable and has no exception', (tester) async {
  // Override the provider with a pending completer, pump loading, resolve it,
  // pump AppMotion.standard, and assert data plus takeException() == null.
});
~~~~

- [ ] **Step 2: Run the focused test and verify it fails**

Run: \`flutter test --no-pub test/features/ux_transition_test.dart\`

Expected: FAIL until each async screen uses the keyed switcher.

- [ ] **Step 3: Implement**

Wrap the existing \`AsyncValue.when\` output in \`SmoothSwitcher\`; retain current retry callbacks and fixed loading heights. Do not animate the map itself.

- [ ] **Step 4: Verify**

Run: \`flutter test --no-pub test/features/ux_transition_test.dart test/features/ux_design_system_test.dart test/features/daily_activity_panel_test.dart\`

Expected: PASS at 320x568 and text scale 1.8.

- [ ] **Step 5: Commit**

~~~~bash
git add lib/features/history/history_screen.dart lib/features/history/daily_activity_panel.dart lib/features/session_detail/session_detail_screen.dart test/features/ux_transition_test.dart
git commit -m "feat: smooth async screen transitions"
~~~~

### Task 3: Make daily activity available before the first walk

**Files:**
- Modify: \`lib/features/history/history_screen.dart\`
- Modify: \`lib/features/history/daily_activity_panel.dart\`
- Test: \`test/features/ux_history_empty_activity_test.dart\`

**Interfaces:**
- Empty history renders \`PageIntro\`, \`DailyActivityPanel\`, and the existing \`산책 시작하기\` action in one scrollable page.

- [ ] **Step 1: Write the failing test**

~~~~dart
testWidgets('empty history still exposes daily activity', (tester) async {
  // Override completedSessionsProvider with an empty snapshot and activity
  // source with UnavailableActivityDataSource.
  // Expect '일별 운동량' and '산책 시작하기'.
});
~~~~

- [ ] **Step 2: Run and verify failure**

Run: \`flutter test --no-pub test/features/ux_history_empty_activity_test.dart\`

Expected: FAIL because the current branch returns only \`EmptyStateView\`.

- [ ] **Step 3: Implement**

Replace only the empty branch with \`PageFrame\` + vertical scroll view. Keep the health source read-only and do not request permission during first render.

- [ ] **Step 4: Verify**

Run: \`flutter test --no-pub test/features/ux_history_empty_activity_test.dart test/features/ux_design_system_test.dart\`

Expected: PASS with no nested-scroll or overflow exception.

- [ ] **Step 5: Commit**

~~~~bash
git add lib/features/history/history_screen.dart lib/features/history/daily_activity_panel.dart test/features/ux_history_empty_activity_test.dart
git commit -m "feat: expose daily activity before first walk"
~~~~

### Task 4: Explain and cache health coverage

**Files:**
- Modify: \`lib/data/activity_data_source.dart\`
- Modify: \`lib/platform/activity/health_activity_data_source.dart\`
- Modify: \`lib/features/history/daily_activity_panel.dart\`
- Modify: \`lib/features/history/history_providers.dart\`
- Test: \`test/data/activity_data_source_test.dart\`
- Test: \`test/features/daily_activity_panel_test.dart\`

**Interfaces:**
- Preserve \`DailyStepSnapshot\` and \`ActivityCoverage\`.
- Add a five-minute in-memory cache keyed by source and local date.
- A successful row keeps \`steps == 0\`; partial/denied/unavailable/error never become zero.

- [ ] **Step 1: Write tests**

~~~~dart
testWidgets('partial health coverage is not presented as zero', (tester) async {
  // Inject a partial Health Connect snapshot and expect a coverage explanation.
});
~~~~

- [ ] **Step 2: Run focused tests and verify failure**

Run: \`flutter test --no-pub test/data/activity_data_source_test.dart test/features/daily_activity_panel_test.dart\`

Expected: FAIL on the new partial-coverage assertion.

- [ ] **Step 3: Implement**

Add source-specific freshness/coverage copy. Invalidate the cache after \`requestAccess()\` and when a week changes outside the cached range. Do not persist health rows in the GPS database.

- [ ] **Step 4: Verify and commit**

Run: \`flutter test --no-pub test/data/activity_data_source_test.dart test/features/daily_activity_panel_test.dart test/features/daily_activity_provider_test.dart\`

~~~~bash
git add lib/data/activity_data_source.dart lib/platform/activity/health_activity_data_source.dart lib/features/history/daily_activity_panel.dart lib/features/history/history_providers.dart test/data/activity_data_source_test.dart test/features/daily_activity_panel_test.dart
git commit -m "feat: explain and cache daily health coverage"
~~~~

### Task 5: Safely reconfigure location energy profiles

**Files:**
- Modify: \`lib/platform/location/location_engine.dart\`
- Modify: \`lib/platform/location/geolocator_location_engine.dart\`
- Modify: \`lib/platform/location/synthetic_location_engine.dart\`
- Modify: \`lib/features/home/session_controller.dart\`
- Create: \`lib/domain/services/location_energy_policy.dart\`
- Test: \`test/domain/location_energy_policy_test.dart\`
- Test: \`test/platform/location_engine_test.dart\`

**Interfaces:**
- \`LocationEngine.setMode(TrackingMode)\` is safe while running.
- \`LocationEnergyPolicy.suggestedMode({required TrackingMode current, required int? batteryPercent, required bool userEnabled})\` returns nullable \`TrackingMode\`.

- [ ] **Step 1: Write policy tests**

~~~~dart
test('low battery never silently changes a mode', () {
  expect(LocationEnergyPolicy.suggestedMode(
    current: TrackingMode.highAccuracy,
    batteryPercent: 10,
    userEnabled: false,
  ), isNull);
});

test('opted-in suggestion lowers one profile', () {
  expect(LocationEnergyPolicy.suggestedMode(
    current: TrackingMode.highAccuracy,
    batteryPercent: 10,
    userEnabled: true,
  ), TrackingMode.balanced);
});
~~~~

- [ ] **Step 2: Run and verify failure**

Run: \`flutter test --no-pub test/domain/location_energy_policy_test.dart\`

Expected: FAIL because the policy does not exist.

- [ ] **Step 3: Implement policy**

Suggest only at \`batteryPercent <= 15\`; require explicit user action and provide dismissal. Never silently change the requested profile.

- [ ] **Step 4: Implement stream reconfiguration**

When running, cancel the old subscription before creating exactly one stream with the new profile, preserve generation guards, and issue at most one seed request. Synthetic engines only update their mode.

- [ ] **Step 5: Verify and commit**

Run: \`flutter test --no-pub test/domain/location_energy_policy_test.dart test/platform/location_engine_test.dart test/features/session_flow_test.dart test/features/session_guard_flow_test.dart\`

~~~~bash
git add lib/platform/location/location_engine.dart lib/platform/location/geolocator_location_engine.dart lib/platform/location/synthetic_location_engine.dart lib/features/home/session_controller.dart lib/domain/services/location_energy_policy.dart test/domain/location_energy_policy_test.dart test/platform/location_engine_test.dart
git commit -m "feat: safely reconfigure location energy profiles"
~~~~

### Task 6: Extract persistence from the controller facade

**Files:**
- Create: \`lib/application/session/session_persistence_coordinator.dart\`
- Modify: \`lib/features/home/session_controller.dart\`
- Test: \`test/application/session_persistence_coordinator_test.dart\`

**Interfaces:**

~~~~dart
abstract interface class SessionPersistenceCoordinator {
  Future<void> checkpoint({
    required String sessionId,
    required List<LocationSample> samples,
    required int generation,
  });

  Future<void> flushForStop({
    required String sessionId,
    required List<LocationSample> samples,
    required int generation,
  });
}
~~~~

- [ ] **Step 1: Write tests**

~~~~dart
test('checkpoint failure retains the complete pending batch for retry', () async {
  // Fake repository throws once, then succeeds; assert every sample is written once.
});

test('stale generation cannot write after a new session starts', () async {
  // Enqueue generation 1, advance to generation 2, and assert no stale write.
});
~~~~

- [ ] **Step 2: Run and verify failure**

Run: \`flutter test --no-pub test/application/session_persistence_coordinator_test.dart\`

Expected: FAIL because the coordinator does not exist.

- [ ] **Step 3: Implement**

Move only queue, batch, retry, and generation checks. Keep safety evaluation and public controller methods in place; preserve existing recovery behavior.

- [ ] **Step 4: Verify and commit**

Run: \`flutter test --no-pub test/application/session_persistence_coordinator_test.dart test/data/walk_repository_test.dart test/data/walk_backup_test.dart test/features/session_flow_test.dart\`

~~~~bash
git add lib/application/session/session_persistence_coordinator.dart lib/features/home/session_controller.dart test/application/session_persistence_coordinator_test.dart
git commit -m "refactor: extract session persistence coordinator"
~~~~

### Task 7: Remove route playback prefix allocations

**Files:**
- Create: \`lib/domain/services/route_playback_cursor.dart\`
- Modify: \`lib/shared/widgets/route_map.dart\`
- Modify: \`lib/features/session_detail/session_detail_screen.dart\`
- Test: \`test/domain/route_playback_cursor_test.dart\`

**Interfaces:**
- \`RoutePlaybackCursor.visibleFragments()\` returns the visible fragment indices and active prefix without copying every completed fragment per tick.

- [ ] **Step 1: Write tests**

~~~~dart
test('cursor matches the old visible prefix at first, middle, and last indexes', () {
  // Compare 1k-point expected coordinate indexes.
});

test('cursor clamps invalid positions', () {
  // Negative and oversized positions return a valid empty/last view.
});
~~~~

- [ ] **Step 2: Run and verify failure**

Run: \`flutter test --no-pub test/domain/route_playback_cursor_test.dart\`

Expected: FAIL because the cursor does not exist.

- [ ] **Step 3: Implement**

Keep static geometry cached. Only the active fragment prefix is materialized for the map layer; completed fragments use their immutable cached lists.

- [ ] **Step 4: Verify and commit**

Run: \`flutter test --no-pub test/domain/route_playback_cursor_test.dart test/domain/route_playback_test.dart test/shared/route_map_geometry_test.dart test/features/route_playback_flow_test.dart\`

~~~~bash
git add lib/domain/services/route_playback_cursor.dart lib/shared/widgets/route_map.dart lib/features/session_detail/session_detail_screen.dart test/domain/route_playback_cursor_test.dart
git commit -m "perf: avoid route playback prefix allocations"
~~~~

### Task 8: Add bounded local diagnostics and release gates

**Files:**
- Create: \`lib/application/diagnostics/session_diagnostics.dart\`
- Modify: \`lib/features/home/session_controller.dart\`
- Modify: \`lib/platform/location/geolocator_location_engine.dart\`
- Modify: \`docs/DEVICE_VALIDATION.md\`
- Modify: \`docs/TRD.md\`
- Test: \`test/application/session_diagnostics_test.dart\`

**Interfaces:**

~~~~dart
class SessionDiagnosticsSnapshot {
  const SessionDiagnosticsSnapshot({
    required this.callbackCount,
    required this.flushCount,
    required this.averageCallbackInterval,
    required this.lastFlushDuration,
  });

  final int callbackCount;
  final int flushCount;
  final Duration? averageCallbackInterval;
  final Duration? lastFlushDuration;
}
~~~~

- [ ] **Step 1: Write test**

~~~~dart
test('diagnostics compute intervals without retaining raw samples', () {
  // Record three timestamps and one flush; assert count, average, and bounded memory.
});
~~~~

- [ ] **Step 2: Run and verify failure**

Run: \`flutter test --no-pub test/application/session_diagnostics_test.dart\`

Expected: FAIL because diagnostics do not exist.

- [ ] **Step 3: Implement**

Reset counters at session start. Expose them only through a debug/settings surface. Never log raw coordinates or health values and never upload diagnostics.

- [ ] **Step 4: Run complete gates**

Run:

~~~~bash
flutter analyze --no-pub
flutter test --no-pub --concurrency=1
python3 scripts/verify_prd_trd.py
git diff --check
flutter build apk --debug
flutter build ios --no-codesign
bash scripts/run_native_platform_tests.sh
~~~~

Expected: all commands pass; dependency and platform warnings are reviewed.

- [ ] **Step 5: Record device evidence and commit**

Record model, OS, brightness, network, signal, start/end battery, mode, callback count, and flush count in \`docs/DEVICE_VALIDATION.md\`. Do not promote simulator values to physical-device claims.

~~~~bash
git add lib/application/diagnostics/session_diagnostics.dart lib/features/home/session_controller.dart lib/platform/location/geolocator_location_engine.dart docs/DEVICE_VALIDATION.md docs/TRD.md test/application/session_diagnostics_test.dart
git commit -m "feat: add local session performance diagnostics"
~~~~

## Plan Self-Review

- Spec coverage: Tasks 1–2 cover motion/accessibility; Task 3 covers empty-history discovery; Task 4 covers health freshness/coverage/cache; Task 5 covers battery suggestions and native reconfiguration; Task 6 covers controller maintainability; Task 7 covers playback performance; Task 8 covers measurement and release gates.
- No placeholders: every task specifies files, interfaces, test commands, and expected outcomes.
- Type consistency: nullable \`TrackingMode\` suggestion, coordinator signatures, and bounded diagnostics are defined before consumers.
- Scope decomposition: every task is independently testable and commits one focused deliverable; no database rewrite or unrelated feature is included.
