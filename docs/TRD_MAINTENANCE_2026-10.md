# 산보 유지보수와 측정 신뢰성 개선 TRD

| 항목 | 내용 |
|---|---|
| 문서 ID | TRD-SANBO-MAINT-2026-10 |
| 작성일 | 2026-10-13 |
| 상태 | 사용자 검토용 설계. 제품 코드 변경 전 |
| 기준 | `v0.9.1`, SQLite v6, 전체 백업 v2, 세션 export v2 |
| 관련 문서 | [PRD](PRD_MAINTENANCE_2026-10.md), [1차 설계](superpowers/specs/2026-10-13-measurement-consistency-and-backup-design.md), [근거](superpowers/verification/2026-10-13-maintenance-audit.md) |

## 1. 현행 흐름과 원인

```text
Geolocator -> LocationQualityPolicy -> SessionController incremental filter
                                        |              |
                                        |              +-> live 숫자
                                        +-> checkpoint SQLite
                                                     |
                               SampleFilter -> RoutePartitioner
                                                     |
                                  WindowAggregator + SessionRollup
                                                     |
                                   finalize transaction + exclusions
                                                     |
                                       상세 / 일별 통계 / export
```

필터와 경로 분할은 존재한다. 불일치는 복구 코드가 제외 샘플을 제거한 목록을
다시 연결하고, presentation이 현재 속도의 최신성 및 샘플 UTC 시간대 변환을
관리하지 않는 데서 생긴다. JSON export는 이미 존재하는 완료 평균 helper를
쓰지 않는다. 작은 변위와 노이즈 문제는 1.5m의 선분별 하한 및 고속 단일 최고값
정책에서 생기며, 1차 버그 수정과 별도로 다룬다.

## 2. 1차 경계와 구현 설계

### 2.1 모바일 백업 저장, MR-01

`BackupFileService.save(fileName, bytes) -> Future<String?>` 계약을 유지한다.
nonnull 결과는 외부 저장이 끝난 대상 URI/URL이고, null은 사용자 취소다.
파일 생성만 끝났거나 공유 화면만 열렸을 때 성공을 반환하지 않는다.

- Desktop은 기존 `file_selector.getSaveLocation`을 유지한다.
- Android/iOS는 기존 플랫폼 통합 패턴을 따라 좁은 파일 내보내기 MethodChannel을
  둔다. 제품 의존성은 추가하지 않는다.
- Dart는 앱 임시 폴더의 전용 하위 폴더에 백업을 쓴 뒤 파일 경로와 표시 이름만
  native에 전달한다. 최대 50MB JSON을 플랫폼 채널로 복제하지 않는다.
- Android는 `ACTION_CREATE_DOCUMENT`, `CATEGORY_OPENABLE`,
  `application/octet-stream`과 `.sanbo` 파일 이름을 사용한다. 선택한 content URI의
  output stream에 임시 파일을 복사하고 close까지 성공한 후 응답한다.
- iOS는 `UIDocumentPickerViewController`의 export를 사용하고 picker의 성공/취소
  callback으로 완료를 판정한다. 프로젝트의 최소 iOS 버전에 맞는 initializer를
  선택하고 배포 대상보다 높은 API는 availability guard를 둔다.
- native는 전달받은 파일이 산보의 임시 내보내기 폴더 안인지 canonical path로
  확인한다. 외부 입력 파일 이름에서 디렉터리 경로를 허용하지 않는다.
- Flutter의 finally에서 성공/취소/실패 모두 임시 파일을 정리한다. native가 복사
  중인 파일을 먼저 지우지 않는다. 앱 종료로 남은 임시 파일은 다음 내보내기 전에
  산보 전용 폴더에서만 정리한다.
- UI busy, 이중 실행 차단, 가져오기 merge/중복 방지, 원본 DB는 유지한다.

검증은 `BackupFileService` fake에만 머물지 않는다. 실제 저장 어댑터, native
취소/실패, 파일 저장 후 재가져오기를 검사한다. iOS simulator 결과와 물리
iPhone 결과를 구분한다.

### 2.2 복구 경로 경계, MR-02

`_recomputeLiveMetricsFromBuffer`에서 필터 표시를 가진 전체 목록을
`RoutePartitioner.partition`에 전달한다. 제외된 점을 먼저 삭제한 뒤 두 이웃을
잇지 않는다. 거리 합계는 completed와 같은 분할 선분 및 1.5m 하한을 쓴다.

연결 가능 조건은 양의 시간, 60초 이하 간격, 유효한 좌표, 필터/제외 경계 없음이다.
복구 이후 첫 새 샘플 역시 마지막 필터 경계를 넘어 연결되지 않아야 한다.
정상 live callback의 O(1) 갱신은 유지하고 O(n) 복구 재계산은 시작/재개에 한정한다.
더 큰 lifecycle 분리나 repository 재작성은 이번 수정의 전제가 아니다.

### 2.3 현재 속도와 신선도, MR-03

현재 속도 값과 최신 상태를 분리한다. `LiveSessionState`에 표시용 last usable fix
instant와 availability를 추가하며 DB에 저장하지 않는다. 기존 `_clock`, 30초
품질 age를 재사용한다. 기준은 `0 <= receipt age <= 30초`다. 허용된 미래 skew
샘플은 age를 0으로 clamp해서 즉시 stale로 만들지 않는다.

- 유효한 위치가 없으면 waiting, 최신 유효 위치와 속도 근거가 있으면 available.
- 첫 좌표만 있고 유효한 provider speed 또는 관측 선분이 없으면 속도는 waiting.
- 정지로 관측된 유효 선분의 속도 0은 available로 표시한다.
- 마지막 유효 위치가 30초를 초과하면 stale, 과거 숫자는 화면과 Semantics에서
  감춘다. 거절된 callback은 last usable instant를 갱신하지 않는다.
- 재개 시 현재 clock으로 즉시 freshness를 다시 평가한다. 새 위치 전 과거
  provider speed를 현재 속도로 표시하지 않는다.
- 전면의 기존 ticker에서 availability를 갱신한다. 백그라운드에서는 새 UI timer를
  만들지 않고 native 위치 수집을 유지한다.
- ticker의 copyWith가 `statusMessage`를 지우는 문제도 같은 변경 범위에서 막는다.

현재 숫자 자체의 smoothing, provider Doppler 우선 정책, speed accuracy 저장은
2차에서 다룬다. Android는 provider speed가 좌표 차분보다 정확할 수 있으며,
accuracy는 확정 오차가 아니라 추정 불확실성이다.
[Android Location 계약](https://developer.android.com/reference/android/location/Location)

### 2.4 시간대와 export, MR-04~05

저장/수학은 UTC instant를 유지한다. 재생 UI는 session.timezone을 받고
`asLocal(timestamp, timezone: session.timezone)`로 바꾼 후 포맷한다. 현재 위치,
슬라이더 양 끝, Semantics에 같은 규칙을 적용한다. `toLocal()`만 호출하면 여행
후 산책 당시 시간대가 달라질 수 있으므로 세션 IANA zone을 쓴다.

완료 JSON/NDJSON의 `avg_speed_mps`는 `completedAverageSpeedMps`로 도출한다.
유효하지 않은 거리/이동 시간은 null이다. active 세션이 export될 수 있는 기존
호출은 완료 지표로 강제 변환하지 않고 기존 상태 의미를 유지한다. 전체 백업은
영속 상태 복원용이므로 이번 변경에서 저장값을 재작성하지 않는다. 세션 export의
schema v2는 nullable 숫자 계약을 유지한다.

### 2.5 상태 문구, MR-06

DailyStepSnapshot의 source와 coverage를 함께 판정한다. error, denied,
unavailable, partial, 정상 zero를 구분하며 오류 CTA는 재조회이고 권한 거부 CTA는
연결/설정이다. `sampleCount`와 `validSampleCount`를 혼용하지 않는다. 현재 신호
상태 badge와 원시 audit count는 서로 다른 정보로 표현한다.
settings capability에는 사용할 수 있는 동작인지 명시하는 읽기 전용 값을 둔다.
iOS의 null opener를 Android 설정 버튼으로 렌더링하지 않는다.

## 3. 2차 측정 정책 설계 경계

### 3.1 작은 이동과 정지 노이즈, MR-08

연속 위치별 1.5m 미만 이동을 영원히 버리는 방식은 교체한다. 분할된 경로의
anchor 기준으로 작은 변위를 누적하고, 순방향 변위가 관측 가능한 수준에 도달한
구간을 측정 선분으로 내보내는 방식을 우선 검토한다. 새 알고리즘은 route
geometry와 측정용 geometry를 구분할 수 있어야 한다. 원시 좌표는 그대로 둔다.

정확도 반경 안의 정지 흔들림과 느린 실제 이동은 좌표만으로 완벽히 구분할 수
없다. 따라서 MR-08 fixture 두 개뿐 아니라 코너, 원을 도는 산책, 느린 보행,
provider speed 0, 정확도 결측, 도심 신호를 함께 평가한다. 단순 radius subtraction,
무조건 provider speed 적분, 전면적인 Kalman filter 도입은 채택하지 않는다.
정책 파라미터와 과거 기록 재계산은 별도 측정 spec에서 확정한다.

### 3.2 고속 자동 제외, MR-09

현재 `window.maxSpeedMps >= 10/3.6`을 단독 조건으로 삼지 않는 안을 추천한다.
측정 선분에서 고속 지속 시간, 샘플 정확도, 관측 공백을 함께 확인하고, 확인된
시간 범위만 기존 분 단위 제외 계약으로 정규화한다. 한 번의 급증과 품질 낮은
좌표로 자동 제외하지 않는다. 정책 설계에는 10km/h 경계, 빠른 걷기, 달리기,
자전거, 차량, 분 경계의 고속 구간, 사용자의 계속 기록 의사를 모두 포함한다.

사용자가 명시한 차량 라벨과 비차량 확정 라벨, 제외 취소, 중복 방지, 원본 보존을
유지한다. 기존처럼 자동 제외를 유지할지 사용자 확인으로 바꿀지는 제품 선택이다.
이 선택과 정확한 지속 시간은 1차 구현에 포함하지 않는다.

### 3.3 평균과 시간 보존, MR-10~11

분/병합 구간에 관측 이동/정지/결측 시간을 명시적으로 전달한다. 병합 평균은
단순한 분 duration 가중 평균이 아니라 해당 분모를 합친 뒤 총거리로 나눈다.
`stationaryRatio`를 빼서 moving time을 추정하면 결측이 이동으로 바뀌므로 사용하지
않는다. 필요한 schema migration과 계산 버전 표시, 백업 호환은 별도 spec에 넣는다.

과거 기록은 열어보는 것만으로 몰래 재계산하지 않는다. 계산 버전과 원본 존재
여부를 확인하고, 재계산 시 사용자 라벨/메모/장소/제외 정보를 보존하는 transaction이
필요하다. 자동 제외가 과거 사용자 수정 기록에 다시 적용되지 않게 한다.

## 4. 스토어와 배포 경계, MR-07, MR-12~13

- 원격 main은 이미 공개한 v0.9.1의 ancestor다. 자동 force-push를 쓰지 않는다.
  정리 시 released commit으로 fast-forward하고 새 후보는 별도 브랜치와 CI로 검토한다.
- release gate의 `0.9.1`/증적 파일/체크섬 이름 hard-code를 새 후보의 실제 metadata로
  바꾼다. app 정보, pubspec, release note의 버전이 같아야 한다.
- AAB의 기본 versionCode와 ABI APK의 Flutter split versionCode를 구분한다.
  기존 arm64 APK는 `2015`다. 새 설치 업데이트의 versionCode가 더 커야 한다.
- 기존 Android 서명 인증서 fingerprint를 유지한다. Google Play upload identity는
  별도 확인 대상이며 GitHub 산출물 서명만으로 Play 게시 가능을 단정하지 않는다.
- 공개 전에 signed AAB/APK의 버전, target SDK, signature, checksum을 확인한다.
- Android Health rationale을 단순 launcher로 보내지 않고 실제 정책 화면으로 보낸다.
  Android 14+ `VIEW_PERMISSION_USAGE`, `HEALTH_PERMISSIONS`,
  `START_VIEW_PERMISSION_USAGE` alias가 필요하다.
  [Health Connect 설정 계약](https://developer.android.com/health-and-fitness/health-connect/get-started)
- 배터리/야외 오차/제조사 background 결과는 [실기기 프로토콜](DEVICE_VALIDATION.md)에
  기기 모델, OS, 모드, 화면 상태와 함께 기록한다. 현재 물리 기기는 연결되지 않았다.

## 5. 요구 추적과 검증

| PRD 요구 | 구현 경계 | 의미 있는 검증 |
|---|---|---|
| MR-01 | `backup_file_service`, Android/iOS 파일 내보내기 | 실제 adapter 취소/완료/오류, 외부 파일 왕복 |
| MR-02 | controller recovery + RoutePartitioner | 필터 점을 사이에 둔 10m/30m 재현, 재개 첫 샘플, 긴 공백 |
| MR-03 | LiveSessionState, ticker, Home | 30초/30초 초과, rejected callback, 정상 0, 첫 신호, resume, Semantics |
| MR-04 | detail playback + `geo.asLocal` | UTC/Asia-Seoul, 기기 zone 변경, DST fold, 화면/접근성 일치 |
| MR-05 | `completed_walk_metrics`, SessionExport | stale persisted value, 100/100, 0/결측/non-finite, JSON/NDJSON/human |
| MR-06 | DailyActivityPanel | error/denied/unavailable/partial/zero별 수치와 CTA |
| MR-07 | release gate + Git refs | main/tag/CI SHA, AAB/각 APK versionCode, cert, checksum, 실제 게시 조회 |
| MR-08 | 후속 측정용 route reducer | 정지/느림/코너/빈번한 callback과 실기기 거리 오차 |
| MR-09 | 후속 자동 제외 정책 | 단일 spike, 지속 고속, 낮은 품질, 사용자 라벨, 제외 취소 |
| MR-10 | 후속 window/segment time contract | 이동 10초+60초 가중, 정지/결측 보존, 반올림 시간 보존 |
| MR-11 | 후속 상세 지표와 copy | 평균 분모, GPS 공백, 추정 오차 표시와 export 일치 |
| MR-12 | Android rationale/usage alias | 두 OS 진입점, 동일 정책 본문, 일반 launch 유지 |
| MR-13 | 물리 기기 QA | Galaxy/Pixel/iPhone 야외/화면 잠금/배터리 matrix |
| MR-14 | 후속 날짜 목록/CTA 접근성 | 선택 날짜 가시성, 큰 글자, 실제 VoiceOver/TalkBack focus |

1차 종료 게이트는 새 회귀 테스트, analyzer, 전체 Flutter 테스트, Android/iOS native
테스트, Android debug/release 빌드, 문서 검증, `git diff --check`다. 모바일
파일 picker 왕복은 가짜 서비스를 주입한 widget 테스트로 대체하지 않는다.
기존 게이트 결과를 반복해서 새 수정의 검증으로 인용하지 않는다.
