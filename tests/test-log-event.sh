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

# T7.1 — events.log 자기자신 변경은 skip
TMP="$(mktemp -d)"; mkdir -p "$TMP/.agent-harness"
EVENTS_LOG="$TMP/.agent-harness/events.log"
REPO_ROOT="$TMP"
HARNESS_WORKER=worker1
input='{"tool_input":{"file_path":"'"$TMP"'/.agent-harness/events.log"}}'
out="$(printf '%s' "$input" | EVENTS_LOG="$EVENTS_LOG" REPO_ROOT="$REPO_ROOT" HARNESS_WORKER="$HARNESS_WORKER" bash "$ROOT/bin/log-event.sh")"
assert_eq "" "$(cat "$EVENTS_LOG" 2>/dev/null)" "events.log 자기변경 skip"

# T7.2 — tasks/results 변경은 기록됨
input='{"tool_input":{"file_path":"'"$TMP"'/.agent-harness/results/1.md"}}'
printf '%s' "$input" | EVENTS_LOG="$EVENTS_LOG" REPO_ROOT="$REPO_ROOT" HARNESS_WORKER="$HARNESS_WORKER" bash "$ROOT/bin/log-event.sh"
grep -q "results/1.md" "$EVENTS_LOG"; assert_success "$?" "results/ 는 기록됨"

# T7.3 — .review-cursor.* 는 skip
: > "$EVENTS_LOG"
input='{"tool_input":{"file_path":"'"$TMP"'/.agent-harness/.review-cursor.spec-rev"}}'
printf '%s' "$input" | EVENTS_LOG="$EVENTS_LOG" REPO_ROOT="$REPO_ROOT" HARNESS_WORKER="$HARNESS_WORKER" bash "$ROOT/bin/log-event.sh"
assert_eq "" "$(cat "$EVENTS_LOG")" ".review-cursor.* skip"

# T7.4 — review/ 는 skip (verdict 산출은 events.log 오염 금지)
: > "$EVENTS_LOG"
input='{"tool_input":{"file_path":"'"$TMP"'/.agent-harness/review/frontend-todo.security-rev.md"}}'
printf '%s' "$input" | EVENTS_LOG="$EVENTS_LOG" REPO_ROOT="$REPO_ROOT" HARNESS_WORKER="$HARNESS_WORKER" bash "$ROOT/bin/log-event.sh"
assert_eq "" "$(cat "$EVENTS_LOG")" "review/ verdict skip"

# T7.5 — /private 심볼릭링크 정규화: REPO_ROOT=/tmp 별칭인데 file_path 가 /private/tmp 절대경로로
#   와도 review/ skip 적용돼야 함(macOS /tmp→private/tmp). 결함 F: 미정규화 시 skip 우회→오염.
#   /tmp 가 /private/tmp 심볼릭링크인 환경(macOS)에서만 의미 — 그 외 OS 는 skip(가드).
if [ "$(cd /tmp 2>/dev/null && pwd -P)" = "/private/tmp" ]; then
  ALIAS_ROOT="/tmp/awa-logevent-f-$$"; REAL_ROOT="/private${ALIAS_ROOT}"  # /tmp/X → /private/tmp/X
  mkdir -p "$ALIAS_ROOT/.agent-harness/review"
  EVENTS_LOG="$ALIAS_ROOT/.agent-harness/events.log"; : > "$EVENTS_LOG"
  input='{"tool_input":{"file_path":"'"$REAL_ROOT"'/.agent-harness/review/frontend-todo.reviewer-quality.md"}}'
  printf '%s' "$input" | EVENTS_LOG="$EVENTS_LOG" REPO_ROOT="$ALIAS_ROOT" HARNESS_WORKER="$HARNESS_WORKER" bash "$ROOT/bin/log-event.sh"
  assert_eq "" "$(cat "$EVENTS_LOG")" "review/ skip — /private 정규화(결함 F)"
  rm -rf "$ALIAS_ROOT"
else
  echo "[SKIP] T7.5 /private 정규화 — /tmp 가 /private/tmp 심볼릭링크 아님(비-macOS)"
fi

rm -rf "$TMP"

test_summary
