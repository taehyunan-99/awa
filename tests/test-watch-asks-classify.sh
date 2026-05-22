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

echo "[P8] ★ set -e 하에서 비-tool_use 줄이 process_jsonl_line 을 non-zero 로 끝내지 않음"
# 실전 결함 재현: watch_one_worker 는 set -euo pipefail. process_jsonl_line 이
#   비-tool_use 줄(system/user 등 대부분)에서 non-zero 반환하면 while-read 서브셸이 즉사 →
#   그 워커 jsonl 감시 영구 중단. tool_use 가 아닌 줄에서도 반드시 rc=0 이어야 함.
echo '{"permissions":{"allow":[]}}' > "$BOOTSET/dev.json"
for ntline in \
  '{"type":"system","subtype":"init"}' \
  '{"type":"user","message":{"content":"hi"}}' \
  '{"type":"file-history-snapshot"}' \
  '{"type":"assistant","message":{"content":[{"type":"text","text":"그냥 설명"}]}}' ; do
  ( set -euo pipefail
    process_jsonl_line "arch" "dev" "%5" "sid" "$ntline" ) >/dev/null 2>&1
  rc=$?
  assert_eq "0" "$rc" "P8 비-tool_use 줄 rc=0 ($(printf '%s' "$ntline" | head -c 30))"
done

echo "[P9] ★ set -e + while-read 루프(watch_one_worker 재현)가 비-tool_use 연속에도 생존"
# 비-tool_use 줄 여러 개 → tool_use 1개. 결함이면 첫 비-tool_use 에서 루프 사망해
#   마지막 tool_use 가 처리 안 됨 (MATRIX/USER-ASK 로그 누락).
: > "$SENDKEYS_LOG"; : > "$LOG"
echo '{"permissions":{"allow":["Bash(ls:*)"]}}' > "$BOOTSET/dev.json"
loop_rc=0
( set -euo pipefail
  printf '%s\n' \
    '{"type":"system","subtype":"init"}' \
    '{"type":"user","message":{"content":"x"}}' \
    "$(mk_tooluse Bash 'ls /tmp')" \
  | while IFS= read -r line; do
      process_jsonl_line "arch" "dev" "%5" "sid" "$line"
    done ) || loop_rc=$?
assert_eq "0" "$loop_rc" "P9 루프 set -e 생존"
assert_contains "$(cat "$LOG")" "MATRIX-ALLOWED" "P9 마지막 tool_use 처리됨 (루프 안 죽음)"

rm -rf "$HARNESS_PROJECT"   # 정정5(MINOR): mktemp -d 임시 디렉터리 정리
test_summary
