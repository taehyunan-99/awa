#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh

ROOT="$(cd .. && pwd)"
export SESSION_OVERRIDE="td_$$"
export AGENT_CMD="cat"

bash "$ROOT/bin/team-up.sh" default >/dev/null
sleep 0.2
[ -f "$ROOT/workspace/.boot/dev.md" ]; assert_eq "0" "$?" "boot 파일 사전 존재"

# 정상 정리
SESSION_OVERRIDE="$SESSION_OVERRIDE" bash "$ROOT/bin/team-down.sh"
assert_eq "0" "$?" "team-down 성공"

tmux has-session -t "$SESSION_OVERRIDE" 2>/dev/null; assert_fail "$?" "세션 제거됨"
[ -d "$ROOT/workspace/.boot" ] && [ -n "$(ls -A "$ROOT/workspace/.boot" 2>/dev/null)" ] && r=1 || r=0
assert_eq "0" "$r" ".boot 비워짐"

# 멱등: 세션 없어도 실패하지 않음
SESSION_OVERRIDE="$SESSION_OVERRIDE" bash "$ROOT/bin/team-down.sh"
assert_eq "0" "$?" "세션 없어도 멱등 성공"

test_summary
