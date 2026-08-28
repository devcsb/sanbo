# PRD: 산보 아키텍처·배터리·회상 UX 고도화 v0.9

| 항목 | 내용 |
|---|---|
| 문서 ID | `PRD-SANBO-ARCH-UX-v0.9` |
| 상태 | 구현 기준선 및 후속 검증 계획 |
| 기준 릴리즈 | 0.9.0 |
| 범위 | Android 우선, 로컬 우선, GPS 세션 기록 (Android API 26+) |
| 관련 문서 | [PRD](./PRD.md), [TRD](./TRD.md), [PLATFORM_AND_MAPS](./PLATFORM_AND_MAPS.md) |

## 1. 제품 판단 요약

산보는 운동 성과 앱이 아니라 “나중에 그때 무엇을 했는지 다시 떠올리는 개인 동선 일지”다. 따라서 정확도를 무조건 최고로 올리는 대신, 사용자가 선택한 기록 모드 안에서 배터리·정확도·복구 가능성을 설명하고, 기록이 멈추거나 오래 정지한 경우 조용하게 알려야 한다.

이번 기준선의 우선순위는 다음과 같다.

1. 데이터 손실·중복·유령 세션을 막는다.
2. GPS를 계속 쓰되, 모드별 간격·거리 필터·wake lock으로 전력 예산을 명시한다.
3. 일·세션 화면에서 GPS 측정값과 건강 플랫폼 걸음 수를 섞지 않고 출처/가용성을 보여준다.
4. 알림과 자동 종료는 안전장치로 사용하되, 사용자가 계속 기록할지 선택할 수 있게 한다.
5. 상세 화면의 반복 DB 조회와 재생 중 좌표 변환을 줄여 긴 기록도 부드럽게 만든다.

## 2. 근거와 유사 서비스 비교

### 2.1 기능 벤치마크

| 서비스 | 관찰 가능한 패턴 | 산보에 적용할 점 | 적용하지 않을 점 |
|---|---|---|---|
| Strava | GPS 기록 중 자동 일시정지를 켤 수 있고 GPS 또는 가속도계로 정지 상태를 판단한다. 기록 종료 후 동기화 단계가 있다. | 정지 감지와 명시적 종료를 보조 수단으로 제공한다. | 서버 동기화·소셜 경쟁은 MVP 목표가 아니다. |
| Nike Run Club | GPS/가속도계를 사용하고 Auto-Pause를 켜면 멈출 때 자동 일시정지·재개한다. | 짧은 설명이 있는 모드 선택과 자동 보조를 제공한다. | 음성 코칭·훈련 계획은 제품 목적과 다르다. |
| Google Fit | 오늘의 걸음·활동·운동을 날짜별로 비교하고, 가속도계로 일정 시간 정지한 운동의 종료 알림을 제공한다. | “오늘/주간” 요약과 정지 후 종료 제안을 제공한다. | 건강 점수·칼로리 같은 해석은 표시하지 않는다. |
| Samsung Health | 센서 기반 걸음 수를 휴대폰·워치 출처별로 보고, 날짜/주간/월간 추이를 확인한다. | 걸음 수를 GPS 거리와 다른 카드로 표시하고 출처/권한 상태를 노출한다. | 삼성 계정·기기 생태계 의존은 두지 않는다. |
| AllTrails / komoot | 지도와 기록을 오프라인에서도 사용할 수 있도록 사전 다운로드를 제공한다. | 네트워크가 없어도 기록과 복구를 유지하고, 지도 실패가 기록 실패가 아니게 한다. | 유료 지도·탐색·턴바이턴 길 안내는 범위 밖이다. |

공식 참고: [Strava recording](https://support.strava.com/en-us/articles/15402137-recording-an-activity), [Nike Run Club settings](https://www.nike.com/help/a/nrc-settings/nrc-run-features), [Google Fit activity](https://support.google.com/fit/answer/6090183?hl=en-GB), [Google Fit stop reminders](https://support.google.com/fit/faq/6108483?hl=en-GB), [Samsung Health steps](https://www.samsung.com/us/support/answer/ANS10001370/), [AllTrails offline maps](https://support.alltrails.com/hc/en-us/articles/37213988725780-How-to-access-your-downloaded-maps), [komoot recording limits](https://support.komoot.com/hc/en-us/articles/10286965082650-Recording-or-navigation-stops).

### 2.2 플랫폼·배터리 근거

Android 위치 API는 갱신 간격이 선호값(best effort)이며, 고정밀도일수록 전력 비용이 커진다. 균형 전력 모드는 Wi‑Fi/기지국을 더 활용하고, 저전력 센서 기반 활동 인식은 움직임 전환 때만 앱을 깨우는 방식으로 설계할 수 있다. Android는 사용자 시작 foreground service와 위치 권한의 최소 범위를 요구하므로, 세션을 시작한 동안만 위치 서비스를 유지하고 종료 즉시 중단한다.

공식 참고: [LocationRequest](https://developers.google.cn/android/reference/com/google/android/gms/location/LocationRequest), [Android location settings](https://developer.android.google.cn/develop/sensors-and-location/location/change-location-settings?hl=en), [Activity Recognition](https://developers.google.cn/location-context/activity-recognition?hl=en), [Play foreground-location guidance](https://support.google.com/googleplay/android-developer/answer/9799150?hl=en).

### 2.3 심리·정신건강 관점의 제품 원칙

- 자기결정이론은 자율성·유능감·관계성 욕구가 충족될 때 자기 조절과 웰빙이 좋아진다고 본다. 따라서 목표 미달을 실패로 표시하거나 강제 알림을 반복하지 않고, 기록 모드·알림·보존/삭제를 사용자가 선택하게 한다.
- 구현 의도(“언제/어디서/어떻게 할지”를 미리 정하는 if–then 계획)는 목표 실행을 높이는 경향이 보고되었다. 산보에서는 “퇴근 후 10분 동네 기록”처럼 선택형 리마인더 문구에만 적용하고, 사용자의 행동을 자동으로 판단하거나 치료적 약속으로 확대하지 않는다.
- 디지털 정신건강 도구 연구에서는 알림·복잡성·반추 부담이 참여를 떨어뜨릴 수 있다는 우려가 반복된다. 따라서 알림은 기록 중 안전 이벤트와 사용자가 켠 선택형 리마인더로 제한하며, 스트릭·리더보드·진단 문구를 넣지 않는다.
- 행동활성화는 우울증 치료 맥락의 임상적 개입이다. 산보는 치료·진단·위기 대응 도구가 아니며, 관련 개념은 “작은 활동을 스스로 선택하고 회상하기 쉽게 만든다”는 비의료적 UX 영감으로만 사용한다.

참고: [Ryan & Deci, 2000](https://www.selfdeterminationtheory.org/SDT/documents/2000_RyanDeci_SDT.pdf), [Gollwitzer & Sheeran meta-analysis](https://www.decisionskills.com/uploads/5/1/6/0/5160560/2006_gollwitzersheeran_implementation_intentions_1.pdf), [digital mental-health engagement review](https://pmc.ncbi.nlm.nih.gov/articles/PMC9168921/), [NHS behavioural activation overview](https://www.cpft.nhs.uk/download.cfm?doc=docm93jijm4n6232.pdf&ver=8802).

## 3. 대상 사용자와 핵심 과업

### 3.1 대상

- 성과 경쟁보다 동선·정지·장소의 맥락을 남기려는 기록형 산책자
- 배터리가 부족하거나 실내/지하로 자주 들어가도 기록을 잃고 싶지 않은 사용자
- 나중에 “그 시간에 무엇을 했지?”를 분 단위로 확인하고 직접 수정하려는 사용자

### 3.2 핵심 과업

1. 시작 후 10초 안에 “기록 중” 상태를 확인한다.
2. 화면을 끄고 걸어도 세션·샘플·분 윈도우가 로컬에 누적된다.
3. 오래 정지하거나 5시간에 도달하면 이유와 선택지를 이해한다.
4. 종료 후 지도·거리·시간·분 단위 활동을 한 화면에서 읽는다.
5. 건강 플랫폼 걸음 수가 있으면 GPS 거리와 구분해 일 단위로 비교한다.
6. 앱 업데이트·재설치 전후에 백업/가져오기로 기록을 복원한다.

## 4. 기능 요구사항

### 4.1 세션 수명주기

| ID | 요구사항 | 수용 기준 |
|---|---|---|
| FR-LIFE-01 | 한 번에 활성 세션은 하나만 허용한다. | 동시 시작 경쟁에서 하나만 성공하고 나머지는 상태 오류를 보인다. |
| FR-LIFE-02 | 세션 시작 전에 권한·위치 서비스·알림 상태를 확인한다. | 실패 원인은 enum 코드로 UI에 전달되고, 한국어 문자열 파싱을 하지 않는다. |
| FR-LIFE-03 | 수신 샘플·파생 윈도우·세션 롤업은 재시도 가능한 저장 경계를 가진다. | 중복 이벤트 재전달 후 샘플/윈도우/세션 집계가 한 번만 반영된다. |
| FR-LIFE-04 | 스트림 종료·앱 재시작 후 복구 카드가 세션을 잃지 않게 한다. | 복구 실패는 새 세션 시작으로 우회되지 않고 재시도만 제공한다. |

### 4.2 배터리 정책

| ID | 요구사항 | 기준선 |
|---|---|---|
| FR-BAT-01 | 기록 모드를 명시한다. | 절전 20초/10m, 균형 8초/5m, 정밀 4초/2m. |
| FR-BAT-02 | 정밀 모드에서만 CPU wake lock을 허용한다. | 절전·균형은 `keepCpuAwake=false`; 종료 즉시 해제한다. |
| FR-BAT-03 | 지도 타일·역지오코딩·장소 조회는 샘플 수신 경로에서 실행하지 않는다. | 기록 중 네트워크 호출은 지도 표시 등 사용자 동작으로 한정한다. |
| FR-BAT-04 | 세션 종료 후 위치 스트림·FGS·타이머를 해제한다. | 종료/폐기/복구 실패 테스트에서 구독·타이머가 남지 않는다. |
| FR-BAT-05 | 물리 배터리 예산은 실기기에서 측정한다. | 동일 기기·동일 밝기·화면 꺼짐 조건으로 모드별 %/h를 기록하고 문서화한다. 에뮬레이터 수치는 근거로 사용하지 않는다. |

권장 측정 목표(가설): 균형 모드 화면 꺼짐 상태에서 60분당 평균 5%p 이하, 정밀 모드 8%p 이하. 기기·신호·온도에 따라 달라지므로 출시 차단 기준이 아니라 회귀 기준으로 사용한다.

### 4.3 안전 자동화

| ID | 요구사항 | 기준선 |
|---|---|---|
| FR-SAFE-01 | 한 장소 정지 20분에 한 번 경고한다. | 알림·앱 내 배너는 한 세션에서 중복 발행하지 않는다. |
| FR-SAFE-02 | 정지 30분에 자동 저장·종료한다. | 종료 사유를 완료 알림과 기록 상세에 남긴다. |
| FR-SAFE-03 | 세션 시작 4시간 45분에 예고하고 5시간에 자동 저장·종료한다. | 앱이 백그라운드여도 복구 시 만료를 판정한다. |
| FR-SAFE-04 | 경고 후 계속 기록을 선택할 수 있다. | 정지 경고만 해제되고, 이동이 시작되면 이전 정지 데드라인은 삭제된다. |

자동 종료는 의학적·안전 판단이 아니라 배터리·데이터 손실을 줄이기 위한 제품 경계다. 사용자가 의도한 장기 기록은 여러 세션으로 나누도록 안내한다.

### 4.4 일 단위 활동·걸음

| ID | 요구사항 | 기준선 |
|---|---|---|
| FR-DAY-01 | 하루 합계는 GPS 산책 지표와 건강 플랫폼 걸음 수를 분리한다. | 카드 제목·출처·단위가 섞이지 않는다. |
| FR-DAY-02 | 걸음 수 0과 접근 불가를 구분한다. | `0`은 유효 값, `null`은 denied/unavailable 상태로 표시한다. |
| FR-DAY-03 | 날짜 경계에서 자동 주간 창만 오늘로 이동한다. | 사용자가 과거 주간을 보고 있으면 자동으로 덮어쓰지 않는다. |
| FR-DAY-04 | Health Connect/HealthKit 어댑터는 인터페이스 뒤에 둔다. | 플랫폼 미연결 기본값은 권한 요청 없이 unavailable이다. |

### 4.5 회상 UX·접근성

| ID | 요구사항 | 기준선 |
|---|---|---|
| FR-UX-01 | 홈은 시작/종료·현재 상태·핵심 수치 3개를 우선한다. | 10초 게이트를 통과하고 경쟁·스트릭을 기본 표시하지 않는다. |
| FR-UX-02 | 상세는 지도·요약·분 타임라인·수정 순서다. | 장소 자동 제안은 로컬 읽기 전용이며 사용자가 저장할 때만 쓰기한다. |
| FR-UX-03 | 애니메이션은 상태 변화의 의미를 보조한다. | `disableAnimations`에서 즉시 전환하며 재생 타이머는 중복 생성하지 않는다. |
| FR-UX-04 | 텍스트 확대·스크린 리더를 지원한다. | 주요 버튼 최소 48dp, 지도·타임라인에 의미 있는 Semantics가 있다. |
| FR-UX-05 | 오류는 재시도·설정 이동·데이터 보존 여부를 함께 보여준다. | 권한 오류와 저장 오류를 같은 문구로 뭉개지 않는다. |

### 4.6 데이터 통제

| ID | 요구사항 | 기준선 |
|---|---|---|
| FR-DATA-01 | 전체 백업은 세션·샘플·윈도우·장소·제외를 포함한다. | 가져오기 전 미리보기/확인, 중복 세션 idempotency, 실패 시 transaction rollback. |
| FR-DATA-02 | 내보내기는 사용자에게 도달 가능한 경로를 사용한다. | 클립보드 NDJSON은 임시 경로를 안내하는 대신 붙여넣을 수 있는 실제 데이터다. |
| FR-DATA-03 | 앱 삭제/재설치의 한계를 설명한다. | OS 앱 삭제로 로컬 DB가 사라질 수 있으며, 백업 파일 없이는 자동 복구되지 않는다는 안내를 설정에 둔다. |

## 5. 상태 모델과 데이터 흐름

```text
Idle
  └─ start → Starting → Tracking ── stop ──→ Saving → Completed
                         │   │
                         │   ├─ stationary warning → continue / auto-save
                         │   ├─ duration warning  → auto-save at 5h
                         │   └─ stream/storage failure → Recoverable
Recoverable ── retry/restore → Tracking or Saving
             └─ discard      → Idle
```

원본 GPS 샘플은 로컬에 보존하고, `SampleFilter`·`RoutePartitioner`·`SessionPipeline`이 같은 규칙으로 거리·분 윈도우·지도·재생을 계산한다. 상세 화면은 파생 데이터를 읽기만 하며 장소 자동 제안은 기존 기억을 화면에 임시 표시할 뿐 DB를 변경하지 않는다.

## 6. 품질·성능 예산과 측정

### 6.1 자동화 가능한 지표

- `flutter analyze --no-pub`: 오류 0
- 전체 테스트: 동시성 1에서 전부 통과
- 시작 경쟁: active 세션 1개
- 저장 재시도: 중복 샘플/윈도우 0건
- 복구: 만료 데드라인을 놓치지 않음
- 상세 장소 조회: 세그먼트 수와 무관하게 장소 테이블 조회 1회
- 상세 지도: 동일 경로의 static 좌표 변환 1회, 재생 tick마다 재변환 없음
- reduced motion: 애니메이션 duration 0

### 6.2 실기기 회귀 매트릭스

| 축 | 최소 케이스 |
|---|---|
| Android | Android 10/13/14 이상, 삼성 제조사 배터리 최적화, 화면 꺼짐, FGS 알림 권한 거부 |
| 신호 | 야외 정상, 실내 약한 신호, 지하/터널 5분 이상 공백 |
| 동작 | 20분 정지, 30분 정지, 4:45/5:00 경계, 앱 강제 종료 후 재실행 |
| 데이터 | 1k/10k/50k 샘플, 백업 가져오기 중 앱 종료, 잘못된 아카이브 |
| 접근성 | 큰 글자, TalkBack, 애니메이션 줄이기 |

배터리 측정은 Android Battery Historian/ADB 배터리 통계와 제조사 설정을 함께 기록한다. GPS 신호·화면·네트워크·온도·배터리 시작/종료를 로그에 남기며, 단일 측정값을 보편적 약속으로 표현하지 않는다.

## 7. 릴리즈 단계

### v0.9.0 (이번 기준선)

- DB v6 안전 데드라인·단일 active 세션·멱등 저장
- 모드별 위치 요청 프로필과 FGS/알림 오류 분리
- 일 단위 GPS/Health 데이터 분리 계약과 Health Connect/HealthKit 읽기 어댑터
- 백업/가져오기와 복구 UX
- 상세 화면 장소 조회·지도 geometry 캐시
- reduced-motion·Semantics·오류 CTA 정리

### v0.10 (실기기 검증 후)

- 기기별 배터리 회귀 대시보드(로컬 진단 파일, 기본 전송 없음)
- 오프라인 지도 캐시 정책의 명시적 UX
- 다중 세션 날짜 집계·시간대 변경 시나리오 확장

### 보류

- 소셜·리더보드·스트릭·공개 공유
- 진단/치료/기분 점수·정신건강 판정
- 상시 위치 수집, 서버 계정·클라우드 동기화

## 8. 잔여 리스크와 의사결정 로그

1. `SessionController`와 `WalkRepository`는 여전히 크다. 이번 릴리즈에서는 순수 정책·저장 경계를 추가해 위험을 낮추고, 다음 단계에서 수명주기·안전·표시 조정자를 별도 서비스로 추출한다.
2. 실제 기기 배터리와 Android 제조사별 백그라운드 정책은 자동 테스트로 증명할 수 없다. 출시 전 매트릭스를 필수 QA로 둔다.
3. Health Connect/HealthKit 읽기는 사용자가 명시적으로 연결할 때만 실행한다. Android Health Connect의
   기본 과거 조회 한도(권한 허용 시점 기준 30일)와 iOS 잠금 상태의 보호 데이터 제한은 UI/설정 안내와
   실기기 QA에서 확인해야 한다. 여러 기기의 합계는 플랫폼 aggregate API에 맡기고 앱에서 GPS와 합산하지 않는다.
4. OSM/CARTO 타일 사용량·약관·오프라인 캐시 정책은 배포 환경에서 재검토한다.
5. 행동과학 근거는 일반 UX 원칙의 참고자료이지 사용자 개인의 정신건강 상태를 추론하거나 치료하는 근거가 아니다.
