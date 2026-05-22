#!/usr/bin/env bash
# notify_lead: 세 디렉터리 항목 수 → lead pane status-right 갱신. source 시 부수효과 없음.
# NOTIFY_DRY_RUN=1 이면 tmux 호출 대신 echo (테스트용).

notify_lead() {
  local state="${PROJECT_ROOT}/.agent-harness/state"
  local saved_nullglob; saved_nullglob="$(shopt -p nullglob)"
  shopt -s nullglob
  local asks incidents removals
  asks=("${state}/pending-asks"/*.json)
  incidents=("${state}/incidents"/*.json)
  removals=("${state}/removal-requests"/*.json)
  eval "$saved_nullglob"
  local n_ask=${#asks[@]} n_inc=${#incidents[@]} n_rm=${#removals[@]}
  local total=$(( n_ask + n_inc + n_rm ))

  # lead pane: workers.list 의 5번째 필드 == lead (대소문자 무관).
  local lead_pane=""
  if [ -f "${state}/workers.list" ]; then
    lead_pane="$(awk 'tolower($5)=="lead"{print $2; exit}' "${state}/workers.list")"
  fi

  local status
  if [ "$total" -eq 0 ]; then
    status=""
  else
    status="❗ ${total} pending: ${n_ask} ask / ${n_inc} inc / ${n_rm} rm"
  fi

  if [ "${NOTIFY_DRY_RUN:-0}" = "1" ]; then
    echo "lead_pane=${lead_pane} status=[${status}]"
    return 0
  fi
  [ -n "$lead_pane" ] || return 0
  tmux set-option -t "$lead_pane" status-right "$status" 2>/dev/null || true
}
