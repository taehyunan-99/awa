#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh

ROOT="$(cd .. && pwd)"
TMP_PROJ="$(mktemp -d)"; ( cd "$TMP_PROJ" && git init -q )
# ★ 정규화(pwd -P) 자격검증은 부모 디렉토리가 *존재*해야 cd 성공 → 특례 부여.
#   events.log·.harness-state 부모 = .agent-harness/ 자체, results/* 부모 = results/.
#   정상 케이스(1~3·10)가 정규화 후에도 통과하도록 셋업에서 부모 디렉토리를 만든다.
mkdir -p "$TMP_PROJ/.agent-harness/results"
cleanup() { rm -rf "$TMP_PROJ"; }
trap cleanup EXIT

run_gate() {
  local event="$1"
  # HARNESS_PROJECT 도 설정: lib.sh 가 source 시 resolve_project_root 로 PROJECT_ROOT 를
  # 무조건 재계산(L27)하므로, env PROJECT_ROOT 만으로는 cwd(=tests/, 하니스 git repo) 의
  # toplevel 로 덮어써진다. test-dev-write-allow.sh 와 동일하게 HARNESS_PROJECT 로 격리 고정.
  printf '%s' "$event" | \
    WORKER="research1" ENTRY_ROLE="researcher" \
    PROJECT_ROOT="$TMP_PROJ" HARNESS_PROJECT="$TMP_PROJ" HARNESS_ROOT="$ROOT" \
    GATE_SKIP_WAIT=1 bash "$ROOT/bin/permission-gate.sh"
}

# 1) results/ 쓰기 → allow (읽기전용 역할이라도)
EV_RESULTS=$(jq -nc --arg p "$TMP_PROJ/.agent-harness/results/t1.md" \
  '{tool_name:"Write", tool_input:{file_path:$p, content:"x"}, tool_use_id:"u1"}')
OUT="$(run_gate "$EV_RESULTS")"
assert_contains "$OUT" '"permissionDecision":"allow"' "results/ Write 특례 allow"
assert_contains "$OUT" "common-output" "특례 사유 표시"

# 2) events.log 쓰기 → allow
EV_EVENTS=$(jq -nc --arg p "$TMP_PROJ/.agent-harness/events.log" \
  '{tool_name:"Edit", tool_input:{file_path:$p}, tool_use_id:"u2"}')
OUT2="$(run_gate "$EV_EVENTS")"
assert_contains "$OUT2" '"permissionDecision":"allow"' "events.log Edit 특례 allow"

# 3) .harness-state 쓰기 → allow
EV_STATE=$(jq -nc --arg p "$TMP_PROJ/.agent-harness/.harness-state" \
  '{tool_name:"Write", tool_input:{file_path:$p, content:"x"}, tool_use_id:"u3"}')
OUT3="$(run_gate "$EV_STATE")"
assert_contains "$OUT3" '"permissionDecision":"allow"' ".harness-state Write 특례 allow"

# 4) 위조 차단: 비-하니스 경로 Write 는 특례 미적용
EV_FORGE=$(jq -nc --arg p "$TMP_PROJ/src/app.js" \
  '{tool_name:"Write", tool_input:{file_path:$p, content:"x"}, tool_use_id:"u4"}')
OUT4="$(run_gate "$EV_FORGE")"
assert_not_contains "$OUT4" "common-output" "비-하니스 경로엔 특례 미적용"

# 5) 경로 위조 방어: results 가 경로 중간에 섞여도 prefix 가 아니면 미적용
EV_TRICK=$(jq -nc --arg p "$TMP_PROJ/evil/.agent-harness/results/x.md" \
  '{tool_name:"Write", tool_input:{file_path:$p, content:"x"}, tool_use_id:"u5"}')
OUT5="$(run_gate "$EV_TRICK")"
assert_not_contains "$OUT5" "common-output" "PROJECT_ROOT prefix 아닌 results 는 특례 미적용"

# === 보안: 트래버설·심링크 탈출 차단 (C1/C2 회귀) ===

# 6) .. 트래버설 — results/ prefix 로 시작해도 PROJECT_ROOT 탈출 시 특례 미적용
EV_DOTDOT=$(jq -nc --arg p "$TMP_PROJ/.agent-harness/results/../../../etc/passwd" \
  '{tool_name:"Write", tool_input:{file_path:$p, content:"x"}, tool_use_id:"u6"}')
OUT6="$(run_gate "$EV_DOTDOT")"
assert_not_contains "$OUT6" "common-output" ".. 트래버설은 특례 미적용(탈출 차단)"

# 7) 심링크 탈출 — results/link → /tmp 심링크 통한 외부 쓰기 차단
ln -s /tmp "$TMP_PROJ/.agent-harness/results/link" 2>/dev/null || true
EV_SYMLINK=$(jq -nc --arg p "$TMP_PROJ/.agent-harness/results/link/evil.txt" \
  '{tool_name:"Write", tool_input:{file_path:$p, content:"x"}, tool_use_id:"u7"}')
OUT7="$(run_gate "$EV_SYMLINK")"
assert_not_contains "$OUT7" "common-output" "심링크 탈출은 특례 미적용"

# 8) prefix bleed — .harness-state-foo 는 .harness-state 정확매칭에 안 걸림
EV_BLEED=$(jq -nc --arg p "$TMP_PROJ/.agent-harness/.harness-state-foo" \
  '{tool_name:"Write", tool_input:{file_path:$p, content:"x"}, tool_use_id:"u8"}')
OUT8="$(run_gate "$EV_BLEED")"
assert_not_contains "$OUT8" "common-output" ".harness-state-foo 는 정확매칭 아니라 특례 미적용"

# 9) 빈 file_path — 특례 미적용 (정상 fallback)
EV_EMPTY=$(jq -nc '{tool_name:"Write", tool_input:{content:"x"}, tool_use_id:"u9"}')
OUT9="$(run_gate "$EV_EMPTY")"
assert_not_contains "$OUT9" "common-output" "빈 file_path 특례 미적용"

# 10) 정상 results 하위 깊은 경로는 여전히 allow (정규화가 정상 경로를 막지 않음 — 회귀)
mkdir -p "$TMP_PROJ/.agent-harness/results/sub"
EV_DEEP=$(jq -nc --arg p "$TMP_PROJ/.agent-harness/results/sub/deep.md" \
  '{tool_name:"Write", tool_input:{file_path:$p, content:"x"}, tool_use_id:"u10"}')
OUT10="$(run_gate "$EV_DEEP")"
assert_contains "$OUT10" "common-output" "정상 results 깊은 경로는 정규화 후에도 allow"

test_summary
