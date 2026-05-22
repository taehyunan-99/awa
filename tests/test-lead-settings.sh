#!/usr/bin/env bash
# settings.lead.json.tpl 의 allow/deny + hooks·env 미포함 검증.
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"
tpl="$ROOT/templates/settings.lead.json.tpl"

[ -f "$tpl" ]; assert_success "$?" "lead 템플릿 존재"
content="$(cat "$tpl")"

assert_contains "$content" '"Read"' "lead allow Read"
assert_contains "$content" '"Write"' "lead allow Write"
assert_contains "$content" 'Bash(rm:*)' "lead allow rm"
assert_contains "$content" 'Bash(rm -rf:*)' "lead allow rm -rf"
assert_contains "$content" 'Bash(jq:*)' "lead allow jq"
assert_contains "$content" '{{HARNESS_ROOT}}/bin/watch-asks.sh' "lead allow watch-asks (토큰)"
assert_contains "$content" 'Bash(kill -0:*)' "lead allow kill -0"
assert_contains "$content" 'Bash(git push --force:*)' "lead deny git force"
assert_contains "$content" 'Bash(sudo:*)' "lead deny sudo"

if printf '%s' "$content" | grep -q '"hooks"'; then
  assert_eq "no-hooks" "has-hooks" "lead 템플릿 hooks 미포함"
else
  assert_success 0 "lead 템플릿 hooks 미포함"
fi
if printf '%s' "$content" | grep -q '"env"'; then
  assert_eq "no-env" "has-env" "lead 템플릿 env 미포함"
else
  assert_success 0 "lead 템플릿 env 미포함"
fi

if command -v jq >/dev/null 2>&1; then
  echo "$content" | sed 's#{{HARNESS_ROOT}}#/tmp/h#g' | jq . >/dev/null
  assert_success "$?" "lead 템플릿 유효 JSON (토큰 치환 후)"
fi

test_summary
