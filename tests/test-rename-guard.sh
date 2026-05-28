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

echo "[G4] agenphony 잔재 0건 (AWA 사이클 §13.3.2-a 보존 대상 + Task 9·10 위임 제외)"
# 보존 대상 (시간 순 기록): .claude/memory/ (과거 사이클 메모리), docs/superpowers/specs/ (과거 spec 스냅샷),
# docs/superpowers/plans/ (과거 plan 스냅샷 — specs 와 동일 범주), .git/, .agent-harness/ (런타임).
# .claude 통째 제외 — .claude/skills/agpn/SKILL.md 는 본 사이클에서 별도 갱신됨.
#
# 패턴 강화 (G4-a): 'agenphony' + 비-하이픈 경계 문자 — 외부 리뷰의 허위 PASS 정정.
# 'agenphony-' (옛 파일명) + 'agenphony ' (정체성 단어) + 'agenphony/' (경로) 모두 포착.
#
# 명시 exclusion (영구 + 후속 Task 위임) — spec §13.3.2-a 범위 표:
#   - Practice/agenphony/   → spec §13.8 디렉토리 리네이밍 기각 (오케스트레이션 메타포 흔적 솔직 인정)
#   - ~/.config/agenphony/  → 사용자 데이터 경로 보존 (런타임 영향 회피)
#   - "# agenphony — "       → AGENTS.md L1 정체성 문구 (Task 9 영역)
#   - "agenphony 하니스"     → 영역 AGENTS.md 본문 (Task 9 영역)
#   - README.md L23 절대경로 → Task 10 README 전면 재작성 영역
#   - tests/window-layout-live-checklist.md 절대경로 → 운영 checklist (Task 9·10 처리)
agenphony_hits="$(grep -rnE 'agenphony[^-]|agenphony-' \
  --include='*.sh' --include='*.md' --include='*.yaml' --include='*.json' \
  --exclude-dir='.claude' \
  --exclude-dir='specs' \
  --exclude-dir='plans' \
  --exclude-dir='.git' \
  --exclude-dir='.agent-harness' \
  "$ROOT" 2>/dev/null \
  | grep -v '/test-rename-guard.sh:' \
  | grep -v '\.config/agenphony' \
  | grep -v 'config\}/agenphony' \
  | grep -v 'XDG_CONFIG_HOME.*agenphony' \
  | grep -v '/agenphony/bin/awa-' \
  | grep -v '/agenphony/profiles/' \
  | grep -v '^[^:]*AGENTS\.md:[0-9]*:.*agenphony' \
  | grep -v '^[^:]*README\.md:[0-9]*:.*agenphony' \
  | grep -v "test-session-resolve\.sh:.*repo basename.*agenphony" \
  || true)"
assert_eq "" "$agenphony_hits" "G4 agenphony 잔재 0건 — 비위임 잔재 (잔존: $agenphony_hits)"

echo "[G5] bin/agenphony-*.sh 부재 (파일명 리네이밍 완료)"
old_bin_files="$(ls "$ROOT"/bin/agenphony-*.sh 2>/dev/null | wc -l | tr -d ' ')"
assert_eq "0" "$old_bin_files" "G5 bin/agenphony-*.sh 파일 부재"

test_summary
