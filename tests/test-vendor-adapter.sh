#!/usr/bin/env bash
# 벤더 어댑터 규약: 각 어댑터가 5개 함수를 정의하는지 + _test 어댑터 동작.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT/tests/assert.sh"
. "$ROOT/tests/harness-paths.sh"
TMPDIR_T="$(mktemp -d)"; trap 'rm -rf "$TMPDIR_T"' EXIT

FUNCS="vendor_boot_cmd vendor_wait_ready vendor_gen_settings vendor_inject_role vendor_orch_plan_directive vendor_default_model"

check_funcs() {  # $1=adapter_path
  ( set +u; HARNESS_ROOT="$HARNESS"; PROJECT_ROOT="$TMPDIR_T"
    . "$1" || exit 1
    for f in $FUNCS; do type "$f" >/dev/null 2>&1 || exit 1; done )
}

check_funcs "$HARNESS_BIN/vendors/claude.sh"; assert_success "$?" "A1 claude.sh 5함수 정의"
check_funcs "$HARNESS_BIN/vendors/_test.sh"; assert_success "$?" "A2 _test.sh 5함수 정의"

out="$( set +u; HARNESS_ROOT="$HARNESS"; PROJECT_ROOT="$TMPDIR_T"
  . "$HARNESS_BIN/vendors/claude.sh"; vendor_boot_cmd "opus" "/tmp/s.json" "abc-123" "" )"
assert_contains "$out" "claude --model opus" "A3a boot_cmd model"
assert_contains "$out" "--settings" "A3b boot_cmd settings"
assert_contains "$out" "--session-id abc-123" "A3c boot_cmd sid"

out="$( set +u; HARNESS_ROOT="$HARNESS"; PROJECT_ROOT="$TMPDIR_T"
  . "$HARNESS_BIN/vendors/claude.sh"; vendor_boot_cmd "opus" "/tmp/s.json" "abc-123" "/tmp/plan.md" )"
assert_contains "$out" "--append-system-prompt-file" "A4 boot_cmd plan 주입"

# P10(2026-05-30): vendor_orch_plan_directive 벤더중립 — claude=빈값(plan 이 이미 시스템
#   컨텍스트), codex=plan 경로 명시 Read 지시(--append-system-prompt-file 부재 보완, 결정적).
out="$( set +u; HARNESS_ROOT="$HARNESS"; PROJECT_ROOT="$TMPDIR_T"
  . "$HARNESS_BIN/vendors/claude.sh"; vendor_orch_plan_directive "/tmp/plan.md" )"
assert_eq "" "$out" "A4b claude plan directive 빈값(시스템 컨텍스트 주입)"
out="$( set +u; HARNESS_ROOT="$HARNESS"; PROJECT_ROOT="$TMPDIR_T"
  . "$HARNESS_BIN/vendors/codex.sh"; vendor_orch_plan_directive "/tmp/x/.boot/plan.md" )"
assert_contains "$out" "/tmp/x/.boot/plan.md" "A4c codex plan directive 경로 명시"
assert_contains "$out" "Read" "A4d codex plan directive Read 지시"
out="$( set +u; HARNESS_ROOT="$HARNESS"; PROJECT_ROOT="$TMPDIR_T"
  . "$HARNESS_BIN/vendors/codex.sh"; vendor_orch_plan_directive "" )"
assert_eq "" "$out" "A4e codex plan 빈값 → 빈 출력(plan 없으면 지시 없음)"

out="$( set +u; HARNESS_ROOT="$HARNESS"; . "$HARNESS_BIN/vendors/claude.sh"
  printf '%s/%s/%s/%s' "$(vendor_default_model orch)" "$(vendor_default_model desk)" \
    "$(vendor_default_model reviewer-quality)" "$(vendor_default_model dev)" )"
assert_eq "opus/sonnet/opus/sonnet" "$out" "A5 claude default model (reviewer=opus)"

out="$( set +u; AGENT_CMD="dummyworker"; . "$HARNESS_BIN/vendors/_test.sh"
  vendor_boot_cmd "x" "y" "z" "" )"
assert_eq "dummyworker" "$out" "A6 _test boot_cmd=AGENT_CMD"

( set +u; PROJECT_ROOT="$TMPDIR_T"; . "$HARNESS_BIN/vendors/_test.sh"
  p="$(vendor_gen_settings "dev" "devname")" && [ -n "$p" ] && vendor_wait_ready "%0" >/dev/null 2>&1 )
assert_success "$?" "A7 _test gen_settings(경로 echo)/wait_ready rc0"

( set +u; HARNESS_ROOT="$HARNESS"; PROJECT_ROOT="$TMPDIR_T"; mkdir -p "$TMPDIR_T"
  . "$HARNESS_BIN/lib.sh"; . "$HARNESS_BIN/vendors/claude.sh"
  p="$(vendor_gen_settings "dev" "devworker")" && [ -n "$p" ] && [ -f "$p" ] \
    && grep -q "devworker" "$p" )
assert_success "$?" "A8 claude gen_settings 실행+토큰 치환(lib.sh 의존)"

# ★ codex 어댑터 실부트 스모크 회귀(2026-05-30) — 실 tmux/codex CLI 없이 단위 검증.
echo "[A9-12] codex 어댑터 (실부트 함정 3종 가드)"
CODEX_PR="$(mktemp -d)"  # 격리 PROJECT_ROOT
FAKE_HOME="$(mktemp -d)/.codex"; mkdir -p "$FAKE_HOME"; echo '{"fake":"auth"}' > "$FAKE_HOME/auth.json"
# A9 — auth.json 전파(심볼링크): 격리 CODEX_HOME 에 사용자 auth 가 링크돼 로그인 화면 회피.
( set +u; HARNESS_ROOT="$HARNESS"; PROJECT_ROOT="$CODEX_PR"; CODEX_HOME="$FAKE_HOME"
  . "$HARNESS_BIN/vendors/codex.sh"; vendor_gen_settings "dev" "dev" >/dev/null
  [ -e "$CODEX_PR/.agent-harness/.codex/auth.json" ] )
assert_success "$?" "A9 codex auth.json 전파(로그인 화면 회피)"
# A10 — config.toml 에 PROJECT_ROOT trusted 등록(trust 프롬프트 사전 제거).
codex_cfg="$CODEX_PR/.agent-harness/.codex/config.toml"
assert_success "$([ -f "$codex_cfg" ] && grep -q 'trust_level = "trusted"' "$codex_cfg"; echo $?)" "A10 codex trusted 등록"
# A11 — effort 매핑: orch=high, dev=medium.
( set +u; HARNESS_ROOT="$HARNESS"; PROJECT_ROOT="$(mktemp -d)"; CODEX_HOME="$FAKE_HOME"
  . "$HARNESS_BIN/vendors/codex.sh"; vendor_gen_settings "orch" "orch" >/dev/null
  grep -q 'model_reasoning_effort = "high"' "$PROJECT_ROOT/.agent-harness/.codex/config.toml" )
assert_success "$?" "A11 codex orch effort=high"
# A12 — wait_ready 본문 회귀 가드(grep): ready 우선 + 업데이트 Skip + trust 처리 패턴 존재.
cx="$HARNESS_BIN/vendors/codex.sh"
assert_success "$(grep -q 'OpenAI Codex' "$cx"; echo $?)" "A12a wait_ready ready 패턴(구버전 헤더)"
assert_success "$(grep -q 'Update available' "$cx"; echo $?)" "A12b wait_ready 업데이트 Skip 패턴"
# ready 분기가 update 분기보다 앞에 있어야(잔상 경합 회피) — 줄번호 비교.
_rl=$(grep -n 'OpenAI Codex|❯' "$cx" | head -1 | cut -d: -f1)
_ul=$(grep -n 'Update available|Update now' "$cx" | head -1 | cut -d: -f1)
assert_success "$([ -n "$_rl" ] && [ -n "$_ul" ] && [ "$_rl" -lt "$_ul" ]; echo $?)" "A12c ready 분기가 update 분기보다 앞"
# A12d — codex 0.130 라이브 발견(2026-06-02): 0.130 ready 화면은 'gpt-N.N <effort> ·'
#   상태줄만 떠 구버전 패턴(OpenAI Codex|❯)이 다 실패 → 120s 풀 폴링·부트 5분 지연.
#   ready 분기 grep 에 'gpt-N.N <effort> ·' 상태줄 패턴이 포함돼야(회귀 차단).
assert_success "$(grep -q 'gpt-\[0-9.\]+ (low|medium|high) ·' "$cx"; echo $?)" "A12d wait_ready 0.130 상태줄 ready 패턴"
rm -rf "$CODEX_PR" "$FAKE_HOME"

# A13 — 오케스트레이터 가드(2026-05-31): LEAD/PM 은 claude 전용. codex 등 비-claude 지정 시
#   claude 로 강제(P17 회피 — codex 는 워커/리뷰어만). resolve_orchestrator_vendor 계약.
( set +u; HARNESS_ROOT="$HARNESS"; . "$HARNESS_BIN/lib.sh"
  [ "$(resolve_orchestrator_vendor "codex" "ORCH" 2>/dev/null)" = "claude" ] )
assert_success "$?" "A13a LEAD codex→claude 강제"
( set +u; HARNESS_ROOT="$HARNESS"; . "$HARNESS_BIN/lib.sh"
  [ "$(resolve_orchestrator_vendor "codex" "DESK" 2>/dev/null)" = "claude" ] )
assert_success "$?" "A13b PM codex→claude 강제"
( set +u; HARNESS_ROOT="$HARNESS"; . "$HARNESS_BIN/lib.sh"
  [ "$(resolve_orchestrator_vendor "claude" "ORCH" 2>/dev/null)" = "claude" ] )
assert_success "$?" "A13c LEAD claude 는 그대로"
# 강제 시 stderr 경고가 나와야(사용자 인지) — 침묵 강등 금지.
( set +u; HARNESS_ROOT="$HARNESS"; . "$HARNESS_BIN/lib.sh"
  resolve_orchestrator_vendor "codex" "ORCH" 2>&1 1>/dev/null | grep -q '강제' )
assert_success "$?" "A13d 강제 시 경고 출력(침묵 강등 금지)"
# awa-up 이 LEAD/PM 직전에 가드를 호출하는지(회귀 가드).
assert_success "$(grep -q 'resolve_orchestrator_vendor.*LEAD' "$HARNESS_BIN/awa-up.sh"; echo $?)" "A13e awa-up LEAD 가드 호출"
assert_success "$(grep -q 'resolve_orchestrator_vendor.*PM' "$HARNESS_BIN/awa-up.sh"; echo $?)" "A13f awa-up PM 가드 호출"

test_summary
