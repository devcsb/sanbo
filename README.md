<div align="center">

<img src="https://img.shields.io/badge/Flutter-3.44-02569B?style=flat-square&logo=flutter&logoColor=white" />
<img src="https://img.shields.io/badge/Dart-3.12-0175C2?style=flat-square&logo=dart&logoColor=white" />
<img src="https://img.shields.io/badge/Android-API%2024+-3DDC84?style=flat-square&logo=android&logoColor=white" />
<img src="https://img.shields.io/badge/License-MIT-yellow?style=flat-square" />

# 산보 (Sanbo)

**산책의 ‘그때 그 1분’을 남기는 위치 기반 개인 로그**

*러닝 워치가 아니라, 동선 · 속도 · 장소 · 활동 추정으로 회상하는 가벼운 산책 앱*

[**기능 소개**](#주요-기능) · [설치](#설치) · [버그 리포트](../../issues)

</div>

---

## 왜 산보인가?

산책을 끝내고 맵 앱을 열어 보면, **파란 선 하나**만 남는 경우가 많습니다.

- 카페에 들렀는지  
- 강변을 빠르게 걸었는지  
- 벤치에서 10분 쉬었는지  

총 거리와 페이스만으로는 **“그때 내가 무엇을 했는지”** 를 되살리기 어렵습니다.

**산보**는 달리기의 스플릿이 아니라, **분(minute) 단위 시간 창**으로 동선을 나누고, 속도·정지·장소 신호를 모아 **활동 추정(가설)** 을 남깁니다. 틀리면 탭해서 고치면 됩니다.

```
시작  →  걷고 · 멈추고 · 머무름  →  종료
              ↓
     분 타임라인 + 추정 활동 + 공개 지도 경로
```

---

## 주요 기능

### 🚶 심플한 시작 / 종료
- 큰 **산책 시작** 버튼 하나로 기록 시작  
- 진행 중 **시간 · 거리 · 속도** 한눈에  
- **산책 종료** 후 요약 화면으로 바로 이동  
- Android 포그라운드 알림으로 백그라운드에서도 수집 유지  

### ⏱️ 분 단위 타임라인
- 벽시계 기준 **1분 윈도우**로 동선 집계  
- 구간별 거리 · 속도 · 정지 비율  
- GPS 공백 구간은 **빈 구간**으로 정직하게 표시  

### 🧠 활동 추정 (가설)
- 걷기 / 빠른 걷기 / 체류 / 카페·상점 추정 등  
- UI에는 **「추정」** 카피 — AI 확정 표현 없음  
- 탭해서 **수정 · 확정** 가능 (사용자 라벨 우선)  

### 🗺️ 공개 지도 경로
- **OpenStreetMap** 공개 타일 + 폴리라인  
- 상용 맵 SDK 종속을 기본 경로로 두지 않음  
- 저작권 attribution 표시  

### 🔒 프라이버시 우선
- **로컬 SQLite** 저장, 계정 · 서버 업로드 없음 (MVP)  
- 세션 / 전체 기록 삭제  
- 위치는 산책 **세션 중에만** 수집 (상시 추적 아님)  

### ♻️ 미완료 산책 복구
- 앱이 비정상 종료되어도 미완료 세션 안내  
- 이어서 기록 · 저장 후 종료 · 삭제(확인 다이얼로그)  

---

## 기술 스택

| 영역 | 선택 |
|------|------|
| UI | Flutter (Material 3), Android 우선 |
| 상태 · 라우팅 | [flutter_riverpod](https://riverpod.dev) · [go_router](https://pub.dev/packages/go_router) |
| 위치 | [geolocator](https://pub.dev/packages/geolocator) + Android FGS 알림 |
| 저장 | [sqflite](https://pub.dev/packages/sqflite) (온디바이스) |
| 지도 | [flutter_map](https://pub.dev/packages/flutter_map) + OSM 타일 |
| 설계 문서 | `docs/PRD.md` · `TRD.md` · `PLATFORM_AND_MAPS.md` · `UX_REVIEW.md` |

---

## 설치

### 직접 빌드 (Android)

**요구 사항**
- Flutter 3.44+ / Dart 3.12+  
- Android SDK (API 24+, JDK 17)  

```bash
# 1. 저장소 클론
git clone https://github.com/devcsb/sanbo.git
cd sanbo

# 2. 의존성
flutter pub get

# 3. 실행 (연결된 기기 / 에뮬레이터)
flutter run

# 4. 디버그 APK
flutter build apk --debug

# 5. 릴리스 APK (선택)
flutter build apk --release --split-per-abi
```

산출물 예:
```text
build/app/outputs/flutter-apk/app-debug.apk
```

USB 디버깅이 켜진 폰:

```bash
adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb shell am start -n com.sanbo.sanbo/.MainActivity
```

### 권한

| 권한 | 용도 |
|------|------|
| 위치 (정밀) | 산책 경로 기록 |
| 알림 / 포그라운드 서비스 | 화면 꺼짐·백그라운드 중 수집 유지 |

거부 시에도 앱은 크래시하지 않고, 다음에 할 일을 안내합니다.

---

## 사용법 (30초)

1. **홈**에서 **산책 시작** → 위치 권한 허용  
2. 평소처럼 산책 (알림: “산보 · 산책 경로를 기록 중”)  
3. **산책 종료** → 요약 카드 · 지도 경로 · 분 타임라인  
4. 틀린 활동 추정은 탭해서 수정 · 확정  
5. **기록** 탭에서 과거 세션 다시 보기 · 삭제  

설정에서 추적 모드(절전 / 균형 / 고정확)와 베이스맵 표기를 바꿀 수 있습니다.

---

## 프로젝트 구조

```
lib/
├── app/                 # bootstrap, go_router (홈 · 기록 · 설정)
├── core/theme/          # Material 3 테마
├── domain/              # 순수 Dart: 필터 · 분 윈도우 · 활동 추정 · 롤업
├── data/                # WalkRepository (sqflite)
├── platform/            # LocationEngine, 지도 타일 소스
├── features/
│   ├── home/            # 시작/종료 · 복구 · 권한 UX
│   ├── history/         # 세션 목록 · 빈 상태
│   ├── session_detail/  # 맵 · 요약 · 타임라인
│   └── settings/        # 모드 · 지도 · 데이터 삭제
└── shared/widgets/      # 하단 탭, RouteMap
docs/                    # PRD / TRD / 플랫폼·지도 / UX 검토
test/                    # 단위 · e2e · UX 회귀
```

---

## 개발 · 테스트

```bash
flutter pub get
flutter analyze
flutter test --concurrency=1
```

핵심 검증 포인트:
- 분 윈도우 집계 (UTC GPS 타임스탬프 → 로컬 분 경계)
- 권한 거부 시 추적 미시작
- 시작 → 합성 위치 → 종료 → 영속 · 라벨 수정 e2e  
- 빈 기록 CTA · 상세 삭제 후 목록 이동 · 미완료 삭제 확인  

---

## 로드맵

| 단계 | 내용 | 상태 |
|------|------|------|
| MVP | 세션 추적 · 분 윈도우 · 추정 · OSM 맵 · 로컬 저장 | ✅ |
| UX | 복구 카드 · busy CTA · 추정 카피 · 빈 상태 | ✅ |
| v1 | 브이월드 타일/검색 키 연동, NDJSON export 강화 | 🔜 |
| Later | iOS, 온디바이스 ML, 일기 연동 | 🔜 |

---

## 기여

이슈와 PR을 환영합니다. 개인 사이드 프로젝트이지만, 산책 로그 UX에 관심 있으면 편하게 열어 주세요.

```bash
git checkout -b feat/your-feature
flutter test --concurrency=1
# PR 생성
```

---

## 라이선스

[MIT License](LICENSE)

---

<div align="center">

Made for quiet walks · by [devcsb](https://github.com/devcsb)

</div>
