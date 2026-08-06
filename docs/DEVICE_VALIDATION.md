# 산보 실기기 검증 프로토콜

코드 테스트만으로는 GPS provider, 제조사 절전 정책, 화면 상태에 따른 배터리 사용량을 확정할 수 없다. 이 문서는 같은 조건으로 반복 측정하기 위한 증거 수집 절차다.

## 대상과 고정 조건

- 대상: Samsung Galaxy 실기기 1대 이상, Android 13 이상
- 앱: 같은 release APK, 같은 application data 상태
- 네트워크: Wi‑Fi/모바일 네트워크 조건을 기록하고 한 루프에서는 고정
- 장소: 하늘이 열린 동일한 야외 1 km 이상 왕복 경로
- 시작 배터리: 80% 이상, 충전기 연결 금지
- 화면: 각 테스트에서 `화면 켬` 또는 `화면 끔`을 명시
- 권한: 위치 `항상 허용` 또는 `앱 사용 중 허용`, 알림 허용 여부를 기록
- 모드 순서: 절전 → 균형 → 정밀. 매 테스트 전 기기를 재부팅하고 10분 안정화

## 60분 배터리 매트릭스

| ID | 모드 | 화면 | 기록할 값 |
|---|---|---|---|
| B1 | 절전 | 끔 | 시작/종료 배터리, 샘플 수, 거리, 누락·자동종료 |
| B2 | 균형 | 끔 | 시작/종료 배터리, 샘플 수, 거리, 누락·자동종료 |
| B3 | 정밀 | 끔 | 시작/종료 배터리, 샘플 수, 거리, 누락·자동종료 |
| B4 | 균형 | 켬 | 화면 비용 비교용 동일 지표 |

각 행은 최소 2회 반복한다. 결과는 `앱 소모율(%/h)`, 샘플 간격 중앙값, 정확도 중앙값, 경로 거리 편차로 요약한다.

## 백그라운드·복구 시나리오

1. 기록 시작 후 2분간 화면을 켠다.
2. 홈으로 나가고 화면을 잠근 뒤 20분 유지한다.
3. 잠금을 해제해 누적 거리·샘플 수·경과 시간이 한 번에 동기화되는지 확인한다.
4. 최근 앱 목록에서 산보를 스와이프하지 않고 10분 더 유지한다.
5. 강제 종료/OS 재시작은 별도 케이스로 실행하고, 재실행 후 `미완료 기록` 복구가 보이는지 확인한다.

## 수집 명령과 증거

```bash
# 패키지 ID는 실제 applicationId로 교체
adb shell dumpsys batterystats --reset
adb shell am force-stop com.sanbo.sanbo
adb shell dumpsys batterystats --enable full-wake-history

# 테스트 종료 후
adb shell dumpsys batterystats com.sanbo.sanbo > batterystats-sanbo.txt
adb shell dumpsys location > location-sanbo.txt
adb shell dumpsys activity services | grep -i -E 'geolocator|sanbo'
```

앱 화면의 시작/종료 시각과 배터리 %를 사진 또는 로그로 남기고, `batterystats`의 GPS·WakeLock·CPU 항목과 대조한다. `dumpsys` 한 번의 출력만으로 배터리 원인을 단정하지 않는다.

## 판정 규칙

- 데이터 정확성: 샘플 누락·중복·자동 종료·복구 실패가 있으면 해당 행은 실패
- 배터리: 같은 경로·화면 조건에서 모드 간 상대 차이를 기록하되 절대 허용치는 기기별로 별도 합의
- 백그라운드: 화면 잠금 뒤 샘플이 계속 저장되고 복귀 시 UI가 최신 누적값을 보여야 통과
- 재현성: 2회 결과가 크게 다르면 통과로 합치지 말고 신호·provider·절전 정책 차이를 원인 후보로 기록

측정 결과는 `docs/QUALITY_REVIEW_0.7.md`의 남은 위험과 루프 기록에 링크한다.
