#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"
source "$ROOT/bin/lib.sh" >/dev/null 2>&1 || true
rf() { cat "$(resolve_role_file "$ROOT/prompts" "$1")"; }   # 역할명 → 내용

lead_content="$(rf lead)"
assert_contains "$lead_content" "단계" "lead 단계전이 금지 규약"
assert_contains "$lead_content" ".harness-state" "lead harness-state 규약"
assert_contains "$lead_content" "카탈로그" "lead 워커 카탈로그 사용"

revl="$(rf reviewer-common)"
assert_contains "$revl" "events.log" "reviewer 공통절차가 events.log 감시"
assert_contains "$revl" ".review-cursor" "reviewer 공통절차 커서 사용"

lead_loop="$(rf lead)"
assert_contains "$lead_loop" "review/" "lead 가 review/ 감시"

for r in spec quality arch; do
  if resolve_role_file "$ROOT/prompts" "reviewer-$r" >/dev/null 2>&1; then
    assert_eq "ok" "ok" "reviewer-$r.md 존재"
  else
    assert_eq "exists" "missing" "reviewer-$r.md 존재해야 함"
  fi
done

if resolve_role_file "$ROOT/prompts" reviewer >/dev/null 2>&1; then
  assert_eq "deleted" "still-exists" "1차 roles/reviewer.md 삭제돼야 함"
else
  assert_eq "ok" "ok" "1차 roles/reviewer.md 삭제됨"
fi

# 9차: reviewer-common.md 런타임 단일출처 존재 (부트 합본 의존)
resolve_role_file "$ROOT/prompts" reviewer-common >/dev/null 2>&1
assert_success "$?" "reviewer-common.md 존재 (reviewer 부트 합본 의존)"

# 9차: pm 역할 프롬프트 검증
pm="$(rf pm)"
assert_contains "$pm" "사용자" "pm 은 사용자 창구"
assert_contains "$pm" "@pm:" "pm→lead 전달 prefix"
assert_not_contains "$pm" "dispatch.sh" "pm 은 dispatch 안 함(lead 의 일)"
assert_contains "$pm" "읽기 전용" "pm 은 읽기전용 규약 명시"

# --- 5축 공통 토대 (_common.md) ---
COMMON="$(cat "$ROOT/prompts/_common.md")"
assert_contains "$COMMON" 'status: DONE|PARTIAL|BLOCKED' "_common ②출력계약 status 헤더"
assert_contains "$COMMON" 'EVIDENCE' "_common ③ EVIDENCE 섹션"
assert_contains "$COMMON" 'HYPOTHESIS' "_common ③ HYPOTHESIS 섹션"
assert_contains "$COMMON" 'confirmed|likely|speculative' "_common ③ confidence 버킷(숫자% 금지)"
assert_contains "$COMMON" 'BLOCKED' "_common ④ BLOCKED 프로토콜"
assert_contains "$COMMON" 'ASSUMED:' "_common ⑤ assume-and-flag"
assert_contains "$COMMON" 'wait-for -S done-{{SESSION}}-{{WORKER_NAME}}' "_common 완료신호 보존(회귀)"

res_c="$(cat "$(resolve_role_file "$ROOT/prompts" researcher)")"
assert_contains "$res_c" "budget" "researcher.md ⑤ budget"
assert_contains "$res_c" "추측" "researcher.md ① 추측 단정 금지"

sec_c="$(cat "$(resolve_role_file "$ROOT/prompts" security)")"
assert_contains "$sec_c" "budget" "security.md ⑤ budget"
assert_contains "$sec_c" "file:line" "security.md ③ 취약점 위치 file:line"

test_summary
