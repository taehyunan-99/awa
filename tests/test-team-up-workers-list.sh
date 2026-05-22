#!/usr/bin/env bash
# team-up.sh 의 5차 변경: new-session -c, settings 2인자, 데몬 기동 코드 존재.
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"
src="$(cat "$ROOT/bin/team-up.sh")"

echo "[U1] new-session 에 -c PROJECT_ROOT"
assert_contains "$src" 'new-session -d -s "$SESSION" -c "${PROJECT_ROOT}"' "U1 new-session -c"

echo "[U2] 워커 settings 2인자 호출"
assert_contains "$src" 'generate_worker_settings "$ENTRY_ROLE" "$ENTRY_NAME"' "U2 워커 2인자"

echo "[U3] lead settings 2인자 호출"
assert_contains "$src" 'generate_worker_settings "LEAD" "LEAD"' "U3 lead 2인자"

echo "[U4] discover_jsonl_and_record 3곳 호출"
n="$(printf '%s' "$src" | grep -c 'discover_jsonl_and_record')"
[ "$n" -ge 3 ]; assert_success "$?" "U4 discovery 3곳 ($n)"

echo "[U5] watch-asks 데몬 기동 (nohup)"
assert_contains "$src" 'nohup bash "${HARNESS_ROOT}/bin/watch-asks.sh"' "U5 데몬 nohup"

echo "[U6] cat 더미로 team-up 성공 (데몬 코드가 cat 경로 안 깨뜨림)"
TMP="$(mktemp -d)"; SAFE="$(basename "$TMP" | sed 's/[^A-Za-z0-9_-]/_/g')"; SESSION="agents-$SAFE"
( cd "$TMP" && git init -q )
# DISCOVER_MAX_TRIES=1: cat 더미는 jsonl 미생성 → discovery 가 기본 60회×0.5s×3곳(워커/lead/리뷰어) 폴링하면 90s+ hang.
# 1회로 단축해 cat 경로 빠른 종료(실측: 30s hang → 10s). claude 분기는 이 env 없이 정상 폴링.
HARNESS_PROJECT="$TMP" AGENT_CMD=cat DISCOVER_MAX_TRIES=1 bash "$ROOT/bin/team-up.sh" feature-team >/dev/null 2>&1
rc=$?
tmux kill-session -t "$SESSION" 2>/dev/null || true
[ -f "$TMP/.agent-harness/state/watch-asks.pid" ] && kill "$(cat "$TMP/.agent-harness/state/watch-asks.pid")" 2>/dev/null || true
rm -rf "$TMP"
assert_eq "0" "$rc" "U6 team-up 성공 (cat 경로)"

test_summary
