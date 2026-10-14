# 산보 0.9.2 1차 유지보수 릴리즈 증적

| 항목 | 상태 |
|---|---|
| 후보 | `0.9.2+16` |
| 기본 코드 | 공개된 `v0.9.1` / `1368d45` |
| 대상 | Android 우선, minSdk 26, targetSdk 36 |
| 공개 게시 | 미실행, draft 준비. 추가 발견한 지도 오류로 차단 |
| Google Play | 게시 여부 미확인, 신규 게시 미실행 |
| build SHA | `ddede226e62532c4613707a92818d1fc7c615929` |
| 신규 태그 / PR CI | PR#1 draft. CI는 PR 현재 head에서 별도 확인 |
| 기존 설치 업데이트 | Android 전용 API34 emulator에 기존 APK 설치. UI 검증 대기 |
| 실제 시스템 파일 왕복 | iOS 재시도 PASS, Android UI 검증 대기 |

물리 Android 기기 검증: 미실행. `adb devices` 조회에서 연결된 기기가 없었습니다.
물리 iPhone 검증도 미실행입니다. 아래 simulator/unit 결과는 물리 기기 증거가 아닙니다.

## 현재 검증

- 복구 거리와 필터 경계 관련 52개 테스트 통과.
- 현재 속도와 Home/복구 관련 68개 테스트 통과.
- 재생 시간대와 DST fold 관련 7개 테스트 통과.
- 완료 export/평균 속도 관련 18개 테스트 통과.
- 건강 데이터 상태와 재조회 관련 31개 테스트 통과.
- Android native unit tests 통과, 신규 파일 경계와 stream 테스트 5개 포함.
- iPhone 17 Pro, iOS 26.5 simulator XCTest 11개 통과.
- 실제 Flutter 백업 어댑터, 설정, codec 관련 26개 테스트 통과.
- `ddede22`에서 전체 Flutter 479개, analyzer, Android debug/release APK와 AAB, 서명/체크섬/작업 트리 검사 통과.
- 같은 제품 소스의 최종 native gate에서 Android JUnit 16개와 iOS XCTest 11개 통과.
- 전용 iPhone17Pro/iOS26.5에서 실제 시스템 picker 취소/저장/복원/동일 이름 두 파일 보존 1개 E2E 통과.
- 같은 simulator의 실제 위치 제공자와 notification cancel 채널 smoke 2개 통과.
- 실제 Home에서 신호 전 측정 대기, 유효 정지0, 위치 공급 중단 뒤 측정 중단과 숫자 제거를 밝은/어두운 테마에서 확인.

각 묶음에 겹치는 기존 테스트가 있어 개수를 합산하지 않습니다. 과거 439개 baseline
통과를 새 코드 전체 검증으로 재사용하지 않습니다.

## 준비할 산출물

| 파일 | 상태 |
|---|---|
| `app-release.aab` | 서명/manifest 검증 통과, 게시 전 |
| `app-arm64-v8a-release.apk` | 버전/서명 검증 통과, 게시 전 |
| `app-armeabi-v7a-release.apk` | 버전/서명 검증 통과, 게시 전 |
| `app-x86_64-release.apk` | 버전/서명 검증 통과, 게시 전 |
| `SHA256SUMS_v0.9.2.txt` | 아래 4개 SHA-256과 일치 |

기존 인증서 SHA-256은
`ceb40402d706589acee5da5df5a010c3dd5c2e9329cd3218961dfce56a6d38ac`입니다.
새 APK와 AAB의 실제 인증서, manifest, 버전과 hash를 빌드 후 조회했습니다.
ABI별 versionCode는 기본 16과 다르므로 같은 ABI의 v0.9.1보다 증가했는지 비교했습니다.

게시 전 Android 시스템 picker 왕복, lifecycle과 기존 설치 데이터 보존, 추가 지도
오류 복구, PR 교차 검토와 최종 CI를 확인합니다. 미검증 항목을 완료로 바꾸지 않습니다.

## 확인한 산출물

| 파일 | SHA-256 |
|---|---|
| `app-armeabi-v7a-release.apk` | `c0b362ac43f0d38dfe47cdad2e05bf51147f0b98c48d3cc57c27e56f91b2bdb4` |
| `app-arm64-v8a-release.apk` | `b53c2f8dc3546f154438934dbc2f795ce34dc95baefe7b060b4a9d1428b174ea` |
| `app-x86_64-release.apk` | `88e8d8fe9b749da0bdeded1dc2afd559169ebcfda8fb95f5e5578a263a05b83e` |
| `app-release.aab` | `8c8a5737edc543ed0b7a08a3ee792b9c92076f6a3411501e8f732b87f1846426` |

APK versionCode는 armeabi-v7a 1015→1016, arm64-v8a 2015→2016,
x86_64 4015→4016입니다. AAB는 16, 모든 targetSdk는 36이며 기존 인증서와
일치합니다. bundletool 1.18.3 manifest/validate와 JAR 서명 검사를 통과했습니다.

JDK keytool의 한국어 출력에서 `IllegalFormatConversionException`이 발생했습니다.
해당 명령에만 영어 locale을 지정해 인증서를 조회했습니다. 산출물과 시스템
설정은 바꾸지 않았습니다. JAR self-signed/stream-order 경고는 검증 로그에 남겼으며
bundletool validate는 exit 0입니다. Google Play 접수 검증으로 일반화하지 않습니다.

원격 main을 기존 공개 v0.9.1 커밋 `1368d45`로 non-force fast-forward했습니다.
이후 CI는 [run 38501773934](https://github.com/devcsb/sanbo/actions/runs/38501773934)에서
커밋 `1368d45`의 CI가 성공했습니다. 신규 후보의 마지막 PR head CI와는 별개입니다.

문서 보강 전 PR head `082a4635c8d28cba0a456ce1a856b3ec90d5d08e`의
[run38505847746](https://github.com/devcsb/sanbo/actions/runs/38505847746)는 Flutter와
native 두 job 모두 성공했습니다. 이후 문서 commit의 CI 상태는 PR 현재 head에서
다시 구분하며, 기존 성공을 새 head의 성공으로 대신하지 않습니다. 제품 build
`ddede22` 이후 제품 소스/의존성 diff는 없습니다.

iOS 파일 왕복은 첫 시도에 Mac 잠금으로 timeout됐으나, 같은 소스로 재시도해
시스템 저장/취소/복원과 동일 이름 두 파일 각각의 재읽기가 통과했습니다.
Android는 기존 signed APK 설치까지 확인했습니다. CUA가 emulator 앱을 인식하지
못해 대체 UI 자동화에 필요한 명시 요청을 기다립니다. 시스템 picker와 구버전
기록의 업데이트 보존, 실제 VoiceOver/TalkBack은 검증 대기입니다.

실제 상세 화면과 기존 CARTO URL의 HTTP200 PNG에 `API KEY REQUIRED`가
표시됐습니다. [현재 공급자 계약](https://docs.carto.com/faqs/carto-basemaps#why-do-i-see-an-api-key-required-watermark)과
키 없는 앱 요청이 맞지 않는 M-19/MR-17로 추적하고 신규 공개 게시를 차단합니다.
[지도 복구 설계 초안](../superpowers/specs/2026-10-14-basemap-service-restoration-design.md)은
검토 전이며 1차 build에는 지도 수정이 없습니다.

## 초안 PR와 릴리즈

[PR #1](https://github.com/devcsb/sanbo/pull/1)은 draft입니다.
[0.9.2 초안 릴리즈](https://github.com/devcsb/sanbo/releases)에도
검증한4개 산출물과 checksum을 올리고 원격 asset digest를 대조했습니다. draft는 공개 게시 증거가 아닙니다.
처음 준비한 c027b41/478개 후보에서 저자 검토의 늦은 좌표 문제를 수정했고,
새 ddede22/479개 산출물로 교체했습니다. 최종 CI head와 실제 기기 수용 게이트, 지도 복구가
남아 있습니다.
