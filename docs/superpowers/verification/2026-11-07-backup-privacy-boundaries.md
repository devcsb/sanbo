# 백업 입력과 개인정보 반출 개선 검증

2026-11-07, `codex/walk-summary-interaction`에서 승인한
[설계](../specs/2026-10-25-import-and-privacy-boundaries-design.md)와
[계획](../plans/2026-11-07-backup-privacy-boundaries.md)을 구현했다.
상태는 **승인 범위 구현과 검증 완료**다. 공개 배포는 이번 범위에 포함하지 않았다.

사용자 지침에 따라 직접 구현하고 코드, 요구사항, 합성 입력과 실제 Android 실행 결과를
대조했다. 별도 독립 보안 업체나 새 모델의 감사, 공개 release APK의 신규 REA 침투
시험을 수행한 것으로 표현하지 않는다. 사용자 DB, 운영 키와 공개 릴리즈는 변경하지 않았다.

## 수정한 문제

| 문제 | 적용한 동작 |
|---|---|
| 크기 metadata로 먼저 할당하는 Android picker | Android 가져오기를 전용 native 경로로 분리하고 실제 읽은 양을 50MiB로 제한 |
| 오래 걸리거나 취소한 읽기 | worker 복사, 30초 제한, CancellationSignal과 descriptor 닫기, 화면 종료 시 읽기 취소 |
| 중단한 사본과 늦은 결과 | UUID 소유권, canonical cache 경로 검사, finally release, 다음 시작에 버려진 사본 회수 |
| Activity 사이 중복 작업 | 이전 제공자가 닫히기 전에는 새 Activity도 가져오기를 시작하지 못하도록 프로세스 전체 lease 검사 |
| 큰 정수, 실수와 비현실적인 기간 | 변환 전 수치 상한, 실제 기간과 시간 지표의 관계, 7일과 최대 10,081분 객체 제한 |
| 집계 overflow가 기록 목록도 가림 | 통계 실패를 목록에서 분리하고 재시도 안내. 손상된 기록의 상세, 원본 생성과 삭제 유지 |
| 원본과 메모의 클립보드 반출 | 원본은 안내 후 NDJSON 파일 저장. 요약 복사는 시각과 지표만 포함 |
| 보관 안내와 실제 동작 불일치 | 비암호화 파일, OS 백업과 실패 기록 보관을 설명. 자동 삭제나 숨은 마이그레이션 없음 |

기존 native 반출의 요청 코드 할당을 재사용했다. 제공자 파일명은 표시 용도로만
사용하며 경로를 만들지 않는다. Dart도 실제 stream byte 수를 제한하고 종료 시
stream을 닫는다. 이전 작업과 ID가 다른 취소/해제 요청은 다른 작업을 정리하지 않는다.

입력 숫자의 상한은 보행 정확도 판정이 아니다. 기존 nullable 필드, v1/v2 복원,
시간대, 중복 ID 건너뛰기, 사용자 라벨, 제외 취소와 원본 GPS를 유지한다.
기존 과도하게 긴 기록은 재계산을 거부하되 읽기와 원본 반출 경로를 남긴다.

## 요구사항과 증거

| 승인 요구 | 검증 |
|---|---|
| 50MiB, 크기 누락과 거짓 크기 | `backup_import_limits_test.dart`, native `BackupImportContractTest`, 실제 DocumentsProvider의 unknown/huge/maximum |
| 취소, I/O 실패와 시간 제한 | stream 종료 검사, 실제 slow 사용자 취소/30초 오류, reliable pipe의 failed 오류 |
| 화면 종료, Activity 재생성과 프로세스 중단 | `backup_navigation_test.dart`, `LifecycleProbe`, 강제 종료 후 cache 회수 |
| 한 작업만 허용, 늦은 결과와 경로 이탈 | busy/late UUID 테스트, 외부 경로와 symlink 거부, blocked provider 재생성 반례 |
| 7일, 변환 전 수치 검사와 1초 반올림 허용 | `backup_input_limits_test.dart`: 정확한 경계, +1µs, 큰 정수/실수, 시간 관계와 천 년 재계산 거부 |
| 기존 다섯 테이블 보존 | 샘플, 분 기록, 장소, 제외와 세션을 채운 뒤 잘못된 수치 6종을 거부하고 전체 백업 내용을 비교 |
| 정상 복원과 사용자 수정 유지 | `walk_backup_test.dart`, `exclusion_boundary_integration_test.dart`, 기존 전체 회귀 |
| 집계 실패에도 접근 유지 | 실제 SQLite 정수 overflow와 실수 합계 Infinity에서 목록, 상세, 원본 생성, 개별 삭제 확인 |
| 원본 저장 완료/취소/실패와 clipboard 미사용 | `session_export_privacy_test.dart`, 기존 native export 검사 |
| 요약에서 메모/장소/좌표 제외 | `walk_stats_export_test.dart`와 privacy 테스트. 원본 파일에는 해당 자료를 보존 |
| 작은 화면, 큰 글자, 다크와 동작 줄이기 | 320px/200% 읽기/오류/취소/재시도 위젯, 렌더링 이미지와 dialog transitionDuration=0 검사 |
| 보관 문구 | 실패 원본 DB 보존을 확인하는 기존 세션 흐름 테스트와 설정/메모 안내 |

경계 테스트는 실제 제품 결함이 먼저 실패하는 것을 확인한 뒤 수정했다. 이미 존재하는
방어의 테스트는 성공하는 회귀로 추가했다. 특히 화면 종료 취소는 `expected 1, actual 0`,
가져오기 완료 후 화면 이탈은 과거 구현을 되돌린 mutation에서 기록 갱신 0을 재현했다.
동작 줄이기 확인창은 0ms 기대에 기본 150ms가 남는 것을 확인했다.

## Android 실행

기존 합성 QA AVD를 `-read-only -no-snapshot -no-window` overlay로 실행했다.
일반 사용자 기기나 원본 AVD의 저장 자료를 초기화하지 않았다. 제품 APK와 분리한
[QA 제공자와 재생성 도구](../../../test/fixtures/android_backup_provider/README.md)를
설치했으며 이 제공자는 제품 manifest나 APK에 포함되지 않는다.

| 입력/상황 | 관찰 결과 |
|---|---|
| unknown, size null | 확인창에 1개, 확정 후 ‘산책 1개를 가져왔어요’ |
| huge, 표시 1바이트/실제 50MiB+1 | 실제 byte 상한 오류, 임시 사본 0개 |
| maximum, 정확히 50MiB | 확인창과 정상 가져오기, 임시 사본 정리 |
| slow, 초당 공백 전송 | 사용자 취소 후 관리 화면 복귀와 사본 0개. 별도 실행은 30초 제한 안내 |
| failed, reliable pipe 오류 | 가져오기 실패와 재시도 안내, 사본 0개 |
| slow 읽기 중 force-stop | 종료 전에 사본 존재, 재시작 후 사본 0개 |
| slow 읽기 중 실제 Activity.recreate | 생성 2회(초기와 재생성), 종료 1회, 사본 0개, PASS |
| blocked metadata와 재생성 | 수정 전 새 작업 수락으로 FAIL. 수정 후 import_busy, 사본 0개와 PASS |

최대 크기 확인창 직후 debug 에뮬레이터에서 `dumpsys meminfo`의 TOTAL PSS는
411,394KiB였다. 이 값은 한 시점의 관측이며 최고치나 release/물리 기기의 수치가
아니다. 파일이 50MiB여도 파싱 후 메모리는 더 크다. 검증된 byte를 다시 UTF-8로
인코딩하던 중복 할당은 제거했지만 저메모리 기기 전체에서의 안정성을 보장하지 않는다.

Activity 검사는 기본 debug 인증서로 서명한 QA 도구를 사용한다. 일반 QA 인증서로는
Android가 대상 앱 instrumentation을 거부했다. 대기하던 picker가 남은 첫 harness도
제거하고 작업 스택을 명시적으로 초기화한 도구로 검증했다. 환경 설정값만 바꾼 시도를
실제 Activity 재생성 증거로 계산하지 않았다. 생산 앱에는 테스트 진입점을 추가하지 않았다.

## 화면과 상호작용

기존 테마와 Material 아이콘, 짧은 기본 확인창 전환을 유지했다. 동작 줄이기에서는
세 가지 백업/원본 확인창 전환을 없앴다. 새 bitmap 에셋이나 애니메이션 SDK는 필요하지 않았다.

원본 파일 안내의 기본 바깥 여백을 줄이고 내용을 스크롤할 수 있게 해 320px/200%에서도
확인과 취소 버튼에 접근할 수 있다. 파일 읽는 중에만 취소를 제공하고, 저장 확정 뒤에는
기록 transaction을 끝내며 화면을 떠나도 기록 목록을 갱신한다. 오류는 사라지는 toast에만
의존하지 않고 재시도와 원본 보존 안내를 남긴다. 화면 읽기용 상태 안내도 유지한다.

합성 자료로 `backup-disclosure-large.png`, `backup-disclosure-dark.png`,
`backup-settings-reading-*.png`, `backup-settings-error-*.png`를 `build/`에 렌더링했다.
과도한 자동 스크롤이 필요하다는 가설은 회귀에서 재현되지 않아 제품에 추가하지 않았다.

## 최종 검증 기록

최종 작업 소유권 수정과 보존 회귀 추가 후 다음 명령을 실행했다. 실행 중 소스 변경
없이 종료 코드 0, 전체 테스트 완료와 새 APK 생성, `[quality] PASS`를 직접 확인했다.

```sh
env -u CARTO_BASEMAP_KEY bash scripts/run_quality_loop.sh --debug-apk
android/gradlew -p android app:testDebugUnitTest app:assembleDebug
```

| 검사 | 결과 |
|---|---|
| PRD/TRD 구조 | PASS |
| Python 빌드/반출 도구 | 21개 통과 |
| Dart 정적 분석 | No issues found |
| Flutter 전체 회귀 | 636개 통과, 1분 50초 |
| Android native | 21개, 실패/오류/skip 0 |
| Android debug APK | assembleDebug 14.1초, APK 생성 |
| 큰 글자/다크 합성 화면 렌더 | 4개 통과, 이미지 직접 확인 |
| Activity 재생성 | 생성 2회, 종료 1회, cacheFiles=0, PASS |
| 취소 무응답 provider와 재생성 | RED: overlap=import_interrupted / FAIL; GREEN: import_busy / PASS |
| 공백과 실행 중 소스 일관성 | PASS |

전체 로그는 `build/backup-privacy-quality-complete.log`, native 로그는
`build/backup-native-global-lease.log`다. 재생성 결과는
`build/backup-activity-recreation-candidate.log`와 `build/backup-overlap-{red,green}.log`,
반출/레이아웃/원자성 결과는 각각 `backup-final-focused.log`, `backup-settings-layout.log`,
`backup-atomicity-final.log`다. 이미지 실행 로그는 `backup-privacy-visual-final.log`다.
로그와 산출물은 로컬 `build/` 자료이며 Git에 개인 경로나 키를 포함한 파일을 넣지 않았다.

최종 APK는 `build/app/outputs/flutter-apk/app-debug.apk`다. CARTO 키를 전달하지 않은
로컬 debug 검증용이며 release/지도 인증 증거가 아니다. SHA-256은
`90dec1ac64dfeb6e3cf02cf96a581430ba31e49a8ec24e6bef2df73e12dbe720`이다.
QA 에뮬레이터는 snapshot을 저장하지 않고 종료해 원래 AVD와 운영 환경을 보존했다.
문서 완료 상태 갱신 뒤에는 문서 구조와 공백만 다시 검사하며 제품 게이트를 반복하지 않는다.

## 남은 범위

- CARTO 클라이언트 키의 APK 추출/외부 재사용 가능성과 상업용 조건은 이 수정으로
  해결되지 않는다. 키, 계정이나 요금제를 변경하지 않았다.
- GPS 흔들림의 거리 누적, 물리 기기 배터리와 측정 비교는 별도 측정 설계의 후속이다.
- iOS 시스템 picker의 선행 copy, OS 백업 제외 정책과 실제 기기 반출은 iOS 공개 전
  검증이 필요하다. 이번에 iOS native 동작을 제한했다고 주장하지 않는다.
- `.sanbo`와 `.ndjson`은 암호화하지 않는다. 유효한 수치로 조작한 백업의 진위를
  인증하는 기능도 아니다. 실패한 원본의 선택 삭제와 보관 기간은 별도 결정으로 남는다.
- 플랫폼 제공자가 취소 신호에 응답하지 않으면 정리가 지연될 수 있다. 화면의 제한
  응답과 실제 취소/닫기를 보내며, 기존 작업이 닫히기 전에는 추가 읽기를 허용하지 않는다.
- 물리 기기 전체, OS 화면 읽기 도구와 새 공개 APK 침투 시험을 대신하는 결과가 아니다.
  이번 작업에서는 새 패키지, 런타임 권한, 서버와 release 배포를 추가하지 않았다.
