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

# dev 페인(cat)이 받은 입력 확인: capture-pane
sleep 0.3
PANE="$(tmux capture-pane -p -t "$SESSION_OVERRIDE:0" -S -50 2>/dev/null || true)"
# cat 더미라 입력 에코가 페인에 남음. TASK T1 문자열 확인은 pane title 매칭이 핵심이므로
# 여기서는 종료코드 + 에러경로 위주로 검증한다.

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
