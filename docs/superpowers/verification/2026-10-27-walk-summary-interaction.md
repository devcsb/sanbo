# 산책 요약과 주간 기록 전환 검증

설계는 [승인 설계](../specs/2026-10-26-walk-summary-interaction-design.md), 작업 범위는
[구현 계획](../plans/2026-10-27-walk-summary-interaction.md)을 따른다.
구현 기준 HEAD는 `99ab8b8`, 회귀 검토 기준은 `aad33d8`이다.

## 구현에서 구체화한 경계

- 시간 범위는 `[start, end)`로 해석한다. 정확히 자정에 종료한 산책은 마지막 포함
  시각이 속한 날짜와 주를 선택한다. 원본 종료 시각과 전주 같은 현지 시각 비교는
  바꾸지 않는다. DST 비교에 고정 168시간을 빼지 않는다.
- 저장된 이동 초는 기존 `positiveDurationSeconds` 상한으로 검증한다. 9.9초 관측에
  반올림 저장값 10초가 있는 정상 기록을 floor 상한 때문에 버리지 않는다.
- 전주에 유효한 기록이 없으면 이동하지 않았다고 가정하지 않고 비교를 생략한다.
- 주간 기록 보기는 합계에 포함한 실제 세션 목록과 누락 세션 진입을 제공한다.
- 상세 상단 섹션은 단일 ListView 콘텐츠 안에서 유지한다. 기존 활동 목록도 모든
  구간을 한 Column으로 만들었다. 추가로 유지하는 대상은 고정 수 상단 섹션이며,
  스크롤 중 메모와 구간 링크 대상이 사라지는 것을 막는다.

## 구현자 검증

최종 focused 명령은 아래와 같다. 60개 테스트가 모두 통과했다.

```sh
flutter test test/domain/session_week_summary_test.dart test/data/session_week_summary_test.dart test/widget/route_map_test.dart test/features/session_route_screen_test.dart test/features/session_summary_panels_test.dart test/features/session_summary_flow_test.dart test/features/route_playback_flow_test.dart test/features/ux_history_detail_widget_test.dart test/features/ux_history_detail_structure_test.dart test/data/exclusion_boundary_integration_test.dart
flutter analyze
```

변경 Dart 파일 14개에 `dart format`을 실행했다. `git diff --check`는 오류가 없었다.
`flutter analyze`는 `No issues found!`로 종료했다(2.2초). 전체 suite와 debug APK는 구현자가
중복 실행하지 않았으며 조율자가 `bash scripts/run_quality_loop.sh --debug-apk`로 확인한다.

## 반례와 실패 이력

- 새 집계/지도/패널 테스트는 구현이 없는 실패를 확인한 뒤 구현했다.
- 자정 종료 주 선택과 9.9초 기록의 10초 저장값 반례가 처음 실패했고 경계 계산을 수정했다.
- TextField의 방향키가 패널을 바꾸던 반례가 실패한 뒤, 키 처리를 탭 초점에 제한했다.
- sessionId 변경 시 이전/새 AnimatedSwitcher 자식이 같은 GlobalKey를 유지하던
  실패를 확인했다. sessionId별 switcher identity로 기존 화면을 분리했다.
- historyTick 갱신 중 전체 loading으로 바뀌던 반례를 확인하고 기존 상세를 유지하되
  주간 새 확정값은 상세 로딩이 끝날 때까지 표시하지 않는다.
- focused 1차 최종 묶음은 57개 통과, 2개 실패였다. 이동한 metric의 lazy dispose와
  아직 mount되지 않은 구간 링크 대상 문제였다. 단일 콘텐츠 유지로 수정했다.
- 초기 analyze의 스타일 정보 11건은 해당 변경 파일에서 수정했고 최종 분석은 통과했다.
- 단위 문구/세션 정렬 수정 후 테스트 1건이 같은 `20초`를 세 위치에서 발견해 실패했다.
  이번 산책/주간 합계/요일 값의 세 표시를 명시적으로 확인하도록 고친 최종 묶음은 60개 통과했다.
- 테스트 harness에서는 ensureVisible 직후 레이아웃 pump 누락, `05:00` 표시를 `5:00`으로
  기대한 오류, SemanticsHandle 해제 누락을 수정했다. 제품 동작 assertion은 유지했다.

## 검증 범위와 남은 한계

자동 테스트는 주 경계/DST/레거시 wall clock/null과 음수/중복 ID/이번 산책 중복 합산 방지,
미래 기록/전주 cutoff를 가로지른 합계/기존 dailyStats 소요시간 의미를 다룬다.
주간 조회 실패에서도 상세 수정/메모/반출 진입을 유지하고, 탭 전환과 지도 복귀가 주간
재조회 횟수를 늘리지 않는지 확인한다. 지도 인증/전송/코덱 오류의 경로 보존은 기존
RouteMap 테스트로 다루며 외부 타일은 offline/mock이다.

패널 검증은 탭/스와이프/반전 취소/세로 스크롤, 키보드와 선택 semantics, 48px 버튼,
320px 100/160/200%, 가로/다크/reduce-motion을 다룬다. 실제 상세는 320px 200%의
라이트/다크에서 loading/partial/empty와 누락 기록 접근을 확인한다. 주간 화면에서
재생을 멈추고 커서를 유지하며, 구간 선택과 기존 편집/제외/복원을 보존한다.
긴 활동 90개에서도 안내 링크가 헤더와 첫 구간을 화면에 보이게 하는지 검사한다.

실제 기기 터치, OS TalkBack/VoiceOver, 지도 인증 성공, GPS와 배터리 영향은
이번 검증으로 증명하지 않았다. 원격 push와 릴리즈는 이번 실행 범위에 포함하지 않았다.

## 최종 교차 검토와 통합 검증

조율자가 `aad33d8` 기준 변경을 별도로 검토했다. 주간 집계는 읽기 전용이며
저장된 이동 시간, 원본 좌표와 사용자 라벨을 바꾸지 않는다. 기존 재생, 제외/복원,
장소와 메모 저장, 반출 기능은 전체 회귀 검사에서 유지했다.

독립 화면 검토에서 큰 지도 pop 직후와 50ms 후에 지도 위젯이 2개 존재하는 것을
확인했다. `Navigator.push` 반환은 종료 애니메이션의 완료가 아니므로 `route.completed`
까지 기다린 뒤 미리보기를 복원하도록 수정했다. 구현자 RED/GREEN 테스트 외에
조율자의 별도 캡처 실행에서도 두 시점 모두 지도 1개를 확인했다.

처음 시작한 전체 게이트는 위 수명주기 반례를 수정하기 위해 중단했고 완료 근거로
사용하지 않았다. 수정 후 전체 suite는 600개 통과, 기존 장소 저장 테스트 1개 실패였다.
화면 밖 편집 버튼을 누르던 테스트를 실제 버튼의 `ensureVisible`/`hitTestable` 검사로
수정하고, 저장 모달이 닫힌 뒤 상세를 확인하도록 했다. 기존 장소 제안/저장/DB
검증은 유지했다. 관련 파일 2개 테스트가 통과한 뒤 아래 전체 게이트를 다시 실행했다.

```sh
env -u CARTO_BASEMAP_KEY bash scripts/run_quality_loop.sh --debug-apk
```

최종 실행 로그는 로컬 `build/walk-summary-quality-complete.log`다.
종료 코드 0과 다음 완료 문구를 직접 확인했다. 실행 중 소스 변경도 없었다.

| 검사 | 결과 |
|---|---|
| 기존 PRD/TRD 구조 | PASS |
| Android 반출/비공개 빌드 도구 | Python 테스트 21개 통과 |
| Dart 정적 분석 | No issues found |
| Flutter 전체 회귀 | 601개 통과, 1분 11초 |
| Android debug APK | assembleDebug 31.6초, APK 생성 |
| 변경 공백/작업 트리 일관성 | PASS |

APK는 `build/app/outputs/flutter-apk/app-debug.apk`이며 SHA-256은
`2d263afbd04c4661fe162fa9e0af3d106ee7644459bb368316a6d4361b12b080`이다.
CARTO 키를 전달하지 않은 debug 검증용 산출물이다. Java 8 source/target 관련 기존
도구 경고가 있었으며 빌드는 성공했다. 릴리즈 서명/배포나 실제 지도 인증 성공의
증거로 사용하지 않는다.

## Flutter 화면 확인

합성 기록과 실제 `AppTheme`, 실제 상세 위젯을 사용해 390px 폭으로 렌더링했다.
테스트 실행기의 기본 사각형 글꼴 대신 로컬 한글/아이콘 글꼴을 캡처에만 로드했다.
제품의 글꼴/의존성/타일 설정은 변경하지 않았다.

- `build/summary-app-route.png`: 완료 문구, 날짜, 거리/시간, 평균, 경로 미리보기.
- `build/summary-app-week.png`: 주간 합계, 이번 산책 기여, 실제 요일 값과 기록 진입.

문구가 카드에 붙고 마지막 글자만 줄바꿈되던 배치를 캡처에서 발견해 완료 안내 아래로
옮기고 12px 간격과 명시적 문장 줄바꿈을 적용했다. 중복 시작 시각도 제거했다.
새로 추가한 배치 회귀를 포함해 영향 테스트 25개가 통과했다. 캡처용 임시 코드는
Flutter 기본 golden 출력 경로를 사용하며, 생성된 이미지의 모양은 직접 확인했다.
이 캡처는 합성 자료이고 지도는 offline 상태다. 실기기/실제 네트워크 검증은 아니다.
