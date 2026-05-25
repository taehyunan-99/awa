#!/usr/bin/env bash
# 12차: agenphony-up 이 @agenphony-project 세션옵션에 PROJECT_ROOT 기록.
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"

echo "[P1] 소스에 set-option @agenphony-project 존재"
assert_contains "$(cat "$ROOT/bin/agenphony-up.sh")" '@agenphony-project' "P1 옵션 기록 코드"

echo "[P2] cat 더미 가동 후 @agenphony-project = PROJECT_ROOT"
TMP="$(mktemp -d)"; SAFE="$(basename "$TMP" | sed 's/[^A-Za-z0-9_-]/_/g')"; SESSION="agenphony-$SAFE"
( cd "$TMP" && git init -q )
HARNESS_PROJECT="$TMP" AGENT_CMD=cat bash "$ROOT/bin/agenphony-up.sh" default >/dev/null 2>&1
got="$(tmux show-options -t "$SESSION" -v @agenphony-project 2>/dev/null || true)"
tmux kill-session -t "$SESSION" 2>/dev/null || true
rm -rf "$TMP"
assert_eq "$TMP" "$got" "P2 @agenphony-project=PROJECT_ROOT"

test_summary
