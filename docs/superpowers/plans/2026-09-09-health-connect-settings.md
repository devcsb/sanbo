# Android Health Connect Settings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Let Android users open the official app-specific Health Connect permission-management screen and see fresh state after returning.

**Architecture:** Keep the read-only ActivityDataSourceConnector contract and add optional settings and cache capabilities. Flutter knows only capability interfaces. A sanbo/health_connect MethodChannel owns SDK status, app-specific manage-data intent, fallback, and safe launch handling.

**Tech Stack:** Flutter/Dart, Riverpod, health 13.3.2, Android Kotlin, AndroidX Health Connect client 1.2.0-alpha02, JUnit, Flutter tests.

**Spec:** docs/superpowers/specs/2026-09-09-android-location-health-stabilization-design.md

## Global Constraints

- Use HealthConnectClient.getHealthConnectManageDataIntent(context, context.packageName) first.
- Keep Android version differences inside native code.
- Preserve HealthKit, zero-vs-unavailable semantics, on-demand reads, five-minute cache, and GPS/health separation.
- Do not add background sync, write permissions, exercise-route writes, server state, or a second permission model.
- Unavailable or unresolved settings returns false and never crashes.
- Clear source cache and invalidate dailyActivityProvider on app resume.
- Every task is RED, GREEN, refactor, regression test, and focused commit.

## File Map

- Modify lib/data/activity_data_source.dart and lib/platform/activity/health_activity_data_source.dart.
- Create lib/platform/activity/health_connect_settings.dart and test/platform/health_connect_settings_test.dart.
- Modify the history panel, providers, app lifecycle, and their tests.
- Modify MainActivity.kt and app/build.gradle.kts.
- Create the native Health Connect contract test and a verification note.
+

### Task 3: Wire the CTA and refresh on resume

**Files:**
- Modify: lib/features/history/daily_activity_panel.dart
- Modify: lib/features/history/history_providers.dart
- Modify: lib/app.dart
- Modify: test/features/daily_activity_panel_test.dart
- Modify: test/features/daily_activity_provider_test.dart

**Interfaces:**
- Consumes Task 1 capabilities and Task 2 bridge.
- Produces the Android settings CTA and a resume refresh helper.

- [ ] Step 1: Write failing widget/provider tests.

~~~dart
final class SettingsActivitySource
    implements ActivityDataSource,
        ActivityDataSourceConnector,
        ActivityDataSourceSettingsOpener,
        ActivityDataSourceCacheInvalidator {
  var settingsCalls = 0;
  var requestCalls = 0;
  var invalidations = 0;

  @override
  Future<bool> openSettings() async {
    settingsCalls++;
    return true;
  }

  @override
  void invalidateCache() => invalidations++;

  @override
  Future<ActivityAccessState> getAccessState() async =>
      ActivityAccessState.denied;

  @override
  Future<ActivityAccessState> requestAccess() async {
    requestCalls++;
    return ActivityAccessState.connected;
  }

  @override
  Future<List<DailyStepSnapshot>> readDailySteps({
    required DateTime startDate,
    required DateTime endDateExclusive,
  }) async => const [];
}
~~~

Add a widget test that taps Health Connect 설정 열기 and expects settingsCalls == 1 and requestCalls == 0. Add a provider test that calls refreshDailyActivityOnResume(ref) and expects one cache invalidation and an invalidated dailyActivityProvider.

- [ ] Step 2: Run focused tests and confirm missing behavior.

Run: flutter test --no-pub --concurrency=1 test/features/daily_activity_panel_test.dart test/features/daily_activity_provider_test.dart

Expected: FAIL because the optional opener is not exposed and the resume helper does not exist.

- [ ] Step 3: Add the CTA while preserving permission fallback.

Derive the optional opener from activityDataSourceProvider, pass onOpenSettings into the loaded panel and connect button, and when the selected steps value is null with an opener present render the primary Health Connect 설정 열기 action. Keep 건강 데이터 연결 as the secondary fallback that calls requestAccess and invalidates dailyActivityProvider. Sources without the opener retain the current one-button behavior. When openSettings returns false, show Health Connect 설정을 열지 못했어요. 앱 설치 상태를 확인한 뒤 다시 시도해 주세요. and keep the widget recoverable.

- [ ] Step 4: Add resume invalidation.

~~~dart
void refreshDailyActivityOnResume(WidgetRef ref) {
  final source = ref.read(activityDataSourceProvider);
  if (source is ActivityDataSourceCacheInvalidator) {
    source.invalidateCache();
  }
  ref.invalidate(dailyActivityProvider);
}
~~~

Call the helper from SanboApp’s AppLifecycleListener.onResume before refreshCurrentLocalDate(ref). It must not change deliberate week navigation or trigger a permission dialog.

- [ ] Step 5: Run UI/data regressions and analyzer.

~~~bash
dart format lib/features/history/daily_activity_panel.dart lib/features/history/history_providers.dart lib/app.dart test/features/daily_activity_panel_test.dart test/features/daily_activity_provider_test.dart
flutter test --no-pub --concurrency=1 test/features/daily_activity_panel_test.dart test/features/daily_activity_provider_test.dart test/data/activity_data_source_test.dart
flutter analyze --no-pub
~~~

- [ ] Step 6: Commit.

~~~bash
git add lib/features/history/daily_activity_panel.dart lib/features/history/history_providers.dart lib/app.dart test/features/daily_activity_panel_test.dart test/features/daily_activity_provider_test.dart
git commit -m "feat: refresh health state after Android settings"
~~~

### Task 4: Verify and document device limits

**Files:**
- Create: docs/superpowers/verification/2026-09-09-health-connect-settings.md
- Modify docs/DEVICE_VALIDATION.md only if its Android health checklist is incomplete.

- [ ] Step 1: Write a checklist for Android 14 manage-data intent, Android 13-and-lower provider path, absent/update-required provider, unresolved intent, grant, revoke, return from settings, valid zero steps, and unchanged iOS HealthKit. State that empty adb devices output means no physical result.
- [ ] Step 2: Run full verification.

~~~bash
flutter test --no-pub --concurrency=1
flutter analyze --no-pub
git diff --check
cd android && ./gradlew :app:testDebugUnitTest :app:assembleDebug
adb devices
~~~

Expected: all automated checks PASS; device output is availability evidence only.

- [ ] Step 3: Record command output, test counts, commit ids, and manual status without raw step totals, account identifiers, health screenshots, or coordinates.
- [ ] Step 4: Commit the evidence.

~~~bash
git add docs/superpowers/verification/2026-09-09-health-connect-settings.md docs/DEVICE_VALIDATION.md
git commit -m "test: record Health Connect settings verification"
~~~

## Plan Self-Review

- Spec coverage: manage-data intent priority, Android-version fallback, safe unavailable handling, optional capabilities, resume invalidation, iOS preservation, and device limits are covered by Tasks 1 through 4.
- Placeholder scan: every step has concrete interfaces, test code, commands, and expected results.
- Type consistency: Task 1 defines capability interfaces; Task 2 defines the bridge used by the source factory; Task 3 defines the resume helper used by app.dart; Task 4 consumes completed artifacts.
- Regression boundary: commits stage only this plan’s files and leave automatic route-exclusion changes unstaged.

+

### Task 1: Add optional settings and cache capabilities

**Files:**
- Modify: lib/data/activity_data_source.dart
- Modify: lib/platform/activity/health_activity_data_source.dart
- Modify: test/data/activity_data_source_test.dart

**Interfaces:**
- Consumes the existing connector and HealthActivityDataSource cache.
- Produces ActivityDataSourceSettingsOpener.openSettings and ActivityDataSourceCacheInvalidator.invalidateCache.

- [ ] Step 1: Write the failing capability test.

~~~dart
test('health source opens settings and invalidates its cache', () async {
  final reader = _FakeDailyStepsReader(
    sourceKind: ActivitySourceKind.healthConnect,
    totals: {DateTime(2026, 8, 1): 100},
  );
  var opened = 0;
  final source = HealthActivityDataSource(
    reader,
    settingsOpener: () async {
      opened++;
      return true;
    },
  );

  await source.readDailySteps(
    startDate: DateTime(2026, 8, 1),
    endDateExclusive: DateTime(2026, 8, 2),
  );
  (source as ActivityDataSourceCacheInvalidator).invalidateCache();
  await (source as ActivityDataSourceSettingsOpener).openSettings();
  await source.readDailySteps(
    startDate: DateTime(2026, 8, 1),
    endDateExclusive: DateTime(2026, 8, 2),
  );

  expect(opened, 1);
  expect(reader.readCalls, 2);
});
~~~

- [ ] Step 2: Run the focused test.

Run: flutter test --no-pub --concurrency=1 test/data/activity_data_source_test.dart

Expected: FAIL because the interfaces and settingsOpener parameter do not exist.

- [ ] Step 3: Add the capability interfaces and safe delegation.

~~~dart
abstract interface class ActivityDataSourceSettingsOpener {
  Future<bool> openSettings();
}

abstract interface class ActivityDataSourceCacheInvalidator {
  void invalidateCache();
}
~~~

Make HealthActivityDataSource implement both interfaces and accept an optional Future<bool> Function()? settingsOpener. openSettings returns false when absent, otherwise awaits the callback and catches platform failures into false. invalidateCache calls the existing private _clearCache. Keep requestAccess cache clearing and leave UnavailableActivityDataSource read-only.

- [ ] Step 4: Run the data-source tests and analyzer.

~~~bash
dart format lib/data/activity_data_source.dart lib/platform/activity/health_activity_data_source.dart test/data/activity_data_source_test.dart
flutter test --no-pub --concurrency=1 test/data/activity_data_source_test.dart
flutter analyze --no-pub
~~~

- [ ] Step 5: Commit.

~~~bash
git add lib/data/activity_data_source.dart lib/platform/activity/health_activity_data_source.dart test/data/activity_data_source_test.dart
git commit -m "feat: add health settings and cache capabilities"
~~~

### Task 2: Implement the native Health Connect settings bridge

**Files:**
- Create: lib/platform/activity/health_connect_settings.dart
- Create: test/platform/health_connect_settings_test.dart
- Modify: lib/platform/activity/health_activity_data_source.dart
- Modify: android/app/src/main/kotlin/com/sanbo/sanbo/MainActivity.kt
- Modify: android/app/build.gradle.kts
- Create: android/app/src/test/kotlin/com/sanbo/sanbo/HealthConnectIntentContractTest.kt

**Interfaces:**
- Consumes Task 1 settings callback and the existing MainActivity channel pattern.
- Produces HealthConnectSettingsBridge.openSettings and native method openSettings returning a boolean.

- [ ] Step 1: Write failing native and Dart contract tests.

~~~kotlin
@Test
fun availableSdkSelectsManageDataBeforeGenericSettings() {
    assertEquals(
        HealthConnectIntentKind.MANAGE_DATA,
        healthConnectIntentKind(sdkAvailable = true, manageIntentResolvable = true),
    )
}

@Test
fun unresolvableManageDataFallsBackToSettingsAction() {
    assertEquals(
        HealthConnectIntentKind.SETTINGS_ACTION,
        healthConnectIntentKind(sdkAvailable = true, manageIntentResolvable = false),
    )
}

@Test
fun unavailableProviderReportsFalse() {
    assertEquals(false, shouldReportSettingsOpened(false, false))
}
~~~

~~~dart
test('bridge returns native boolean result', () async {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('sanbo/health_connect'),
        (call) async => true,
      );
  addTearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('sanbo/health_connect'),
          null,
        ),
  );

  expect(await const HealthConnectSettingsBridge().openSettings(), isTrue);
});
~~~

- [ ] Step 2: Run the new tests.

~~~bash
flutter test --no-pub --concurrency=1 test/platform/health_connect_settings_test.dart
cd android && ./gradlew :app:testDebugUnitTest --tests com.sanbo.sanbo.HealthConnectIntentContractTest
~~~

Expected: FAIL because the bridge, native helpers, and channel handler do not exist.

- [ ] Step 3: Implement the Flutter bridge and factory wiring.

~~~dart
import 'package:flutter/services.dart';

class HealthConnectSettingsBridge {
  const HealthConnectSettingsBridge({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('sanbo/health_connect');

  final MethodChannel _channel;

  Future<bool> openSettings() async {
    try {
      return await _channel.invokeMethod<bool>('openSettings') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
~~~

In createPlatformHealthActivityDataSource, pass the bridge callback only on Android. Leave iOS HealthKit without the optional opener.

- [ ] Step 4: Implement native status, intent priority, and safe handling.

~~~kotlin
dependencies {
    implementation("androidx.health.connect:connect-client:1.2.0-alpha02")
}
~~~

~~~kotlin
enum class HealthConnectIntentKind { MANAGE_DATA, SETTINGS_ACTION }

internal fun healthConnectIntentKind(
    sdkAvailable: Boolean,
    manageIntentResolvable: Boolean,
): HealthConnectIntentKind? = when {
    !sdkAvailable -> null
    manageIntentResolvable -> HealthConnectIntentKind.MANAGE_DATA
    else -> HealthConnectIntentKind.SETTINGS_ACTION
}

internal fun shouldReportSettingsOpened(
    sdkAvailable: Boolean,
    intentStarted: Boolean,
): Boolean = sdkAvailable && intentStarted
~~~

Create a separate MethodChannel named sanbo/health_connect in configureFlutterEngine. Its openSettings handler calls HealthConnectClient.getSdkStatus(this); for SDK_AVAILABLE it creates getHealthConnectManageDataIntent(this, packageName) and starts it if resolvable; otherwise it tries Intent(HealthConnectClient.getHealthConnectSettingsAction()). Catch ActivityNotFoundException, SecurityException, and other launch failures and return result.success(false). Return false for unavailable or update-required provider status. Do not merge it into the notification channel.

- [ ] Step 5: Run bridge tests and the debug build.

~~~bash
dart format lib/platform/activity/health_connect_settings.dart lib/platform/activity/health_activity_data_source.dart test/platform/health_connect_settings_test.dart
flutter test --no-pub --concurrency=1 test/platform/health_connect_settings_test.dart test/data/activity_data_source_test.dart
cd android && ./gradlew :app:testDebugUnitTest :app:assembleDebug
~~~

- [ ] Step 6: Commit.

~~~bash
git add lib/platform/activity/health_connect_settings.dart lib/platform/activity/health_activity_data_source.dart test/platform/health_connect_settings_test.dart android/app/src/main/kotlin/com/sanbo/sanbo/MainActivity.kt android/app/build.gradle.kts android/app/src/test/kotlin/com/sanbo/sanbo/HealthConnectIntentContractTest.kt
git commit -m "feat: open Android Health Connect settings natively"
~~~
