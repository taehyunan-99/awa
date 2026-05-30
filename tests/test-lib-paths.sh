#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh

ROOT="$(cd .. && pwd)"
source "$ROOT/bin/lib.sh"

assert_eq "$ROOT" "$HARNESS_ROOT" "HARNESS_ROOT 가 하네스 루트"
assert_eq "$PROJECT_ROOT/.agent-harness" "$WORKSPACE" "WORKSPACE 경로"
assert_eq "agents" "$SESSION_DEFAULT" "기본 세션명"

# SESSION 미설정 → 자동명 폴백 (T3): awa-<basename of PROJECT_ROOT>
sess_auto="awa-$(basename "$PROJECT_ROOT")"
assert_eq "${sess_auto}:0.2" "$(target_of 2)" "SESSION 미설정 → 자동명 폴백"
assert_eq "${sess_auto}:0.4" "$(target_of 4)" "페인 인덱스 4 → target"

# SESSION 설정 → 활성 세션 존중 (세션 오버라이드/멀티팀)
SESSION=myteam
assert_eq "myteam:0.3" "$(target_of 3)" "SESSION 설정 → 활성 세션 존중"
unset SESSION

assert_eq "$PROJECT_ROOT/.agent-harness/.boot/dev.md" "$(boot_file dev)" "boot_file 경로"

test_summary
