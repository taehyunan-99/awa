#!/usr/bin/env bash
# 12차: stage 보조 파일 — 4축 리뷰 프롬프트·profiles 근거.
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"
RP="$ROOT/.claude/skills/agpn/stage-review-prompt.md"
PF="$ROOT/.claude/skills/agpn/references/profiles.md"

echo "[R1] 4축 리뷰 프롬프트 — 네 축 모두 명시"
rp="$(cat "$RP")"
for axis in "완결성" "실행가능성" "기술건전성" "검증가능성"; do
  assert_contains "$rp" "$axis" "R1 $axis"
done
echo "[R2] 반환 형식 — PASS/FAIL·종합 verdict"
assert_contains "$rp" "APPROVED" "R2a APPROVED"
assert_contains "$rp" "CHANGES_NEEDED" "R2b CHANGES_NEEDED"

echo "[R3] profiles.md — 네 profile 모두"
pf="$(cat "$PF")"
for p in "default" "feature-team" "research" "code-review"; do
  assert_contains "$pf" "$p" "R3 $p"
done

test_summary
