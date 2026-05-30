#!/usr/bin/env bash
set -uo pipefail
_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_DIR/lib.sh"

# 11차 리뷰 [CRIT-32]: 환경변수 override 지원 — 테스트가 격리된 세션명 사용 가능.
# 본 운영은 변경 없음 (env 미설정 시 _DASHBOARD 그대로).
DASH="${AWA_DASH_NAME:-_DASHBOARD}"

# === 헬퍼 함수 (pane grid 모델) ==========================================

# 세션/윈도우 옵션 적용 — _DASHBOARD 의 base-index + 모든 grid 윈도우에 border.
# (구 dash_init_session + _dash_apply_window_opts 흡수.)
dash_apply_session_opts() {
  tmux set-option -t "$DASH" base-index 0 2>/dev/null || true
  tmux set-option -t "$DASH" pane-base-index 1 2>/dev/null || true
  local w
  while IFS= read -r w; do
    [ -n "$w" ] || continue
    tmux set-option -w -t "${DASH}:$w" allow-set-title off 2>/dev/null || true
    tmux set-option -w -t "${DASH}:$w" allow-rename off 2>/dev/null || true
    tmux set-option -w -t "${DASH}:$w" automatic-rename off 2>/dev/null || true
    tmux set-option -w -t "${DASH}:$w" pane-border-status top 2>/dev/null || true
    tmux set-option -w -t "${DASH}:$w" pane-border-format \
      ' [ #{@awa-project} ] #{pane_title} ' 2>/dev/null || true
  done < <(tmux list-windows -t "$DASH" -F '#W' 2>/dev/null)
}

# 원세션(또는 임의 세션)에서 @awa-role=role 인 첫 pane_id 출력 (없으면 빈 문자열).
dash_find_role_pane() {
  local session="$1" role="$2"
  tmux list-panes -s -t "$session" -F '#{@awa-role} #{pane_id}' 2>/dev/null \
    | awk -v r="$role" '$1==r{print $2; exit}'
}

# 현재 _DASHBOARD grid 의 프로젝트들을 <session>\t<lead_pane>\t<pm_pane> 로 출력.
# grid 안 pane 은 @awa-project(세션명) + @awa-role 로 식별. 프로젝트 순서 = 첫 등장 순.
#
# ⚠️ tmux -F format 은 \t 를 literal 백슬래시+t 로 출력한다(실측: od -c 확인). awk -F'\t'
# 와 불일치하므로 구분자로 쓰면 안 됨. → tmux 는 공백 구분으로 받고(세션명/역할/pane_id 는
# 공백 없음 — AWA 세션은 awa-*/_DASHBOARD), 출력은 printf 로 탭 생성(render stdin 과 정합).
dash_collect_current() {
  tmux has-session -t "$DASH" 2>/dev/null || return 0
  # 모든 grid pane 을 (project role pane_id) 공백 3필드로 덤프 → awk 로 프로젝트별 lead/pm 병합.
  # 출력은 탭 3필드(dash_render stdin 형식). @awa-project 빈 값(빈 골격 잔재) 은 제외.
  tmux list-panes -s -t "$DASH" -F '#{@awa-project} #{@awa-role} #{pane_id}' 2>/dev/null \
    | awk '
        NF>=3 && $1!=""{
          if (!(($1) in seen)) { order[n++]=$1; seen[$1]=1 }
          if ($2=="lead") lead[$1]=$3
          if ($2=="pm")   pm[$1]=$3
        }
        END{ for(i=0;i<n;i++){ p=order[i]; printf "%s\t%s\t%s\n", p, lead[p], pm[p] } }'
}

# 지정 윈도우에 rows 행 × 2열 빈 골격 생성. 각 행의 <lead_slot>\t<pm_slot> pane_id 를 rows 줄 출력.
# 검증된 시퀀스: 행 세로 스택(직전 pane 명시 타깃) → even-vertical → 각 행 좌우 split.
dash_make_skeleton() {
  local win="$1" rows="$2"
  local first prev row_ids=() i lpid rpid
  first="$(tmux list-panes -t "${DASH}:${win}" -F '#{pane_id}' | head -1)"
  row_ids+=("$first"); prev="$first"
  i=1
  while [ "$i" -lt "$rows" ]; do
    prev="$(tmux split-window -v -t "$prev" -d -P -F '#{pane_id}' 2>/dev/null)"
    row_ids+=("$prev")
    i=$((i+1))
  done
  tmux select-layout -t "${DASH}:${win}" even-vertical 2>/dev/null || true
  for lpid in "${row_ids[@]}"; do
    rpid="$(tmux split-window -h -t "$lpid" -d -P -F '#{pane_id}' 2>/dev/null)"
    printf '%s\t%s\n' "$lpid" "$rpid"
  done
}

# 전체 grid 재구성. stdin: <session>\t<lead_pane>\t<pm_pane> 행들 (프로젝트 순서대로).
# 프로젝트 0개 → _DASHBOARD kill. 3개씩 묶어 grid-1, grid-2 ... 윈도우.
#
# ⚠️ 핵심 안전순서: kill-window 는 내부 pane 을 죽인다(실측). 입력 leads/pms 가
# 기존 grid 윈도우에 살아있을 수 있으므로(add/재패킹), 기존 윈도우를 먼저 죽이면 안 된다.
# → 새 grid 를 **임시 이름(_new-N)** 으로 만들어 swap 으로 실제 pane 을 끌어온 뒤,
#   비게 된 기존 grid-* 윈도우를 일괄 kill, 마지막에 _new-N → grid-N rename.
dash_render() {
  local -a sess=() leads=() pms=()
  local s l p
  while IFS=$'\t' read -r s l p || [ -n "$s" ]; do
    [ -n "$s" ] || continue
    sess+=("$s"); leads+=("$l"); pms+=("$p")
  done
  local total="${#sess[@]}"
  if [ "$total" -eq 0 ]; then
    tmux kill-session -t "$DASH" 2>/dev/null || true
    return 0
  fi
  tmux has-session -t "$DASH" 2>/dev/null || tmux new-session -d -s "$DASH" -n _placeholder -x 200 -y 50

  # per-page 처리. 페이지 = 최대 3 프로젝트. 임시 이름 _new-N 으로 빌드.
  local idx=0 page=1
  while [ "$idx" -lt "$total" ]; do
    local rows=$(( total - idx )); [ "$rows" -gt 3 ] && rows=3
    local newwin="_new-${page}"
    tmux kill-window -t "${DASH}:${newwin}" 2>/dev/null || true   # 직전 실패 잔재 정리
    tmux new-window -d -t "$DASH" -n "$newwin" 2>/dev/null || true
    # 골격 생성 → 슬롯 목록 수집.
    local -a slot_l=() slot_r=()
    local sl sr
    while IFS=$'\t' read -r sl sr; do
      slot_l+=("$sl"); slot_r+=("$sr")
    done < <(dash_make_skeleton "$newwin" "$rows")
    # swap: 각 프로젝트 lead→좌슬롯, pm→우슬롯. (실제 pane 이 _new-N 으로 들어오고
    # 빈 골격 pane 이 원위치로 — 원위치가 기존 grid-* 면 그 윈도우는 곧 kill 됨.)
    local r=0
    while [ "$r" -lt "$rows" ]; do
      local gi=$(( idx + r ))
      # lead/pm pane_id 결손(한쪽만 있는 깨진 잔재 등) → 빈 swap 으로 골격 노출 방지. 경고 후 skip.
      if [ -z "${leads[$gi]}" ] || [ -z "${pms[$gi]}" ]; then
        echo "경고: ${sess[$gi]} 의 lead/pm pane 결손 — 해당 행 skip" >&2
        r=$((r+1)); continue
      fi
      tmux swap-pane -s "${leads[$gi]}" -t "${slot_l[$r]}" 2>/dev/null || true
      tmux swap-pane -s "${pms[$gi]}"   -t "${slot_r[$r]}" 2>/dev/null || true
      # @awa-role/@awa-project 재적용 (양쪽 pane — 단일 장애점 회피). swap 후 실제 pane = leads/pms.
      tmux set-option -p -t "${leads[$gi]}" @awa-role lead 2>/dev/null || true
      tmux set-option -p -t "${pms[$gi]}"   @awa-role pm   2>/dev/null || true
      tmux set-option -p -t "${leads[$gi]}" @awa-project "${sess[$gi]}" 2>/dev/null || true
      tmux set-option -p -t "${pms[$gi]}"   @awa-project "${sess[$gi]}" 2>/dev/null || true
      r=$((r+1))
    done
    # ⚠️ swap 후 select-layout 호출 금지 — even-vertical 은 좌우 쌍을 무시하고 전체 pane 을
    # 세로 1열로 재배치해 grid 를 파괴한다(실측). 행 균등은 골격(dash_make_skeleton)의
    # even-vertical 로 이미 끝났고 swap 은 위치를 보존하므로 여기서 재적용 불필요.
    idx=$(( idx + rows ))
    page=$(( page + 1 ))
  done

  # 이제 실제 pane 은 모두 _new-* 로 이동 완료. 기존 grid-*/_placeholder 는 빈 골격뿐 → 일괄 kill.
  local w
  while IFS= read -r w; do
    case "$w" in
      grid-*|_placeholder) tmux kill-window -t "${DASH}:$w" 2>/dev/null || true ;;
    esac
  done < <(tmux list-windows -t "$DASH" -F '#W' 2>/dev/null)
  # _new-N → grid-N rename.
  while IFS= read -r w; do
    case "$w" in
      _new-*) tmux rename-window -t "${DASH}:$w" "grid-${w#_new-}" 2>/dev/null || true ;;
    esac
  done < <(tmux list-windows -t "$DASH" -F '#W' 2>/dev/null)
  dash_apply_session_opts
}

# === Actions =============================================================

# 인자 세션 목록 → 검증된 (session\tlead\tpm) 행으로. 자기참조 거부 + 중복 dedup + 스킵.
# stdout: 유효 프로젝트 행. stderr: 경고.
_dash_resolve_sessions() {
  local -a raw=( "$@" ) sessions=()
  local _u s l p
  # 순서보존 dedup (bash 3.2 — awk).
  while IFS= read -r _u; do
    [ -n "$_u" ] && sessions+=("$_u")
  done < <(printf '%s\n' "${raw[@]}" | awk '!seen[$0]++')
  for s in "${sessions[@]}"; do
    if [ "$s" = "$DASH" ]; then
      echo "오류: $DASH 자신을 대상으로 지정할 수 없음" >&2
      continue
    fi
    if ! tmux has-session -t "$s" 2>/dev/null; then
      echo "경고: 원세션 $s 부재 — 스킵" >&2
      continue
    fi
    l="$(dash_find_role_pane "$s" lead)"
    p="$(dash_find_role_pane "$s" pm)"
    if [ -z "$l" ] || [ -z "$p" ]; then
      echo "경고: $s 에서 lead/pm pane(@awa-role) 미발견 — 스킵" >&2
      continue
    fi
    printf '%s\t%s\t%s\n' "$s" "$l" "$p"
  done
}

action_merge() {
  [ "$#" -ge 1 ] || { echo "오류: merge 인자 필요" >&2; return 1; }
  if tmux has-session -t "$DASH" 2>/dev/null; then
    echo "오류: $DASH 이미 존재. Add 사용." >&2
    return 1
  fi
  local rows; rows="$(_dash_resolve_sessions "$@")"
  if [ -z "$rows" ]; then
    echo "오류: merge 가능한 세션이 없음 (모든 인자 거부됨)" >&2
    return 1
  fi
  printf '%s\n' "$rows" | dash_render
  echo "Merged $DASH."
}

action_add() {
  local session="${1:-}"
  [ -n "$session" ] || { echo "오류: add 인자 필요" >&2; return 1; }
  if ! tmux has-session -t "$DASH" 2>/dev/null; then
    echo "오류: $DASH 부재. 신규 생성은 (5) Merge 사용." >&2
    return 1
  fi
  # 현재 프로젝트 + 새 프로젝트 합쳐 전체 재구성.
  local cur new
  cur="$(dash_collect_current)"
  new="$(_dash_resolve_sessions "$session")"
  if [ -z "$new" ]; then
    echo "오류: add 대상이 거부됨" >&2
    return 1
  fi
  # 중복 방지: 이미 grid 에 있는 세션이면 cur 만으로 충분 (new 의 세션명이 cur 에 있으면 제외).
  { [ -n "$cur" ] && printf '%s\n' "$cur"; printf '%s\n' "$new"; } \
    | awk -F'\t' '!seen[$1]++' | dash_render
  echo "Added $session to $DASH."
}

# 한 프로젝트의 lead/pm pane 을 원세션으로 복원. 인자: 프로젝트(세션)명.
dash_detach_one() {
  local proj="$1"
  # 2번째 인자 no_recreate=1 이면 원세션 부재 시 대화형 read 없이 조용히 스킵.
  # 자동 경로(action_split, dash_post_check_last)가 의도치 않게 프롬프트로 멈추는 것 방지.
  local no_recreate="${2:-}"
  if [ "$proj" = "$DASH" ]; then
    echo "오류: $DASH 자신은 detach 대상 아님" >&2; return 1
  fi
  # grid 에서 해당 프로젝트 lead/pm pane 찾기.
  local row lead pm
  row="$(dash_collect_current | awk -F'\t' -v p="$proj" '$1==p{print; exit}')"
  if [ -z "$row" ]; then
    echo "경고: $proj 가 grid 에 없음 — 스킵" >&2; return 1
  fi
  lead="$(printf '%s' "$row" | cut -f2)"
  pm="$(printf '%s' "$row" | cut -f3)"
  # 원세션 부재 → 사용자 확인 후 재생성 (자동 경로면 프롬프트 없이 스킵).
  if ! tmux has-session -t "$proj" 2>/dev/null; then
    echo "경고: 원세션 $proj 부재." >&2
    if [ "$no_recreate" = "1" ]; then
      echo "경고: 자동 정리 경로 — $proj 재생성 생략(스킵)." >&2
      return 1
    fi
    read -r -p "Create session $proj and restore? (y/n): " ans
    [ "$ans" = "y" ] || return 1
    tmux new-session -d -s "$proj" -n team
    fix_session_indexing "$proj" 2>/dev/null || true
    fix_session_titles "$proj" 2>/dev/null || true
    # 세션옵션 @awa-project(경로)/@awa-project-name(basename) 복원 — awa-main.sh·
    # awa-down-menu.sh 가 이 옵션으로 경로를 조회하며, 없으면 down-menu 가 exit 1 로 중단된다.
    # basename 은 세션명(awa-<basename>) 규칙에서 도출. 경로는 grid 에 정보가 없어 사용자 입력.
    local _restore_path _restore_name
    _restore_name="${proj#awa-}"   # awa-<basename> → basename (prefix 없으면 원형 유지)
    read -r -p "PROJECT_ROOT path for $proj (빈 입력=down-menu 메타 미복원): " _restore_path
    if [ -n "$_restore_path" ]; then
      tmux set-option -t "$proj" @awa-project "$_restore_path" 2>/dev/null || true
      tmux set-option -t "$proj" @awa-project-name "$(basename "$_restore_path")" 2>/dev/null || true
    else
      # 경로 미입력 — basename 만이라도 복원(pane-border-format 표시용). down-menu 경로 조회는 불가.
      tmux set-option -t "$proj" @awa-project-name "$_restore_name" 2>/dev/null || true
      echo "경고: $proj 경로 미입력 — @awa-project(경로) 미설정. /awa down 메뉴에서 이 세션은 제외될 수 있음." >&2
    fi
  fi
  # 원세션 team 윈도우에 빈 슬롯(lead|pm) 2개 만들고 swap 으로 복원.
  if ! tmux list-windows -t "$proj" -F '#W' 2>/dev/null | grep -qx 'team'; then
    tmux new-window -d -t "$proj" -n team 2>/dev/null || true
  fi
  local slot_l slot_r
  slot_l="$(tmux list-panes -t "${proj}:team" -F '#{pane_id}' | head -1)"
  slot_r="$(tmux split-window -h -t "$slot_l" -d -P -F '#{pane_id}' 2>/dev/null)"
  tmux swap-pane -s "$lead" -t "$slot_l" 2>/dev/null || true
  tmux swap-pane -s "$pm"   -t "$slot_r" 2>/dev/null || true
  tmux set-option -p -t "$lead" @awa-role lead 2>/dev/null || true
  tmux set-option -p -t "$pm"   @awa-role pm   2>/dev/null || true
  tmux select-pane -t "$lead" -T "LEAD" 2>/dev/null || true
  tmux select-pane -t "$pm"   -T "PM"   2>/dev/null || true
  tmux select-layout -t "${proj}:team" even-horizontal 2>/dev/null || true
  fix_session_titles "$proj" 2>/dev/null || true
  return 0
}

# detach 후 남은 프로젝트 수에 따라 재구성/정리.
dash_post_check_last() {
  tmux has-session -t "$DASH" 2>/dev/null || return 0
  local rows; rows="$(dash_collect_current)"
  local count=0
  [ -n "$rows" ] && count="$(printf '%s\n' "$rows" | grep -c '.')"
  if [ "$count" -le 1 ]; then
    # 0 또는 1개 남음 → 마지막 1개도 detach 후 _DASHBOARD kill.
    if [ "$count" -eq 1 ]; then
      local last; last="$(printf '%s\n' "$rows" | head -1 | cut -f1)"
      echo "Last project remaining — auto detach + kill $DASH."
      dash_detach_one "$last" 1 || true
    fi
    tmux kill-session -t "$DASH" 2>/dev/null || true
  else
    # 2개 이상 남음 → 재패킹 (전체 재구성).
    printf '%s\n' "$rows" | dash_render
  fi
}

action_detach() {
  local -a projs=( "$@" )
  [ "${#projs[@]}" -ge 1 ] || { echo "오류: detach 인자(프로젝트명) 필요" >&2; return 1; }
  if ! tmux has-session -t "$DASH" 2>/dev/null; then
    echo "오류: $DASH 부재." >&2; return 1
  fi
  local p
  for p in "${projs[@]}"; do
    dash_detach_one "$p" || true
  done
  dash_post_check_last
}

action_split() {
  if ! tmux has-session -t "$DASH" 2>/dev/null; then
    echo "오류: $DASH 부재." >&2; return 1
  fi
  local rows p
  rows="$(dash_collect_current)"
  while IFS=$'\t' read -r p _l _p; do
    [ -n "$p" ] || continue
    dash_detach_one "$p" 1 || true
  done < <(printf '%s\n' "$rows")
  tmux kill-session -t "$DASH" 2>/dev/null || true
  echo "Split $DASH."
}

action_kill() {
  local -a projs=( "$@" )
  [ "${#projs[@]}" -ge 1 ] || { echo "오류: kill 인자(프로젝트명) 필요" >&2; return 1; }
  if ! tmux has-session -t "$DASH" 2>/dev/null; then
    echo "오류: $DASH 부재." >&2; return 1
  fi
  local p proj_path
  for p in "${projs[@]}"; do
    # 세션옵션 @awa-project(=PROJECT_ROOT 경로, awa-up L354)를 detach 전에 캡처 —
    # detach 가 원세션을 재생성하면 이 옵션이 사라지므로 선행 캡처가 필수.
    proj_path="$(tmux show-options -t "$p" -v @awa-project 2>/dev/null || echo "")"
    dash_detach_one "$p" || continue
    if [ -n "$proj_path" ] && [ -d "$proj_path" ]; then
      bash "$_DIR/awa-down.sh" --project "$proj_path" || true
    else
      echo "경고: $p 의 @awa-project 경로($proj_path) 부재/무효 — down 생략(detach 만)." >&2
    fi
  done
  dash_post_check_last
}

# === main ================================================================

action="${1:-}"
shift || true
case "$action" in
  merge)  action_merge "$@" ;;
  add)    action_add "$@" ;;
  detach) action_detach "$@" ;;
  split)  action_split ;;
  kill)   action_kill "$@" ;;
  ""|menu) echo "Usage: $0 {merge <s1> [s2...] | add <s> | detach <proj...> | split | kill <proj...>}" ;;
  *) echo "오류: 알 수 없는 action '$action'" >&2; exit 1 ;;
esac
