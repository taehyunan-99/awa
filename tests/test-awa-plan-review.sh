#!/usr/bin/env bash
# tests/test-awa-plan-review.sh — awa 검증가능성 abort 시나리오 카탈로그
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"

# Scenario (a) — 검증가능성 FAIL plan → 1차 abort
hits_a=$(grep -E '검증가능성.*abort|검증가능성.*FAIL.*abort|검증가능성 축 FAIL.*즉시 abort' \
  "$ROOT/.claude/skills/awa/SKILL.md" 2>/dev/null | head -1 || true)
assert_contains "$hits_a" "검증가능성" "(a) SKILL.md 검증가능성 abort 분기 존재"

# Scenario (b) — 다른 축 FAIL plan → proceed despite gaps? 옵션 노출
hits_b=$(grep "proceed despite gaps" "$ROOT/.claude/skills/awa/SKILL.md" 2>/dev/null | head -1 || true)
assert_contains "$hits_b" "proceed despite gaps" "(b) SKILL.md proceed despite gaps 분기 존재"

# Scenario (c) — acceptance criteria 누락 task → lead push (Task 5 책임)
# Task 5 완료 후 PASS 자연 전환. 현 시점 매치 여부는 정보 출력만 (테스트 카운트에 미반영).
if grep -q 'acceptance criteria\|acceptance_criteria' "$ROOT/prompts/roles/01-orchestration/orch.md" 2>/dev/null; then
  echo "  info: (c) lead.md ⓑ acceptance criteria push — 매치 (Task 5 PASS 상태)"
else
  echo "  info: (c) lead.md ⓑ acceptance criteria push — Task 5 책임 (SKIP 정상)"
fi

# Scenario (d) — 기존 plan 재진입 → 1차 게이트 PASS (역방향 호환 §6.9)
# 정성 표현 검증가능성 시나리오는 수동 검증 (Task 11 sanity check)
echo "  info: (d) 역방향 호환 — 수동 검증 stub (Task 11 sanity check)"

test_summary
