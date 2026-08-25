#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PACKAGE="${SANBO_ANDROID_PACKAGE:-com.sanbo.sanbo}"
ACTIVITY="${SANBO_ANDROID_ACTIVITY:-$PACKAGE/.MainActivity}"
DEVICE_ID="${SANBO_ANDROID_DEVICE_ID:-}"
CLEAR_DATA="${SANBO_ANDROID_CLEAR_DATA:-0}"
NOTIFICATION_PERMISSION="${SANBO_ANDROID_NOTIFICATION_PERMISSION:-grant}"
SCREEN_OFF="${SANBO_ANDROID_SCREEN_OFF:-0}"
REVOKE_LOCATION_AFTER_START="${SANBO_ANDROID_REVOKE_LOCATION_AFTER_START:-0}"
TOGGLE_LOCATION_AFTER_START="${SANBO_ANDROID_TOGGLE_LOCATION_AFTER_START:-0}"
BASE_LAT="${SANBO_ANDROID_BASE_LAT:-37.500000}"
BASE_LON="${SANBO_ANDROID_BASE_LON:-127.000000}"
STEP_LON="${SANBO_ANDROID_STEP_LON:-0.000100}"
PREBUILT_APK="${SANBO_ANDROID_APK:-}"
SKIP_DB_ASSERTIONS="${SANBO_ANDROID_SKIP_DB_ASSERTIONS:-0}"

step() {
  printf '\n[android-smoke] %s\n' "$1"
}

fail() {
  echo "[android-smoke] FAIL: $1" >&2
  exit 1
}

find_adb() {
  if [[ -n "${ANDROID_ADB:-}" && -x "${ANDROID_ADB}" ]]; then
    printf '%s' "$ANDROID_ADB"
    return
  fi
  if command -v adb >/dev/null 2>&1; then
    command -v adb
    return
  fi

  local user_home="${HOME:-}"
  local android_sdk=""
  if command -v flutter >/dev/null 2>&1; then
    android_sdk="$(flutter config --list 2>/dev/null | sed -n 's/^  android-sdk: //p' | head -n 1)"
  fi
  for candidate in \
    "${ANDROID_SDK_ROOT:-}/platform-tools/adb" \
    "${ANDROID_HOME:-}/platform-tools/adb" \
    "$android_sdk/platform-tools/adb" \
    "$user_home/Library/Android/sdk/platform-tools/adb"; do
    if [[ -n "$candidate" && -x "$candidate" ]]; then
      printf '%s' "$candidate"
      return
    fi
  done
  fail 'adb를 찾을 수 없습니다. ANDROID_ADB를 지정해 주세요.'
}

ADB_BIN="$(find_adb)"
if ! command -v flutter >/dev/null 2>&1; then
  fail 'flutter가 PATH에 없습니다.'
fi
if ! command -v sqlite3 >/dev/null 2>&1; then
  fail '로컬 sqlite3가 필요합니다.'
fi

available_devices=()
while IFS= read -r available_device; do
  [[ -n "$available_device" ]] && available_devices+=("$available_device")
done < <("$ADB_BIN" devices | awk 'NR > 1 && $2 == "device" {print $1}')
if [[ -z "$DEVICE_ID" ]]; then
  DEVICE_ID="${available_devices[0]:-}"
fi
[[ -n "$DEVICE_ID" ]] || fail '사용 가능한 Android 대상이 없습니다.'
if ! printf '%s\n' "${available_devices[@]}" | grep -Fxq "$DEVICE_ID"; then
  fail "Android 대상이 연결되지 않았습니다: $DEVICE_ID"
fi
case "$SKIP_DB_ASSERTIONS" in
  0|1) ;;
  *) fail "SANBO_ANDROID_SKIP_DB_ASSERTIONS는 0 또는 1이어야 합니다: $SKIP_DB_ASSERTIONS" ;;
esac
if [[ "$SKIP_DB_ASSERTIONS" == "1" && -z "$PREBUILT_APK" ]]; then
  fail 'SANBO_ANDROID_SKIP_DB_ASSERTIONS=1은 SANBO_ANDROID_APK와 함께 사용해야 합니다.'
fi

adb() {
  "$ADB_BIN" -s "$DEVICE_ID" "$@"
}

is_emulator="$(adb shell getprop ro.kernel.qemu | tr -d '\r')"
[[ "$is_emulator" == "1" ]] ||
  fail "이 smoke는 Android 에뮬레이터 전용입니다: $DEVICE_ID"

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/sanbo-android-smoke.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT
ui_xml="$tmp_dir/window.xml"

dump_ui() {
  adb exec-out uiautomator dump /dev/tty 2>/dev/null |
    sed 's/UI hierchary dumped to:.*$//' >"$ui_xml"
}

tap_desc() {
  local needle="$1"
  local timeout_s="${2:-20}"
  local deadline=$((SECONDS + timeout_s))
  while ((SECONDS < deadline)); do
    dump_ui
    local coords
    coords="$(python3 - "$needle" "$ui_xml" <<'PY'
import re
import sys
import xml.etree.ElementTree as ET

needle, path = sys.argv[1:]
try:
    root = ET.parse(path).getroot()
except (ET.ParseError, FileNotFoundError):
    raise SystemExit(1)

matches = []
for node in root.iter('node'):
    text = node.attrib.get('text', '')
    description = node.attrib.get('content-desc', '')
    if needle not in text and needle not in description:
        continue
    bounds = re.fullmatch(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]', node.attrib.get('bounds', ''))
    if bounds is None:
        continue
    x1, y1, x2, y2 = map(int, bounds.groups())
    matches.append((node.attrib.get('clickable') == 'true', (x1 + x2) // 2, (y1 + y2) // 2))

if not matches:
    raise SystemExit(1)
matches.sort(key=lambda item: not item[0])
_, x, y = matches[0]
print(x, y)
PY
)" || true
    if [[ -n "$coords" ]]; then
      read -r x y <<<"$coords"
      adb shell input tap "$x" "$y"
      return 0
    fi
    sleep 1
  done
  return 1
}

wait_desc() {
  local needle="$1"
  local timeout_s="${2:-20}"
  local deadline=$((SECONDS + timeout_s))
  while ((SECONDS < deadline)); do
    dump_ui
    if grep -Eq "content-desc=\"[^\"]*${needle}[^\"]*\"|text=\"[^\"]*${needle}[^\"]*\"" "$ui_xml"; then
      return 0
    fi
    sleep 1
  done
  return 1
}

dismiss_notification_prompt() {
  [[ "$NOTIFICATION_PERMISSION" == "deny" ]] || return 0
  tap_desc 'Don’t allow' 5 ||
    tap_desc "Don't allow" 5 ||
    tap_desc '허용 안 함' 5 ||
    tap_desc '알림 허용 안 함' 5 || true
}

location_providers() {
  adb shell dumpsys location |
    sed -n '/Location Providers:/,/Historical Aggregate Location Provider Data:/p'
}

if [[ -n "$PREBUILT_APK" ]]; then
  step "지정 APK 사용"
  apk="$PREBUILT_APK"
else
  step "debug APK 빌드"
  flutter build apk --debug --target lib/main.dart
  apk="build/app/outputs/flutter-apk/app-debug.apk"
fi
[[ -f "$apk" ]] || fail "APK가 생성되지 않았습니다: $apk"
asset_strings="$tmp_dir/kernel.strings"
if [[ -z "$PREBUILT_APK" ]]; then
  unzip -p "$apk" assets/flutter_assets/kernel_blob.bin 2>/dev/null |
    strings >"$asset_strings"
  grep -q 'lib/main.dart' "$asset_strings" || fail 'APK target이 lib/main.dart가 아닙니다.'
fi

step "APK 설치와 권한 준비"
adb install -r "$apk" >/dev/null
if [[ "$CLEAR_DATA" == "1" ]]; then
  adb shell pm clear "$PACKAGE" >/dev/null
fi
for permission in \
  android.permission.ACCESS_FINE_LOCATION \
  android.permission.ACCESS_COARSE_LOCATION; do
  adb shell pm grant "$PACKAGE" "$permission" >/dev/null 2>&1 || true
done
case "$NOTIFICATION_PERMISSION" in
  grant)
    adb shell pm grant "$PACKAGE" android.permission.POST_NOTIFICATIONS \
      >/dev/null 2>&1 || true
    ;;
  deny)
    adb shell pm revoke "$PACKAGE" android.permission.POST_NOTIFICATIONS \
      >/dev/null 2>&1 || true
    ;;
  *)
    fail "SANBO_ANDROID_NOTIFICATION_PERMISSION은 grant 또는 deny여야 합니다: $NOTIFICATION_PERMISSION"
    ;;
esac
case "$SCREEN_OFF" in
  0|1) ;;
  *) fail "SANBO_ANDROID_SCREEN_OFF는 0 또는 1이어야 합니다: $SCREEN_OFF" ;;
esac
case "$REVOKE_LOCATION_AFTER_START" in
  0|1) ;;
  *) fail "SANBO_ANDROID_REVOKE_LOCATION_AFTER_START는 0 또는 1이어야 합니다: $REVOKE_LOCATION_AFTER_START" ;;
esac
case "$TOGGLE_LOCATION_AFTER_START" in
  0|1) ;;
  *) fail "SANBO_ANDROID_TOGGLE_LOCATION_AFTER_START는 0 또는 1이어야 합니다: $TOGGLE_LOCATION_AFTER_START" ;;
esac
adb shell am force-stop "$PACKAGE"
adb shell am start -W -n "$ACTIVITY" >/dev/null

step "앱 시작과 세션 진입"
tap_desc '산보 시작하기' 8 || true
tap_desc '산책 시작' 30 || fail '산책 시작 버튼을 찾지 못했습니다.'
if [[ "$NOTIFICATION_PERMISSION" == "deny" ]]; then
  # A clean emulator still shows Android's first-run notification dialog even
  # when the permission was revoked through adb. Dismiss it to exercise the
  # same post-denial recording path as a real user choice.
  dismiss_notification_prompt
fi
wait_desc '기록 중' 30 || fail '기록 상태로 전환되지 않았습니다.'
if [[ "$TOGGLE_LOCATION_AFTER_START" == "1" ]]; then
  step "기록 중 위치 서비스 차단과 provider 복구"
  adb shell cmd location set-location-enabled false >/dev/null
  sleep 4
  # Android may show a system warning over the app after location is disabled.
  tap_desc 'Close' 3 || tap_desc '닫기' 3 || true
  wait_desc '미완료 기록' 30 || fail '위치 서비스 차단 뒤 미완료 기록 복구 카드가 표시되지 않았습니다.'
  disabled_location="$(location_providers)"
  if [[ "$disabled_location" == *"$PACKAGE"* &&
    "$disabled_location" == *'ProviderRequest['* ]]; then
    fail '위치 서비스 차단 뒤 앱 provider 요청이 남아 있습니다.'
  fi
  adb shell cmd location set-location-enabled true >/dev/null
  tap_desc '이어서 기록' 20 || fail '위치 서비스 복구 뒤 이어서 기록을 찾지 못했습니다.'
  dismiss_notification_prompt
  wait_desc '기록 중' 30 || fail '위치 서비스 복구 뒤 기록을 재개하지 못했습니다.'
fi
if [[ "$REVOKE_LOCATION_AFTER_START" == "1" ]]; then
  step "기록 중 위치 권한 철회와 cold recovery"
  for permission in \
    android.permission.ACCESS_FINE_LOCATION \
    android.permission.ACCESS_COARSE_LOCATION; do
    adb shell pm revoke "$PACKAGE" "$permission" >/dev/null 2>&1 || true
  done
  adb shell am force-stop "$PACKAGE"
  sleep 1
  for permission in \
    android.permission.ACCESS_FINE_LOCATION \
    android.permission.ACCESS_COARSE_LOCATION; do
    adb shell pm grant "$PACKAGE" "$permission" >/dev/null 2>&1 || true
  done
  adb shell am start -W -n "$ACTIVITY" >/dev/null
  wait_desc '미완료 기록' 30 || fail '위치 권한 철회 뒤 미완료 기록 복구 카드가 표시되지 않았습니다.'
  tap_desc '이어서 기록' 15 || fail '위치 권한 철회 뒤 이어서 기록을 찾지 못했습니다.'
  wait_desc '기록 중' 30 || fail '위치 권한을 다시 허용한 뒤 기록을 재개하지 못했습니다.'
fi
if [[ "$SCREEN_OFF" == "1" ]]; then
  adb shell input keyevent 26
  sleep 2
fi

step "실제 Geolocator provider에 GPS 이동 주입"
adb emu geo fix "$BASE_LON" "$BASE_LAT" >/dev/null
sleep 3
for index in 0 1 2 3 4; do
  longitude="$(awk -v base="$BASE_LON" -v step="$STEP_LON" -v point_number="$index" 'BEGIN {printf "%.6f", base + step * point_number}')"
  adb emu geo fix "$longitude" "$BASE_LAT" >/dev/null
  sleep 9
done
if [[ "$SCREEN_OFF" == "1" ]]; then
  adb shell input keyevent 26
  sleep 2
fi

dump_ui
metric="$(grep -Eo 'content-desc=\"시간[^\"]+\"' "$ui_xml" | head -n 1 | sed -E 's/^content-desc="(.*)"$/\1/')"
[[ -n "$metric" ]] || fail '실시간 거리 요약을 찾지 못했습니다.'
echo "[android-smoke] $metric"
distance_km="$(python3 - "$metric" <<'PY'
import re
import sys

match = re.search(r'거리\s+([0-9]+(?:\.[0-9]+)?)\s+킬로미터', sys.argv[1])
if match is None:
    raise SystemExit(1)
print(match.group(1))
PY
)" || fail '거리 요약을 해석하지 못했습니다.'
python3 - "$distance_km" <<'PY'
import sys

if float(sys.argv[1]) <= 0.01:
    raise SystemExit('거리 누적값이 0.01km를 넘지 않았습니다.')
PY

active_location=''
active_provider=0
for _ in 1 2 3 4 5 6; do
  active_location="$(location_providers)"
  if [[ "$active_location" == *"$PACKAGE"* &&
    "$active_location" == *'ProviderRequest['* ]]; then
    active_provider=1
    break
  fi
  sleep 1
done
((active_provider == 1)) || fail '세션 중 Android location provider 요청이 확인되지 않았습니다.'

step "세션 종료와 저장 확인"
tap_desc '산책 종료' 10 || fail '산책 종료 버튼을 찾지 못했습니다.'
wait_desc '산책 요약' 30 || fail '산책 요약 화면으로 전환되지 않았습니다.'

if [[ "$SKIP_DB_ASSERTIONS" == "1" ]]; then
  # Production release APKs are not debuggable, so Android rejects run-as.
  # UI completion and provider release remain observable in this mode.
  total_distance="${distance_km}km (UI)"
  valid_samples='UI 확인'
else
  db="$tmp_dir/sanbo.db"
  adb exec-out run-as "$PACKAGE" cat app_flutter/sanbo.db >"$db"
  read -r status total_distance valid_samples <<<"$(
    sqlite3 -separator ' ' "$db" \
      'select status, total_distance_m, valid_sample_count from sessions order by started_at desc limit 1;'
  )"
  [[ "$status" == 'completed' ]] || fail "최근 세션 상태가 completed가 아닙니다: $status"
  python3 - "$total_distance" <<'PY'
import sys

if float(sys.argv[1]) <= 15:
    raise SystemExit('저장된 거리가 15m를 넘지 않았습니다.')
PY
  ((valid_samples >= 4)) || fail "유효 샘플 수가 4개 미만입니다: $valid_samples"
fi

stopped_provider=0
for _ in 1 2 3 4 5 6; do
  stopped_location="$(location_providers)"
  if [[ "$stopped_location" != *"$PACKAGE"* ]]; then
    stopped_provider=1
    break
  fi
  sleep 1
done
((stopped_provider == 1)) || fail '세션 종료 뒤 fused provider 요청이 해제되지 않았습니다.'

printf '\n[android-smoke] PASS device=%s distance_m=%s valid_samples=%s\n' \
  "$DEVICE_ID" "$total_distance" "$valid_samples"
