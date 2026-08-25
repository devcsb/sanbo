<div align="center">

<img src="assets/branding/sanbo-main.jpg" alt="sanbo — 작은 기록, 큰 흐름" width="720" />

<br/>

<img src="https://img.shields.io/badge/Flutter-3.47-02569B?style=flat-square&logo=flutter&logoColor=white" />
<img src="https://img.shields.io/badge/Dart-3.12-0175C2?style=flat-square&logo=dart&logoColor=white" />
<img src="https://img.shields.io/badge/Android-API%2024+-3DDC84?style=flat-square&logo=android&logoColor=white" />
<img src="https://img.shields.io/badge/License-MIT-yellow?style=flat-square" />

# 산보 (sanbo)

**작은 기록, 큰 흐름**

산책의 ‘그때 그 1분’을 남기는 위치 기반 개인 로그

*러닝 워치가 아니라, 동선 · 속도 · 장소 · 활동 추정으로 회상하는 가벼운 산책 앱*

[**기능 소개**](#주요-기능) · [설치](#설치) · [버그 리포트](../../issues)

<img src="assets/branding/sanbo-icon.png" alt="sanbo app icon" width="96" />

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
- 한 장소에 20분 머물면 안내, 30분이면 자동 저장·종료
- 4시간 45분에 종료 예고, 5시간이면 자동 저장·종료

### ⏱️ 분 단위 타임라인
- 벽시계 기준 **1분 윈도우**로 동선 집계  
- 구간별 거리 · 속도 · 정지 비율  
- GPS 공백 구간은 **빈 구간**으로 정직하게 표시
- 구간을 탭하면 해당 시각과 동선을 지도에서 강조
- 구간 보기와 활동·장소 편집 버튼을 분리해 오조작 방지

### 🧠 활동 추정 (가설)
- 걷기 / 빠른 걷기 / 체류 / 카페·상점 추정 등  
- UI에는 **「추정」** 카피 — AI 확정 표현 없음  
- 탭해서 **수정 · 확정** 가능 (사용자 라벨 우선)  

### 📍 장소 기억
- 체류 구간에 `동네 카페`, `강변 벤치`처럼 직접 이름 저장
- 다음 산책의 가까운 체류 지점에서 저장된 이름을 로컬로 재사용
- 사용자가 요청할 때만 기기 주소 서비스로 주소 제안
- 외부 지오코더 자동·배치 호출 없음

### 🗺️ 공개 지도 경로
- **OpenStreetMap** 공개 타일(Carto Voyager) + 폴리라인 — **API 키 불필요**  
- 상용 맵 SDK · 브이월드 키 연동 없음  
- 저작권 attribution 표시 (`© OpenStreetMap · © CARTO`)
- 시간 슬라이더와 재생 버튼으로 경로·현재 활동·장소를 함께 회상

### 🔒 프라이버시 우선
- **로컬 SQLite** 저장, 계정 · 서버 업로드 없음 (MVP)  
- Android 클라우드 백업·기기 이전에서 위치 기록 제외
- 앱 업데이트에는 로컬 기록 유지; 앱 삭제·기기 변경 전 수동 전체 백업 지원
- 버전이 있는 `.sanbo` 전체 백업 내보내기·병합 가져오기 (중복 산책 건너뛰기)
- 세션 / 전체 기록 삭제  
- 위치는 산책 **세션 중에만** 수집 (상시 추적 아님)  
- 장소 이름과 주소도 로컬 SQLite에만 저장

### ♻️ 미완료 산책 복구
- 앱이 비정상 종료되어도 미완료 세션 안내  
- 이어서 기록 · 저장 후 종료 · 삭제(확인 다이얼로그)  

### ✨ 조용한 이정표 · 메모 · 내보내기
- **나의 흐름**: 산책 횟수 · 누적 거리 · 최장 시간 (경쟁 없는 개인 이정표)  
- **일별 운동량**: 기록 화면에서 최근 7일을 넘겨 보며 선택한 날짜의 총거리 · 총시간 · 산책 횟수 확인 (완료 산책의 시작일 기준)
- 산책 종료 시 새로 열린 이정표만 짧게 안내  
- 세션 **메모** (로컬 전용)  
- 요약 **클립보드 복사** · **NDJSON 내보내기** (FR-16)  
- 설정에서 모든 산책·원본 경로·수정 내용·장소를 파일로 백업·복원
- 시작/종료 가벼운 햅틱  

---

## 기술 스택

| 영역 | 선택 |
|------|------|
| UI | Flutter (Material 3), Android 우선 |
| 상태 · 라우팅 | [flutter_riverpod](https://riverpod.dev) · [go_router](https://pub.dev/packages/go_router) |
| 위치 | [geolocator](https://pub.dev/packages/geolocator) + Android FGS 알림 |
| 저장 | [sqflite](https://pub.dev/packages/sqflite) (온디바이스) |
| 지도 | [flutter_map](https://pub.dev/packages/flutter_map) + OSM 타일 |
| 설계 문서 | `docs/PRD.md` · `TRD.md` · `PLATFORM_AND_MAPS.md` · `UX_REVIEW.md` · `QUALITY_REVIEW_0.7.md` |

---

## 설치

### 직접 빌드 (Android)

**요구 사항**
- Flutter 3.47.1+ / Dart 3.12.2+
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

# 5. 릴리스 APK는 아래 서명 설정 후 빌드
flutter build apk --release --split-per-abi
```

산출물 예:
```text
build/app/outputs/flutter-apk/app-arm64-v8a-release.apk   # 갤럭시 등
build/app/outputs/flutter-apk/app-debug.apk
```

디버그 APK는 개발·테스트용이며 배포용 릴리스가 아닙니다. 릴리스 빌드는
`android/key.properties`에 지정한 키만 사용하고, 키 설정이 없으면 의도적으로
실패합니다. 기존 배포 앱을 업데이트하려면 반드시 기존 배포본과 같은 서명
인증서를 사용해야 합니다.

```bash
keytool -genkeypair -v -keystore upload-keystore.jks -keyalg RSA \
  -keysize 2048 -validity 10000 -alias upload
cp android/key.properties.example android/key.properties
# android/key.properties의 경로·비밀번호를 실제 값으로 변경
flutter build appbundle --release
```

`android/key.properties`와 키스토어는 Git에서 제외됩니다. 저장·키 비밀번호는
`SANBO_RELEASE_STORE_PASSWORD`와 `SANBO_RELEASE_KEY_PASSWORD` 환경 변수로도
주입할 수 있습니다. macOS의 품질 스크립트는 `sanbo-release-keystore`라는 Keychain
항목이 있으면 비밀번호를 출력하지 않고 사용합니다. 키스토어는 접근 권한을 제한하고
암호화된 별도 백업을 유지하세요. 키를 잃으면 이후 업데이트 배포가 어려워질 수 있습니다.

### 지도

베이스맵은 **OpenStreetMap** 데이터(CARTO 타일)만 사용합니다. 별도 API 키·브이월드 연동은 없습니다.
산책 원본 좌표를 업로드하지는 않지만, 지도를 열면 표시 영역에 해당하는 타일 좌표와
IP 등 네트워크 정보가 CARTO에 전달될 수 있습니다. 지도 타일을 불러오지 못해도 GPS 기록과
로컬 저장은 계속 동작합니다.

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
4. 타임라인 구간을 탭해 지도에서 보고, 편집 버튼으로 활동·장소 수정
5. **기록** 탭에서 최근 7일 일별 운동량과 과거 세션 다시 보기 · 삭제

설정에서 추적 모드(절전 20초 / 균형 8초 / 정밀 4초)를 바꾸고 전체 백업을
내보내거나 가져올 수 있습니다. 백업 파일에는 정밀 위치가 있으므로 공유에
주의하세요.

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
│   ├── history/         # 세션 목록 · 일별 운동량 · 빈 상태
│   ├── session_detail/  # 맵 · 요약 · 타임라인
│   └── settings/        # 모드 · 지도 · 전체 백업/복원 · 데이터 삭제
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
| 0.2.0 | OSM 전용 지도 · 카피/설정 UX 정리 · 브이월드 제거 | ✅ |
| 0.3.0 | 전 화면 디자인 시스템 · 반응형/접근성 · 설정 안전성 강화 | ✅ |
| 0.3.1 | 개인 이정표 · 메모 · 요약 복사 · NDJSON export · 햅틱 | ✅ |
| 0.3.3 | GPS 전력 최적화 · 장기 정지/세션 자동 종료 알림 | ✅ |
| 0.4.0 | 체류 장소 이름 · 기기 주소 제안 · 로컬 장소 재사용 | ✅ |
| 0.5.0 | 지도–타임라인 연동 · 경로 슬라이더/재생 · 선택 구간 강조 | ✅ |
| 0.6.0 | 전체 백업/병합 복원 · DB 무결성/마이그레이션 검증 · 백그라운드 UI 절전 · 릴리스 서명 안전장치 | ✅ |
| 0.7.0 | 0.4–0.6 기능 통합 정식 릴리스 · 기존 설치 업데이트 호환 · 릴리스 산출물 검증 | ✅ |
| 0.7.1 | 장기 기록 저장 복구 · GPS gap 통계 · 대용량 백업 응답성 · 릴리스 서명/manifest 게이트 강화 | ✅ |
| 0.7.2 | 기록 화면 최근 7일 일별 운동량 API·UI · 장시간 GPS 거리·속도 보정 · 5시간 세션 자동 종료 정책 | ✅ |
| 0.8.0 | 고속 이동 종료 확인·알림 · 완료 기록 구간 제외/복원 · 위치 스트림·알림 복구 강화 · iOS 알림 탭 경로 정비 | ✅ |
| v1 | 공유 시트 · GPX 내보내기 · POI 카테고리 | 🔜 |
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
