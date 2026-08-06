# 산보 0.7 비판적 품질 검토

검토일: 2026-08-06

## 결론

이번 검토에서 데이터 유실·배포 사고 가능성이 큰 항목을 우선 수정했다. 핵심은
전체 백업/복원, 원자적 DB 처리, 백그라운드 표현 계층 절전, iOS 위치 설정,
릴리스 서명 분리와 기존 설치의 업데이트 호환성 확보다. 기존 산책·복구·지도·장소·자동 종료 흐름은 전체 회귀
테스트로 재검증했다.

반복 판정 기준과 증거 게이트는 [`docs/QUALITY_RUBRIC.md`](QUALITY_RUBRIC.md)에 고정한다.

## 발견 사항과 조치

| 우선순위 | 발견 | 조치 |
|---|---|---|
| P0 | 릴리스 키가 빌드 스크립트에 고정되면 키 노출·오서명 위험이 있고, 새 키로 즉시 교체하면 기존 v0.3.2 설치를 업데이트할 수 없음 | 키 설정을 git 밖 `key.properties`로 분리하고, v0.7은 기존 배포본과 동일한 인증서로 서명해 업데이트 호환성을 유지함. 새 업로드 키 전환은 별도 마이그레이션 과제로 관리 |
| P0 | 세션별 클립보드 내보내기만 있고 기기 변경·앱 삭제 후 전체 복원 경로 없음 | 완료 산책·원본 GPS·윈도우·사용자 수정·메모·장소를 담는 `.sanbo` 백업과 병합 가져오기 추가 |
| P1 | 백업 입력이 손상되면 일부 행만 들어갈 위험 | 파일/행/좌표/범위/FK/버전 검증 후 단일 SQLite transaction으로 반영, 오류 시 전체 rollback |
| P1 | 백그라운드에서도 GPS 샘플마다 Riverpod/UI 상태를 발행하고 1초 타이머가 유지됨 | 네이티브 위치 수집은 유지하되 화면 상태 발행·1초 타이머는 중단, 복귀 시 누적값 1회 동기화 |
| P1 | 저장 체크포인트와 안전 종료 타이머가 분리돼 중복 wake-up 발생 | 30초 유지보수 경로로 통합하고 모드별 약 30초 샘플 묶음도 보조 트리거로 사용 |
| P0 | 체크포인트 쓰기 중 종료·버리기가 실행되면 늦은 SQLite callback이 최종화·삭제 뒤 샘플을 재삽입할 수 있음 | 직렬 maintenance queue와 세션 generation fence를 추가하고 종료 전에 현재 쓰기를 기다리도록 수정; 경합 회귀 테스트 추가 |
| P1 | 최초 Android 시작에서 알림 권한이 위치 권한보다 먼저 요청되고, seed 요청이 현재 추적 모드와 무관한 공통 설정을 사용함 | 위치 권한 승인 뒤 알림 권한을 best-effort로 요청하고, seed/fallback을 절전·균형·정밀 프로파일에 맞춤 |
| P1 | 저장소 오류가 발생하면 진행 중 기록 복구가 조용히 실패해 사용자가 기록 유실로 오해할 수 있음 | 복구 실패를 사용자용 오류·상태 문구로 노출하고 회귀 테스트 추가 |
| P1 | 기록이 많아질수록 History와 산책 종료 milestone 계산이 모든 세션을 읽고 Dart에서 통계를 매번 재계산함 | 초기 50개 페이지 + ‘더 많은 기록 보기’, 누적 통계 SQLite 집계, 종료 milestone도 aggregate 사용, bounded query 회귀 테스트 |
| P1 | 복구 조회 오류의 배너 재시도가 새 산책 시작으로 연결될 수 있음 | `canRetryRecovery`와 `retryRecovery()`로 복구 재시도·busy·신규 시작을 분리하고 source/UI 회귀 테스트 추가 |
| P2 | 앱이 `inactive`가 된 짧은 생명주기 구간에도 화면 ticker가 잠시 유지될 수 있음 | `AppLifecycleListener.onInactive`에서도 presentation 절전을 시작하고 lifecycle 회귀 테스트 추가 |
| P2 | 상세 진입 시 세션·샘플·윈도우를 순차 조회해 첫 화면 지연이 누적될 수 있음 | 세션 확인 뒤 샘플·윈도우 독립 쿼리를 `Future.wait`로 병렬 실행하고 구조·위젯 테스트 재검증 |
| P1 | PRD/TRD 구조 검증기가 의도적으로 제거된 역사적 이미지 파일을 필수로 요구해 항상 실패함 | 이미지 파일명 traceability는 유지하고 바이너리 존재 검사는 제거; G7 게이트 재통과 |
| P1 | 완료 기록의 상태·시각 정렬 조회에 복합 인덱스가 없어 장기 기록에서 전체 스캔·정렬 비용이 커질 수 있음 | schema v3 `idx_sessions_status_started_at` 추가, v1→v3 마이그레이션 보존 및 `EXPLAIN QUERY PLAN` 사용 확인 |
| P1 | iOS 설명 문자열은 있으나 background location capability/settings가 불완전 | `UIBackgroundModes=location`, fitness용 `AppleSettings`, 위치 사용 표시 추가 |
| P1 | DB 열기 시 FK/무결성 확인과 업데이트 보존 검증이 약함 | FK 활성화, `quick_check`, 증가형 v1→v2 마이그레이션 및 기존 행 보존 테스트 추가 |
| P1 | 최초 선택한 `file_picker 11.0.3`이 AGP 9에서 Android 빌드를 차단 | AGP 9 내장 Kotlin을 지원하는 Flutter 공식 `file_selector` 구현으로 교체 |
| P2 | 설정에서 백업의 민감도·병합 동작을 알기 어려움 | 내보내기 전 정밀 GPS 포함 경고, 가져오기 전 파일명·산책 수·중복 건너뛰기 안내 추가 |

## 배터리 관점

- 절전/균형/정밀 목표 주기는 각각 20초/8초/4초이며 거리 필터는 10m/5m/2m다.
- CPU WakeLock은 정밀 모드에서만 켠다.
- 백그라운드에서는 화면 rebuild와 1초 경과 타이머를 중단한다.
- 첫 위치 seed와 fallback도 선택한 모드의 정확도·주기·거리 필터를 사용한다.
- SQLite 체크포인트는 30초 타이머와 샘플 묶음 중 먼저 도달한 조건으로 수행한다.
- 20분 정지 경고, 30분 정지 종료, 2시간 45분 경고, 3시간 종료는 유지한다.

실제 배터리 퍼센트는 기기·신호·화면 상태에 크게 좌우되므로 코드만으로 수치를
확정하지 않았다. Galaxy 실기기에서 각 모드 60분, 동일 경로, 화면 꺼짐 조건의
전후 배터리와 Android Battery Historian을 비교하는 검증이 남아 있다.

## 데이터 보존·백업 규칙

- 일반 앱 업데이트는 동일 application ID의 앱 샌드박스 DB를 유지한다.
- Android OS 자동 클라우드/기기 이전 백업은 정밀 위치 보호를 위해 계속 끈다.
- 앱 삭제나 기기 변경 전 사용자가 전체 백업 파일을 별도 보관해야 한다.
- 진행 중 산책은 복제된 active 세션을 만들지 않도록 전체 백업에서 제외한다.
- 가져오기는 기존 기록을 지우지 않으며 같은 세션 ID를 건너뛴다.
- 백업은 암호화되지 않은 JSON이므로 신뢰할 수 있는 저장소에만 둬야 한다.
- 현재 안전 상한은 파일 50MB, 테이블당 50만 행이다.

## 검증 결과

- `flutter analyze`: 문제 없음
- `flutter test --concurrency=1`: 123개 통과
- Android release split APK: `0.7.0+10` 빌드 성공
- Android release: 3개 ABI APK의 인증서가 기존 v0.3.2 배포본과 동일함을 확인
- APK SHA-256: arm64 `9b981c…6322`, armeabi-v7a `39d071…e0c4`, x86_64 `4b88d6…214c`
- iOS Simulator debug: Xcode/CocoaPods 빌드 성공
- DB: v1→v2 마이그레이션에서 기존 행 보존 확인
- DB: v1→v3 마이그레이션에서 기존 행·세션 조회 인덱스 보존 확인
- 백업: 전체 왕복, 중복 가져오기, 손상 좌표 rollback, 미래 DB 버전 거부 확인
- 추가 회귀: maintenance 직렬화·종료 경합·discard fence·추적 모드 요청 프로파일 확인
- 1차 루프: 저장소 오류 복구 실패의 오류 노출 및 회귀 확인 (121개 테스트)
- 2차 루프 보강: 종료 후 milestone 계산도 SQLite aggregate 경로로 전환
- 루브릭 게이트: `python3 scripts/verify_prd_trd.py` 통과 (역사적 레퍼런스 이미지는 바이너리 없이 문서 파일명만 추적)
- 자동 루프 옵션: `bash scripts/run_quality_loop.sh --release-apk` 통과 (3 ABI APK)
- release arm64 APK manifest: 위치·FGS location·알림·WakeLock 권한과 `GeolocatorLocationService` 확인
- 자동 G8 manifest 게이트: release arm64 APK 권한·서비스·location FGS 타입 확인
- 비정상 GPS 좌표(NaN·범위 초과) 샘플은 경로 앵커가 되지 않도록 필터 경계 검증 추가
- 동일 시각 완료 기록의 history offset 페이지가 ID tie-breaker로 중복·누락되지 않도록 보강

## 남은 위험

1. 백업 자체 암호화와 앱 잠금은 아직 없다.
2. 50MB를 넘는 장기 사용자용 스트리밍 백업은 후속 구현이 필요하다.
3. Android 제조사별 절전 정책과 iOS 잠금 화면의 장시간 수집은 실기기 검증이 필요하다.
4. OS 파일 선택기의 저장/가져오기 UX는 Android·iPhone 실기기에서 최종 확인해야 한다.
5. iOS background location은 App Store 제출 사유와 권한 교육 문구를 별도 심사해야 한다.
6. 페이지 크기와 SQLite 집계는 코드·DB 테스트로 검증했지만, 실제 수천 건 스크롤 체감은 실기기에서 추가 측정해야 한다.
7. 실기기 배터리·백그라운드 검증 절차는 [`docs/DEVICE_VALIDATION.md`](DEVICE_VALIDATION.md)로 고정했지만, 아직 측정 결과는 없다.
