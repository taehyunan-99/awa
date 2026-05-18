#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh

ROOT="$(cd .. && pwd)"
export SESSION_OVERRIDE="ww_$$"
export AGENT_CMD="cat"

cleanup() { tmux kill-session -t "$SESSION_OVERRIDE" 2>/dev/null || true; rm -rf "$ROOT/workspace/.boot"; }
trap cleanup EXIT

bash "$ROOT/bin/team-up.sh" default >/dev/null
sleep 0.3

# 신호가 먼저 와 있는 경우: 즉시 반환 (race 안전, spec §4.2)
tmux wait-for -S done-dev-PRE
START=$(date +%s)
SESSION_OVERRIDE="$SESSION_OVERRIDE" bash "$ROOT/bin/wait-worker.sh" dev PRE 5
rc=$?
END=$(date +%s)
assert_eq "0" "$rc" "선신호 → 즉시 0 종료"
[ $((END - START)) -le 2 ]; assert_eq "0" "$?" "선신호 → 2초 이내 반환"

# 신호를 나중에 보내는 경우: 백그라운드에서 1초 후 신호
( sleep 1; tmux wait-for -S done-dev-LATER ) &
START=$(date +%s)
SESSION_OVERRIDE="$SESSION_OVERRIDE" bash "$ROOT/bin/wait-worker.sh" dev LATER 5
rc=$?
assert_eq "0" "$rc" "지연 신호 → 0 종료"
wait

# 타임아웃: 아무도 신호 안 보냄 → 2초 타임아웃, 비-0, 페인 덤프 출력
OUT="$(SESSION_OVERRIDE="$SESSION_OVERRIDE" bash "$ROOT/bin/wait-worker.sh" dev NEVER 2 2>&1)"
rc=$?
assert_fail "$rc" "타임아웃 → 비-0 종료"
assert_contains "$OUT" "타임아웃" "타임아웃 메시지 출력"
assert_contains "$OUT" "capture" "페인 덤프 섹션 표기"

test_summary
