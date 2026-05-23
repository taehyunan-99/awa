#!/usr/bin/env bash
# permission-gate.sh: stdin JSON → permissionDecision JSON. 회색은 Task 4 에서.
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"
export HARNESS_PROJECT="$(mktemp -d)"
export PROJECT_ROOT="$HARNESS_PROJECT"
export HARNESS_ROOT="$ROOT"
( cd "$HARNESS_PROJECT" && git init -q )

BOOT="$HARNESS_PROJECT/.agent-harness/.boot-settings"
mkdir -p "$BOOT"
echo '{"permissions":{"allow":["Bash(ls:*)"]}}' > "$BOOT/dev.json"
mkdir -p "$HARNESS_PROJECT/config"
cat > "$HARNESS_PROJECT/config/lead-auto-allow.yaml" <<'YAML'
read-only:
  - "Bash(find:*)"
YAML

GATE="$ROOT/bin/permission-gate.sh"
run_gate() {  # $1=tool $2=input_json ; stdin event 합성
  local tool="$1" input="$2"
  printf '{"tool_name":"%s","tool_input":%s,"tool_use_id":"tu_123"}' "$tool" "$input" \
    | WORKER="dev-1" ENTRY_ROLE="dev" PROJECT_ROOT="$HARNESS_PROJECT" HARNESS_ROOT="$ROOT" bash "$GATE"
}

echo "[G1] matrix MATCH → permissionDecision=allow"
out="$(run_gate "Bash" '{"command":"ls -la"}')"
dec="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision')"
assert_eq "allow" "$dec" "G1 matrix allow"

echo "[G2] danger MATCH → permissionDecision=deny + incident 생성"
out="$(run_gate "Bash" '{"command":"rm -rf /tmp/x"}')"
dec="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision')"
assert_eq "deny" "$dec" "G2 danger deny"
inc_count="$(ls "$HARNESS_PROJECT/.agent-harness/state/incidents/"*.json 2>/dev/null | wc -l | tr -d ' ')"
[ "$inc_count" -ge 1 ]; assert_success "$?" "G2 incident 생성"

echo "[G3] auto-allow MATCH → allow + settings 에 패턴 추가"
out="$(run_gate "Bash" '{"command":"find . -name x"}')"
dec="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision')"
assert_eq "allow" "$dec" "G3 auto allow"
has="$(jq -r '[.permissions.allow[] | select(. == "Bash(find:*)")] | length' "$BOOT/dev.json")"
assert_eq "1" "$has" "G3 auto 패턴 학습"

echo "[G4] emit JSON 스키마 정합 (hookEventName=PreToolUse)"
ev="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.hookEventName')"
assert_eq "PreToolUse" "$ev" "G4 hookEventName"

echo "[G5] emit JSON 유효성 + stdout 오염 없음 (colon command → gray placeholder deny)"
out="$(run_gate "Bash" '{"command":"echo a:b:c"}')"
# 출력이 정확히 1줄 유효 JSON 인지 (stdout 에 로그/경고 안 섞임 — claude 파싱 필수).
lines="$(printf '%s' "$out" | grep -c .)"
assert_eq "1" "$lines" "G5 stdout 단일 JSON 줄 (오염 없음)"
printf '%s' "$out" | jq -e '.hookSpecificOutput.permissionDecision' >/dev/null 2>&1
assert_success "$?" "G5 emit JSON jq 파싱 가능"

echo "[G5b] reason 특수문자 안전 (jq -n 이스케이프) — 라이브러리 모드 source"
# PERM_GATE_LIB_ONLY=1 로 source 하면 main 미실행 → 함수만 로드 (stdin hang 회피).
out="$(PERM_GATE_LIB_ONLY=1 WORKER=x ENTRY_ROLE=dev PROJECT_ROOT="$HARNESS_PROJECT" HARNESS_ROOT="$ROOT" \
  bash -c 'source "'"$ROOT"'/bin/permission-gate.sh"; emit_deny "danger:rm \"q\" \\back"')"
printf '%s' "$out" | jq -e . >/dev/null 2>&1
assert_success "$?" "G5b 따옴표·역슬래시 reason 도 유효 JSON"
r="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason')"
assert_eq 'danger:rm "q" \back' "$r" "G5b reason 원형 보존"

test_summary
