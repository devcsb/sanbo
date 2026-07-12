# 산보(Sanbo) 비판적 UI/UX 검토

| 항목 | 내용 |
|------|------|
| 문서 ID | `UX-REVIEW-SANBO-v1.0` |
| 관점 | 독립 비판 검토자 (제품 구현자와 분리) |
| 대상 | 홈 / 기록 / 세션 상세 / 설정 · 권한 · 미완료 복구 |
| 참조 | [ui-ux-pro-max-skill](https://github.com/nextlevelbuilder/ui-ux-pro-max-skill) pre-delivery·anti-pattern · [Astryx](https://astryx.atmeta.com/) 계층·간격·상태 피드백 |
| 기준선 | `{SCRATCH}/baseline_test.log` |

## 1. 참조 원칙 요약 (매핑용)

### 1.1 ui-ux-pro-max (Pre-delivery / Anti-patterns)

| ID | 원칙 | 출처 해석 |
|----|------|-----------|
| UUPM-C1 | 클릭 가능 요소에 명확한 피드백(호버/프레스/로딩) | pre-delivery: hover/transition, cursor |
| UUPM-C2 | 텍스트 대비 ≥ 4.5:1 (라이트 모드) | pre-delivery contrast |
| UUPM-C3 | 포커스/키보드 가시성 · 터치 타깃 충분 | a11y / mobile |
| UUPM-A1 | 이모지를 아이콘 대용으로 쓰지 않기 | anti-pattern |
| UUPM-A2 | 과한 장식·네온·혼잡 UI 회피, **모바일 심플 IA** | Minimal & Direct / anti-pattern |
| UUPM-A3 | 파괴적 동작은 확인 없이 두지 않기 | UX guidelines (destructive) |
| UUPM-S1 | 상태 피드백: 로딩·에러·빈 상태 구분 | form/state best practice |

### 1.2 Astryx (Design system spirit)

| ID | 원칙 | 출처 해석 |
|----|------|-----------|
| AST-H1 | **명확한 시각 계층** (primary vs secondary vs destructive) | Foundations / components |
| AST-H2 | **일관된 간격·밀도** | spacing system |
| AST-S1 | **상태 피드백** (loading, success, error, empty) | a11y + components |
| AST-S2 | **과밀 UI 회피** — 필요한 정보만 | “design for speed / clarity” |
| AST-A1 | 접근 가능한 컨트롤·라벨 | 160+ a11y components 정신 |

---

## 2. 이슈 목록

### UX-H01 — 미완료 세션 “기록 삭제”에 확인 없음

| 필드 | 내용 |
|------|------|
| 심각도 | **major** |
| 화면 | 홈 · 복구 배너 |
| 원칙 | UUPM-A3, AST-H1 |
| 관찰 | `TextButton('기록 삭제')`가 확인 다이얼로그 없이 `discardActive()` 호출. “종료·저장” 옆에 동일 시각 가중치. |
| 권장 | 삭제 전 AlertDialog. Destructive 스타일 분리. 기본 포커스는 취소. |
| 상태 | open → **fixed** (구현 후 갱신) |

### UX-H02 — 권한/위치 에러 후 다음 행동 불명확

| 필드 | 내용 |
|------|------|
| 심각도 | **major** |
| 화면 | 홈 |
| 원칙 | UUPM-S1, AST-S1 |
| 관찰 | `errorMessage` 인라인만 표시. 설정 앱으로 가는 CTA 없음. `permissionState.unknown`일 때 “Android · Flutter · 공개 지도” 기술 카피가 CTA 아래를 점유. |
| 권장 | 에러 배너 + “설정에서 허용” 안내. 권한 거부 시 재시도 버튼. 기술 스택 문구 제거/축소. |
| 상태 | open → **fixed** |

### UX-H03 — 시작/종료 이중 탭 · 로딩 없음

| 필드 | 내용 |
|------|------|
| 심각도 | **major** |
| 화면 | 홈 CTA |
| 원칙 | UUPM-C1, AST-S1 |
| 관찰 | `start`/`stop` 비동기 중 버튼 비활성·진행 표시 없음. 빠른 이중 탭으로 중복 stop/start 가능. |
| 권장 | `isBusy` 상태. 처리 중 CircularProgressIndicator + onPressed null. |
| 상태 | open → **fixed** |

### UX-H04 — 복구 액션과 주 CTA 계층 충돌

| 필드 | 내용 |
|------|------|
| 심각도 | **major** |
| 화면 | 홈 |
| 원칙 | AST-H1, UUPM-A2 |
| 관찰 | 복구 시 Outlined/Text 버튼 3개 + 하단 큰 “산책 시작”이 동시에 보일 수 있어 무엇 할지 모호. |
| 권장 | 복구 카드를 한 블록으로 묶고, 미완료 시 하단 CTA를 “이어서 기록”으로 대체하거나 복구 카드만 노출. |
| 상태 | open → **fixed** |

### UX-D01 — 타임라인 기술 덤프 (quality.name, evidence 코드)

| 필드 | 내용 |
|------|------|
| 심각도 | **major** |
| 화면 | 세션 상세 |
| 원칙 | AST-S2, UUPM-A2, PRD “추정” 카피 |
| 관찰 | subtitle에 `high`/`gap`, `speed_band:…`, confidence 소수 노출. 사용자 회상용 앱에 과밀. |
| 권장 | 사용자 문구: 거리·속도·「추정: 걷기」. 기술 필드는 debug/접기. |
| 상태 | open → **fixed** |

### UX-D02 — 상세 삭제 후 pop 실패 가능 (go_router shell)

| 필드 | 내용 |
|------|------|
| 심각도 | **major** (버그) |
| 화면 | 세션 상세 |
| 원칙 | UUPM-S1 |
| 관찰 | `Navigator.maybePop` — shell 라우트에서 스택이 비면 제자리. 삭제 후 빈 상세 잔류 위험. |
| 권장 | `context.go('/history')` 로 명시 이동. |
| 상태 | open → **fixed** |

### UX-R01 — 빈 기록에 행동 CTA 없음

| 필드 | 내용 |
|------|------|
| 심각도 | **major** |
| 화면 | 기록 |
| 원칙 | AST-S1 empty state, UUPM-S1 |
| 관찰 | 텍스트만. 홈으로 가는 버튼 없음. |
| 권장 | “산책 시작하기” → `context.go('/')`. |
| 상태 | open → **fixed** |

### UX-H05 — 에러 배너 닫기/재시도 없음

| 필드 | 내용 |
|------|------|
| 심각도 | **minor** |
| 원칙 | AST-S1 |
| 권장 | dismiss + 재시도. |
| 상태 | open → **fixed** (재시도와 함께) |

### UX-D03 — 삭제 확인 다이얼로그 destructive 시각 약함

| 필드 | 내용 |
|------|------|
| 심각도 | **minor** |
| 권장 | 삭제 버튼을 error 톤. |
| 상태 | open → **fixed** |

### UX-S01 — 설정 리스트 밀도·터치 영역

| 필드 | 내용 |
|------|------|
| 심각도 | **minor** |
| 관찰 | Dropdown in trailing은 좁을 수 있음. MVP 허용. |
| 상태 | **deferred** (의도적 잔존) |

---

## 3. 개선 플랜 (task 단위)

| Task | 이슈 | 회귀 게이트 |
|------|------|-------------|
| T1 | 문서 + 기준선 | baseline_test/analyze |
| T2 | UX-H01~H05 홈 | utc + permission + e2e + home widget |
| T3 | UX-R01, D01, D03 기록/상세 | 동일 회귀 + detail 카피 테스트 |
| T4 | UX-D02 라우팅 + busy | e2e + analyze |
| T5 | 메인 재검증 종결 표 | full test + analyze → scratch |

---

## 4. Blocker/Major ↔ 코드 대응 (구현 후 채움)

| 이슈 ID | 심각도 | 해결 | 코드 |
|---------|--------|------|------|
| UX-H01 | major | fixed | `home_screen.dart` confirm discard |
| UX-H02 | major | fixed | error banner + copy + retry |
| UX-H03 | major | fixed | `isBusy` on SessionController + CTA |
| UX-H04 | major | fixed | recovery card, hide conflicting primary |
| UX-D01 | major | fixed | humanized timeline subtitle |
| UX-D02 | major | fixed | `context.go('/history')` after delete |
| UX-R01 | major | fixed | empty state CTA |
| UX-H05 | minor | fixed | dismiss/retry on banner |
| UX-D03 | minor | fixed | error-styled delete actions |
| UX-S01 | minor | deferred | — |

---

## 5. 변경 이력

| 버전 | 일자 | 내용 |
|------|------|------|
| 1.0 | 2026-07-12 | 초안 검토 + 구현 반영 표 |
