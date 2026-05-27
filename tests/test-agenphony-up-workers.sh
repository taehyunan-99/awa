#!/usr/bin/env bash
# 12차: agenphony-up --workers 조합 인자 → WORKERS 직접 구성.
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"
src="$(cat "$ROOT/bin/agenphony-up.sh")"

# 15th: bookmarks 격리 — agenphony-up.sh 가 ~/.config/agenphony/bookmarks.tsv 에 기록.
# 테스트 fixture 가 사용자 실 경로를 더럽히지 않도록 임시 dir 로 redirect.
_AGPN15_XDG="$(mktemp -d)"
export XDG_CONFIG_HOME="$_AGPN15_XDG"
trap 'rm -rf "$_AGPN15_XDG"' EXIT

echo "[W1] --workers 파서 case 존재"
# 주석이 아닌 실제 case 토큰을 매칭 (약한 단언 보강)
assert_contains "$src" '--workers)' "W1 --workers 파서 case"

echo "[W2] --workers 와 profile 상호배타 (둘 다 오면 오류)"
TMP="$(mktemp -d)"; ( cd "$TMP" && git init -q )
HARNESS_PROJECT="$TMP" AGENT_CMD=cat bash "$ROOT/bin/agenphony-up.sh" --workers "dev:dev:sonnet" default >/dev/null 2>&1
rc=$?
tmux kill-session -t "agenphony-$(basename "$TMP" | sed 's/[^A-Za-z0-9_-]/_/g')" 2>/dev/null || true
rm -rf "$TMP"
assert_eq "1" "$rc" "W2 --workers+profile 동시 → 비0 종료"

echo "[W3] --workers 단독 가동 성공 (LAYOUT unbound 사망 안 함)"
TMP="$(mktemp -d)"; SAFE="$(basename "$TMP" | sed 's/[^A-Za-z0-9_-]/_/g')"; SESSION="agenphony-$SAFE"
( cd "$TMP" && git init -q )
HARNESS_PROJECT="$TMP" AGENT_CMD=cat bash "$ROOT/bin/agenphony-up.sh" --workers "dev:dev:sonnet,test:tester:haiku" >/dev/null 2>&1
rc=$?
np="$(tmux list-panes -s -t "$SESSION" 2>/dev/null | wc -l | tr -d ' ')"
tmux kill-session -t "$SESSION" 2>/dev/null || true
rm -rf "$TMP"
assert_eq "0" "$rc" "W3a --workers 단독 가동 성공"
# LEAD+PM+watcher(3) + dev+test(2) = 5 (리뷰어 없음 — --workers 에 리뷰어 미지정)
assert_eq "5" "$np" "W3b pane 5개 (LEAD/PM/watcher + dev/test)"

test_summary
