#!/usr/bin/env bash
# awa-up 후 .boot-settings/<role>.json 6 파일 생성 + 매핑 검증.
# AGENT_CMD=cat 으로 더미 실행 — claude 부재 환경에서도 동작.
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
source ./harness-paths.sh

ROOT="$(cd .. && pwd)"
TMP="$(mktemp -d)"
SAFE="$(printf '%s' "$(basename "$TMP")" | sed 's/[^A-Za-z0-9_-]/_/g')"
SESSION="awa-$SAFE"

# 15th: bookmarks 격리 — awa-up.sh 가 ~/.config/awa/bookmarks.tsv 에 기록.
# 테스트 fixture 가 사용자 실 경로를 더럽히지 않도록 임시 dir 로 redirect.
_AGPN15_XDG="$(mktemp -d)"
export XDG_CONFIG_HOME="$_AGPN15_XDG"

cleanup() {
  tmux kill-session -t "$SESSION" 2>/dev/null || true
  rm -rf "$TMP"
  [ -n "${_AGPN15_XDG:-}" ] && rm -rf "$_AGPN15_XDG"
}
trap cleanup EXIT
( cd "$TMP" && git init -q )

# default 프로파일: engineer/researcher 워커 + alignment/quality/security 리뷰어 + review-mgr.
HARNESS_PROJECT="$TMP" AGENT_CMD=cat bash "$HARNESS_BIN/awa-up.sh" default >/dev/null 2>&1
rc=$?
assert_eq "0" "$rc" "awa-up 성공"

BOOTSET="$TMP/.agent-harness/.boot-settings"
[ -d "$BOOTSET" ]; assert_success "$?" ".boot-settings 디렉터리 생성"

# default WORKERS=(engineer:engineer researcher:researcher), REVIEWERS=(alignment-rev:reviewer-alignment ...).
# generate_worker_settings 매핑 (2026-06-01 역할 재배선):
#  - engineer → engineer 템플릿 → engineer.json (코드 쓰기)
#  - researcher → readonly 템플릿 → researcher.json (읽기전용, 코드 쓰기 없음)
#  - reviewer-* → reviewer 템플릿 → reviewer-{alignment,quality,security}.json
# 파일 모두 *필수* 검증 — 매핑 회귀 신호 강하게.
[ -f "$BOOTSET/engineer.json" ]; assert_success "$?" "engineer.json 존재"
[ -f "$BOOTSET/researcher.json" ]; assert_success "$?" "researcher.json 존재 (readonly 템플릿)"
[ -f "$BOOTSET/reviewer-quality.json" ]; assert_success "$?" "reviewer-quality.json 존재"
[ -f "$BOOTSET/reviewer-alignment.json" ]; assert_success "$?" "reviewer-alignment.json 존재"
[ -f "$BOOTSET/reviewer-security.json" ]; assert_success "$?" "reviewer-security.json 존재"

# engineer 검증 (코드 쓰기 워커)
content="$(cat "$BOOTSET/engineer.json")"
assert_contains "$content" "Bash(git push *)" "engineer.json git push deny"
assert_contains "$content" "PROJECT_ROOT=\\\"$TMP\\\"" "engineer.json PROJECT_ROOT 치환"
assert_contains "$content" 'WORKER=\"engineer\"' "engineer.json WORKER=entry_name(engineer)"
# 잔존 토큰 부재
if printf '%s' "$content" | grep -qE '\{\{[A-Z_]+\}\}'; then
  assert_eq "no" "yes" "engineer.json 토큰 잔존 부재"
fi

# researcher 검증 — readonly 매핑 (코드 전역 쓰기 없음, 공통산출은 gate 특례가 보장).
content="$(cat "$BOOTSET/researcher.json")"
assert_not_contains "$content" "Write($TMP/**)" "researcher.json 코드 전역 쓰기 없음 (readonly)"
assert_contains "$content" '"Read"' "researcher.json Read allow (readonly)"
assert_contains "$content" "permission-gate.sh" "researcher.json PreToolUse 게이트 보존"
assert_contains "$content" 'WORKER=\"researcher\"' "researcher.json WORKER=entry_name(researcher)"

# reviewer-quality 검증
content="$(cat "$BOOTSET/reviewer-quality.json")"
# reviewer deny 는 Skill(awa) 만 — 위험 명령 차단은 permission-gate hook 위임(기술적 deny 최소).
# Skill(awa) 는 게이트로 못 막는 재귀 가동이라 settings deny 로 확정 차단(2026-06-03 PM 납치).
_rev_deny="$(printf '%s' "$content" | jq -r '.permissions.deny[]?' 2>/dev/null)"
assert_contains "$_rev_deny" "Skill(awa)" "reviewer-quality.json deny 에 Skill(awa) (재귀 가동 차단)"
assert_eq "Skill(awa)" "$(printf '%s' "$_rev_deny" | tr -d '[:space:]')" "reviewer-quality.json deny 는 Skill(awa) 단일 (위험명령은 게이트 위임)"
assert_contains "$content" "permission-gate.sh" "reviewer-quality.json hook"
assert_contains "$content" '"Read"' "reviewer-quality.json seed allow Read"
assert_contains "$content" 'WORKER=\"quality-rev\"' "reviewer-quality.json WORKER=entry_name"

# reviewer-alignment / reviewer-security 도 동일 reviewer 템플릿 — Skill(awa) deny + hook 존재.
for rev in reviewer-alignment reviewer-security; do
  content="$(cat "$BOOTSET/$rev.json")"
  _rev_deny="$(printf '%s' "$content" | jq -r '.permissions.deny[]?' 2>/dev/null)"
  assert_contains "$_rev_deny" "Skill(awa)" "$rev.json deny 에 Skill(awa)"
  assert_contains "$content" "permission-gate.sh" "$rev.json hook"
  assert_contains "$content" '"Read"' "$rev.json seed allow Read"
done

# AGENT_CMD=cat 경로에선 --settings 가 cmd 에 추가되지 않음 (claude 분기에서만 추가).
# 본 테스트는 *파일 생성* 만 검증. claude 인자 적용은 integration probe (T10) 가 담당.

test_summary
