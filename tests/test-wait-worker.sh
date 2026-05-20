#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh

ROOT="$(cd .. && pwd)"
export SESSION_OVERRIDE="ww_$$"
export AGENT_CMD="cat"

# T9: HARNESS_PROJECT 격리 — wait-worker.sh 가 cwd 가 git repo 인지 검사하므로
# 임시 PROJECT_ROOT 를 지정 (echo cwd 의 git repo 영향 차단).
TMP_PROJ="$(mktemp -d)"; ( cd "$TMP_PROJ" && git init -q )
export HARNESS_PROJECT="$TMP_PROJ"

cleanup() {
  tmux kill-session -t "$SESSION_OVERRIDE" 2>/dev/null || true
  rm -rf "$TMP_PROJ"
}
trap cleanup EXIT

bash "$ROOT/bin/team-up.sh" default >/dev/null
sleep 0.3

# 신호가 먼저 와 있는 경우: 즉시 반환 (race 안전, spec §4.2)
# T9(E1): CHANNEL=done-$SESSION-$WORKER-$TASK_ID 로 SESSION prefix 필수.
tmux wait-for -S "done-$SESSION_OVERRIDE-dev-PRE"
START=$(date +%s)
SESSION_OVERRIDE="$SESSION_OVERRIDE" bash "$ROOT/bin/wait-worker.sh" dev PRE 5
rc=$?
END=$(date +%s)
assert_eq "0" "$rc" "선신호 → 즉시 0 종료"
[ $((END - START)) -le 2 ]; assert_eq "0" "$?" "선신호 → 2초 이내 반환"

# 신호를 나중에 보내는 경우: 백그라운드에서 1초 후 신호
( sleep 1; tmux wait-for -S "done-$SESSION_OVERRIDE-dev-LATER" ) &
START=$(date +%s)
SESSION_OVERRIDE="$SESSION_OVERRIDE" bash "$ROOT/bin/wait-worker.sh" dev LATER 5
rc=$?
assert_eq "0" "$rc" "지연 신호 → 0 종료"
wait

# 타임아웃: 아무도 신호 안 보냄 → 2초 타임아웃, 비-0, 페인 덤프 출력
OUT="$(SESSION_OVERRIDE="$SESSION_OVERRIDE" bash "$ROOT/bin/wait-worker.sh" dev NEVER 2 2>&1)"
rc=$?
assert_fail "$rc" "타임아웃 → 비-0 종료"
assert_contains "$OUT" "타임아웃" "타임아웃 메시지 출력"
assert_contains "$OUT" "capture" "페인 덤프 섹션 표기"

test_summary
