#!/usr/bin/env bash
# 12차: 리네이밍 회귀 가드 — agents-/team-up/team-down 잔존 0건.
# AWA 사이클 (Task 2 §13.3.2): agenphony- 잔재 0건 추가 (보존 대상 제외).
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

echo "[G2] awa-up.sh 존재, team-up.sh 부재"
assert_eq "1" "$([ -f "$ROOT/bin/awa-up.sh" ] && echo 1 || echo 0)" "G2a awa-up.sh 존재"
assert_eq "0" "$([ -f "$ROOT/bin/team-up.sh" ] && echo 1 || echo 0)" "G2b team-up.sh 부재"

echo "[G3] resolve_session 이 awa- prefix"
assert_contains "$(cat "$ROOT/bin/lib.sh")" "awa-%s" "G3 세션 prefix awa-"

echo "[G4] agenphony- 잔재 0건 (AWA 사이클 §13.3.2-a 보존 대상 제외)"
# 보존 대상 (시간 순 기록): .claude/memory/ (과거 사이클 메모리), docs/superpowers/specs/ (과거 spec 스냅샷),
# docs/superpowers/plans/ (과거 plan 스냅샷 — specs 와 동일 범주), .git/, .agent-harness/ (런타임).
# .claude 통째 제외 — .claude/skills/agpn/SKILL.md 는 본 사이클에서 별도 갱신됨.
agenphony_hits="$(grep -rn 'agenphony-' \
  --include='*.sh' --include='*.md' --include='*.yaml' --include='*.json' \
  --exclude-dir='.claude' \
  --exclude-dir='specs' \
  --exclude-dir='plans' \
  --exclude-dir='.git' \
  --exclude-dir='.agent-harness' \
  "$ROOT" 2>/dev/null | grep -v '/test-rename-guard.sh:' || true)"
assert_eq "" "$agenphony_hits" "G4 agenphony- 잔재 0건 (잔존: $agenphony_hits)"

echo "[G5] bin/agenphony-*.sh 부재 (파일명 리네이밍 완료)"
old_bin_files="$(ls "$ROOT"/bin/agenphony-*.sh 2>/dev/null | wc -l | tr -d ' ')"
assert_eq "0" "$old_bin_files" "G5 bin/agenphony-*.sh 파일 부재"

test_summary
