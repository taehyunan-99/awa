#!/usr/bin/env bash
# awa 스킬 재귀 가동 차단: 모든 역할군 settings 템플릿이 Skill(awa) 를 deny 하는지.
# 근거: awa SKILL.md 가 "User ! required for launch" 로 못박음 — 어떤 워커/리뷰어/pm/lead 도
# awa 스킬을 자동발동하면 자기 위에 하니스를 재귀 가동(라이브 2026-06-03 PM 납치 사건).
# 역할(시스템프롬프트)이 awa 금지를 명시해도 스킬 자동트리거(행동)를 못 막으므로
# 도구 권한 레이어에서 확정 차단해야 함(채널 교정 — injection 결함과 동일 계열).
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"

# deny 블록을 갖는 모든 역할군 템플릿이 Skill(awa) 를 차단해야 한다.
for tpl in desk orch dev test readonly reviewer; do
  f="$ROOT/templates/settings.${tpl}.json.tpl"
  [ -f "$f" ] || { assert_eq "1" "0" "$tpl 템플릿 존재"; continue; }
  deny="$(sed -e 's|{{[^}]*}}|null|g' "$f" | jq -r '.permissions.deny[]?' 2>/dev/null)"
  assert_contains "$deny" "Skill(awa)" "$tpl 템플릿 deny 에 Skill(awa) (재귀 가동 차단)"
done

# generate_worker_settings 산출물(실제 적용 settings)도 Skill(awa) 를 deny 해야 한다.
TMP_PROJ="$(mktemp -d)"; ( cd "$TMP_PROJ" && git init -q )
cleanup() { rm -rf "$TMP_PROJ"; }
trap cleanup EXIT

for role in desk frontend reviewer-alignment; do
  OUT="$(HARNESS_PROJECT="$TMP_PROJ" bash -c '
    source '"$ROOT"'/bin/lib.sh
    generate_worker_settings '"$role"' '"$role"'
  ')"
  gen_deny="$(cat "$OUT" | jq -r '.permissions.deny[]?' 2>/dev/null)"
  assert_contains "$gen_deny" "Skill(awa)" "$role 산출 settings deny 에 Skill(awa)"
done

test_summary
