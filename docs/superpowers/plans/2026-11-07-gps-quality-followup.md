# GPS 신뢰도와 계산 비용 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. 기존 격리 worktree에서 직접 구현하며 재위임하지 않는다.

**Goal:** 원본을 보존하면서 GPS 흔들림 확인을 돕고 경로 분할의 반복 검사를 줄인다.

**Architecture:** 순수 Dart 감지 함수를 분 집계와 기존 evidence 저장에 연결한다. 경로 분할은 정렬된 두 커서를 사용한다. 기존 Flutter UI와 저장 계약을 유지한다.

**Tech Stack:** Flutter, Dart, SQLite, 기존 테스트 도구. 새 런타임 의존성 없음.

**Spec:** `docs/superpowers/specs/2026-11-07-gps-quality-followup-design.md`.

## Global Constraints

- 수치/원본/사용자 라벨/제외/기존 기간 정책은 유지한다. 자동 일괄 재계산 없음.
- 최소 5개/30초, 이웃 간격 최대 30초, 정확도 (0,150]m, 의미 있는 이동 1.5m,
  합계 10m, 직선/누적 비율 25%, 120도 반전 2회, provider 양수 속도 0.5m/s 미만.
- 추가 열, 백업 버전, SDK, 권한, 키/계정/요금제/배포 변경 없음.
- 물리 GPS/배터리 결과는 S26 연결 뒤에만 보고한다.

## Review Focus

1. 실제 짧은 왕복과 노이즈의 입력이 같을 수 있다. 수치를 삭제하지 않고 안내한다.
2. 느린 직선과 원형 이동, sparse/NaN 데이터, 날짜 변경선을 과잉 판정하지 않는다.
3. 인접/부분 제외, 정확한 시작 좌표, 필터와 긴 공백을 새 커서가 연결하지 않는다.
4. 사용자 확정/제외 구간에 안내를 반복하거나 과거 DB를 읽으면서 쓰지 않는다.
5. 원본 evidence는 백업과 NDJSON에서 보존하며 화면에는 읽을 수 있는 문구를 쓴다.

## Task 1: 흔들림 진단과 저장 계약

Files: `lib/domain/services/gps_jitter_assessment.dart`(신규), `lib/domain/models/minute_window.dart`,
`window_aggregator.dart`, `activity_inferencer.dart`, 관련 domain/data tests.

- [x] 감지와 보존에 대한 RED를 작성하고 기존 흔들림 누적 수치를 재현한다.
- [x] 순수 감지, evidence, 낮은 확신의 추정과 사용자 수정 보존을 구현한다.
- [x] 정상 걷기/왕복/경계/백업/제외 취소를 검증한다.

## Task 2: 경로 분할의 계산 비용

Files: `route_partitioner.dart`, `test/helpers/legacy_route_partitioner.dart`(신규), 관련 tests.

- [x] 반복 호출 상한의 RED, 이전 구현과 비교하는 결정적/난수 입력을 작성한다.
- [x] 단조 전진 커서로 바꾸고 기존 모든 경계 결과를 비교한다.
- [x] 합성 부하의 전후 실행 시간을 기록하되 배터리 측정으로 표현하지 않는다.

## Task 3: 확인 안내와 운영 기록

Files: `session_detail_screen.dart`, `timeline_copy.dart`, 관련 widget tests, PRD/TRD,
`docs/testing/2026-11-07-s26-location-energy.md`(신규), CARTO 운영 문서와 검증 기록.

- [x] 미확정/확정/제외와 큰 글자/다크 안내를 RED로 검사한다.
- [x] 기존 패널과 구간 이동을 재사용하고 기계 코드를 노출하지 않는다.
- [x] S26 실측 절차, 공식 자료와 CARTO 잔여 경계를 갱신한다.
- [x] 관련 검사 뒤 전체 품질 게이트와 debug APK를 확인하고 커밋한다.

최종 큰 글자 캡처에서 지도 출처의 기존 잘림을 발견해 `route_map.dart`의 폭 제약과 줄바꿈, 회귀 검사를 작업 3에 포함했다. 결과는 [검증 기록](../verification/2026-11-07-gps-quality-followup.md)에 정리했다.
