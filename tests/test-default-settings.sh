#!/usr/bin/env bash
# settings.readonly.json.tpl 의 allow/deny + PreToolUse permission-gate 전수 matcher 검증.
# (구 settings.default.json.tpl → readonly 로 의미 정정, 2026-06-01 역할 재배선)
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"
tpl="$ROOT/templates/settings.readonly.json.tpl"

[ -f "$tpl" ]; assert_success "$?" "readonly 템플릿 존재"
content="$(cat "$tpl")"

assert_contains "$content" '"Read"' "default allow Read"
assert_contains "$content" 'Bash(ls:*)' "default allow ls"
assert_contains "$content" 'Bash(grep:*)' "default allow grep"
assert_contains "$content" 'Bash(sudo:*)' "default deny sudo"
assert_contains "$content" 'Bash(dd:*)' "default deny dd"
assert_contains "$content" 'WORKER=\"{{ENTRY_NAME}}\"' "default PreToolUse WORKER 토큰"
assert_contains "$content" '{{HARNESS_ROOT}}/bin/permission-gate.sh' "default permission-gate hook"
assert_contains "$content" 'ENTRY_ROLE=\"{{ENTRY_ROLE}}\"' "default ENTRY_ROLE 토큰"
assert_contains "$content" '"matcher": "*"' "default 전수 게이트 matcher"

if command -v jq >/dev/null 2>&1; then
  echo "$content" | sed -e 's#{{HARNESS_ROOT}}#/tmp/h#g' -e 's#{{ENTRY_NAME}}#x#g' -e 's#{{PROJECT_ROOT}}#/tmp/p#g' | jq . >/dev/null
  assert_success "$?" "default 템플릿 유효 JSON"
fi

test_summary
