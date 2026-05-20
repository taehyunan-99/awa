#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh

ROOT="$(cd .. && pwd)"
export SESSION_OVERRIDE="e2e_$$"
# 워커 페인에서 더미 워커 실행 (dev 워커만 검증 대상; 나머지도 같은 더미)
export AGENT_CMD="bash $ROOT/tests/dummy-worker.sh dev $SESSION_OVERRIDE"

# T12: PROJECT_ROOT 분리 후 임시 git repo 를 PROJECT_ROOT 로 사용
TMP_PROJ="$(mktemp -d)"; ( cd "$TMP_PROJ" && git init -q )
export HARNESS_PROJECT="$TMP_PROJ"

cleanup() {
  tmux kill-session -t "$SESSION_OVERRIDE" 2>/dev/null || true
  [ -n "${TMP_PROJ:-}" ] && rm -rf "$TMP_PROJ"
}
trap cleanup EXIT

bash "$ROOT/bin/team-up.sh" default >/dev/null
sleep 0.5

# 작업 파일 작성
echo "# E1: E2E 더미 작업" > "$TMP_PROJ/.agent-harness/tasks/E1.md"

# dispatch → wait → 결과 확인
SESSION_OVERRIDE="$SESSION_OVERRIDE" bash "$ROOT/bin/dispatch.sh" dev E1
assert_eq "0" "$?" "E2E dispatch 성공"

SESSION_OVERRIDE="$SESSION_OVERRIDE" bash "$ROOT/bin/wait-worker.sh" dev E1 10
assert_eq "0" "$?" "E2E wait-worker 신호 수신"

[ -f "$TMP_PROJ/.agent-harness/results/E1.md" ]; assert_eq "0" "$?" "결과 파일 생성됨"
RES="$(cat "$TMP_PROJ/.agent-harness/results/E1.md")"
assert_contains "$RES" "상태: SUCCESS" "결과에 SUCCESS"
assert_contains "$RES" "워커: dev" "결과에 워커명"

test_summary
