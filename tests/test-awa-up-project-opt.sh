#!/usr/bin/env bash
# 12차: awa-up 이 @awa-project 세션옵션에 PROJECT_ROOT 기록.
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"

# 15th: bookmarks 격리 — awa-up.sh 가 ~/.config/agenphony/bookmarks.tsv 에 기록.
# 테스트 fixture 가 사용자 실 경로를 더럽히지 않도록 임시 dir 로 redirect.
_AGPN15_XDG="$(mktemp -d)"
export XDG_CONFIG_HOME="$_AGPN15_XDG"
trap 'rm -rf "$_AGPN15_XDG"' EXIT

echo "[P1] 소스에 set-option @awa-project 존재"
assert_contains "$(cat "$ROOT/bin/awa-up.sh")" '@awa-project' "P1 옵션 기록 코드"

echo "[P2] cat 더미 가동 후 @awa-project = PROJECT_ROOT"
TMP="$(mktemp -d)"; SAFE="$(basename "$TMP" | sed 's/[^A-Za-z0-9_-]/_/g')"; SESSION="awa-$SAFE"
( cd "$TMP" && git init -q )
HARNESS_PROJECT="$TMP" AGENT_CMD=cat bash "$ROOT/bin/awa-up.sh" default >/dev/null 2>&1
got="$(tmux show-options -t "$SESSION" -v @awa-project 2>/dev/null || true)"
tmux kill-session -t "$SESSION" 2>/dev/null || true
rm -rf "$TMP"
assert_eq "$TMP" "$got" "P2 @awa-project=PROJECT_ROOT"

test_summary
