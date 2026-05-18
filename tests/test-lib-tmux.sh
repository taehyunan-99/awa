#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh

ROOT="$(cd .. && pwd)"
source "$ROOT/bin/lib.sh"

TS="libtest_$$"

# session_exists: 없을 때 비-0
if session_exists "$TS"; then rc=0; else rc=1; fi
assert_eq "1" "$rc" "없는 세션 → session_exists 비-0"

# 더미 세션 생성: 첫 페인에서 bash 가 입력을 파일로 기록.
# 테스트는 단일 페인을 $TS:0.1 (window 0, pane 1) 로 가정한다.
# 사용자 전역 tmux 설정(base-index/pane-base-index)에 무관하게
# 이 가정이 성립하도록 세션 생성 전 base-index=0, pane-base-index=1 고정.
OUT="$(mktemp)"
# 사용자 전역 옵션을 백업했다가 테스트 종료 시 복원 (서버 설정 비침습).
_OLD_BI="$(tmux show-option -gv base-index 2>/dev/null || echo 0)"
_OLD_PBI="$(tmux show-option -gv pane-base-index 2>/dev/null || echo 0)"
restore_tmux_opts() {
  tmux set-option -g base-index "$_OLD_BI" 2>/dev/null || true
  tmux set-option -g pane-base-index "$_OLD_PBI" 2>/dev/null || true
}
trap restore_tmux_opts EXIT
tmux set-option -g base-index 0 2>/dev/null
tmux set-option -g pane-base-index 1 2>/dev/null
tmux new-session -d -s "$TS" -x 80 -y 24 "bash -c 'cat > $OUT'"
sleep 0.3

if session_exists "$TS"; then rc=0; else rc=1; fi
assert_eq "0" "$rc" "있는 세션 → session_exists 0"

# send_prompt 로 텍스트 주입 (특수문자 포함)
send_prompt "$TS:0.1" 'hello "world" $X'
sleep 0.3
tmux send-keys -t "$TS:0.1" C-d   # cat 종료
sleep 0.3

GOT="$(cat "$OUT")"
assert_eq 'hello "world" $X' "$GOT" "send_prompt 가 리터럴 텍스트+개행 주입"

tmux kill-session -t "$TS" 2>/dev/null || true
rm -f "$OUT"

test_summary
