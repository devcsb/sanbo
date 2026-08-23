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
SCENARIO="${SANBO_IOS_SCENARIO:-walk}"
TEST_FILE="integration_test/native_location_e2e_test.dart"
LOCATION_OPTIONS=(--interval=1)
TEST_PID=""

step() {
  printf '\n[ios-smoke] %s\n' "$1"
}

fail() {
  echo "[ios-smoke] FAIL: $1" >&2
  exit 1
}

case "$SCENARIO" in
  walk)
    ;;
  high_speed)
    # Keep the route long enough to survive a cold CI Xcode build before the
    # integration runner attaches to the already-running simulator.
    END_LAT="${SANBO_IOS_END_LAT:-37.600000}"
    SPEED="${SANBO_IOS_SPEED_MPS:-11}"
    # iOS 18.x can coalesce fixed-interval simulator updates while the
    # integration runner is attaching. Distance-driven updates keep the real
    # provider stream flowing on both CI and local simulator runtimes.
    LOCATION_OPTIONS=(--distance=10)
    TEST_FILE="integration_test/native_high_speed_e2e_test.dart"
    ;;
  *)
    fail "알 수 없는 iOS simulator smoke 시나리오입니다: $SCENARIO"
    ;;
esac

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
  if [[ -n "$TEST_PID" ]] && kill -0 "$TEST_PID" 2>/dev/null; then
    kill "$TEST_PID" 2>/dev/null || true
    wait "$TEST_PID" 2>/dev/null || true
  fi
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

step "Core Location waypoint 시나리오와 실제 provider E2E ($SCENARIO)"
xcrun simctl location "$SIMULATOR_ID" clear
if [[ "$SCENARIO" == high_speed ]]; then
  # iOS 18.x may not replay a route that started before the app's
  # CLLocationManager was attached. Start the integration runner first, then
  # inject the route as soon as its UIKit process is alive.
  step "integration runner 준비"
  # Native XCTest can leave a previous Runner process alive on the shared
  # simulator. Terminate it so process detection below cannot match stale UI.
  xcrun simctl terminate "$SIMULATOR_ID" "$PACKAGE" >/dev/null 2>&1 || true
  for _ in {1..30}; do
    if ! xcrun simctl spawn "$SIMULATOR_ID" launchctl list 2>/dev/null |
      grep -Fq "UIKitApplication:${PACKAGE}["; then
      break
    fi
    sleep 1
  done
  if xcrun simctl spawn "$SIMULATOR_ID" launchctl list 2>/dev/null |
    grep -Fq "UIKitApplication:${PACKAGE}["; then
    fail '이전 integration runner process가 simulator에서 종료되지 않았습니다.'
  fi
  flutter test --no-pub "$TEST_FILE" -d "$SIMULATOR_ID" &
  TEST_PID=$!
  app_seen=false
  for _ in {1..90}; do
    if ! kill -0 "$TEST_PID" 2>/dev/null; then
      set +e
      wait "$TEST_PID"
      test_status=$?
      set -e
      TEST_PID=""
      fail "integration runner가 location 주입 전에 종료됐습니다 (exit=$test_status)."
    fi
    if xcrun simctl spawn "$SIMULATOR_ID" launchctl list 2>/dev/null |
      grep -Fq "UIKitApplication:${PACKAGE}["; then
      app_seen=true
      break
    fi
    sleep 1
  done
  [[ "$app_seen" == true ]] || fail 'integration runner 앱이 simulator에서 시작되지 않았습니다.'
  xcrun simctl location "$SIMULATOR_ID" start \
    --speed="$SPEED" \
    "${LOCATION_OPTIONS[@]}" \
    "$START_LAT,$START_LON" "$END_LAT,$END_LON"
  set +e
  wait "$TEST_PID"
  test_status=$?
  set -e
  TEST_PID=""
  exit "$test_status"
fi

xcrun simctl location "$SIMULATOR_ID" start \
  --speed="$SPEED" \
  "${LOCATION_OPTIONS[@]}" \
  "$START_LAT,$START_LON" "$END_LAT,$END_LON"
flutter test --no-pub "$TEST_FILE" -d "$SIMULATOR_ID"

printf '\n[ios-smoke] PASS simulator=%s\n' "$SIMULATOR_ID"
