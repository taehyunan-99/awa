#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh

ROOT="$(cd .. && pwd)"
export SESSION_OVERRIDE="td_$$"
export AGENT_CMD="cat"

# T10: --project 격리된 임시 PROJECT_ROOT. marker + .agent-harness/.boot 사전 구성.
TMP_PROJ="$(mktemp -d)"; ( cd "$TMP_PROJ" && git init -q )
export HARNESS_PROJECT="$TMP_PROJ"
mkdir -p "$TMP_PROJ/.agent-harness/.boot" "$TMP_PROJ/.claude"
touch "$TMP_PROJ/.claude/.agent-harness-marker"
echo "boot" > "$TMP_PROJ/.agent-harness/.boot/dev.md"

# 15th: bookmarks 격리 — awa-up.sh 가 ~/.config/agenphony/bookmarks.tsv 에 기록.
# 테스트 fixture 가 사용자 실 경로를 더럽히지 않도록 임시 dir 로 redirect.
_AGPN15_XDG="$(mktemp -d)"
export XDG_CONFIG_HOME="$_AGPN15_XDG"

# 정리 hook (성공/실패 무관)
cleanup() {
  tmux kill-session -t "$SESSION_OVERRIDE" 2>/dev/null || true
  rm -rf "$TMP_PROJ"
  [ -n "${_AGPN15_XDG:-}" ] && rm -rf "$_AGPN15_XDG"
}
trap cleanup EXIT

bash "$ROOT/bin/awa-up.sh" default >/dev/null
sleep 0.2
[ -f "$TMP_PROJ/.agent-harness/.boot/dev.md" ]; assert_eq "0" "$?" "boot 파일 사전 존재"

# 정상 정리 (marker 있음)
SESSION_OVERRIDE="$SESSION_OVERRIDE" bash "$ROOT/bin/awa-down.sh"
assert_eq "0" "$?" "awa-down 성공"

tmux has-session -t "$SESSION_OVERRIDE" 2>/dev/null; assert_fail "$?" "세션 제거됨"
[ -d "$TMP_PROJ/.agent-harness/.boot" ] && [ -n "$(ls -A "$TMP_PROJ/.agent-harness/.boot" 2>/dev/null)" ] && r=1 || r=0
assert_eq "0" "$r" ".boot 비워짐"

# 멱등: 세션 없어도 실패하지 않음 (marker 이미 제거됨 → marker-없음 분기, exit 0)
SESSION_OVERRIDE="$SESSION_OVERRIDE" bash "$ROOT/bin/awa-down.sh"
assert_eq "0" "$?" "세션 없어도 멱등 성공"

# T10.1 — marker 있을 때 정상 정리 (독립 임시 프로젝트)
TMP_PROJ2="$(mktemp -d)"; ( cd "$TMP_PROJ2" && git init -q )
export HARNESS_PROJECT="$TMP_PROJ2"
mkdir -p "$TMP_PROJ2/.claude" "$TMP_PROJ2/.agent-harness"
touch "$TMP_PROJ2/.claude/.agent-harness-marker"
echo '{}' > "$TMP_PROJ2/.claude/settings.json"
echo "x" > "$TMP_PROJ2/.agent-harness/events.log"
SESSION_OVERRIDE="td_test_$$" tmux new-session -d -s "td_test_$$" 2>/dev/null
SESSION_OVERRIDE="td_test_$$" bash "$ROOT/bin/awa-down.sh"
[ ! -f "$TMP_PROJ2/.agent-harness/events.log" ]; assert_success "$?" "events.log 정리됨 (marker 있음)"
[ ! -f "$TMP_PROJ2/.claude/settings.json" ]; assert_success "$?" "settings.json 정리됨"
[ ! -f "$TMP_PROJ2/.claude/.agent-harness-marker" ]; assert_success "$?" "marker 정리됨"
rm -rf "$TMP_PROJ2"

# T10.2 — marker 없을 때 .agent-harness/·settings.json 보호 (사용자 자료 보호)
TMP_PROJ3="$(mktemp -d)"; ( cd "$TMP_PROJ3" && git init -q )
export HARNESS_PROJECT="$TMP_PROJ3"
mkdir -p "$TMP_PROJ3/.claude" "$TMP_PROJ3/.agent-harness"
# marker 일부러 없음
echo '{"keep":true}' > "$TMP_PROJ3/.claude/settings.json"
echo "user-data" > "$TMP_PROJ3/.agent-harness/events.log"
SESSION_OVERRIDE="td_nomark_$$" bash "$ROOT/bin/awa-down.sh" >/dev/null 2>&1
assert_eq "0" "$?" "marker 없어도 exit 0"
[ -f "$TMP_PROJ3/.agent-harness/events.log" ]; assert_success "$?" "events.log 보존됨 (marker 없음)"
[ -f "$TMP_PROJ3/.claude/settings.json" ]; assert_success "$?" "settings.json 보존됨 (marker 없음)"
rm -rf "$TMP_PROJ3"

test_summary
