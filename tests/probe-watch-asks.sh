#!/usr/bin/env bash
# e2e probe: 실제 tmux + claude 로 watch-asks 동작 실측 (§8.4).
# claude -p 금지 — tmux send-keys 기반. RUN_INTEGRATION=1 일 때만.
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh

if [ "${RUN_INTEGRATION:-0}" != "1" ]; then
  echo "SKIP: RUN_INTEGRATION!=1 (e2e probe 는 claude 의존)"
  exit 0
fi

ROOT="$(cd .. && pwd)"
TMP="$(mktemp -d)"
( cd "$TMP" && git init -q )
SAFE="$(basename "$TMP" | sed 's/[^A-Za-z0-9_-]/_/g')"
SESSION="agents-$SAFE"

cleanup() {
  [ -f "$TMP/.agent-harness/state/watch-asks.pid" ] && \
    kill "$(cat "$TMP/.agent-harness/state/watch-asks.pid")" 2>/dev/null || true
  HARNESS_PROJECT="$TMP" bash "$ROOT/bin/team-down.sh" >/dev/null 2>&1 || true
  tmux kill-session -t "$SESSION" 2>/dev/null || true
  rm -rf "$TMP"
}
trap cleanup EXIT

cat > "$TMP/probe-profile.sh" <<'EOF'
LAYOUT="tiled"
WORKERS=("dev:dev:sonnet")
EOF
HARNESS_PROJECT="$TMP" bash "$ROOT/bin/team-up.sh" "$TMP/probe-profile.sh" >/dev/null 2>&1

STATE="$TMP/.agent-harness/state"

echo "[E2E-1] workers.list 생성 (F18: discovery 가 jsonl 발견)"
for i in $(seq 1 30); do [ -f "$STATE/workers.list" ] && break; sleep 1; done
[ -f "$STATE/workers.list" ]; assert_success "$?" "E2E-1 workers.list"
nf="$(awk 'NR==1{print NF}' "$STATE/workers.list")"
assert_eq "5" "$nf" "E2E-1 workers.list 5필드"

echo "[E2E-2] watch-asks 데몬 기동 (F20: env 전달)"
[ -f "$STATE/watch-asks.pid" ]; assert_success "$?" "E2E-2 데몬 PID"
kill -0 "$(cat "$STATE/watch-asks.pid")" 2>/dev/null; assert_success "$?" "E2E-2 데몬 살아있음"
assert_contains "$(cat "$STATE/watch-asks.log")" "$TMP" "E2E-2 PROJECT_ROOT env 전달"

echo "[E2E-3] matrix/lead-auto-allow 자동 통과"
pane="$(awk 'NR==1{print $2}' "$STATE/workers.list")"
tmux send-keys -t "$pane" -l "Bash 도구로 'ls /tmp' 를 실행하라"
tmux send-keys -t "$pane" Enter
for i in $(seq 1 20); do
  grep -q "ALLOWED" "$STATE/watch-asks.log" 2>/dev/null && break
  sleep 1
done
grep -q "ALLOWED" "$STATE/watch-asks.log" 2>/dev/null
assert_success "$?" "E2E-3 자동 통과 로그"

echo "[E2E-4] danger 명령 → 자동 거부 + incident"
tmux send-keys -t "$pane" -l "Bash 도구로 'rm -rf /tmp/probe-x' 를 실행하라"
tmux send-keys -t "$pane" Enter
for i in $(seq 1 20); do
  ls "$STATE/incidents"/*.json >/dev/null 2>&1 && break
  sleep 1
done
ls "$STATE/incidents"/*.json >/dev/null 2>&1
assert_success "$?" "E2E-4 incident 생성"
grep -q "AUTO-DENIED" "$STATE/watch-asks.log" 2>/dev/null
assert_success "$?" "E2E-4 AUTO-DENIED 로그"

test_summary
