#!/usr/bin/env bash
# 12차: agenphony-list 가 agenphony-* 세션을 경로·워커구성과 함께 나열.
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"

echo "[L1] 세션 0개일 때만: 안내 메시지 (실제 0개일 때만 검증, 아니면 스킵)"
live="$(tmux ls -F '#{session_name}' 2>/dev/null | grep -c '^agenphony-' || true)"
if [ "${live:-0}" = "0" ]; then
  out="$(bash "$ROOT/bin/agenphony-list.sh" 2>&1 || true)"
  assert_contains "$out" "agpn stage" "L1 0개 안내(빈 경우 stage 안내)"
else
  echo "  (SKIP L1 — agenphony-* 세션 $live 개 존재, 0개 가정 불가)"
fi

echo "[L2] 더미 세션 1개: 세션명·경로·attach 명령 (단일 pane=dev)"
TMP="$(mktemp -d)"; SAFE="$(basename "$TMP" | sed 's/[^A-Za-z0-9_-]/_/g')"; S="agenphony-$SAFE"
tmux new-session -d -s "$S" -c "$TMP"
tmux set-option -t "$S" @agenphony-project "$TMP"
tmux select-pane -t "$S" -T "dev"
out="$(bash "$ROOT/bin/agenphony-list.sh" 2>&1 || true)"
tmux kill-session -t "$S" 2>/dev/null || true; rm -rf "$TMP"
assert_contains "$out" "$S" "L2a 세션명"
assert_contains "$out" "$TMP" "L2b 프로젝트경로(@agenphony-project)"
assert_contains "$out" "tmux attach -t $S" "L2c attach 명령"

echo "[L3] 멀티 pane 워커구성 집계"
# P6: new-session window 인덱스가 base-index 따라 1일 수 있음 → 실제 인덱스 받아 split.
TMP="$(mktemp -d)"; SAFE="$(basename "$TMP" | sed 's/[^A-Za-z0-9_-]/_/g')"; S="agenphony-$SAFE"
tmux new-session -d -s "$S" -c "$TMP"
tmux set-option -t "$S" @agenphony-project "$TMP"
WIN="$(tmux list-windows -t "$S" -F '#{window_index}' | head -1)"
tmux select-pane -t "$S:$WIN" -T "dev"
p2="$(tmux split-window -t "$S:$WIN" -d -P -F '#{pane_id}')"; tmux select-pane -t "$p2" -T "dev"
p3="$(tmux split-window -t "$S:$WIN" -d -P -F '#{pane_id}')"; tmux select-pane -t "$p3" -T "test"
out="$(bash "$ROOT/bin/agenphony-list.sh" 2>&1 || true)"
tmux kill-session -t "$S" 2>/dev/null || true; rm -rf "$TMP"
assert_contains "$out" "dev2" "L3a dev 2개 집계"
assert_contains "$out" "test1" "L3b test 1개 집계"

echo "[L4] reviewer 는 별도 review window → 워커구성에서 제외 (회귀 가드)"
# 실 agenphony-up 은 reviewer 를 window1(review)에 두고 워커는 window0 에 둔다.
# list-panes -s 로 전 window 를 긁으면 reviewer 가 워커구성에 섞임 → window0 한정으로 차단.
TMP="$(mktemp -d)"; SAFE="$(basename "$TMP" | sed 's/[^A-Za-z0-9_-]/_/g')"; S="agenphony-$SAFE"
tmux new-session -d -s "$S" -c "$TMP"
tmux set-option -t "$S" @agenphony-project "$TMP"
WIN="$(tmux list-windows -t "$S" -F '#{window_index}' | head -1)"
tmux select-pane -t "$S:$WIN" -T "dev"
pm="$(tmux split-window -t "$S:$WIN" -d -P -F '#{pane_id}')"; tmux select-pane -t "$pm" -T "watcher"
# 별도 review window 에 reviewer (실 구조 모사).
tmux new-window -t "$S" -n review
RWIN="$(tmux list-windows -t "$S" -F '#{window_index} #{window_name}' | awk '$2=="review"{print $1}')"
tmux select-pane -t "$S:$RWIN" -T "quality-rev"
out="$(bash "$ROOT/bin/agenphony-list.sh" 2>&1 || true)"
tmux kill-session -t "$S" 2>/dev/null || true; rm -rf "$TMP"
assert_contains "$out" "dev1" "L4a dev 워커 집계됨"
assert_not_contains "$out" "quality-rev" "L4b reviewer 는 워커구성에 안 섞임"

test_summary
