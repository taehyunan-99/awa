#!/usr/bin/env bash
# 12차: .claude/skills 는 git 추적, .claude/settings.local.json 은 ignore (R5).
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"

echo "[X1] .claude/skills 하위는 추적 가능 (check-ignore 는 파일 실재 불요 — 실 SKILL.md 보존)"
# 실 SKILL.md 를 truncate 하면 안 됨 → 추적 안 되는 probe 경로로 패턴만 평가.
assert_eq "1" "$(git -C "$ROOT" check-ignore -q .claude/skills/agpn/__probe__.md; [ $? -ne 0 ] && echo 1 || echo 0)" "X1 .claude/skills 하위 추적가능(ignore 아님)"

echo "[X2] .claude/settings.local.json 은 여전히 ignore"
assert_eq "1" "$(git -C "$ROOT" check-ignore -q .claude/settings.local.json && echo 1 || echo 0)" "X2 settings.local.json ignore"

test_summary
