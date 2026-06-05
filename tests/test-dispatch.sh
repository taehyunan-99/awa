#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
source ./harness-paths.sh

ROOT="$(cd .. && pwd)"
export SESSION_OVERRIDE="dp_$$"
export AGENT_CMD="cat"

TMP_PROJ="$(mktemp -d)"; ( cd "$TMP_PROJ" && git init -q )
export HARNESS_PROJECT="$TMP_PROJ"
mkdir -p "$TMP_PROJ/.agent-harness/tasks"

# 15th: bookmarks 격리 — awa-up.sh 가 ~/.config/awa/bookmarks.tsv 에 기록.
# 테스트 fixture 가 사용자 실 경로를 더럽히지 않도록 임시 dir 로 redirect.
_AGPN15_XDG="$(mktemp -d)"
export XDG_CONFIG_HOME="$_AGPN15_XDG"

cleanup() {
  tmux kill-session -t "$SESSION_OVERRIDE" 2>/dev/null || true
  rm -rf "$TMP_PROJ"
  [ -n "${_AGPN15_XDG:-}" ] && rm -rf "$_AGPN15_XDG"
}
trap cleanup EXIT

bash "$HARNESS_BIN/awa-up.sh" default >/dev/null
sleep 0.3

# 작업 파일 준비
echo "# T1: 더미 작업" > "$TMP_PROJ/.agent-harness/tasks/T1.md"

# 정상 dispatch
SESSION_OVERRIDE="$SESSION_OVERRIDE" bash "$HARNESS_BIN/dispatch.sh" engineer T1
assert_eq "0" "$?" "정상 dispatch 성공"

# engineer 워커 페인(cat 더미)에 TASK T1 이 실제 주입됐는지 pane_id 로 확인
# 14차 UX: engineer 워커는 workers 윈도우(1)에 있음.
DEV_ID="$(tmux list-panes -t "$SESSION_OVERRIDE:workers" -F '#{pane_title} #{pane_id}' | awk '$1=="engineer"{print $2}')"
sleep 0.3
PANE="$(tmux capture-pane -p -t "$DEV_ID" -S -50 2>/dev/null || true)"
if printf '%s' "$PANE" | grep -qF 'TASK T1'; then g=0; else g=1; fi
assert_eq "0" "$g" "engineer 페인에 TASK T1 주입 확인"

# 존재하지 않는 작업 파일
SESSION_OVERRIDE="$SESSION_OVERRIDE" bash "$HARNESS_BIN/dispatch.sh" engineer NOPE
assert_fail "$?" "없는 작업 파일 → 실패"

# 존재하지 않는 워커
SESSION_OVERRIDE="$SESSION_OVERRIDE" bash "$HARNESS_BIN/dispatch.sh" ghost T1
assert_fail "$?" "없는 워커 → 실패"

# 세션 없을 때
tmux kill-session -t "$SESSION_OVERRIDE" 2>/dev/null || true
SESSION_OVERRIDE="$SESSION_OVERRIDE" bash "$HARNESS_BIN/dispatch.sh" engineer T1
assert_fail "$?" "세션 없음 → 실패"

test_summary
