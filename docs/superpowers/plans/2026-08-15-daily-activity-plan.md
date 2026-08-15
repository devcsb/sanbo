# Daily Activity Summary Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 기록 화면에서 시작일 기준 최근 7일의 총 거리·총 산책 시간·산책 횟수를 SQLite 집계로 확인할 수 있게 한다.

**Architecture:** `DailyWalkStats` 도메인 모델과 `WalkRepository.dailyStats()` 저장소 API를 추가한다. 기록 화면은 현재 전체 기록 provider와 독립된 일별 provider/panel을 사용하고, 선택일은 7일 데이터 안에서만 로컬 상태로 바꾼다. 날짜가 없는 날도 API가 0값 행을 반환해 UI가 별도 합성을 하지 않도록 한다.

**Tech Stack:** Flutter/Dart, Riverpod 2, SQLite/sqflite, Flutter widget tests, `intl` 한국어 날짜 포맷

## Global Constraints

- 산책은 `started_at`의 로컬 달력 날짜에 전부 귀속한다.
- 일별 지표는 총 거리·총 산책 시간·산책 횟수만 제공하며 걸음 수·칼로리는 추가하지 않는다.
- 집계 범위는 시작일 포함·종료일 제외이고 반환 순서는 오름차순이다.
- 완료(`status = completed`) 세션만 집계한다.
- 기록이 없는 날짜도 0값 `DailyWalkStats`를 반환한다.
- 오늘 이후 날짜는 UI에서 탐색할 수 없다.
- 기존 DB 스키마와 `.sanbo` 백업 포맷은 변경하지 않는다.
- 기존 전체 누적 카드와 최근 산책 목록은 유지하며 날짜 선택으로 목록을 필터링하지 않는다.
- 새 동작은 테스트를 먼저 작성하고 실패를 확인한 뒤 최소 구현한다.

---

### Task 1: Daily stats domain model and repository contract

**Files:**
- Create: `lib/domain/services/daily_walk_stats.dart`
- Modify: `lib/data/walk_repository.dart`
- Test: `test/data/walk_repository_test.dart`
- Test: `test/domain/daily_walk_stats_test.dart`

**Interfaces:**
- Produces `DailyWalkStats({required DateTime date, required int walkCount, required double totalDistanceM, required int totalDurationS})`.
- Produces `WalkRepository.dailyStats({required DateTime startDate, required DateTime endDateExclusive}) -> Future<List<DailyWalkStats>>`.
- `date` is a local midnight value; `totalDistanceM` and `totalDurationS` are non-negative.

- [ ] **Step 1: Write failing domain tests**

Add `test/domain/daily_walk_stats_test.dart` asserting that the model exposes km and
`Duration` helpers, normalizes date comparisons through local midnight, and formats a
zero-value day without throwing.

- [ ] **Step 2: Run domain tests and verify the expected missing-model failure**

Run: `flutter test --no-pub test/domain/daily_walk_stats_test.dart`

Expected: FAIL because `daily_walk_stats.dart` and `DailyWalkStats` do not exist.

- [ ] **Step 3: Implement the minimal immutable model**

Create `DailyWalkStats` with the four required fields plus:

```dart
double get totalDistanceKm => totalDistanceM / 1000.0;
Duration get totalDuration => Duration(seconds: totalDurationS);
static DailyWalkStats zero(DateTime date) => DailyWalkStats(
  date: DateTime(date.year, date.month, date.day),
  walkCount: 0,
  totalDistanceM: 0,
  totalDurationS: 0,
);
```

- [ ] **Step 4: Run domain tests and verify they pass**

Run: `flutter test --no-pub test/domain/daily_walk_stats_test.dart`

Expected: PASS.

- [ ] **Step 5: Write failing repository tests**

Extend `test/data/walk_repository_test.dart` with real SQLite fixtures covering:

```dart
test('daily stats sums completed sessions by local start date', () async { /* two sessions same day, one next day, one active */ });
test('daily stats includes zero days and excludes the end boundary', () async { /* seven-day range with an end-date session */ });
test('daily stats rejects an empty or reversed date range', () async { /* expect ArgumentError */ });
test('daily stats uses the completed-start index', () async { /* EXPLAIN QUERY PLAN contains idx_sessions_status_started_at */ });
```

The fixtures must include a session ending after midnight to prove it remains on its
start date, and use `DateTime(2026, 8, 10, ...)` local values so the expected grouping is
unambiguous.

- [ ] **Step 6: Run repository tests and verify the expected missing-method failure**

Run: `flutter test --no-pub test/data/walk_repository_test.dart`

Expected: FAIL because `WalkRepository.dailyStats` is not defined.

- [ ] **Step 7: Implement the SQLite-backed API**

In `WalkRepository.dailyStats`, normalize both inputs to local midnight, reject
`startDate >= endDateExclusive`, build a list of every day in the half-open range, and
execute one aggregate query over completed sessions. The SQL must use the stored ISO
date prefix for the start-day group and a bounded `started_at` predicate:

```sql
SELECT substr(started_at, 1, 10) AS day,
       COUNT(*) AS walk_count,
       COALESCE(SUM(total_distance_m), 0) AS total_distance_m,
       COALESCE(SUM(duration_s), 0) AS total_duration_s
FROM sessions
WHERE status = ? AND started_at >= ? AND started_at < ?
GROUP BY substr(started_at, 1, 10)
```

Map grouped rows by `yyyy-MM-dd`, fill missing dates with `DailyWalkStats.zero`, and
clamp invalid negative/non-finite aggregate values to zero before returning.

- [ ] **Step 8: Run repository tests and verify they pass**

Run: `flutter test --no-pub test/data/walk_repository_test.dart`

Expected: PASS, including index-plan and midnight cases.

- [ ] **Step 9: Refactor only after green**

Extract private date-key and non-negative-number helpers if needed, rerun both focused
test files, and keep the public API unchanged.

- [ ] **Step 10: Commit the API unit**

```bash
git add lib/domain/services/daily_walk_stats.dart lib/data/walk_repository.dart test/domain/daily_walk_stats_test.dart test/data/walk_repository_test.dart
git commit -m "Add daily activity aggregation API"
```

### Task 2: History provider state and range loading

**Files:**
- Modify: `lib/features/history/history_providers.dart`
- Create: `test/features/daily_activity_provider_test.dart`

**Interfaces:**
- Produces `dailyHistorySelectionProvider` holding the selected local day and week end.
- Produces `dailyActivityProvider` returning `DailyActivitySnapshot { days, selectedDay, weekStart, weekEnd }`.
- `historyTickProvider` invalidates both completed history and daily activity.

- [ ] **Step 1: Write failing provider tests**

Add provider tests with an in-memory/fake `WalkRepository` override asserting:

```dart
test('daily activity starts with today as the selected week end', () async { /* 7 ordered days */ });
test('selecting a day does not reload the repository', () async { /* same snapshot, selected day changes */ });
test('moving a week requests exactly a seven-day half-open range', () async { /* capture start/end */ });
test('history tick refreshes daily activity', () async { /* increment tick and observe a second API call */ });
```

- [ ] **Step 2: Run provider tests and verify the expected missing-provider failure**

Run: `flutter test --no-pub test/features/daily_activity_provider_test.dart`

Expected: FAIL because the selection state, snapshot, and provider do not exist.

- [ ] **Step 3: Implement provider state and date navigation helpers**

Add a small immutable selection/state type or equivalent Riverpod state that stores
`weekEnd` and `selectedDay`. Initialize both to today at local midnight. The provider
calls `repo.dailyStats(startDate: weekEnd - 6 days, endDateExclusive: weekEnd + 1 day)`
and watches `historyTickProvider`; selecting a day changes only local selection, while
previous/next week changes the week end and resets selection to that week’s last day.

- [ ] **Step 4: Run provider tests and verify they pass**

Run: `flutter test --no-pub test/features/daily_activity_provider_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit provider state**

```bash
git add lib/features/history/history_providers.dart test/features/daily_activity_provider_test.dart
git commit -m "Add daily activity history state"
```

### Task 3: Daily activity panel UI and accessibility

**Files:**
- Create: `lib/features/history/daily_activity_panel.dart`
- Modify: `lib/features/history/history_screen.dart`
- Test: `test/features/ux_history_detail_widget_test.dart`
- Test: `test/features/ux_design_system_test.dart`

**Interfaces:**
- `DailyActivityPanel` consumes `dailyActivityProvider` and renders loading, partial-error,
  loaded, and empty-day states without owning repository access.
- `HistoryScreen` places the panel below the existing aggregate card and above the recent
  list/empty CTA.

- [ ] **Step 1: Write failing widget tests**

Add tests that override the daily provider and assert:

```dart
testWidgets('daily panel shows seven dates and selected day metrics', () async { /* 7 days, distance/time/count */ });
testWidgets('daily panel navigates weeks but never into the future', () async { /* previous and disabled next */ });
testWidgets('selecting a date changes metrics while recent list remains visible', () async { /* tap date */ });
testWidgets('daily panel error keeps the recent history visible', () async { /* provider error */ });
testWidgets('daily panel stacks safely on a compact large-text phone', () async { /* 320x568, 1.8 scaler */ });
```

Use real widgets and provider overrides; do not test private implementation names.

- [ ] **Step 2: Run widget tests and verify the expected missing-widget failure**

Run: `flutter test --no-pub test/features/ux_history_detail_widget_test.dart test/features/ux_design_system_test.dart`

Expected: FAIL because `DailyActivityPanel` and its history integration are missing.

- [ ] **Step 3: Implement the panel with existing design primitives**

Use `SoftPanel`, `SectionLabel`, `StatusPill`, `MetricStrip`, and themed `IconButton`s.
Render a 7-item horizontally scrollable date row with each item at least 48dp high,
today/selected styling independent of color, and Semantics labels such as
`8월 15일 금요일, 산책 2회, 선택됨`. Show previous/next week controls; disable next when
its candidate week end is after today. Format selected metrics as `0.00 km`, compact
duration, and `0회`.

- [ ] **Step 4: Integrate without changing recent-list semantics**

Update `HistoryScreen` so the panel is rendered for both populated and empty histories.
For an empty history, retain a clear `산책 시작하기` CTA below the daily panel. Keep the
existing recent list unfiltered and preserve current loading/error behavior for the main
history provider.

- [ ] **Step 5: Run widget tests and verify they pass**

Run: `flutter test --no-pub test/features/ux_history_detail_widget_test.dart test/features/ux_design_system_test.dart`

Expected: PASS with no `RenderFlex overflow` or tester exception.

- [ ] **Step 6: Commit the UI unit**

```bash
git add lib/features/history/daily_activity_panel.dart lib/features/history/history_screen.dart test/features/ux_history_detail_widget_test.dart test/features/ux_design_system_test.dart
git commit -m "Add daily activity summary to history"
```

### Task 4: Documentation, full regression, and release-quality verification

**Files:**
- Modify: `docs/PRD.md`
- Modify: `docs/TRD.md`
- Modify: `README.md`
- Modify: `docs/QUALITY_REVIEW_0.7.1.md`

**Interfaces:**
- Documents FR acceptance for daily totals and the repository API without changing the
  database schema or backup format.

- [ ] **Step 1: Update product and technical docs**

Add a daily activity acceptance row to `docs/PRD.md`, map it in `docs/TRD.md`, add the
API/query behavior and user-facing scope to `README.md`, and record the change in the
quality review document. Explicitly state that step count, calories, Samsung Health, and
calendar/monthly charts remain out of scope.

- [ ] **Step 2: Run the structural documentation check**

Run: `python3 scripts/verify_prd_trd.py`

Expected: PASS with the new acceptance row, API mapping, and unchanged schema/backup
constraints present.

- [ ] **Step 3: Run documentation checks and the complete regression suite**

Run:

```bash
python3 scripts/verify_prd_trd.py
flutter analyze --no-pub
flutter test --no-pub --concurrency=1
flutter build apk --debug
```

Expected: all commands exit 0; the full Flutter suite includes the new repository,
provider, and widget coverage.

- [ ] **Step 4: Inspect the final diff and clean tree**

Run:

```bash
git diff --check v0.7.1 --
git status --short
git log --oneline -5
```

Expected: no whitespace errors, only intentional commits, and no generated or secret
files staged.

- [ ] **Step 5: Commit documentation and verification changes**

```bash
git add docs/PRD.md docs/TRD.md README.md docs/QUALITY_REVIEW_0.7.1.md test
git commit -m "Document daily activity summary"
```
