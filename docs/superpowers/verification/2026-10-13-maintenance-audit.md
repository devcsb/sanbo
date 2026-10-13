# 산보 유지보수 검토 근거

검토일 2026-10-13~14 한국 시간, 기준 `v0.9.1` / `1368d453803df4b69f4158ff1181fd17e539a2f8`.
제품 코드를 바꾸기 전에 기존 gate, 독립 합성 probe와 native adapter를 실행했다.
외부 근거는 2026-10-13에 조회했다. 아래 결과는 새 개선 구현의 검증 결과가 아니다.

## 1. 배포 대조

- `git status --short --branch`: 시작 시 clean, `main...origin/main [ahead 16]`.
- `git ls-remote --heads --tags origin`: 원격 main `b9fb762`, v0.9.1은 local HEAD와
  같은 `1368d45`. origin/main을 stale local cache로 판단한 결과가 아니다.
- `gh release list`, `gh api repos/devcsb/sanbo/releases/tags/v0.9.1`:
  [v0.9.1](https://github.com/devcsb/sanbo/releases/tag/v0.9.1) 공개, draft=false,
  prerelease=false, 2026-09-24T14:43:53Z, 한국 시간 23:43:53.
- 원격 quality 마지막 성공은 `b9fb762`의
  [CI run](https://github.com/devcsb/sanbo/actions/runs/33222617638).
  v0.9.1 배포 commit에서 GitHub main CI를 실행했다는 증거는 없다.
- 같은 저장소의 기존 worktree는 clean이며 v0.9.0에 있다. 별도 미커밋 backlog는 없다.
- Google Play 게시, App Store 게시, 실제 사용 기기 버전은 확인하지 못했다.

GitHub asset digest, 공개 checksum 파일, 로컬 signed output의 SHA-256이 모두 일치한다.

| 파일 | SHA-256 |
|---|---|
| app-release.aab | `e5bd6d7945e1ab6b7105f36305bfd099666bb29992c3667db11b13e85e1081cb` |
| app-arm64-v8a-release.apk | `9d91a8a7c76b5878455cc6182a373b42f4eab18b4535744ef366bc144e0f0013` |
| app-armeabi-v7a-release.apk | `218a8f1c551e486d9fd7f27880c69cfbea6d6a249c075e61f80344975aa684a3` |
| app-x86_64-release.apk | `a1418a7569475ca1926fe8e696b251f91ffe0eea0272962ed779df10e0415579` |

arm64 APK의 `apksigner verify --print-certs`는 성공했다. certificate SHA-256은
`ceb40402d706589acee5da5df5a010c3dd5c2e9329cd3218961dfce56a6d38ac`으로 기존
gate와 일치한다. manifest versionName `0.9.1`, split versionCode `2015`, targetSdk
`36`. 기본 pubspec의 `+15`와 split APK의 versionCode를 혼동하지 않는다.

배포 후보 문서는 여전히 외부 배포 전 상태다. [9월 증적](../../release/2026-09-24-android-release.md)은
후보 생성 문서였으며 실제 게시 확인은 위 결과로 보완한다.

## 2. 기존 품질 게이트

| 명령 | 이번 실행 결과 |
|---|---|
| `bash scripts/run_quality_loop.sh` | PASS, analyzer 문제 없음, Flutter 439개 통과, PRD/TRD 구조 및 whitespace 통과 |
| `bash scripts/run_native_platform_tests.sh` | PASS, Android unit tests와 iOS simulator XCTest 통과 |
| `flutter build apk --debug --target lib/main.dart` | PASS, app-debug.apk 생성, 0.9.1/targetSdk36 확인 |
| 실제 Android 연결 조회 | 연결된 기기 없음 |
| iOS 화면 검토 | iPhone 17 Pro, iOS 26.5 simulator, 앱 실행 및 홈/기록/설정 확인 |

Flutter 3.47.1, Dart 3.13.1, Xcode 26.6 환경이었다. health/파일 picker dependency의
deprecated API 및 Gradle/Java 경고는 남지만 이번 빌드/테스트 실패 원인은 아니다.
의존성 버전을 이번 조사에서 올리지 않았다. 물리 기기 배터리/GPS 실측은 실행하지 않았다.

## 3. 독립 측정 probe

별도 `/tmp` Dart 프로그램에서 production `SessionPipeline`과
`AutomaticRouteExclusionPolicy`를 직접 호출했다. 좌표는 적도 위도 방향으로
`latitude = meters / 111194.92664455874`, longitude=0을 사용했다.
세션 UTC 시작은 2026-10-13T00:00:00Z, session zone은 Asia/Seoul이었다.
raw sample은 provider speed를 넣지 않았다. 정확도는 별도 표시가 없으면 5m다.

| 입력 | 실제 계산 결과 | 의미 |
|---|---|---|
| t=0..60초, 4초마다 0m/5m 번갈아 보고, accuracy10 | 75m, 이동60초, 정지0초, 1.25m/s, quality high, walkSteady | 정지 노이즈를 4.5km/h 걷기로 추정 |
| t=0..60초, 4초마다 4.8m 직진, 32초 위치만 +15m | 92.4m, 평균1.54m/s, max4.95m/s, walkSteady, 자동 제외60초 | 단일 spike가 분 전체 자동 제외 |
| t=0..60초, 2초마다 1m 직진 | 거리0m, 이동60초, 평균0m/s, quality high, unknown | 선분별 1.5m 하한이 느린 연속 이동을 전부 버림 |
| t=0..120초, 1초마다 1m 직진 | 거리0m, 이동120초 | callback cadence가 측정 결과를 바꿈 |

관련 코드와 원인은 다음과 같다.

- `lib/domain/pipeline/geo.dart`: `minMeaningfulSegmentDistanceM=1.5`.
- `session_rollup.dart`, `window_aggregator.dart`: 인접 선분마다 하한을 적용하고
  작은 선분의 시간은 이동으로 집계한다. 누적 변위 anchor가 없다.
- `automatic_route_exclusion.dart`: 분의 maxSpeedMps 하나만 10km/h와 비교하고
  해당 분 전체를 제외한다. 지속성이나 품질을 직접 확인하지 않는다.
- 오차 반경을 정확도 상한 이내라는 이유만으로 실제 이동의 증거로 취급한다.

이것은 원인과 반례의 재현이다. 실제 기기의 발생률과 새로운 정확도 목표를
충족했다는 주장으로 해석하지 않는다.

## 4. 실제 어댑터와 controller probe

throwaway Flutter test는 실제 `FileSelectorAndroid.registerWith()` 및
`FileSelectorIOS.registerWith()`로 플랫폼 구현을 바꿔 저장을 호출했다.
설정 UI가 쓰는 `PlatformBackupFileService.save`에서 둘 다 아래 오류가 발생했다.

```text
Android backup export: UnimplementedError: getSavePath() has not been implemented.
iOS backup export: UnimplementedError: getSavePath() has not been implemented.
```

이는 mock의 오류가 아니다. file_selector 1.1.0의 공식 플랫폼 표도 모바일의
save location을 지원하지 않는다.
[공식 패키지 문서](https://pub.dev/packages/file_selector)

controller probe는 기존 repository helper와 synthetic engine, 주입 가능한 clock을
사용했다. 2개 유효 위치로 1.5011m/s를 만든 뒤 clock을 90초 앞으로 옮기고 기존
1초 ticker를 실행했다. 속도는 5.4041km/h 그대로, raw/valid count는 2개였다.
기존 ticker는 elapsed만 갱신하고 속도 age를 판정하지 않는다.

복구 probe는 t=0초 0m, 10초 10m, 20초 20m filtered/accuracy200,
30초 30m를 repository에 저장한 뒤 restoreIfNeeded와 SessionPipeline을 대조했다.

```text
recovery route distance=29.999999999999993 m
completed route distance=9.999999999999998 m
```

복구는 filtered 샘플을 목록에서 삭제한 뒤 valid 이웃을 연결한다. completed의
RoutePartitioner는 filtered 점에서 fragment를 끊는다. 이를 같은 경계로 통일해야 한다.
세 probe 모두 현재의 잘못된 동작을 assert해 재현에 성공했다. 개선 요구를 통과한
회귀 테스트와는 다르며 제품 test 디렉터리에 추가하지 않았다.

## 5. 추가 계산과 UI 검토

- 병합 평균: 사용자 확인 라벨이 같은 두 분, 10m/이동10초/정지50초와
  90m/이동60초를 합치면 SegmentMerger는 1.25m/s를 반환한다. 같은 이동 분모의
  평균은 100/70=1.4286m/s다. duration으로 평균을 다시 가중한다.
- 구조화 export: 완료 session distance100m, movingTime100초, 저장 avgSpeed9m/s.
  humanSummary는 3.6km/h, toJsonDocument와 NDJSON session은 9m/s를 내보낸다.
- 재생 시각: repository.getSamples의 timestamp는 UTC다. 재생 컨트롤은
  DateFormat으로 바로 포맷한다. 00:00Z/서울09:00의 불일치가 코드 경로로 확인된다.
- Home 상태 pill은 raw sampleCount를 기준으로 기록 중이라고 판단한다.
  모든 sample이 filtered여도 기록 성공처럼 보일 수 있다. 보조 설명은 valid count를
  사용하므로 같은 화면의 메시지가 엇갈린다.
- 건강 데이터 source=error는 수치 영역 `연결되지 않음`과 함께 렌더링된다.
- 실제 iOS AX tree에서 `건강 데이터를 불러오지 못했어요` 다음에
  `Health Connect 설정 열기`, `건강 데이터 연결`이 나타났다. iOS factory의
  settingsOpener는 null인데 data source는 해당 capability를 항상 구현한다.
- 실제 402pt급 simulator 화면에서 최근 7일의 마지막/선택된 오늘 날짜가 가로
  목록 오른쪽 밖으로 밀렸다. 선택 날짜를 먼저 드러내는 동작이 없다.
- Home과 intro AX tree에서 동일 시작 CTA의 중복 button node가 보였다.
  실제 VoiceOver 탐색에서 이중 focus를 일으키는지는 미검증이다. 후보 이슈로
  유지하며 단정하지 않는다.

현재 기본 시각 체계, 큰 CTA, 세 탭, 기록 빈 상태의 운동량 노출과 reduced-motion
대응은 존재한다. 전면적인 리디자인보다 상태의 의미와 날짜/시간 가시성 수정이
우선이다. TalkBack/VoiceOver, 실제 폰 큰 글자, 야외 대비 검토는 남아 있다.

## 6. 성능, 구조, 개인정보 검토

5시간 synthetic straight trace의 production pipeline을 로컬 Dart JIT에서 1회씩
실행했다. OS 스케줄링과 JIT warmup이 포함돼 정밀 벤치마크는 아니다.

| 입력 간격 | 샘플 수 | 분 수 | 실행 시간 | 결과 거리 |
|---|---:|---:|---:|---:|
| 1초 | 18,001 | 300 | 약142ms | 0m |
| 4초 | 4,501 | 300 | 약25ms | 약21,575.73m |
| 8초 | 2,251 | 300 | 약11ms | 약21,575.73m |
| 20초 | 901 | 300 | 약4ms | 약21,575.73m |

정상 cadence에서는 이 로컬 probe로 큰 계산 지연을 재현하지 못했다. callback당
증분 갱신, 30초 checkpoint, 백그라운드 UI timer 중단, on-demand Health 조회,
경로 playback prefix 재사용은 이미 구현됐다. 새로운 성능 문제를 증명하지 않은
상태에서 이를 다시 작성하지 않는다.

controller 2,026줄, repository 2,455줄, detail 1,974줄은 변경 영향 파악 비용을
키운다. 첫 수정에 전체 분해를 넣지 않고 측정 책임을 바꿀 때 관련 부분만 분리한다.

로컬 DB transaction, 백업 merge/rollback, 원본 위치 보존, 제외 취소 테스트가
있다. 계정/위치 서버 업로드는 없고 지도 타일 요청은 외부 네트워크를 사용한다.
백업은 `.sanbo` JSON이므로 사용자가 보관 장소를 통제해야 한다. 현재 모바일
백업 실패는 이 데이터 보존 안내의 실제 실행을 막는 문제다.

Android manifest에는 Health rationale action만 있고 실제 개인정보 안내 화면 및
Android14+ usage alias가 없다. 공식 시작 가이드는 usage alias와 같은 정책 내용의
화면을 요구한다. 이번 단계에서는 스토어 준비 장애로 기록한다.
[Health Connect 공식 가이드](https://developer.android.com/health-and-fitness/health-connect/get-started)

Android accuracy는 추정 반경이고 provider speed는 GNSS Doppler로 좌표 차분보다
정확할 수 있다. 둘 다 단순 상수/확정 이동 근거로 다루면 안 된다.
[Location API 계약](https://developer.android.com/reference/android/location/Location)

## 7. 남은 판단과 작업

1. 첫 설계를 검토하고 백업/표시/복구 오류부터 고친다.
2. 작은 이동/정지 노이즈/지속성 고속 제외를 독립 설계한다. 원본과 사용자 수정은
   보존하고, 과거 기록 재계산과 schema/calculation version도 함께 결정한다.
3. 새 release candidate의 게이트와 게시 상태를 확인하고 main/CI를 일치시킨다.
4. 개인정보 안내 및 스토어 서명/등록 상태를 확인한다.
5. 물리 기기 GPS/배터리/제조사 절전/health permission matrix를 실행한다.

작업 중 product dependency, DB, 기존 태그, 외부 release는 변경하지 않았다.
현재 작성한 PRD/TRD/설계는 사용자 검토 전 제안이다.

## 8. 2026-10-14 추가 경계 검토

계속 작업 시 authoritative state를 다시 확인했다. 브랜치는 clean한 `9c370d2`,
원격 main은 여전히 `b9fb762`, 최신 공개 release는 `v0.9.1`이었다. 기존 전체
품질 gate를 반복하지 않고 새로운 경계 probe만 실행했다. 설계 승인 응답은
없었으므로 제품 코드 및 구현 계획은 변경하지 않았다.

별도 `/tmp` Dart 프로그램으로 현재 SessionPipeline의 process/recalculateCompleted를
호출했다. 좌표는 앞서 사용한 적도 위도 변환, 정확도5m, 시작 UTC는
2026-10-14T00:00:00Z, session zone은 Asia/Seoul이다.

| probe | 입력 | 결과 |
|---|---|---|
| 개별 시간 반올림 | 0초0m, 29.5초29.5m, 60초29.5m | 총60초, 이동30초, 정지31초, 합계61초 |
| 분 경계 부분 시간 | 00:00:59.5부터1초 동안2m 이동 | 총1초, minute.durationS는1초/1초, 거리 합계는2m로 일치 |
| 과거 부분 제외 | 5초마다5m씩1분 이동, 10~30초만 제외 | 실제 제외20초, 세션 총시간40초/거리35m, 분 행 거리0m/제외60초 |

첫 반례의 원인은 SessionRollup이 movingSeconds와 stationarySeconds를 별도로
round하는 것이다. 두 번째는 WindowAggregator가 양수 부분 분을 각각 올림하는
기존 정수 계약에서 생긴다. 정확한 관측 시간과 표시용 최소 정수 시간의 계약을
분리하지 않으면 모든 부분 분을 양수로 유지하면서 합계도 보존할 수 없다.

세 번째는 부분 제외가 분과 겹친다는 이유만으로 _excludedWindow를 반환하는
데서 생긴다. SessionRollup과 RoutePartitioner는 실제 제외 범위를 사용하는 반면,
타임라인은 그 분 전체를0거리/제외로 보여준다. backup v2 import는 부분/복수
제외를 지원하고 관련 테스트는 대표 ID 보존을 검사하므로 실제 지원하는 경계다.
새 분 단위 제외 사용자 흐름 전체의 오류라고 일반화하지 않고 과거 백업 호환
문제로 분류한다.

MR-10에 반올림 시간 보존을 보강하고 MR-15에 부분 제외 범위와 통계/표시 일치를
추가했다. 후속 측정 설계 범위이며 현재 1차 설계의 승인 상태를 바꾸지 않는다.
