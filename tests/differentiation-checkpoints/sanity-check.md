# Sanity Check 표준 절차

## 목적
`tests/check-differentiation-status.sh` 자동화가 *자기 결함* 못 감지하는 메타-메타 함정 회피.
spec §9.6 — 옵션 A (Sanity Check 시나리오).

## 절차 (사이클 진입 직전 1회)

1. *닫힘* 표시 항목 1개 선택 (예: A2 plan-defect 채널)
2. 책임 파일의 PASS 조건 트리거를 *일시 무력화*
   예: `lead.md` 의 `@plan-defect` → `@plan-defect-DISABLED` 임시 변경
3. `bash tests/check-differentiation-status.sh` 실행
4. 해당 항목 FAIL 보고 확인
   - FAIL 보고 = 자동화 정상 (PASS)
   - FAIL 보고 없음 = 자동화 결함 (검사 로직 보강)
5. 트리거 복원 (`@plan-defect-DISABLED` → `@plan-defect`)
6. 재실행 — PASS 보고 확인

## 기록
`tests/differentiation-checkpoints/sanity-log.md` 에 다음 형식으로 누적:

```
## YYYY-MM-DD
- 선택 항목: A2
- 무력화 변경: lead.md @plan-defect → @plan-defect-DISABLED
- 자동화 결과: FAIL 감지 ✅
- 복원 후 결과: PASS ✅
```

## 자기참조 차단
sanity check *건너뜀* 자체는 §9.9 PASS 조건 (직전 30일 1회 기록) FAIL 로 자동 감지.
신설 후 30일 grace period 적용 (`.birthday` 파일 epoch).
