# 산보 실기기 검증 프로토콜

코드 테스트만으로는 GPS provider, 제조사 절전 정책, 화면 상태에 따른 배터리 사용량을 확정할 수 없다. 이 문서는 같은 조건으로 반복 측정하기 위한 증거 수집 절차다.

## 대상과 고정 조건

- 대상: Samsung Galaxy 실기기 1대 이상, Android 13 이상
- 앱: 같은 release APK, 같은 application data 상태
- 네트워크: Wi‑Fi/모바일 네트워크 조건을 기록하고 한 루프에서는 고정
- 장소: 하늘이 열린 동일한 야외 1 km 이상 왕복 경로
- 시작 배터리: 80% 이상, 충전기 연결 금지
- 화면: 각 테스트에서 `화면 켬` 또는 `화면 끔`을 명시
- 권한: 위치 `항상 허용` 또는 `앱 사용 중 허용`, 알림 허용 여부를 기록
- 모드 순서: 절전 → 균형 → 정밀. 매 테스트 전 기기를 재부팅하고 10분 안정화

## 60분 배터리 매트릭스

| ID | 모드 | 화면 | 기록할 값 |
|---|---|---|---|
| B1 | 절전 | 끔 | 시작/종료 배터리, 샘플 수, 거리, 누락·자동종료 |
| B2 | 균형 | 끔 | 시작/종료 배터리, 샘플 수, 거리, 누락·자동종료 |
| B3 | 정밀 | 끔 | 시작/종료 배터리, 샘플 수, 거리, 누락·자동종료 |
| B4 | 균형 | 켬 | 화면 비용 비교용 동일 지표 |

각 행은 최소 2회 반복한다. 결과는 `앱 소모율(%/h)`, 샘플 간격 중앙값, 정확도 중앙값, 경로 거리 편차로 요약한다.

## 백그라운드·복구 시나리오

1. 기록 시작 후 2분간 화면을 켠다.
2. 홈으로 나가고 화면을 잠근 뒤 20분 유지한다.
3. 잠금을 해제해 누적 거리·샘플 수·경과 시간이 한 번에 동기화되는지 확인한다.
4. 최근 앱 목록에서 산보를 스와이프하지 않고 10분 더 유지한다.
5. 강제 종료/OS 재시작은 별도 케이스로 실행하고, 재실행 후 `미완료 기록` 복구가 보이는지 확인한다.

## 수집 명령과 증거

```bash
# 패키지 ID는 실제 applicationId로 교체
adb shell dumpsys batterystats --reset
adb shell am force-stop com.sanbo.sanbo
adb shell dumpsys batterystats --enable full-wake-history

# 테스트 종료 후
adb shell dumpsys batterystats com.sanbo.sanbo > batterystats-sanbo.txt
adb shell dumpsys location > location-sanbo.txt
adb shell dumpsys activity services | grep -i -E 'geolocator|sanbo'
```

앱 화면의 시작/종료 시각과 배터리 %를 사진 또는 로그로 남기고, `batterystats`의 GPS·WakeLock·CPU 항목과 대조한다. `dumpsys` 한 번의 출력만으로 배터리 원인을 단정하지 않는다.

## 판정 규칙

- 데이터 정확성: 샘플 누락·중복·자동 종료·복구 실패가 있으면 해당 행은 실패
- 배터리: 같은 경로·화면 조건에서 모드 간 상대 차이를 기록하되 절대 허용치는 기기별로 별도 합의
- 백그라운드: 화면 잠금 뒤 샘플이 계속 저장되고 복귀 시 UI가 최신 누적값을 보여야 통과
- 재현성: 2회 결과가 크게 다르면 통과로 합치지 말고 신호·provider·절전 정책 차이를 원인 후보로 기록

측정 결과는 `docs/QUALITY_REVIEW_0.7.md`의 남은 위험과 루프 기록에 링크한다.

## 고속 경고와 경로 제외 실기기 매트릭스

아래 행은 실제 기기에서만 채운다. 자동화 빌드나 simulator 결과로 통과 처리하지 않는다. 각 실행에는 기기 모델과 OS, 위치와 알림 권한 상태, 관측 결과를 남기고 `통과/실패`를 하나만 표시한다.

실기기 측정 전에 native 계약을 빠르게 확인하려면 저장소 루트에서 다음 명령을 실행한다.

```bash
scripts/run_native_platform_tests.sh
```

이 명령은 Android native unit test와 사용 가능한 iPhone simulator의 XCTest만 실행한다.
통과하더라도 실제 GPS 수집, 백그라운드 FGS, 제조사 절전 정책과 시스템 알림 전달은
검증하지 않으므로 아래 실기기 행의 상태를 바꾸지 않는다.

Android 에뮬레이터에서 실제 APK와 provider 경로를 반복 확인하려면 다음 명령을
사용한다.

```bash
scripts/run_android_emulator_smoke.sh
```

이 명령은 에뮬레이터에서 GPS 주입, 거리 누적, 완료 세션 저장과 종료 후 provider
해제를 확인한다. 기본값은 앱 데이터를 보존하며, 깨끗한 intro부터 반복하려면
`SANBO_ANDROID_CLEAR_DATA=1`을 명시한다. 에뮬레이터 결과는 아래 물리 기기 행의
통과 판정으로 승격하지 않는다.

운영 release APK를 다시 빌드하지 않고 provider와 UI 종료 흐름만 확인하려면
prebuilt APK 경로를 넘긴다. release APK는 Android 보안 정책상 `run-as`로 앱 DB를
읽을 수 없으므로 `SANBO_ANDROID_SKIP_DB_ASSERTIONS=1`을 함께 지정한다. DB 집계,
route exclusion과 재시작 persistence는 debuggable debug APK smoke에서 별도로
검사한다.

```bash
SANBO_ANDROID_DEVICE_ID=emulator-5554 \
SANBO_ANDROID_APK=build/app/outputs/flutter-apk/app-arm64-v8a-release.apk \
SANBO_ANDROID_SKIP_DB_ASSERTIONS=1 \
SANBO_ANDROID_NOTIFICATION_PERMISSION=deny \
SANBO_ANDROID_SCREEN_OFF=1 \
  bash scripts/run_android_emulator_smoke.sh
```

고속 경고와 killed-app cold tap을 같은 순서로 반복하려면 다음 명령을 사용한다.

```bash
SANBO_ANDROID_DEVICE_ID=emulator-5554 \\
  bash scripts/run_android_high_speed_cold_tap_smoke.sh
```

이 명령은 약 11m/s GPS 경로를 백그라운드에서 주입하고, `4103` 알림 게시,
`am crash` 뒤 notification shade 탭, 복구 경고, 계속 기록, 완료 저장과 provider
해제를 한 번에 확인한다. emulator 결과는 물리 기기 행의 통과 판정으로 승격하지 않는다.

앱 프로세스를 유지한 상태에서 notification shade 탭을 반복하려면 다음처럼
`SANBO_ANDROID_TAP_MODE=warm`을 추가한다. 기본값 `cold`는 프로세스를 강제 종료한
뒤 복구하는 경로다.

```bash
SANBO_ANDROID_DEVICE_ID=emulator-5554 \\
SANBO_ANDROID_TAP_MODE=warm \\
  bash scripts/run_android_high_speed_cold_tap_smoke.sh
```

알림에서 바로 `기록 종료`를 선택하는 실제 경로까지 확인하려면
`SANBO_ANDROID_TAP_ACTION=stop`을 추가한다. 기본값 `continue`는 경고를 닫고
계속 기록한 뒤 별도로 산책을 종료한다. `stop`은 notification shade 탭 뒤
복구 경고의 `기록 종료`를 눌러 요약 화면과 provider 해제를 검사한다.

```bash
SANBO_ANDROID_DEVICE_ID=emulator-5554 \\
  SANBO_ANDROID_TAP_MODE=cold \\
  SANBO_ANDROID_TAP_ACTION=stop \\
  bash scripts/run_android_high_speed_cold_tap_smoke.sh
```

완료된 고속 세션에서 차량 이동 구간을 실제 APK UI로 제외하고 복원하는 경로까지
자동 확인하려면 `SANBO_ANDROID_ROUTE_EXCLUSION=1`을 추가한다. 제외 직후 DB의
`route_exclusions` 행과 거리 감소를 확인하고, `제외 취소` 뒤 원래 통계와 경로가
돌아오며 제외 행이 사라지는지 검사한다.

```bash
SANBO_ANDROID_DEVICE_ID=emulator-5554 \\
  SANBO_ANDROID_TAP_MODE=warm \\
  SANBO_ANDROID_ROUTE_EXCLUSION=1 \\
  bash scripts/run_android_high_speed_cold_tap_smoke.sh
```

제외된 구간이 앱 강제 종료 뒤에도 유지되는지까지 확인하려면 다음처럼
`SANBO_ANDROID_RESTART_PERSISTENCE=1`을 추가한다. 재시작 후 기록 상세 화면에서
`산책에서 제외됨` 상태와 DB의 제외 행을 확인한 다음 `제외 취소`로 복원한다.

```bash
SANBO_ANDROID_DEVICE_ID=emulator-5554 \\
  SANBO_ANDROID_TAP_MODE=cold \\
  SANBO_ANDROID_ROUTE_EXCLUSION=1 \\
  SANBO_ANDROID_RESTART_PERSISTENCE=1 \\
  bash scripts/run_android_high_speed_cold_tap_smoke.sh
```

알림 권한 거부 경로는 `SANBO_ANDROID_NOTIFICATION_PERMISSION=deny`를 추가한다.
기본값은 `grant`이며, 어느 모드에서도 위치 기록과 세션 저장 결과를 확인한다.
화면을 끈 상태의 provider 지속성은 `SANBO_ANDROID_SCREEN_OFF=1`을 추가해
에뮬레이터에서 반복할 수 있다.

고속 경고가 알림 권한 거부 뒤에도 앱 내부에 남고 기록을 계속할 수 있는지 확인하려면
다음 명령을 실행한다.

```bash
SANBO_ANDROID_DEVICE_ID=emulator-5554 \\
  SANBO_ANDROID_NOTIFICATION_PERMISSION=deny \\
  bash scripts/run_android_high_speed_cold_tap_smoke.sh
```

이 경로는 약 11m/s GPS를 백그라운드에서 주입한 뒤 시스템 high-speed 알림이
게시되지 않는지 확인하고, 앱을 다시 전면에 올려 앱 내부 경고의 `계속 기록`과
완료 저장을 검사한다.

기록 중 위치 권한을 철회한 뒤 앱을 다시 시작하고 권한을 복구하는 경로는 다음처럼
자동 확인할 수 있다. 기존 active session을 새로 만들지 않고 `미완료 기록` 카드에서
`이어서 기록`을 선택하는지 검사한다.

```bash
SANBO_ANDROID_DEVICE_ID=emulator-5554 \
  SANBO_ANDROID_REVOKE_LOCATION_AFTER_START=1 \
  bash scripts/run_android_emulator_smoke.sh
```

기록 중 위치 서비스를 끄는 Android provider 장애를 같은 프로세스에서 재현하려면
`SANBO_ANDROID_TOGGLE_LOCATION_AFTER_START=1`을 추가한다. 위치 서비스 차단 뒤
복구 카드, 앱 provider 요청 해제, 위치 서비스 재활성화와 `이어서 기록`, 세션 저장을
차례로 검사한다. 에뮬레이터 시스템 경고가 나타나면 smoke가 닫기 동작도 처리한다.

```bash
SANBO_ANDROID_DEVICE_ID=emulator-5554 \
  SANBO_ANDROID_APK=build/app/outputs/flutter-apk/app-debug.apk \
  SANBO_ANDROID_CLEAR_DATA=1 \
  SANBO_ANDROID_NOTIFICATION_PERMISSION=deny \
  SANBO_ANDROID_TOGGLE_LOCATION_AFTER_START=1 \
  bash scripts/run_android_emulator_smoke.sh
```

이 경로는 Android 에뮬레이터의 provider 장애 회귀를 검증하지만, 제조사별 위치 설정
화면과 백그라운드 정책을 포함한 물리 기기 검증을 대신하지 않는다.

iOS simulator의 실제 Core Location 경로는 다음 명령으로 반복한다.

```bash
scripts/run_ios_simulator_smoke.sh
```

이 명령은 simulator 앱을 설치한 뒤 `location-always` 권한과 waypoint를 준비하고,
실제 `GeolocatorLocationEngine`으로 거리 누적과 완료 저장을 검사한다. 결과는
물리 iPhone의 백그라운드와 절전 정책 검증으로 승격하지 않는다.

iOS simulator에서 실제 위치 provider의 고속 경고와 전면 시스템 알림 억제까지
확인하려면 다음 시나리오를 사용한다.

```bash
IOS_SIMULATOR_ID=96749A10-F3A8-4C98-87EE-79A8EE439BDA \
  SANBO_IOS_SCENARIO=high_speed \
  bash scripts/run_ios_simulator_smoke.sh
```

이 시나리오는 약 11m/s waypoint를 주입해 `SessionGuard`의 고속 경고와 300m
이상 거리 저장을 확인한다. 앱 전면에서는 시스템 알림을 게시하지 않는 계약도
검사하며, simulator 결과는 물리 iPhone 검증으로 승격하지 않는다.

simulator 화면 전원 끄기 조건을 반복하려면 `SANBO_IOS_SCREEN_OFF=1`을 추가한다.
기본 45초 뒤 화면을 끄며, Xcode 빌드와 앱 실행이 끝난 뒤 위치 provider가 계속
동작하는지 확인한다. `SANBO_IOS_SCREEN_OFF_DELAY_S`로 지연 시간을 조정할 수
있지만 이 조건은 iOS 잠금 화면이나 물리 iPhone 절전 정책을 대체하지 않는다.

```bash
IOS_SIMULATOR_ID=96749A10-F3A8-4C98-87EE-79A8EE439BDA \
  SANBO_IOS_SCENARIO=high_speed \
  SANBO_IOS_SCREEN_OFF=1 \
  bash scripts/run_ios_simulator_smoke.sh
```

## 최근 자동 검증 로그

2026-08-23에 Flutter 3.47.1 환경에서 다음 결과를 확인했다.

- `bash scripts/run_quality_loop.sh --debug-apk`: 정적 분석, 전체 Flutter 테스트 337개, Android debug APK와 생성 파일 검사를 모두 통과
- `bash scripts/run_native_platform_tests.sh`: Android native unit test와 iOS simulator XCTest 통과
- `SANBO_ANDROID_NOTIFICATION_PERMISSION=deny SANBO_ANDROID_SCREEN_OFF=1 SANBO_ANDROID_CLEAR_DATA=1 bash scripts/run_android_emulator_smoke.sh`: Android emulator 실제 provider 경로 통과, 거리 25.14m, 유효 샘플 5개
- `IOS_SIMULATOR_ID=96749A10-F3A8-4C98-87EE-79A8EE439BDA bash scripts/run_ios_simulator_smoke.sh`: iOS simulator 실제 Core Location 경로 통과
- Android emulator에서 high-speed 알림을 표시한 뒤 앱 프로세스를 강제 종료하고 시스템 알림을 탭하는 cold tap 통과. `기록 종료 확인 중` 복구 화면과 `계속 기록` 동작을 확인했고, 알림은 사라지고 활성 세션은 DB에 남았다. 이후 `산책 종료`로 세션을 완료했으며 위치 요청은 `OFF`가 됐다.
- Android emulator에서 약 11m/s GPS 경로를 주입해 전면 경고가 표시되고 시스템 알림이 억제되는 것을 확인했다. 백그라운드에서 생성된 `4103` 알림을 실행 중 앱에서 탭한 warm tap도 `기록 종료 확인 중`으로 복귀했고, `계속 기록` 뒤 경고가 해제됐다. 경로 0.75km, 위치 15개를 확인한 뒤 세션을 종료했고 위치 요청은 `OFF`가 됐다.
- Android emulator에서 완료된 차량 이동 세션의 상세 화면을 열어 `차량 이동 구간 제외`와 `제외 취소`를 차례로 실행했다. 597m 구간을 제외하자 총거리가 751.74m에서 90.10m로 줄고 해당 분에 `user_exclusion_id`가 저장됐으며, 복원 뒤 원래 거리와 12개 경로 점이 돌아왔다.
- 같은 완료 세션에서 제외 상태를 저장한 뒤 앱을 강제 종료하고 다시 열어 기록 화면과 상세 화면을 재진입했다. `10:05, 산책에서 제외됨, 제외 취소 가능` 상태와 DB의 제외 ID가 유지됐고, 재시작 후 `제외 취소`로 원래 통계를 복원했다.
- 같은 커밋에서 `SANBO_ANDROID_NOTIFICATION_PERMISSION=deny SANBO_ANDROID_SCREEN_OFF=1 SANBO_ANDROID_CLEAR_DATA=1` 조건을 다시 실행했다. Android emulator `emulator-5554`에서 알림 권한을 거부하고 화면을 잠근 뒤에도 실제 provider가 계속 동작했고, 거리 29.70m, 유효 샘플 5개로 세션 저장과 provider 해제를 확인했다.
- 같은 커밋에서 iPhone 17 Pro simulator `96749A10-F3A8-4C98-87EE-79A8EE439BDA`에 실제 앱을 재설치하고 Core Location waypoint를 다시 주입했다. `integration_test/native_location_e2e_test.dart`가 실제 `GeolocatorLocationEngine` 경로에서 통과했다.
- 같은 커밋에서 iPhone 17 Pro simulator에 약 11m/s waypoint를 주입하는 `SANBO_IOS_SCENARIO=high_speed` smoke를 실행해 실제 provider 고속 경고, 300m 초과 거리, 전면 시스템 알림 억제를 확인하고 세션 완료까지 통과했다.
- 같은 커밋에서 Android emulator의 알림 거부와 화면 잠금 smoke를 한 번 더 실행했다. 실제 provider가 계속 동작했고, 거리 62.22m, 유효 샘플 5개로 세션 저장과 종료 후 provider 해제를 다시 확인했다.
- 같은 검증 루프에서 고속 경고와 차량 구간 제외 통합 테스트 66개, Android 기기 통합 테스트 2개, Android native unit test와 iOS simulator XCTest를 모두 통과했다.
- Android emulator에서 실제 APK에 경도 0.0005도씩 4초 간격으로 GPS를 주입해 약 11m/s 이동을 재현했다. 전면에서 `산책 기록을 계속할까요?`와 `기록 종료`, `계속 기록`을 확인하고 계속 기록을 선택했으며, 완료 세션은 792.88m, 139초, 유효 샘플 12개로 저장됐다.
- 같은 세션의 상세 화면에서 `11:51–11:53` 차량 이동 추정 구간 793m를 `차량 이동 구간 제외`로 제외했다. 지도와 합계가 0m, 유효 샘플 1개로 갱신되고 `user_exclusion_id`가 저장됐으며, `제외 취소` 뒤 792.88m, 유효 샘플 12개와 제외 행 0개로 복원됐다.
- Android emulator에서 같은 고속 경로를 앱 프로세스가 백그라운드에 있는 상태로 재현한 뒤 `am crash com.sanbo.sanbo`로 프로세스를 종료했다. 시스템 알림의 `산책 기록을 계속할까요?` 행을 실제 notification shade에서 탭하자 새 프로세스가 cold start되고 `기록 종료 확인 중` 복구 화면과 `기록 종료`, `계속 기록` 버튼이 표시됐다. `계속 기록` 뒤 알림이 사라졌고, `산책 종료`로 617.24m, 유효 샘플 10개의 completed 세션을 저장했으며 `dumpsys location`의 앱 provider 요청은 `OFF`가 됐다.
- `scripts/run_android_high_speed_cold_tap_smoke.sh`를 Android emulator `emulator-5554`에서 처음부터 다시 실행했다. fused provider의 fix coalescing을 고려한 마지막 GPS fix 대기 뒤 알림을 게시했고, 프로세스 종료와 notification shade 탭, 복구와 종료 저장을 자동으로 통과했다. 완료 세션은 708.13m, 유효 샘플 10개였고 종료 뒤 현재 location provider 요청은 없었다.
- 같은 커밋에서 Android emulator `emulator-5554`의 고속 cold tap smoke를 다시 실행해 708.13m, 유효 샘플 10개와 종료 후 provider 요청 없음이 재현됐다. 이어 알림 권한 거부와 화면 잠금 조건의 provider smoke도 다시 통과했고 22.74m, 유효 샘플 5개가 저장됐다.
- 2026-08-25에 임시 로컬 서명으로 만든 arm64 release APK를 Android emulator `emulator-5554`에 설치해 운영 바이너리 경로를 확인했다. 알림 권한 거부와 화면 잠금 provider smoke는 UI 거리 0.06km, 세션 요약 전환과 종료 후 provider 해제를 통과했고, release high-speed cold tap은 백그라운드 GPS, `am crash`, notification shade 탭, 복구 화면, 계속 기록과 종료 후 provider 해제를 통과했다. release APK는 비디버그라 `run-as` DB 검사를 생략했으며, 이 임시 인증서는 production signing 검증에 사용하지 않았다.
- 같은 커밋에서 iPhone 17 Pro simulator `96749A10-F3A8-4C98-87EE-79A8EE439BDA`의 Core Location smoke를 다시 실행해 실제 provider E2E 1개가 통과했다.
- 2026-08-24에 Android emulator 통합 테스트 2개와 고속 cold tap을 다시 실행해 통과했다. cold tap 완료 세션은 708.13m, 유효 샘플 10개였고 종료 뒤 provider 요청이 없었다. 같은 날 iPhone 17 Pro simulator의 실제 Core Location 고속 시나리오와 차량 구간 제외 및 복원을 다시 실행해 1개 테스트가 통과했다.
- iOS는 CocoaPods가 아닌 Flutter 생성 Swift Package를 사용한다. 현재 `permission_handler_apple`의 생성 package가 `NSLocationWhenInUseUsageDescription`과 `NSLocationAlwaysAndWhenInUseUsageDescription`을 읽어 위치와 Always 권한 코드를 활성화하는 구성을 확인했고, iOS native XCTest와 실제 provider smoke를 통과했다.
- 커밋 `54988e7`에서 iPhone 17 Pro simulator의 실제 Core Location 고속 세션을 완료한 뒤 차량 구간을 제외하고 복원하는 경로까지 통과했다. 제외 전후 세션 집계와 경로가 복원되는지 저장소에서 확인했다.
- Android emulator에서 기록 중 위치 권한을 철회한 뒤 앱을 다시 열었다. `미완료 기록` 복구 카드가 나타났고, 위치 권한을 다시 허용해 `이어서 기록`을 선택한 뒤 세션을 완료했다. DB에는 `completed`, 거리 11.33m, 유효 샘플 3개가 저장됐다.
- 알림 channel이 늦게 등록되는 cold-start를 가정한 handshake 회귀 테스트를 추가하고, 전체 Flutter 테스트 338개, analyze, Android debug APK와 native Android unit test, iOS simulator XCTest를 다시 통과했다.
- Android emulator `emulator-5554`에서 고속 cold tap smoke를 다시 실행했다. 프로세스 종료 뒤 notification shade 탭, 복구 화면, 계속 기록과 세션 완료가 통과했고, 완료 세션은 거리 708.13m, 유효 샘플 10개였으며 종료 후 provider 요청은 없었다.
- iPhone 17 Pro simulator `96749A10-F3A8-4C98-87EE-79A8EE439BDA`에서 실제 Core Location 고속 시나리오와 차량 구간 제외 및 복원 통합 테스트를 다시 실행해 통과했다.
- Flutter engine이 재생성될 때 이전 channel의 늦은 `ready` 응답을 무시하도록 Android와 iOS에 channel generation 검사를 추가했다. Android native unit test와 iOS simulator XCTest에서 현재 세대 응답만 readiness를 열도록 확인했다.
- Android emulator `emulator-5554`에서 generation 변경 후 고속 cold tap smoke를 다시 실행했다. notification shade 탭, 복구 화면, 계속 기록과 세션 완료가 통과했고, 완료 세션은 거리 752.09m, 유효 샘플 10개였으며 종료 후 provider 요청은 없었다.
- 2026-08-24에 Flutter 3.47.1 전체 테스트를 무작위 순서 seed `30303`으로 다시 실행해 338개가 통과했다. 같은 HEAD에서 `scripts/run_native_platform_tests.sh`를 다시 실행해 Android native unit test와 iOS simulator XCTest를 통과했다.
- 2026-08-24에 Android emulator `emulator-5554`에서 알림 권한 거부와 화면 잠금 조건의 provider smoke를 다시 실행해 거리 23.54m, 유효 샘플 5개 저장과 종료 후 provider 해제를 확인했다. 같은 날 iPhone 17 Pro simulator의 고속 Core Location E2E와 차량 구간 제외 및 복원을 다시 실행해 통과했다.
- `flutter test --no-pub -d emulator-5554 integration_test/app_e2e_test.dart`를 장치 선택을 명시해 실행했다. Android emulator에서 UI 세션 저장, 고속 경고, 차량 구간 제외와 복원 통합 테스트 2개가 모두 통과했다.
- 2026-08-24에 `scripts/run_quality_loop.sh --debug-apk`를 다시 실행해 구조 검증, `flutter analyze`, 전체 Flutter 테스트 338개, Android debug APK를 통과했다. 이어 `scripts/run_native_platform_tests.sh`에서 Android native unit test와 iOS simulator XCTest를 통과했다.
- 같은 날 Android emulator `emulator-5554`에서 알림 권한 거부와 화면 잠금 조건의 실제 provider smoke를 다시 실행해 거리 61.27m, 유효 샘플 5개를 저장하고 종료 후 provider 해제를 확인했다. iPhone 17 Pro simulator에서는 `SANBO_IOS_SCENARIO=high_speed`를 다시 실행해 실제 Core Location 고속 경고와 세션 완료까지 통과했다.
- 같은 날 무작위 seed `74291`로 전체 Flutter 테스트 338개를 다시 실행했고 analyze, Android debug APK, Android native unit test와 iOS simulator XCTest를 통과했다. Android emulator 통합 테스트 2개, 고속 cold tap 708.13m와 유효 샘플 10개, 알림 거부·화면 잠금 provider smoke 23.09m와 유효 샘플 5개를 재현했으며, iPhone 17 Pro simulator의 실제 Core Location 고속 시나리오도 통과했다.
- 원격 CI run `32683623419`가 현재 HEAD `b932a247767370cca629ea94a4388509f3995cfd`에서 Flutter quality와 native platform tests 모두 성공했다.
- 원격 CI run `32685707316`이 현재 HEAD `3cb99ce424477569e0aa4891edd67dcd2516509b`에서 Flutter quality와 native platform tests 모두 성공했다.
- 2026-08-24에 Android emulator `emulator-5554`에서 `SANBO_ANDROID_NOTIFICATION_PERMISSION=deny` 고속 cold tap smoke를 추가로 실행했다. 시스템 high-speed 알림은 게시되지 않았고 앱을 전면에 올린 뒤 앱 내부 `계속 기록`으로 복귀했으며, 완료 세션은 705.73m, 유효 샘플 10개였다. 종료 후 provider 요청도 해제됐다.
- 2026-08-24에 Android emulator `emulator-5554`에서 `SANBO_ANDROID_TAP_MODE=warm` 고속 smoke를 실행했다. 앱 프로세스를 유지한 상태에서 notification shade를 탭해 홈의 고속 경고로 복귀했고, `계속 기록`, 세션 완료와 provider 해제를 확인했다. 완료 세션은 707.94m, 유효 샘플 11개였다.
- 2026-08-24에 Android emulator `emulator-5554`에서 알림 권한 거부와 화면 잠금 provider smoke를 다시 실행했다. 거리 24.62m, 유효 샘플 5개가 저장됐고 종료 후 provider 해제를 확인했다.
- 같은 실행에서 completed 세션을 저장한 뒤 앱 프로세스를 강제 종료하고 다시 시작했다. 재시작 전후 completed 세션 수가 1개로 유지됐고 기록 화면이 다시 표시됐다.
- 2026-08-24에 Android emulator `emulator-5554`에서 `SANBO_ANDROID_TAP_MODE=warm SANBO_ANDROID_ROUTE_EXCLUSION=1` 고속 smoke를 실행했다. 실제 APK에서 차량 이동 구간을 열어 `차량 이동 구간 제외`를 실행한 뒤 DB의 exclusion 저장과 거리 감소를 확인했고, `제외 취소` 뒤 거리 750.88m, 유효 샘플 12개와 `route_exclusions` 0개로 복원됐으며 provider 요청도 해제됐다.
- 같은 날 `SANBO_ANDROID_TAP_MODE=cold SANBO_ANDROID_ROUTE_EXCLUSION=1` 조합을 다시 실행했다. 프로세스 종료 후 알림 탭으로 복구한 뒤 차량 구간 제외와 복원을 수행했고, 구간 길이에 따라 제외 후 잔여 거리가 0m가 아니어도 실제 baseline보다 감소하는지 검사하도록 smoke 기준을 보정했다. 최종 세션은 708.13m, 유효 샘플 9개였고 `route_exclusions` 0개와 provider 해제를 확인했다.
- 같은 날 알림 거부와 화면 잠금 provider smoke의 `pipefail` 오탐 검사를 문자열 매칭으로 보정했다. Android emulator `emulator-5554`에서 같은 조건을 다시 실행해 실제 `HIGH_ACCURACY` provider 요청, 거리 68.51m, 유효 샘플 6개, 종료 후 provider 해제를 확인했다.
- 2026-08-24 커밋 `8cb8c2c`에서 앱 lifecycle의 `inactive → hidden → paused → detached → resumed` 전환을 기존 SanboApp 회귀 경로에 연결해 알림 readiness 재초기화 호출을 검증했고, 해당 테스트를 3회 반복해 모두 통과했다.
- 같은 커밋에서 `scripts/run_quality_loop.sh --debug-apk`를 실행해 PRD/TRD 구조 검증, `flutter analyze`, Flutter 테스트 340개, Android debug APK와 whitespace 검사를 모두 통과했다. `scripts/run_native_platform_tests.sh`도 Android native unit test와 iOS RunnerTests 5개를 통과했다.
- 같은 커밋에서 Android emulator `emulator-5554`의 일반 provider smoke는 거리 32.73m와 유효 샘플 5개, 알림 거부 및 화면 잠금 smoke는 거리 65.56m와 유효 샘플 7개로 통과했다. 두 경로 모두 종료 뒤 location provider 요청이 해제됐다.
- 같은 커밋에서 Android emulator 고속 cold tap과 차량 구간 제외 및 복원을 재실행해 거리 617.24m와 유효 샘플 10개를 저장하고 exclusion 복원과 provider 해제를 확인했다. iPhone 17 Pro simulator `96749A10-F3A8-4C98-87EE-79A8EE439BDA`의 실제 Core Location 고속 시나리오도 1개 테스트로 통과했다.
- origin `main`과 CI run `32721540117`이 모두 커밋 `8cb8c2c4753465804d83d742caf12780e1638753`를 가리키며 Flutter quality와 native platform tests가 성공했다.
- 2026-08-24에 iOS 알림 채널을 존재하지 않는 플러그인 registrar가 아니라 implicit engine의 application messenger에 연결하도록 수정했다. 회귀 테스트는 수정 전 RED, 수정 후 GREEN을 확인했고, 전체 Flutter 테스트 341개와 `scripts/run_quality_loop.sh --debug-apk`, Android native unit test와 iOS RunnerTests 5개, iPhone 17 Pro simulator의 실제 Core Location 고속 smoke를 다시 통과했다.
- `d537ac4` 현재 HEAD에서 Android emulator `emulator-5554`의 `SANBO_ANDROID_TAP_MODE=cold SANBO_ANDROID_ROUTE_EXCLUSION=1` smoke를 다시 실행해 cold tap 복구, 차량 구간 제외와 복원, 종료 후 provider 해제를 통과했다. 완료 세션은 거리 708.13m, 유효 샘플 10개였다. 같은 HEAD에서 알림 권한 거부와 화면 잠금 provider smoke는 거리 25.11m, 유효 샘플 5개로 통과했고, iPhone 17 Pro simulator의 실제 Core Location 고속 smoke도 1개 테스트로 통과했다.
- `ac74048` 현재 HEAD에서 호환 SDK Flutter 3.47.1로 `scripts/run_quality_loop.sh --debug-apk`를 다시 실행해 PRD와 TRD 구조 검증, `flutter analyze`, 전체 Flutter 테스트 342개, Android debug APK와 whitespace 검사를 통과했다. 이어 `scripts/run_native_platform_tests.sh`에서 Android native unit test와 iOS RunnerTests 5개를 통과했다.
- 같은 HEAD에서 Android emulator `emulator-5554`의 cold tap과 차량 구간 제외 및 복원 smoke를 다시 실행해 거리 708.1256m, 유효 샘플 10개를 확인했고, 알림 거부와 화면 잠금 provider smoke는 거리 21.3273m, 유효 샘플 5개로 통과했다. iPhone 17 Pro simulator의 실제 Core Location 고속 시나리오도 1개 테스트로 통과했다.
- 원격 CI run `32728894929`가 `ac74048cedd726d45df7b6fffb92f53f28c42a3d`에서 Flutter quality와 native platform tests 모두 성공했다.
- 2026-08-24에 iOS simulator smoke 순서를 실제 Core Location provider E2E 뒤 native `MethodChannel`의 `cancel` 응답 확인으로 고정했다. channel probe는 `MissingPluginException`을 숨기지 않고 직접 검증하며, provider 테스트가 남긴 Runner가 다음 위치 trace를 방해하지 않도록 마지막에 fresh process로 실행한다. 이 변경을 포함한 전체 Flutter 테스트 343개, Android native unit test와 iOS RunnerTests 5개, iOS high-speed provider E2E와 channel probe를 다시 통과했다.
- 2026-08-25에 커밋 `0f99b7b`의 Android high-speed cold tap과 `SANBO_ANDROID_ROUTE_EXCLUSION=1 SANBO_ANDROID_RESTART_PERSISTENCE=1` 조합을 다시 실행했다. 강제 종료와 알림 복구 뒤 차량 구간을 제외하고 앱을 재시작했으며, 재시작 후 화면 상태, 총거리 감소, `route_exclusions` 행과 `minute_windows.user_exclusion_id` 파생 행을 확인했다. `제외 취소` 뒤 제외 행과 파생 참조가 모두 0으로 돌아왔고, 최종 세션은 708.1256m, 유효 샘플 10개, provider 요청 없음으로 통과했다.
- 2026-08-25에 커밋 `9f5d920`을 호환 Flutter 3.47.1 환경에서 재검증했다. `scripts/run_quality_loop.sh --debug-apk`는 PRD와 TRD 구조 검증, `flutter analyze`, 전체 Flutter 테스트 346개, Android debug APK와 whitespace 검사를 통과했고, `scripts/run_native_platform_tests.sh`는 Android native unit test와 iOS RunnerTests 5개를 통과했다.
- 같은 실행에서 Android emulator `emulator-5554`의 `SANBO_ANDROID_TAP_MODE=cold SANBO_ANDROID_ROUTE_EXCLUSION=1 SANBO_ANDROID_RESTART_PERSISTENCE=1` smoke를 통과했다. cold tap 복구, 차량 이동 구간 제외, 강제 종료 뒤 제외 상태 유지, `제외 취소` 복원과 종료 후 provider 해제를 확인했으며 최종 세션은 972.7850m, 유효 샘플 14개였다.
- 같은 실행에서 Android emulator의 알림 거부와 화면 잠금 provider smoke를 통과했다. 실제 위치 수집과 세션 저장을 확인했고 최종 세션은 19.0037m, 유효 샘플 4개였으며 종료 후 provider 요청은 없었다.
- 같은 실행에서 iPhone 17 Pro simulator `96749A10-F3A8-4C98-87EE-79A8EE439BDA`의 실제 Core Location walk와 `SANBO_IOS_SCENARIO=high_speed`를 각각 통과했다. native notification channel `cancel` probe도 통과했다.
- 현재 호스트에는 Android emulator `emulator-5554`만 연결되어 있고 iOS `devicectl`은 연결된 기기를 반환하지 않았다. 따라서 아래 물리 기기 매트릭스는 계속 `미판정`으로 둔다.
- 같은 검증 루프에서 `SANBO_ANDROID_CLEAR_DATA=1 SANBO_ANDROID_REVOKE_LOCATION_AFTER_START=1` Android emulator smoke를 실행했다. 기록 중 위치 권한을 철회하고 프로세스를 재시작한 뒤 권한을 복구해 `미완료 기록`의 `이어서 기록`으로 돌아왔으며, 최종 세션은 34.5412m, 유효 샘플 5개, 종료 후 provider 요청 없음으로 통과했다.
- Xcode simulator가 병렬 테스트 clone을 `SBMainWorkspace Busy`로 거부하는 환경 변동을 재현했다. native XCTest wrapper에 병렬 실행을 끈 설정을 고정한 뒤 Android native unit test와 iOS RunnerTests 5개가 다시 통과했다.
- 2026-08-25에 최신 `main`에서 Android emulator `emulator-5554`의 `SANBO_ANDROID_TAP_MODE=cold SANBO_ANDROID_ROUTE_EXCLUSION=1 SANBO_ANDROID_RESTART_PERSISTENCE=1` smoke를 다시 실행했다. cold tap 복구, 차량 이동 구간 제외, 강제 종료 뒤 제외 상태 유지, `제외 취소` 복원과 provider 해제를 확인했으며 최종 세션은 거리 1016.7435m, 유효 샘플 14개였다.
- 같은 실행 루프에서 iPhone 17 Pro simulator `96749A10-F3A8-4C98-87EE-79A8EE439BDA`의 `SANBO_IOS_SCENARIO=high_speed` 실제 Core Location 경고 E2E와 fresh process native notification channel probe를 통과했다. Xcode 캐시 포화로 한 번 중단된 뒤 Sanbo 전용 DerivedData와 `/tmp` 캐시를 정리하고 재실행했으며, simulator 결과는 물리 iPhone 판정으로 승격하지 않는다.
- 2026-08-25에 Android emulator `emulator-5554`에서 `SANBO_ANDROID_TAP_ACTION=stop`을 추가한 cold tap smoke를 실행했다. 첫 실행에서 UI 탐색기가 비활성 버튼과 부분 일치 상태 문구를 잘못 눌러 실패했고, 정확한 content-desc 우선 매칭과 `enabled=true` 확인을 보강한 뒤 다시 실행해 notification shade 탭, `기록 종료`, completed 세션 970.3855m와 유효 샘플 13개, 종료 후 provider 해제를 통과했다.
- 같은 보강 뒤 `SANBO_ANDROID_TAP_MODE=warm SANBO_ANDROID_TAP_ACTION=stop SANBO_ANDROID_ROUTE_EXCLUSION=1 SANBO_ANDROID_RESTART_PERSISTENCE=1`을 실행했다. warm tap 뒤 즉시 종료, 차량 구간 제외와 복원, 강제 종료 뒤 제외 상태 유지까지 통과했고 최종 세션은 1015.5173m, 유효 샘플 14개, provider 요청 없음이었다.
- 같은 날 `SANBO_ANDROID_NOTIFICATION_PERMISSION=deny SANBO_ANDROID_TAP_ACTION=stop`도 실행했다. 시스템 알림 없이 앱 내부 고속 경고에서 `기록 종료`를 선택해 970.3855m, 유효 샘플 13개의 completed 세션을 저장하고 provider 해제를 확인했다.
- 2026-08-25 최신 `main`에서 `SANBO_ANDROID_TAP_MODE=warm SANBO_ANDROID_TAP_ACTION=continue SANBO_ANDROID_NOTIFICATION_PERMISSION=grant`를 다시 실행했다. 프로세스를 유지한 warm tap 뒤 `계속 기록`으로 복귀했고 972.6537m, 유효 샘플 14개와 종료 후 provider 해제를 확인했다.
- 같은 최신 실행에서 `SANBO_ANDROID_TAP_MODE=cold SANBO_ANDROID_TAP_ACTION=stop SANBO_ANDROID_NOTIFICATION_PERMISSION=deny`를 실행했다. 시스템 알림 없이 앱 내부 고속 경고에서 `기록 종료`를 선택했고 970.3767m, 유효 샘플 13개의 completed 세션과 종료 후 provider 해제를 확인했다.
- 2026-08-25에 iOS scene manifest의 종료 상태 알림 탭 경로를 보강했다. `SceneDelegate`의 `connectionOptions.notificationResponse`를 AppDelegate의 readiness 버퍼로 전달하고, payload 검증 회귀 테스트를 추가했다. Android native unit test와 iOS RunnerTests 7개, iOS simulator의 실제 Core Location 고속 E2E와 fresh process notification channel probe를 다시 통과했다.
- 같은 날 현재 HEAD에서 Android emulator `emulator-5554`의 cold tap, `기록 종료`, 차량 구간 제외, 강제 종료 뒤 제외 상태 유지와 복원을 다시 실행했다. 최종 세션은 970.3855m, 유효 샘플 13개였고 종료 후 provider 요청은 없었다. iPhone 17 Pro simulator에서는 실제 앱을 백그라운드로 보낸 뒤 약 11m/s waypoint를 주입해 시스템 알림 센터에 `산책 기록을 계속할까요?`와 고속 이동 본문이 게시되는 것을 확인했다. simulator 접근성 입력으로 알림 행을 탭해 앱 재실행까지 판정하는 경로는 안정적으로 동작하지 않아 iOS cold tap 물리 판정은 올리지 않았다.
- 2026-08-25 최신 HEAD에서 핵심 Flutter 회귀 90개, Android native unit test, iOS RunnerTests 7개를 다시 실행해 모두 통과했다. 같은 실행에서 Android emulator `emulator-5554`의 `SANBO_ANDROID_TAP_MODE=cold SANBO_ANDROID_TAP_ACTION=stop SANBO_ANDROID_ROUTE_EXCLUSION=1 SANBO_ANDROID_RESTART_PERSISTENCE=1`을 통과했고, cold tap, `기록 종료`, 차량 구간 제외, 재시작 뒤 제외 상태 유지와 `제외 취소` 복원을 확인했다. 최종 세션은 927.4504m, 유효 샘플 13개였으며 종료 후 provider 요청은 없었다. iPhone 17 Pro simulator의 `SANBO_IOS_SCENARIO=high_speed` 실제 Core Location 경고 E2E와 fresh process notification channel probe도 통과했다. 이 실행은 simulator 증거이며 물리 기기 판정으로 승격하지 않는다.
- 2026-08-25에 iPhone 17 Pro simulator의 `SANBO_IOS_SCENARIO=high_speed` 실행 중 `xcrun simctl io 96749A10-F3A8-4C98-87EE-79A8EE439BDA screenConfig power off`로 화면 전원을 끄고 실제 Core Location 고속 E2E와 fresh process notification channel probe를 끝까지 통과했다. simulator 화면 전원 끄기는 iOS 잠금 화면이나 물리 기기 절전 정책의 증거가 아니므로 물리 기기 판정으로 승격하지 않는다.
- 최신 `main`에서 지원 SDK Flutter 3.47.1로 전체 Flutter 테스트 350개와 무작위 seed `92731` 전체 테스트 350개, `flutter analyze`, Android debug APK, Android native unit test와 iOS RunnerTests를 다시 통과했다. Android emulator 고속 cold tap은 `기록 종료`, 차량 구간 제외와 복원, 재시작 뒤 상태 보존까지 통과했고 최종 세션은 970.3944m, 유효 샘플 13개, 종료 후 provider 요청 없음이었다. 같은 실행에서 iOS simulator 화면 전원을 45초 뒤 끈 `SANBO_IOS_SCREEN_OFF=1` 고속 Core Location E2E와 fresh process notification channel probe도 통과했다.
- 2026-08-25 readiness handshake의 동시 `initialize()` 경로에서 이전 native engine의 in-flight `ready` Future를 재사용하지 않도록 회귀 테스트와 순차 재시도를 추가했다. 지원 SDK Flutter 3.47.1에서 관련 회귀 89개, 전체 테스트 351개와 무작위 seed `381927` 전체 테스트 351개, analyze, Android debug APK, Android native unit test와 iOS RunnerTests를 통과했다. 같은 변경 뒤 Android emulator cold tap 및 차량 구간 제외, 재시작 보존 smoke는 970.3944m, 유효 샘플 13개로 통과했고 iOS simulator 화면 전원 끄기 고속 Core Location E2E와 fresh notification channel probe도 통과했다.
- 같은 최신 `main`에서 도메인, 문서 계약, 알림 readiness 회귀 83개와 Android UI integration 2개를 다시 실행해 모두 통과했다. Android emulator `emulator-5554`의 `SANBO_ANDROID_TAP_MODE=cold SANBO_ANDROID_TAP_ACTION=stop SANBO_ANDROID_ROUTE_EXCLUSION=1 SANBO_ANDROID_RESTART_PERSISTENCE=1` smoke는 cold tap, `기록 종료`, 차량 구간 제외, 재시작 보존과 복원을 재현했고 최종 세션은 970.3855m, 유효 샘플 13개, 종료 후 provider 요청 없음이었다. 같은 HEAD에서 iOS simulator 화면 전원을 20초 뒤 끈 실제 Core Location 고속 E2E와 fresh process notification channel probe를 통과했다. `xcrun devicectl list devices`에는 물리 iOS 장비가 없어 이 결과를 물리 기기 판정으로 승격하지 않는다.
- 2026-08-25 커밋 `93c1a82`에서 Android Fused 위치 스트림이 첫 fix 이후 `LocationServiceDisabledException`, `PermissionDeniedException`, `PositionUpdateException`만 전달하고 닫히지 않는 경우를 즉시 LocationManager fallback으로 넘기도록 보강했다. 첫 fix 전 오류는 기존 startup fallback 경로를 유지하고, fallback 미지원 플랫폼은 복구를 시도하지 않도록 정책 회귀를 추가했다. 호환 SDK Flutter 3.47.1에서 전체 Flutter 테스트 352개, `flutter analyze`, PRD/TRD 구조 검증과 whitespace 검사를 통과했다.
- 같은 커밋의 로컬 Android emulator 고속 cold tap, `기록 종료`, 차량 구간 제외와 복원, 앱 재시작 보존 smoke는 970.3855m와 유효 샘플 13개로 통과했고 Android UI integration 2개도 통과했다. iOS simulator 화면 전원 끄기 고속 Core Location E2E와 fresh process notification channel probe, Android native unit test와 iOS RunnerTests도 통과했다. 원격 CI run `32800965938`은 커밋 `93c1a828189149a54ef2339999ff47350b430bee`에서 Flutter quality와 native platform tests 모두 성공했다.
- 2026-08-25에 Android emulator `emulator-5554`에서 `SANBO_ANDROID_TOGGLE_LOCATION_AFTER_START=1` provider smoke를 추가로 실행했다. 기록 중 위치 서비스를 끈 뒤 시스템 경고를 닫고 `미완료 기록` 복구 카드와 앱 provider 요청 해제를 확인했으며, 위치 서비스를 다시 켠 뒤 `이어서 기록`으로 복귀해 66.6927m, 유효 샘플 7개의 completed 세션과 종료 후 provider 해제를 통과했다. 첫 실행에서 알림 권한 대화상자가 복구 직후 다시 표시되는 환경 동작을 확인해 smoke가 거부 동작을 재사용하도록 보강했다. 이 결과는 에뮬레이터 증거이며 물리 기기 판정으로 승격하지 않는다.
- 같은 날 최신 `main`에서 iPhone 17 Pro simulator의 `SANBO_IOS_SCENARIO=high_speed SANBO_IOS_SCREEN_OFF=1 SANBO_IOS_SCREEN_OFF_DELAY_S=20`을 다시 실행해 실제 Core Location 고속 경고와 화면 전원 끄기 뒤 E2E, fresh notification channel probe를 통과했다. Android emulator에서는 Flutter renderer가 `0x0` surface를 반환하는 환경 상태를 재부팅과 debug APK 재빌드로 분리한 뒤 `SANBO_ANDROID_TOGGLE_LOCATION_AFTER_START=1`을 재실행해 61.5106m, 유효 샘플 6개의 completed 세션과 provider 해제를 통과했다. 잘못된 IANA timezone이 device-local instant를 보존하고 terminal stream recovery 상태에서 중복 provider 정리 없이 종료 저장하는 회귀 테스트를 추가해 전체 Flutter 테스트 355개와 analyze를 통과했다. simulator와 emulator 결과는 물리 기기 판정으로 승격하지 않는다.
- 2026-08-25 최신 `main`에서 Android emulator provider 장애 smoke를 다시 실행했다. 기록 중 위치 서비스를 끈 뒤 복구 카드와 provider 요청 해제를 확인하고 다시 켠 뒤 `이어서 기록`으로 완료했으며, 세션은 62.5923m와 유효 샘플 5개로 저장됐다. 같은 날 고속 cold tap에서 알림 거부, 앱 내부 `기록 종료`, 차량 구간 제외와 복원, 강제 종료 뒤 제외 상태 보존을 한 번에 다시 실행해 970.3767m와 유효 샘플 13개, 종료 후 provider 요청 없음을 확인했다. iOS simulator에서는 화면 전원을 20초 뒤 끈 고속 Core Location E2E와 fresh notification channel probe를 다시 통과했다. 모두 simulator와 emulator 증거이며 물리 기기 판정으로 승격하지 않는다.

이 로그는 자동화와 simulator 증거를 남기기 위한 것이며, 아래 물리 기기 행의
`미판정` 상태를 `통과`로 바꾸지 않는다.

| 확인 | 플랫폼 | 기기·OS | 권한 상태 | 기대 상태 | 관측 결과 | 통과/실패 |
|------|--------|---------|-----------|-----------|-----------|-----------|
| [ ] foreground warning without system banner | Android | 미기록 | 위치: 미기록, 알림: 미기록 | 앱 전면에서 28.8km/h 누적 60초 뒤 고속 종료 확인만 보이고 시스템 배너는 없다 | 미기록 | 미판정 |
| [ ] background notification | Android | 미기록 | 위치: 미기록, 알림: 미기록 | 백그라운드에서 highSpeed 알림이 표시되고 기록은 계속된다 | 미기록 | 미판정 |
| [ ] screen-off notification | Android | 미기록 | 위치: 미기록, 알림: 미기록 | 화면을 꺼도 highSpeed 알림이 도착하고 위치 수집은 계속된다 | 미기록 | 미판정 |
| [ ] warm tap | Android | 미기록 | 위치: 미기록, 알림: 미기록 | 실행 중인 앱에서 알림 탭 시 홈의 고속 경고로 이동한다 | 미기록 | 미판정 |
| [ ] killed-app cold tap | Android | 미기록 | 위치: 미기록, 알림: 미기록 | 종료된 앱에서 탭하면 복구 뒤 홈의 고속 경고를 재구성한다 | 미기록 | 미판정 |
| [ ] notification denied | Android | 미기록 | 위치: 허용, 알림: 거부 | 알림 권한 거부가 세션 생성, 위치 수집, 고속 상태 계산을 막지 않는다 | 미기록 | 미판정 |
| [ ] notification API failure | Android | 미기록 | 위치: 허용, 알림: 허용 또는 API 실패 주입 | 알림 API 실패가 기록, 위치 수집, 세션 저장을 막지 않는다 | 미기록 | 미판정 |
| [ ] continued background location | Android | 미기록 | 위치: 허용, 알림: 미기록 | 홈 이동과 화면 잠금 뒤 새 위치와 누적값이 계속 저장된다 | 미기록 | 미판정 |
| [ ] route exclusion | Android | 미기록 | 위치: 미기록, 알림: 미기록 | 전제: 완료 세션. 선택한 연속 구간만 `산책에서 제외`되고 지도와 모든 합계가 함께 갱신된다 | 미기록 | 미판정 |
| [ ] all-points exclusion | Android | 미기록 | 위치: 미기록, 알림: 미기록 | 전제: 완료 세션. 모든 점을 제외해도 세션과 원시 샘플은 남고 경로·집계는 0으로 갱신된다 | 미기록 | 미판정 |
| [ ] restore | Android | 미기록 | 위치: 미기록, 알림: 미기록 | 전제: 제외된 완료 세션. `제외 취소` 뒤 지도, 세션, 기록, 일별 합계가 원래 계산으로 함께 돌아온다 | 미기록 | 미판정 |
| [ ] app restart persistence | Android | 미기록 | 위치: 미기록, 알림: 미기록 | 전제: 제외된 완료 세션. 앱 재시작 뒤 제외 범위와 파생 분 기록, 지도와 합계가 유지된다 | 미기록 | 미판정 |
| [ ] foreground warning without system banner | iOS | 미기록 | 위치: 미기록, 알림: 미기록 | 앱 전면에서 28.8km/h 누적 60초 뒤 고속 종료 확인만 보이고 시스템 배너는 없다 | 미기록 | 미판정 |
| [ ] background notification | iOS | 미기록 | 위치: 미기록, 알림: 미기록 | 백그라운드에서 highSpeed 알림이 표시되고 기록은 계속된다 | 미기록 | 미판정 |
| [ ] screen-off notification | iOS | 미기록 | 위치: 미기록, 알림: 미기록 | 화면을 꺼도 highSpeed 알림이 도착하고 위치 수집은 계속된다 | 미기록 | 미판정 |
| [ ] warm tap | iOS | 미기록 | 위치: 미기록, 알림: 미기록 | 실행 중인 앱에서 알림 탭 시 홈의 고속 경고로 이동한다 | 미기록 | 미판정 |
| [ ] killed-app cold tap | iOS | 미기록 | 위치: 미기록, 알림: 미기록 | 종료된 앱에서 탭하면 복구 뒤 홈의 고속 경고를 재구성한다 | 미기록 | 미판정 |
| [ ] notification denied | iOS | 미기록 | 위치: 허용, 알림: 거부 | 알림 권한 거부가 세션 생성, 위치 수집, 고속 상태 계산을 막지 않는다 | 미기록 | 미판정 |
| [ ] notification API failure | iOS | 미기록 | 위치: 허용, 알림: 허용 또는 API 실패 주입 | 알림 API 실패가 기록, 위치 수집, 세션 저장을 막지 않는다 | 미기록 | 미판정 |
| [ ] continued background location | iOS | 미기록 | 위치: 허용, 알림: 미기록 | 홈 이동과 화면 잠금 뒤 새 위치와 누적값이 계속 저장된다 | 미기록 | 미판정 |
| [ ] route exclusion | iOS | 미기록 | 위치: 미기록, 알림: 미기록 | 전제: 완료 세션. 선택한 연속 구간만 `산책에서 제외`되고 지도와 모든 합계가 함께 갱신된다 | 미기록 | 미판정 |
| [ ] all-points exclusion | iOS | 미기록 | 위치: 미기록, 알림: 미기록 | 전제: 완료 세션. 모든 점을 제외해도 세션과 원시 샘플은 남고 경로·집계는 0으로 갱신된다 | 미기록 | 미판정 |
| [ ] restore | iOS | 미기록 | 위치: 미기록, 알림: 미기록 | 전제: 제외된 완료 세션. `제외 취소` 뒤 지도, 세션, 기록, 일별 합계가 원래 계산으로 함께 돌아온다 | 미기록 | 미판정 |
| [ ] app restart persistence | iOS | 미기록 | 위치: 미기록, 알림: 미기록 | 전제: 제외된 완료 세션. 앱 재시작 뒤 제외 범위와 파생 분 기록, 지도와 합계가 유지된다 | 미기록 | 미판정 |
