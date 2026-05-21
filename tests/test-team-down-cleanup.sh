#!/usr/bin/env bash
# team-down 이 .boot-settings/·permission-events.log·.lead-perm-cursor 제거 확인.
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh

ROOT="$(cd .. && pwd)"
TMP="$(mktemp -d)"
SAFE="$(printf '%s' "$(basename "$TMP")" | sed 's/[^A-Za-z0-9_-]/_/g')"
SESSION="agents-$SAFE"

cleanup() {
  tmux kill-session -t "$SESSION" 2>/dev/null || true
  rm -rf "$TMP"
}
trap cleanup EXIT
( cd "$TMP" && git init -q )

HARNESS_PROJECT="$TMP" AGENT_CMD=cat bash "$ROOT/bin/team-up.sh" feature-team >/dev/null 2>&1

# team-up 후 권한 산출물 + 사용자 흔적 만들기.
WS="$TMP/.agent-harness"
mkdir -p "$WS/.boot-settings"
echo '{"x":"y"}' > "$WS/.boot-settings/dev.json"
echo 'ts dev - PRE Bash rm' > "$WS/permission-events.log"
echo "0" > "$WS/.lead-perm-cursor"

# team-down 실행
HARNESS_PROJECT="$TMP" bash "$ROOT/bin/team-down.sh" >/dev/null 2>&1

[ ! -d "$WS/.boot-settings" ]; assert_success "$?" ".boot-settings 제거"
[ ! -f "$WS/permission-events.log" ]; assert_success "$?" "permission-events.log 제거"
[ ! -f "$WS/.lead-perm-cursor" ]; assert_success "$?" ".lead-perm-cursor 제거"

# 기존 cleanup 동작 회귀
[ ! -d "$WS/.boot" ] || [ -z "$(ls "$WS/.boot"/*.md 2>/dev/null)" ]
assert_success "$?" ".boot/*.md 제거 (기존 동작)"

test_summary
