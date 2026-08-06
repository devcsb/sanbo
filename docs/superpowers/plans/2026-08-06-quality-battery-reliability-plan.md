# 산보 배터리·저장 안정성·UX 고도화 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Preserve v0.7.0 data/update compatibility while serializing session persistence, aligning Android location requests with tracking modes, improving permission order, and adding regression coverage for late asynchronous callbacks.

**Architecture:** Add a small, platform-independent `SessionMaintenanceQueue` that coalesces checkpoint requests and can close before finalization/discard. Integrate it with `SessionController` through a session generation token so callbacks from a finished session cannot mutate state or SQLite. Keep existing SQLite schema, backup format, FGS stream, and sampling intervals; make only the Android permission and one-shot request construction more deliberate.

**Tech Stack:** Flutter/Dart 3.12, Riverpod `Notifier`, geolocator 13, permission_handler 11, sqflite 2, flutter_test, Android foreground location service.

## Global Constraints

- Preserve SQLite schema, `.sanbo` backup format, application ID, and existing release-signing/update compatibility.
- Keep tracking targets at battery saver 20s, balanced 8s, high accuracy 4s with existing distance filters.
- Android behavior is the priority; do not change iOS automatic pause policy in this plan.
- Notification failure remains best-effort and must never stop GPS recording.
- Every task ends with a focused test and a small commit; no release tag or GitHub push is created by this plan.

---

### Task 1: Add a serial, coalescing maintenance queue

**Files:**
- Create: `lib/features/home/session_maintenance_queue.dart`
- Create: `test/features/session_maintenance_queue_test.dart`

**Interfaces:**
- Produces `SessionMaintenanceQueue.enqueue(Future<void> Function() task)`, `close()`, `reopen()`, and `isClosed` for `SessionController`.
- `enqueue` runs one task at a time, keeps at most one latest queued task while a task is active, and returns a Future representing the currently active drain.
- `close` prevents queued work from starting and waits for the active task to finish; it never cancels an in-flight SQLite write.

- [ ] **Step 1: Write failing queue tests**

Add tests that use `Completer<void>` gates:

```dart
test('serializes work and coalesces multiple requests', () async {
  final queue = SessionMaintenanceQueue();
  final firstGate = Completer<void>();
  final order = <int>[];

  queue.enqueue(() async {
    order.add(1);
    await firstGate.future;
  });
  queue.enqueue(() async => order.add(2));
  queue.enqueue(() async => order.add(3));

  expect(order, [1]);
  firstGate.complete();
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
  expect(order, [1, 3]);
});

test('close waits for active work and drops queued work', () async {
  final queue = SessionMaintenanceQueue();
  final gate = Completer<void>();
  var ranQueued = false;
  queue.enqueue(() => gate.future);
  queue.enqueue(() async => ranQueued = true);

  final closing = queue.close();
  expect(queue.isClosed, isTrue);
  gate.complete();
  await closing;
  expect(ranQueued, isFalse);
});
```

- [ ] **Step 2: Run the focused tests and confirm the expected failure**

Run: `flutter test --concurrency=1 test/features/session_maintenance_queue_test.dart`

Expected: FAIL because `SessionMaintenanceQueue` does not exist yet.

- [ ] **Step 3: Implement the minimal queue**

Implement a private drain Future, one pending task slot, and a closed flag. The drain must clear `_active` in `finally`, never start `_pendingTask` after `close`, and allow `reopen` only after the active drain is complete.

- [ ] **Step 4: Run focused tests**

Run: `flutter test --concurrency=1 test/features/session_maintenance_queue_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/home/session_maintenance_queue.dart test/features/session_maintenance_queue_test.dart
git commit -m "Add serialized session maintenance queue"
```

### Task 2: Integrate queue and generation guards into session lifecycle

**Files:**
- Modify: `lib/features/home/session_controller.dart`
- Modify: `test/features/session_flow_test.dart`
- Modify: `test/features/session_guard_flow_test.dart`

**Interfaces:**
- `SessionController` owns one `SessionMaintenanceQueue`, `_sessionGeneration`, and `_endingSession`.
- `_runMaintenance()` enqueues a task that captures the current generation and checks it before flush and guard evaluation.
- `stop()` and `discardActive()` close the queue before waiting, then perform their final operation without reopening it.

- [ ] **Step 1: Add regression tests for lifecycle boundaries**

Extend the existing fake repository/location test setup with scenarios that start a session, trigger background/checkpoint work, then stop or discard. Assert that completed sessions have one logical sample per emitted fix and discarded sessions have no active row or samples. Add a test that a guard limit schedules auto-stop after maintenance returns rather than awaiting `stop()` from inside the maintenance task.

- [ ] **Step 2: Run the focused tests and record failures**

Run: `flutter test --concurrency=1 test/features/session_flow_test.dart test/features/session_guard_flow_test.dart`

Expected: the new concurrency assertions fail or expose the current unguarded path before implementation.

- [ ] **Step 3: Integrate the queue**

Import `session_maintenance_queue.dart`; replace `_maintenanceRunning` with the queue. Make `_runMaintenance()` enqueue one task and use a captured generation. Keep `_flushPendingSamples` as the only method that inserts checkpoint samples.

- [ ] **Step 4: Guard late callbacks and stop re-entry**

Increment the generation and set `_endingSession` before cancelling subscriptions in `stop()`/`discardActive()`. Await `queue.close()`, flush remaining samples only from the closing operation, and prevent `_onSample`, stream errors, first-fix watchdog, and maintenance guard evaluation from mutating state when the generation is stale or ending.

For stationary/duration limit events, schedule `_autoStop` with `unawaited` after the maintenance task returns; do not await `stop()` from inside the queue drain.

- [ ] **Step 5: Reopen only for a new/resumed tracking session**

At the beginning of a valid new or recovery-resume `start()`, clear `_endingSession`, increment the generation, and call `queue.reopen()`. Keep the queue closed while a failed stop remains in recovery mode.

- [ ] **Step 6: Run focused tests and the full controller suite**

Run: `flutter test --concurrency=1 test/features/session_flow_test.dart test/features/session_guard_flow_test.dart test/features/session_maintenance_queue_test.dart`

Expected: PASS with no duplicate/revived samples and no deadlock at automatic limits.

- [ ] **Step 7: Commit**

```bash
git add lib/features/home/session_controller.dart test/features/session_flow_test.dart test/features/session_guard_flow_test.dart
git commit -m "Serialize session finalization and block late callbacks"
```

### Task 3: Align Android permission flow and one-shot location settings

**Files:**
- Modify: `lib/platform/location/geolocator_location_engine.dart`
- Create: `test/platform/geolocator_location_engine_policy_test.dart`

**Interfaces:**
- Keep `LocationEngine` unchanged.
- Add private helpers in `GeolocatorLocationEngine` that build Android one-shot settings from the current `TrackingMode` and a `forceLocationManager` flag.

- [ ] **Step 1: Add policy-level tests**

Test the extracted policy/helper values for all three modes: accuracy mapping, target interval, distance filter, and high-accuracy-only CPU wake behavior. Add a source-independent test for the permission flow policy object if needed rather than mocking static geolocator calls.

- [ ] **Step 2: Run focused tests and confirm the new policy is absent**

Run: `flutter test --concurrency=1 test/platform/geolocator_location_engine_policy_test.dart`

Expected: FAIL until the helper/policy is implemented.

- [ ] **Step 3: Reorder permission requests**

Check service and location permission first. Return denied/deniedForever/unknown without requesting notifications. Only after `_mapPermission(p) == granted` and on Android, call `_requestNotificationPermission()`. Preserve best-effort exception handling.

- [ ] **Step 4: Use mode-aware Android settings for seed/fallback**

Create Android one-shot `AndroidSettings` with the current accuracy, distance filter, interval, foreground notification config, CPU wake policy, `forceLocationManager`, and a short time limit. Use matching Apple/generic settings on other platforms without changing iOS pause behavior. Pass `forceLocationManager: true` when the fallback watchdog requests a seed.

- [ ] **Step 5: Run focused tests and analyze**

Run: `flutter test --concurrency=1 test/platform/geolocator_location_engine_policy_test.dart` and `flutter analyze`.

Expected: PASS and no analyzer issues.

- [ ] **Step 6: Commit**

```bash
git add lib/platform/location/geolocator_location_engine.dart test/platform/geolocator_location_engine_policy_test.dart
git commit -m "Align Android permission and seed requests with tracking mode"
```

### Task 4: Harden UI state copy and regression coverage

**Files:**
- Modify: `lib/features/home/home_screen.dart`
- Modify: `lib/features/settings/settings_screen.dart`
- Modify: `test/features/ux_home_recovery_test.dart`
- Modify: `test/features/ux_settings_safety_test.dart`
- Modify: `docs/QUALITY_REVIEW_0.7.md`

**Interfaces:**
- Preserve existing routes and settings labels.
- Add only copy/state guards needed to distinguish first-fix waiting, active recording, auto-stop warning, and retryable save failure.

- [ ] **Step 1: Add failing UI assertions**

Extend existing widget/source tests to assert that first-fix waiting has actionable copy, recovery save remains enabled only when not busy, data management remains disabled during a session, and auto-stop warning copy retains the continue action.

- [ ] **Step 2: Implement minimal UI changes**

Keep the existing calm layout and touch targets. Ensure the current state message is not replaced by a stale async callback and that save failure keeps the recovery CTA visible. Do not add a new tab or change navigation.

- [ ] **Step 3: Run UX tests**

Run: `flutter test --concurrency=1 test/features/ux_home_recovery_test.dart test/features/ux_settings_safety_test.dart test/features/session_guard_flow_test.dart`

Expected: PASS.

- [ ] **Step 4: Update quality review findings**

Document the resolved maintenance race, permission order, mode-aware seed settings, and remaining real-device battery measurement gap in `docs/QUALITY_REVIEW_0.7.md`.

- [ ] **Step 5: Commit**

```bash
git add lib/features/home/home_screen.dart lib/features/settings/settings_screen.dart test/features/ux_home_recovery_test.dart test/features/ux_settings_safety_test.dart docs/QUALITY_REVIEW_0.7.md
git commit -m "Polish tracking state feedback and update quality review"
```

### Task 5: Run release-grade verification and handoff

**Files:**
- Modify only if verification exposes a real issue: files from Tasks 1–4.
- No release tag or GitHub push in this plan.

- [ ] **Step 1: Run formatting and static checks**

Run: `dart format --output=none --set-exit-if-changed lib test` and `flutter analyze`.

Expected: no formatting changes required and no analyzer issues.

- [ ] **Step 2: Run the entire test suite**

Run: `flutter test --concurrency=1`.

Expected: all existing and new tests pass.

- [ ] **Step 3: Build Android debug APK**

Run: `flutter build apk --debug`.

Expected: exit 0 and a debug APK is produced.

- [ ] **Step 4: Build Android release split APKs when local key.properties is present**

Run: `flutter build apk --release --split-per-abi`.

Expected: three ABI APKs build successfully; if signing configuration is absent, report the intentional guard failure without changing the repository.

- [ ] **Step 5: Re-check worktree and summarize evidence**

Run: `git diff --check`, `git status --short --branch`, and inspect the staged/committed diff. Report test counts, build outputs, and any remaining real-device-only checks.
