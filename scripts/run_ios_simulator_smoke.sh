#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PACKAGE="${SANBO_IOS_PACKAGE:-com.sanbo.sanbo}"
SIMULATOR_ID="${IOS_SIMULATOR_ID:-}"
START_LAT="${SANBO_IOS_START_LAT:-37.500000}"
START_LON="${SANBO_IOS_START_LON:-127.000000}"
END_LAT="${SANBO_IOS_END_LAT:-37.501000}"
END_LON="${SANBO_IOS_END_LON:-127.000000}"
SPEED="${SANBO_IOS_SPEED_MPS:-1}"

step() {
  printf '\n[ios-smoke] %s\n' "$1"
}

fail() {
  echo "[ios-smoke] FAIL: $1" >&2
  exit 1
}

[[ "$(uname -s)" == "Darwin" ]] || fail 'iOS simulator smoke는 macOS에서만 실행할 수 있습니다.'
command -v xcrun >/dev/null 2>&1 || fail 'xcrun이 PATH에 없습니다.'
command -v flutter >/dev/null 2>&1 || fail 'flutter가 PATH에 없습니다.'

if [[ -z "$SIMULATOR_ID" ]]; then
  SIMULATOR_ID="$(
    xcrun simctl list devices available |
      sed -n 's/.*iPhone.*(\([0-9A-F-]\{36\}\)).*/\1/p' |
      head -n 1
  )"
fi
[[ -n "$SIMULATOR_ID" ]] || fail '사용 가능한 iPhone simulator가 없습니다.'

available_simulators="$(xcrun simctl list devices available)"
if [[ "$available_simulators" != *"$SIMULATOR_ID"* ]]; then
  fail "사용할 수 없는 iPhone simulator입니다: $SIMULATOR_ID"
fi

location_cleanup() {
  xcrun simctl location "$SIMULATOR_ID" clear >/dev/null 2>&1 || true
}
trap location_cleanup EXIT

step "iPhone simulator 부팅"
xcrun simctl boot "$SIMULATOR_ID" 2>/dev/null || true
xcrun simctl bootstatus "$SIMULATOR_ID" -b >/dev/null

step "실제 앱 bundle 설치와 Core Location 권한 준비"
flutter build ios --simulator --no-codesign --target lib/main.dart
app="build/ios/iphonesimulator/Runner.app"
[[ -d "$app" ]] || fail "simulator app이 생성되지 않았습니다: $app"
xcrun simctl install "$SIMULATOR_ID" "$app"
xcrun simctl privacy "$SIMULATOR_ID" grant location-always "$PACKAGE"

step "Core Location waypoint 시나리오와 실제 provider E2E"
xcrun simctl location "$SIMULATOR_ID" clear
xcrun simctl location "$SIMULATOR_ID" start \
  --speed="$SPEED" \
  --interval=1 \
  "$START_LAT,$START_LON" "$END_LAT,$END_LON"
flutter test --no-pub integration_test/native_location_e2e_test.dart -d "$SIMULATOR_ID"

printf '\n[ios-smoke] PASS simulator=%s\n' "$SIMULATOR_ID"
