#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/workspace"
EV="$TMP/workspace/events.log"; : > "$EV"

# 1. dispatch 가 .harness-task.<worker> 기록 (dispatch 의 기록 로직만 검증 —
#    tmux/세션 없이: write_harness_task 헬퍼를 lib.sh 에 두고 dispatch 가 호출.
#    헬퍼 단위 검증.)
source "$ROOT/bin/lib.sh"
WORKSPACE="$TMP/workspace"
write_harness_task dev 101
assert_eq "101" "$(cat "$TMP/workspace/.harness-task.dev")" "dispatch 가 task 기록"

# 2. log-event.sh: HARNESS_TASK env 없고 .harness-task.<worker> 있으면 그 값 사용
echo '{"tool_input":{"file_path":"'"$TMP"'/src/a.ts"}}' \
  | HARNESS_WORKER=dev EVENTS_LOG="$EV" REPO_ROOT="$TMP" \
    bash "$ROOT/bin/log-event.sh"
line="$(cat "$EV")"
t="$(printf '%s' "$line" | awk -F'\t' '{print $3}')"
assert_eq "101" "$t" "hook 이 .harness-task 에서 task 읽음(env 없을 때)"

# 3. HARNESS_TASK env 있으면 env 우선
: > "$EV"
echo '{"tool_input":{"file_path":"'"$TMP"'/src/b.ts"}}' \
  | HARNESS_WORKER=dev HARNESS_TASK=999 EVENTS_LOG="$EV" REPO_ROOT="$TMP" \
    bash "$ROOT/bin/log-event.sh"
t2="$(awk -F'\t' '{print $3}' "$EV")"
assert_eq "999" "$t2" "env HARNESS_TASK 우선"

# 4. 둘 다 없으면 - (기존 동작 보존)
: > "$EV"; rm -f "$TMP/workspace/.harness-task.unknown"
echo '{"tool_input":{"file_path":"'"$TMP"'/src/c.ts"}}' \
  | EVENTS_LOG="$EV" REPO_ROOT="$TMP" bash "$ROOT/bin/log-event.sh"
t3="$(awk -F'\t' '{print $3}' "$EV")"
assert_eq "-" "$t3" "task 미상시 - (기존 보존)"

test_summary
