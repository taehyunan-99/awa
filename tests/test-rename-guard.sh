#!/usr/bin/env bash
# 12차: 리네이밍 회귀 가드 — agents-/team-up/team-down 잔존 0건.
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"

echo "[G1] 옛 이름 잔존 0건 (docs 제외, .claude/skills 포함 — P12)"
# .claude/skills 도 범위에 (스킬 파일 오타로 옛 이름 유입 방지). 존재 안 하면 grep 이 무시.
hits="$(grep -rln 'agents-\|team-up\|team-down\|tmux-agent-team' \
  "$ROOT/bin" "$ROOT/prompts" "$ROOT/tests" "$ROOT/profiles" "$ROOT/config" "$ROOT/templates" "$ROOT/README.md" \
  "$ROOT/.claude/skills" \
  2>/dev/null | grep -v '/test-rename-guard.sh$' || true)"
assert_eq "" "$hits" "G1 옛 이름 잔존 0건 (잔존: $hits)"

echo "[G2] agenphony-up.sh 존재, team-up.sh 부재"
assert_eq "1" "$([ -f "$ROOT/bin/agenphony-up.sh" ] && echo 1 || echo 0)" "G2a agenphony-up.sh 존재"
assert_eq "0" "$([ -f "$ROOT/bin/team-up.sh" ] && echo 1 || echo 0)" "G2b team-up.sh 부재"

echo "[G3] resolve_session 이 agenphony- prefix"
assert_contains "$(cat "$ROOT/bin/lib.sh")" "agenphony-%s" "G3 세션 prefix agenphony-"

test_summary
