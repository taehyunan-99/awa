#!/usr/bin/env bash
# 벤더 어댑터 규약: 각 어댑터가 5개 함수를 정의하는지 + _test 어댑터 동작.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT/tests/assert.sh"
TMPDIR_T="$(mktemp -d)"; trap 'rm -rf "$TMPDIR_T"' EXIT

FUNCS="vendor_boot_cmd vendor_wait_ready vendor_gen_settings vendor_inject_role vendor_default_model"

check_funcs() {  # $1=adapter_path
  ( set +u; HARNESS_ROOT="$ROOT"; PROJECT_ROOT="$TMPDIR_T"
    . "$1" || exit 1
    for f in $FUNCS; do type "$f" >/dev/null 2>&1 || exit 1; done )
}

check_funcs "$ROOT/bin/vendors/claude.sh"; assert_success "$?" "A1 claude.sh 5함수 정의"
check_funcs "$ROOT/bin/vendors/_test.sh"; assert_success "$?" "A2 _test.sh 5함수 정의"

out="$( set +u; HARNESS_ROOT="$ROOT"; PROJECT_ROOT="$TMPDIR_T"
  . "$ROOT/bin/vendors/claude.sh"; vendor_boot_cmd "opus" "/tmp/s.json" "abc-123" "" )"
assert_contains "$out" "claude --model opus" "A3a boot_cmd model"
assert_contains "$out" "--settings" "A3b boot_cmd settings"
assert_contains "$out" "--session-id abc-123" "A3c boot_cmd sid"

out="$( set +u; HARNESS_ROOT="$ROOT"; PROJECT_ROOT="$TMPDIR_T"
  . "$ROOT/bin/vendors/claude.sh"; vendor_boot_cmd "opus" "/tmp/s.json" "abc-123" "/tmp/plan.md" )"
assert_contains "$out" "--append-system-prompt-file" "A4 boot_cmd plan 주입"

out="$( set +u; HARNESS_ROOT="$ROOT"; . "$ROOT/bin/vendors/claude.sh"
  printf '%s/%s/%s/%s' "$(vendor_default_model lead)" "$(vendor_default_model pm)" \
    "$(vendor_default_model reviewer-quality)" "$(vendor_default_model dev)" )"
assert_eq "opus/sonnet/opus/sonnet" "$out" "A5 claude default model (reviewer=opus)"

out="$( set +u; AGENT_CMD="dummyworker"; . "$ROOT/bin/vendors/_test.sh"
  vendor_boot_cmd "x" "y" "z" "" )"
assert_eq "dummyworker" "$out" "A6 _test boot_cmd=AGENT_CMD"

( set +u; PROJECT_ROOT="$TMPDIR_T"; . "$ROOT/bin/vendors/_test.sh"
  p="$(vendor_gen_settings "dev" "devname")" && [ -n "$p" ] && vendor_wait_ready "%0" >/dev/null 2>&1 )
assert_success "$?" "A7 _test gen_settings(경로 echo)/wait_ready rc0"

( set +u; HARNESS_ROOT="$ROOT"; PROJECT_ROOT="$TMPDIR_T"; mkdir -p "$TMPDIR_T"
  . "$ROOT/bin/lib.sh"; . "$ROOT/bin/vendors/claude.sh"
  p="$(vendor_gen_settings "dev" "devworker")" && [ -n "$p" ] && [ -f "$p" ] \
    && grep -q "devworker" "$p" )
assert_success "$?" "A8 claude gen_settings 실행+토큰 치환(lib.sh 의존)"

test_summary
