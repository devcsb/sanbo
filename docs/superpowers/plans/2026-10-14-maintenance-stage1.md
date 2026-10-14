# 산보 1차 유지보수 통합 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 승인된 MR-01~07을 수정하고 새 검증과 서명된 0.9.2 후보, 검토 가능한 PR/배포 자료를 만든다.

**Architecture:** [측정 표시 계획](2026-10-14-session-measurement-consistency.md)과 [모바일 백업 계획](2026-10-14-mobile-backup-export.md)을 독립적으로 구현한 뒤 이 통합 계획에서 새 revision 검증과 릴리즈 준비를 연결한다. 기존 도메인/저장/플랫폼 경계를 유지하고 원본 기록을 재작성하지 않는다.

**Tech Stack:** Flutter 3.47.1/Dart, Android Kotlin/API26+/target36, iOS Swift/15+, SQLite v6, Git/GitHub Releases, JUnit/XCTest/Flutter tests.

**Spec:** [1차 설계](../specs/2026-10-13-measurement-consistency-and-backup-design.md), 사용자 승인 2026-10-14. 관련 [PRD](../../PRD_MAINTENANCE_2026-10.md), [TRD](../../TRD_MAINTENANCE_2026-10.md).

## Global Constraints

- 사용자 지침대로 현재 Codex 실행자가 이 세션에서 직접 수행한다. 재위임하지 않는다.
- 제품 코드 수정은 이 작성된 구현 계획을 사용자가 검토한 뒤 시작한다.
- 후보 버전은 `0.9.2+16`. 기존 `v0.9.1` 태그/파일/서명/체크섬을 바꾸지 않는다.
- 기존 signing fingerprint `ceb40402d706589acee5da5df5a010c3dd5c2e9329cd3218961dfce56a6d38ac`, minSdk26, targetSdk36을 유지한다.
- 기존 전체 백업 v2, 세션 export v2, SQLite v6와 원본/라벨/장소/제외 취소를 유지한다.
- GPS maxAge 30초, futureSkew 5초, routeGap 60초, 거리 하한 1.5m, 추적 간격과 5시간 종료는 1차에서 바꾸지 않는다.
- 자동 제외 후속 방향은 사용자 선택인 지속 고속+GPS 품질 확인이다. 임계 지속 시간 등 미작성 정책을 이번 코드에 임의로 넣지 않는다.
- 반복 gate 대신 변경된 revision의 의미 있는 검증을 남긴다. 실제 기기와 simulator/emulator 결과를 구분한다.
- 여러 파일 변경은 최종 PR을 사용자에게 보여 교차 검토를 받는다. 공개 게시 단계는 검증된 산출물을 준비한 뒤 별도로 확인한다.

## Review Focus

- 복구/종료/설정의 기존 기록이 새 APK 업데이트 후 유지된다. 아래 Task 2의 기존 설치 업데이트에서 확인한다.
- source/tag/CI가 다른 과거 배포 상태를 다시 만들지 않는다. 아래 Task 2에서 non-force main 정리와 exact revision CI를 확인한다.
- ABI별 versionCode가 기본 +16과 다름을 놓치지 않는다. 아래 Task 1/2에서 새 APK 각각을 기존 APK와 비교한다.
- 마지막 native 저장 결과/false Health capability/최근 GPS freshness가 플랫폼마다 다르게 작동하지 않는다. 두 하위 계획의 actual adapter/native/UI 검사로 확인한다.
- 검증 후 metadata/문서만 더해도 이전 binary를 다른 제품 코드라고 주장하지 않는다. 아래 Task 2에서 build SHA와 product-source diff를 기록한다.

## 실행 순서와 단계 상태

1. 측정 표시 계획 Task1~5를 순서대로 실행한다.
2. 모바일 백업 계획 Task1~3을 실행한다.
3. 아래 릴리즈 metadata, 전체 검증과 배포 자료 작업을 실행한다.

각 task는 fail→최소 수정→focused green→해당 파일 커밋 순서다. 기존 사용자 수정과
다른 세션의 파일을 되돌리지 않는다. 실행 시작 시 `git status`, `git worktree list`,
App의 `list_artifacts`로 현재 checkout을 확인하고 using-git-worktrees 스킬에 따라
맞는 작업 공간을 선택한다. 현재 브랜치는 `codex/sanbo-maintenance-review-20261013`이다.
이미 검토 브랜치와 clean checkout이 있으면 이를 유지하며 불필요한 worktree를 만들지 않는다.

## 요구 추적

| 요구 | 작업 | 종료 증거 |
|---|---|---|
| MR-01 | 백업 계획 Task 1~3 | 실제 mobile picker 저장/취소와 bytes/DB import 왕복 |
| MR-02 | 측정 계획 Task 1 | 복구 10m/완료 10m, filtered tail 뒤 첫 샘플의 연결 차단 |
| MR-03 | 측정 계획 Task 2 | 30초 경계, stale 숫자/접근성 숨김, fresh 0, cold/warm resume |
| MR-04 | 측정 계획 Task 3 | 세션 zone의 재생/양 끝/접근성, DST fold 및 다른 기기 zone |
| MR-05 | 측정 계획 Task 4 | 저장값 9와 관계없이 100/100=1m/s, JSON/NDJSON/human 일치 |
| MR-06 | 측정 계획 Task 5 | error/denied/unavailable/partial/zero, iOS false settings capability |
| MR-07 | 통합 계획 Task 1~2 | 버전/manifest/cert/hash, main/tag/CI SHA, 기존 설치 업데이트, 게시 상태 |

MR-08~15와 스토어 준비 요구는 1차 완료로 표시하지 않는다. 원래 전체 목표는
1차만으로 끝나지 않으며 후속 측정 설계와 구현, 실기기 검증까지 별도로 추적한다.

### Task 1: 신규 후보 metadata와 release gate

**Files**
- Modify: `pubspec.yaml`, `lib/app/app_info.dart`, `scripts/run_quality_loop.sh`.
- Modify: `test/features/release_metadata_docs_test.dart`, 필요 시 `test/app_info_test.dart`의 후보 기대값.
- Create: `RELEASE_NOTES_v0.9.2.md`, `docs/release/2026-10-14-maintenance-stage1-release.md`.
- Create after actual gates: `docs/superpowers/verification/2026-10-14-maintenance-stage1.md`.

**Interfaces**
- AppInfo.version `0.9.2`, pubspec `0.9.2+16`.
- Gate produces `build/app/outputs/release/SHA256SUMS_v0.9.2.txt` and signed AAB/ABI APKs.
- release evidence distinguishes planned/pass/fail/not-run by command/revision, never by intent.

- [x] Step 1: release_metadata_docs_test를 새 버전과 새 증적 파일로 바꿔 실제 파일
미존재/버전 불일치로 RED를 확인한다. 기존 0.9.1 증적은 그대로 두고 기대값만
신규 후보로 옮긴다.

```dart
test('release metadata selects 0.9.2 and keeps device status explicit', () {
  final pubspec = File('pubspec.yaml').readAsStringSync();
  final release = File('docs/release/2026-10-14-maintenance-stage1-release.md')
      .readAsStringSync();
  expect(pubspec, contains('version: 0.9.2+16'));
  for (final text in ['0.9.2+16', 'app-release.aab',
    'app-arm64-v8a-release.apk', 'SHA-256', 'targetSdk 36']) {
    expect(release, contains(text));
  }
});
```

게이트 결과는 이 문자열 test로 증명하지 않고 실제 command output으로 기록한다.
새 증적 문서에는 실제 연결 조회 결과로 물리 기기 검증 상태를 적는다.

- [x] Step 2: pubspec/AppInfo 버전을 변경하고 release gate의 candidate/evidence/
versionName/checksum 이름을 새 후보로 바꾼다. signing/manifest/clean-tree/
generated-file 검사와 기존 키 접근 방식을 유지한다. versionName은 선택한
`expected_release_version`의 `+` 앞값에서 도출해 중복 hard-code를 줄인다.

```bash
expected_release_version="0.9.2+16"
expected_version_name="${expected_release_version%%+*}"
release_evidence="docs/release/2026-10-14-maintenance-stage1-release.md"
checksum_file="$checksum_dir/SHA256SUMS_v$expected_version_name.txt"
```

- [x] Step 3: release notes는 실제 구현된 MR-01~06과 검증 범위만 쓰고 자동 제외/
노이즈 개선을 포함했다고 쓰지 않는다. 새 gate/실제 기기 결과는 처음에는 미실행으로
기록하고 command가 끝난 뒤만 갱신한다.
- [x] Step 4: `flutter test --no-pub --concurrency=1 test/features/release_metadata_docs_test.dart test/app_info_test.dart`와 `git diff --check`를 실행하고 해당 파일만 `chore: 산보 0.9.2 릴리즈 후보 메타데이터 정리`로 커밋한다.

### Task 2: 통합 검증, 기존 설치 업데이트, PR와 배포 자료

**Files / artifacts**
- Read/build: 위 두 하위 계획의 전체 제품 코드와 후보 metadata.
- Write results: `docs/superpowers/verification/2026-10-14-maintenance-stage1.md`, 신규 release evidence.
- Build: `build/app/outputs/bundle/release/app-release.aab`, ABI APK3개, 신규 checksum.
- External preparation: 작업 브랜치, draft PR, draft GitHub Release. 생성한 PR은 App에 attach한다.

**Interfaces**
- Verification record contains source/build SHA, actual commands/exits, test counts, native picker results, device model/OS, cert/manifest/hash, and unverified physical/store items.
- Published release URL/version/assets are re-read from GitHub API after the publication step. Draft URL is not publication evidence.

- [x] Step 1: 새 build 전에 old release APK 3개를 `/tmp/sanbo-v0.9.1-upgrade-baseline`에
보존한다. 로컬 output이 없으면 GitHub의 v0.9.1 asset을 같은 폴더에 받고 기존 공개
hash와 비교한다. 기존 태그나 원격 asset은 수정하지 않는다.

- [x] Step 2: clean committed tree에서 새 소스 SHA를 기록하고 서로의 generated state를
바꿀 수 있는 Flutter/Gradle/Pods gate는 순차 실행한다.

```bash
git status --porcelain=v1
release_build_sha="$(git rev-parse HEAD)"
QUALITY_BASE_REF=v0.9.1 bash scripts/run_quality_loop.sh --all-apk
bash scripts/run_native_platform_tests.sh
```

전체 gate는 기존 439개 baseline을 재인용하지 않는다. 새 tests의 실제 최종 개수와 exit를
기록한다. gate가 제품 파일이나 lockfile을 바꾸면 생성 변경을 검토한 뒤 새 revision에서
필요한 gate만 다시 실행한다. 성공한 같은 revision의 전체 gate를 별 이유 없이 반복하지 않는다.

- [x] Step 3: APK 3개에 대해 실제 versionName/versionCode/targetSdk/certificate를 조회한다.
각 새 versionCode는 같은 ABI의 0.9.1 APK보다 커야 한다. arm64의 기존 값 2015와 기본 15를
혼동하지 않는다. AAB도 artifact manifest와 jar 서명을 검사한다. bundletool CLI가 없으면
공식 google/bundletool release의 all-jar를 도구용 `/tmp`에 받고 버전과 SHA를 기록한다.
제품 dependency에는 넣지 않는다.

```bash
apkanalyzer manifest version-name build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
apkanalyzer manifest version-code build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
apkanalyzer manifest target-sdk build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
apksigner verify --print-certs build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
jarsigner -verify build/app/outputs/bundle/release/app-release.aab
bundletool dump manifest --bundle=build/app/outputs/bundle/release/app-release.aab --module=base
```

apksigner/apkanalyzer가 PATH에 없으면 실행 중 확인한 Android SDK 도구의 절대 경로를
사용한다. bundletool all-jar는 조회한 공식 jar 경로를 `bundletool_jar` 변수에 넣고
`java -jar "$bundletool_jar" dump manifest --bundle=build/app/outputs/bundle/release/app-release.aab --module=base`
형식으로 같은 명령을 실행한다. trace에는 실제 사용한 도구 경로를 남긴다.

- [ ] Step 4: 두 하위 계획의 focused native/device 시나리오와 실제 백업 왕복을 끝낸다.
기존 native location/notification smoke는 새 native registration과 lifecycle 회귀를
확인할 때 실행한다. host용 FFI helper를 실제 기기 DB factory로 사용하지 않는다.

- [ ] Step 5: 전용 Android emulator에 보존한 v0.9.1 signed APK를 설치해 짧은 산책 기록을
실제 UI/provider로 하나 만든다. native backup이 없는 구버전이므로 백업 성공을 전제하지
않는다. 기록 시간/거리/라벨/장소를 캡처한 뒤 같은 ABI의 새 APK를 `adb install -r`로
업데이트한다. 삭제 설치/`pm clear` 없이 기록이 남고 MR-01 저장/가져오기와 상세/재생이
작동하는지 확인한다. debug/release의 versionCode나 서명이 달라 실패하면 그 원인을
보고하며 설치 데이터를 지워 우회하지 않는다.

- [ ] Step 6: 밝은/어두운 테마, 320dp/1.8배와 2배 글자, 신호 없음/정지 0/stale/
복구/Health 오류의 수치와 버튼을 확인한다. 프레임/배터리 효과를 화면 이미지나
synthetic 계산 시간만으로 주장하지 않는다. VoiceOver/TalkBack을 실행하지 못하면
Semantics/widget 증거와 구분한다.

- [x] Step 7: 결과 문서를 실제 source SHA와 함께 기록한다. 검증 후 문서만 추가해 commit이
바뀌면 아래처럼 제품 소스가 같은지 확인한다. 여기서 release_build_sha는 Step 2에서
기록한 실제 값이고 committed 제품 파일이 달라지면 artifact 검증을 새로 해야 한다.

```bash
git diff "$release_build_sha" HEAD -- lib android ios pubspec.yaml pubspec.lock
```

문서 commit을 binary build SHA와 동일하다고 쓰지 않는다. release tag는 검증한 제품
build SHA를 대상으로 잡고 새 증적/문서 commit의 관계를 명시한다.

- [ ] Step 8: 원격 main을 조회해 이미 공개된 `1368d45`의 ancestor인지 확인한다.
그대로라면 공개된 v0.9.1 source로 non-force fast-forward하고 작업 브랜치를 push한다.
원격에 다른 작업이 있으면 fetch 후 비교하고 그 변경을 보존해 통합한다.

```bash
git fetch origin
git merge-base --is-ancestor origin/main 1368d453803df4b69f4158ff1181fd17e539a2f8
git push origin 1368d453803df4b69f4158ff1181fd17e539a2f8:refs/heads/main
```

두 번째 검사가 성공한 경우에만 세 번째 명령을 실행하고 force 옵션을 쓰지 않는다.
새 변경은 draft PR로 제시해 여러 파일 변경의 교차 검토를 받는다. PR 본문은 실제 trigger와
수정 후 동작, 실제 검증, 남은 실기기/스토어 범위를 기록한다. body-file을 사용하고
성공한 PR URL을 `attach_artifact`로 이 채팅에 연결한다.

- [ ] Step 9: 신규 candidate의 signed asset/checksum/source SHA/notes로 draft GitHub
Release를 준비한다. CI는 PR의 현재 head SHA에서 완료됐는지 조회하고 unknown/running을
성공으로 보지 않는다. 사용자가 검토할 수 있게 PR과 draft release, 서명/업데이트 검증을
제시한다. 공개 게시 전에는 주어진 AGENTS.md의 비가역 행동 확인 지침에 따라 구체적인
산출물로 확인받는다. 기존 v0.9.1 asset을 덮어쓰지 않는다.

- [ ] Step 10: 게시를 승인받으면 검토한 revision을 main에 반영하고 선택한 release를
공개한다. 실제 GitHub release API에서 draft=false, 태그 SHA, 새 asset digests를
읽어 검증한다. 원격 main/tag/CI/실제 게시와 검증한 제품 소스 관계를 증적에 남긴다.
Google Play/스토어 게시나 물리 기기 테스트를 실행하지 않았으면 완료로 기록하지 않는다.

## 후속 범위와 전체 목표

2026-10-14 실제 iOS 파일 왕복과 location/notification smoke는 통과했다.
Android CUA 접근이 없어 대체 UI 자동화에 필요한 명시 요청을 기다린다.
기존 APK 설치는 끝났으나 산책 생성/업데이트와 Android 파일 왕복은 미완료다.
실제 지도에 API 키 안내만 표시되는 M-19/MR-17을 추가로 확인해 공개 게시를
차단했다. [지도 복구 설계 초안](../specs/2026-10-14-basemap-service-restoration-design.md)은
별도 검토 전이며 승인된 MR-01~07에 몰래 포함하지 않는다.

사용자가 선택한 지속 고속+GPS 품질 기반 자동 제외를 다음 측정 설계의 제품 기준으로
사용한다. 새 거리 reducer, 작은 변위/정지 노이즈, 병합 속도 분모, 시간 보존, 부분 제외와
계산 버전/백업 호환은 MR-08~11/MR-15의 별도 spec→plan→implementation으로 진행한다.
MR-14 날짜/접근성과 MR-12 스토어 privacy 진입도 해당 흐름에서 설계한다.

이 1차 계획 완료만으로 전체 goal을 complete로 표시하지 않는다. 물리 기기 필요 항목은
기기 상태와 실행 가능성을 그때 확인하고 실제 없는 증거를 만들지 않는다.

## 검토 상태

- [x] 1차 설계 사용자 승인, 자동 제외 후속 방향 선택 기록
- [x] 독립 계획 두 개와 통합/릴리즈 계획 작성
- [x] 사용자가 작성된 계획을 검토, 실행 승인 2026-10-14
- [x] 이 세션에서 직접 구현하는 기존 실행 방식으로 진행
- [ ] 새 회귀/native/실제 파일 왕복/전체 gate/업데이트 검증
- [ ] PR 교차 검토와 구체적인 공개 배포 확인
