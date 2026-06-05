#!/usr/bin/env bash
# 회귀 가드: @lead-ask(LEAD→PM 역방향)가 프롬프트·산출 boot 에서 완전히 사라졌는지.
# 11차 push-pull 재정비 — 미래 드리프트 방지.
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
source ./harness-paths.sh

ROOT="$(cd .. && pwd)"
export AGENT_CMD="cat"

# 1) 프롬프트 소스에 @lead-ask 0건.
if grep -rn "lead-ask" "$HARNESS_PROMPTS/" >/dev/null 2>&1; then
  assert_eq "0건" "발견됨" "prompts/ 에 @lead-ask 잔존: $(grep -rn 'lead-ask' "$HARNESS_PROMPTS/")"
else
  assert_eq "0건" "0건" "prompts/ 에 @lead-ask 잔존 0건"
fi

# 2) awa-up.sh 코드에 @lead-ask·pm pane 알림 채널 주입 0건.
if grep -n "lead-ask\|pm pane 알림 채널" "$HARNESS_BIN/awa-up.sh" >/dev/null 2>&1; then
  assert_eq "0건" "발견됨" "awa-up.sh 에 @lead-ask 잔존: $(grep -n 'lead-ask\|pm pane 알림 채널' "$HARNESS_BIN/awa-up.sh")"
else
  assert_eq "0건" "0건" "awa-up.sh 에 @lead-ask 채널 주입 0건"
fi

# 3) 산출된 LEAD boot 합본에 @lead-ask·pm pane_id 채널 0건 (실제 가동 산출물).
PROJ="$(mktemp -d)"; ( cd "$PROJ" && git init -q )
SES="$(HARNESS_PROJECT="$PROJ" bash -c "source $HARNESS_BIN/lib.sh; resolve_session")"

# 15th: bookmarks 격리 — awa-up.sh 가 ~/.config/awa/bookmarks.tsv 에 기록.
# 테스트 fixture 가 사용자 실 경로를 더럽히지 않도록 임시 dir 로 redirect.
_AGPN15_XDG="$(mktemp -d)"
export XDG_CONFIG_HOME="$_AGPN15_XDG"

cleanup() { tmux kill-session -t "$SES" 2>/dev/null || true; rm -rf "$PROJ"; [ -n "${_AGPN15_XDG:-}" ] && rm -rf "$_AGPN15_XDG"; }
trap cleanup EXIT

bash "$HARNESS_BIN/awa-up.sh" --project "$PROJ" default >/dev/null 2>&1
sleep 0.8
LEAD_BOOT="$PROJ/.agent-harness/.boot/LEAD.md"
[ -f "$LEAD_BOOT" ]
assert_success "$?" "LEAD boot 합본 생성"
if grep -qF "lead-ask" "$LEAD_BOOT" 2>/dev/null; then
  assert_eq "0건" "발견됨" "LEAD boot 에 @lead-ask 잔존"
else
  assert_eq "0건" "0건" "LEAD boot 에 @lead-ask 잔존 0건"
fi
bash "$HARNESS_BIN/awa-down.sh" --project "$PROJ" >/dev/null 2>&1

test_summary
