#!/usr/bin/env bash
# T2.5 회귀: timeout 인자가 *초* 단위로 정확히 작동.
# max_iter = timeout * 5, sleep 0.2s 단위.

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HARNESS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$SCRIPT_DIR/assert.sh"
. "$HARNESS_ROOT/bin/lib.sh"

SESSION="t-timeout-$$"
tmux new-session -d -s "$SESSION" -x 80 -y 24
trap "tmux kill-session -t '$SESSION' 2>/dev/null || true" EXIT

PID0="$(tmux display-message -p -t "${SESSION}:0.0" '#{pane_id}')"

# claude 없는 PATH 로 설정 (timeout 강제).
tmux send-keys -t "$PID0" "export PATH=/nonexistent" Enter
sleep 0.3

# timeout=2 → 약 2초 (max_iter=10, sleep 0.2 → ~2초).
START="$(date +%s)"
shell_ready_wait "$PID0" 2
rc=$?
END="$(date +%s)"
elapsed=$((END - START))

assert_eq "1" "$rc" "claude 미존재 → timeout return 1"
# 2초 ± 1초 허용 (시스템 부하).
if [ "$elapsed" -ge 1 ] && [ "$elapsed" -le 4 ]; then
  assert_eq "0" "0" "timeout=2 → 약 2초 (실제 ${elapsed}s)"
else
  # 범위 밖 — 명백히 안 맞는 두 토큰으로 fail 보장 (elapsed 가 우연히 2여도 통과 불가).
  assert_eq "in_range" "out_of_range_${elapsed}s" "timeout=2 의 실제 elapsed 가 1~4초 범위"
fi

test_summary
