# 1차 유지보수 구현과 검증 기록

기존 서명 후보 build SHA는 `ddede226e62532c4613707a92818d1fc7c615929`입니다.
2026-10-15 지도 복구 제품 변경은 이 후보에 포함되지 않으며 새 빌드 검증을 구분합니다.
[통합 계획](../plans/2026-10-14-maintenance-stage1.md),
[릴리즈 증적](../../release/2026-10-14-maintenance-stage1-release.md)을 함께 봅니다.

| 검사 | 결과 |
|---|---|
| 전체 품질 loop `--all-apk` | PASS, Flutter 479개, analyzer, debug/release/AAB, manifest, cert, hash, clean-tree |
| 전체 native gate | PASS, Android JUnit 16개, iOS 26.5 XCTest 11개 |
| APK 버전/서명 | 세 ABI의 versionCode 각각 증가, 기존 인증서 일치 |
| AAB manifest/서명 | 0.9.2+16, SDK36, JAR 검증과 인증서 일치, bundletool validate exit0 |
| 기존 APK 보존 | 공개 v0.9.1 세 파일 SHA-256 일치, 별도 보존 |
| 실제 iOS picker 왕복 | 재시도 PASS, 취소/저장/복원/중복 이름 보존과 두 파일 재읽기 |
| iOS 실제 위치/알림 채널 smoke | PASS, 전용 simulator의 native provider와 notification cancel 호출 2개 |
| 실제 Home 표시 | iOS 밝은/어두운 테마에서 측정 대기, 유효0, stale 문구와 Semantics 확인 |
| 실제 Android picker / 설치 업데이트 | PASS, API34 실제 파일 왕복 E2E1개와 구버전→ddede22 데이터 보존 |
| 실제 배경 지도 | FAIL, HTTP200 PNG에 API 키 안내. M-19/MR-17으로 신규 공개 게시 차단 |
| 실제 스크린리더 / 물리 GPS·배터리 | 미실행 |
| 신규 공개 게시 / Play | 미실행 |

전체 gate와 새 회귀 결과를 확인한 뒤 기록했습니다. 같은 최종 gate를 반복하지 않았습니다.
마지막 build와 제품 코드가 달라지면 관련 검증을 다시 해야 합니다.

## 구현한 동작

복구 경로를 공통 partitioner로 분할하고, filtered tail 뒤 첫 새 좌표를 과거
fragment에 연결하지 않습니다. 현재 속도의 숫자와 최신 여부를 분리했습니다.
재생과 접근성 값은 세션 IANA 시간대를 쓰고 완료 export 평균은 거리/이동 시간
helper를 재사용합니다. Health 읽기 실패/권한/연결 전/0을 구분하며 지원 없는
iOS Health Connect 설정 버튼을 숨깁니다. 모바일 백업은 파일 경로만 native에
보내며 실제 copy/OS callback 완료 이후 성공/취소/오류를 반환하도록 구현했습니다.

## 실행 중 판정과 남은 검증

- 승인된 기존 검토 브랜치를 유지했고 재위임하지 않았습니다. 독립 교차 검토는
  PR 사용자 검토 전입니다. 저자 검토를 독립 검토로 주장하지 않습니다.
- Android picker의 request code는 4105부터 작업별로 증가합니다. 이전 Activity
  응답이 새 작업을 완료하지 않게 하기 위한 변경이며 16-bit 범위에서 순환합니다.
- temp cleanup은 native 결과를 가리지 않는 best effort입니다. 실패한 정리는
  다음 export에서 24시간 초과한 산보 전용 폴더를 대상으로 다시 처리합니다.
- 저장하는 malformed 좌표는 기존 repository가 버립니다. 따라서 복구 후 live
  malformed tail을 시험했습니다. malformed 경계를 process death 이후 보존할
  방법은 별도 저장 설계가 필요합니다. 1차에서 schema와 원본 좌표 계약을 바꾸지
  않았으며 이 한계를 완료된 해결로 주장하지 않습니다.
  별도 probe에서 위도91 행을 저장 목록에서 버린 뒤 복구하면40m, 동일 원본을
  바로 필터/분할하면20m임을 확인했습니다. PRD M-18/MR-16으로 추적합니다.
- Flutter test의 real timer, offscreen/merged Semantics를 분리해 실제 widget
  callback의 시각을 검사했습니다. 실제 VoiceOver 포커스/발화는 별도 검증입니다.
- 여러 파일 변경의 독립 교차 검토와 실제 지도 복구/게시 확인이
  끝나기 전에는 이 계획과 전체 목표를 완료로 표시하지 않습니다.

## 로컬 실행 로그

검증 원본은 각 계획의 git-ignored `.superpowers/sdd/` workspace에 보관합니다.
`integration-quality.log`, `integration-native.log`, `release-artifacts.json`,
`native-summary.json`과 각 task의 RED/GREEN 로그를 남겼습니다.
GitHub 문서의 PASS만으로 재실행 증거를 대신하지 않습니다.

## 저자 검토에서 추가로 수정한 반례

10초5m 위치를 받은 뒤5초2m 좌표가 늦게 도착하면 기존 증분 경계가 다음
30초20m 선분까지 옮겨져 live5m/완료15m가 됐습니다. 새 회귀가5m로 실패하는
것을 확인하고 거절된 늦은 좌표에 한해 공통 partitioner로 재계산했습니다.
live/완료 모두15m이며 관련57개 테스트와 전체479개, 새 APK/AAB gate를
통과했습니다. 최종 제품 build는 `ddede226e62532c4613707a92818d1fc7c615929`입니다.

정상 순서 callback은 O(1)을 유지합니다. 늦은 좌표는5시간 상한의 buffer에서
O(n log n) 재계산하며, 자주 발생하는 provider에는 후속 indexed reducer가
필요합니다. Native 소스/의존성은 직전16/11개 gate 소스와 diff가 없습니다.

저자 검토로 구현/취소/오류/stream close/경로와 최신성/시간대/export 경계를
읽고 확인했습니다. 새로 확인한 늦은 좌표 불일치는 수정했습니다. Android picker와
설치 보존은 아래 추가 검증을 통과했지만 독립 PR 검토와 실제 지도 확인이 남아 merge/publication 준비 완료로
판정하지 않습니다. M-18과 측정 정책, 실제 스크린리더/물리 GPS는 후속 요구로
유지합니다. 테스트와 문서로 그 항목을 완료한 것으로 대체하지 않습니다.

## 실제 iOS 검증 재개

첫 시도의 Mac 잠금/12분 timeout은 환경 제한이었다. 전용 iPhone17Pro
`Sanbo Maintenance 20261014` / iOS26.5 / device ID
`47B2C6D4-88A1-4D43-90B3-0C4DB02EE71A`를 부팅한 뒤 CUA 화면에 접근할 수 있었다.
같은 제품 소스에서 다음 새 검증을 진행했다.

```bash
flutter test --no-pub integration_test/native_backup_export_e2e_test.dart -d 47B2C6D4-88A1-4D43-90B3-0C4DB02EE71A
flutter test --no-pub integration_test/native_notification_channel_e2e_test.dart integration_test/native_location_e2e_test.dart -d 47B2C6D4-88A1-4D43-90B3-0C4DB02EE71A
```

첫 명령은 1개 test, 3분2초, exit0이다. 시스템 저장창에서 취소하고 다시 저장한
파일의 bytes와 두 native SQLite DB의 원본7개, 분별 라벨/메모/장소/제외를
비교했다. 동일 파일 재가져오기는 중복 산책1개를 건너뛰었다. 같은 이름으로 두 번째
내용을 저장할 때 시스템 `둘 다 유지`를 선택하고 두 파일을 각각 열어 첫 내용과
새 내용이 보존됐는지 확인했다. 성공은 mock/native unit의 대체 결과가 아니다.
로그는 백업 ledger의 `task-3-ios-e2e-retry.log`다.

두 번째 명령은 2개 test, 1분38초, exit0이다. CoreLocation provider에 simctl로
합성 보행 경로1.4m/s를 주고, CUA로 위치를 한 번 허용했다. 거리15m 초과,
유효 위치3개 이상과 완료 저장을 확인하는 기존 smoke 및 실제 notification
channel cancel 호출이 통과했다. `ios-native-smoke.log`에 결과가 있다. 물리
정확도나 실제 알림 발화/배터리 검증으로 일반화하지 않는다. 종료 후 합성 위치를
clear했다.

`lib/main.dart` 실제 실행에서는 신호 전 `측정 대기`, 합성 정지 관측 뒤
`0.0km/h`, 위치 공급 clear 후 `측정 중단`을 화면에서 확인했다. CUA AX 값도
stale 상태에서는 `현재 속도 측정 중단`으로 바뀌고 이전 숫자를 읽지 않았다.
어두운 테마에서도 같은 상태와 종료 버튼을 확인하고 테스트 산책을 종료했다.
320dp/2배 글자는 앞서 통과한 widget 검증이며 이 simulator 크기로 검증했다고
주장하지 않는다. 실제 VoiceOver/TalkBack 검증은 여전히 미실행이다.

## Android 검증 접근과 추가 지도 오류

새 전용 `sanbo_maintenance_20261014`, Pixel6/API34/arm64 emulator에 보존한
v0.9.1 signed APK를 설치했고 `adb install` 결과는 Success였다. 기존 다른
프로젝트 AVD나 사용자 기기의 데이터를 지우지 않았다. CUA는 실행 중인
`qemu-system-aarch64` 이름과 실제 binary 경로를 모두 `Invalid app`으로
거절했다. 2026-10-15 사용자가 대체 ADB UI 자동화를 승인해 검증을 재개했다.
별도 `sanbo_backup_e2e_20261015`/API34의 실제 native 백업 E2E1개가1분15초에
통과했다. 취소/저장/복원/중복 ID 건너뛰기와 동일 이름 두 파일 내용 보존을 확인했다.
구버전 설치에서는 실제 UI/provider 산책을 만든 뒤 삭제 없이 signed `ddede22`로
업데이트했다. 122.203m/342초/유효14개와 원본15개, 메모/확정 라벨/장소가
유지됐고 실제 Settings 백업8298bytes와 재가져오기 중복1개 건너뛰기를 확인했다.
로그 `android-signed-upgrade.log`, 실제 파일의 구조/수치 대조 결과
`android-upgraded-backup-check.json`, UI 캡처 `android-new-*`에 남겼다.
저장창 중 프로세스 종료, OS 저장창 취소, COLD 재시작 뒤 저장 성공도 확인했다.
Activity configuration 회전/스크린리더/물리 GPS 검증을 뜻하지 않는다.

실제 iOS 상세 지도는 `API KEY REQUIRED` 이미지였다. 기존 CARTO endpoint에
HTTP200/image/png/2049bytes가 반환됐으나 파일을 직접 열어 정상 지도가 아님을
확인했다. [공식 CARTO 계약](https://docs.carto.com/faqs/carto-basemaps#why-do-i-see-an-api-key-required-watermark)도
2026-09-25부터 키 없는 raster 제공을 중단했다고 설명한다. PRD M-19/MR-17과
[추가 설계](../specs/2026-10-14-basemap-service-restoration-design.md)와 구현 계획을
2026-10-15 승인받았다. 인증/키 미설정/HTTP200 notice/네트워크/codec 실패와
닫힌 화면 callback/재생 rebuild/화면 재열기 회귀를 구현했다. 공급자 notice는
보존하고 앱 안내는 지도 아래 표시한다. 실제 키 미준비로 정상 지도/새 서명 후보는
미검증이다. 기존 `ddede22` 후보에 지도 수정이 포함됐다고 주장하지 않는다.

## 지도 변경 소스의 새 검증

지도 소스와 키 전달 설정을 포함한 `8d560499bf4884528fcb265f7c99d6ef9067f872`에서
키 없이 `QUALITY_BASE_REF=v0.9.1 bash scripts/run_quality_loop.sh --debug-apk`를
실행했습니다. Flutter516개, analyzer, Android debug APK, 문서/whitespace와
generated-file audit가 통과했고 exit0입니다. APK SHA-256은
`598ed70bc40e9828593383503029e57b38fe010b58c0fd1e7398eba192b546a6`입니다.
이 값은 keyless debug build이며 기존 signed candidate와 구분합니다.

새 디버그 APK의 첫 API34 auto-GPU 실행은 ANR로 실패했습니다. main은
`FlutterJNI.nativeSurfaceCreated`를 기다렸고 raster는 에뮬레이터 GLES의
`qemu_pipe_read/glLinkProgram`에서 대기했습니다. 앱의 지도 진입 전이었습니다.
같은 APK와 데이터를 보존한 채 전용 AVD만 SwiftShader로 다시 시작하자
COLD launch statusok/3117ms로 실행됐습니다. 원본 dropbox stack과 첫 실패를
보존했습니다. 제품 코드로 ANR을 고쳤거나 물리 기기 성능을 측정했다고 주장하지
않으며, 이후 에뮬레이터 화면 검증은 이 소프트웨어 렌더러 조건으로 구분합니다.

전용 키가 없어 새 release APK/AAB, Android/iOS 정상 도로·지명 확인과 draft
asset 교체는 실행하지 않았습니다. 이 남은 게이트 없이 M-19를 해결 완료로
표시하지 않습니다. 검토는 저자가 수행했으며 독립 PR 검토는 사용자 검토 전입니다.

키 없는 debug APK를 같은 전용 API34 AVD에서 실제 실행하고 Settings의 시스템
picker로 앞서 보존한 합성 산책을 가져왔습니다. 상세 화면은 위치14개/시작점/종료점/
재생 위치, 지도 아래 실패 문구, 재생 버튼/시각 변화/접근성 시각을 유지했습니다.
시작 직후 AVD의 기본 위치와 주입 경로가 서로 멀어 전체 bounds가 넓은 합성 기록이며,
선분 수와 분할 보존은 widget/geometry 회귀로 별도 확인했습니다. 정상 도로/지명이
표시된 결과가 아닙니다. 증거는 `android-keyless-session-detail.*`과
`android-keyless-playback-running.*`입니다.

최종 UI 검증은 전용 AVD SwiftShader와 Flutter 런타임 QA 플래그
`enable-software-rendering=true`, `enable-impeller=false`를 함께 썼습니다.
첫 단일 software 플래그 시도는 Impeller와 양립하지 않는다는 엔진 assertion으로
종료됐고 두 플래그를 함께 적용해 실행했습니다. 이 플래그는 검증 기기에만 주었으며
제품 Manifest/renderer 설정과 서명 후보를 변경하지 않았습니다.

같은 소스의 별도 debug build에 실제 자격 증명이 아닌 고정 invalid key를 넣었습니다.
실제 CARTO 안내 PNG가 표시됐고 이를 가리거나 지우지 않으면서 지도 아래 앱 안내와
marker/재생을 유지했습니다. 현재 앱 프로세스 logcat을 검사해 test key와
`?key=` URL이 없음을 확인했습니다. Android 전용 기기의 Wi-Fi/data를 끄고 화면을
다시 열었을 때 이전 안내 타일을 성공 cache로 재사용하지 않고 회색 배경/실패 문구/
marker/재생 UI를 유지했습니다. 네트워크 설정은 초기값으로 모두 원복했습니다.
증거는 `android-invalid-key-settled.*`, `android-offline-detail.*`와
`android-invalid-build-check.json`입니다. 종료 후 두 전용 AVD를 중지했으며 데이터는
보존했습니다. 실제 정상 키와 iOS 지도 UI, 새 signed map candidate는 여전히 남아 있습니다.
