#!/usr/bin/env bash
# 워커 settings 의 {{...}} 토큰 치환 확인 + 손상 템플릿 잔존 시 awa-up fail.
# 6차: project .claude/settings.json 은 빈 {} 로 이관됨 (hook 은 워커 --settings 로).
#   따라서 토큰 치환(events.log/log-event.sh)의 검증 대상은 워커 .boot-settings/<role>.json.
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh

ROOT="$(cd .. && pwd)"
TMP="$(mktemp -d)"

# 15th: bookmarks 격리 — awa-up.sh 가 ~/.config/awa/bookmarks.tsv 에 기록.
# 테스트 fixture 가 사용자 실 경로를 더럽히지 않도록 임시 dir 로 redirect.
_AGPN15_XDG="$(mktemp -d)"
export XDG_CONFIG_HOME="$_AGPN15_XDG"

cleanup() {
  tmux kill-session -t "awa-$(printf '%s' "$(basename "$TMP")" | sed 's/[^A-Za-z0-9_-]/_/g')" 2>/dev/null || true
  rm -rf "$TMP"
  [ -n "${_AGPN15_XDG:-}" ] && rm -rf "$_AGPN15_XDG"
}
trap cleanup EXIT
( cd "$TMP" && git init -q )

echo "[M1] 정상 awa-up — 워커 settings 토큰 치환 완료 (PostToolUse log-event)"
HARNESS_PROJECT="$TMP" AGENT_CMD=cat bash "$ROOT/bin/awa-up.sh" default >/dev/null 2>&1
rc=$?
assert_eq "0" "$rc" "M1 awa-up 성공"
# 6차: project settings.json 은 빈 {} — 토큰 치환 검증은 워커 settings 에서.
proj_content="$(cat "$TMP/.claude/settings.json")"
assert_eq "{}" "$(printf '%s' "$proj_content" | tr -d '[:space:]')" "M1 project settings 빈 {} (hook 이관)"
# 워커 engineer settings — PostToolUse(log-event) 토큰 치환 확인.
worker_settings="$TMP/.agent-harness/.boot-settings/engineer.json"
[ -f "$worker_settings" ]; assert_success "$?" "M1 워커 engineer settings 생성됨"
content="$(cat "$worker_settings" 2>/dev/null || true)"
# {{...}} 토큰 잔존 검증
assert_eq "" "$(printf '%s' "$content" | grep -oE '\{\{[A-Z_]+\}\}')" "M1 토큰 잔존 없음"
# 치환 결과에 실제 경로 포함 (PostToolUse log-event)
assert_contains "$content" "$TMP/.agent-harness/events.log" "M1 PROJECT_ROOT 치환"
assert_contains "$content" "$ROOT/bin/log-event.sh" "M1 HARNESS_ROOT 치환 (PostToolUse)"
# PreToolUse permission-gate 도 함께 (단일 --settings 공존 확인)
assert_contains "$content" "$ROOT/bin/permission-gate.sh" "M1 PreToolUse permission-gate 공존"

bash "$ROOT/bin/awa-down.sh" --project "$TMP" >/dev/null 2>&1 || true

echo "[M2] 손상된 템플릿 — 토큰 잔존 시 fail-fast"
# fixture: harness 전체 사본 + 템플릿에 sed 가 못 잡는 화이트리스트 외 토큰 박기.
# 검증 grep 은 광범위 패턴 \{\{[A-Z_]+\}\} — 화이트리스트 외 잔존도 fail.
FIX_HARNESS="$(mktemp -d)"
TMP2="$(mktemp -d)"
SAFE2="$(printf '%s' "$(basename "$TMP2")" | sed 's/[^A-Za-z0-9_-]/_/g')"
# trap 확장 — M2 자원도 EXIT 시 자동 정리. assert 중간 fail 도 leak 차단.
cleanup_m2() {
  tmux kill-session -t "awa-$SAFE2" 2>/dev/null || true
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
out="$(HARNESS_PROJECT="$TMP2" AGENT_CMD=cat bash "$FIX_HARNESS/bin/awa-up.sh" default 2>&1)"
rc=$?

assert_fail "$rc" "M2 손상된 토큰 — awa-up 실패"
assert_contains "$out" "토큰 미치환" "M2 잔존 검증 메시지"

test_summary
