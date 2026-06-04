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
cat > "$HARNESS_PROJECT/config/orch-auto-allow.yaml" <<'YAML'
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

# ★ 회색(gate_gray) 케이스 격리 (e2e 발견): gate_gray 는 tmux wait-for 로 lead 응답을
#   블로킹 대기한다. 단위 테스트가 이를 그대로 타면 *실제 tmux 서버* 채널에 wait-for 를
#   걸어 — 서버가 있으면(다른 세션·e2e) 대기자 없는 채널에 진짜 블로킹 → hang (G5 는 POLL_MAX
#   미설정이라 기본 540초!), 채널 woken 잔존에 따라 비결정적(실측 규명). 단위 테스트는 외부
#   tmux 상태에 의존하면 안 되므로 GATE_SKIP_WAIT=1 로 wait-for 호출을 건너뛰고 .response
#   검증 로직만 결정적으로 본다. 실제 wait-for 블로킹 경로는 probe-permission-gate(E3) +
#   run_with_timeout RT 테스트가 커버. ★ G5 부터 회색이므로 여기서 설정 (G5/G6/G7/G8 전부 덮음).
export GATE_SKIP_WAIT=1

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

echo "[G6] 회색 + .response=approve-once 미리 깔림 → allow"
# gate 가 uuid 를 생성하므로, .response 를 특정 uuid 로 못 깐다 →
# GATE_TEST_UUID env 로 uuid 고정 (permission-gate.sh 가 테스트시 이 env 사용).
export GATE_TEST_UUID="fixed-test-uuid"
export GATE_POLL_MAX="1"   # 1초 상한 (테스트 가속)
RESP_DIR="$HARNESS_PROJECT/.agent-harness/state/pending-asks"
mkdir -p "$RESP_DIR"
printf 'approve-once' > "$RESP_DIR/${GATE_TEST_UUID}.response"
out="$(run_gate "Bash" '{"command":"npm test"}')"
dec="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision')"
assert_eq "allow" "$dec" "G6 회색 approve-once → allow"
unset GATE_TEST_UUID GATE_POLL_MAX

echo "[G7] 회색 + .response 없음 → deny (fail-closed)"
# 핵심: "응답 파일 없음 = deny" 라는 fail-closed 단일 방어선 검증. GATE_SKIP_WAIT 로 wait-for
#   를 건너뛰어도 .response 가 없으면 deny — 격리와 무관하게 방어선 자체를 검증한다.
export GATE_TEST_UUID="no-resp-uuid"
export GATE_POLL_MAX="1"
out="$(run_gate "Bash" '{"command":"npm run build"}')"
dec="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision')"
assert_eq "deny" "$dec" "G7 응답없음 → deny (fail-closed)"
unset GATE_TEST_UUID GATE_POLL_MAX

echo "[G8] 회색 + .response=approve-permanent:command-group → allow + 학습"
export GATE_TEST_UUID="perm-uuid"
export GATE_POLL_MAX="1"
printf 'approve-permanent:command-group' > "$RESP_DIR/${GATE_TEST_UUID}.response"
out="$(run_gate "Bash" '{"command":"npm test foo"}')"
dec="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision')"
assert_eq "allow" "$dec" "G8 approve-permanent allow"
learned="$(jq -r '[.permissions.allow[] | select(. == "Bash(npm test:*)")] | length' "$BOOT/dev.json")"
assert_eq "1" "$learned" "G8 command-group 학습 (Bash(npm test:*))"
unset GATE_TEST_UUID GATE_POLL_MAX

echo "[G9] 회색 + approve-permanent:command-group + 복합명령 → allow 하되 학습 안 함 (강등)"
# 복합 명령(&&)으로 검증 — rm 등 별도 의미를 끌어들이지 않는 순수 복합 케이스.
export GATE_TEST_UUID="compound-uuid"
export GATE_POLL_MAX="1"
printf 'approve-permanent:command-group' > "$RESP_DIR/${GATE_TEST_UUID}.response"
before="$(jq '.permissions.allow | length' "$BOOT/dev.json")"
out="$(run_gate "Bash" '{"command":"cd src && ./run.sh build"}')"
dec="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision')"
assert_eq "allow" "$dec" "G9 복합명령 approve-permanent → allow (강등)"
after="$(jq '.permissions.allow | length' "$BOOT/dev.json")"
assert_eq "$before" "$after" "G9 복합명령은 학습 안 됨 (allow length 불변)"
clean="$(jq -r '[.permissions.allow[] | select(test("\n"))] | length' "$BOOT/dev.json")"
assert_eq "0" "$clean" "G9 줄바꿈 든 패턴 0"
unset GATE_TEST_UUID GATE_POLL_MAX

echo "[G10] 회색 + approve-permanent + 단순명령은 정상 학습 (G9 강등이 단순명령엔 영향 없음 회귀)"
export GATE_TEST_UUID="simple-uuid"
export GATE_POLL_MAX="1"
printf 'approve-permanent:command-group' > "$RESP_DIR/${GATE_TEST_UUID}.response"
out="$(run_gate "Bash" '{"command":"yarn lint src"}')"
dec="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision')"
assert_eq "allow" "$dec" "G10 단순명령 approve-permanent → allow"
learned="$(jq -r '[.permissions.allow[] | select(. == "Bash(yarn lint:*)")] | length' "$BOOT/dev.json")"
assert_eq "1" "$learned" "G10 단순명령은 정상 학습 (Bash(yarn lint:*))"
unset GATE_TEST_UUID GATE_POLL_MAX
unset GATE_SKIP_WAIT

test_summary
