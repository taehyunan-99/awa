#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
source ./harness-paths.sh
ROOT="$(cd .. && pwd)"
source "$HARNESS_BIN/lib.sh"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export WORKSPACE="$TMP"

# 초기: 파일 없음 → state_get 빈값
assert_eq "" "$(state_get phase)" "초기 phase 빈값"

# state_set 후 read 멱등
state_set phase architecture
assert_eq "architecture" "$(state_get phase)" "phase 기록·복원"
state_set phase implementation
assert_eq "implementation" "$(state_get phase)" "phase 갱신(사용자 명령 반영)"

# 다른 키 독립
state_set last_task 101
assert_eq "101" "$(state_get last_task)" "다른 키 독립 보존"
assert_eq "implementation" "$(state_get phase)" "기존 키 유지"

test_summary
