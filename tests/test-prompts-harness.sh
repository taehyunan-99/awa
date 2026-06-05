#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
source ./harness-paths.sh
ROOT="$(cd .. && pwd)"
source "$HARNESS_BIN/lib.sh" >/dev/null 2>&1 || true

common="$(cat "$HARNESS_PROMPTS/_common.md")"
assert_contains "$common" "events.log" "_common 에 events.log 보조 규약"
assert_contains "$common" "scope" "_common 에 scope 준수 언급"

dev="$(cat "$(resolve_role_file "$HARNESS_PROMPTS" dev)")"
assert_contains "$dev" "allowed_paths" "dev 역할에 scope 준수 규칙"

test_summary
