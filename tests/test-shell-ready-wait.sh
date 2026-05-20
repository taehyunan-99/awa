#!/usr/bin/env bash
# T2 회귀: shell_ready_wait 함수.
# - 정상 pane: sentinel echo 응답 → return 0
# - claude 미존재 pane: timeout → return 1
# - SHELL_READY_TIMEOUT env 오버라이드

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HARNESS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$SCRIPT_DIR/assert.sh"
. "$HARNESS_ROOT/bin/lib.sh"

# 테스트 세션 생성.
SESSION="t-shell-ready-$$"
tmux new-session -d -s "$SESSION" -x 80 -y 24
trap "tmux kill-session -t '$SESSION' 2>/dev/null || true" EXIT

# pane 0 의 pane_id 캡처.
PID0="$(tmux display-message -p -t "${SESSION}:0.0" '#{pane_id}')"

# T2.1: 정상 pane (claude 가 PATH 에 있다는 가정).
# fake claude 를 만들어 PATH 앞에 추가해 환경 무관 검증.
FAKE_BIN="$(mktemp -d)"
cat > "$FAKE_BIN/claude" <<'EOF'
#!/bin/sh
echo "fake claude"
EOF
chmod +x "$FAKE_BIN/claude"
# noexec /tmp 환경 가드 — chmod +x 했어도 실행 권한이 안 붙는 마운트 케이스.
if [ ! -x "$FAKE_BIN/claude" ]; then
  echo "skip: fake claude 실행 권한 부여 실패 (noexec mount?)" >&2
  rm -rf "$FAKE_BIN"
  tmux kill-session -t "$SESSION" 2>/dev/null || true
  exit 0
fi
# PATH 를 fake bin + 셸 기본만으로 좁힘 — 시스템 claude 가 잡힐 가능성 차단.
tmux send-keys -t "$PID0" "export PATH=\"$FAKE_BIN:/usr/bin:/bin\"" Enter
sleep 0.5

if shell_ready_wait "$PID0" 5; then
  assert_eq "0" "0" "정상 pane 에서 shell_ready_wait 통과"
else
  assert_eq "0" "1" "정상 pane 에서 shell_ready_wait 통과 (실패)"
fi

# T2.2: SHELL_READY_TIMEOUT env 오버라이드 (claude 미존재 PATH).
tmux send-keys -t "$PID0" "export PATH=\"/usr/bin:/bin\"" Enter
sleep 0.5

SHELL_READY_TIMEOUT=1 shell_ready_wait "$PID0"
rc=$?
assert_eq "1" "$rc" "claude 미존재 + SHELL_READY_TIMEOUT=1 → return 1"

# T2.3: timeout 0 → 즉시 fail.
SHELL_READY_TIMEOUT=0 shell_ready_wait "$PID0"
rc=$?
assert_eq "1" "$rc" "timeout=0 → 즉시 return 1"

rm -rf "$FAKE_BIN"

test_summary
