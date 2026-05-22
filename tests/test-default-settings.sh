#!/usr/bin/env bash
# settings.default.json.tpl 의 allow/deny + PreToolUse log-deny WORKER 토큰화 검증.
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"
tpl="$ROOT/templates/settings.default.json.tpl"

[ -f "$tpl" ]; assert_success "$?" "default 템플릿 존재"
content="$(cat "$tpl")"

assert_contains "$content" '"Read"' "default allow Read"
assert_contains "$content" 'Bash(ls:*)' "default allow ls"
assert_contains "$content" 'Bash(grep:*)' "default allow grep"
assert_contains "$content" 'Bash(sudo:*)' "default deny sudo"
assert_contains "$content" 'Bash(dd:*)' "default deny dd"
assert_contains "$content" 'WORKER=\"{{ENTRY_NAME}}\"' "default PreToolUse WORKER 토큰"
assert_contains "$content" '{{HARNESS_ROOT}}/bin/log-deny.sh' "default log-deny hook"
assert_contains "$content" '{{PROJECT_ROOT}}/.agent-harness/permission-events.log' "default PERMISSION_EVENTS_LOG"

if command -v jq >/dev/null 2>&1; then
  echo "$content" | sed -e 's#{{HARNESS_ROOT}}#/tmp/h#g' -e 's#{{ENTRY_NAME}}#x#g' -e 's#{{PROJECT_ROOT}}#/tmp/p#g' | jq . >/dev/null
  assert_success "$?" "default 템플릿 유효 JSON"
fi

test_summary
