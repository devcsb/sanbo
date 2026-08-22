#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

step() {
  printf '\n[native] %s\n' "$1"
}

if [[ ! -f "$ROOT/android/local.properties" ]]; then
  android_sdk="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
  [[ -n "$android_sdk" ]] || {
    echo "ANDROID_SDK_ROOT or ANDROID_HOME is required to run Android native tests" >&2
    exit 1
  }

  flutter_sdk="${FLUTTER_ROOT:-}"
  if [[ -z "$flutter_sdk" ]]; then
    flutter_bin="$(command -v flutter || true)"
    [[ -n "$flutter_bin" ]] || {
      echo "Flutter is required to run Android native tests" >&2
      exit 1
    }
    flutter_sdk="$(cd "$(dirname "$flutter_bin")/.." && pwd)"
  fi

  printf 'sdk.dir=%s\nflutter.sdk=%s\n' "$android_sdk" "$flutter_sdk" \
    > "$ROOT/android/local.properties"
fi

step "Android native unit tests"
(
  cd android
  ./gradlew app:testDebugUnitTest
)

if [[ "$(uname -s)" != "Darwin" ]]; then
  printf '\n[native] iOS native XCTest skipped: macOS is required\n'
  exit 0
fi

if ! command -v xcrun >/dev/null 2>&1 || ! command -v xcodebuild >/dev/null 2>&1; then
  echo "iOS native XCTest requires xcrun and xcodebuild" >&2
  exit 1
fi

simulator_id="${IOS_SIMULATOR_ID:-}"
if [[ -z "$simulator_id" ]]; then
  simulator_id="$(
    xcrun simctl list devices available |
      sed -n 's/.*iPhone.*(\([0-9A-F-]\{36\}\)).*/\1/p' |
      head -n 1
  )"
fi
if [[ -z "$simulator_id" ]]; then
  echo "No available iPhone simulator found. Set IOS_SIMULATOR_ID." >&2
  exit 1
fi

step "iOS native XCTest on $simulator_id"
xcrun simctl boot "$simulator_id" 2>/dev/null || true
xcrun simctl bootstatus "$simulator_id" -b >/dev/null
xcodebuild test \
  -workspace ios/Runner.xcworkspace \
  -scheme Runner \
  -destination "platform=iOS Simulator,id=$simulator_id" \
  -derivedDataPath /tmp/sanbo-ios-native-tests \
  FLUTTER_TARGET=lib/main.dart \
  CODE_SIGNING_ALLOWED=NO \
  -quiet

printf '\n[native] PASS\n'
