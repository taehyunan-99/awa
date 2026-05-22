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
# shellcheck disable=SC1091
source "${HARNESS_ROOT}/bin/matrix-lookup.sh"
# shellcheck disable=SC1091
source "${HARNESS_ROOT}/bin/danger-check.sh"
# shellcheck disable=SC1091
source "${HARNESS_ROOT}/bin/notify-lead.sh"

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

# ===== jsonl 줄 파싱 helper =====

is_assistant_text() {
  printf '%s' "$1" | jq -e '.message.content[]? | select(.type=="text")' >/dev/null 2>&1
}
extract_text() {
  printf '%s' "$1" | jq -r '[.message.content[]? | select(.type=="text") | .text] | join(" ")' 2>/dev/null
}
matches_rm_report() {
  # @lead: rm / rm-r / remove-dir 보고 패턴.
  local re='@lead:[[:space:]]*(rm|rm-r|remove-dir)[[:space:]]'
  [[ "$1" =~ $re ]]
}
is_tool_use() {
  printf '%s' "$1" | jq -e '.message.content[]? | select(.type=="tool_use")' >/dev/null 2>&1
}
extract_tool() {
  printf '%s' "$1" | jq -r 'first(.message.content[]? | select(.type=="tool_use") | .name)' 2>/dev/null
}
extract_input_json() {
  printf '%s' "$1" | jq -c 'first(.message.content[]? | select(.type=="tool_use") | .input)' 2>/dev/null
}

send_keys_safe() {
  local pane="$1" key="$2"
  if ! tmux send-keys -t "$pane" "$key" 2>/dev/null; then
    log_safe "[$(timestamp)] SEND_KEYS_FAILED pane=${pane} key=${key}"
    mark_worker_inactive "$pane"   # E4(spec §6): workers.list 의 해당 워커를 `# inactive:` 로 표시 → 다음 사이클 lead 발견
  fi
}

# E4: send-keys 실패(pane 죽음) 시 workers.list 해당 줄을 `# inactive:` heading 으로 prefix.
# pane 은 4번째 필드가 아님 — entry_name pane session jsonl entry_role 중 2번째. atomic(tmp+mv).
mark_worker_inactive() {
  local pane="$1" list="${STATE_DIR}/workers.list" tmp
  [ -f "$list" ] || return 0
  tmp="${list}.tmp.$$.${RANDOM}"   # F2: 병렬 워커 tmp 충돌 회피
  awk -v p="$pane" '{ if ($2==p && $0 !~ /^# inactive:/) print "# inactive: " $0; else print }' "$list" > "$tmp" && mv "$tmp" "$list"
}

log_and_queue_removal() {
  local entry_name="$1" text="$2"
  local uuid; uuid="$(uuidgen)"
  local f="${STATE_DIR}/removal-requests/${uuid}.json"
  jq -n --arg w "$entry_name" --arg t "$text" --argjson ts "$(timestamp)" \
    '{worker:$w, report:$t, timestamp:$ts, status:"pending"}' > "$f"
  notify_lead
  log_safe "[$(timestamp)] ${entry_name} rm 보고 → removal-request (${uuid})"
}

queue_incident() {
  local entry_name="$1" pane="$2" tool="$3" input="$4" category="$5"
  local uuid; uuid="$(uuidgen)"
  local f="${STATE_DIR}/incidents/${uuid}.json"
  jq -n --arg w "$entry_name" --arg p "$pane" --arg tool "$tool" \
        --argjson inp "$input" --arg cat "$category" --argjson ts "$(timestamp)" \
    '{worker:$w, pane:$p, tool:$tool, input:$inp, category:$cat, timestamp:$ts, notified:false}' > "$f"
}

queue_pending_ask() {
  local uuid="$1" entry_name="$2" entry_role="$3" pane="$4" session="$5" tool="$6" input="$7"
  local f="${STATE_DIR}/pending-asks/${uuid}.json"
  jq -n --arg w "$entry_name" --arg r "$entry_role" --arg p "$pane" --arg s "$session" \
        --arg tool "$tool" --argjson inp "$input" --argjson ts "$(timestamp)" \
    '{worker:$w, entry_role:$r, pane:$p, session:$s, tool:$tool, input:$inp, timestamp:$ts}' > "$f"
}

process_jsonl_line() {
  local entry_name="$1" entry_role="$2" pane="$3" session="$4" line="$5"
  local text tool input input_summary matched category cat_pattern pattern ask_uuid

  # 1. assistant text 의 @lead: rm 보고 감지
  if is_assistant_text "${line}"; then
    text="$(extract_text "${line}")"
    if matches_rm_report "${text}"; then
      log_and_queue_removal "${entry_name}" "${text}"
    fi
    return
  fi

  # 2. tool_use 이벤트만 처리
  is_tool_use "${line}" || return

  tool="$(extract_tool "${line}")"
  input="$(extract_input_json "${line}")"
  [ -n "$input" ] || input='{}'
  input_summary="$(summarize_input "${tool}" "${input}")"

  # 3. matrix-lookup → MATCH 면 send-keys 2
  if matched="$(matrix_lookup "${entry_role}" "${tool}" "${input}")"; then
    send_keys_safe "${pane}" "2"
    log_safe "[$(timestamp)] ${entry_name} ${tool}(${input_summary}) → MATRIX-ALLOWED (${matched})"
    return
  fi

  # 4. danger-check → MATCH 면 send-keys 3 + incident (lead-auto-allow 보다 먼저)
  if category="$(danger_check "${tool}" "${input}")"; then
    send_keys_safe "${pane}" "3"
    queue_incident "${entry_name}" "${pane}" "${tool}" "${input}" "${category}"
    notify_lead
    log_safe "[$(timestamp)] ${entry_name} ${tool}(${input_summary}) → AUTO-DENIED (${category})"
    return
  fi

  # 5. lead-auto-allow → MATCH 면 add_to_allow + send-keys 2
  if cat_pattern="$(lead_auto_allow_lookup "${tool}" "${input}")"; then
    category="${cat_pattern%%:*}"
    pattern="${cat_pattern#*:}"
    add_to_allow "${entry_role}" "${pattern}"
    send_keys_safe "${pane}" "2"
    log_safe "[$(timestamp)] ${entry_name} ${tool}(${input_summary}) → LEAD-AUTO-ALLOWED (category: ${category}, added: ${pattern})"
    return
  fi

  # 6. 회색 영역 → pending-ask
  ask_uuid="$(uuidgen)"
  queue_pending_ask "${ask_uuid}" "${entry_name}" "${entry_role}" "${pane}" "${session}" "${tool}" "${input}"
  notify_lead
  log_safe "[$(timestamp)] ${entry_name} ${tool}(${input_summary}) → USER-ASK (uuid: ${ask_uuid})"
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

watch_pending_responses() {
  while true; do
    for resp in "${STATE_DIR}/pending-asks/"*.response; do
      [[ -f "${resp}" ]] || continue
      process_response "${resp}"
    done
    sleep 0.5
  done
}

process_response() {
  local resp="$1"
  local uuid="${resp##*/}"; uuid="${uuid%.response}"
  local meta="${STATE_DIR}/pending-asks/${uuid}.json"

  [[ -f "${meta}" ]] || { rm -f "${resp}"; return; }

  local entry_role pane tool input decision scope pattern
  entry_role="$(jq -r .entry_role "${meta}")"
  pane="$(jq -r .pane "${meta}")"
  tool="$(jq -r .tool "${meta}")"
  input="$(jq -c '.input' "${meta}")"
  decision="$(cat "${resp}")"

  case "${decision}" in
    approve-once)
      send_keys_safe "${pane}" "1"
      ;;
    "approve-permanent:exact"|"approve-permanent:command-group"|"approve-permanent:tool")
      scope="${decision#approve-permanent:}"
      pattern="$(derive_pattern "${tool}" "${input}" "${scope}")"
      add_to_allow "${entry_role}" "${pattern}"
      send_keys_safe "${pane}" "2"
      ;;
    deny)
      send_keys_safe "${pane}" "3"
      ;;
  esac

  rm -f "${resp}" "${meta}"
  notify_lead
}

# 메인: 라이브러리 로드 모드가 아니면 데몬 실행.
if [ "${WATCH_ASKS_LIB_ONLY:-0}" != "1" ]; then
  run_daemon
fi
