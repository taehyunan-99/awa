#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh

ROOT="$(cd .. && pwd)"
export SESSION_OVERRIDE="dp_$$"
export AGENT_CMD="cat"

cleanup() { tmux kill-session -t "$SESSION_OVERRIDE" 2>/dev/null || true; rm -rf "$ROOT/workspace/.boot"; rm -f "$ROOT/workspace/tasks/T1.md"; }
trap cleanup EXIT

bash "$ROOT/bin/team-up.sh" default >/dev/null
sleep 0.3

# 작업 파일 준비
echo "# T1: 더미 작업" > "$ROOT/workspace/tasks/T1.md"

# 정상 dispatch
SESSION_OVERRIDE="$SESSION_OVERRIDE" bash "$ROOT/bin/dispatch.sh" dev T1
assert_eq "0" "$?" "정상 dispatch 성공"

# dev 워커 페인(cat 더미)에 TASK T1 이 실제 주입됐는지 pane_id 로 확인
DEV_ID="$(tmux list-panes -t "$SESSION_OVERRIDE:0" -F '#{pane_title} #{pane_id}' | awk '$1=="dev"{print $2}')"
sleep 0.3
PANE="$(tmux capture-pane -p -t "$DEV_ID" -S -50 2>/dev/null || true)"
if printf '%s' "$PANE" | grep -qF 'TASK T1'; then g=0; else g=1; fi
assert_eq "0" "$g" "dev 페인에 TASK T1 주입 확인"

# 존재하지 않는 작업 파일
SESSION_OVERRIDE="$SESSION_OVERRIDE" bash "$ROOT/bin/dispatch.sh" dev NOPE
assert_fail "$?" "없는 작업 파일 → 실패"

# 존재하지 않는 워커
SESSION_OVERRIDE="$SESSION_OVERRIDE" bash "$ROOT/bin/dispatch.sh" ghost T1
assert_fail "$?" "없는 워커 → 실패"

# 세션 없을 때
tmux kill-session -t "$SESSION_OVERRIDE" 2>/dev/null || true
SESSION_OVERRIDE="$SESSION_OVERRIDE" bash "$ROOT/bin/dispatch.sh" dev T1
assert_fail "$?" "세션 없음 → 실패"

test_summary
