# S26 위치와 배터리 비교 측정

2026-11-07 사용자는 S26과 최신 Android를 사용한다고 알렸으며 연결과 실측은 추후로
미뤘다. 이 문서는 실행 절차다. 현재 배터리 절감률, GPS 정확도와 OS 버전 번호를
확정하는 측정 결과가 아니다.

## 연결 뒤 먼저 남길 정보

아래 조회는 읽기 전용이다. `SERIAL`은 실제 연결한 자신의 기기로 지정하고 공유
보고서에는 serial을 적지 않는다. 결과는 개인 로컬 자료로 보관한다.

```sh
adb -s SERIAL shell getprop ro.product.model
adb -s SERIAL shell getprop ro.build.version.release
adb -s SERIAL shell getprop ro.build.version.sdk
adb -s SERIAL shell getprop ro.build.display.id
adb -s SERIAL shell dumpsys package com.sanbo.sanbo
adb -s SERIAL shell dumpsys battery
adb -s SERIAL shell dumpsys batterystats --charged com.sanbo.sanbo
```

모델, OS/build, APK 버전과 commit, battery saver/최적화 설정, 충전 상태, 신호 환경,
화면 밝기와 켜진 시간을 각 회차에 남긴다. 앱 업데이트는 기존 기록을 보존한다.
앱 삭제나 전체 기록 삭제, 배터리 통계 reset, OS 절전 강제 전환은 계측에 필요하지 않다.

다른 앱이나 위치가 섞이는 전체 `dumpsys location`/logcat을 공유하지 않는다. 위
batterystats도 출력에 전역 정보가 포함될 수 있으므로 외부 보고서에는 산보의 CPU,
GPS와 WakeLock 누적량 및 시작/종료 배터리 값만 옮긴다. 원본 경로나 건강 자료를
외부 서버로 보내는 계측을 추가하지 않는다.

## 비교 행렬

기존 공개 후보와 후속 후보를 **동일한 build 종류**로 비교한다. debug의 CPU 수치를
release와 직접 비교하지 않는다. 각 모드는 동일한 충전 범위, 화면 조건과 비슷한
신호 환경에서 비교하고, 순서를 교차해 최소 3회 반복한다.

현재 설치본과 같은 서명의 후보를 사용한다. 서명이 다른 debug APK를 설치하기 위해
기존 앱을 삭제하지 않는다. 비교용 debug 앱이 필요하면 별도 테스트 환경을 사용하고,
실제 기록이 있는 설치본은 보존한다.

| 상황 | 시간과 확인 |
|---|---|
| 실외 정지 | 15분, 정지인데 GPS 거리/이동 시간이 누적되는지, provider 전환과 누적 CPU |
| 정상 걷기 | 30분 같은 경로, 외부 기준 거리, 포함 거리/이동 시간과 신호 공백 |
| 느린 걸음과 짧은 왕복 | 정해 둔 20m 왕복 반복, 확인 안내가 실제 왕복을 삭제하지 않는지 |
| 차/전철 앞뒤 걷기 | 같은 산책 ID, 제외와 공백, 하차 뒤 GPS 재개와 경계 선분 |
| 화면 끄기/다른 앱 전환 | 백그라운드 기록, 1초 UI ticker 정지, 복귀 뒤 정상 갱신 |
| provider 중단/복귀 | 기존 Samsung fallback의 복구, 중복 구독과 거짓 종료 없음 |

정밀/균형/절전의 요청 간격은 각각 4/8/20초이며 거리 필터와 함께 작동한다. 간격은
확정 수신 주기가 아니다. 정밀 모드만 CPU WakeLock을 요청하는 기존 계약도 대조한다.
짧은 콜백 침묵만으로 provider 장애를 확정하거나, fallback을 제거하는 비교를 먼저 하지 않는다.

## 기록과 판단

각 회차 전후에 같은 누적 통계를 읽어 차이를 낸다. GPS/CPU/WakeLock 시간은
batterystats와 동일한 기준 기간인지 확인한다. 재부팅/충전/통계 경계 변경이나 앱
프로세스 교체로 기준을 잃으면 해당 회차를 합산하지 않는다. provider 전환 횟수는
앱의 위치 진단 로그에서 정리하되 좌표/오류 원문을 공개하지 않는다. 로그 조회가
불가능한 release에서는 그 항목을 미측정으로 남긴다.

배터리 % 한 번의 차이로 절감률을 발표하지 않는다. 기기 전체 배터리 변화와 앱의
위치/CPU 사용을 함께 비교한다. 위치 누락, false vehicle/정지 판정과 복구 지연이
늘어나면 에너지 수치가 좋아도 개선으로 판정하지 않는다.

현재 offline 검증은 순수 분류/보존 회귀와 경로 분할 CPU 비교다.
`dart run scripts/benchmark_route_partition.dart`는 합성 입력과 이전 구현을 대조하지만
센서, 무선망, 화면과 실기기 배터리 비용을 측정하지 않는다.

공식 근거는 [Android의 위치 배터리 안내](https://developer.android.com/develop/sensors-and-location/location/battery)다.
정확도, 빈도와 전달 지연이 전력에 영향을 준다. 이 일반 원칙만으로 산보의 절감량을
계산하거나 사용자가 느낀 소모 원인을 확정하지 않는다.
