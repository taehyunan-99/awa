#!/usr/bin/env bash
# P11 Phase2 — dispatch-queue 탈-tmux 검증.
# lead 가 tmux 를 직접 안 건드리고 dispatch-queue/<id>.json 만 쓰면, watcher(sandbox 밖)가
# 폴링해 dispatch.sh 를 대행 → 워커가 TASK 를 받아 결과를 낸다. 이 end-to-end 경로를 검증.
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
source ./harness-paths.sh

ROOT="$(cd .. && pwd)"
export SESSION_OVERRIDE="dq_$$"
# 더미 워커: TASK 받으면 결과 파일 + done 라인(탈-tmux 완료신호).
export AGENT_CMD="bash $ROOT/tests/dummy-worker.sh engineer $SESSION_OVERRIDE"

TMP_PROJ="$(mktemp -d)"; ( cd "$TMP_PROJ" && git init -q )
export HARNESS_PROJECT="$TMP_PROJ"

_XDG="$(mktemp -d)"; export XDG_CONFIG_HOME="$_XDG"

cleanup() {
  tmux kill-session -t "$SESSION_OVERRIDE" 2>/dev/null || true
  [ -n "${TMP_PROJ:-}" ] && rm -rf "$TMP_PROJ"
  [ -n "${_XDG:-}" ] && rm -rf "$_XDG"
}
trap cleanup EXIT

bash "$HARNESS_BIN/awa-up.sh" default >/dev/null
sleep 0.5

WS="$TMP_PROJ/.agent-harness"
# 1) lead 가 할 일을 모사: task 파일 작성 + dispatch-queue 에 json atomic write.
#    (tmux 명령 전혀 안 씀 — sandbox 안 lead 와 동일 조건.)
echo "# Q1: dispatch-queue E2E 더미 작업" > "$WS/tasks/Q1.md"
mkdir -p "$WS/state/dispatch-queue"
printf '{"worker":"engineer","task_id":"Q1"}' > "$WS/state/dispatch-queue/Q1.json.tmp"
mv "$WS/state/dispatch-queue/Q1.json.tmp" "$WS/state/dispatch-queue/Q1.json"

# 2) watcher 가 큐를 폴링해 dispatch.sh 를 대행 → 워커 결과 파일 생성까지 대기(최대 ~8s).
RES="$WS/results/Q1.md"
for _i in $(seq 1 80); do
  [ -f "$RES" ] && break
  sleep 0.1
done

assert_eq "0" "$([ -f "$RES" ] && echo 0 || echo 1)" "watcher 가 dispatch-queue 소비→워커 결과 생성"
[ -f "$RES" ] && assert_contains "$(cat "$RES")" "상태: SUCCESS" "결과에 SUCCESS"

# 3) watcher 가 큐 .json 을 소비(삭제)했는지 — 무한 재실행 방지.
assert_eq "1" "$([ -f "$WS/state/dispatch-queue/Q1.json" ] && echo 0 || echo 1)" "처리된 dispatch-queue .json 소비됨(삭제)"

test_summary
