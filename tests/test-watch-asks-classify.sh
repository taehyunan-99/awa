#!/usr/bin/env bash
# process_jsonl_line 6단계 분류 (matrix/danger/lead-auto-allow/pending).
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"
export HARNESS_PROJECT="$(mktemp -d)"
( cd "$HARNESS_PROJECT" && git init -q )
export PROJECT_ROOT="$HARNESS_PROJECT" HARNESS_ROOT="$ROOT"
export STATE_DIR="$PROJECT_ROOT/.agent-harness/state"
export LOG="$STATE_DIR/watch-asks.log"
mkdir -p "$STATE_DIR/pending-asks" "$STATE_DIR/incidents" "$STATE_DIR/removal-requests"
BOOTSET="$PROJECT_ROOT/.agent-harness/.boot-settings"; mkdir -p "$BOOTSET"
mkdir -p "$PROJECT_ROOT/config"
cat > "$PROJECT_ROOT/config/lead-auto-allow.yaml" <<'EOF'
safe-test:
  - "Bash(npm test:*)"
EOF

export SENDKEYS_LOG="$STATE_DIR/sendkeys.log"
export NOTIFY_DRY_RUN=1

# 함수만 로드 (메인 루프 skip).
# shellcheck disable=SC1091
WATCH_ASKS_LIB_ONLY=1 source "$ROOT/bin/watch-asks.sh"
# send_keys_safe 를 테스트용으로 오버라이드.
send_keys_safe() { printf '%s %s\n' "$1" "$2" >> "$SENDKEYS_LOG"; }

mk_tooluse() {  # $1=tool $2=command
  printf '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"%s","input":{"command":"%s"}}]}}' "$1" "$2"
}

echo "[P1] matrix MATCH → send-keys 2 + log MATRIX-ALLOWED"
echo '{"permissions":{"allow":["Bash(ls:*)"]}}' > "$BOOTSET/dev.json"
: > "$SENDKEYS_LOG"
process_jsonl_line "arch" "dev" "%5" "sid" "$(mk_tooluse Bash 'ls /tmp')"
assert_contains "$(cat "$SENDKEYS_LOG")" "%5 2" "P1 send-keys 2"
assert_contains "$(cat "$LOG")" "MATRIX-ALLOWED" "P1 log"

echo "[P2] danger MATCH → send-keys 3 + incident"
echo '{"permissions":{"allow":[]}}' > "$BOOTSET/dev.json"
: > "$SENDKEYS_LOG"
process_jsonl_line "arch" "dev" "%5" "sid" "$(mk_tooluse Bash 'rm -rf /tmp/x')"
assert_contains "$(cat "$SENDKEYS_LOG")" "%5 3" "P2 send-keys 3"
ls "$STATE_DIR/incidents"/*.json >/dev/null 2>&1; assert_success "$?" "P2 incident 생성"
assert_contains "$(cat "$LOG")" "AUTO-DENIED" "P2 log"

echo "[P3] lead-auto-allow MATCH → add_to_allow + send-keys 2"
echo '{"permissions":{"allow":[]}}' > "$BOOTSET/dev.json"
: > "$SENDKEYS_LOG"
process_jsonl_line "arch" "dev" "%5" "sid" "$(mk_tooluse Bash 'npm test foo')"
assert_contains "$(cat "$SENDKEYS_LOG")" "%5 2" "P3 send-keys 2"
assert_contains "$(cat "$BOOTSET/dev.json")" "Bash(npm test:*)" "P3 allow 추가"
assert_contains "$(cat "$LOG")" "LEAD-AUTO-ALLOWED" "P3 log"

echo "[P4] 회색 → pending-ask + USER-ASK"
echo '{"permissions":{"allow":[]}}' > "$BOOTSET/dev.json"
: > "$SENDKEYS_LOG"
process_jsonl_line "arch" "dev" "%5" "sid" "$(mk_tooluse Bash 'custom-tool x')"
ls "$STATE_DIR/pending-asks"/*.json >/dev/null 2>&1; assert_success "$?" "P4 pending-ask 생성"
assert_contains "$(cat "$LOG")" "USER-ASK" "P4 log"
[ ! -s "$SENDKEYS_LOG" ]; assert_success "$?" "P4 send-keys 없음 (응답 대기)"

echo "[P5] rm 보고 (assistant text) → removal-request"
rmline='{"type":"assistant","message":{"content":[{"type":"text","text":"@lead: rm src/old.py — deprecated"}]}}'
process_jsonl_line "arch" "dev" "%5" "sid" "$rmline"
ls "$STATE_DIR/removal-requests"/*.json >/dev/null 2>&1; assert_success "$?" "P5 removal-request 생성"

echo "[P6] danger 가 lead-auto-allow 보다 먼저 (위험 우선)"
echo '{"permissions":{"allow":[]}}' > "$BOOTSET/dev.json"
: > "$SENDKEYS_LOG"
process_jsonl_line "arch" "dev" "%5" "sid" "$(mk_tooluse Bash 'sudo rm x')"
assert_contains "$(cat "$SENDKEYS_LOG")" "%5 3" "P6 위험 우선 send-keys 3"

echo "[P7] E4 send-keys 실패 → workers.list inactive 표시 (spec §6 E4)"
printf 'arch %%5 sid /tmp/a.jsonl dev\n' > "$STATE_DIR/workers.list"
mark_worker_inactive "%5"
assert_contains "$(cat "$STATE_DIR/workers.list")" "# inactive: arch %5" "P7 inactive heading"
mark_worker_inactive "%5"   # 멱등: 이미 inactive 면 중복 prefix 안 함
n="$(grep -c '^# inactive:' "$STATE_DIR/workers.list")"
assert_eq "1" "$n" "P7 멱등 (중복 prefix 없음)"

rm -rf "$HARNESS_PROJECT"   # 정정5(MINOR): mktemp -d 임시 디렉터리 정리
test_summary
