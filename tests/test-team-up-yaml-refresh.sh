#!/usr/bin/env bash
# awa-up 의 orch-auto-allow.yaml marker 게이트 + 백업 갱신 검증 (8차).
# 4 시나리오: 최초설치 / marker있음+다름→백업갱신 / marker있음+같음→스킵 / marker없음→보호경고.
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"
TMP="$(mktemp -d)"
SAFE="$(printf '%s' "$(basename "$TMP")" | sed 's/[^A-Za-z0-9_-]/_/g')"
SESSION="awa-$SAFE"

# 15th: bookmarks 격리 — awa-up.sh 가 ~/.config/awa/bookmarks.tsv 에 기록.
# 테스트 fixture 가 사용자 실 경로를 더럽히지 않도록 임시 dir 로 redirect.
_AGPN15_XDG="$(mktemp -d)"
export XDG_CONFIG_HOME="$_AGPN15_XDG"

cleanup() { tmux kill-session -t "$SESSION" 2>/dev/null || true; rm -rf "$TMP"; [ -n "${_AGPN15_XDG:-}" ] && rm -rf "$_AGPN15_XDG"; }
trap cleanup EXIT
( cd "$TMP" && git init -q )

YAML="$TMP/.agent-harness/config/orch-auto-allow.yaml"
MARKER="$TMP/.agent-harness/config/.orch-auto-allow-marker"
run_teamup() { HARNESS_PROJECT="$TMP" AGENT_CMD=cat bash "$ROOT/bin/awa-up.sh" feature-team >/dev/null 2>&1; tmux kill-session -t "$SESSION" 2>/dev/null || true; }

echo "[YR1] 최초설치: yaml 없음 → 복사 + marker 생성"
run_teamup
[ -f "$YAML" ];   assert_success "$?" "YR1 yaml 생성됨"
[ -f "$MARKER" ]; assert_success "$?" "YR1 marker 생성됨"
cmp -s "$ROOT/config/orch-auto-allow.yaml" "$YAML"; assert_success "$?" "YR1 하네스와 동일"

echo "[YR2] marker있음+같음: 재실행 → 백업 안 만듦(스킵)"
run_teamup
bak_count="$(ls "$TMP/.agent-harness/config/"*.bak 2>/dev/null | wc -l | tr -d ' ')"
assert_eq "0" "$bak_count" "YR2 동일 yaml 재설치 시 .bak 없음"

echo "[YR3] marker있음+다름: 구버전 yaml → 백업 후 하네스 최신으로 갱신"
printf 'read-only:\n  - "Bash(OLDVERSION:*)"\n' > "$YAML"   # 구버전으로 변조 (marker 유지)
run_teamup
bak_count="$(ls "$TMP/.agent-harness/config/"*.bak 2>/dev/null | wc -l | tr -d ' ')"
assert_eq "1" "$bak_count" "YR3 .bak 1개 생성"
cmp -s "$ROOT/config/orch-auto-allow.yaml" "$YAML"; assert_success "$?" "YR3 하네스 최신으로 교체됨"
grep -q OLDVERSION "$TMP/.agent-harness/config/"*.bak; assert_success "$?" "YR3 구버전이 .bak 에 보존"

echo "[YR4] marker없음+있음: 사용자 작성 → 보존(불변) + 경고"
rm -f "$TMP/.agent-harness/config/"*.bak "$MARKER"           # marker 제거 = 사용자 작성 취급
printf 'read-only:\n  - "Bash(USERCUSTOM:*)"\n' > "$YAML"
warn="$(HARNESS_PROJECT="$TMP" AGENT_CMD=cat bash "$ROOT/bin/awa-up.sh" feature-team 2>&1 >/dev/null)"
tmux kill-session -t "$SESSION" 2>/dev/null || true
grep -q USERCUSTOM "$YAML"; assert_success "$?" "YR4 사용자 yaml 보존(불변)"
printf '%s' "$warn" | grep -qiE 'orch-auto-allow|marker|사용자'; assert_success "$?" "YR4 경고 출력"

test_summary
