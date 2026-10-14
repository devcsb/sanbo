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
| 기존 설치 업데이트 | PASS, API34 emulator에서 v0.9.1→ddede22, 데이터 보존 |
| 실제 시스템 파일 왕복 | Android/iOS 실제 picker 저장/취소/복원/동일 이름 보존 PASS |

물리 Android 기기 검증: 미실행. `adb devices` 조회에서 연결된 기기가 없었습니다.
물리 iPhone 검증도 미실행입니다. 아래 simulator/unit 결과는 물리 기기 증거가 아닙니다.

## 현재 소스와 서명 후보의 구분

2026-10-15 지도 설계와 구현 계획을 승인받아 인증 URL, 오류 처리와 경로 보존,
비공개 빌드 설정을 구현했습니다. 실제 전용 키는 아직 준비되지 않았습니다. 아래
`ddede22` APK/AAB는 지도 수정 전 후보이며 새 코드로 다시 서명한 후보가 아닙니다.
키를 준비한 뒤 실제 Android/iOS 지도와 새 서명 빌드를 확인해야 게시할 수 있습니다.

지도 변경 소스 `8d56049`의 키 없는 전체 gate는 Flutter516개, analyzer와 debug
APK까지 통과했습니다. release 빌드는 키 누락 시 조기에 실패합니다. 실제 화면의
auto-GPU ANR과 SwiftShader 재실행 조건은 [검증 기록](../superpowers/verification/2026-10-14-maintenance-stage1.md)에
구분해 남겼습니다. 이전 signed gate를 새 지도 release 검증으로 대신하지 않습니다.

## 1차 서명 후보 검증

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

Android 시스템 picker와 기존 설치 데이터 보존은 아래와 같이 통과했습니다.
게시 전 실제 지도 복구, 새 서명 후보, PR 교차 검토와 최종 CI를 확인합니다. 미검증 항목을 완료로 바꾸지 않습니다.

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
해당 CI head까지는 `ddede22`와 제품 소스/의존성 diff가 없었습니다.
현재 검토 브랜치에는 지도 제품 소스가 추가됐으며 이전 빌드와 구분합니다.

iOS 파일 왕복은 첫 시도에 Mac 잠금으로 timeout됐으나, 같은 소스로 재시도해
시스템 저장/취소/복원과 동일 이름 두 파일 각각의 재읽기가 통과했습니다.
2026-10-15 사용자가 ADB UI 자동화를 승인한 뒤 전용 API34 emulator 두 개로
검증했습니다. 실제 시스템 picker 취소/저장/복원/동일 이름 두 파일 보존 E2E는
1개, 1분15초, exit0입니다. 별도 구버전 설치에는 실제 UI/provider로 산책을 만들고
`adb install -r`로 arm64 versionCode2015→2016을 적용했습니다. 거리122.203m,
전체342초, 유효14개/원본15개, 메모/확정 라벨/저장 장소가 보존됐습니다.
새 Settings에서8298bytes 백업을 저장하고 JSON 내용을 대조했으며 재가져오기는
`산책 0개를 가져왔어요 · 중복 1개 건너뜀`을 표시했습니다. 저장창 대기 중 프로세스를
종료하고 남아 있던 OS 저장창을 취소한 뒤 COLD 재시작과 재저장도 확인했습니다.
Activity 회전/실제 TalkBack이나 물리 기기 검증을 완료한 것으로 일반화하지 않습니다.

실제 상세 화면과 기존 CARTO URL의 HTTP200 PNG에 `API KEY REQUIRED`가
표시됐습니다. [현재 공급자 계약](https://docs.carto.com/faqs/carto-basemaps#why-do-i-see-an-api-key-required-watermark)과
키 없는 앱 요청이 맞지 않는 M-19/MR-17로 추적하고 신규 공개 게시를 차단합니다.
[지도 복구 설계](../superpowers/specs/2026-10-14-basemap-service-restoration-design.md)와
[구현 계획](../superpowers/plans/2026-10-15-basemap-service-restoration.md)을 승인받았습니다.
코드/회귀 검증은 진행했지만 실제 키로 도로와 지명을 확인하기 전까지 M-19는 열려 있습니다.

## 초안 PR와 릴리즈

[PR #1](https://github.com/devcsb/sanbo/pull/1)은 draft입니다.
[0.9.2 초안 릴리즈](https://github.com/devcsb/sanbo/releases)에도
검증한4개 산출물과 checksum을 올리고 원격 asset digest를 대조했습니다. draft는 공개 게시 증거가 아닙니다.
처음 준비한 c027b41/478개 후보에서 저자 검토의 늦은 좌표 문제를 수정했고,
새 ddede22/479개 산출물로 교체했습니다. 지도 변경을 포함한 새 build SHA와 후보, 최종 CI와 독립 검토, 실제 지도 및
물리 기기 수용 게이트가 남아 있습니다.

키 없는 실제 Android 화면, 합성 invalid-key의 공급자 안내 보존, Wi-Fi/data를 끈
상태의 회색 배경/실패 문구/marker/재생 UI도 확인했습니다. 테스트 기기의 네트워크를
원복하고 종료했습니다. 정상 키/iOS 지도/새 signed 후보 검증으로 대신하지 않습니다.

## 비공개 지도 키 준비와 빌드

기존 지도는 OSM 데이터를 CARTO가 제공하는 구조입니다. OSM 데이터 사용과
CARTO 타일 요청 인증은 별개입니다. [CARTO 공식 FAQ](https://docs.carto.com/faqs/carto-basemaps)에
따르면 무료 키를 별도로 발급할 수 있고 월 비상업500만/상업100만 타일 요청까지
무료입니다. 상업 무료 한도 초과 플랜은 월500달러부터입니다. 사용 유형과 약관 동의는
사용자가 정합니다. 계정/결제/유료 플랜 신청은 진행하지 않았습니다.

키를 Git이나 대화에 복사하지 않고 사용자 소유 로컬 파일
`~/.config/sanbo/carto-basemap.json`에 `{"CARTO_BASEMAP_KEY":"발급한 값"}`으로
보관합니다. 파일 권한은0600으로 둡니다. 경로/준비 여부만 알려주면 됩니다.
이 키는 앱에 포함되는 공개 클라이언트용 키이며 서버 비밀 키와 다릅니다.
발급 시 앱/서명 제한을 선택했다면 그 설정도 별도로 확인해야 합니다.

로컬 파일에서 환경으로만 전달하는 실행 예시는 다음과 같습니다. 값은 argv와
로그에 출력하지 않습니다. 기존 비공개 파일을 빌드 스크립트가 수정하지 않습니다.

```bash
python3 - <<'PYKEY'
import json, os
from pathlib import Path
key_file = Path.home() / '.config/sanbo/carto-basemap.json'
try:
    key = json.loads(key_file.read_text())['CARTO_BASEMAP_KEY'].strip()
    if not key:
        raise ValueError()
except (OSError, ValueError, KeyError, AttributeError):
    raise SystemExit('CARTO build configuration is not ready') from None
os.environ['CARTO_BASEMAP_KEY'] = key
os.environ['QUALITY_BASE_REF'] = 'v0.9.1'
os.execvpe('bash', ['bash', 'scripts/run_quality_loop.sh', '--all-apk'], os.environ)
PYKEY
```

release/all은 키가 없으면 Git/Flutter gate 전에 중단합니다. debug/no-build는 키 없이
실행할 수 있습니다. 키가 있는 빌드는 새 private 임시 디렉터리의0600 JSON을
`--dart-define-from-file`로 전달하고 성공/실패 후 해당 파일과 디렉터리만 정리합니다.
이전 서명 후보를 키 없는 지도 수정 후보로 재표시하거나 다시 올리지 않습니다.
