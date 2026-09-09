# Android Location Stabilization Verification

Date: 2026-09-09 (Asia/Seoul)

## Automated evidence

- `flutter test --no-pub --concurrency=1`: PASS, 428 tests.
- `flutter analyze --no-pub`: PASS, no issues.
- `cd android && ./gradlew :app:testDebugUnitTest :app:assembleDebug`: PASS.
- `git diff --check`: run after this note is added; no whitespace errors expected.

The focused location and session regressions cover fresh/stale/future/out-of-order fixes,
malformed accuracy, approximate Android permission, watchdog recovery, pre-session anchors,
and filtered samples remaining in the audit buffer without affecting live metrics.

## Shipped policy

- Freshness: at most 30 seconds old.
- Future timestamp tolerance: at most 5 seconds.
- Hard accuracy ceiling: 500 m.
- Rejected fixes remain persisted as filtered audit rows and cannot become route anchors,
  speed evidence, valid samples, stationary state, or high-speed continuity.
- Android approximate location is surfaced as a recoverable precise-location settings action;
  it does not create a walk session.

## Device status

No Android physical device or emulator was available in this environment. `flutter devices`
reported an iOS simulator, macOS, and Chrome only; `adb` was not installed on PATH. Therefore
the manufacturer-specific Android provider, background, battery, and settings-screen behavior
remain unverified and must be recorded using the physical-device protocol in
`docs/DEVICE_VALIDATION.md`.

No raw coordinates, health values, account identifiers, or device logs are included here.
