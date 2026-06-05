#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
source ./harness-paths.sh
ROOT="$(cd .. && pwd)"
source "$HARNESS_BIN/lib.sh"

unset SESSION_OVERRIDE PROFILE_SESSION SESSION 2>/dev/null || true

# T3 이후 폴백은 자동명("awa-<basename of PROJECT_ROOT>") — 이 test 의 cwd 기준.
sess_auto="awa-$(basename "$PROJECT_ROOT")"

# target_in <window> <pane> → session:window.pane (resolve_session 사용)
assert_eq "${sess_auto}:0.2" "$(target_in 0 2)" "window 0 pane 2"
assert_eq "${sess_auto}:1.3" "$(target_in 1 3)" "window 1(review) pane 3"

PROFILE_SESSION="ft"
assert_eq "ft:1.2" "$(target_in 1 2)" "세션명 resolve_session 반영"
unset PROFILE_SESSION

# 기존 target_of 회귀 (window 0 고정 유지)
assert_eq "${sess_auto}:0.4" "$(target_of 4)" "target_of 기존 동작 유지"

test_summary
