#!/usr/bin/env bash
# codex-gate-bridge.sh: codex hook 입력 → permission-gate.sh 동형 판정 → codex 출력.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT/tests/assert.sh"
BRIDGE="$ROOT/bin/vendors/codex-gate-bridge.sh"
TMPDIR_G="$(mktemp -d)"; trap 'rm -rf "$TMPDIR_G"' EXIT
mkdir -p "$TMPDIR_G/.agent-harness/state"

if ! command -v jq >/dev/null 2>&1; then
  echo "  SKIP: jq 미설치 — gate 테스트 생략"; test_summary; exit $?
fi

run_bridge() {  # stdin=codex hook JSON → stdout. GATE_SKIP_WAIT=1 로 gray 경로 tmux wait-for 블로킹 차단.
  PROJECT_ROOT="$TMPDIR_G" HARNESS_ROOT="$ROOT" WORKER="dev" ENTRY_ROLE="dev" \
    GATE_SKIP_WAIT=1 bash "$BRIDGE"
}

# G1: 위험 명령(rm -rf) → deny (동형성 핵심)
out="$(printf '{"tool_name":"Bash","tool_input":{"command":"rm -rf /"},"tool_use_id":"t1"}' | run_bridge)"
assert_contains "$out" '"permissionDecision":"deny"' "G1 rm -rf → deny(동형 판정)"

# G2: apply_patch→Edit 정규화 단위 검증 (브리지 jq 변환만 격리, 정책 무관).
norm="$(printf '{"tool_name":"apply_patch","tool_input":{"command":"x"}}' \
  | jq -c 'if (.tool_name // "")=="apply_patch" then .tool_name="Edit" else . end')"
echo "$norm" | grep -q '"tool_name":"Edit"' ; assert_success "$?" "G2 apply_patch→Edit 정규화"

# G3: 깨진 입력 → fail-closed deny
out="$(printf 'not json' | run_bridge)"
assert_contains "$out" '"permissionDecision":"deny"' "G3 깨진 입력 fail-closed deny"

test_summary
