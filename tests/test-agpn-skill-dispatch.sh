#!/usr/bin/env bash
# 12차: agpn SKILL.md 가 plan/stage/list 분기·핵심 규약 포함.
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"
SK="$ROOT/.claude/skills/agpn/SKILL.md"

echo "[S1] SKILL.md 존재 + frontmatter"
assert_eq "1" "$([ -f "$SK" ] && echo 1 || echo 0)" "S1a 파일 존재"
src="$(cat "$SK")"
assert_contains "$src" "description:" "S1b frontmatter description"

echo "[S2] 세 서브커맨드 분기 명시"
assert_contains "$src" "plan" "S2a plan"
assert_contains "$src" "stage" "S2b stage"
assert_contains "$src" "list" "S2c list"

echo "[S3] 핵심 규약 — 라이브 tmux 는 사용자가 ! 로 (직접 실행 금지)"
assert_contains "$src" "awa-up" "S3a 발진 명령은 awa-up"

test_summary
