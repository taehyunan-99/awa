#!/usr/bin/env bash
# awa SKILL.md 가 실제 서브커맨드 분기·핵심 규약 포함. (15차에서 plan/stage/list → down/dash/bookmarks 로 변경됨 — 2026-06-06 stale 단언 교정)
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"
SK="$ROOT/.claude/skills/awa/SKILL.md"

echo "[S1] SKILL.md 존재 + frontmatter"
assert_eq "1" "$([ -f "$SK" ] && echo 1 || echo 0)" "S1a 파일 존재"
src="$(cat "$SK")"
assert_contains "$src" "description:" "S1b frontmatter description"

echo "[S2] 실제 서브커맨드 분기 명시 (### \`/awa <sub>\` 헤더 — substring 우연매치 방지)"
assert_contains "$src" '### `/awa down`' "S2a down 서브커맨드"
assert_contains "$src" '### `/awa dash' "S2b dash 서브커맨드"
assert_contains "$src" '### `/awa bookmarks' "S2c bookmarks 서브커맨드"

echo "[S3] 핵심 규약 — 라이브 tmux 는 사용자가 ! 로 (직접 실행 금지)"
assert_contains "$src" "awa-up" "S3a 발진 명령은 awa-up"

test_summary
