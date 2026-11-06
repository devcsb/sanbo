# 산책 요약과 주간 기록 전환 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 이번 산책 수치를 유지하면서 경로와 주간 누적을 탭/밀기로 전환하고, 지도를 별도 화면에서 탐색한다.

**Architecture:** 기존 완료 상세 화면에 독립적인 주간 읽기 provider와 두 패널 위젯을 붙인다. 측정값은 저장된 값의 의미를 유지하며 주간 오류가 상세 기록을 막지 않는다. 경로 미리보기와 지도 탐색의 입력 처리를 구분한다.

**Tech Stack:** Flutter, Dart, Riverpod 2, sqflite, flutter_map 7, timezone. 새 의존성을 추가하지 않는다.

**Spec:** `docs/superpowers/specs/2026-10-26-walk-summary-interaction-design.md` (2026-10-27 사용자 승인).

## 실행 방식

사용자는 `gpt-6.1-sol`, reasoning `medium`을 주 구현자로 지정하고 구현 진행을 요청했다.
한 구현자가 아래 작업을 순서대로 수행한다. 추가 승인을 묻거나 재위임하지 않는다.
조율자는 구현 결과를 별도로 검토하고 최종 전체 게이트를 한 번 실행한다.
이번 범위는 앱 구현과 검증이며 릴리즈 공개/기존 DB 재계산/광고 도입을 포함하지 않는다.

## Global Constraints

- 이번 산책 수치, 사용자 라벨, 원본과 제외 취소를 보존한다. DB 마이그레이션은 필요 없다.
- 현재 스키마에는 확정 걷기 정책 버전이 없다. 이번 구현에서는 `포함 거리`, `이동 시간`,
  `이동 평균 속도`라는 호환 표현을 사용하고 순수 걷기를 확정하지 않는다.
- `dailyStats()`의 `duration_s` 합계를 이동 시간으로 재사용하지 않는다. 기존 일일 통계의 의미를 변경하지 않는다.
- 지도/주간 통계/상세 데이터 실패를 분리하고, 탭 전환으로 DB 조회나 위치 구독을 새로 만들지 않는다.
- 2개 패널, 첫 진입은 경로, 자동 넘김/무한 반복 없음, 전환 220ms, 동작 줄이기에서는 비필수 전환 없음.
- 주요 터치 영역 48×48 논리 픽셀 이상. 320px와 글자 100/160/200%, 다크 모드에서 내용을 자르지 않는다.
- 큰 지도 닫기, 재생, 선택 구간, 메모, 제외/복원, 내보내기 경로를 보존한다. 보이지 않는 지도 재생은 멈춘다.
- 새 패키지/SDK/외부 서비스/권한 없음. CARTO 자격 증명을 출력하거나 저장소에 넣지 않는다.
- 코드 탐색에서 `*.freezed.dart`, `*.g.dart`를 제외한다. 사실은 한 곳에 두고 다른 문서는 포인터로 연결한다.

## Review Focus

1. 월요일 경계와 전주 같은 요일/시각, DST에서 시간을 임의로 배분하거나 이번 산책을 두 번 합산하지 않는다 (작업 1).
2. 이동 시간이 없는 과거 기록, 비정상 수치, 경계를 넘는 저장 합계가 있어도 0이나 확정 걷기로 위장하지 않는다 (작업 1, 4).
3. 큰 글자와 좁은 화면에서 패널 높이가 잘리거나 탭이 세로 스크롤을 막지 않는다 (작업 3).
4. 큰 지도 복귀/누적 화면 전환/구간 선택 시 재생 위치와 강조가 불필요하게 초기화되지 않는다 (작업 2, 4).
5. 주간 통계 실패와 지도 인증 실패 중 하나가 생겨도 기존 기록 수정/반출을 유지한다 (작업 4).

## 작업 1. 제한된 주간 이동 시간 집계

**Files:**
- Create: `lib/domain/services/session_week_summary.dart`
- Modify: `lib/data/walk_repository.dart`
- Create: `lib/features/session_detail/session_week_provider.dart`
- Test: `test/domain/session_week_summary_test.dart`, `test/data/session_week_summary_test.dart`

**Interfaces:**
- `SessionWeekSummary`와 요일별 값 객체를 정의한다. 주/전주 시작과 종료, 날짜별 이동 초,
  세션 수, 이번 산책 기여 초, 누락 여부, 비교 가능한 전주 합계를 가진다.
- 순수 함수 `summarizeSessionWeek({required WalkSession reference, required List<WalkSession> sessions})`를 제공한다.
- `WalkRepository.sessionWeekSummary(String sessionId)`는 기준 세션과 해당 주/비교 주에
  겹치는 완료 기록만 읽고 위 결과를 반환한다.
- `sessionWeekSummaryProvider`는 sessionId를 받는 autoDispose family이며 `historyTickProvider`로 무효화한다.

- [x] 저장된 이동 시간 600초/전체 시간 1200초를 구분하고 이번 산책을 1회만 더하는 테스트를 작성한다.
- [x] UTC 저장값/시간대가 붙지 않은 과거 값, 월요일 시작, 지난주 같은 현지 시각,
  DST, 기간 밖/종료 이후 세션을 테스트한다. 기준 시간대는 기준 세션의 저장 IANA 시간대다.
- [x] null/음수 이동 시간, 유한하지 않은 값, 기록 없음, 기간을 가로지른 합계가 비교를
  숨기고 부분 집계 상태를 반환하는 테스트를 작성한다. 중복 ID도 한 번만 센다.
- [x] 새 테스트 실패를 확인하고 구현한다. 현재 스키마에서는 구간별 이동 초가 저장되지
  않으며 raw GPS만으로 과거 측정 정책을 확정할 수 없다. 한 현지 날짜와 집계 범위에
  완전히 들어오는 정상 세션만 저장된 이동 시간을 사용한다. 나머지는 균등 배분하거나
  재계산하지 않고 누락을 명시한다. 비교/순번은 불완전하면 숨긴다.
- [x] 날짜별 객체 수를 7개로 제한한다. SQL은 완료 상태와 겹치는 날짜 범위로 제한하고,
  과거 wall-clock 문자열은 기존 파서를 사용해 최종 포함 여부를 판단한다.
- [x] 관련 테스트를 실행하고 실패를 수정한다. 다른 화면의 `dailyStats` 회귀도 확인한다.

## 작업 2. 지도 미리보기와 탐색 구분

**Files:**
- Modify: `lib/shared/widgets/route_map.dart`
- Create: `lib/features/session_detail/session_route_screen.dart`
- Test: `test/widget/route_map_test.dart`, `test/features/session_route_screen_test.dart`

**Interfaces:**
- `RouteMap`에 호출부별 interaction flags와 선택적 `MapController` 전달을 지원한다.
  기존 호출부의 기본값은 `InteractiveFlag.pinchZoom`으로 유지한다.
- `SessionRouteScreen`은 기존 `RouteMapGeometry`, fragments, 선택 강조/재생 커서를 입력으로
  받고 전체 화면 지도와 확대/축소/전체 맞춤/방향 이동 버튼을 제공한다.

- [x] 기존 기본 동작 유지, 새 미리보기에서 지도 제스처가 꺼짐, 탐색 화면 조작과
  빈 경로에서도 닫기 가능함을 검증하는 테스트를 작성하고 실패를 확인한다.
- [x] 지도 오류/재시도/attribution/fragment 보존을 유지하며 모드별 조작을 구현한다.
  현재 보이지 않는 요약 지도와 탐색 지도에 활성 tile client가 동시에 남지 않게 한다.
- [x] 지도와 연결된 기존 테스트와 새 탐색 테스트를 실행한다. 외부 타일 요청은 mock/offline로 검증한다.

## 작업 3. 두 패널 전환 위젯

**Files:**
- Create: `lib/features/session_detail/session_summary_panels.dart`
- Test: `test/features/session_summary_panels_test.dart`

**Interfaces:**
- `SessionSummaryPanels`는 경로/주간 위젯, 선택 index, `ValueChanged<int> onPageChanged`,
  각 상세 진입 callback을 받는다. 양쪽 선택은 하나의 상태를 사용한다.
- 공개 key/semantics로 탭, 선택 패널, 주간 오류/누락 상태를 테스트에서 식별할 수 있게 한다.

- [x] 버튼과 좌우 드래그가 같은 index를 바꾸고 상단 별도 요약을 바꾸지 않는 테스트를 작성한다.
- [x] ArrowLeft/Right, Home/End, 선택 semantics, 비선택 패널 focus 제외, 48px 버튼을 테스트한다.
- [x] 320px/160%/200%/가로/다크 모드, 긴 내용과 주간 오류에서 overflow가 없는지 검증한다.
- [x] 기본 `PageView`/`PageController`로 구현한다. 텍스트와 화면 폭에 맞는 높이를
  확보하고 필요하면 두 패널 중 큰 자연 높이에 맞춘다. 새 범용 레이아웃 프레임워크를 만들지 않는다.
- [x] 220ms 전환과 reduce-motion 즉시 전환, 가로 전환 취소와 세로 스크롤을 검증한다.
- [x] 테스트를 통과시킨다. 직접 만든 웹 시안의 포인터 판정 코드를 Flutter에 이식하지 않는다.

## 작업 4. 완료 상세 화면에 통합

**Files:**
- Modify: `lib/features/session_detail/session_detail_screen.dart`
- Test: `test/features/ux_history_detail_widget_test.dart`, `test/features/ux_history_detail_structure_test.dart`,
  `test/features/route_playback_flow_test.dart`
- Create: `test/features/session_summary_flow_test.dart`

**Interfaces:**
- 작업 1 provider, 작업 2 탐색 화면, 작업 3 패널을 소비한다.
- 기존 `sessionDetailProvider`, 재생/선택/편집/내보내기 계약을 유지한다.

- [x] 기존 데이터를 사용한 문구와 수치가 처음에 보이고 지도/누적 전환 중 유지되는 테스트를 작성한다.
- [x] 이번 산책 수치를 위에 배치하고 호환 문구를 적용한다. 조건부 보조 문구는
  실제 기여분/횟수가 정확할 때만 쓰며 측정되지 않은 것을 가상 데이터로 채우지 않는다.
- [x] 평균 계산 안내에 포함 거리, 초 단위 이동 시간과 실제 계산값을 연결한다.
  분모 0/null은 측정되지 않음이며 순간/최고 속도를 대신 표시하지 않는다.
- [x] 주간 loading/error/empty/partial을 별도로 표시한다. 과거 세션은 `그 주`와 범위를,
  현재 주는 `이번 주`를 쓴다. 기준 세션 시간대와 날짜 범위를 드러낸다.
- [x] 확인 필요 안내는 현재 데이터의 의미대로 쓰고 패널 밖에 둔다. 이번 UI 작업에서
  새로운 구간 제외를 실행하지 않는다. 없는 미확인 시간이나 원인을 만들어 쓰지 않는다.
- [x] 누적 화면에서 재생을 멈추고 커서를 유지한다. 구간 강조 시 경로로 전환한다.
  지도 상세 복귀/동일 sessionId reload에서는 선택과 스크롤을 유지하고 다른 sessionId에서는 초기화한다.
- [x] 제외/복원 후 상세와 주간 값이 함께 갱신되고 중간에 서로 다른 확정 수치를 섞지 않는 테스트를 넣는다.
- [x] 통계 provider가 실패해도 메모, 구간 수정, 기존 내보내기 접근이 남는 테스트를 넣는다.
- [x] 관련 기존 위젯/재생/제외 통합 테스트를 실행한다. 옛 문구/위치만 가정한 테스트는
  새 계약에 맞게 수정하되 실제 동작 assertion을 제거해 통과시키지 않는다.

## 작업 5. 통합 검증과 기록

**Files:**
- Create: `docs/superpowers/verification/2026-10-27-walk-summary-interaction.md`
- Modify: 이 계획의 체크박스와 승인 설계의 구현 상태만 갱신한다.

- [x] 구현자는 변경 Dart 파일 format, `flutter analyze`, 작업별 관련 테스트를 실행해
  정확한 명령/결과/실패 이력을 기록한다. 이미 통과한 전체 게이트를 반복 실행하지 않는다.
- [x] 조율자가 변경 전 기준 `aad33d8`과 diff를 대조해 반례를 검토한다. 정책 의미 변경,
  주 경계/DST, provider 분리, 중복 타일 client, 기존 재생/제외 회귀를 우선 본다.
- [x] 조율자가 `flutter test` 전체를 한 번 실행하고 `flutter analyze` 결과와 대조한다.
  전체 실패 후 수정하면 전체를 다시 실행해 확인한다. 새로운 실패가 없으면 반복하지 않는다.
- [x] 빌드 가능 환경에서 `flutter build apk --debug`로 컴파일 확인한다. 키 없는 검증 빌드는
  정상 지도 인증을 증명하지 않으며 릴리즈 서명/배포는 이번 작업 범위가 아니다.
- [x] 합성 기록으로 실제 앱 화면을 확인할 수 있으면 캡처한다. 불가하면 위젯 검증 범위와
  실제 터치/OS 화면 읽기/배터리 미검증을 구분해 보고한다.
- [x] 최종 변경을 한국어 커밋으로 남긴다. AI attribution을 넣지 않고 커밋/파일/검증 결과를 전달한다.
