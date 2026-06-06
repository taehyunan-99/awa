#!/usr/bin/env bash
# 자유프롬프트 → ORCH 작업 주입(2026-06-06): 자연어 작업이 .awa/task.md 로 저장돼
# --plan 으로 ORCH 에 주입되는 절차가 interview.md/SKILL.md 에 명시돼 있는지 grep 가드.
# Layer 1 (문서 토큰 존재) 전용 — 행동 보증은 라이브 검증(grep≠행동보증, tests/AGENTS.md).
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"
IV="$ROOT/.claude/skills/awa/references/interview.md"
SK="$ROOT/.claude/skills/awa/SKILL.md"

iv="$(cat "$IV")"
sk="$(cat "$SK")"

echo "[F1] interview.md — task.md 저장 절차 존재"
assert_contains "$iv" ".awa/task.md" "F1a interview .awa/task.md 경로"
assert_contains "$iv" "자유 프롬프트" "F1b interview 자유프롬프트 분기"
assert_contains "$iv" "--plan" "F1c interview --plan 주입 명시"

echo "[F2] interview.md — task.md 는 4축 리뷰 안 거침 명시(B안)"
assert_contains "$iv" "4축 리뷰를 거치지 않는다" "F2 task.md 무리뷰 명시"

echo "[F3] interview.md — 상호배타(plan 경로면 task.md 불필요)"
assert_contains "$iv" "상호배타" "F3 plan↔task.md 상호배타"

echo "[F4] SKILL.md — Step2 자연어면 task.md Write 명시"
assert_contains "$sk" ".awa/task.md" "F4a SKILL task.md 경로"

echo "[F5] SKILL.md — Step4 launch 에 자연어 --plan task.md 동반"
# launch 인자 블록에 task.md 가 --plan 과 함께 등장하는지 (같은 문서 내 공존)
assert_contains "$sk" "--plan <PROJECT>/.awa/task.md" "F5 SKILL launch --plan task.md"

test_summary
