# Architecture, Battery, and UX Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Harden the existing local-first walk recorder so concurrent writes, crash recovery, five-hour safety limits, detail playback, and daily activity presentation remain correct and battery-conscious, with an explicit Health Connect/HealthKit read path.

**Architecture:** Keep the current Riverpod and repository seams while extracting only deterministic policies and transactional boundaries that can be tested without a device. SQLite remains the source of truth for sessions, samples, and windows; GPS remains an explicit-session adapter, while a future health adapter exposes daily steps as a separate provenance-bearing stream. UI providers stay read-only and map playback separates static geometry from the moving cursor.

**Tech Stack:** Flutter/Dart 3.12, Riverpod 2.6, sqflite 2.4, flutter_map 7, geolocator 13, Flutter widget/unit tests, sqflite_common_ffi.

**Spec:** `docs/superpowers/specs/2026-08-29-architecture-battery-ux-hardening-design.md`

## Global Constraints

- Preserve local-first storage and existing user data; schema migrations must be forward-only and recoverable.
- GPS collection is allowed only during an explicitly started walk; daily health steps must never be inferred from GPS or merged into route distance.
- Battery profiles remain saver `20s/10m`, balanced `8s/5m`, high accuracy `4s/2m` with no wakelock except high accuracy.
- A stationary warning is emitted at 20 minutes and automatic stop at 30 minutes; duration warning is emitted at 4h45m and automatic stop at 5 hours.
- Warning and limit deadlines must survive process death; denied, unavailable, and zero health data are distinct states.
- User copy remains neutral, non-diagnostic, private, and does not introduce streak/leaderboard pressure.
- Every changed behavior has a deterministic unit/widget test; run `flutter analyze --no-pub`, `flutter test --no-pub --concurrency=1`, and `python3 scripts/verify_prd_trd.py` before completion.

## File Map

- Modify `lib/data/app_database.dart`: schema version 6, one-active-session and sample idempotency constraints, persisted safety deadlines, and migration deduplication.
- Modify `lib/data/walk_repository.dart`: transaction wrappers, conflict-safe inserts, update-count checks, and a single aggregate read for session detail.
- Modify `lib/domain/models/walk_session.dart`: persisted safety deadline fields.
- Create `lib/domain/models/session_error_code.dart`: stable controller/UI error categories.
- Create `lib/domain/services/session_deadline.dart`: pure deadline calculation/evaluation shared by live and recovery paths.
- Modify `lib/features/home/session_controller.dart`: persist deadlines at start, evaluate them during samples/maintenance/foreground recovery, and expose typed safety outcomes through existing state.
- Modify `lib/features/session_detail/session_detail_screen.dart`: make the detail provider read-only and move place enrichment to an explicit command.
- Modify `lib/shared/widgets/route_map.dart`: cache static `LatLng` geometry and keep playback cursor layers dynamic.
- Modify `lib/features/history/history_providers.dart`: refresh local date selection on resume/date rollover.
- Create `lib/data/activity_data_source.dart`: source/provenance contract for Health Connect/HealthKit daily steps without coupling GPS and health data; `DailyActivitySnapshot` gains `Map<DateTime, DailyStepSnapshot> stepsByDate`.
- Modify `lib/features/history/daily_activity_panel.dart` and its providers: present steps, GPS walk totals, and coverage/permission state as separate cards.
- Extend `test/data/app_database_migration_test.dart`, `test/data/walk_repository_test.dart`, `test/features/session_guard_flow_test.dart`, `test/features/ux_history_detail_widget_test.dart`, and create `test/domain/session_deadline_test.dart` and `test/data/activity_data_source_test.dart`.

### Task 1: Make session and sample persistence crash-safe and idempotent

**Files:**
- Modify: `lib/data/app_database.dart:5-185`
- Modify: `lib/data/walk_repository.dart:269-310,382-510,816-950,1129-1135`
- Test: `test/data/app_database_migration_test.dart`
- Test: `test/data/walk_repository_test.dart`

**Interfaces:**
- Produces `schemaVersion == 5` for persistence constraints with `idx_sessions_single_active` and a unique location-sample key `(session_id, ts, lat, lon)`; Task 2 advances the schema to v6 for deadline columns.
- `WalkRepository.insertSamples(String, List<LocationSample>)` becomes retry-safe by using `ConflictAlgorithm.ignore`.
- `WalkRepository.replaceSamples` and `replaceWindows` become single-transaction delete-and-reinsert operations.
- `WalkRepository.finalizeSession` and `completeSession` throw `StateError` when the session update affects anything other than exactly one row.

- [ ] **Step 1: Write migration and repository failing tests**

Add tests that open a v4 fixture and assert it upgrades to v5, duplicate active-session insertion fails, duplicate sample retries leave one row, and a failed transactional replacement leaves the original rows intact.

```dart
test('v4 database upgrades with one-active and sample idempotency indexes', () async {
  final path = await createV4Fixture();
  addTearDown(() => databaseFactory.deleteDatabase(path));
  final db = await openAppDatabase(path: path);
  final indexes = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'index' AND name IN "
    "('idx_sessions_single_active', 'idx_samples_idempotency')",
  );
  expect(indexes.map((row) => row['name']), containsAll([
    'idx_sessions_single_active',
    'idx_samples_idempotency',
  ]));
});

test('retrying the same sample batch is idempotent', () async {
  final repo = await openTestRepository();
  addTearDown(repo.close);
  final session = await repo.startSession();
  final sample = fixtureSample(session.startedAt);
  await repo.insertSamples(session.id, [sample]);
  await repo.insertSamples(session.id, [sample]);
  expect((await repo.getSamples(session.id)), hasLength(1));
});
```

- [ ] **Step 2: Run the focused tests and verify failure**

Run `flutter test --no-pub test/data/app_database_migration_test.dart test/data/walk_repository_test.dart --concurrency=1`.

Expected: FAIL because the current schema is v4, there is no idempotency index, and sample inserts use the default conflict algorithm.

- [ ] **Step 3: Add the v5 migration and fresh-install schema constraints**

Set `schemaVersion` to `5` for this task. In `onUpgrade`, for `oldVersion < 5`, remove duplicate samples with a `DELETE ... WHERE id NOT IN (SELECT MIN(id) ... GROUP BY session_id, ts, lat, lon)` statement, then create:

```sql
CREATE UNIQUE INDEX IF NOT EXISTS idx_sessions_single_active
ON sessions(status) WHERE status = 'active';
CREATE UNIQUE INDEX IF NOT EXISTS idx_samples_idempotency
ON location_samples(session_id, ts, lat, lon);
```

Create both indexes in `_createSchema` as well. Do not rewrite or delete user sessions during migration.

- [ ] **Step 4: Make repository writes transactional and conflict-safe**

Use `ConflictAlgorithm.ignore` in both `insertSamples` and the sample batch inside `finalizeSession`. Wrap `replaceSamples`, `replaceWindows`, and `deleteAll` in `_db.transaction`. In `finalizeSession`, check the `txn.update` result and throw `StateError('산책 완료 상태를 저장하지 못했습니다')` unless it equals one. In `completeSession`, perform the update in a transaction and check the result. Convert the active-session unique-index `DatabaseException` in `startSession` to the existing Korean “이미 진행 중…” state error so the UI does not expose SQL text.

- [ ] **Step 5: Run focused tests and commit**

Run the focused command from Step 2, then `git diff --check`.

Expected: PASS with migration, duplicate retry, transactional rollback, and all pre-existing repository tests.

Commit with `git add lib/data/app_database.dart lib/data/walk_repository.dart test/data/app_database_migration_test.dart test/data/walk_repository_test.dart && git commit -m "fix: make walk persistence transactional and idempotent"`.

### Task 2: Persist safety deadlines and make five-hour/stationary guards recoverable

**Files:**
- Modify: `lib/domain/models/walk_session.dart`
- Create: `lib/domain/services/session_deadline.dart`
- Modify: `lib/data/app_database.dart`
- Modify: `lib/data/walk_repository.dart`
- Modify: `lib/features/home/session_controller.dart`
- Test: `test/domain/session_deadline_test.dart`
- Test: `test/features/session_guard_flow_test.dart`

**Interfaces:**
- `SessionDeadlines` is an immutable value with `stationaryWarningAt`, `stationaryLimitAt`, `durationWarningAt`, and `durationLimitAt`.
- `SessionDeadlinePolicy.calculate(DateTime startedAt, SessionGuardPolicy policy) -> SessionDeadlines` uses absolute UTC instants.
- `SessionDeadlinePolicy.evaluate(SessionDeadlines, DateTime now) -> SessionDeadlineEvent` returns the highest-priority due event without mutating state.

- [ ] **Step 1: Add pure deadline failing tests**

Create `test/domain/session_deadline_test.dart` covering exact boundaries, UTC/local input normalization, warning-before-limit priority, and no event before the deadline.

```dart
test('evaluates the five-hour limit at the exact instant', () {
  final started = DateTime.utc(2026, 8, 29, 0);
  final deadlines = SessionDeadlinePolicy.calculate(
    started,
    const SessionGuardPolicy(),
  );
  expect(
    SessionDeadlinePolicy.evaluate(deadlines, started.add(const Duration(hours: 5))),
    SessionDeadlineEvent.durationLimit,
  );
});
```

- [ ] **Step 2: Run the new test to verify failure**

Run `flutter test --no-pub test/domain/session_deadline_test.dart --concurrency=1`.

Expected: FAIL because the policy/value types do not exist.

- [ ] **Step 3: Implement the pure deadline policy and persist fields**

Advance `schemaVersion` to `6`. Add nullable ISO-8601 columns to `sessions` in the v6 migration (`stationary_warning_at`, `stationary_limit_at`, `duration_warning_at`, `duration_limit_at`), migrate existing active sessions by calculating deadlines from `started_at`, and map them in `_sessionFromRow`/`_sessionToRow`. Add the same columns to fresh installs. Extend `WalkSession.copyWith` without changing existing call sites. Implement the pure policy with UTC instants and a deterministic event enum.

- [ ] **Step 4: Integrate deadlines into start, maintenance, foreground, and cold recovery**

At `SessionController.start`, calculate and persist deadlines before arming the location engine. During `_onSample`, `_runMaintenance`, `setAppForeground(true)`, and restoration, evaluate persisted deadlines with `_clock()`. Publish an existing `SessionWarning` once per kind; on a limit call `_autoStop` with a neutral completion notice. Keep the existing `SessionGuard` for movement/high-speed continuity, but do not rely on a Dart timer alone for the five-hour limit. Reset issued flags only after an explicit continue action.

- [ ] **Step 5: Add recovery/duplicate-event tests and run them**

Add tests that kill/recreate the provider after 4h46m and still show the duration warning, that a second maintenance pass does not duplicate a notification, and that the 5h boundary finalizes once. Run `flutter test --no-pub test/domain/session_deadline_test.dart test/features/session_guard_flow_test.dart --concurrency=1`.

- [ ] **Step 6: Commit the safety deadline slice**

Run `flutter analyze --no-pub` and commit with `git add lib/domain/models/walk_session.dart lib/domain/services/session_deadline.dart lib/data/app_database.dart lib/data/walk_repository.dart lib/features/home/session_controller.dart test/domain/session_deadline_test.dart test/features/session_guard_flow_test.dart && git commit -m "feat: persist recoverable session safety deadlines"`.

### Task 3: Remove read-provider side effects and optimize detail playback rendering

**Files:**
- Modify: `lib/data/walk_repository.dart`
- Modify: `lib/features/session_detail/session_detail_screen.dart:29-105,800-1060`
- Modify: `lib/shared/widgets/route_map.dart:9-150`
- Test: `test/features/place_memory_flow_test.dart`
- Test: `test/features/route_playback_flow_test.dart`
- Test: `test/features/ux_history_detail_widget_test.dart`

**Interfaces:**
- `sessionDetailProvider` performs only reads plus an in-memory display overlay for nearby remembered places; it never calls `attachPlaceToWindows`.
- Existing explicit editor commands (`rememberPlaceForWindows`, `deletePlace`) remain the only persistence paths for place links; no new repository command is required for the overlay.
- `RouteMap` receives a stable `RouteMapGeometry` for static layers and a nullable `RoutePlaybackCursor` for the dynamic marker/highlight.

- [ ] **Step 1: Write a provider side-effect regression test**

Use a spy repository in `test/features/place_memory_flow_test.dart` that counts `attachPlaceToWindows` calls. Read `sessionDetailProvider(id).future` twice without invoking a UI command and assert the count remains zero.

- [ ] **Step 2: Run the regression test to verify failure**

Run `flutter test --no-pub test/features/place_memory_flow_test.dart --concurrency=1`.

Expected: FAIL because the current provider enriches and writes while loading.

- [ ] **Step 3: Split read aggregation from explicit enrichment**

Keep the existing parallel session/sample/window/exclusion reads, remove the provider's `attachPlaceToWindows` call, and apply nearby remembered places with `MinuteWindow.copyWithPlace` in memory. The existing “장소 기억” editor remains the explicit write command and invalidates the provider only after it succeeds.

- [ ] **Step 4: Cache static map geometry and keep playback dynamic**

Create an immutable `RouteMapGeometry` that converts route fragments to `LatLng` once. Memoize it in `SessionDetailScreen` when the session id or route fragments change. `RouteMap` should reuse the geometry for `PolylineLayer` and only rebuild `MarkerLayer`/highlight polylines when playback progress or selection changes. Do not create a new `LatLng` for every timer tick.

- [ ] **Step 5: Add playback and large-route tests**

Extend `test/features/route_playback_flow_test.dart` with a 4,500-point route and assert advancing playback does not change the static geometry identity. Extend the widget test to assert the marker label changes while the base polyline remains present. Run the three focused test files.

- [ ] **Step 6: Commit detail performance changes**

Run `flutter analyze --no-pub` and commit with `git add lib/data/walk_repository.dart lib/features/session_detail/session_detail_screen.dart lib/shared/widgets/route_map.dart test/features/place_memory_flow_test.dart test/features/route_playback_flow_test.dart test/features/ux_history_detail_widget_test.dart && git commit -m "perf: separate detail reads from route playback updates"`.

### Task 4: Make daily activity date handling explicit and add a health-source seam

**Files:**
- Create: `lib/data/activity_data_source.dart`
- Modify: `lib/features/history/history_providers.dart`
- Modify: `lib/features/history/daily_activity_panel.dart`
- Test: `test/data/activity_data_source_test.dart`
- Test: `test/data/walk_repository_test.dart`
- Test: `test/features/daily_activity_provider_test.dart`

**Interfaces:**
- `ActivitySourceKind { healthConnect, healthKit, unavailable, denied }`.
- `DailyStepSnapshot { date, steps, source, coverage, recordedAt }`; `steps == null` means denied/unavailable, while `0` is a valid reported value.
- `ActivityDataSource.readDailySteps({required DateTime startDate, required DateTime endDateExclusive}) -> Future<List<DailyStepSnapshot>>`.
- `UnavailableActivityDataSource` is the default adapter and never requests permission or returns fabricated zeroes.

- [ ] **Step 1: Write source/provenance and date-rollover tests**

Assert denied/unavailable steps remain null, zero remains zero, and `dailyActivityProvider` changes its week end after a simulated foreground resume crossing midnight. Add a fake source that returns cumulative daily totals and verify the provider does not add GPS distance to step counts.

- [ ] **Step 2: Run focused tests to verify failure**

Run `flutter test --no-pub test/data/activity_data_source_test.dart test/features/daily_activity_provider_test.dart --concurrency=1`.

Expected: FAIL because the source contract and resume refresh do not exist.

- [ ] **Step 3: Add the source seam and explicit daily aggregate model**

Create the contract and unavailable adapter. Add an `activityDataSourceProvider` override point. In `dailyActivityProvider`, read the source and return both `DailyWalkStats` and `DailyStepSnapshot` keyed by local date; never convert unavailable to 0. Add a platform adapter behind a separate reader interface so permission UX and aggregate query behavior can be tested independently of method channels.

- [ ] **Step 4: Refresh local date state on resume and render separate cards**

Expose a `refreshCurrentLocalDate()` notifier helper, call it from the app lifecycle observer when returning to foreground, and preserve a user-selected historical day unless it was the previous “today” marker. In `daily_activity_panel.dart`, show “걸음 수”, “GPS 산책”, and “데이터 상태” as separate semantic regions with neutral unavailable/permission copy.

- [ ] **Step 5: Run focused tests and commit**

Run `flutter test --no-pub test/data/activity_data_source_test.dart test/features/daily_activity_provider_test.dart test/features/ux_history_detail_widget_test.dart --concurrency=1`, then commit with `git add lib/data/activity_data_source.dart lib/features/history/history_providers.dart lib/features/history/daily_activity_panel.dart test/data/activity_data_source_test.dart test/features/daily_activity_provider_test.dart && git commit -m "feat: separate daily activity source from gps walks"`.

### Task 5: Reduced-motion, typed error presentation, and verification evidence

**Files:**
- Modify: `lib/features/session_detail/session_detail_screen.dart`
- Modify: `lib/features/home/home_screen.dart`
- Modify: `lib/features/home/session_controller.dart`
- Modify: `lib/platform/prefs/app_flags.dart`
- Modify: `docs/PRD.md`, `docs/TRD.md`, `docs/DEVICE_VALIDATION.md`, `docs/QUALITY_REVIEW_0.8.0.md`
- Test: `test/features/ux_home_recovery_test.dart`
- Test: `test/features/ux_history_detail_widget_test.dart`

**Interfaces:**
- `SessionErrorCode` (defined in `lib/domain/models/session_error_code.dart`) is an internal enum mapped to localized copy; UI routing never checks Korean error substrings.
- `AppFlagsStore` writes JSON through a temporary sibling file and atomic rename.

- [ ] **Step 1: Write UX regression tests**

Add a widget test with `MediaQueryData(disableAnimations: true)` and assert route playback reaches the same final marker without waiting for animation. Add a recovery test that injects a typed permission error and asserts the settings CTA appears without relying on message text. Add a flags test that simulates an interrupted write and verifies the previous JSON remains readable.

- [ ] **Step 2: Run focused tests to verify failure**

Run `flutter test --no-pub test/features/ux_home_recovery_test.dart test/features/ux_history_detail_widget_test.dart --concurrency=1`.

Expected: FAIL because the UI currently uses string matching and does not consistently honor reduced motion.

- [ ] **Step 3: Implement reduced-motion and typed error mapping**

Use `MediaQuery.maybeOf(context)?.disableAnimations == true` to set route transition/playback animation durations to `Duration.zero` and avoid decorative scale/fade loops. Add `SessionErrorCode` to the controller’s internal error result, map it to the existing Korean copy, and update `home_screen.dart` to branch on the code. Preserve all existing user-facing messages.

- [ ] **Step 4: Make app flags writes atomic and update docs**

Write encoded flags to `<path>.tmp`, flush/close, then rename over the target; on startup recover a valid temp file if the main file is missing. Update PRD/TRD to name `flutter_map` as the current renderer, correct the trusted-location gap table to 60 seconds, document Health source states, and clearly label physical Galaxy/iPhone battery rows as pending until measured.

- [ ] **Step 5: Run the complete verification loop**

Run:

```bash
flutter analyze --no-pub
flutter test --no-pub --concurrency=1
python3 scripts/verify_prd_trd.py
git diff --check
```

For a physical validation build, record at least a 60-minute balanced-mode session and a 60-minute saver-mode session on one Galaxy and one iPhone, including initial/end battery, screen-on time, GPS samples, auto-stop behavior, and notification delivery. Do not mark those rows passed from emulator data.

- [ ] **Step 6: Commit the verification/documentation slice**

Commit with `git add lib/features/session_detail/session_detail_screen.dart lib/features/home/home_screen.dart lib/features/home/session_controller.dart lib/platform/prefs/app_flags.dart docs/PRD.md docs/TRD.md docs/DEVICE_VALIDATION.md docs/QUALITY_REVIEW_0.8.0.md test/features/ux_home_recovery_test.dart test/features/ux_history_detail_widget_test.dart && git commit -m "chore: harden ux fallbacks and verification evidence"`.

## Self-review checklist

- Spec coverage: Tasks 1–2 cover durable storage, idempotency, and five-hour/stationary safety; Task 3 covers read purity and playback performance; Task 4 covers date rollover and the Health source seam; Task 5 covers reduced motion, typed errors, atomic flags, and evidence/document drift.
- Placeholder scan: no step relies on “later”, “TBD”, or unspecified error handling; all new interfaces and test commands are named.
- Type consistency: `SessionDeadlines`, `SessionDeadlinePolicy`, `DailyStepSnapshot`, `ActivityDataSource`, `RouteMapGeometry`, and `SessionErrorCode` are introduced before consumers and retain existing repository/controller entry points.
- Scope control: the Health Connect/HealthKit adapter is read-only and on-demand; physical battery measurements and store-policy validation remain verification/follow-up work, not simulated in the local test suite.
