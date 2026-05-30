#!/usr/bin/env bash
# 12차→15차: SKILL.md 가 unified entry 로 재구성 (Task 8). plan/stage/list 서브커맨드 제거.
# 본 테스트는 핵심 규약(자동탐색·subagent·발진명령·! 안내)이 신규 구조에 보존됐는지 확인.
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"
src="$(cat "$ROOT/.claude/skills/awa/SKILL.md")"

echo "[F1] plan 자동탐색 경로"
assert_contains "$src" "docs/superpowers/plans" "F1 plans 디렉터리 스캔"
echo "[F2] 4축 리뷰 subagent (general-purpose) + 프롬프트 파일"
assert_contains "$src" "general-purpose" "F2a subagent_type"
assert_contains "$src" "references/review-prompt.md" "F2b 프롬프트 파일 (references/)"
echo "[F3] 발진 명령 — preset/--workers 양형"
assert_contains "$src" "--workers" "F3a 커스텀 --workers"
assert_contains "$src" "--plan" "F3b --plan"
echo "[F4] 라이브 직접 실행 금지 — ! 안내"
assert_contains "$src" '!' "F4 ! 로 실행 안내"

test_summary
