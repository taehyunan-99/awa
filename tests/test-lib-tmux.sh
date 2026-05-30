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

# 더미 세션: 첫 페인에서 cat 이 입력을 파일로 기록.
# 전역 tmux 설정과 무관하게 fix_session_indexing 으로 세션 로컬 인덱스 고정.
OUT="$(mktemp)"
tmux new-session -d -s "$TS" -x 80 -y 24 "bash -c 'cat > $OUT'"
fix_session_indexing "$TS"
sleep 0.3

if session_exists "$TS"; then rc=0; else rc=1; fi
assert_eq "0" "$rc" "있는 세션 → session_exists 0"

# 인덱스 규약 검증: window 0 / pane 1 이 실제로 존재해야 함
WIN="$(tmux list-windows -t "$TS" -F '#{window_index}' | head -1)"
assert_eq "0" "$WIN" "세션 로컬 window base-index=0 적용됨"
PANE="$(tmux list-panes -t "$TS:0" -F '#{pane_index}' | head -1)"
assert_eq "1" "$PANE" "세션 로컬 pane-base-index=1 적용됨"

# send_prompt 로 텍스트 주입 (특수문자 포함). target_of 사용.
send_prompt "$TS:0.1" 'hello "world" $X'
sleep 0.3
tmux send-keys -t "$TS:0.1" C-d
sleep 0.3

GOT="$(cat "$OUT")"
assert_eq 'hello "world" $X' "$GOT" "send_prompt 가 리터럴 텍스트+개행 주입"

tmux kill-session -t "$TS" 2>/dev/null || true
rm -f "$OUT"

test_summary
