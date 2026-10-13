# 산보 1차 유지보수 설계, 백업과 측정 표시 일관성

| 항목 | 내용 |
|---|---|
| 상태 | 사용자 검토용. 구현 계획 작성과 제품 코드 수정 전 |
| 작성일 | 2026-10-13 |
| 기준 코드 | `v0.9.1` / `1368d45` |
| 후보 버전 | `0.9.2+16`, 구현 완료와 release gate 통과 후 확정 |
| 요구 | [PRD MR-01~07](../../PRD_MAINTENANCE_2026-10.md), [TRD](../../TRD_MAINTENANCE_2026-10.md) |
| 조사 근거 | [유지보수 검토](../verification/2026-10-13-maintenance-audit.md) |

## 1. 의도와 성공 기준

사용자가 원하는 결과는 과거 개발을 배포 상태와 대조하고, 산보를 신뢰할 수 있게
유지보수하는 것이다. 산책 회상이라는 목적과 Android 우선 배포, 로컬 저장,
사용자 수정/제외 복원, 기존 기록 보존을 유지한다.

이번 단위 작업은 모바일 백업 내보내기, 복구 거리, 현재 속도 최신성, 재생 시각,
완료 export, 건강 데이터 오류 안내를 바로잡는다. 거리/정지 판정의 새 알고리즘과
고속 자동 제외 기준 변경은 별도의 측정 설계로 진행한다. 새 사용자 선택이 필요한
측정 정책과 재현된 구현 오류를 한 번에 섞지 않기 위해 범위를 나눴다.

성공하면 Android/iOS에서 백업 파일을 외부에 저장할 수 있고, 같은 필터 경로의
복구/완료 거리가 일치하며, 오래된 GPS 속도를 현재 속도처럼 표시하지 않는다.
산책 당시 시간대와 완료 속도 계산식을 UI와 export가 함께 사용한다.

## 2. 선택한 접근과 대안

추천안은 기존 경계를 재사용하는 수정이다. `RoutePartitioner`,
`completedAverageSpeedMps`, `asLocal`, `BackupFileService`, native channel 패턴을
활용한다. 새 서버나 제품 dependency를 추가하지 않고 기본 세 화면을 유지한다.

대안인 화면 문구만 수정하는 방법은 백업 실패와 거리 불일치를 남긴다.
controller/repository 전체 재작성은 2천 줄 이상의 기존 복구/저장 로직에 큰
회귀 범위를 만든다. 필요한 부분을 고치고 향후 측정 reducer 도입 때 관련
책임만 분리하는 편이 이번 목적에 맞다.

## 3. 구성과 책임

### 모바일 파일 저장

Flutter 파일 서비스는 직렬화된 백업 bytes를 앱 임시 폴더에 쓰고 native에 경로와
파일 이름을 전달한다. Native는 Android 시스템 문서 생성과 iOS 파일 export를
실행한다. 사용자의 저장 완료 callback 이후에만 대상 URI/URL을 반환한다.

기존 `save`의 null 취소와 exception 실패 계약, 설정 busy 상태를 유지한다.
플랫폼 서비스가 파일 저장의 책임을 지고, `WalkRepository`는 계속 JSON snapshot과
merge transaction만 담당한다. 원본 DB와 전체 백업 v2는 바뀌지 않는다.

다른 앱의 파일 접근, 공유 서비스 업로드, 범용 파일 관리 기능은 추가하지 않는다.
사용자는 시스템 picker에서 직접 저장 위치를 고른다.

### 복구 측정

복구 시 필터 표시를 가진 목록을 유지한 채 공통 RoutePartitioner에 넘긴다.
제외된 좌표/시간 공백을 연결하지 않고 같은 거리 하한으로 합계한다.
복구 직후의 새 위치 역시 마지막 필터 경계를 넘지 않아야 한다.
일반 GPS callback의 기존 O(1) 처리는 유지한다.

### 현재 속도 표시

숫자와 availability를 분리한다. 현재 속도는 최신 유효 위치와 속도 근거가 있을
때만 표시한다. 첫 위치 전과 근거 없는 첫 단일 좌표는 측정 대기, 유효한 정지
관측은 0km/h, 30초 초과 공백은 측정 중단이다. 수신했지만 거절한 좌표는
신선도를 갱신하지 않는다.

전면에서는 기존 ticker를 재사용하고, resume에서 clock과 마지막 유효 instant를
대조한다. 백그라운드에 UI 전용 timer를 더하지 않는다. elapsed-only state 갱신이
statusMessage를 지우지 않도록 함께 고친다. 저장된 기록에 새 표시 상태를 넣지 않는다.

### 시간대, export, 건강 데이터

저장 instant는 UTC다. 재생 컨트롤 전체와 접근성 안내는 session.timezone으로
변환한 값을 표시한다. 기기 시간대와 세션 시간대를 혼동하지 않는다.

완료 JSON/NDJSON의 평균 속도도 거리/이동 시간 helper를 쓴다. 계산 불가 시 null로
표현하며 백업의 원본 영속 상태를 임의로 바꾸지 않는다.

건강 데이터는 source와 coverage를 함께 사용해 미연결, 권한 필요, 조회 오류,
일부 기간, 유효 0걸음을 구분한다. iOS에서 동작하지 않는 Health Connect 설정
버튼을 노출하지 않는다. settings capability에 사용 가능 여부를 명시해 공통 UI가
존재만으로 지원을 추정하지 않게 한다. 기존 Android 설정 복귀 cache invalidation은 유지한다.

## 4. 데이터 흐름과 오류 처리

```text
backup snapshot -> temporary file -> native picker -> output copied/closed
                                                     |
                                            success / cancel / error
                                                     |
                                  user feedback + temporary-file cleanup

stored samples with filter flags -> shared route fragments -> recovery totals
latest usable fix + clock -> speed availability -> UI and accessibility copy
UTC sample + session IANA zone -> all playback labels
completed distance / moving time -> UI, human summary, JSON, NDJSON
health source + coverage + settings availability -> value and recovery action
```

- 저장 장소 선택 취소는 오류 알림이나 성공 알림을 만들지 않는다.
- 파일 복사/쓰기 오류는 재시도 가능한 저장 실패다. 원본 산책을 변경하지 않는다.
- 파일 picker가 닫히거나 Activity가 재생성되면 pending native 응답을 성공으로
  처리하지 않고 취소/실패로 끝낸다. 기존 channel readiness 세대 관리와 분리한다.
- native 경계에서 임시 export 폴더 밖의 경로와 경로가 포함된 파일 이름을 거부한다.
- 임시 파일 정리는 native 복사가 끝난 뒤 처리한다. 전체 JSON을 native channel로
  복사하지 않아 대형 백업의 메모리 복제를 줄인다.
- GPS 공백에도 elapsed와 저장된 거리는 유지한다. 속도 불가를 관측 정지로 바꾸지 않는다.
- 잘못된 IANA zone은 기존 `asLocal` fallback을 사용하며 경로 계산을 막지 않는다.
- 건강 데이터 조회 실패는 GPS 세션, 기록 목록, 정상 날짜 데이터를 막지 않는다.

## 5. 예상 변경 경계

| 경계 | 예상 대상 |
|---|---|
| Flutter 파일 서비스 | `lib/platform/backup/backup_file_service.dart`, 모바일 native bridge와 adapter 테스트 |
| Android 문서 저장 | MainActivity 연동 및 별도 작은 export handler, native contract 테스트 |
| iOS 문서 저장 | AppDelegate 연동 및 작은 picker delegate, native contract 테스트 |
| 복구/현재 속도 | `session_controller.dart`, HomeScreen, controller 및 widget 회귀 |
| 재생 시각 | `session_detail_screen.dart`, route playback widget 회귀 |
| 완료 export | `session_export.dart`, export unit tests |
| Health 표시 | DailyActivityPanel, 기존 settings capability 및 fake contract |
| 릴리즈 | pubspec/AppInfo/notes/품질 script/배포 증적 |

이 변경은 여러 파일과 모바일 인터페이스를 다룬다. 작성된 설계와 구현 계획을
사용자가 검토하는 단계가 필요하다. 실행은 현재 Codex 실행자가 맡고 재위임하지 않는다.

## 6. 테스트와 수용 게이트

| 시나리오 | 기대 결과 |
|---|---|
| actual mobile save adapter | 지원되지 않는 file_selector save API를 호출하지 않음 |
| 파일 저장 완료/취소/쓰기 실패 | 실제 외부 파일, null 취소, 저장 실패를 구분. fake UI 성공만으로 판정하지 않음 |
| 백업 왕복 | 원본/제외/라벨/장소 보존, duplicate skip 및 import rollback 유지 |
| 10m -> filtered -> 20m 구간 | 복구 및 완료 거리 모두 10m, 새 위치로 filtered 경계 연결 안 함 |
| 위치 30초/30초 초과 | 경계 포함 최신/이후 stale. fresh 정지 0은 숫자로 표시 |
| 첫 좌표만 수신, rejected callback, resume | 속도 근거/신선도 없는 숫자를 표시하지 않음 |
| 서울 09시 UTC 샘플 | 재생/양 끝/접근성 모두 09시. DST fold 및 다른 기기 zone도 같은 순간 |
| 저장 평균 9, 거리/시간 100/100 | human/JSON/NDJSON 평균 1m/s. 0/결측/non-finite는 계산 불가 |
| Health 오류 및 iOS 화면 | 미연결과 구분, 재조회 CTA, iOS에 Android 전용 설정 버튼 없음 |
| 전면/백그라운드 전환 | ticker 중단/재개 유지, foreground 1회 최신 snapshot |

새 동작을 요구하는 테스트가 기존 코드에서 실패하는지 확인한 후 수정한다.
전체 Flutter 테스트/analyzer, Android/iOS native tests, Android debug/release 빌드,
문서 검증과 patch 검사를 변경된 revision에서 실행한다. 새 build가 기존과 같은
서명을 쓰고 versionCode가 증가하는지 확인한다.

물리 기기가 없는 검증은 simulator/emulator 결과로만 기록한다. GitHub 게시,
Google Play 게시, 실기기 GPS 정확도는 각각 별도 종료 조건이다. 기존 v0.9.1
checksum을 새 버전의 증거로 재사용하지 않는다.

## 7. 후속 작업과 이번 범위 밖

- GPS 노이즈 억제와 작은 연속 변위 보존, 지속성 기반 자동 제외는 독립 측정
  설계를 작성한다. 현재 자동 제외 설정에 대한 사용자 선택도 그 설계에 반영한다.
- 관측 이동/정지/결측 시간, 병합 평균 분모와 과거 계산 버전 migration은 해당
  설계에서 함께 다룬다.
- 날짜 칩 선택 가시성, 중복 접근성 버튼 후보는 추가 UI 회귀와 함께 후속 반영한다.
- Health Connect 정책 화면/Android 14 alias와 스토어 identity는 스토어 준비
  단위 작업으로 진행한다. 정책 화면 누락 상태를 스토어 준비 완료로 표시하지 않는다.
- 광범위 controller/repository 분할, map SDK 교체, SDK 업그레이드, 서버 도입,
  측정 간격/권한 상한 완화는 이번 1차 범위 밖이다.

## 8. 현재 단계

- [x] 사용자 의도와 기존 제품 경계 확인
- [x] 과거 작업, 태그, 공개 release, binary hash 대조
- [x] 기존 전체 품질 gate와 모바일 네이티브/빌드 검증
- [x] 측정/백업 오류 재현, 실제 iOS 화면 검토
- [x] PRD, TRD, 1차 설계 문서 작성
- [x] 문서 요구 추적, 내부 모순, 링크와 미완성 항목 검사
- [ ] 사용자 written-spec 검토
- [ ] written-spec 승인 후 구현 계획 작성, 계획 검토와 실행 방식 선택
- [ ] 수정 구현 및 새 revision 검증
- [ ] 새 릴리즈 게시 단계 검토
