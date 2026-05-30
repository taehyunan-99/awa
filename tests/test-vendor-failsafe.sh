#!/usr/bin/env bash
# vendor_gen_settings rc 1 → 워커 가동 거부(fail-safe). 어댑터 계약 검증.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT/tests/assert.sh"
TMPDIR_F="$(mktemp -d)"; trap 'rm -rf "$TMPDIR_F"' EXIT

# F1: codex gen_settings 가 쓰기 불가 CODEX_HOME 경로에서 rc1.
( set +u
  HARNESS_ROOT="$ROOT"; PROJECT_ROOT="/dev/null/awa-nodir"
  . "$ROOT/bin/vendors/codex.sh"
  vendor_gen_settings "dev" >/dev/null 2>&1 )
assert_fail "$?" "F1 codex gen_settings rc1 on 쓰기불가"

# F2: claude gen_settings 도 템플릿 부재 시 rc1 (generate_worker_settings 계약).
# lib.sh L7 이 source 시 HARNESS_ROOT 를 실제 루트로 재계산하므로, 템플릿 부재 상황은
# source *이후* HARNESS_ROOT 를 빈 디렉토리로 덮어써 재현한다(L7 우회).
( set +u
  PROJECT_ROOT="$TMPDIR_F/proj"; mkdir -p "$PROJECT_ROOT"
  . "$ROOT/bin/lib.sh"; . "$ROOT/bin/vendors/claude.sh"
  HARNESS_ROOT="$TMPDIR_F/no-templates"
  vendor_gen_settings "dev" >/dev/null 2>&1 )
assert_fail "$?" "F2 claude gen_settings rc1 on 템플릿부재"

# F3: codex lead → config.toml effort=high + model_reasoning_effort 키.
( set +u; HARNESS_ROOT="$ROOT"; PROJECT_ROOT="$TMPDIR_F/cx-lead"; mkdir -p "$PROJECT_ROOT"
  . "$ROOT/bin/vendors/codex.sh"; vendor_gen_settings "lead" "LEAD" >/dev/null 2>&1 )
cfg="$TMPDIR_F/cx-lead/.agent-harness/.codex/config.toml"
assert_contains "$(cat "$cfg" 2>/dev/null)" 'model_reasoning_effort = "high"' "F3 codex lead effort=high"

# F4: codex dev → effort=medium. reviewer 도 high(품질 우선).
( set +u; HARNESS_ROOT="$ROOT"; PROJECT_ROOT="$TMPDIR_F/cx-dev"; mkdir -p "$PROJECT_ROOT"
  . "$ROOT/bin/vendors/codex.sh"; vendor_gen_settings "dev" "d" >/dev/null 2>&1 )
assert_contains "$(cat "$TMPDIR_F/cx-dev/.agent-harness/.codex/config.toml" 2>/dev/null)" \
  'model_reasoning_effort = "medium"' "F4 codex dev effort=medium"
( set +u; HARNESS_ROOT="$ROOT"; PROJECT_ROOT="$TMPDIR_F/cx-rev"; mkdir -p "$PROJECT_ROOT"
  . "$ROOT/bin/vendors/codex.sh"; vendor_gen_settings "reviewer-quality" "r" >/dev/null 2>&1 )
assert_contains "$(cat "$TMPDIR_F/cx-rev/.agent-harness/.codex/config.toml" 2>/dev/null)" \
  'model_reasoning_effort = "high"' "F4b codex reviewer effort=high(품질우선)"

# F5: ready 오탐 차단 — boot 명령 자체가 wait_ready 의 ready 패턴(OpenAI Codex|❯)을 포함하면
#   pane 의 명령 echo 가 TUI 로드 전 ready 로 오판된다. boot_cmd 가 ready 패턴 미포함이어야 함.
bootcmd="$( set +u; PROJECT_ROOT="$TMPDIR_F/p"; . "$ROOT/bin/vendors/codex.sh"
  vendor_boot_cmd "gpt-5.5" "" "" "" )"
printf '%s' "$bootcmd" | grep -qE 'OpenAI Codex|❯'
assert_fail "$?" "F5 codex boot 명령이 ready 패턴 미포함(echo 오탐 차단)"

# F6: hooks.json 은 HARNESS_ROOT 에 특수문자(따옴표/$/백슬래시)가 있어도 유효 JSON(jq 생성).
if command -v jq >/dev/null 2>&1; then
  ( set +u; HARNESS_ROOT='/tmp/has $pecial"q/and\back'; PROJECT_ROOT="$TMPDIR_F/cx-esc"
    mkdir -p "$PROJECT_ROOT"; . "$ROOT/bin/vendors/codex.sh"
    vendor_gen_settings "dev" "d" >/dev/null 2>&1 )
  jq -e . "$TMPDIR_F/cx-esc/.agent-harness/.codex/hooks.json" >/dev/null 2>&1
  assert_success "$?" "F6 hooks.json 특수문자 HARNESS_ROOT 에서도 유효 JSON"
else
  echo "  SKIP: jq 미설치 — F6 생략"
fi

test_summary
