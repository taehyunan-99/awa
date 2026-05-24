#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh

ROOT="$(cd .. && pwd)"

# pm 템플릿 생성 검증: generate_worker_settings "pm" "pm" 가 pm 템플릿을 산출하는지.
TMP_PROJ="$(mktemp -d)"; ( cd "$TMP_PROJ" && git init -q )
cleanup() { rm -rf "$TMP_PROJ"; }
trap cleanup EXIT

# lib.sh 가 PROJECT_ROOT·HARNESS_ROOT 를 요구하므로 HARNESS_PROJECT 로 격리 후 source.
OUT="$(HARNESS_PROJECT="$TMP_PROJ" bash -c '
  source '"$ROOT"'/bin/lib.sh
  generate_worker_settings pm pm
')"
rc=$?
assert_eq "0" "$rc" "generate_worker_settings pm 성공"

# 산출 경로가 .boot-settings/pm.json 인지
assert_contains "$OUT" ".boot-settings/pm.json" "pm settings 경로"
[ -f "$OUT" ]
assert_success "$?" "pm settings 파일 존재"

PMSET="$(cat "$OUT")"
# pm 은 hook 없음 (게이트 비대상)
assert_not_contains "$PMSET" "permission-gate.sh" "pm 은 PreToolUse 게이트 없음"
assert_not_contains "$PMSET" "log-event.sh" "pm 은 PostToolUse 없음"
# pm 은 bypassPermissions 아님 (과권한 금지)
assert_not_contains "$PMSET" "bypassPermissions" "pm 은 bypassPermissions 아님"
# 읽기 도구 + 전달용 tmux + pull-read bash allow
assert_contains "$PMSET" "Read" "pm Read allow"
assert_contains "$PMSET" "Grep" "pm Grep allow"
assert_contains "$PMSET" "Bash(tmux:*)" "pm tmux allow (lead 전달용)"
assert_contains "$PMSET" "Bash(cat:*)" "pm cat allow (pull-read)"
# pm 은 Write/rm allow 없음 (읽기전용)
assert_not_contains "$PMSET" '"Write(' "pm 은 Write allow 없음"
assert_not_contains "$PMSET" "Bash(rm" "pm 은 rm allow 없음"

# I1: 읽기전용을 deny 로 코드 강제 (allow 부재만으론 default mode 에서 사용자 프롬프트 — pm 이
# 사용자 창구라 자기참조. deny 는 default mode 에서 확정 차단이라 불변식을 settings 로 보장).
_pm_deny="$(printf '%s' "$PMSET" | jq -r '.permissions.deny[]?' 2>/dev/null)"
assert_contains "$_pm_deny" "Write" "pm deny 에 Write (읽기전용 코드 강제)"
assert_contains "$_pm_deny" "Edit" "pm deny 에 Edit"
assert_contains "$_pm_deny" "NotebookEdit" "pm deny 에 NotebookEdit"

test_summary
