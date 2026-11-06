# 백업 입력과 개인정보 반출 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** 조작된 백업의 자원 확대와 집계 실패를 막고, 원본 반출을 명확한 파일 저장 흐름으로 바꾼다.

**Architecture:** 기존 Flutter/Riverpod/SQLite와 native 파일 처리 통로를 확장한다. 외부 입력 경계와 완료 기록 재계산에 같은 자원 제한을 사용하고, 집계 실패를 목록에서 분리한다. UI는 기존 테마와 모션 토큰을 유지한다.

**Tech Stack:** Dart, Flutter, SQLite, Android Kotlin, 기존 iOS 파일 내보내기. 새 패키지/SDK 없음.

**Spec:** `docs/superpowers/specs/2026-10-25-import-and-privacy-boundaries-design.md`.

사용자는 후속 구현과 필요한 UX 개선을 승인했다. 기존 세션에서 직접 구현하며 계획 재승인을 기다리지 않는다. 에셋은 필요성에 따라 판단하며, 이번 파일 관리 흐름은 기존 아이콘과 컴포넌트로 표현한다.

## Global Constraints

- 파일 50MiB, 테이블당 행 500,000, 세션 범위 7일, 분 객체 최대 10,081개.
- 시간은 실제 관측 범위의 올림 초 이내이며 이동+정지는 1초 반올림 오차를 허용한다. nullable 과거 필드는 유지한다.
- 기타 저장 수치 절댓값 1e9, 샘플 수 500,000. 정수 변환 전에 범위를 검사한다.
- 원본/사용자 라벨/기존 DB는 몰래 수정하거나 삭제하지 않는다. import는 전체 transaction으로 처리한다.
- Android는 metadata 크기로 메모리를 사전 할당하지 않고, 실제 읽은 양과 30초 읽기 한도를 적용한다.
- 원본 NDJSON은 안내 후 파일 저장, 요약 복사는 메모/장소/원본/활동 상세를 제외한다.
- 기존 테마, 큰 글자, 48px 터치 영역과 reduce-motion을 유지한다. 키/계정/요금제/배포 변경 없음.

## Review Focus

1. 정확히 7일이거나 분 중간 시작인 과거 정상 자료는 허용하고 초과만 거부한다(작업 1).
2. 한 행은 유한하지만 전체 합계가 무한/overflow인 기존 DB도 목록 접근을 유지한다(작업 3).
3. 크기 없는 provider/거짓 metadata/읽기 중 실패/취소/재생성의 사본과 늦은 결과를 정리한다(작업 2).
4. 파일 선택/안내 취소 때 clipboard나 파일 저장이 일어나지 않고 실패를 성공으로 알리지 않는다(작업 4).
5. 작은 화면/큰 글자/백그라운드 복귀에서 읽기 중/완료/실패 상태와 재시도가 명확하다(작업 4).

## Task 1: 입력 수치와 계산량 경계

**Files:** `lib/domain/services/backup_limits.dart`(신규), `lib/data/walk_repository.dart`, `lib/domain/services/session_pipeline.dart`, `lib/domain/pipeline/window_aggregator.dart`, `test/data/walk_backup_test.dart`, `test/data/backup_input_limits_test.dart`(신규), `test/domain/session_pipeline_test.dart`.

**Interfaces:** `validateProcessingSpan(DateTime start, DateTime end)`는 올림 초를 반환하고 음수/7일 초과를 FormatException으로 거부한다. import 검증과 완료 재계산이 공유한다.

- [x] 큰 정수/유한한 큰 실수/천 년 범위/이동+정지 불일치, 7일과 부분 분 경계에 대한 RED 테스트를 작성한다.
- [x] 변환 전 상한, 시간 관계 검사, 재계산 전 범위 검사와 분 생성 상한을 구현한다. 제외 참조는 ID map을 쓰고 분×제외 스캔을 피한다.
- [x] 정상 v1/v2, 중복 ID, 시간대, 제외 취소 회귀를 실행하고 커밋한다.

## Task 2: 제한된 파일 읽기

**Files:** `lib/platform/backup/backup_file_service.dart`, `android/app/src/main/kotlin/com/sanbo/sanbo/BackupImportHandler.kt`(신규), `MainActivity.kt`, Android native tests, `test/platform/backup_file_service_test.dart`.

**Interfaces:** Android `sanbo/backup_import` 채널의 `pick`은 소유 cache 경로/이름/작업 ID를 반환한다. `release`/`cancel`은 해당 작업만 정리한다. Dart는 제한된 stream으로 읽고 finally에서 release한다. iOS/desktop도 `openRead`로 제한한다.

- [x] null/거짓 크기, 한도+1, I/O 실패, timeout/취소/Activity 종료와 늦은 결과 테스트를 추가하고 실제 결함의 RED를 확인한다.
- [x] 시스템 문서 picker, 단일 읽기 작업, worker에서 제한된 복사, native 취소/descriptor 닫기, 작업별 cache 정리와 stale 회수를 구현한다.
- [x] Dart/native 관련 테스트와 Android debug 컴파일을 확인하고 커밋한다.

## Task 3: 통계 실패와 기록 목록 분리

**Files:** `lib/features/history/history_providers.dart`, `history_screen.dart`, `test/features/history_stats_failure_test.dart`(신규).

**Interfaces:** `HistorySnapshot.stats`는 nullable이며 실패 때 목록/페이지 이동은 정상 반환한다. 통계 실패를 0으로 표시하지 않고 별도 재시도 안내를 제공한다.

- [x] 오염된 합계와 정상 목록을 실제 SQLite/위젯으로 재현한다.
- [x] 유한성 검사와 집계 실패 격리, 이상한 개별 값의 안전한 표시를 구현한다.
- [x] 정상 빈 기록/페이지 추가/상세 접근 회귀 후 커밋한다.

## Task 4: 개인정보 반출과 복구 UX

**Files:** `lib/domain/services/session_export.dart`, `lib/features/session_detail/session_detail_screen.dart`, `lib/features/settings/settings_screen.dart`, `lib/features/home/session_controller.dart`, 파일 저장 서비스와 영향 테스트.

**Interfaces:** 원본 저장은 기존 `BackupFileService.save(fileName:,bytes:)`를 재사용하며 확장자별 desktop 필터를 쓴다. 단일 세션 파일은 전체 복원용이 아님을 설명한다.

- [x] 원본 저장 취소/완료/실패, clipboard 미사용, 요약 개인정보 제외를 RED로 확인한다.
- [x] 정밀 위치/메모/암호화 여부 안내, 중복 작업 방지, 작은 화면에서 스크롤 가능한 확인창과 진행 피드백을 구현한다.
- [x] OS 백업/실패 기록 보관 문구를 실제 동작에 맞추고, 기존 모션으로 상태 전환을 유지한다.
- [x] 320px/200%/다크/reduce-motion과 기존 메모/내보내기/구간 편집 회귀를 검증하고 커밋한다.

## Task 5: 통합 검증과 완료 감사

**Files:** 승인 설계 상태, `docs/superpowers/verification/2026-11-07-backup-privacy-boundaries.md`(신규), 관련 PRD/TRD 링크.

- [x] 원본 보존과 정상 복원, native 경계와 UI 상태를 교차 검토하고 발견한 실제 반례를 해결한다.
- [x] `bash scripts/run_quality_loop.sh --debug-apk` 및 변경 범위의 native 검사를 실행한다. 완료 문구/산출물을 직접 확인한다.
- [x] 합성 자료로 화면을 렌더링해 확인하고 필요한 디테일을 수정한다. 실제 기기 최대 크기/취소 검증의 한계를 구분해 기록한다.
- [x] 승인 설계의 모든 요구와 증거를 대조하고 한국어 커밋, 결과와 남은 한계를 전달한다. 실제 완료 전에는 goal을 완료 처리하지 않는다.

완료 결과와 요구사항별 증거는 [검증 기록](../verification/2026-11-07-backup-privacy-boundaries.md)에 정리했다.
작업 2와 4는 파일 서비스 인터페이스와 확인 흐름이 연결되어 같은 변경 묶음으로 커밋한다.
