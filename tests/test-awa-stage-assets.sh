#!/usr/bin/env bash
# 12차→15차: 리뷰 프롬프트 파일이 references/ 로 이전됨 (Task 8).
# 16차: presets.md 폐기(동적 조합 인터뷰가 대체) — R3 블록 제거.
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"
RP="$ROOT/.claude/skills/awa/references/review-prompt.md"

echo "[R1] 4축 리뷰 프롬프트 — 네 축 모두 명시"
rp="$(cat "$RP")"
for axis in "완결성" "실행가능성" "기술건전성" "검증가능성"; do
  assert_contains "$rp" "$axis" "R1 $axis"
done
echo "[R2] 반환 형식 — PASS/FAIL·종합 verdict"
assert_contains "$rp" "APPROVED" "R2a APPROVED"
assert_contains "$rp" "CHANGES_NEEDED" "R2b CHANGES_NEEDED"

test_summary
