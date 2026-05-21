#!/usr/bin/env bash
# log-deny.sh 의 입출력 계약 검증.
# stdin JSON → permission-events.log 에 6필드 줄 append.
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh

ROOT="$(cd .. && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

LOG="$TMP/permission-events.log"

echo "[L1] 정상 JSON — tool_name=Bash + command=rm /tmp/x 추출"
echo '{"tool_name":"Bash","tool_input":{"command":"rm /tmp/x"}}' | \
  PERMISSION_EVENTS_LOG="$LOG" WORKER="dev" bash "$ROOT/bin/log-deny.sh"
rc=$?
assert_eq "0" "$rc" "L1 exit 0"
line="$(tail -1 "$LOG")"
assert_contains "$line" $'\tdev\t-\tPRE\tBash\trm /tmp/x' "L1 worker+PRE+tool+cmd"
nf="$(printf '%s' "$line" | awk -F'\t' '{print NF}')"
assert_eq "6" "$nf" "L1 6 필드"

echo "[L2] PERMISSION_EVENTS_LOG 미설정 — stderr 경고 + exit 0"
err="$(echo '{"tool_name":"Bash","tool_input":{"command":"echo x"}}' | \
  WORKER="dev" bash "$ROOT/bin/log-deny.sh" 2>&1 >/dev/null)"
rc=$?
assert_eq "0" "$rc" "L2 exit 0 (조용한 skip)"
assert_contains "$err" "PERMISSION_EVENTS_LOG env 미설정" "L2 stderr 경고"

echo "[L3] JSON 깨짐 — tool_name 추출 실패하지만 exit 0"
echo 'not-json garbage' | \
  PERMISSION_EVENTS_LOG="$LOG" WORKER="dev" bash "$ROOT/bin/log-deny.sh"
rc=$?
assert_eq "0" "$rc" "L3 exit 0 (조용한 처리)"

echo "[L4] tool_name 부재 — 빈 tool 필드로 append, NF=6 유지"
: > "$LOG"
echo '{"foo":"bar"}' | \
  PERMISSION_EVENTS_LOG="$LOG" WORKER="dev" bash "$ROOT/bin/log-deny.sh"
line="$(tail -1 "$LOG")"
nf="$(printf '%s' "$line" | awk -F'\t' '{print NF}')"
# printf '%s\t%s\t-\tPRE\t%s\t%s\n' 가 빈 tool/cmd 일 때도 정확히 6 필드 (awk 가 trailing empty 셈).
assert_eq "6" "$nf" "L4 NF=6 (빈 필드 포함 6 필드)"

echo "[L5] WORKER env 미설정 — stderr 경고 + 'unknown' 으로 기록"
: > "$LOG"
err="$(echo '{"tool_name":"Bash","tool_input":{"command":"ls"}}' | \
  PERMISSION_EVENTS_LOG="$LOG" bash "$ROOT/bin/log-deny.sh" 2>&1 >/dev/null)"
rc=$?
assert_eq "0" "$rc" "L5 exit 0 (기록은 진행)"
assert_contains "$err" "WORKER env 미설정" "L5 stderr 경고"
line="$(tail -1 "$LOG")"
assert_contains "$line" $'\tunknown\t-\tPRE\t' "L5 'unknown' worker 로 기록"

echo "[L6] CMD 안 탭/CR 무력화 — NF=6 유지"
: > "$LOG"
# JSON 값에 리터럴 탭 박기 (printf format 로 \t 해석 강제)
printf '{"tool_name":"Bash","tool_input":{"command":"echo a\tb"}}' | \
  PERMISSION_EVENTS_LOG="$LOG" WORKER="dev" bash "$ROOT/bin/log-deny.sh"
line="$(tail -1 "$LOG")"
nf="$(printf '%s' "$line" | awk -F'\t' '{print NF}')"
assert_eq "6" "$nf" "L6 탭 포함 cmd 도 NF=6"

test_summary
