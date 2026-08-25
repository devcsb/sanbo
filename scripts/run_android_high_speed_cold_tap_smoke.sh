#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PACKAGE="${SANBO_ANDROID_PACKAGE:-com.sanbo.sanbo}"
ACTIVITY="${SANBO_ANDROID_ACTIVITY:-$PACKAGE/.MainActivity}"
DEVICE_ID="${SANBO_ANDROID_DEVICE_ID:-}"
NOTIFICATION_PERMISSION="${SANBO_ANDROID_NOTIFICATION_PERMISSION:-grant}"
TAP_MODE="${SANBO_ANDROID_TAP_MODE:-cold}"
TAP_ACTION="${SANBO_ANDROID_TAP_ACTION:-continue}"
ROUTE_EXCLUSION="${SANBO_ANDROID_ROUTE_EXCLUSION:-0}"
RESTART_PERSISTENCE="${SANBO_ANDROID_RESTART_PERSISTENCE:-0}"
BASE_LAT="${SANBO_ANDROID_BASE_LAT:-37.500000}"
BASE_LON="${SANBO_ANDROID_BASE_LON:--127.000000}"
STEP_LON="${SANBO_ANDROID_STEP_LON:-0.000500}"
# Fused providers can coalesce the first mock fix with a cached location. Keep
# enough waypoints after that possible continuity reset to guarantee at least
# the 60-second high-speed guard window even when a few fixes are dropped.
POINT_COUNT="${SANBO_ANDROID_HIGH_SPEED_POINTS:-24}"
POINT_INTERVAL_S="${SANBO_ANDROID_HIGH_SPEED_INTERVAL_S:-4}"
PREBUILT_APK="${SANBO_ANDROID_APK:-}"
SKIP_DB_ASSERTIONS="${SANBO_ANDROID_SKIP_DB_ASSERTIONS:-0}"

fail() {
  echo "[android-high-speed-cold-tap] FAIL: $1" >&2
  exit 1
}

find_adb() {
  if [[ -n "${ANDROID_ADB:-}" && -x "$ANDROID_ADB" ]]; then
    printf '%s' "$ANDROID_ADB"
    return
  fi
  if command -v adb >/dev/null 2>&1; then
    command -v adb
    return
  fi
  for candidate in \
    "${ANDROID_SDK_ROOT:-}/platform-tools/adb" \
    "${ANDROID_HOME:-}/platform-tools/adb" \
    "$HOME/Library/Android/sdk/platform-tools/adb"; do
    if [[ -x "$candidate" ]]; then
      printf '%s' "$candidate"
      return
    fi
  done
  fail 'adb를 찾을 수 없습니다.'
}

ADB_BIN="$(find_adb)"
command -v flutter >/dev/null 2>&1 || fail 'flutter가 PATH에 없습니다.'
command -v sqlite3 >/dev/null 2>&1 || fail 'sqlite3가 필요합니다.'

available_devices=()
while IFS= read -r available_device; do
  [[ -n "$available_device" ]] && available_devices+=("$available_device")
done < <("$ADB_BIN" devices | awk 'NR > 1 && $2 == "device" {print $1}')
if [[ -z "$DEVICE_ID" ]]; then
  DEVICE_ID="${available_devices[0]:-}"
fi
[[ -n "$DEVICE_ID" ]] || fail '사용 가능한 Android 대상이 없습니다.'
printf '%s\n' "${available_devices[@]}" | grep -Fxq "$DEVICE_ID" ||
  fail "Android 대상이 연결되지 않았습니다: $DEVICE_ID"
case "$SKIP_DB_ASSERTIONS" in
  0|1) ;;
  *) fail "SANBO_ANDROID_SKIP_DB_ASSERTIONS는 0 또는 1이어야 합니다: $SKIP_DB_ASSERTIONS" ;;
esac
if [[ "$SKIP_DB_ASSERTIONS" == "1" && -z "$PREBUILT_APK" ]]; then
  fail 'SANBO_ANDROID_SKIP_DB_ASSERTIONS=1은 SANBO_ANDROID_APK와 함께 사용해야 합니다.'
fi
if [[ "$SKIP_DB_ASSERTIONS" == "1" &&
  ("$ROUTE_EXCLUSION" == "1" || "$RESTART_PERSISTENCE" == "1") ]]; then
  fail 'release APK의 DB 비디버그 경로에서는 route exclusion과 restart persistence를 검사할 수 없습니다.'
fi

adb() {
  "$ADB_BIN" -s "$DEVICE_ID" "$@"
}

[[ "$(adb shell getprop ro.kernel.qemu | tr -d '\r')" == "1" ]] ||
  fail "Android emulator 전용 스크립트입니다: $DEVICE_ID"

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/sanbo-high-speed-cold-tap.XXXXXX")"
ui_xml="$tmp_dir/window.xml"
db="$tmp_dir/sanbo.db"

dump_ui() {
  adb exec-out uiautomator dump /dev/tty 2>/dev/null |
    sed 's/UI hierchary dumped to:.*$//' >"$ui_xml"
}

find_bounds() {
  local needle="$1"
  python3 - "$needle" "$ui_xml" <<'PY'
import re
import sys
import xml.etree.ElementTree as ET

needle, path = sys.argv[1:]
root = ET.parse(path).getroot()

def node_bounds(node):
    match = re.fullmatch(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]', node.attrib.get('bounds', ''))
    return None if match is None else tuple(map(int, match.groups()))

def is_enabled(node):
    return node.attrib.get('enabled') != 'false'

def visit(node, ancestors, exact_only):
    text = node.attrib.get('text', '')
    description = node.attrib.get('content-desc', '')
    exact_match = needle == text or needle == description
    partial_match = needle in text or needle in description
    if (exact_match if exact_only else partial_match):
        for ancestor in reversed(ancestors + [node]):
            if ancestor.attrib.get('clickable') == 'true' and is_enabled(ancestor):
                value = node_bounds(ancestor)
                if value is not None:
                    x1, y1, x2, y2 = value
                    print((x1 + x2) // 2, (y1 + y2) // 2)
                    raise SystemExit(0)
        value = node_bounds(node)
        if value is not None and is_enabled(node):
            x1, y1, x2, y2 = value
            print((x1 + x2) // 2, (y1 + y2) // 2)
            raise SystemExit(0)
    for child in node:
        visit(child, ancestors + [node], exact_only)

visit(root, [], True)
visit(root, [], False)
raise SystemExit(1)
PY
}

tap_text() {
  local needle="$1"
  local wait_seconds="${2:-20}"
  local deadline=$((SECONDS + wait_seconds))
  while (( SECONDS < deadline )); do
    dump_ui || true
    local coords=''
    coords="$(find_bounds "$needle")" || true
    if [[ -n "$coords" ]]; then
      read -r x y <<<"$coords"
      adb shell input tap "$x" "$y"
      return 0
    fi
    sleep 1
  done
  return 1
}

wait_text() {
  local needle="$1"
  local wait_seconds="${2:-20}"
  local deadline=$((SECONDS + wait_seconds))
  while (( SECONDS < deadline )); do
    dump_ui || true
    if grep -Fq "$needle" "$ui_xml"; then
      return 0
    fi
    sleep 1
  done
  return 1
}

dismiss_notification_prompt() {
  [[ "$NOTIFICATION_PERMISSION" == "deny" ]] || return 0
  for _ in 1 2 3; do
    tap_text 'Don’t allow' 5 ||
      tap_text "Don't allow" 5 ||
      tap_text '허용 안 함' 5 ||
      tap_text '알림 허용 안 함' 5 || true
    dump_ui || true
    if ! grep -Fq 'permission_message' "$ui_xml"; then
      return 0
    fi
    sleep 1
  done
}

wait_notification() {
  local deadline=$((SECONDS + 30))
  while (( SECONDS < deadline )); do
    if adb shell dumpsys notification --noredact |
      grep -Fq 'android.title=String (산책 기록을 계속할까요?)'; then
      return 0
    fi
    sleep 1
  done
  return 1
}

vehicle_edit_bounds() {
  local target="${1:-vehicle}"
  python3 - "$target" "$ui_xml" <<'PY'
import re
import sys
import xml.etree.ElementTree as ET

target, path = sys.argv[1:]
root = ET.parse(path).getroot()

def bounds(node):
    match = re.fullmatch(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]', node.attrib.get('bounds', ''))
    return None if match is None else tuple(map(int, match.groups()))

vehicle_rows = []
for node in root.iter('node'):
    description = node.attrib.get('content-desc', '')
    value = bounds(node)
    if value is None:
        continue
    if target == 'vehicle' and '차량 이동' in description:
        vehicle_rows.append(value)
    elif target == 'excluded' and '산책에서 제외됨' in description:
        vehicle_rows.append(value)

for node in root.iter('node'):
    description = node.attrib.get('content-desc', '')
    value = bounds(node)
    if value is None or '구간 편집' not in description:
        continue
    _, top, _, bottom = value
    if any(top < row_bottom and bottom > row_top for _, row_top, _, row_bottom in vehicle_rows):
        left, top, right, bottom = value
        print((left + right) // 2, (top + bottom) // 2)
        raise SystemExit(0)
raise SystemExit(1)
PY
}

tap_vehicle_edit() {
  local target="${1:-vehicle}"
  local deadline=$((SECONDS + 30))
  while (( SECONDS < deadline )); do
    dump_ui || true
    local coords=''
    coords="$(vehicle_edit_bounds "$target")" || true
    if [[ -n "$coords" ]]; then
      read -r x y <<<"$coords"
      adb shell input tap "$x" "$y"
      return 0
    fi
    sleep 1
  done
  return 1
}

scroll_to_activity_flow() {
  for _ in 1 2 3; do
    dump_ui || true
    if grep -Fq '구간 편집' "$ui_xml"; then
      return 0
    fi
    adb shell input swipe 540 1900 540 600 700
    sleep 1
  done
  dump_ui || true
  grep -Fq '구간 편집' "$ui_xml"
}

restore_current_exclusion() {
  tap_vehicle_edit excluded || fail '제외된 차량 구간 편집 버튼을 찾지 못했습니다.'
  tap_text '제외 취소' 10 || fail '제외 취소 메뉴를 찾지 못했습니다.'
  sleep 2
  scroll_to_activity_flow || fail '복원 후 활동 흐름을 찾지 못했습니다.'
  if grep -Fq '산책에서 제외됨' "$ui_xml"; then
    fail '제외 취소 뒤 제외 상태가 남아 있습니다.'
  fi
}

run_route_exclusion() {
  echo '[android-high-speed-cold-tap] route exclusion and restore'
  adb exec-out run-as "$PACKAGE" cat app_flutter/sanbo.db >"$db"
  read -r route_baseline_total route_baseline_exclusions <<<"$(
    sqlite3 -separator ' ' "$db" \
      'select total_distance_m, (select count(*) from route_exclusions) from sessions order by started_at desc limit 1;'
  )"
  tap_text $'기록\n탭 3개 중 2번째' 15 || fail '기록 탭을 찾지 못했습니다.'
  tap_text '상세 보기' 15 || fail '최근 고속 세션 상세 화면을 찾지 못했습니다.'
  scroll_to_activity_flow || fail '상세 화면의 활동 흐름을 찾지 못했습니다.'
  tap_vehicle_edit || fail '차량 이동 구간 편집 버튼을 찾지 못했습니다.'
  tap_text '산책에서 제외' 10 || fail '산책에서 제외 메뉴를 찾지 못했습니다.'
  tap_text '차량 이동 구간 제외' 10 || fail '차량 이동 구간 제외 확인을 찾지 못했습니다.'
  sleep 2
  adb exec-out run-as "$PACKAGE" cat app_flutter/sanbo.db >"$db"
  read -r excluded_total exclusion_count <<<"$(
    sqlite3 -separator ' ' "$db" \
      'select total_distance_m, (select count(*) from route_exclusions) from sessions order by started_at desc limit 1;'
  )"
  [[ "$exclusion_count" -gt "$route_baseline_exclusions" ]] ||
    fail '차량 이동 구간 제외 뒤 route exclusion이 저장되지 않았습니다.'
  python3 - "$route_baseline_total" "$excluded_total" <<'PY'
import sys

baseline, excluded = map(float, sys.argv[1:])
if not excluded < baseline - 1e-6:
    raise SystemExit('차량 이동 구간 제외 뒤 산책 거리가 줄지 않았습니다.')
PY
  scroll_to_activity_flow || fail '제외 후 활동 흐름을 찾지 못했습니다.'
  wait_text '산책에서 제외됨' 10 || fail '제외 상태가 화면에 표시되지 않았습니다.'

  if [[ "$RESTART_PERSISTENCE" == "1" ]]; then
    echo '[android-high-speed-cold-tap] excluded state after app restart'
    adb shell am force-stop "$PACKAGE"
    sleep 1
    adb shell am start -W -n "$ACTIVITY" >/dev/null
    tap_text $'기록\n탭 3개 중 2번째' 15 ||
      fail '재시작 뒤 기록 탭을 찾지 못했습니다.'
    tap_text '상세 보기' 15 ||
      fail '재시작 뒤 최근 고속 세션 상세 화면을 찾지 못했습니다.'
    scroll_to_activity_flow || fail '재시작 뒤 활동 흐름을 찾지 못했습니다.'
    wait_text '산책에서 제외됨' 10 ||
      fail '재시작 뒤 제외 상태가 표시되지 않았습니다.'
    adb exec-out run-as "$PACKAGE" cat app_flutter/sanbo.db >"$db"
    read -r persisted_total persisted_exclusion_count persisted_excluded_windows <<<"$(
      sqlite3 -separator ' ' "$db" \
        'select total_distance_m, (select count(*) from route_exclusions), (select count(*) from minute_windows where user_exclusion_id is not null) from sessions order by started_at desc limit 1;'
    )"
    [[ "$persisted_exclusion_count" -gt "$route_baseline_exclusions" ]] ||
      fail '재시작 뒤 route exclusion이 유지되지 않았습니다.'
    python3 - "$route_baseline_total" "$persisted_total" <<'PY'
import sys

baseline, persisted = map(float, sys.argv[1:])
if not persisted < baseline - 1e-6:
    raise SystemExit('재시작 뒤 제외된 총거리가 유지되지 않았습니다.')
PY
    ((persisted_excluded_windows > 0)) ||
      fail '재시작 뒤 제외된 분 기록이 유지되지 않았습니다.'
  fi

  restore_current_exclusion
}

echo '[android-high-speed-cold-tap] install and reset'
if [[ -n "$PREBUILT_APK" ]]; then
  apk="$PREBUILT_APK"
else
  flutter build apk --debug --target lib/main.dart >/dev/null
  apk='build/app/outputs/flutter-apk/app-debug.apk'
fi
[[ -f "$apk" ]] || fail "APK가 생성되지 않았습니다: $apk"
adb shell input keyevent 224 || true
adb shell input keyevent 3 || true
adb install -r "$apk" >/dev/null
adb shell pm clear "$PACKAGE" >/dev/null
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
case "$TAP_MODE" in
  cold|warm) ;;
  *) fail "SANBO_ANDROID_TAP_MODE는 cold 또는 warm이어야 합니다: $TAP_MODE" ;;
esac
case "$TAP_ACTION" in
  continue|stop) ;;
  *) fail "SANBO_ANDROID_TAP_ACTION은 continue 또는 stop이어야 합니다: $TAP_ACTION" ;;
esac
case "$ROUTE_EXCLUSION" in
  0|1) ;;
  *) fail "SANBO_ANDROID_ROUTE_EXCLUSION은 0 또는 1이어야 합니다: $ROUTE_EXCLUSION" ;;
esac
case "$RESTART_PERSISTENCE" in
  0|1) ;;
  *) fail "SANBO_ANDROID_RESTART_PERSISTENCE는 0 또는 1이어야 합니다: $RESTART_PERSISTENCE" ;;
esac
adb shell am force-stop "$PACKAGE"
sleep 1
adb shell am start -W -n "$ACTIVITY" >/dev/null

tap_text '산보 시작하기' 10 || true
tap_text '산책 시작' 30 || fail '산책 시작 버튼을 찾지 못했습니다.'
if [[ "$NOTIFICATION_PERMISSION" == "grant" ]]; then
  tap_text '허용' 3 || tap_text 'Allow' 3 || true
else
  dismiss_notification_prompt
fi
wait_text '기록 중' 30 || fail '기록 상태로 전환되지 않았습니다.'

echo '[android-high-speed-cold-tap] background route injection'
adb shell input keyevent 3
sleep 2
if adb shell dumpsys activity activities | grep -Eq "ResumedActivity:.*$PACKAGE"; then
  fail 'HOME 입력 뒤에도 앱이 전면에 남아 있습니다.'
fi
adb emu geo fix "$BASE_LON" "$BASE_LAT" >/dev/null
sleep 3
for index in $(seq 1 "$POINT_COUNT"); do
  longitude="$(awk -v base="$BASE_LON" -v step="$STEP_LON" -v point_number="$index" 'BEGIN {printf "%.6f", base + step * point_number}')"
  adb emu geo fix "$longitude" "$BASE_LAT" >/dev/null
  sleep "$POINT_INTERVAL_S"
done
# The Android fused provider may coalesce emulator fixes. Send one final fix
# and wait for the configured provider interval so the guard sees the last
# high-speed span before the notification assertion.
final_index=$((POINT_COUNT + 1))
final_longitude="$(awk -v base="$BASE_LON" -v step="$STEP_LON" -v point_number="$final_index" 'BEGIN {printf "%.6f", base + step * point_number}')"
adb emu geo fix "$final_longitude" "$BASE_LAT" >/dev/null
sleep 15
stopped_from_warning=0
if [[ "$NOTIFICATION_PERMISSION" == "grant" ]]; then
  wait_notification || fail '백그라운드 high-speed 알림이 게시되지 않았습니다.'

  if [[ "$TAP_MODE" == "cold" ]]; then
    echo '[android-high-speed-cold-tap] crash process and tap notification shade'
    adb shell am crash "$PACKAGE" || true
    sleep 2
    [[ -z "$(adb shell pidof "$PACKAGE" | tr -d '\r')" ]] || fail '프로세스가 종료되지 않았습니다.'
  else
    echo '[android-high-speed-cold-tap] warm process and tap notification shade'
    [[ -n "$(adb shell pidof "$PACKAGE" | tr -d '\r')" ]] ||
      fail 'warm tap 전에 앱 프로세스가 실행 중이 아닙니다.'
  fi
  adb shell dumpsys notification --noredact |
    grep -Fq 'android.title=String (산책 기록을 계속할까요?)' ||
    fail 'high-speed 알림이 유지되지 않았습니다.'
  adb shell input keyevent 224
  for attempt in 1 2 3; do
    adb shell input swipe 500 20 500 1200 600
    sleep 1
    dump_ui
    grep -Fq '산책 기록을 계속할까요?' "$ui_xml" && break
  done
  tap_text '산책 기록을 계속할까요?' 10 || fail 'notification shade에서 high-speed 알림을 탭하지 못했습니다.'
  if [[ "$TAP_MODE" == "cold" ]]; then
    wait_text '기록 종료 확인 중' 30 || fail 'cold tap 복구 경고가 표시되지 않았습니다.'
  else
    wait_text '산책 기록을 계속할까요?' 30 || fail 'warm tap 뒤 high-speed 경고가 표시되지 않았습니다.'
  fi
  if [[ "$TAP_ACTION" == "stop" ]]; then
    echo '[android-high-speed-cold-tap] stop from high-speed warning'
    tap_text '기록 종료' 10 || fail '고속 경고에서 기록 종료 버튼을 찾지 못했습니다.'
    wait_text '산책 요약' 30 || fail '고속 경고의 기록 종료 뒤 요약 화면으로 전환되지 않았습니다.'
    stopped_from_warning=1
  else
    tap_text '계속 기록' 10 || fail '계속 기록 버튼을 찾지 못했습니다.'
    wait_text '기록 중' 20 || fail '계속 기록 뒤 tracking 상태가 아닙니다.'
    if adb shell dumpsys notification --noredact |
      grep -Fq 'android.title=String (산책 기록을 계속할까요?)'; then
      fail '계속 기록 뒤 high-speed 알림이 취소되지 않았습니다.'
    fi
  fi
else
  if adb shell dumpsys notification --noredact |
    grep -Fq 'android.title=String (산책 기록을 계속할까요?)'; then
    fail '알림 권한 거부 뒤 high-speed 시스템 알림이 게시되었습니다.'
  fi
  echo '[android-high-speed-cold-tap] notification denied, foreground recovery'
  adb shell am start -W -n "$ACTIVITY" >/dev/null
  wait_text '산책 기록을 계속할까요?' 20 ||
    fail '알림 권한 거부 뒤 앱 내부 high-speed 경고가 표시되지 않았습니다.'
  if [[ "$TAP_ACTION" == "stop" ]]; then
    echo '[android-high-speed-cold-tap] stop from foreground warning without notification'
    tap_text '기록 종료' 10 || fail '알림 거부 고속 경고에서 기록 종료 버튼을 찾지 못했습니다.'
    wait_text '산책 요약' 30 || fail '알림 거부 고속 경고의 기록 종료 뒤 요약 화면으로 전환되지 않았습니다.'
    stopped_from_warning=1
  else
    tap_text '계속 기록' 10 || fail '알림 권한 거부 뒤 계속 기록 버튼을 찾지 못했습니다.'
    wait_text '기록 중' 20 || fail '알림 권한 거부 뒤 계속 기록 상태가 아닙니다.'
  fi
fi

if [[ "$stopped_from_warning" == "0" ]]; then
  tap_text '산책 종료' 10 || fail '산책 종료 버튼을 찾지 못했습니다.'
  wait_text '산책 요약' 30 || fail '산책 요약 화면으로 전환되지 않았습니다.'
fi
if [[ "$SKIP_DB_ASSERTIONS" == "1" ]]; then
  total_distance='UI 확인'
  valid_samples='UI 확인'
else
  if [[ "$ROUTE_EXCLUSION" == "1" ]]; then
    run_route_exclusion
  fi
  adb exec-out run-as "$PACKAGE" cat app_flutter/sanbo.db >"$db"
  read -r status total_distance valid_samples <<<"$(
    sqlite3 -separator ' ' "$db" \
      'select status, total_distance_m, valid_sample_count from sessions order by started_at desc limit 1;'
  )"
  [[ "$status" == 'completed' ]] || fail "최근 세션 상태가 completed가 아닙니다: $status"
  python3 - "$total_distance" <<'PY'
import sys

if float(sys.argv[1]) <= 100:
    raise SystemExit('저장된 고속 경로 거리가 100m를 넘지 않았습니다.')
PY
  ((valid_samples >= 8)) || fail "유효 샘플 수가 8개 미만입니다: $valid_samples"

  if [[ "$ROUTE_EXCLUSION" == "1" ]]; then
    read -r exclusion_count remaining_excluded_windows <<<"$(
      sqlite3 -separator ' ' "$db" \
        'select (select count(*) from route_exclusions), (select count(*) from minute_windows where user_exclusion_id is not null);'
    )"
    [[ "$exclusion_count" == "0" ]] ||
      fail "제외 취소 뒤 route exclusion이 남아 있습니다: $exclusion_count"
    [[ "$remaining_excluded_windows" == "0" ]] ||
      fail "제외 취소 뒤 제외된 분 기록이 남아 있습니다: $remaining_excluded_windows"
    python3 - "$route_baseline_total" "$total_distance" <<'PY'
import sys

baseline, restored = map(float, sys.argv[1:])
if abs(restored - baseline) > max(1.0, baseline * 0.02):
    raise SystemExit('제외 취소 뒤 차량 구간이 원래 통계로 복원되지 않았습니다.')
PY
  fi
fi

provider_released=0
for _ in $(seq 1 20); do
  location_dump="$(adb shell dumpsys location |
    sed -n '/Location Providers:/,/Historical Aggregate Location Provider Data:/p')"
  if ! echo "$location_dump" | grep -q "$PACKAGE" ||
    ! echo "$location_dump" | grep -Eq 'ProviderRequest\[@'; then
    provider_released=1
    break
  fi
  sleep 1
done
((provider_released == 1)) || fail '세션 종료 뒤 앱 location provider 요청이 남아 있습니다.'

printf '\n[android-high-speed-cold-tap] PASS device=%s distance_m=%s valid_samples=%s\n' \
  "$DEVICE_ID" "$total_distance" "$valid_samples"
