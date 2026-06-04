#!/usr/bin/env bash
# settings.orch.json.tpl 의 allow/deny + hooks·env 미포함 검증.
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"
tpl="$ROOT/templates/settings.orch.json.tpl"

[ -f "$tpl" ]; assert_success "$?" "orch 템플릿 존재"
content="$(cat "$tpl")"

assert_contains "$content" '"Read"' "orch allow Read"
assert_contains "$content" '"Write"' "orch allow Write"
assert_contains "$content" 'Bash(rm:*)' "orch allow rm"
assert_contains "$content" 'Bash(rm -rf:*)' "orch allow rm -rf"
assert_contains "$content" 'Bash(jq:*)' "orch allow jq"
assert_contains "$content" 'Bash(tmux:*)' "orch allow tmux (wake -S)"
! printf '%s' "$content" | grep -q 'watch-asks'; assert_success "$?" "orch watch-asks allow 제거"
assert_contains "$content" 'Bash(kill -0:*)' "orch allow kill -0"
assert_contains "$content" 'Bash(git push --force:*)' "orch deny git force"
assert_contains "$content" 'Bash(sudo:*)' "orch deny sudo"

# 6차 e2e 발견: ORCH 는 hook 게이트 비대상 → claude 기본 권한모델 적용. orch.md 가 안내하는
# 명령치환($(...))·변수할당·if 복합 셸을 claude 가 "정적분석 불가"로 보고 매 사이클 confirm 요구
# (allow 패턴과 무관). bypassPermissions 로 배관 confirm 제거 — deny·circuit breaker(rm -rf /)는
# 유효, AskUserQuestion(워커 권한 판단 사람 위임)은 별개 메커니즘이라 영향 없음 (공식 docs 확인).
assert_contains "$content" '"defaultMode": "bypassPermissions"' "orch bypassPermissions (배관 confirm 제거, deny 유지)"

if printf '%s' "$content" | grep -q '"hooks"'; then
  assert_eq "no-hooks" "has-hooks" "orch 템플릿 hooks 미포함"
else
  assert_success 0 "orch 템플릿 hooks 미포함"
fi
if printf '%s' "$content" | grep -q '"env"'; then
  assert_eq "no-env" "has-env" "orch 템플릿 env 미포함"
else
  assert_success 0 "orch 템플릿 env 미포함"
fi

if command -v jq >/dev/null 2>&1; then
  echo "$content" | sed 's#{{HARNESS_ROOT}}#/tmp/h#g' | jq . >/dev/null
  assert_success "$?" "orch 템플릿 유효 JSON (토큰 치환 후)"
fi

test_summary
