# 1차 유지보수 구현과 검증 기록

제품 build SHA는 `c027b4195bbae2aa96766bc976f35b7f5ebca0cb`입니다. 이후 문서 commit과 binary build SHA를 구분합니다.
[통합 계획](../plans/2026-10-14-maintenance-stage1.md),
[릴리즈 증적](../../release/2026-10-14-maintenance-stage1-release.md)을 함께 봅니다.

| 검사 | 결과 |
|---|---|
| 전체 품질 loop `--all-apk` | PASS, Flutter 478개, analyzer, debug/release/AAB, manifest, cert, hash, clean-tree |
| 전체 native gate | PASS, Android JUnit 16개, iOS 26.5 XCTest 11개 |
| APK 버전/서명 | 세 ABI의 versionCode 각각 증가, 기존 인증서 일치 |
| AAB manifest/서명 | 0.9.2+16, SDK36, JAR 검증과 인증서 일치, bundletool validate exit0 |
| 기존 APK 보존 | 공개 v0.9.1 세 파일 SHA-256 일치, 별도 보존 |
| 실제 iOS picker 왕복 | UI 조작 불가, 12분 timeout. 미완료 |
| 실제 Android picker / 설치 업데이트 | 미실행 |
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
- 여러 파일 변경의 교차 검토, 실제 picker 왕복, 기존 설치 업데이트와 게시 확인이
  끝나기 전에는 이 계획과 전체 목표를 완료로 표시하지 않습니다.

## 로컬 실행 로그

검증 원본은 각 계획의 git-ignored `.superpowers/sdd/` workspace에 보관합니다.
`integration-quality.log`, `integration-native.log`, `release-artifacts.json`,
`native-summary.json`과 각 task의 RED/GREEN 로그를 남겼습니다.
GitHub 문서의 PASS만으로 재실행 증거를 대신하지 않습니다.
