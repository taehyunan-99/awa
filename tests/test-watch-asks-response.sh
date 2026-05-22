#!/usr/bin/env bash
# process_response: approve-once/approve-permanent/deny → send-keys + add_to_allow.
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"
export HARNESS_PROJECT="$(mktemp -d)"
( cd "$HARNESS_PROJECT" && git init -q )
export PROJECT_ROOT="$HARNESS_PROJECT" HARNESS_ROOT="$ROOT"
export STATE_DIR="$PROJECT_ROOT/.agent-harness/state"
export LOG="$STATE_DIR/watch-asks.log"
mkdir -p "$STATE_DIR/pending-asks"
BOOTSET="$PROJECT_ROOT/.agent-harness/.boot-settings"; mkdir -p "$BOOTSET"
echo '{"permissions":{"allow":[]}}' > "$BOOTSET/dev.json"
export SENDKEYS_LOG="$STATE_DIR/sendkeys.log"
export NOTIFY_DRY_RUN=1

# shellcheck disable=SC1091
WATCH_ASKS_LIB_ONLY=1 source "$ROOT/bin/watch-asks.sh"
send_keys_safe() { printf '%s %s\n' "$1" "$2" >> "$SENDKEYS_LOG"; }

mk_meta() {  # $1=uuid $2=tool $3=command
  jq -n --arg w arch --arg r dev --arg p '%5' --arg s sid --arg tool "$2" \
        --argjson inp "{\"command\":\"$3\"}" --argjson ts 100 \
    '{worker:$w, entry_role:$r, pane:$p, session:$s, tool:$tool, input:$inp, timestamp:$ts}' \
    > "$STATE_DIR/pending-asks/$1.json"
}

echo "[R1] approve-once → send-keys 1 + meta/response 삭제"
mk_meta u1 Bash "custom x"
echo "approve-once" > "$STATE_DIR/pending-asks/u1.response"
: > "$SENDKEYS_LOG"
process_response "$STATE_DIR/pending-asks/u1.response"
assert_contains "$(cat "$SENDKEYS_LOG")" "%5 1" "R1 send-keys 1"
[ ! -f "$STATE_DIR/pending-asks/u1.json" ]; assert_success "$?" "R1 meta 삭제"
[ ! -f "$STATE_DIR/pending-asks/u1.response" ]; assert_success "$?" "R1 response 삭제"

echo "[R2] approve-permanent:command-group → add_to_allow + send-keys 2"
mk_meta u2 Bash "custom-tool"
echo "approve-permanent:command-group" > "$STATE_DIR/pending-asks/u2.response"
: > "$SENDKEYS_LOG"
process_response "$STATE_DIR/pending-asks/u2.response"
assert_contains "$(cat "$SENDKEYS_LOG")" "%5 2" "R2 send-keys 2"
assert_contains "$(cat "$BOOTSET/dev.json")" "Bash(custom-tool:*)" "R2 allow 추가"

echo "[R3] deny → send-keys 3"
mk_meta u3 Bash "x"
echo "deny" > "$STATE_DIR/pending-asks/u3.response"
: > "$SENDKEYS_LOG"
process_response "$STATE_DIR/pending-asks/u3.response"
assert_contains "$(cat "$SENDKEYS_LOG")" "%5 3" "R3 send-keys 3"

echo "[R4] meta 없는 response → response 만 삭제"
echo "approve-once" > "$STATE_DIR/pending-asks/orphan.response"
process_response "$STATE_DIR/pending-asks/orphan.response"
[ ! -f "$STATE_DIR/pending-asks/orphan.response" ]; assert_success "$?" "R4 orphan response 삭제"

echo "[R5] approve-permanent:exact → 정확 패턴"
mk_meta u5 Bash "deploy prod"
echo "approve-permanent:exact" > "$STATE_DIR/pending-asks/u5.response"
process_response "$STATE_DIR/pending-asks/u5.response"
assert_contains "$(cat "$BOOTSET/dev.json")" "Bash(deploy prod)" "R5 exact 패턴"

rm -rf "$HARNESS_PROJECT"   # 정정5(MINOR): mktemp -d 임시 디렉터리 정리
test_summary
