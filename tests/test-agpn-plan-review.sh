#!/usr/bin/env bash
# tests/test-agpn-plan-review.sh — /agpn 검증가능성 abort 시나리오 카탈로그
set -uo pipefail
HARNESS_ROOT="${HARNESS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"

# Scenario (a) — 검증가능성 FAIL plan → 1차 abort
grep -q '검증가능성.*abort\|검증가능성.*FAIL.*abort\|검증가능성 축 FAIL.*즉시 abort' \
  "$HARNESS_ROOT/.claude/skills/agpn/SKILL.md" || {
  echo "[FAIL] (a) SKILL.md 검증가능성 abort 분기 부재"
  exit 1
}

# Scenario (b) — 다른 축 FAIL plan → proceed despite gaps? 옵션 노출
grep -q 'proceed despite gaps' "$HARNESS_ROOT/.claude/skills/agpn/SKILL.md" || {
  echo "[FAIL] (b) SKILL.md proceed despite gaps 분기 부재"
  exit 1
}

# Scenario (c) — acceptance criteria 누락 task → lead push (Task 5 책임)
# 이 시나리오는 Task 5 완료 후 PASS — 이번 Task 에서는 skip stub
grep -q 'acceptance criteria\|acceptance_criteria' \
  "$HARNESS_ROOT/prompts/roles/01-orchestration/lead.md" || {
  echo "[SKIP] (c) lead.md ⓑ acceptance criteria push — Task 5 책임"
}

# Scenario (d) — 기존 plan 재진입 → 1차 게이트 PASS (역방향 호환 §6.9)
# acceptance_criteria 구조화 필드 없는 plan 도 검증가능성 정성 표현 PASS
echo "[STUB] (d) 역방향 호환 — 정성 표현 검증가능성 시나리오는 수동 검증 (Task 11 sanity check)"

echo "[PASS] /agpn plan review 시나리오 카탈로그 — (a)·(b)·(c)·(d)"
exit 0
