#!/usr/bin/env bash
# 14차 UX: 윈도우 재배치 + border 라벨 통합 검증.
# fixture 는 실 agenphony-up 띄우지 않고 tmux new-session + 직접 split 으로 구성.
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"
source "$ROOT/bin/lib.sh"

# 15th: bookmarks 격리 — agenphony-up.sh 가 ~/.config/agenphony/bookmarks.tsv 에 기록.
# 테스트 fixture 가 사용자 실 경로를 더럽히지 않도록 임시 dir 로 redirect.
# 본문은 fixture 별 trap 을 등록/해제하므로, 최종 trap 해제 후 살아남는 별도 EXIT trap 필요.
_AGPN15_XDG="$(mktemp -d)"
export XDG_CONFIG_HOME="$_AGPN15_XDG"
_agpn15_xdg_cleanup() { [ -n "${_AGPN15_XDG:-}" ] && rm -rf "$_AGPN15_XDG"; }

echo "[W1] fix_session_titles 가 pane-border-status·format 세팅"
# 각 fixture 는 trap (본문 중 사망 대비) + 끝에 명시 cleanup + `trap -` (다음
# fixture 의 새 trap 으로 안전히 덮어쓰기) 의 3단 패턴. 이중 호출은 `|| true` 로 무해.
TMP="$(mktemp -d)"; SAFE="$(basename "$TMP" | sed 's/[^A-Za-z0-9_-]/_/g')"; S="agenphony-$SAFE"
trap 'tmux kill-session -t "$S" 2>/dev/null || true; rm -rf "$TMP"; _agpn15_xdg_cleanup' EXIT INT TERM
tmux new-session -d -s "$S" -c "$TMP"
fix_session_titles "$S"

got_status="$(tmux show-options -v -t "$S" pane-border-status 2>/dev/null || echo MISS)"
assert_eq "top" "$got_status" "W1a pane-border-status=top"

got_format="$(tmux show-options -v -t "$S" pane-border-format 2>/dev/null || echo MISS)"
expected_format=' [ #{@agenphony-project-name} ] #{pane_title} '
assert_eq "$expected_format" "$got_format" "W1b pane-border-format 정확 일치(앞뒤 공백 포함)"

tmux kill-session -t "$S" 2>/dev/null || true; rm -rf "$TMP"
trap - EXIT INT TERM

echo "[W2] agenphony-up 으로 띄운 세션의 윈도우 구조"
# AGENT_CMD=cat 더미로 토큰 0, 실 layout 만 검증.
TMP2="$(mktemp -d)"; ( cd "$TMP2" && git init -q )
PROF="$TMP2/profile.sh"
cat > "$PROF" <<'PROF_EOF'
WORKERS=("dev1:dev" "tester:tester")
REVIEWERS=("quality-rev:reviewer-quality:haiku")
LEAD_MODEL=opus
PM_MODEL=sonnet
PROF_EOF
SAFE2="$(basename "$TMP2" | sed 's/[^A-Za-z0-9_-]/_/g')"; S2="agenphony-$SAFE2"
trap 'tmux kill-session -t "$S2" 2>/dev/null || true; rm -rf "$TMP2"; _agpn15_xdg_cleanup' EXIT INT TERM
SESSION_OVERRIDE="$S2" HARNESS_PROJECT="$TMP2" AGENT_CMD=cat \
  bash "$ROOT/bin/agenphony-up.sh" "$PROF" >/dev/null 2>&1 || true

# W2a: 윈도우 이름 = team, workers, review (REVIEWERS 있으니 3개)
got_windows="$(tmux list-windows -t "$S2" -F '#{window_name}' 2>/dev/null | tr '\n' ',' | sed 's/,$//')"
assert_eq "team,workers,review" "$got_windows" "W2a 윈도우 3개(team,workers,review)"

# W2b: window 0 (team) pane 2개, title 순서 LEAD/PM
got_team="$(tmux list-panes -t "$S2:team" -F '#{pane_title}' 2>/dev/null | tr '\n' ',' | sed 's/,$//')"
assert_eq "LEAD,PM" "$got_team" "W2b team 윈도우 = LEAD,PM"

# W2c: window 1 (workers) 마지막 pane title = watcher
got_last_workers="$(tmux list-panes -t "$S2:workers" -F '#{pane_title}' 2>/dev/null | tail -1)"
assert_eq "watcher" "$got_last_workers" "W2c workers 윈도우 마지막 pane = watcher"

# W2d: @agenphony-project-name = basename
got_pname="$(tmux show-options -v -t "$S2" @agenphony-project-name 2>/dev/null || echo MISS)"
assert_eq "$(basename "$TMP2")" "$got_pname" "W2d @agenphony-project-name = basename"

tmux kill-session -t "$S2" 2>/dev/null || true; rm -rf "$TMP2"
trap - EXIT INT TERM

# 15th: 모든 fixture 의 trap 이 해제된 후 XDG temp dir 정리 (살아남는 EXIT trap).
trap '_agpn15_xdg_cleanup' EXIT

test_summary
