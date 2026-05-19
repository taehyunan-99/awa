#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
EV="$TMP/events.log"; : > "$EV"

# log-event.sh 는 stdin 으로 hook JSON 받아 5필드 라인을 EVENTS_LOG 에 append.
# 워커명은 HARNESS_WORKER env. 경로는 REPO_ROOT 기준 상대경로화.
echo '{"tool_input":{"file_path":"'"$ROOT"'/src/auth/login.ts"}}' \
  | HARNESS_WORKER=dev HARNESS_TASK=101 EVENTS_LOG="$EV" REPO_ROOT="$ROOT" \
    bash "$ROOT/bin/log-event.sh"

line="$(cat "$EV")"
assert_contains "$line" "dev" "워커명 기록"
assert_contains "$line" "101" "task id 기록"
assert_contains "$line" "modify" "action=modify"
assert_contains "$line" "src/auth/login.ts" "repo 상대경로화"
fields="$(awk -F'\t' '{print NF}' "$EV")"
assert_eq "5" "$fields" "정확히 5필드(탭 구분)"

test_summary
