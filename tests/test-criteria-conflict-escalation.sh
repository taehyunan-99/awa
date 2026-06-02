#!/usr/bin/env bash
# 워커 자율 plan 해소 차단 회귀 (#3, 2026-06-01).
# 설계 결함(메모리 worker-autonomous-plan-resolution-risk): criteria 의 결과값↔구현방식 모순
#   (range-sum C1 "==15" inclusive vs C2 "i<hi" exclusive)을 워커가 @plan-defect 없이 혼자
#   `i<=hi` 로 해소 → 리뷰어는 "결과 충족"만 보고 통과 → C2 위반이 어디에도 안 남음 →
#   drift 은폐 + 회로 침묵. 이상적 경계 = "모순 감지까지. 해소는 @plan-defect 로 올림".
# 수정: _common.md 의 (1) assume-and-flag 절에 "criteria 간 모순은 ASSUMED 자율 해소 금지"
#   (2) @plan-defect 신호에 "결과값↔구현방식 모순" 명시. 모든 워커 공통이라 _common.md 단일 위치.
# Layer 1 (grep): 강화 문구 토큰 존재. (프롬프트 변경이라 동작 테스트는 라이브 — test-plan-defect-e2e 가 라우팅 담당.)
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"
CM="$ROOT/prompts/_common.md"

echo "[C1] assume-and-flag 절: criteria 간 모순은 자율 해소 금지 → @plan-defect"
# assume-and-flag(가역·scope내 자율 가정 허용)의 *예외* 로 criteria 모순을 명시해야
# 워커가 모순을 'ASSUMED 로 합리적 가정' 하고 넘어가는 걸 차단.
grep -qE 'criteria.*(모순|충돌|상충)' "$CM"
assert_success "$?" "C1 _common.md 에 criteria 모순 언급"
grep -qE '(자율 해소|혼자 (해소|판단|메우)).*(금지|말)' "$CM"
assert_success "$?" "C1 자율 해소 금지 문구"

echo "[C2] 결과값↔구현방식 모순 명시 (미묘한 충돌 — range-sum 교훈)"
# 명백한 모순(objective↔criteria)뿐 아니라 *한 단계 추론 거치는* 결과값↔구현방식 충돌도
# 에스컬레이션 대상임을 명시. mul(명백)은 잡았지만 range-sum(미묘)은 놓친 게 결함.
grep -qE '결과값.*구현방식|구현방식.*결과값' "$CM"
assert_success "$?" "C2 결과값↔구현방식 모순 명시"

echo "[C3] @plan-defect 로 올리라는 연결 (감지→에스컬레이션 경로)"
# 모순 감지 시 행선지가 @plan-defect 임을 같은 맥락에서 연결.
grep -qE '모순.*@plan-defect|@plan-defect.*(모순|충돌)|criteria.*충돌.*@plan-defect' "$CM"
assert_success "$?" "C3 모순→@plan-defect 라우팅 연결"

echo "[C4] 균형 가드: 정상 구현 재량은 보존 (과차단 방지)"
# 메모리 경고 — '과하면 정상적 구현 재량까지 위축'. 강화 문구가 *모순* 한정임을 명시해
# 일반 구현 선택(재량)까지 막지 않도록. assume-and-flag 자체는 유지.
grep -q 'assume-and-flag' "$CM"
assert_success "$?" "C4 assume-and-flag 절 보존(재량 유지)"

test_summary
