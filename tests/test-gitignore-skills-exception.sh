#!/usr/bin/env bash
# 12차: .claude/skills 는 git 추적, .claude/settings.local.json 은 ignore (R5).
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"

echo "[X1] .claude/skills/agpn/SKILL.md 추적 가능"
mkdir -p "$ROOT/.claude/skills/agpn"; : > "$ROOT/.claude/skills/agpn/SKILL.md"
assert_eq "1" "$(git -C "$ROOT" check-ignore -q .claude/skills/agpn/SKILL.md; [ $? -ne 0 ] && echo 1 || echo 0)" "X1 SKILL.md 추적가능(ignore 아님)"

echo "[X2] .claude/settings.local.json 은 여전히 ignore"
assert_eq "1" "$(git -C "$ROOT" check-ignore -q .claude/settings.local.json && echo 1 || echo 0)" "X2 settings.local.json ignore"

test_summary
