#!/usr/bin/env bash
# 12차: 리네이밍 회귀 가드 — agents-/team-up/team-down 잔존 0건.
# AWA 사이클 (Task 2 §13.3.2): agenphony- 잔재 0건 추가 (보존 대상 제외).
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
source ./harness-paths.sh
ROOT="$(cd .. && pwd)"

echo "[G1] 옛 이름 잔존 0건 (docs 제외, .claude/skills 포함 — P12)"
# .claude/skills 도 범위에 (스킬 파일 오타로 옛 이름 유입 방지). 존재 안 하면 grep 이 무시.
hits="$(grep -rln 'agents-\|team-up\|team-down\|tmux-agent-team' \
  "$HARNESS_BIN" "$HARNESS_PROMPTS" "$ROOT/tests" "$HARNESS_PROFILES" "$HARNESS_CONFIG" "$HARNESS_TEMPLATES" "$ROOT/README.md" \
  "$ROOT/.claude/skills" \
  2>/dev/null | grep -v '/test-rename-guard.sh$' || true)"
assert_eq "" "$hits" "G1 옛 이름 잔존 0건 (잔존: $hits)"

echo "[G2] awa-up.sh 존재, team-up.sh 부재"
assert_eq "1" "$([ -f "$HARNESS_BIN/awa-up.sh" ] && echo 1 || echo 0)" "G2a awa-up.sh 존재"
assert_eq "0" "$([ -f "$HARNESS_BIN/team-up.sh" ] && echo 1 || echo 0)" "G2b team-up.sh 부재"

echo "[G3] resolve_session 이 awa- prefix"
assert_contains "$(cat "$HARNESS_BIN/lib.sh")" "awa-%s" "G3 세션 prefix awa-"

echo "[G4] agenphony 잔재 0건 (엄격 모드 — exclusion 0)"
# 이전 사이클 spec §13.8 의 '디렉토리 리네이밍 기각' 결정을 본 사이클(2026-05-28)이 명시적으로 뒤집음
# (폴더 리네이밍 awa/ + 사용자 데이터 마이그레이션 + 식별자 일괄 정리 완료).
# 보존 영역 = memory(=.claude/memory)·과거 spec/plan·.git·.agent-harness 만 (--exclude-dir 으로 처리).
# --exclude-dir 은 basename 매칭이라 'memory'/'specs'/'plans' 는 어디 위치든 모두 제외됨 — 의도: .claude/memory, docs/superpowers/specs|plans/.
# .claude/skills 등 활성 영역은 가드 대상에 포함.
# settings.local.json 은 사용자 권한 학습 산출물(spec §2.2 예외, feedback_gitignore_no_touch 영역) → --exclude.
agenphony_hits="$(grep -rnE 'agenphony[^-]|agenphony-' \
  --include='*.sh' --include='*.md' --include='*.yaml' --include='*.json' \
  --exclude='settings.local.json' \
  --exclude-dir='memory' \
  --exclude-dir='specs' \
  --exclude-dir='plans' \
  --exclude-dir='.git' \
  --exclude-dir='.agent-harness' \
  "$ROOT" 2>/dev/null \
  | grep -v '/test-rename-guard.sh:' \
  || true)"
assert_eq "" "$agenphony_hits" "G4 agenphony 잔재 0건 — 엄격 모드 (잔존: $agenphony_hits)"

echo "[G5] bin/agenphony-*.sh 부재 (파일명 리네이밍 완료)"
old_bin_files="$(ls "$HARNESS_BIN"/agenphony-*.sh 2>/dev/null | wc -l | tr -d ' ')"
assert_eq "0" "$old_bin_files" "G5 bin/agenphony-*.sh 파일 부재"

echo "[G6] 폴더명 일관성 — basename(PROJECT_ROOT) == 'awa'"
actual_basename="$(basename "$ROOT")"
assert_eq "awa" "$actual_basename" "G6 PROJECT_ROOT basename = awa (잔존: $actual_basename)"

test_summary
