# 산보 반복 품질 검토 루브릭

검토 방식: 독립적인 비판 검토자가 매 변경 묶음마다 같은 질문과 증거 게이트를 반복한다.

## 운영 루프

1. **범위 고정** — 이번 루프의 사용자 가치, 위험도(P0/P1/P2), 변경하지 않을 영역을 한 문장으로 적는다.
2. **증거 수집** — 코드 의도보다 실제 테스트·정적 분석·빌드·상태 전이를 우선한다.
3. **비판 판정** — 각 축을 `충족 / 부분 충족 / 미충족 / 증거 부족`으로 판정하고, 증거 부족은 충족으로 세지 않는다.
4. **최고 레버리지 수정** — 데이터 유실·잘못된 기록·배터리·막힘 UX 순으로 한두 개만 수정한다.
5. **회귀 고정** — 발견한 결함을 실패하는 테스트로 먼저 재현하고, 수정 후 해당 테스트와 전체 모음을 실행한다.
6. **릴리스 게이트** — 분석·테스트·APK·작업 트리 상태를 확인하고 남은 위험을 다음 루프 backlog로 기록한다.

## 판정 축

| 축 | 핵심 질문 | 최소 증거 | 실패 예 |
|---|---|---|---|
| 데이터 내구성 | 종료·복구·가져오기 중 기록이 유실·중복·오염되지 않는가? | transaction/queue 코드 + 경합·rollback·migration 테스트 | 늦은 callback, 부분 import |
| 기록 정확도 | GPS 점프·저품질·시간 역행이 거리/활동 추측을 부풀리지 않는가? | 필터·윈도우·rollup 테스트 + 원본 보존 확인 | 허위 거리, gap 보간 |
| 배터리/플랫폼 | 모드별 수집 주기와 백그라운드 동작이 의도와 일치하는가? | 요청 프로파일 테스트 + 실기기 측정 계획 | 불필요한 UI rebuild, 권한 순서 오류 |
| 상태/동시성 | 시작·종료·자동 종료·복구가 중복 실행과 stale 상태를 막는가? | state transition/late callback 테스트 | 이중 저장, busy 해제 누락 |
| 사용성/a11y | loading/error/empty/busy/destructive 상태에서 다음 행동이 보이는가? | 위젯·카피·Semantics 테스트 | 설정 경로 없음, 기술 용어 노출 |
| 성능/확장성 | 기록 수와 세션 길이가 늘어도 UI·DB 작업이 선형적으로 감당 가능한가? | 장기 세션 fixture/쿼리·스크롤 프로파일 | 전체 기록 매번 로드, O(n²) 재계산 |
| 배포/보안 | 업데이트 보존, 서명, 백업 민감도와 실패 경로가 안전한가? | manifest/signing/build/backup 검증 | 새 키로 업데이트 불가, 평문 백업 오해 |

## 필수 게이트

```text
G1 flutter analyze                         0 issues
G2 flutter test --concurrency=1            all passed
G3 debug APK                              build succeeds
G4 release APK (release key available)    build succeeds
G5 git diff --check + generated-file audit clean
G6 every P0/P1 finding has a test, fix, or explicit next-loop owner
G7 python3 scripts/verify_prd_trd.py        PRD/TRD structural verification passes
G8 release arm64 APK manifest               location/FGS/notification/WakeLock + service type
```

반복 실행 명령:

```bash
bash scripts/run_quality_loop.sh             # 구조·analyze·전체 테스트
bash scripts/run_quality_loop.sh --debug-apk
bash scripts/run_quality_loop.sh --release-apk
scripts/run_native_platform_tests.sh        # Android native unit + iOS simulator XCTest
```

APK 옵션은 로컬 release signing 설정과 빌드 시간을 전제로 한다. Flutter 명령이 생성하는
iOS 보조 파일은 커밋 전에 저장소 정책에 맞게 정리한다.

## 루프 기록 양식

```text
Loop: YYYY-MM-DD / short name
Scope:
Findings: [P0/P1/P2 + axis]
Evidence: commands, tests, runtime observations
Changes:
Regression tests:
Gates: G1 … G6
Remaining risks / next loop:
```

현재 루프의 실기기 증거 수집은 [`docs/DEVICE_VALIDATION.md`](DEVICE_VALIDATION.md)의 고정 조건과 매트릭스를 사용한다. 장기 기록 확장성은 페이지·aggregate 테스트로 보완했지만,
실제 수천 건 스크롤과 배터리/백그라운드 동작은 코드 테스트만으로 완료 판정하지 않는다.

`run_native_platform_tests.sh`는 native channel 계약과 권한·알림 보조 코드를 Android
unit test와 iOS simulator XCTest로 확인한다. 실제 GPS provider, 제조사 절전 정책,
시스템 알림 전달은 검증하지 않으므로 이 스크립트의 성공만으로 실기기 매트릭스를
통과 처리하지 않는다.
