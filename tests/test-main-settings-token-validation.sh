#!/usr/bin/env bash
# settings.json.tpl 의 {{...}} 토큰 치환 확인 + 잔존 시 team-up fail.
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh

ROOT="$(cd .. && pwd)"
TMP="$(mktemp -d)"

cleanup() {
  tmux kill-session -t "agents-$(printf '%s' "$(basename "$TMP")" | sed 's/[^A-Za-z0-9_-]/_/g')" 2>/dev/null || true
  rm -rf "$TMP"
}
trap cleanup EXIT
( cd "$TMP" && git init -q )

echo "[M1] 정상 team-up — settings.json 토큰 치환 완료"
HARNESS_PROJECT="$TMP" AGENT_CMD=cat bash "$ROOT/bin/team-up.sh" default >/dev/null 2>&1
rc=$?
assert_eq "0" "$rc" "M1 team-up 성공"
content="$(cat "$TMP/.claude/settings.json")"
# {{...}} 토큰 잔존 검증
assert_eq "" "$(printf '%s' "$content" | grep -oE '\{\{(PROJECT_ROOT|HARNESS_ROOT)\}\}')" "M1 토큰 잔존 없음"
# 치환 결과에 실제 경로 포함
assert_contains "$content" "$TMP/.agent-harness/events.log" "M1 PROJECT_ROOT 치환"
assert_contains "$content" "$ROOT/bin/log-event.sh" "M1 HARNESS_ROOT 치환"
# 옛 __...__ 토큰 잔존 안 함
assert_eq "" "$(printf '%s' "$content" | grep -oE '__(PROJECT_ROOT|HARNESS_ROOT)__')" "M1 옛 토큰 부재"

bash "$ROOT/bin/team-down.sh" --project "$TMP" >/dev/null 2>&1 || true

echo "[M2] 손상된 템플릿 — 토큰 잔존 시 fail-fast"
# fixture: harness 전체 사본 + 템플릿에 sed 가 못 잡는 화이트리스트 외 토큰 박기.
# 검증 grep 은 광범위 패턴 \{\{[A-Z_]+\}\} — 화이트리스트 외 잔존도 fail.
FIX_HARNESS="$(mktemp -d)"
TMP2="$(mktemp -d)"
SAFE2="$(printf '%s' "$(basename "$TMP2")" | sed 's/[^A-Za-z0-9_-]/_/g')"
# trap 확장 — M2 자원도 EXIT 시 자동 정리. assert 중간 fail 도 leak 차단.
cleanup_m2() {
  tmux kill-session -t "agents-$SAFE2" 2>/dev/null || true
  rm -rf "$TMP2" "$FIX_HARNESS"
}
trap 'cleanup; cleanup_m2' EXIT
cp -r "$ROOT/templates" "$FIX_HARNESS/templates"
cp -r "$ROOT/bin" "$FIX_HARNESS/bin"
cp -r "$ROOT/prompts" "$FIX_HARNESS/prompts"
cp -r "$ROOT/profiles" "$FIX_HARNESS/profiles"
# 화이트리스트 외 토큰 박기 — sed 가 못 잡고 잔존 → 광범위 검증 grep 가 fail 시킴.
cat > "$FIX_HARNESS/templates/settings.json.tpl" <<'TPL'
{"hooks":{"PostToolUse":[{"matcher":"Write","hooks":[{"type":"command","command":"X={{UNKNOWN_TOKEN}} bash {{HARNESS_ROOT}}/bin/log-event.sh"}]}]}}
TPL

( cd "$TMP2" && git init -q )
out="$(HARNESS_PROJECT="$TMP2" AGENT_CMD=cat bash "$FIX_HARNESS/bin/team-up.sh" default 2>&1)"
rc=$?

assert_fail "$rc" "M2 손상된 토큰 — team-up 실패"
assert_contains "$out" "토큰 미치환" "M2 잔존 검증 메시지"

test_summary
