# 5시간 세션 자동 종료 정책 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task with verification checkpoints.

**Goal:** 전체 산책 세션의 자동 종료 한도를 5시간으로 확대하고 4시간 45분 경고, 코드·테스트·제품 문서를 일치시킨다.

**Architecture:** `SessionGuardPolicy`가 단일 정책 값을 소유하고 `SessionController`가 도메인 이벤트를 사용자 문구·알림·자동 저장으로 변환한다. 도메인 테스트와 Riverpod 흐름 테스트가 경계 시각과 실패 복구를 각각 검증하며, README/PRD/TRD/품질 검토 문서가 동일한 수치를 설명한다.

**Tech Stack:** Flutter/Dart, Riverpod, Flutter test, Markdown product/technical docs.

## Global Constraints

- 전체 세션 경고는 `4시간 45분`, 자동 저장·종료는 `5시간`으로 고정한다.
- 한 장소 정지 경고 `20분`·자동 종료 `30분`은 변경하지 않는다.
- 5시간 초과 계속 기록 기능과 GPS 수집/배터리 정책 변경은 포함하지 않는다.
- 기존 0.7.1 릴리즈 문서는 과거 산출물로 보존하고, 후속 정책은 품질 검토 문서에 기록한다.

---

### Task 1: 정책 경계 회귀 테스트

**Files:**
- Modify: `test/domain/session_guard_test.dart:180-215`
- Modify: `test/features/session_guard_flow_test.dart:150-180`

**Interfaces:**
- Consumes: `SessionGuardPolicy`, `SessionGuard.evaluate`, `SessionController.debugEvaluateSessionGuard`.
- Produces: 4시간 45분 경고·15분 남음·5시간 제한과 컨트롤러 알림 카피를 고정하는 회귀 테스트.

- [ ] **Step 1: Write the failing tests**

  도메인 테스트의 제목과 시각을 `4시간 45분`/`5시간` 기준으로 바꾸고, 흐름 테스트도
  `start + 4h45m`에서 경고를 확인한 뒤 `start + 5h`에서 종료·완료 알림을 확인한다.

- [ ] **Step 2: Run tests to verify they fail**

  Run: `flutter test --no-pub --concurrency=1 test/domain/session_guard_test.dart test/features/session_guard_flow_test.dart`

  Expected: 기존 3시간 기본값과 문구 때문에 새 경계 assertion이 실패한다.

### Task 2: 도메인·컨트롤러 정책 구현

**Files:**
- Modify: `lib/domain/services/session_guard.dart:10-23`
- Modify: `lib/features/home/session_controller.dart:670-695`

**Interfaces:**
- Consumes: Task 1의 실패 테스트와 기존 `SessionGuardEvent` 상태 전이.
- Produces: 기본 `durationWarningAfter = 4h45m`, `durationLimit = 5h`, 동기화된 한국어 안내·완료 문구.

- [ ] **Step 1: Change only the policy defaults and copy**

  `SessionGuardPolicy`의 기본 duration 값을 각각 `const Duration(hours: 4, minutes: 45)`와
  `const Duration(hours: 5)`로 바꾸고, 컨트롤러 경고·완료 문구의 숫자를 `4시간 45분`과
  `5시간`으로 바꾼다. 정지 관련 분기와 복구 실패 동작은 건드리지 않는다.

- [ ] **Step 2: Run focused tests to verify they pass**

  Run: `flutter test --no-pub --concurrency=1 test/domain/session_guard_test.dart test/features/session_guard_flow_test.dart`

  Expected: focused tests pass with the new boundary and copy.

### Task 3: 제품 문서 동기화

**Files:**
- Modify: `README.md:55-56,254`
- Modify: `docs/PRD.md:232,497,513`
- Modify: `docs/TRD.md:253-254,730`
- Modify: `docs/QUALITY_REVIEW_0.7.1.md` (append 0.7.2-dev policy follow-up)

**Interfaces:**
- Consumes: implemented 5-hour behavior from Task 2.
- Produces: 사용자 안내, 요구사항, 기술 규칙, 릴리즈 후속 검토가 같은 정책을 설명하는 문서.

- [ ] **Step 1: Update all active policy references**

  README 주요 기능과 roadmap, PRD FR-23/변경 이력, TRD 안전 종료 표/변경 이력을
  `4시간 45분` 경고 및 `5시간` 종료로 갱신한다. 0.7.1 릴리즈 노트의 역사적 3시간
  문구는 수정하지 않고, 품질 검토 문서에 후속 정책과 미검증 실기기 검증 항목을 기록한다.

- [ ] **Step 2: Run structural/document checks**

  Run: `python3 scripts/verify_prd_trd.py && git diff --check`

  Expected: PRD/TRD 구조 검증 PASS and no whitespace errors.

### Task 4: 전체 검증 및 커밋

**Files:**
- No additional source files; verify all files from Tasks 1–3.

- [ ] **Step 1: Run the full test and analysis gates**

  Run: `flutter test --no-pub --concurrency=1` and `flutter analyze --no-pub`.

  Expected: all tests pass and analyzer reports no issues.

- [ ] **Step 2: Review policy references and status**

  Run: `rg -n '3시간|2시간 45분|4시간 45분|5시간' README.md docs lib test` and `git status --short`.

  Expected: active code/docs/tests contain only intentional 5-hour policy references; historical release notes may retain 3-hour references; status lists only planned files.

- [ ] **Step 3: Commit the implementation**

  ```bash
  git add lib/domain/services/session_guard.dart lib/features/home/session_controller.dart test/domain/session_guard_test.dart test/features/session_guard_flow_test.dart README.md docs/PRD.md docs/TRD.md docs/QUALITY_REVIEW_0.7.1.md docs/superpowers/plans/2026-08-16-five-hour-session-duration-plan.md
  git commit -m "feat: extend session auto-stop to five hours"
  ```
