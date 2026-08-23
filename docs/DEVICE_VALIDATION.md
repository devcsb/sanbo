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

고속 경고와 killed-app cold tap을 같은 순서로 반복하려면 다음 명령을 사용한다.

```bash
SANBO_ANDROID_DEVICE_ID=emulator-5554 \\
  bash scripts/run_android_high_speed_cold_tap_smoke.sh
```

이 명령은 약 11m/s GPS 경로를 백그라운드에서 주입하고, `4103` 알림 게시,
`am crash` 뒤 notification shade 탭, 복구 경고, 계속 기록, 완료 저장과 provider
해제를 한 번에 확인한다. emulator 결과는 물리 기기 행의 통과 판정으로 승격하지 않는다.

알림 권한 거부 경로는 `SANBO_ANDROID_NOTIFICATION_PERMISSION=deny`를 추가한다.
기본값은 `grant`이며, 어느 모드에서도 위치 기록과 세션 저장 결과를 확인한다.
화면을 끈 상태의 provider 지속성은 `SANBO_ANDROID_SCREEN_OFF=1`을 추가해
에뮬레이터에서 반복할 수 있다.

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
- 같은 커밋에서 iPhone 17 Pro simulator `96749A10-F3A8-4C98-87EE-79A8EE439BDA`의 Core Location smoke를 다시 실행해 실제 provider E2E 1개가 통과했다.
- 커밋 `54988e7`에서 iPhone 17 Pro simulator의 실제 Core Location 고속 세션을 완료한 뒤 차량 구간을 제외하고 복원하는 경로까지 통과했다. 제외 전후 세션 집계와 경로가 복원되는지 저장소에서 확인했다.
- Android emulator에서 기록 중 위치 권한을 철회한 뒤 앱을 다시 열었다. `미완료 기록` 복구 카드가 나타났고, 위치 권한을 다시 허용해 `이어서 기록`을 선택한 뒤 세션을 완료했다. DB에는 `completed`, 거리 11.33m, 유효 샘플 3개가 저장됐다.
- 알림 channel이 늦게 등록되는 cold-start를 가정한 handshake 회귀 테스트를 추가하고, 전체 Flutter 테스트 338개, analyze, Android debug APK와 native Android unit test, iOS simulator XCTest를 다시 통과했다.
- Android emulator `emulator-5554`에서 고속 cold tap smoke를 다시 실행했다. 프로세스 종료 뒤 notification shade 탭, 복구 화면, 계속 기록과 세션 완료가 통과했고, 완료 세션은 거리 708.13m, 유효 샘플 10개였으며 종료 후 provider 요청은 없었다.
- iPhone 17 Pro simulator `96749A10-F3A8-4C98-87EE-79A8EE439BDA`에서 실제 Core Location 고속 시나리오와 차량 구간 제외 및 복원 통합 테스트를 다시 실행해 통과했다.

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
