#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"

orch="$(cat "$ROOT/prompts/roles/orchestrator.md")"
assert_contains "$orch" "단계" "orchestrator 단계전이 금지 규약"
assert_contains "$orch" ".harness-state" "orchestrator harness-state 규약"
assert_contains "$orch" "카탈로그" "orchestrator 워커 카탈로그 사용"

revl="$(cat "$ROOT/prompts/loop/reviewer.md")"
assert_contains "$revl" "events.log" "reviewer loop 가 events.log 감시"
assert_contains "$revl" ".review-cursor" "reviewer loop 커서 사용"

orchl="$(cat "$ROOT/prompts/loop/orchestrator.md")"
assert_contains "$orchl" "review/" "orchestrator loop 가 review/ 감시"

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

test_summary
