# 산보(Sanbo) 비판적 UI/UX 검토

| 항목 | 내용 |
|------|------|
| 문서 ID | `UX-REVIEW-SANBO-v2.0` |
| 관점 | 독립 비판 검토자 (제품 구현자와 분리) |
| 대상 | 홈 · 복구 · 기록(빈/목록) · 세션 상세 · 설정 · 인트로 · 하단 내비 · 지도 |
| 축 | 시각 계층/IA · 상태 피드백 · 파괴 동작 안전 · 카피/jargon · 터치/a11y 기초 |
| 참조 | Material 3 patterns · empty/error/loading · destructive confirm · calm mobile IA |
| 기준선 | `{SCRATCH}/ux_tests.log`, `{SCRATCH}/ux_analyze.log` |

---

## 1. 검토 축 (checklist)

| 축 | 질문 |
|----|------|
| **A. 시각 계층 / IA** | 주 행동 vs 보조 vs 파괴가 한눈에 구분되는가? 복구 시 CTA 충돌이 없는가? |
| **B. 상태 피드백** | loading / error / empty / busy 가 구분되며 다음 행동이 보이는가? |
| **C. 파괴 동작 안전** | 삭제·버리기 전 확인이 있고 destructive 시각인가? |
| **D. 카피 / jargon** | 사용자 화면에 PRD·스택·enum·영문 기술 라벨이 없는가? |
| **E. 터치 / a11y 기초** | ≥ ~48dp 타깃, tooltip/Semantics, 영구 거부 시 설정 경로가 있는가? |

---

## 2. 이슈 목록 (v2 재검토)

### UX-H01 — 미완료 “기록 삭제”에 확인 없음
| 필드 | 내용 |
|------|------|
| 심각도 | **major** |
| 축 | C |
| 관찰(과거) | 확인 없이 `discardActive()`. |
| 상태 | **fixed** — `confirmDiscardIncompleteWalk` + error 톤 삭제 버튼 |

### UX-H02 — 권한/위치 에러 후 다음 행동 불명확
| 필드 | 내용 |
|------|------|
| 심각도 | **major** |
| 축 | B, E |
| 관찰(과거) | 인라인 에러만; 설정 진입 경로 없음; 기술 카피. |
| 상태 | **fixed** — 배너 + 다시 시도 + (영구 거부/서비스 꺼짐 시) **설정 열기** → `LocationEngine.openSystemSettings()` |

### UX-H03 — 시작/종료 이중 탭 · 로딩 없음
| 필드 | 내용 |
|------|------|
| 심각도 | **major** |
| 축 | B |
| 상태 | **fixed** — `LiveSessionState.isBusy`, CTA spinner + null `onPressed` |

### UX-H04 — 복구 액션과 주 CTA 계층 충돌
| 필드 | 내용 |
|------|------|
| 심각도 | **major** |
| 축 | A |
| 상태 | **fixed** — 복구 시 하단 “산책 시작” 숨김; 카드 내 이어서/저장/지우기 |

### UX-H05 — 에러 배너 닫기/재시도
| 필드 | 내용 |
|------|------|
| 심각도 | **minor** → 해결 시 major 경로 보조 |
| 상태 | **fixed** — dismiss + 다시 시도 (+ 설정 열기) |

### UX-H06 — 복구 “저장하고 종료” busy 피드백 약함
| 필드 | 내용 |
|------|------|
| 심각도 | **major** (v2) |
| 축 | B |
| 관찰 | `isBusy` 시 이어서 기록만 스피너, 저장 버튼은 비활성만. |
| 상태 | **fixed** — 저장 OutlinedButton에도 busy spinner |

### UX-H07 — 영구 권한 거부 시 OS 설정 진입 불가
| 필드 | 내용 |
|------|------|
| 심각도 | **major** (v2) |
| 축 | B, E |
| 관찰 | 문구만 “설정에서 허용” — 앱 내 딥링크 없음. |
| 상태 | **fixed** — `openSystemSettings()` + 배너 **설정 열기** |

### UX-H08 — LIVE 영문 라벨
| 필드 | 내용 |
|------|------|
| 심각도 | **minor** (카피 일관성) |
| 축 | D |
| 상태 | **fixed** — 「기록 중」 |

### UX-D01 — 타임라인 기술 덤프
| 필드 | 내용 |
|------|------|
| 심각도 | **major** |
| 축 | D |
| 상태 | **fixed** — `timelineWindowSubtitle` 인간 문구; 추정은 칩 |

### UX-D02 — 상세 삭제 후 shell pop 실패
| 필드 | 내용 |
|------|------|
| 심각도 | **major** |
| 축 | B |
| 상태 | **fixed** — `context.go('/history')` |

### UX-D03 — 삭제 확인 destructive 시각
| 필드 | 내용 |
|------|------|
| 심각도 | **minor** |
| 상태 | **fixed** — error FilledButton |

### UX-D04 — 상세 not-found / 로드 에러에 탈출 CTA 없음
| 필드 | 내용 |
|------|------|
| 심각도 | **major** (v2) |
| 축 | B |
| 관찰 | EmptyState만 있고 기록 목록으로 돌아갈 버튼 없음. |
| 상태 | **fixed** — **기록으로** → `/history` |

### UX-D05 — 타임라인 행 터치 높이 부족 가능
| 필드 | 내용 |
|------|------|
| 심각도 | **minor** |
| 축 | E |
| 상태 | **fixed** — `minHeight: 52` + Semantics |

### UX-R01 — 빈 기록 CTA 없음
| 필드 | 내용 |
|------|------|
| 심각도 | **major** |
| 상태 | **fixed** — EmptyStateView + 산책 시작하기 |

### UX-R02 — 기록 행 a11y 라벨 없음
| 필드 | 내용 |
|------|------|
| 심각도 | **minor** |
| 상태 | **fixed** — Semantics + minHeight 64 |

### UX-S01 — 설정 Dropdown 터치 좁음
| 필드 | 내용 |
|------|------|
| 심각도 | **minor** |
| 상태 | **fixed** — `SegmentedButton` (min 44) + tooltip 설명 |

### UX-M01 — 포인트 없는 지도가 조용히 서울만 표시
| 필드 | 내용 |
|------|------|
| 심각도 | **minor** |
| 축 | B |
| 상태 | **fixed** — 「경로 포인트가 없어요」 오버레이 |

### UX-I01 — 인트로 CTA Semantics
| 필드 | 내용 |
|------|------|
| 심각도 | **minor** |
| 상태 | **fixed** — Semantics label 「산보 시작하기」 |

### UX-N01 — 하단 탭 애니메이션 과다 (과거)
| 필드 | 내용 |
|------|------|
| 심각도 | **deferred** |
| 관찰 | AnimatedSwitcher 제거됨. 추가 탭 햅틱은 제품 범위 밖. |
| 상태 | **deferred** — 현재 단순 NavigationBar 유지 |

---

## 3. Major 대응 요약

| ID | 심각도 | 상태 | 코드 |
|----|--------|------|------|
| UX-H01 | major | fixed | `discard_confirm.dart` |
| UX-H02 | major | fixed | `home_screen.dart` error banner |
| UX-H03 | major | fixed | `session_controller.dart` isBusy |
| UX-H04 | major | fixed | `home_screen.dart` recovery vs primary |
| UX-H06 | major | fixed | recovery save spinner |
| UX-H07 | major | fixed | `LocationEngine.openSystemSettings` + 설정 열기 |
| UX-D01 | major | fixed | `timeline_copy.dart` |
| UX-D02 | major | fixed | detail `go('/history')` |
| UX-D04 | major | fixed | detail EmptyState CTA |
| UX-R01 | major | fixed | history EmptyState CTA |
| UX-H05/H08/D03/D05/R02/S01/M01/I01 | minor | fixed | 각 화면/위젯 |
| UX-N01 | minor | deferred | 탭 햅틱 등 |

**Major 미해결(open): 없음.** 남은 항목은 deferred(탭 햅틱)뿐.

---

## 4. 회귀 게이트

| 경로 | 테스트 |
|------|--------|
| busy / permission 카피 | `test/features/ux_busy_and_permission_test.dart` |
| discard confirm | `test/features/ux_discard_dialog_test.dart` |
| recovery hierarchy (source) | `test/features/ux_home_recovery_test.dart` |
| empty history CTA | `test/features/ux_history_detail_widget_test.dart` |
| detail delete routing | 동일 |
| timeline user copy | `timeline_copy_test.dart`, `ux_history_detail_structure_test.dart` |
| intro CTA | `test/features/intro_screen_test.dart` |
| open settings spy | `test/features/ux_open_settings_test.dart` |
| map empty overlay | `test/widget/route_map_test.dart` |

---

## 5. 변경 이력

| 버전 | 일자 | 내용 |
|------|------|------|
| 1.0 | 2026-07-12 | 초안 검토 + 1차 수정 표 |
| 2.0 | 2026-07-13 | 전 화면 재검토; H06/H07/D04 등 major 추가 수정; multi-axis 문서화 |
