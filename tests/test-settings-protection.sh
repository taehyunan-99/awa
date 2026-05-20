#!/usr/bin/env bash
# T15: D2·E8·F8 통합 — settings.json marker 게이트가 team-up/team-down 양쪽에서 일관 동작.
# 주의: 파일 상단에 set -e 없음. plan 의 `set +e ... set -e` 페어 함정 회피 — 그냥 rc 캡처만.
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"

TMP="$(mktemp -d)"

# 본 테스트가 띄우는 agents-* 세션만 정리 (다른 테스트와 충돌 회피 위해 변수로 좁힘).
# 단 마지막 T15.4 의 agents-otherproj 는 명시적 prefix 이므로 함께 정리.
_session_cleanup() {
  tmux kill-session -t "agents-otherproj" 2>/dev/null || true
  if [ -n "${T15_SAFE:-}" ]; then
    tmux kill-session -t "agents-$T15_SAFE" 2>/dev/null || true
  fi
}
trap '_session_cleanup; rm -rf "$TMP"' EXIT

( cd "$TMP" && git init -q )
mkdir -p "$TMP/.claude"

# 세션 이름 사전 계산 (lib.sh _session_autoname 과 동일 규칙).
T15_SAFE="$(printf '%s' "$(basename "$TMP")" | sed 's/[^A-Za-z0-9_-]/_/g')"

echo "[T15.1] marker 없는 settings.json — team-up 거부 + 사용자 데이터 보존"
echo '{"existing":"user_setting"}' > "$TMP/.claude/settings.json"
# marker 없음 (의도적)
out="$(HARNESS_PROJECT="$TMP" AGENT_CMD=cat bash "$ROOT/bin/team-up.sh" default 2>&1)"
rc=$?
assert_fail "$rc" "team-up 거부 (rc != 0)"
assert_contains "$out" "이미 존재" "거부 메시지"
content="$(cat "$TMP/.claude/settings.json")"
assert_contains "$content" "user_setting" "사용자 settings.json 보존"
# T15.1 가 만일 세션을 띄웠다면 leak 방지 (정상 흐름이면 안 띄움)
tmux kill-session -t "agents-$T15_SAFE" 2>/dev/null || true
rm -f "$TMP/.claude/settings.json"

echo "[T15.2] marker 있을 때 team-up 정상 — settings.json 덮어쓰기, marker 유지"
echo '{"old":"harness_made"}' > "$TMP/.claude/settings.json"
touch "$TMP/.claude/.agent-harness-marker"
HARNESS_PROJECT="$TMP" AGENT_CMD=cat bash "$ROOT/bin/team-up.sh" default >/dev/null 2>&1
rc=$?
assert_success "$rc" "team-up 성공 (marker 있음)"
sleep 0.3
grep -q "log-event.sh" "$TMP/.claude/settings.json"; assert_success "$?" "settings.json 덮어쓰기 (hook 포함)"
[ -f "$TMP/.claude/.agent-harness-marker" ]; assert_success "$?" "marker 유지"
tmux kill-session -t "agents-$T15_SAFE" 2>/dev/null || true
rm -f "$TMP/.claude/settings.json" "$TMP/.claude/.agent-harness-marker"

echo "[T15.3] marker 없는 team-down — 정리 skip + 안내, 사용자 데이터 보존"
echo '{"user":"setting"}' > "$TMP/.claude/settings.json"
mkdir -p "$TMP/.agent-harness"
echo "user_data" > "$TMP/.agent-harness/important.txt"
out="$(HARNESS_PROJECT="$TMP" bash "$ROOT/bin/team-down.sh" 2>&1)"
rc=$?
assert_success "$rc" "team-down rc=0 (멱등)"
assert_contains "$out" "marker 없음" "marker 없음 경고"
[ -f "$TMP/.claude/settings.json" ]; assert_success "$?" "settings.json 보존"
[ -f "$TMP/.agent-harness/important.txt" ]; assert_success "$?" ".agent-harness/ 사용자 파일 보존"
rm -f "$TMP/.claude/settings.json"
rm -rf "$TMP/.agent-harness"

echo "[T15.4] 살아있는 agents-* 세션 안내 (F8)"
tmux new-session -d -s "agents-otherproj" 2>/dev/null
out="$(HARNESS_PROJECT="$TMP" bash "$ROOT/bin/team-down.sh" 2>&1)"
rc=$?
assert_success "$rc" "team-down rc=0"
assert_contains "$out" "agents-otherproj" "다른 살아있는 세션 안내"
tmux kill-session -t "agents-otherproj" 2>/dev/null || true

test_summary
