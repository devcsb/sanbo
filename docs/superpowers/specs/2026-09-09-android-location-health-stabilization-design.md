# Android 위치정보 안정화와 Health Connect 설정 진입 설계

**문서 ID:** SANBO-ANDROID-STABILITY-2026-09  
**상태:** 구현 기준 설계  
**대상 릴리즈:** 현재 `main`의 `0.9.0+14` 코드와 릴리즈 이후 변경사항  
**작성일:** 2026-09-09

## 1. 배경과 문제 정의

현재 산보는 `geolocator` 기반 Android/iOS 위치 수집, Android foreground
service, 위치 provider 정지 시 LocationManager fallback, 원본 샘플 보존과
분 단위 재집계까지 구현되어 있다. 현재 관련 Flutter 테스트와 analyzer는
통과하지만, 자동화 테스트만으로는 제조사 위치 provider, approximate location,
화면 잠금, 배터리 절전 정책과 Health Connect 설정 UI를 증명할 수 없다.

현재 코드 조사에서 확인된 제품 경계는 다음과 같다.

1. 위치 권한이 허용되어도 Android 12+의 approximate 위치인지 별도로 확인하지
   않는다.
2. provider가 전달한 첫 fix와 one-shot fix는 좌표·timestamp·정확도 검증이
   controller와 pipeline에 분산되어 있다. stale cached fix가 callback으로
   도착해도 provider boundary에서 신선한 fix인지 명시적으로 표현하지 않는다.
3. Health Connect 연동은 `requestAuthorization`과 걸음 수 조회까지만 제공하며,
   앱별 Health Connect 권한 관리 화면을 여는 capability가 없다.
4. Health Connect 설정에서 권한을 바꾼 뒤 앱으로 돌아와도 기존 5분 cache가
   남아 있으면 최신 연결 상태가 즉시 반영되지 않을 수 있다.

## 2. 목표

### 2.1 위치

- Android 산책 기록 시작 전에 precise/reduced location 상태를 구분한다.
- 산책 경로 anchor가 되기 전 위치 sample의 좌표, timestamp, 정확도와 freshness를
  하나의 순수 정책으로 검증한다.
- stale, 미래 시각, malformed, hard accuracy 초과 sample은 원본 audit row로
  보존하되 live route와 최종 집계에는 포함하지 않는다.
- live, crash recovery, finalize가 같은 경계 규칙을 사용한다.
- 기존 fused stream, LocationManager fallback, FGS, 저장 재시도와 원본 보존
  계약을 깨지 않는다.
- 진단 정보는 callback/accept/reject/fallback 상태 같은 제한된 집계만 기록하고
  원시 좌표·걸음 수를 기록하지 않는다.

### 2.2 Health Connect

- Android에서 연결되지 않은 건강 데이터 영역을 누르면 Health Connect의 앱별
  권한 관리 화면으로 이동할 수 있게 한다.
- Android 14 framework와 Android 13 이하 provider 차이를 native adapter에서
  흡수한다.
- Health Connect가 없거나 업데이트가 필요한 경우 설치 안내를 유지한다.
- 설정 화면에서 권한을 바꾸고 돌아오면 상태와 일별 걸음 수를 다시 읽는다.
- iOS HealthKit 권한과 기존 GPS 거리/Health 걸음 수 분리 계약은 유지한다.

## 3. 비목표

- Android 위치 provider를 직접 새로 작성하거나 `geolocator`를 제거하지 않는다.
- 실측 증거 없이 정확도 threshold, interval, 배터리 정책을 임의로 완화하지
  않는다.
- Health Connect 백그라운드 동기화, 쓰기 권한, 운동 경로 저장을 추가하지 않는다.
- GPS 거리와 Health 걸음 수를 합산하지 않는다.
- 서버, 계정, 원격 진단 로그를 추가하지 않는다.
- 현재 사용자 작업으로 남아 있는 자동 경로 제외 변경을 재작성하거나 정리하지
  않는다.

## 4. 공식 플랫폼 기준

Android Health Connect 공식 API는 앱별 권한 관리를 위해
`HealthConnectClient.getHealthConnectManageDataIntent(context, packageName)`를
제공한다. 이 API를 우선 사용하고, 사용할 수 없는 기기에서는 SDK가 제공하는
Health Connect settings action과 provider/package fallback을 순차적으로
시도한다.

Health Connect는 Android 14 이상에서 framework/system UI로 제공되고, Android
13 이하에서는 provider 앱 설치 여부에 의존한다. 앱 설정의 Manage access는
사용자의 앱별 Health Connect 권한 관리 화면으로 직접 연결되어야 한다.

Android 위치 기능은 approximate와 precise 권한을 별도로 취급해야 한다. 산보는
경로를 기록하는 기능이므로 Android reduced location에서는 경로 기록을 시작하지
않고 사용자가 산보 앱의 위치 권한 설정에서 precise를 활성화하도록 안내한다.

## 5. 제안 아키텍처

### 5.1 위치 품질 경계

새 순수 Dart 정책 파일 `lib/domain/services/location_quality_policy.dart`를
추가한다.

```dart
enum LocationQualityRejection {
  invalidCoordinate,
  invalidTimestamp,
  staleTimestamp,
  futureTimestamp,
  excessiveAccuracy,
  beforeSession,
  outOfOrder,
}

class LocationQualityDecision {
  const LocationQualityDecision.accepted() : rejection = null;
  const LocationQualityDecision.rejected(this.rejection);

  final LocationQualityRejection? rejection;
  bool get accepted => rejection == null;
}

class LocationQualityPolicy {
  const LocationQualityPolicy({
    this.maxAge = const Duration(seconds: 30),
    this.maxFutureSkew = const Duration(seconds: 5),
    this.hardMaxAccuracyM = 500,
  });

  final Duration maxAge;
  final Duration maxFutureSkew;
  final double hardMaxAccuracyM;

  LocationQualityDecision evaluate({
    required LocationSample sample,
    required DateTime observedAt,
    DateTime? sessionStart,
    DateTime? previousAccepted,
  });
}
```

`GeolocatorLocationEngine`은 Position을 `LocationSample`으로 변환한 직후 이
   정책을 사용한다. 거부된 sample도 `isFilteredOut=true`로 stream에 전달해
   controller가 audit 저장을 유지하게 한다. 단, `_lastEmitAt`은 callback이
   도착했다는 사실만으로 갱신하지 않고 freshness를 통과한 sample에서만 갱신한다.
   따라서 오래된 cached fix가 stall watchdog를 잘못 해제하지 않는다.

`SessionController._onSample`은 같은 정책을 session boundary와 out-of-order
   판정에 재사용한다. 기존 `SampleFilter`는 jump/soft accuracy/path geometry를
   담당하며, quality policy와 역할을 중복하지 않는다. finalize와 recovery는
   기존 pipeline 재실행 시 동일 boundary를 적용한다.

### 5.2 Android precise location

`LocationPermissionState`에 `reducedAccuracy`를 추가한다. Android에서 foreground
location permission이 granted인 뒤 `Geolocator.getLocationAccuracy()`가
`LocationAccuracyStatus.reduced`를 반환하면 `requestPermission()`은
`reducedAccuracy`를 반환한다.

controller는 이 상태에서 session을 만들거나 provider를 시작하지 않는다. Home의
오류 banner는 precise 권한을 설명하고 기존 `openSystemSettings()`로 앱 설정을
연다. 기존 denied, deniedForever, serviceDisabled, grantedForegroundOnly 흐름은
각각 유지한다.

### 5.3 Health Connect capability

기존 읽기 계약을 깨지 않도록 설정 진입을 별도 optional capability로 둔다.

```dart
abstract interface class ActivityDataSourceSettingsOpener {
  Future<bool> openSettings();
}
```

`HealthActivityDataSource`는 이 capability를 구현한다. Android 구현은 별도
`sanbo/health_connect` MethodChannel을 통해 native로 위임한다.

Native 호출 순서는 다음과 같다.

1. `HealthConnectClient.getSdkStatus(context)`가 `SDK_AVAILABLE`이면
   `getHealthConnectManageDataIntent(context, context.packageName)`를 만든다.
2. Intent에 resolve 가능한 activity가 있으면 실행한다.
3. 그렇지 않으면 `HealthConnectClient.getHealthConnectSettingsAction()`으로
   settings Intent를 시도한다.
4. provider가 설치되지 않았거나 update-required이면 기존 Health plugin의
   install flow를 사용하거나 false를 반환해 Flutter가 설치 안내를 표시한다.
5. `ActivityNotFoundException`과 SecurityException은 앱 crash가 아니라 false로
   반환한다.

Health Connect Intent를 실행하는 책임은 native adapter에만 둔다. Flutter UI는
   package name, action string, API level을 알지 않는다.

### 5.4 Health UI와 resume refresh

현재 연결 action은 Android에서는 Health Connect 앱별 관리 화면으로 이동하도록
   연결한다. 설정에서 돌아온 뒤 `ActivityDataSourceSettingsOpener` 호출 결과를
   기다리는 것이 아니라, 앱 `onResume`에서 다음을 수행한다.

- optional `ActivityDataSourceCacheInvalidator` capability가 있으면 cache를
  비운다.
- `dailyActivityProvider`를 invalidate한다.
- 다음 read에서 `hasPermissions`를 다시 확인하고 최신 상태를 표시한다.

연결됨/권한 거부/지원 불가/읽기 오류/유효한 0걸음은 현재의 상태 모델을 유지한다.

## 6. 오류와 데이터 보존

- malformed 또는 stale sample은 raw location row로 남기되 route anchor, distance,
  speed, valid sample count에는 포함하지 않는다.
- precise 권한 미충족은 권한 오류와 구분되는 사용자 안내 상태로 표시한다.
- Health Connect 설정을 열 수 없으면 Flutter 화면에 재시도 가능한 오류를 표시한다.
- Health Connect 권한 변경 직후 cache를 비워 stale daily total을 표시하지 않는다.
- native 위치 stream, FGS, timer, notification 정리 계약은 변경하지 않는다.
- 진단에는 rejection reason별 개수와 provider recovery 횟수만 포함할 수 있으며,
  좌표·정확한 위치·health value는 포함하지 않는다.

## 7. 테스트 전략

각 task는 다음 순서를 강제한다.

1. 실제 요구 동작을 보여주는 failing test 작성
2. 해당 테스트가 기능 부재 때문에 실패하는지 확인
3. 최소 production code로 GREEN
4. 관련 기존 테스트와 전체 회귀 테스트 실행
5. GREEN 상태에서만 refactor

테스트 층은 다음과 같다.

- 순수 정책 unit test: malformed, stale, future, session boundary, out-of-order,
  acceptable cold fix
- 위치 engine policy test: reduced permission mapping, valid fix만 watchdog baseline
  갱신, filtered provider fix 보존
- controller/widget test: reduced accuracy에서 session 미생성, 설정 CTA 노출 및
  호출
- Health data source test: settings capability와 cache invalidation 계약
- Android Kotlin unit test: SDK available/manage intent, action fallback, invalid
  intent handling, method channel result contract
- 전체 `flutter test --no-pub --concurrency=1`, `flutter analyze --no-pub`, Android
  native unit test, debug APK build
- 연결된 Android 기기가 생기면 Samsung/Pixel matrix에서 permission, outdoor cold
  start, screen lock, background, provider disabled/re-enabled, Health Connect
  permission grant/revoke/return flow를 수동 검증한다.

현재 환경에서는 `adb devices`에 연결된 Android 기기가 없으므로 실기기 결과는
자동화 결과와 분리해 기록한다. emulator가 제공되면 emulator 증거로만 표시하고
실기기 판정으로 승격하지 않는다.

## 8. 성공 기준

- Android approximate location 상태가 명확히 감지되고 precise 설정으로 안내된다.
- stale/malformed/future 위치가 경로와 집계를 오염시키지 않는다.
- provider stall/recovery와 기존 세션 lifecycle 회귀가 없다.
- 연결되지 않은 Android Health 영역에서 앱별 Health Connect 권한 관리 화면으로
  이동할 수 있다.
- 설정에서 돌아온 뒤 Health 연결 상태와 일별 걸음 수가 cache 없이 재평가된다.
- 기존 iOS HealthKit, GPS/Health 데이터 분리, raw sample 보존, 사용자 자동 제외
  작업과 충돌하지 않는다.
- 자동화 테스트·analyze·Android unit test·debug build가 모두 통과한다.
- 물리 Android 검증이 수행되지 않은 상태에서는 물리기기 안정화를 완료했다고
  주장하지 않는다.
