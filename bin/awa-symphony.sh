#!/usr/bin/env bash
set -uo pipefail
_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_DIR/lib.sh"

# 11차 리뷰 [CRIT-32]: 환경변수 override 지원 — 테스트가 격리된 세션명 사용 가능.
# 본 운영은 변경 없음 (env 미설정 시 _SYMPHONY 그대로).
SYM="${AGPN_SYM_NAME:-_SYMPHONY}"

# === 헬퍼 함수 ==========================================================

sym_safe_check_origin() {
  # 원세션에 team 외 window 가 있어야 move-window 시 자동 kill 회피 (결함 8)
  local s="$1"
  local wc
  wc=$(tmux list-windows -t "$s" -F '#W' 2>/dev/null | wc -l | tr -d ' ')
  if [ "${wc:-0}" -lt 2 ]; then
    echo "오류: $s 에 team 외 window 가 없음 — move 시 원세션 사라짐. 거부." >&2
    return 1
  fi
  return 0
}

_sym_apply_window_opts() {
  # window 옵션을 _SYMPHONY 의 *모든* 윈도우에 박기.
  # tmux 3.x: allow-set-title/allow-rename/automatic-rename/pane-border-status/pane-border-format
  # 은 모두 window 옵션이라 `-w -t <session>:<window>` 단위로 적용해야 silent fail 회피.
  local w
  while IFS= read -r w; do
    [ -n "$w" ] || continue
    tmux set-option -w -t "$SYM:$w" allow-set-title off 2>/dev/null || true
    tmux set-option -w -t "$SYM:$w" allow-rename off 2>/dev/null || true
    tmux set-option -w -t "$SYM:$w" automatic-rename off 2>/dev/null || true
    tmux set-option -w -t "$SYM:$w" pane-border-status top 2>/dev/null || true
    tmux set-option -w -t "$SYM:$w" pane-border-format ' [ #{window_name} ] #{pane_title} ' 2>/dev/null || true
  done < <(tmux list-windows -t "$SYM" -F '#W' 2>/dev/null)
}

sym_init_session() {
  # _SYMPHONY 옵션 세팅 + 검증 (결함 9, 14)
  # session 옵션 (base-index, pane-base-index)
  tmux set-option -t "$SYM" base-index 0 2>/dev/null || true
  tmux set-option -t "$SYM" pane-base-index 1 2>/dev/null || true
  # window 옵션은 모든 윈도우에 단위로 적용 (-t <session> 만으론 silent fail — probe 실측)
  _sym_apply_window_opts
  # 검증 — show-options -t <session> -v 는 *활성 윈도우* 의 window option 을 조회 (probe 실측).
  # _sym_apply_window_opts 가 모든 윈도우에 박았으니 활성 윈도우도 포함.
  local v
  v="$(tmux show-options -t "$SYM" -v allow-set-title 2>/dev/null)"
  [ "$v" = "off" ] || { echo "오류: $SYM allow-set-title 적용 실패 (got '$v')" >&2; return 1; }
  v="$(tmux show-options -t "$SYM" -v pane-border-status 2>/dev/null)"
  [ "$v" = "top" ] || { echo "오류: $SYM pane-border-status 적용 실패 (got '$v')" >&2; return 1; }
  return 0
}

_sym_set_window_label() {
  # session 의 team window 가 _SYMPHONY 에 이동된 뒤, 프로젝트별 라벨 적용 (결함 15).
  # _sym_apply_window_opts 가 default format 으로 덮은 후 호출되어야 라벨이 유지됨.
  local session="$1"
  local proj_name
  proj_name="$(basename "$(tmux show-options -t "$session" -v @awa-project 2>/dev/null || echo "$session")" 2>/dev/null || echo "$session")"
  tmux set-option -w -t "$SYM:$session-team" pane-border-format \
    " [ $proj_name ] #{pane_title} " 2>/dev/null || true
}

sym_move_in() {
  # 원세션의 team window 를 _SYMPHONY 로 이동 + rename + window 단위 라벨
  local session="$1"
  # 충돌 검사
  if tmux list-windows -t "$SYM" -F '#W' 2>/dev/null | grep -qx 'team'; then
    echo "오류: $SYM 에 'team' window 잔존. 직전 Add rename 실패 가능. abort." >&2
    return 1
  fi
  tmux move-window -s "$session:team" -t "$SYM:" 2>/dev/null || {
    echo "오류: move-window 실패 ($session:team → $SYM:)" >&2
    return 1
  }
  tmux rename-window -t "$SYM:team" "$session-team"
  # rename 검증
  if ! tmux list-windows -t "$SYM" -F '#W' 2>/dev/null | grep -qx "$session-team"; then
    echo "오류: rename-window 실패. $SYM 상태 점검 필요." >&2
    return 1
  fi
  # 새 window 에 옵션 + 프로젝트 라벨 적용 (결함 15).
  # 순서: 공통 window-opts (default pane-border-format) → 프로젝트 라벨 덮어쓰기.
  tmux set-option -w -t "$SYM:$session-team" allow-set-title off 2>/dev/null || true
  tmux set-option -w -t "$SYM:$session-team" allow-rename off 2>/dev/null || true
  tmux set-option -w -t "$SYM:$session-team" automatic-rename off 2>/dev/null || true
  tmux set-option -w -t "$SYM:$session-team" pane-border-status top 2>/dev/null || true
  _sym_set_window_label "$session"
  return 0
}

# === Actions =============================================================

action_compose() {
  # arg: space-separated session names (≥2 권고, 1개도 동작 — sym 부재일 때만)
  local -a raw=( "$@" )
  [ "${#raw[@]}" -ge 1 ] || { echo "오류: compose 인자 필요" >&2; return 1; }
  if tmux has-session -t "$SYM" 2>/dev/null; then
    echo "오류: $SYM 이미 존재. Add 사용." >&2
    return 1
  fi
  # 8차 리뷰 [MAJOR-18]: 중복 인자 제거 (SKILL 자동 후속에서 existing+새세션 중복 가능).
  # 순서 보존 dedup — bash 3.2 호환 (awk 사용).
  local -a sessions=()
  local _u
  while IFS= read -r _u; do
    [ -n "$_u" ] && sessions+=("$_u")
  done < <(printf '%s\n' "${raw[@]}" | awk '!seen[$0]++')
  # 8차 리뷰 [MAJOR-16]: 자기 참조 거부 — 발견 즉시 abort (전체 compose 무효)
  local s
  for s in "${sessions[@]}"; do
    if [ "$s" = "$SYM" ]; then
      echo "오류: $SYM 자신을 compose 대상으로 지정할 수 없음" >&2
      return 1
    fi
  done
  # 각 세션 별 존재·안전 검증은 per-session skip 정책 — 한 세션 실패가 전체를 막지 않음.
  # SKILL 자동 후속에서 한 프로젝트만 비정상이어도 나머지는 묶이도록 (테스트 S7 가정).
  local -a valid=()
  for s in "${sessions[@]}"; do
    if ! tmux has-session -t "$s" 2>/dev/null; then
      echo "경고: 원세션 $s 부재 — 스킵" >&2
      continue
    fi
    if ! sym_safe_check_origin "$s"; then
      # sym_safe_check_origin 이 이미 stderr 에 에러 메시지 출력
      continue
    fi
    valid+=("$s")
  done
  if [ "${#valid[@]}" -lt 1 ]; then
    echo "오류: compose 가능한 세션이 없음 (모든 인자 거부됨)" >&2
    return 1
  fi
  tmux new-session -d -s "$SYM" -n "_placeholder"
  sym_init_session || { tmux kill-session -t "$SYM" 2>/dev/null; return 1; }
  local first=1
  for s in "${valid[@]}"; do
    sym_move_in "$s" || { tmux kill-session -t "$SYM" 2>/dev/null; return 1; }
    if [ "$first" = "1" ]; then
      tmux kill-window -t "$SYM:_placeholder" 2>/dev/null || true
      first=0
    fi
  done
  echo "Composed $SYM with: ${valid[*]}"
}

action_add() {
  local session="${1:-}"
  [ -n "$session" ] || { echo "오류: add 인자 필요" >&2; return 1; }
  # 8차 리뷰 [MAJOR-16]: add 인자가 _SYMPHONY 자체면 자기 참조 — 거부
  if [ "$session" = "$SYM" ]; then
    echo "오류: $SYM 자신을 add 할 수 없음" >&2
    return 1
  fi
  if ! tmux has-session -t "$SYM" 2>/dev/null; then
    echo "오류: $SYM 부재. 신규 생성은 (5) Compose 사용." >&2
    return 1
  fi
  if ! tmux has-session -t "$session" 2>/dev/null; then
    echo "오류: 원세션 $session 부재" >&2
    return 1
  fi
  # 7차 리뷰 [MAJOR-11]: 사용자가 _SYMPHONY 를 외부에서 만들어둔 경우 옵션 미적용 가능
  # → 멱등 호출로 항상 보장 (set-option 이라 부작용 없음)
  sym_init_session || return 1
  sym_safe_check_origin "$session" || return 1
  sym_move_in "$session" || return 1
  echo "Added $session to $SYM"
}

sym_detach_one() {
  # _SYMPHONY 의 한 *-team window 를 원세션으로 복원
  local sym_win="$1"
  # 8차 리뷰 [MAJOR-19]: window 이름이 '-team' 으로 안 끝나면 패턴 위반 — 거부
  case "$sym_win" in
    *-team) ;;
    *) echo "오류: detach 대상 '$sym_win' 은 *-team 패턴 아님" >&2; return 1 ;;
  esac
  local orig_session="${sym_win%-team}"
  # 8차 리뷰 [MAJOR-19]: orig 이 _SYMPHONY 자체면 자기 참조 — 거부
  if [ "$orig_session" = "$SYM" ]; then
    echo "오류: $SYM 자신은 detach 대상 아님" >&2
    return 1
  fi
  if ! tmux has-session -t "$orig_session" 2>/dev/null; then
    echo "경고: 원세션 $orig_session 부재." >&2
    read -r -p "Create session $orig_session and restore? (y/n): " ans
    [ "$ans" = "y" ] || return 1
    tmux new-session -d -s "$orig_session" -n _placeholder
    # 9차 리뷰 [CRIT-20]: 14차 fix (allow-set-title 윈도우 상속 부재) 적용 — lib.sh 단일 출처
    fix_session_indexing "$orig_session"
    fix_session_titles "$orig_session"
  fi
  if tmux list-windows -t "$orig_session" -F '#W' 2>/dev/null | grep -qx 'team'; then
    echo "오류: $orig_session 에 이미 'team' window 존재. Detach 거부 (충돌 위험)." >&2
    echo "  수동 해결: tmux rename-window -t $orig_session:team team-old" >&2
    return 1
  fi
  tmux rename-window -t "$SYM:$sym_win" "team" 2>/dev/null || {
    echo "오류: rename 실패 ($sym_win → team)" >&2
    return 1
  }
  tmux move-window -s "$SYM:team" -t "$orig_session:" 2>/dev/null || {
    echo "오류: move 실패 ($SYM:team → $orig_session)" >&2
    return 1
  }
  tmux kill-window -t "$orig_session:_placeholder" 2>/dev/null || true
  return 0
}

sym_post_check_last() {
  # _SYMPHONY 에 *-team window 가 1개만 남으면 자동 detach + kill
  if ! tmux has-session -t "$SYM" 2>/dev/null; then return 0; fi
  local remaining
  remaining=$(tmux list-windows -t "$SYM" -F '#W' 2>/dev/null | grep -E -- '-team$' || true)
  # 6차 리뷰 [CRIT-1]: grep -c + || echo 0 은 빈 입력 시 '0\n0' 멀티라인 생성 → 분기 미진입
  local count
  if [ -z "$remaining" ]; then count=0; else count=$(printf '%s\n' "$remaining" | wc -l | tr -d ' '); fi
  if [ "$count" = "1" ]; then
    echo "Last project remaining — auto detach + kill $SYM."
    sym_detach_one "$remaining" || return 1
    tmux kill-session -t "$SYM" 2>/dev/null || true
  elif [ "$count" = "0" ]; then
    # 잔여 0 → _SYMPHONY 자체 kill
    tmux kill-session -t "$SYM" 2>/dev/null || true
  fi
}

action_detach() {
  # arg: space-separated *-team window names
  local -a wins=( "$@" )
  [ "${#wins[@]}" -ge 1 ] || { echo "오류: detach 인자 필요" >&2; return 1; }
  if ! tmux has-session -t "$SYM" 2>/dev/null; then
    echo "오류: $SYM 부재." >&2
    return 1
  fi
  local w
  for w in "${wins[@]}"; do
    sym_detach_one "$w" || return 1
  done
  sym_post_check_last
}

action_disband() {
  if ! tmux has-session -t "$SYM" 2>/dev/null; then
    echo "오류: $SYM 부재." >&2
    return 1
  fi
  local wins
  wins=$(tmux list-windows -t "$SYM" -F '#W' 2>/dev/null | grep -E -- '-team$' || true)
  local w
  while IFS= read -r w; do
    [ -n "$w" ] || continue
    sym_detach_one "$w" || true   # 일부 실패해도 진행 — 최대한 복원
  done <<< "$wins"
  tmux kill-session -t "$SYM" 2>/dev/null || true
  echo "Disbanded $SYM."
}

action_kill() {
  # arg: *-team window names
  local -a wins=( "$@" )
  [ "${#wins[@]}" -ge 1 ] || { echo "오류: kill 인자 필요" >&2; return 1; }
  if ! tmux has-session -t "$SYM" 2>/dev/null; then
    echo "오류: $SYM 부재." >&2
    return 1
  fi
  local w orig proj
  for w in "${wins[@]}"; do
    orig="${w%-team}"
    sym_detach_one "$w" || continue
    proj=$(tmux show-options -t "$orig" -v @awa-project 2>/dev/null || echo "")
    if [ -n "$proj" ]; then
      bash "$_DIR/awa-down.sh" --project "$proj" || true
    fi
  done
  sym_post_check_last
}

# === main ================================================================

action="${1:-}"
shift || true
case "$action" in
  compose) action_compose "$@" ;;
  add) action_add "$@" ;;
  detach) action_detach "$@" ;;
  disband) action_disband ;;
  kill) action_kill "$@" ;;
  ""|menu) echo "Usage: $0 {compose <s1> [s2...] | add <s> | detach <w...> | disband | kill <w...>}" ;;
  *) echo "오류: 알 수 없는 action '$action'" >&2; exit 1 ;;
esac
