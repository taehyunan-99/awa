#!/usr/bin/env bash
# 공통 함수/상수. 각 bin 스크립트가 source 한다.
# 직접 실행용 아님.

# 이 파일(bin/lib.sh) 기준으로 repo 루트 계산
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$_LIB_DIR/.." && pwd)"
WORKSPACE="$REPO_ROOT/workspace"
SESSION_DEFAULT="agents"

# SESSION 결정 단일화. 우선순위: SESSION_OVERRIDE > PROFILE_SESSION > SESSION_DEFAULT.
# dispatch.sh/wait-worker.sh/team-up.sh 가 모두 이 함수로 세션명을 얻어 불일치 제거(이슈 2).
resolve_session() {
  printf '%s' "${SESSION_OVERRIDE:-${PROFILE_SESSION:-${SESSION:-$SESSION_DEFAULT}}}"
}

# 윈도우·페인 인덱스 → tmux target. 세션명은 resolve_session().
# 2윈도우(team=0, review=1) 도입으로 window 고정 불가 → window 인자화(이슈 1·3).
target_in() {
  local win="$1" pane="$2"
  printf '%s:%s.%s' "$(resolve_session)" "$win" "$pane"
}

# 하위호환: 기존 호출부(window 0 가정)는 그대로. 내부적으로 target_in 위임.
target_of() {
  target_in 0 "$1"
}

# 세션 로컬로 인덱스 규약 고정. 전역 ~/.tmux.conf 설정에 비의존.
# 인자: 세션명. window base-index=0, pane-base-index=1 강제.
fix_session_indexing() {
  local s="$1"
  tmux set-option -t "$s" base-index 0 2>/dev/null || true
  tmux set-option -t "$s" pane-base-index 1 2>/dev/null || true
  # 이미 만들어진 윈도우/페인에도 즉시 반영되도록 재정렬
  tmux move-window -r -s "$s" 2>/dev/null || true
}

# 세션 로컬로 pane title 자동 리네임 비활성화. 전역 ~/.tmux.conf 불변.
# spec §6: dispatch/wait-worker 가 pane title=워커명으로 워커를 조회하므로,
# 워커 셸의 OSC title escape 가 select-pane -T 로 지정한 title 을
# 덮어쓰지 못하도록 세션 로컬로 고정한다.
#
# tmux 3.6a 실측 + man tmux 근거:
#   - allow-rename  : \ek..\e\\ (window-name) 전용 — pane_title 에 무력
#   - allow-set-title: \e]0;..\007 / \e]2;..\007 (pane title) 를 차단 ← 핵심
# 따라서 pane_title 보존의 결정타는 allow-set-title off 이다.
# allow-rename/automatic-rename off 도 세션 로컬·무해하므로 함께 고정한다
# (window-name 까지 호스트명으로 흔들리지 않도록 방어).
fix_session_titles() {
  local s="$1"
  tmux set-option -t "$s" allow-set-title off 2>/dev/null || true
  tmux set-option -t "$s" allow-rename off 2>/dev/null || true
  tmux set-option -t "$s" automatic-rename off 2>/dev/null || true
}

# 워커 이름 → 부트스트랩 합본 파일 경로
boot_file() {
  local worker="$1"
  printf '%s/.boot/%s.md' "$WORKSPACE" "$worker"
}

# 세션 존재 여부. 존재하면 0, 아니면 비-0.
session_exists() {
  local s="${1:-$SESSION_DEFAULT}"
  tmux has-session -t "$s" 2>/dev/null
}

# glob 경로 매칭. bash [[ == ]] 는 ** 재귀를 지원 안 함 → 정규식 변환(spec §5.1, 이슈 8).
#   **  → .*           (디렉터리 경계 넘는 재귀)
#   *   → [^/]*         (단일 세그먼트, / 안 넘음)
#   .   → \.            (literal)
# 전체 앵커(^...$)로 부분일치(authx vs auth) 차단.
# 반환: 매치 0, 불일치 1.
scope_match() {
  local path="$1" pat="$2" re=""
  local i ch
  for (( i=0; i<${#pat}; i++ )); do
    ch="${pat:i:1}"
    case "$ch" in
      '*')
        if [ "${pat:i+1:1}" = '*' ]; then re+='.*'; i=$((i+1)); else re+='[^/]*'; fi ;;
      '.') re+='\.' ;;
      '/') re+='/' ;;
      *) re+="$ch" ;;
    esac
  done
  [[ "$path" =~ ^${re}$ ]]
}

# 리뷰 커서 (spec §5.7). claude 무상태 보완 — 리뷰어가 호출해 증분·멱등.
_cursor_file() { printf '%s/.review-cursor.%s' "${WORKSPACE}" "$1"; }

cursor_read() {  # $1=reviewer → 현재 커서(없으면 0)
  local f; f="$(_cursor_file "$1")"
  if [ -f "$f" ]; then cat "$f"; else echo 0; fi
}

cursor_new_lines() {  # $1=reviewer $2=events.log → 커서 이후 줄 출력 (커서 불변)
  local n; n="$(cursor_read "$1")"
  tail -n +"$((n + 1))" "$2" 2>/dev/null || true
}

cursor_commit() {  # $1=reviewer $2=새 커서값
  printf '%s' "$2" > "$(_cursor_file "$1")"
}

# 메인 상태 (spec §5.8, B-4). key=value 평문(파싱 단순·셸 친화). claude 무상태 보완.
_state_file() { printf '%s/.harness-state' "${WORKSPACE}"; }

state_get() {  # $1=key → value (없으면 빈문자열)
  local f; f="$(_state_file)"
  [ -f "$f" ] || return 0
  local line; line="$(grep -m1 "^$1=" "$f" 2>/dev/null || true)"
  printf '%s' "${line#*=}"
}

state_set() {  # $1=key $2=value (있으면 교체, 없으면 추가)
  local f key val
  f="$(_state_file)"; key="$1"; val="$2"
  touch "$f"
  if grep -q "^$key=" "$f" 2>/dev/null; then
    grep -v "^$key=" "$f" > "$f.tmp" || true; mv "$f.tmp" "$f"
  fi
  printf '%s=%s\n' "$key" "$val" >> "$f"
}

# events.log 파싱 (spec §5.2). 탭 5필드: ts worker task action path.
event_field() {  # $1=line $2=fieldno(1-5)
  printf '%s' "$1" | awk -F'\t' -v n="$2" '{print $n}'
}

event_valid() {  # $1=line → 정확히 5필드면 0
  local nf; nf="$(printf '%s' "$1" | awk -F'\t' '{print NF}')"
  [ "$nf" = "5" ]
}

events_valid_count() {  # $1=file → valid 라인 수
  local c=0 line
  while IFS= read -r line; do
    event_valid "$line" && c=$((c + 1))
  done < "$1"
  printf '%s' "$c"
}

# 디바운스 (spec §5.5): 처리 범위 내 유니크 (worker,path). valid 라인만.
debounce_pairs() {  # $1=file → "worker\tpath" 유니크
  local line w p
  while IFS= read -r line; do
    event_valid "$line" || continue
    w="$(event_field "$line" 2)"; p="$(event_field "$line" 5)"
    printf '%s\t%s\n' "$w" "$p"
  done < "$1" | awk '!seen[$0]++'
}

# 리뷰 종합 (spec §5.4·§6): review/<worker>-<id>.*.md 중 하나라도
# VIOLATION 이면 VIOLATION, 전부 OK 면 OK, 파일 없으면 PENDING.
review_verdict() {  # $1=review디렉터리 $2=worker $3=id
  local dir="$1" w="$2" id="$3" f found=0 v
  for f in "$dir/$w-$id."*.md; do
    [ -f "$f" ] || continue
    found=1
    v="$(grep -m1 '^verdict:' "$f" | awk '{print $2}')"
    if [ "$v" = "VIOLATION" ]; then printf 'VIOLATION'; return 0; fi
  done
  if [ "$found" = "1" ]; then printf 'OK'; else printf 'PENDING'; fi
}

# 프롬프트 안전 주입: 텍스트(리터럴)와 Enter 분리. spec §4.1.
send_prompt() {
  local target="$1" text="$2"
  tmux send-keys -t "$target" -l "$text"
  tmux send-keys -t "$target" Enter
}
