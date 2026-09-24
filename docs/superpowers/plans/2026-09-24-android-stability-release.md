# Android Stability and Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Correct completed-walk speed/pace semantics, close the remaining Android location and Health Connect stability gaps, review the existing automatic route exclusion changes, and produce a release candidate with evidence-based deployment gates.

**Architecture:** Keep live speed in the active-session controller, but derive completed-session speed and `/km` pace from persisted trusted distance and moving time through one pure domain helper. Keep location quality and Health Connect platform boundaries isolated, and preserve raw samples plus reversible route exclusions. Release engineering remains a separate gate so a signed artifact can be verified without claiming physical-device coverage that was not run.

**Tech Stack:** Flutter/Dart, Riverpod, sqflite, geolocator, Android Kotlin, Health Connect Jetpack client, Flutter unit/widget/integration tests, Android Gradle release builds.

**Spec:** `docs/superpowers/specs/2026-09-09-android-location-health-stabilization-design.md`

## Global Constraints

- Active-session `속도` remains a current live speed; completed-session `평균 이동속도` is `totalDistanceM / movingTimeS`.
- Completed `/km` is derived from the same average movement speed and never from the last provider `speedMps`.
- Invalid or unavailable distance/time yields no fabricated pace or speed value.
- Raw location samples remain auditable; route exclusions remain reversible.
- Android reduced/approximate location must not start a route recording.
- Health Connect settings navigation belongs to the native Android adapter; Flutter does not hard-code platform actions.
- No physical Android stability claim is made without a connected device run.
- Existing user modifications in the working tree are preserved and reviewed before release.

## Review Focus

- A completed record with a stale or provider-derived `avgSpeedMps` must display the canonical distance/time average.
- Zero moving time, zero distance, missing fields, and non-finite values must not produce a misleading `/km` value.
- Automatic high-speed exclusion must not silently erase a user correction or make a duplicate exclusion.
- Android 13/provider and Android 14+/framework Health Connect settings paths must fail safely when unavailable.
- A dirty tree, wrong version, wrong signing certificate, or absent Android device must block or qualify release claims.

### Task 1: Canonical completed movement speed

**Files:**
- Create: `lib/domain/services/completed_walk_metrics.dart`
- Modify: `lib/features/session_detail/session_detail_screen.dart`
- Modify: `lib/domain/services/session_export.dart`
- Modify: `lib/domain/services/walk_stats.dart`
- Test: `test/domain/completed_walk_metrics_test.dart`
- Test: `test/features/ux_history_detail_widget_test.dart`
- Test: `test/domain/walk_stats_export_test.dart`

**Interfaces:**
- Produces `double? completedAverageSpeedMps({required double? totalDistanceM, required int? movingTimeS})`.
- Consumers use this value for completed-session speed and `pacePerKmLabel`; active-session live speed remains unchanged.

- [ ] Step 1: Add failing pure-Dart tests for distance/time calculation, stale persisted speed independence, zero/invalid input, and pace derivation.
- [ ] Step 2: Run `flutter test --no-pub --concurrency=1 test/domain/completed_walk_metrics_test.dart` and confirm the new helper/import fails before production implementation.
- [ ] Step 3: Implement the minimal finite/non-negative helper and route completed UI/export through it.
- [ ] Step 4: Add a detail widget regression fixture whose stored `avgSpeedMps` disagrees with distance/moving time and assert the displayed value follows distance/moving time.
- [ ] Step 5: Run focused tests, then `flutter test --no-pub --concurrency=1 test/domain/completed_walk_metrics_test.dart test/domain/walk_stats_export_test.dart test/features/ux_history_detail_widget_test.dart`.
- [ ] Step 6: Commit only the task files with `fix: 완료 산책 평균 이동속도 기준 통일`.

### Task 2: Location session-boundary and resume hardening

**Files:**
- Modify: `lib/platform/location/geolocator_location_engine.dart`
- Modify: `lib/features/home/session_controller.dart`
- Test: `test/platform/geolocator_location_engine_policy_test.dart`
- Test: `test/features/session_flow_test.dart`

**Interfaces:**
- The engine evaluates emitted samples with the active session start when available.
- Lifecycle resume rechecks permission/precision state before recording continues.

- [ ] Step 1: Add failing tests for a pre-session cached fix being filtered at the engine boundary and reduced accuracy becoming visible after resume.
- [ ] Step 2: Run the focused tests and confirm failure.
- [ ] Step 3: Pass the session boundary into engine quality evaluation and refresh permission state on resume without changing FGS cleanup.
- [ ] Step 4: Run focused location/controller tests and the full Flutter suite.
- [ ] Step 5: Commit with `fix: 세션 경계와 재개 위치 상태 재검증`.

### Task 3: Health Connect action and capability regression hardening

**Files:**
- Modify: `android/app/src/main/kotlin/com/sanbo/app/MainActivity.kt`
- Modify: `lib/platform/activity/health_connect_settings.dart`
- Test: `android/app/src/test/kotlin/com/sanbo/app/MainActivityTest.kt`
- Test: `test/platform/health_connect_settings_test.dart`
- Test: `test/features/daily_activity_provider_test.dart`

**Interfaces:**
- Native code remains responsible for SDK status, managed-data intent, SDK-provided settings action, and safe fallback.
- Flutter receives only a boolean result and refreshes health state on resume.

- [ ] Step 1: Add failing native and Flutter tests for managed-data intent preference, provider/framework fallback, unavailable intent, and cache invalidation on resume.
- [ ] Step 2: Run Android unit and focused Flutter tests and confirm failure.
- [ ] Step 3: Replace brittle action assumptions with the supported SDK action lookup/fallback while retaining safe false results.
- [ ] Step 4: Run Android unit tests, focused Flutter tests, analyzer, and the full Flutter suite.
- [ ] Step 5: Commit with `fix: Health Connect 설정 진입 fallback 안정화`.

### Task 4: Automatic route exclusion semantic review

**Files:**
- Modify: `lib/domain/services/automatic_route_exclusion.dart`
- Modify: `lib/data/walk_repository.dart`
- Modify: `lib/features/session_detail/session_detail_screen.dart`
- Test: `test/domain/automatic_route_exclusion_test.dart`
- Test: `test/data/walk_repository_test.dart`
- Test: `test/features/ux_history_detail_widget_test.dart`

**Interfaces:**
- Automatic exclusion remains an explicit, reversible data-layer operation.
- User restoration and label edits cannot recreate or leave behind a contradictory automatic exclusion without a deliberate policy decision.

- [ ] Step 1: Add failing tests for fast walking false-positive boundaries, restore/relabel behavior, duplicate prevention, and raw-sample preservation.
- [ ] Step 2: Run focused tests and confirm failure.
- [ ] Step 3: Implement the smallest policy correction consistent with existing product copy and reversible history semantics.
- [ ] Step 4: Run focused repository/widget tests and the full suite.
- [ ] Step 5: Commit with `fix: 자동 경로 제외 복원 의미 보강`.

### Task 5: Release candidate hygiene and artifact verification

**Files:**
- Modify: `pubspec.yaml`
- Modify: `docs/PRD.md`
- Modify: `docs/TRD.md`
- Modify: `scripts/run_quality_loop.sh`
- Create: `docs/release/2026-09-24-android-release.md`
- Test/verify: release scripts and Gradle outputs

**Interfaces:**
- Version, changelog, signing, target SDK, artifact checksum, and device-validation status are documented together.

- [ ] Step 1: Add failing release metadata checks for the selected version and required Android artifact evidence.
- [ ] Step 2: Run the checks and confirm they fail against the current `0.9.0+14` candidate or missing evidence.
- [ ] Step 3: Bump the release version, clean committed-doc whitespace, and extend the release gate without printing secrets.
- [ ] Step 4: Run analyzer, full Flutter tests, PRD/TRD verification, signed AAB/APK builds, APK signature/target/version checks, and checksum generation.
- [ ] Step 5: Commit release metadata and scripts with `chore: Android 릴리즈 후보 게이트 정리`.

### Task 6: Deployment

**Files:**
- Release artifacts generated under `build/app/outputs/`
- Git tag and remote release metadata only after the selected deployment target is confirmed

- [ ] Step 1: Verify the final clean-tree state, release commit, artifact checksums, and exact signing certificate.
- [ ] Step 2: Publish the selected target. GitHub Release requires authenticated `gh` or an equivalent configured remote; Google Play Internal Testing requires an authenticated Play Console upload path and app access.
- [ ] Step 3: Record the published URL/version and distinguish uploaded artifacts from unavailable physical-device evidence.
- [ ] Step 4: If deployment credentials are absent, stop at a verified signed artifact and report the exact external credential needed rather than claiming publication.
