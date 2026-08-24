#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PACKAGE="${SANBO_ANDROID_PACKAGE:-com.sanbo.sanbo}"
ACTIVITY="${SANBO_ANDROID_ACTIVITY:-$PACKAGE/.MainActivity}"
DEVICE_ID="${SANBO_ANDROID_DEVICE_ID:-}"
NOTIFICATION_PERMISSION="${SANBO_ANDROID_NOTIFICATION_PERMISSION:-grant}"
TAP_MODE="${SANBO_ANDROID_TAP_MODE:-cold}"
BASE_LAT="${SANBO_ANDROID_BASE_LAT:-37.500000}"
BASE_LON="${SANBO_ANDROID_BASE_LON:--127.000000}"
STEP_LON="${SANBO_ANDROID_STEP_LON:-0.000500}"
POINT_COUNT="${SANBO_ANDROID_HIGH_SPEED_POINTS:-18}"
POINT_INTERVAL_S="${SANBO_ANDROID_HIGH_SPEED_INTERVAL_S:-4}"

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

def visit(node, ancestors):
    text = node.attrib.get('text', '')
    description = node.attrib.get('content-desc', '')
    if needle in text or needle in description:
        for ancestor in reversed(ancestors + [node]):
            if ancestor.attrib.get('clickable') == 'true':
                value = node_bounds(ancestor)
                if value is not None:
                    x1, y1, x2, y2 = value
                    print((x1 + x2) // 2, (y1 + y2) // 2)
                    raise SystemExit(0)
        value = node_bounds(node)
        if value is not None:
            x1, y1, x2, y2 = value
            print((x1 + x2) // 2, (y1 + y2) // 2)
            raise SystemExit(0)
    for child in node:
        visit(child, ancestors + [node])

visit(root, [])
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

echo '[android-high-speed-cold-tap] install and reset'
flutter build apk --debug --target lib/main.dart >/dev/null
apk='build/app/outputs/flutter-apk/app-debug.apk'
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
adb shell am force-stop "$PACKAGE"
sleep 1
adb shell am start -W -n "$ACTIVITY" >/dev/null

tap_text '산보 시작하기' 10 || true
tap_text '산책 시작' 30 || fail '산책 시작 버튼을 찾지 못했습니다.'
if [[ "$NOTIFICATION_PERMISSION" == "grant" ]]; then
  tap_text '허용' 3 || tap_text 'Allow' 3 || true
else
  tap_text 'Don’t allow' 5 ||
    tap_text "Don't allow" 5 ||
    tap_text '허용 안 함' 5 ||
    tap_text '알림 허용 안 함' 5 || true
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
  tap_text '계속 기록' 10 || fail '계속 기록 버튼을 찾지 못했습니다.'
  wait_text '기록 중' 20 || fail '계속 기록 뒤 tracking 상태가 아닙니다.'
  if adb shell dumpsys notification --noredact |
    grep -Fq 'android.title=String (산책 기록을 계속할까요?)'; then
    fail '계속 기록 뒤 high-speed 알림이 취소되지 않았습니다.'
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
  tap_text '계속 기록' 10 || fail '알림 권한 거부 뒤 계속 기록 버튼을 찾지 못했습니다.'
  wait_text '기록 중' 20 || fail '알림 권한 거부 뒤 계속 기록 상태가 아닙니다.'
fi

tap_text '산책 종료' 10 || fail '산책 종료 버튼을 찾지 못했습니다.'
wait_text '산책 요약' 30 || fail '산책 요약 화면으로 전환되지 않았습니다.'
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
