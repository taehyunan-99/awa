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

  # pending-asks 는 처리 시 파일 삭제 → 존재 자체가 미처리. incident/removal 은 파일 잔존 +
  # notified/status 필드로 처리 여부 표시 (spec §5.4) → 미처리만 카운트.
  local n_ask=${#asks[@]} n_inc=0 n_rm=0
  local f
  # ${arr[@]:-} : bash 3.2 + set -u 에서 빈 배열 참조가 unbound 로 터지지 않도록 가드.
  for f in "${incidents[@]:-}"; do
    [ -f "$f" ] || continue
    [ "$(jq -r '.notified // false' "$f" 2>/dev/null)" = "false" ] && n_inc=$(( n_inc + 1 ))
  done
  for f in "${removals[@]:-}"; do
    [ -f "$f" ] || continue
    [ "$(jq -r '.status // "pending"' "$f" 2>/dev/null)" = "pending" ] && n_rm=$(( n_rm + 1 ))
  done
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
