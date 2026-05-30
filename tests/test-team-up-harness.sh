#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"

S="tuh_$$"
# T6: PROJECT_ROOT 분리 후엔 임시 git repo 가 PROJECT_ROOT 가 됨
TMP_PROJ="$(mktemp -d)"; ( cd "$TMP_PROJ" && git init -q )
export HARNESS_PROJECT="$TMP_PROJ"

# 15th: bookmarks 격리 — awa-up.sh 가 ~/.config/awa/bookmarks.tsv 에 기록.
# 테스트 fixture 가 사용자 실 경로를 더럽히지 않도록 임시 dir 로 redirect.
_AGPN15_XDG="$(mktemp -d)"
export XDG_CONFIG_HOME="$_AGPN15_XDG"

cleanup() {
  tmux kill-session -t "$S" 2>/dev/null || true
  rm -rf "$TMP_PROJ"
  [ -n "${_AGPN15_XDG:-}" ] && rm -rf "$_AGPN15_XDG"
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

AGENT_CMD="cat" bash "$ROOT/bin/awa-up.sh" "$PROF" >/dev/null 2>&1
rc=$?
assert_success "$rc" "awa-up 2윈도우 가동"

# 14차 UX: window 0=team, window 1=workers, window 2=review.
wins="$(tmux list-windows -t "$S" -F '#{window_index}' | tr '\n' ' ')"
assert_contains "$wins" "0" "window 0(team) 존재"
assert_contains "$wins" "1" "window 1(workers) 존재"
assert_contains "$wins" "2" "window 2(review) 존재"

w0titles="$(tmux list-panes -t "$S:team" -F '#{pane_title}' | tr '\n' ' ')"
assert_contains "$w0titles" "LEAD" "team 윈도우에 lead"
w1titles="$(tmux list-panes -t "$S:workers" -F '#{pane_title}' | tr '\n' ' ')"
assert_contains "$w1titles" "dev" "workers 윈도우에 dev 워커"
w2titles="$(tmux list-panes -t "$S:review" -F '#{pane_title}' | tr '\n' ' ')"
assert_contains "$w2titles" "qual" "review 윈도우에 리뷰어 qual"

tmux kill-session -t "$S" 2>/dev/null || true
test_summary
