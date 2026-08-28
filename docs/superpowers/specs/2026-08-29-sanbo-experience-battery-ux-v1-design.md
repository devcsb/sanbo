# 산보 경험·배터리·구조 고도화 v1 설계

| 항목 | 내용 |
|---|---|
| 상태 | 구현 기준 설계안 |
| 대상 | Android·iOS GPS 산책 기록 앱 |
| 기준 브랜치 | `codex/architecture-battery-ux-hardening` |
| 기존 데이터 | SQLite v6와 기존 백업 포맷을 유지 |
| 핵심 원칙 | 회상 중심, 선택권 보장, 로컬 우선, 배터리 비용의 투명한 설명 |

## 1. 문제 정의

산보의 핵심 가치는 운동 성과 경쟁이 아니라 “나중에 그때 무엇을 했는지 다시 떠올리는 기록”이다. 따라서 가장 높은 정확도를 항상 강제하기보다 사용자가 선택한 정밀도·배터리·기록 지속성의 균형을 이해할 수 있어야 한다.

현재 구현은 위치 수집, 세션 복구, 트랜잭션 저장, 일별 GPS/건강 데이터 분리까지 상당 부분 갖추고 있다. 그러나 다음 문제가 남아 있다.

1. `SessionController`와 `WalkRepository`가 여러 책임을 동시에 가지므로 변경 영향 범위가 크다.
2. 위치 요청 주기는 의도적으로 완화되어 있지만 Android의 실제 callback은 best-effort이며, 물리 배터리 실측이 없다.
3. 화면별 전환·로딩·상태 표현의 공통 규칙이 부족하면 작은 기능 추가가 화면마다 다른 motion과 layout jump를 만들 수 있다.
4. 기록이 없는 사용자는 일별 운동량을 볼 수 없고, Health Connect/HealthKit의 권한·보존 기간·잠금 상태 차이를 충분히 알기 어렵다.
5. 회상 기능이 목표·알림·심리 상태 추론으로 확장되면 사용자의 자율성과 개인정보를 해칠 수 있다.

## 2. 조사 근거와 제품 결정

| 근거 | 관찰 | 산보에 적용하는 결정 |
|---|---|---|
| Strava 기록 기능 | GPS/가속도 기반 Auto-Pause, 화면 잠금, 오디오 cue를 선택적으로 제공 | 자동 판단은 보조 기능으로 두고 사용자가 계속 기록·종료를 선택 |
| Nike Run Club | Auto-Pause, 음성 피드백 주기, countdown, 자동 잠금 | 시작 전 한 번의 설정과 기록 중 최소 상태 표시를 제공 |
| Samsung Health | 일·주·월별 걸음 추이와 목표를 제공하며 기기 위치에 따라 수치가 달라질 수 있음 | 걸음 수는 GPS 거리와 별도 카드로 표시하고 목표·경쟁은 기본값으로 두지 않음 |
| 신체활동 앱 메타분석 | 자기 모니터링·피드백·목표·cue가 자주 사용되며 피드백의 효과는 있으나 표현 형식의 이질성이 큼 | 사실 기반 요약과 선택형 cue를 우선하고, 효과를 보장하는 치료 문구는 사용하지 않음 |
| 디지털 정신건강 참여 리뷰 | 유용성·개인화·통제감은 촉진 요인, 복잡성·기술 오류·과도한 부담은 장벽 | 알림 빈도·조용한 시간·데이터 삭제를 사용자가 통제하며 진단·기분 판정을 금지 |

참고: [Strava recording](https://support.strava.com/en-us/articles/15402137-recording-an-activity), [Nike Run Club settings](https://www.nike.com/help/a/nrc-settings/nrc-run-features), [Samsung Health steps](https://www.samsung.com/ca/support/mobile-devices/view-your-step-count-in-samsung-health/), [피드백 메타분석](https://pubmed.ncbi.nlm.nih.gov/38178230/), [신체활동 구성요소 메타분석](https://pubmed.ncbi.nlm.nih.gov/36396151/), [디지털 정신건강 참여 리뷰](https://pmc.ncbi.nlm.nih.gov/articles/PMC8074985/).

## 3. 목표와 비목표

### 3.1 목표

- 시작·복구·종료 상태를 사용자가 한 번에 이해한다.
- 화면이 꺼져도 수집을 유지하면서 UI·DB·알림의 불필요한 작업을 줄인다.
- 모든 화면 전환과 피드백이 일관되고, 큰 글자·Reduced Motion·스크린 리더에서도 같은 과업을 완료한다.
- GPS 거리, 로컬 산책 집계, Health Connect/HealthKit 걸음 수의 출처와 신선도를 구분한다.
- 앱 업데이트·재시작·저장 실패 뒤 기록을 잃거나 중복 생성하지 않는다.
- 사용자가 원할 때만 회상 메모와 알림을 사용하고, 실패·성취를 심리 상태로 해석하지 않는다.

### 3.2 비목표

- 의료 진단·치료·위기 대응·정신건강 상태 추론
- 상시 위치 수집, 소셜 비교, 리더보드, 스트릭 압박
- Samsung Health 전용 SDK 또는 계정 연동
- GPS를 건강 플랫폼 걸음 수로 대체하거나 두 수치를 합산
- 이번 단계에서 데이터베이스 전체 재작성

## 4. 사용자 시나리오와 수용 기준

### S1. 빠른 시작

사용자는 홈에서 10초 안에 기록을 시작하고, 권한 실패 시 원인·설정 이동·재시도를 구분해서 본다.

- 시작 버튼은 유휴 상태에서 항상 하나의 명확한 primary action이다.
- `Starting` 동안 중복 탭은 무시하고, 권한·서비스·알림 실패는 typed error code로 표현한다.
- 첫 유효 fix 전에는 “GPS 보정 중”을 표시하며 저장 실패와 혼동하지 않는다.

### S2. 화면을 끄고 걷기

사용자는 화면을 잠가도 기록이 계속되는지 신뢰할 수 있어야 한다.

- Android foreground service와 iOS background location을 세션 동안만 유지한다.
- 백그라운드에서는 1초 ticker와 매 fix UI 발행을 중지한다.
- 샘플은 30초 또는 모드별 batch 조건으로 저장하고, 종료 시 남은 샘플을 transaction으로 flush한다.
- 앱이 foreground로 돌아오면 최신 집계·경고·오류를 한 번에 동기화한다.

### S3. 잊고 켜둔 기록

한 장소 20분, 전체 4시간 45분에는 한 번 안내하고, 각각 30분·5시간에는 자동 저장·종료한다.

- 한 이벤트는 세션마다 한 번만 알린다.
- `계속 기록`을 누르면 경고만 해제하고 실제 이동·정지 판단은 계속한다.
- 자동 종료 사유는 완료 알림·기록 상세·복구 카드에서 동일한 문구로 보인다.
- 프로세스가 죽어도 저장된 deadline으로 다음 실행 시 만료를 판정한다.

### S4. 일별 운동량과 회상

사용자는 특정 날짜의 GPS 산책 합계와 외부 걸음 수를 함께 보되, 서로 다른 의미임을 이해한다.

- 일별 카드에는 거리·시간·산책 횟수와 걸음 수를 별도 슬롯으로 둔다.
- `0`은 유효한 0이고 `null`은 권한 없음·지원 불가·읽기 실패다.
- Health Connect/HealthKit 출처, 마지막 조회 시각, 제한된 과거 범위를 설명한다.
- 기록이 하나도 없어도 오늘의 운동량 진입점을 사용할 수 있다.

### S5. 회상 메모

사용자는 원하는 날짜나 장소에 짧은 사실 메모를 남길 수 있다.

- 메모·장소·사용자 라벨은 명시적 저장 버튼을 눌렀을 때만 로컬에 쓴다.
- “오늘 잘했어요”, “우울해 보여요” 같은 판정 문구는 사용하지 않는다.
- 삭제·전체 백업·가져오기는 사용자가 확인하고 되돌릴 수 있는 흐름을 가진다.

## 5. 목표 아키텍처

### 5.1 경계

```text
Presentation
  └─ SessionController facade / History providers / Transition widgets
Application
  ├─ SessionLifecycleCoordinator
  ├─ SessionSafetyCoordinator
  ├─ SessionPersistenceCoordinator
  ├─ DailyActivityService
  └─ SessionPresentationMapper
Domain
  ├─ SessionPipeline
  ├─ SampleFilter / RoutePartitioner
  ├─ SessionGuard / SessionDeadlinePolicy
  └─ Local calendar and pure statistics
Infrastructure
  ├─ LocationEngine (geolocator / synthetic)
  ├─ ActivityDataSource (Health Connect / HealthKit)
  ├─ WalkStore (SQLite)
  ├─ NotificationService
  └─ BackupFileService
```

`SessionController`는 당장 제거하지 않고 facade로 남긴다. 새 coordinator를 주입 가능한 interface로 만들고 기존 public method를 위임하게 하여, 한 단계씩 추출한다. 기존 백업 포맷과 `WalkRepository`의 호출 계약은 migration adapter가 안정화될 때까지 유지한다.

### 5.2 명시적 상태 모델

```text
Idle
 └─ start → Starting
Starting
 ├─ permission/service error → Idle(error)
 ├─ engine ready → Tracking
 └─ storage error → Recoverable
Tracking
 ├─ warning → Tracking(warning)
 ├─ stop → Saving
 ├─ stream/storage failure → Recoverable
 └─ deadline → Saving(autoStopReason)
Saving
 ├─ success → Completed
 └─ failure → Recoverable
Recoverable
 ├─ retry/resume → Starting or Saving
 └─ discard → Idle
```

상태 전이 불변식:

- active session은 최대 하나다.
- `Tracking`이 아니면 native location stream은 실행되지 않는다.
- `Saving` 진입 전에는 pending sample을 flush한다.
- `Completed`가 아니면 history 목록에 표시하지 않는다.
- 하나의 warning kind와 session id 조합은 중복 발행하지 않는다.

### 5.3 데이터 흐름

```text
LocationEngine
  → LocationSampleAccumulator
  → SampleFilter / SessionGuard
  → SessionPersistenceCoordinator (batch checkpoint)
  → SessionPipeline (final rollup)
  → History / Detail / Daily Stats

Health Connect / HealthKit
  → DailyActivityService (on-demand, read-only)
  → Daily Activity UI
```

GPS와 Health read는 서로의 실패나 배터리 예산을 전파하지 않는다. Health 결과는 세션 DB에 복제하지 않고, 출처·coverage·조회 시각을 포함한 view model로 전달한다.

## 6. 배터리 설계

### 6.1 기본 프로필

| 모드 | accuracy | 요청 주기 | 거리 필터 | Wake lock |
|---|---|---:|---:|---|
| 절전 | medium | 20초 | 10m | 끔 |
| 균형 | high | 8초 | 5m | 끔 |
| 정밀 | bestForNavigation | 4초 | 2m | 켬 |

주기는 목표값일 뿐 OS가 보장하는 callback 주기가 아니다. Android에서는 위치 batching·최소 간격 설정 가능성을 별도 adapter 옵션으로 검증한다. 사용자가 고른 모드를 임의로 바꾸지 않고, 배터리 15% 이하에서만 “절전으로 전환할까요?”라는 선택형 안내를 제공한다.

### 6.2 작업 예산

- UI: foreground ticker 1초, background에서는 0회
- DB: 30초 checkpoint 또는 모드별 약 30초 분량 batch
- 네트워크: GPS callback·Health read 경로에서 호출하지 않음
- Health: 화면 요청 시 1회, observer/background polling 금지
- 알림: safety event별 1회, 선택형 회상 알림은 기본 꺼짐·quiet hours 지원

### 6.3 배터리 측정

자동 테스트는 배터리 퍼센트를 증명하지 않는다. 출시 전 동일 기기·밝기·온도·화면 꺼짐·신호 조건으로 절전/균형/정밀 60분을 측정한다.

- 균형: 60분당 평균 5%p 이하를 회귀 목표로 둔다.
- 정밀: 60분당 평균 8%p 이하를 회귀 목표로 둔다.
- 목표 초과 시 위치 profile, 화면 상태, 제조사 배터리 정책, 네트워크 조건을 함께 기록한다.

## 7. 화면 전환과 이펙트 규칙

### 7.1 공통 motion token

| 상황 | 기본 시간 | 동작 |
|---|---:|---|
| 화면·카드 교체 | 180ms | fade + 짧은 layout transition |
| 경고/복구 패널 확장 | 240ms | size + fade, 내용 위치 고정 |
| 성공·저장 확인 | 120ms | opacity 또는 color 강조 |
| Reduced Motion | 0ms | 즉시 상태 전환 |

- `AnimatedSwitcher`에는 상태별 stable key를 사용해 재생성 깜박임을 막는다.
- 로딩은 고정 높이 skeleton/placeholder를 사용해 layout jump를 막는다.
- 지도와 긴 목록은 전환 애니메이션 대상에서 제외하고, 새 데이터가 준비된 뒤 cross-fade한다.
- 자동 반복·탄성·화면 전체 확대 효과는 사용하지 않는다.
- 모든 비동기 callback은 `mounted` 또는 provider generation을 확인한 뒤 화면을 갱신한다.

### 7.2 접근성

- primary/secondary button 최소 48dp
- text scale 1.8 이상에서 가로 overflow 0
- 상태 변화는 색만으로 전달하지 않고 text·Semantics로 병행
- TalkBack/VoiceOver가 “기록 중, 샘플 n개, 거리 x km”를 한 번에 이해
- Reduced Motion에서도 경고·저장 완료·복구 상태가 사라지지 않음

## 8. 알림·심리적 안전

자기 모니터링과 사실 기반 피드백은 유용할 수 있지만, 앱은 의료 서비스가 아니다. 알림은 행동을 통제하는 장치가 아니라 사용자가 선택한 기록을 보존하는 안전장치로 정의한다.

- 20분 정지·4시간 45분 경고는 기록 손실 방지 목적이며 세션당 한 번만 발행한다.
- 30분 정지·5시간 종료는 자동 저장 사유를 명시한다.
- 선택형 회상 알림은 시간대·요일·빈도·일시중지·전체 해제를 제공한다.
- 알림 문구는 관찰형으로 쓴다. 예: “오늘 기록을 돌아볼까요?”
- 죄책감·실패·진단·치료·정신상태 추론·사회 비교·스트릭을 기본 UX에 넣지 않는다.
- 건강·위치·메모 데이터의 수집 범위, 보존, 삭제, 백업 포함 여부를 설정에서 계속 확인할 수 있게 한다.

## 9. Health Connect/HealthKit 정책

- Android는 Health Connect의 `READ_STEPS`와 Activity Recognition을 요청하고, iOS는 HealthKit read permission을 요청한다.
- 최초 진입에서는 권한 대화상자를 자동으로 띄우지 않는다.
- 이미 연결된 Android 권한은 읽을 수 있고, iOS는 read permission을 공개하지 않으므로 실제 read 실패를 별도 상태로 보여준다.
- 0걸음·권한 거부·지원 불가·잠금 상태 오류를 각각 구분한다.
- Health Connect 기본 과거 조회 제한은 UI에 표시하고, 필요한 경우 역사 데이터 권한을 별도 opt-in으로 확장한다.
- Health 데이터는 산보의 GPS 거리·속도·칼로리로 변환하지 않는다.
- Android manifest에는 권한 화면에서 연결되는 실제 privacy policy 활동/URL을 릴리즈 전에 추가한다.

`health` 패키지는 Apple HealthKit과 Google Health Connect를 공통 API로 제공하지만 Android API 26 이상, Activity Recognition, Android 14의 `FlutterFragmentActivity` 및 Health Connect privacy 안내 구성이 필요하다. 자세한 플랫폼 요구사항은 [health 패키지 문서](https://pub.dev/packages/health)를 따른다.

## 10. 오류·복구·데이터 보존

- 플랫폼 adapter는 `LocationFailureKind`, `ActivityAccessState` 같은 안정된 타입을 반환한다.
- 외부 예외 문자열 parsing은 adapter 경계의 최종 fallback으로만 허용한다.
- checkpoint 실패는 메모리 pending queue에 보존하고 다음 checkpoint/종료/복구에서 재시도한다.
- 종료 transaction은 samples·windows·rollup을 함께 commit/rollback한다.
- 백업 import는 파일 크기·schema version·좌표·시간 범위를 검증하고 실패 시 기존 DB를 변경하지 않는다.
- 모든 오류 화면은 “무엇이 실패했는지 / 기록이 남아 있는지 / 다시 시도할지 / 설정으로 갈지”를 함께 보여준다.

## 11. 구현 단계

### Phase 1 — 경험 안전선

- 공통 motion token과 `AnimatedSwitcher`/skeleton primitive 도입
- 기록 없음 상태에서도 일별 운동량 진입점 제공
- Health source freshness·30일 제한·잠금/권한 copy 보강
- 위치 lifecycle/async generation 테스트 확장
- frame timing·callback count·DB batch 시간을 로컬 진단 로그로 측정하되 기본 전송하지 않음

### Phase 2 — 경계 추출과 배터리 적응

- `SessionController`에서 persistence/safety/accumulator를 순차 추출
- `LocationEngine.reconfigure` 계약을 추가해 profile 변경이 실제 native stream 재시작으로 이어지는지 보장
- 배터리 15% 이하 선택형 절전 전환, 정지 경고 중 고주기 UI 작업 억제
- Route playback cursor와 daily Health read TTL cache 도입

### Phase 3 — 출시·플랫폼 완결

- Health Connect privacy policy activity-alias와 Play Data Safety 문서 완성
- API 24/25 지원 중단 여부를 릴리즈 노트에 명시하거나 location-only 대안을 결정
- Galaxy 실기기·iPhone 실기기 권한/잠금/백그라운드/배터리 매트릭스 수행
- legacy KGP 경고가 없는 health plugin 버전 또는 대체 adapter 확인

## 12. 테스트 전략과 출시 기준

### 자동화

- 상태 전이 property/invariant test
- location stream late callback·dispose·generation test
- notification deduplication test
- 0/null/error/partial Health data test
- DST·시간대·30일 경계 test
- large text·TalkBack semantics·Reduced Motion widget test
- 1k/10k/50k sample playback benchmark
- `flutter analyze`, 전체 Flutter test, Android native test, iOS XCTest, Android debug/release build

### 실기기

- Android 10/13/14+, Samsung 배터리 최적화, FGS 알림 거부
- iOS 화면 잠금, Always 권한 승격, protected Health data 잠금
- 야외·실내·터널·네트워크 단절
- 정지 20/30분, 전체 4:45/5시간, 강제 종료 후 복구
- 백업 가져오기 중 종료, 중복 import, 잘못된 파일

### 출시 차단 조건

1. Privacy policy 연결과 민감 건강 권한 설명이 준비되지 않음
2. 실기기에서 기록이 멈추거나 세션 종료 후 native location이 남음
3. 데이터 손실·중복·복구 불가가 재현됨
4. 큰 글자·Reduced Motion에서 핵심 과업을 완료할 수 없음
5. 측정하지 않은 배터리 수치를 마케팅 문구로 사용함

## 13. 결정 로그

- GPS는 제품 핵심 기록이므로 제거하지 않고 profile·batch·UI suppression으로 비용을 관리한다.
- Health steps는 외부 데이터의 의미를 보존하기 위해 GPS와 합산하지 않는다.
- 전면 재작성 대신 facade와 coordinator를 이용한 점진적 추출을 선택한다.
- 자동 알림은 기록 보존에 필요한 safety event만 기본 활성화한다.
- 심리학·정신의학 연구는 행동 변화와 안전 UX의 참고로만 사용하고, 개인 진단이나 치료 권고로 확장하지 않는다.
