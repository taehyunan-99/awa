#!/usr/bin/env bash
# 12차: awa-up 이 타깃 .gitignore 에 하네스 산출물 멱등 자동추가.
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"

# 15th: bookmarks 격리 — awa-up.sh 가 ~/.config/agenphony/bookmarks.tsv 에 기록.
# 테스트 fixture 가 사용자 실 경로를 더럽히지 않도록 임시 dir 로 redirect.
_AGPN15_XDG="$(mktemp -d)"
export XDG_CONFIG_HOME="$_AGPN15_XDG"
trap 'rm -rf "$_AGPN15_XDG"' EXIT

run_up() { # $1=프로젝트경로
  local p="$1" safe; safe="$(basename "$p" | sed 's/[^A-Za-z0-9_-]/_/g')"
  HARNESS_PROJECT="$p" AGENT_CMD=cat bash "$ROOT/bin/awa-up.sh" default >/dev/null 2>&1
  tmux kill-session -t "awa-$safe" 2>/dev/null || true
}

echo "[GI1] git repo: .gitignore 에 하네스 산출물 전부 추가"
T1="$(mktemp -d)"; ( cd "$T1" && git init -q ); run_up "$T1"
g="$(cat "$T1/.gitignore" 2>/dev/null || true)"
assert_contains "$g" ".agent-harness/" "GI1a .agent-harness"
assert_contains "$g" ".claude/" "GI1b .claude"
assert_contains "$g" "config/.lead-auto-allow-marker" "GI1c yaml marker"
assert_contains "$g" "config/*.bak" "GI1d yaml 백업"; rm -rf "$T1"

echo "[GI2] 멱등: 이미 있으면 중복 추가 안 함"
T2="$(mktemp -d)"; ( cd "$T2" && git init -q )
printf '.agent-harness/\n.claude/\nconfig/.lead-auto-allow-marker\nconfig/*.bak\n' > "$T2/.gitignore"
run_up "$T2"
cnt="$(grep -c '^\.agent-harness/$' "$T2/.gitignore")"
assert_eq "1" "$cnt" "GI2 .agent-harness 1줄 (중복 없음)"; rm -rf "$T2"

echo "[GI4] trailing newline 없는 기존 .gitignore: 첫 룰이 병합되지 않음"
T4="$(mktemp -d)"; ( cd "$T4" && git init -q )
printf 'node_modules/' > "$T4/.gitignore"   # newline 없이 끝남
run_up "$T4"
g4="$(cat "$T4/.gitignore" 2>/dev/null || true)"
assert_contains "$g4" "node_modules/" "GI4a 기존 룰 보존"
assert_eq "1" "$(grep -cxF 'node_modules/' "$T4/.gitignore")" "GI4b node_modules/ 독립 1줄"
assert_eq "1" "$(grep -cxF '.agent-harness/' "$T4/.gitignore")" "GI4c .agent-harness/ 독립 1줄"
rm -rf "$T4"

echo "[GI3] 비 git repo: .gitignore 생성 안 함"
T3="$(mktemp -d)"; run_up "$T3"
assert_eq "0" "$([ -f "$T3/.gitignore" ] && echo 1 || echo 0)" "GI3 비repo 는 .gitignore 없음"; rm -rf "$T3"

test_summary
