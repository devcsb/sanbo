# 산보 구조·배터리·UX 고도화 설계

작성일: 2026-08-29
상태: 구현 기준선
대상 릴리스: v0.8.x 이후

## 1. 목적과 제품 원칙

산보는 상시 감시 앱이 아니라 사용자가 명시적으로 시작한 산책을 차분히 되돌아보는
개인 기록 앱이다. 따라서 정확도·배터리·데이터 내구성을 하나의 숫자로 최적화하지
않고 다음 원칙을 유지한다.

1. 명시적으로 시작한 세션에서만 GPS를 사용한다.
2. 일상 걸음 수는 GPS 경로와 별도의 Health 데이터 소스로 읽는다.
3. 원본 샘플과 파생 집계를 구분하고, 파생 데이터는 재계산 가능하게 둔다.
4. 자동 종료·알림은 사용자를 압박하기보다 잊은 기록과 배터리 낭비를 줄이는 안전장치로
   표현한다.
5. 실패 시 조용히 성공한 것처럼 보이지 않고, 복구 가능한 상태와 다음 행동을 제시한다.

## 2. 현재 기준선과 발견된 위험

### 유지할 강점

- `SampleFilter → RoutePartitioner → WindowAggregator → SessionRollup`의 순수한 처리
  순서와 회귀 테스트.
- 세션 종료와 백업 가져오기의 transaction 경계.
- generation token, 유지보수 큐, 백그라운드 UI 업데이트 억제.
- 로컬 우선 저장, 정밀 위치 백업 경고, 빈 상태·오류·복구 CTA.

### 우선 해결할 위험

| 우선순위 | 문제 | 영향 |
|---|---|---|
| P1 | `deleteAll`, bulk label update, legacy completion API가 원자적이지 않음 | 부분 삭제·부분 편집 |
| P1 | active session 및 sample insert에 DB 멱등성 제약이 없음 | 중복 세션·중복 샘플 |
| P1 | 5시간/장기 정지 판단이 샘플과 Dart timer에 의존 | Doze/provider 정지 시 자동 종료 지연 |
| P1 | 상세 provider가 읽기 중 장소를 쓰고, playback마다 지도 전체를 재생성 | 테스트 어려움·상세 화면 끊김 |
| P1 | 세션 제어·저장소·상세 화면의 책임 집중 | 변경 범위와 회귀 위험 증가 |
| P2 | reduced-motion·자정 rollover·문자열 기반 오류 분기 | 접근성·예측 가능성 저하 |
| P2 | PRD/TRD의 MapLibre·gap 기준과 실제 구현의 불일치 | 변경 시 잘못된 기준 선택 |

## 3. 목표 아키텍처

### 3.1 포트와 어댑터

도메인과 UI는 concrete plugin 또는 SQLite에 직접 의존하지 않는다.

```text
features
  ├─ SessionViewModel / HistoryViewModel
  └─ widgets
application
  ├─ SessionLifecycleService
  ├─ SessionSafetyService
  ├─ ActivityAggregationService
  └─ BackupService
domain
  ├─ pipeline (현재 순수 처리 유지)
  ├─ ActivityDataSource
  ├─ SessionStore
  └─ models
data
  ├─ SqliteSessionStore
  ├─ SqliteActivityStore
  └─ SqliteBackupStore
platform
  ├─ GpsSessionDataSource (geolocator/FGS)
  ├─ HealthConnectDataSource
  ├─ HealthKitDataSource
  └─ DeadlineScheduler
```

```dart
abstract interface class ActivityDataSource {
  Future<ActivityPermission> permission();
  Future<ActivityDaySnapshot> readDays({
    required DateTime start,
    required DateTime endExclusive,
  });
}

abstract interface class SessionStore {
  Future<SessionSnapshot?> active();
  Future<WalkSession> start(StartSessionCommand command);
  Future<void> checkpoint(CheckpointCommand command);
  Future<WalkSession> finalize(FinalizeSessionCommand command);
  Future<void> deleteAll();
}
```

### 3.2 명시적 세션 상태

현재 여러 boolean 조합 대신 다음 상태를 application 계층에서 관리한다.

```text
Idle
Starting
Tracking
Warning
Stopping
RecoverableFailure
Completed
Discarded
```

기존 `LiveSessionState`는 단계적으로 이 상태를 노출하는 compatibility facade로 두고,
UI가 `errorMessage.contains('권한')`처럼 문구를 해석하지 않도록 typed error code를
사용한다.

### 3.3 단일 snapshot 읽기

세션 상세는 `session`, `samples`, `windows`, `exclusions`를 각각 읽지 않고 하나의
repository snapshot API로 읽는다. 읽기 provider는 절대 쓰기 부작용을 만들지 않는다.
장소 자동 연결은 명시적인 application command로 이동한다.

## 4. 배터리 및 자동 종료 설계

### 4.1 GPS 정책

- Android 기본 balanced: 8초/5m, CPU WakeLock 없음.
- battery saver: 20초/10m.
- high accuracy: 사용자가 명시적으로 선택한 경우에만 4초/2m + WakeLock.
- GPS 수집은 명시적 세션 동안에만 수행한다.
- 매 샘플 UI rebuild는 금지하고 aggregate snapshot만 foreground에 게시한다.
- checkpoint는 기본 30초를 유지하되, 샘플 batch와 시간 중 먼저 도달한 경우에만
  flush한다.

### 4.2 Health 데이터

Health Connect/HealthKit의 일별 걸음 수는 GPS 거리와 별도로 저장·표시한다.

- Android 누적 걸음 수는 raw record 합산이 아니라 aggregate API를 사용한다.
- 데이터마다 `source`, `observedAt`, `coverage`, `permission`을 보존한다.
- 권한 거부는 0걸음이 아니라 `unavailable`로 표시한다.
- Health 걸음 수를 GPS 세션 거리나 `validSampleCount`에 더하지 않는다.
- 첫 화면에서는 권한을 강제하지 않고, 일별 운동량 카드에서 선택적으로 연결한다.

### 4.3 내구성 있는 deadline

세션 시작 시 다음 값을 DB에 저장한다.

```text
started_at
stationary_warning_deadline
stationary_limit_deadline
duration_warning_deadline
duration_limit_deadline
```

평가는 다음 시점에 모두 수행한다.

1. 샘플 수신
2. checkpoint
3. 앱 foreground 복귀
4. Android scheduler callback
5. cold recovery

OS가 정확한 실행 시각을 보장하지 않는 경우에도 재개 즉시 deadline을 비교해 자동
종료하거나 복구 상태로 전환한다. 알림 실패는 기록을 중단시키지 않는다.

## 5. 데이터 무결성

1. `active` 세션에 partial unique index를 둔다.
2. 샘플 dedupe key를 저장하고 `INSERT OR IGNORE`로 checkpoint 재시도를 멱등화한다.
3. `deleteAll`, `finalize`, route edit, bulk label edit는 하나의 transaction 명령으로만
   노출한다.
4. update/delete count가 기대값과 다르면 transaction을 rollback한다.
5. backup export/import는 chunk/isolate 경로를 제공하고 50MB 상한 전 메모리 사용량을
   제한한다.
6. DB schema, backup schema, migration fixture를 같은 contract test로 검증한다.

## 6. 상세 화면과 전환

- 정적 경로 polyline과 playback marker를 분리한다.
- 좌표 → `LatLng` 변환과 단순화 결과를 snapshot에서 한 번만 계산한다.
- playback은 marker/진행선만 갱신하며 전체 `RouteMap`을 재생성하지 않는다.
- `MediaQuery.disableAnimations` 또는 접근성 reduced-motion 상태에서는 scroll/map
  animation을 즉시 완료한다.
- 기본 전환 시간은 180–260ms, 명시적인 완료/복구 CTA에만 haptic을 사용한다.
- 선택 상태·제외 상태는 색상만이 아니라 라벨과 아이콘으로도 구분한다.

## 7. 일별 운동량 UI

기록 화면은 다음 세 출처를 분리해 표시한다.

```text
오늘의 움직임
  걸음 수       Health Connect / HealthKit (연결 시)
  GPS 산책      산보가 저장한 완료 세션
  데이터 상태   연결됨 / 권한 필요 / 아직 없음
```

기록이 없는 날은 “실패”나 연속 기록 단절로 표현하지 않는다. 사용자는 날짜 범위,
동기화, 목표 및 알림을 각각 독립적으로 제어한다.

## 8. 오류·복구 UX

- `LocationErrorCode.permissionDenied`, `serviceDisabled`, `providerUnavailable`,
  `storageFailure`, `deadlineReached`를 typed 상태로 노출한다.
- 모든 오류는 `다시 시도`, `설정 열기`, `복구 저장`, `삭제` 중 가능한 다음 행동을
  명확히 표시한다.
- 백업 가져오기 중에는 파일명·세션 수·중복 처리 결과·실패 원인을 표시한다.
- 정지 경고와 5시간 경고는 한 번만 게시하고, snooze/계속 기록의 결과를 명시한다.

## 9. 검증 계획과 수용 기준

### 자동 검증

- 기존 356개 테스트 유지.
- active session 동시 시작 경쟁 테스트.
- sample checkpoint 재시도 중복 테스트.
- deleteAll 중간 오류 rollback 테스트.
- deadline이 샘플 없이도 foreground 복귀 시 처리되는 테스트.
- provider read가 DB write를 발생시키지 않는 테스트.
- 4,500개 샘플 playback frame/build 회귀 테스트.
- reduced-motion, 자정 rollover, 큰 글자 및 Semantics golden 테스트.

### 실기기 검증

- Galaxy Android 13 이상: 절전/균형/정밀, 화면 켬/끔, 60분 배터리 반복 2회.
- 제조사 절전/Doze, FGS 지속, 알림 권한 거부, provider 정지와 재개.
- iPhone: background location, 화면 잠금, 권한 승격, HealthKit 권한 철회.
- 결과는 `%/시간`, 샘플 간격 중앙값, 거리 편차, 자동 종료 지연으로 기록한다.

### 완료 조건

1. 원자적 저장 명령 외에 부분 상태를 만들 수 있는 public 경로가 없다.
2. Android에서 정상 권한·provider 조건의 60분 세션이 중복 없이 저장된다.
3. 자동 종료가 샘플 부재 후 foreground/cold recovery에서 반드시 정리된다.
4. playback과 기록 상세가 60fps 목표를 깨지 않는지 profile evidence가 있다.
5. Health 데이터가 GPS 거리와 혼합되지 않고 권한/출처가 표시된다.
6. PRD, TRD, 실제 map renderer와 gap 정책이 일치한다.

## 10. 단계적 출시

### Phase 1 — 무결성·내구성

DB index/dedupe, transaction API, deadline persistence, typed error를 먼저 적용한다.

### Phase 2 — 상세 성능·접근성

snapshot read, playback layer 분리, reduced-motion, 날짜 rollover를 적용한다.

### Phase 3 — Health 통합

Android Health Connect 읽기 전용을 먼저 출시하고, iOS HealthKit을 같은 port에 연결한다.

### Phase 4 — 실기기와 문서 정합성

Galaxy/iPhone 검증을 완료하고 PRD/TRD 및 release loop를 갱신한다.
