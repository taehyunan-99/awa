#!/usr/bin/env bash
# watch-asks 데몬: 워커 jsonl tail -F + 줄 단위 분류·응답·큐 관리 (§5.1).
set -euo pipefail
shopt -s nullglob

# 테스트가 함수만 로드할 때 (메인 루프·env required 스킵). T14/T15 단위 테스트가 사용.
if [ "${WATCH_ASKS_LIB_ONLY:-0}" = "1" ]; then
  : "${PROJECT_ROOT:=}" "${HARNESS_ROOT:=}"
fi

if [ "${WATCH_ASKS_LIB_ONLY:-0}" != "1" ]; then
  PROJECT_ROOT="${PROJECT_ROOT:?}"
  HARNESS_ROOT="${HARNESS_ROOT:?}"
  # lib.sh 가 HARNESS_PROJECT 우선으로 PROJECT_ROOT 를 재계산하므로,
  # 외부에서 PROJECT_ROOT env 로 넘긴 값을 lib.sh source 전에 HARNESS_PROJECT 에 전달.
  export HARNESS_PROJECT="${PROJECT_ROOT}"
  STATE_DIR="${PROJECT_ROOT}/.agent-harness/state"
  export LOG="${STATE_DIR}/watch-asks.log"
fi

# shellcheck disable=SC1091
source "${HARNESS_ROOT}/bin/lib.sh"

# T13 골격에서는 lib.sh 만 source (matrix/danger/notify 는 T14 가 추가).

run_daemon() {
  mkdir -p "${STATE_DIR}/pending-asks" "${STATE_DIR}/incidents" "${STATE_DIR}/removal-requests"
  echo $$ > "${STATE_DIR}/watch-asks.pid"
  # F20: env 전달 검증 — 첫 줄에 PROJECT_ROOT/HARNESS_ROOT 기록.
  log_safe "[$(timestamp)] watch-asks 기동 PROJECT_ROOT=${PROJECT_ROOT} HARNESS_ROOT=${HARNESS_ROOT}"

  CHILDREN=()
  trap cleanup EXIT INT TERM

  # workers.list 읽어 워커당 자식 fork (lead skip).
  while IFS=' ' read -r entry_name pane session jsonl_path entry_role; do
    [[ "${entry_role}" == "lead" || "${entry_role}" == "LEAD" ]] && continue
    watch_one_worker "${entry_name}" "${entry_role}" "${pane}" "${session}" "${jsonl_path}" &
    CHILDREN+=($!)
  done < "${STATE_DIR}/workers.list"

  watch_pending_responses &
  CHILDREN+=($!)

  wait
}

# 재귀 descendants 수집 (pkill -P 는 직계 자식만 — tail 은 손자).
descendants() {
  local p="$1" c
  for c in $(pgrep -P "$p" 2>/dev/null); do
    descendants "$c"
    echo "$c"
  done
}

cleanup() {
  # 1차: tail PID 직접 kill (reparent 면역 — FIFO 경유로 PID 직접 추적)
  if [[ -f "${STATE_DIR}/tail-pids" ]]; then
    while IFS= read -r tpid; do
      kill "$tpid" 2>/dev/null || true
    done < "${STATE_DIR}/tail-pids"
    rm -f "${STATE_DIR}/tail-pids"
  fi
  # 2차: 직계 자식
  for cpid in "${CHILDREN[@]:-}"; do
    kill "$cpid" 2>/dev/null || true
  done
  # 3차: 재귀 손자 (보루 — reparent 안 된 손자 대비)
  for d in $(descendants $$); do
    kill "$d" 2>/dev/null || true
  done
  pkill -P $$ 2>/dev/null || true
  exit 0
}

# T14 가 채울 분류 함수 (골격: 로그만).
process_jsonl_line() {
  local entry_name="$1" entry_role="$2" pane="$3" session="$4" line="$5"
  log_safe "[$(timestamp)] ${entry_name} 줄 수신 (골격 — T14 가 분류)"
}

watch_one_worker() {
  local entry_name="$1" entry_role="$2" pane="$3" session="$4" jsonl="$5"
  # FIFO 경유로 tail 을 백그라운드 잡으로 → PID 직접 추적 (reparent 면역, 실측 PASS).
  # pipe(`tail | while`) 면 tail 이 손자라 reparent 시 좀비. BSD tail: --line-buffered 없음.
  local fifo; fifo=$(mktemp -u)
  mkfifo "$fifo"
  tail -F -n 0 "${jsonl}" > "$fifo" 2>/dev/null &
  local tail_pid=$!
  echo "$tail_pid" >> "${STATE_DIR}/tail-pids"   # cleanup 이 직접 kill (단일 데몬 내 순차 append → race 없음)
  while IFS= read -r line; do
    process_jsonl_line "${entry_name}" "${entry_role}" "${pane}" "${session}" "${line}"
  done < "$fifo"
  rm -f "$fifo"
}

# T15 가 채울 응답 watcher (골격: 빈 루프).
watch_pending_responses() {
  while true; do
    sleep 0.5
  done
}

# 메인: 라이브러리 로드 모드가 아니면 데몬 실행.
if [ "${WATCH_ASKS_LIB_ONLY:-0}" != "1" ]; then
  run_daemon
fi
