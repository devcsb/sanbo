# 산보 0.9.2 1차 유지보수 릴리즈 증적

| 항목 | 상태 |
|---|---|
| 후보 | `0.9.2+16` |
| 기본 코드 | 공개된 `v0.9.1` / `1368d45` |
| 대상 | Android 우선, minSdk 26, targetSdk 36 |
| 공개 게시 | 미실행, 후보 준비 중 |
| Google Play | 게시 여부 미확인, 신규 게시 미실행 |
| 태그, build SHA, CI | 최종 검증 후 기록 |
| 기존 설치 업데이트 | 미실행 |
| 실제 시스템 파일 왕복 | 검증 대기, 단위 테스트와 구분 |

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
- 현재 revision의 전체 Flutter/analyzer/debug/release/native 통합 gate는 아직 미실행.

각 묶음에 겹치는 기존 테스트가 있어 개수를 합산하지 않습니다. 과거 439개 baseline
통과를 새 코드 전체 검증으로 재사용하지 않습니다.

## 준비할 산출물

| 파일 | 상태 |
|---|---|
| `app-release.aab` | 신규 후보 빌드 전 |
| `app-arm64-v8a-release.apk` | 신규 후보 빌드 전 |
| `app-armeabi-v7a-release.apk` | 신규 후보 빌드 전 |
| `app-x86_64-release.apk` | 신규 후보 빌드 전 |
| `SHA256SUMS_v0.9.2.txt` | 신규 후보 빌드 전, SHA-256 기록 예정 |

기존 인증서 SHA-256은
`ceb40402d706589acee5da5df5a010c3dd5c2e9329cd3218961dfce56a6d38ac`입니다.
새 APK와 AAB의 실제 인증서, manifest, 버전과 hash를 빌드 후 조회합니다.
ABI별 versionCode는 기본 16과 다르므로 같은 ABI의 v0.9.1보다 증가했는지 비교합니다.

게시 전 실제 시스템 picker 왕복, 취소/오류/재생성, 기존 설치 데이터 보존, PR 교차
검토와 최종 CI를 확인합니다. 미검증 항목을 완료로 바꾸지 않습니다.
