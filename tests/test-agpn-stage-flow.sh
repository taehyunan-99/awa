#!/usr/bin/env bash
# 12차: SKILL.md stage 절 — 4단계·자동탐색·subagent·발진명령 규약.
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"
src="$(cat "$ROOT/.claude/skills/agpn/SKILL.md")"

echo "[F1] plan 자동탐색 경로"
assert_contains "$src" "docs/superpowers/plans" "F1 plans 디렉터리 스캔"
echo "[F2] 4축 리뷰 subagent (general-purpose) + 프롬프트 파일"
assert_contains "$src" "general-purpose" "F2a subagent_type"
assert_contains "$src" "stage-review-prompt.md" "F2b 프롬프트 파일"
echo "[F3] 발진 명령 — profile/--workers 양형 + --project 자동도출"
assert_contains "$src" "--workers" "F3a 커스텀 --workers"
assert_contains "$src" "--plan" "F3b --plan"
echo "[F4] 라이브 직접 실행 금지 — ! 안내"
assert_contains "$src" '!' "F4 ! 로 실행 안내"

test_summary
