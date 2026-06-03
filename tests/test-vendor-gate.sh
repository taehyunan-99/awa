#!/usr/bin/env bash
# codex-gate-bridge.sh: codex hook 입력 → permission-gate.sh 동형 판정 → codex 출력.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT/tests/assert.sh"
BRIDGE="$ROOT/bin/vendors/codex-gate-bridge.sh"
TMPDIR_G="$(mktemp -d)"; trap 'rm -rf "$TMPDIR_G"' EXIT
mkdir -p "$TMPDIR_G/.agent-harness/state"
mkdir -p "$TMPDIR_G/.agent-harness/review"   # apply_patch verdict 경로 특례 검증용

if ! command -v jq >/dev/null 2>&1; then
  echo "  SKIP: jq 미설치 — gate 테스트 생략"; test_summary; exit $?
fi

run_bridge() {  # stdin=codex hook JSON → stdout. GATE_SKIP_WAIT=1 로 gray 경로 tmux wait-for 블로킹 차단.
  #   HARNESS_PROJECT 고정: lib.sh source 시 resolve_project_root 가 PROJECT_ROOT 를 cwd
  #   toplevel(=하니스 레포)로 덮어쓰는 걸 차단. bridge 가 이제 HARNESS_PROJECT 를 전파하므로
  #   실제 codex hook 경로(cwd=PROJECT_ROOT)와 동형. ENTRY_ROLE 인자(기본 dev)로 역할 가변.
  PROJECT_ROOT="$TMPDIR_G" HARNESS_PROJECT="$TMPDIR_G" HARNESS_ROOT="$ROOT" \
    WORKER="${1:-dev}" ENTRY_ROLE="${1:-dev}" \
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

# === apply_patch 경로 추출 실판정 (2026-06-03 라이브 결함: codex 주력 파일쓰기 도구) ===
#   codex apply_patch hook payload 는 tool_input.command 에 patch 본문(*** Add File: <path>)을
#   통째로 담는다 — file_path 필드 없음. 기존 bridge 는 경로를 못 뽑아 빈 file_path → gray →
#   USER-ASK → DENY → codex verdict 영구 소실. 수정: patch 본문에서 경로 추출 후 각각 gate 호출.

# G4: 리뷰어가 apply_patch 로 verdict(review/) 다중 Add File → allow(빈출력)
#   reviewer 역할로 실행 — review/ 는 공통산출 특례라 settings 무관 allow.
PATCH_OK='*** Begin Patch
*** Add File: .agent-harness/review/engineer-t.security-rev.md
*** Add File: .agent-harness/.review-cursor.security-rev
*** End Patch'
out="$(printf '%s' "$(jq -nc --arg c "$PATCH_OK" '{tool_name:"apply_patch",tool_input:{command:$c}}')" | run_bridge reviewer)"
assert_eq "" "$out" "G4 apply_patch verdict 다중 Add File → allow(빈출력 통과)"

# G5: apply_patch 가 verdict + 시스템경로(/etc/passwd) 혼합 → deny (한 경로라도 위험이면 전체 차단)
PATCH_MIX='*** Begin Patch
*** Add File: .agent-harness/review/x.security-rev.md
*** Update File: /etc/passwd
*** End Patch'
out="$(printf '%s' "$(jq -nc --arg c "$PATCH_MIX" '{tool_name:"apply_patch",tool_input:{command:$c}}')" | run_bridge reviewer)"
assert_contains "$out" '"permissionDecision":"deny"' "G5 apply_patch verdict+/etc 혼합 → deny(원자적 fail-safe)"

# G6: apply_patch 트래버설 탈출(review/../../../) → deny
PATCH_TRAV='*** Begin Patch
*** Add File: .agent-harness/review/../../../tmp/evil.txt
*** End Patch'
out="$(printf '%s' "$(jq -nc --arg c "$PATCH_TRAV" '{tool_name:"apply_patch",tool_input:{command:$c}}')" | run_bridge reviewer)"
assert_contains "$out" '"permissionDecision":"deny"' "G6 apply_patch 트래버설 탈출 → deny"

# G7: 리뷰어가 apply_patch 로 코드파일(calc.sh) 패치 → deny (read-only 격리 유지)
PATCH_CODE='*** Begin Patch
*** Update File: calc.sh
*** End Patch'
out="$(printf '%s' "$(jq -nc --arg c "$PATCH_CODE" '{tool_name:"apply_patch",tool_input:{command:$c}}')" | run_bridge reviewer)"
assert_contains "$out" '"permissionDecision":"deny"' "G7 reviewer apply_patch 코드파일 → deny(격리)"

# G8: 경로 추출 0건(빈 패치) → 기존 gray 차단 보존 (보안 약화 없음)
PATCH_EMPTY='*** Begin Patch
*** End Patch'
out="$(printf '%s' "$(jq -nc --arg c "$PATCH_EMPTY" '{tool_name:"apply_patch",tool_input:{command:$c}}')" | run_bridge reviewer)"
assert_contains "$out" '"permissionDecision":"deny"' "G8 빈 패치(경로0) → deny(gray 차단 보존)"

test_summary
