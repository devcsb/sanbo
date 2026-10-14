# 산보(Sanbo) 기획 문서

개인 산책 **분 단위 동선·속도·장소·활동 추정** 로그.  
**Flutter · Android 우선 · 한국 공개 지도 · 심플 UX.**

앱 코드는 저장소 루트 (`lib/`). 실행: `flutter run` · 테스트: `flutter test`

| 문서 | 내용 |
|------|------|
| [PRD_MAINTENANCE_2026-10.md](./PRD_MAINTENANCE_2026-10.md) | 2026년 10월 배포 대조, 측정 신뢰성, 백업, 상태 안내 개선 요구 |
| [TRD_MAINTENANCE_2026-10.md](./TRD_MAINTENANCE_2026-10.md) | 위 요구의 구현 경계, 단계 구분과 검증 기준 |
| [1차 유지보수 설계](./superpowers/specs/2026-10-13-measurement-consistency-and-backup-design.md) | 2026-10-14 승인된 백업과 측정 표시 일관성 설계 |
| [1차 유지보수 구현 계획](./superpowers/plans/2026-10-14-maintenance-stage1.md) | 측정 표시, 모바일 백업, 기존 설치 업데이트와 릴리즈 검증 순서. 2026-10-14 승인, 구현과 검증 진행 |
| [1차 구현 검증 기록](./superpowers/verification/2026-10-14-maintenance-stage1.md) | 새 build의 478개 Flutter 테스트와 native/서명 검증, 실제 파일 검증 대기 상태 |
| [유지보수 검토 근거](./superpowers/verification/2026-10-13-maintenance-audit.md) | 공개 릴리즈 체크섬, 439개 테스트와 실제 오류 재현 결과 |
| [PRD.md](./PRD.md) | 제품 요구, 시나리오, FR/NFR, MVP, 재검증 |
| [PRD_ARCHITECTURE_UX_BATTERY_V0.9.md](./PRD_ARCHITECTURE_UX_BATTERY_V0.9.md) | 아키텍처·배터리·회상 UX 기준선, 벤치마크 근거, 실기기 검증 계획 |
| [TRD.md](./TRD.md) | 스키마, 파이프라인, Android FGS, MapLibre, 추적 표 |
| [PLATFORM_AND_MAPS.md](./PLATFORM_AND_MAPS.md) | Flutter/Android, OSM·VWorld 비교, 러닝앱 Borrow/Reject |
| [UX_REVIEW.md](./UX_REVIEW.md) | 비판적 UI/UX 검토 · major 개선 대응 표 |

문서 검증: `python3 scripts/verify_prd_trd.py`
