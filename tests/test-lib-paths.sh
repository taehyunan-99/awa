#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh

ROOT="$(cd .. && pwd)"
source "$ROOT/bin/lib.sh"

assert_eq "$ROOT" "$REPO_ROOT" "REPO_ROOT 가 repo 루트"
assert_eq "$ROOT/workspace" "$WORKSPACE" "WORKSPACE 경로"
assert_eq "agents" "$SESSION_DEFAULT" "기본 세션명"

assert_eq "agents:0.2" "$(target_of 2)" "페인 인덱스 2 → target"
assert_eq "agents:0.4" "$(target_of 4)" "페인 인덱스 4 → target"

assert_eq "$ROOT/workspace/.boot/dev.md" "$(boot_file dev)" "boot_file 경로"

test_summary
