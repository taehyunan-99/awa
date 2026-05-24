#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"

lead_content="$(cat "$ROOT/prompts/roles/lead.md")"
assert_contains "$lead_content" "단계" "lead 단계전이 금지 규약"
assert_contains "$lead_content" ".harness-state" "lead harness-state 규약"
assert_contains "$lead_content" "카탈로그" "lead 워커 카탈로그 사용"

revl="$(cat "$ROOT/prompts/roles/reviewer-common.md")"
assert_contains "$revl" "events.log" "reviewer 공통절차가 events.log 감시"
assert_contains "$revl" ".review-cursor" "reviewer 공통절차 커서 사용"

lead_loop="$(cat "$ROOT/prompts/roles/lead.md")"
assert_contains "$lead_loop" "review/" "lead 가 review/ 감시"

for r in spec quality arch; do
  if [ -f "$ROOT/prompts/roles/reviewer-$r.md" ]; then
    assert_eq "ok" "ok" "reviewer-$r.md 존재"
  else
    assert_eq "exists" "missing" "reviewer-$r.md 존재해야 함"
  fi
done

if [ -f "$ROOT/prompts/roles/reviewer.md" ]; then
  assert_eq "deleted" "still-exists" "1차 roles/reviewer.md 삭제돼야 함"
else
  assert_eq "ok" "ok" "1차 roles/reviewer.md 삭제됨"
fi

# 9차: reviewer-common.md 런타임 단일출처 존재 (부트 합본 의존)
[ -f "$ROOT/prompts/roles/reviewer-common.md" ]
assert_success "$?" "reviewer-common.md 존재 (reviewer 부트 합본 의존)"

# 9차: pm 역할 프롬프트 검증
pm="$(cat "$ROOT/prompts/roles/pm.md")"
assert_contains "$pm" "사용자" "pm 은 사용자 창구"
assert_contains "$pm" "@pm:" "pm→lead 전달 prefix"
assert_not_contains "$pm" "dispatch.sh" "pm 은 dispatch 안 함(lead 의 일)"
assert_contains "$pm" "읽기 전용" "pm 은 읽기전용 규약 명시"

test_summary
