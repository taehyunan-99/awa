#!/usr/bin/env bash
# 14차 UX: 윈도우 재배치 + border 라벨 통합 검증.
# fixture 는 실 agenphony-up 띄우지 않고 tmux new-session + 직접 split 으로 구성
# (기존 test-agenphony-list.sh L3·L4 동일 패턴).
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"
source "$ROOT/bin/lib.sh"

echo "[W1] fix_session_titles 가 pane-border-status·format 세팅"
# 각 fixture 는 trap (본문 중 사망 대비) + 끝에 명시 cleanup + `trap -` (다음
# fixture 의 새 trap 으로 안전히 덮어쓰기) 의 3단 패턴. 이중 호출은 `|| true` 로 무해.
TMP="$(mktemp -d)"; SAFE="$(basename "$TMP" | sed 's/[^A-Za-z0-9_-]/_/g')"; S="agenphony-$SAFE"
trap 'tmux kill-session -t "$S" 2>/dev/null || true; rm -rf "$TMP"' EXIT INT TERM
tmux new-session -d -s "$S" -c "$TMP"
fix_session_titles "$S"

got_status="$(tmux show-options -v -t "$S" pane-border-status 2>/dev/null || echo MISS)"
assert_eq "top" "$got_status" "W1a pane-border-status=top"

got_format="$(tmux show-options -v -t "$S" pane-border-format 2>/dev/null || echo MISS)"
expected_format=' [ #{@agenphony-project-name} ] #{pane_title} '
assert_eq "$expected_format" "$got_format" "W1b pane-border-format 정확 일치(앞뒤 공백 포함)"

tmux kill-session -t "$S" 2>/dev/null || true; rm -rf "$TMP"
trap - EXIT INT TERM

test_summary
