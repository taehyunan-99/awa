#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"
source "$ROOT/bin/lib.sh"

# 기본: 인자 없고 env 없으면 자동명 (agents-<basename of PROJECT_ROOT>) — T3.
# repo basename 이 'tmux-agent-team' 이므로 'agents-tmux-agent-team'.
unset SESSION_OVERRIDE PROFILE_SESSION SESSION 2>/dev/null || true
expected_auto="agents-$(basename "$PROJECT_ROOT")"
assert_eq "$expected_auto" "$(resolve_session)" "기본 → 자동명 폴백"

# PROFILE_SESSION 우선 (team-up: 프로파일 SESSION)
PROFILE_SESSION="featteam"
assert_eq "featteam" "$(resolve_session)" "PROFILE_SESSION 반영"

# SESSION_OVERRIDE 최우선 (테스트/멀티팀)
SESSION_OVERRIDE="ovr"
assert_eq "ovr" "$(resolve_session)" "SESSION_OVERRIDE 최우선"
unset SESSION_OVERRIDE PROFILE_SESSION

test_summary
