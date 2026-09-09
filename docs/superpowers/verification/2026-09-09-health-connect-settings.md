# Android Health Connect Settings Verification

Date: 2026-09-09 (Asia/Seoul)

## Automated evidence

- `flutter test --no-pub --concurrency=1`: PASS, 428 tests.
- Health Connect/data-source and UI/provider focused suite: PASS, 91 tests in the combined
  location/health regression invocation.
- `flutter analyze --no-pub`: PASS, no issues.
- `cd android && ./gradlew :app:testDebugUnitTest :app:assembleDebug`: PASS.
- `git diff --check`: run after this note is added; no whitespace errors expected.

The contract tests cover the Flutter method-channel boolean result and recoverable native
failures. Android native unit tests cover the app-specific manage-data intent priority,
version-specific settings fallback, and safe false results when the SDK or intent is not
available.

## Shipped behavior

- `HealthConnectClient.getHealthConnectManageDataIntent(context, packageName)` is attempted
  first for the app-specific permission-management screen.
- Native code owns Android-version action differences and catches unavailable/unresolvable
  activity cases without crashing Flutter.
- The history panel exposes `Health Connect 설정 열기` as the primary action when the optional
  capability is present, while preserving the existing permission request fallback.
- Returning to the app invalidates the Health Connect daily cache and
  `dailyActivityProvider`, so grant/revoke changes are reflected without a second permission
  model or background sync.
- iOS keeps the existing HealthKit reader path because the settings opener is Android-only.

## Manual checklist status

| Case | Status |
|---|---|
| Android 14 app-specific manage-data screen | Not run: no Android device |
| Android 13-and-lower provider/settings path | Not run: no Android device |
| Provider absent or update required | Not run: no Android device |
| Unresolved settings intent | Covered by native contract test; device UI not run |
| Grant, revoke, and return refresh | Not run: no Android device |
| Authorized zero steps | Covered by existing data-source semantics; device UI not run |
| iOS HealthKit preservation | Covered by Flutter/analyzer regression suite; physical iOS not run |

`flutter devices` reported only an iOS simulator, macOS, and Chrome. `adb` was not installed
on PATH. Android physical/emulator results therefore remain intentionally unverified and must
be completed with the HC1–HC8 matrix in `docs/DEVICE_VALIDATION.md`.

No raw step totals, health screenshots, account identifiers, or coordinates are included.
