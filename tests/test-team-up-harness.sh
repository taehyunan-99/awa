#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"

S="tuh_$$"
# T6: PROJECT_ROOT 분리 후엔 임시 git repo 가 PROJECT_ROOT 가 됨
TMP_PROJ="$(mktemp -d)"; ( cd "$TMP_PROJ" && git init -q )
export HARNESS_PROJECT="$TMP_PROJ"
cleanup() {
  tmux kill-session -t "$S" 2>/dev/null || true
  rm -rf "$TMP_PROJ"
}
trap cleanup EXIT

PROF="$(mktemp -d)/p.sh"
cat > "$PROF" <<EOF
SESSION="$S"
LAYOUT="tiled"
WORKERS=("dev:dev" "test:tester")
REVIEWERS=("qual:reviewer-quality:haiku")
LEAD_MODEL="opus"
EOF

AGENT_CMD="cat" bash "$ROOT/bin/agenphony-up.sh" "$PROF" >/dev/null 2>&1
rc=$?
assert_success "$rc" "agenphony-up 2윈도우 가동"

wins="$(tmux list-windows -t "$S" -F '#{window_index}' | tr '\n' ' ')"
assert_contains "$wins" "0" "window 0(team) 존재"
assert_contains "$wins" "1" "window 1(review) 존재"

w0titles="$(tmux list-panes -t "$S:0" -F '#{pane_title}' | tr '\n' ' ')"
assert_contains "$w0titles" "LEAD" "team 윈도우에 lead"
assert_contains "$w0titles" "dev" "team 윈도우에 dev 워커"
w1titles="$(tmux list-panes -t "$S:1" -F '#{pane_title}' | tr '\n' ' ')"
assert_contains "$w1titles" "qual" "review 윈도우에 리뷰어 qual"

tmux kill-session -t "$S" 2>/dev/null || true
test_summary
