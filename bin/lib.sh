#!/usr/bin/env bash
# 공통 함수/상수. 각 bin 스크립트가 source 한다.
# 직접 실행용 아님.

# 이 파일(bin/lib.sh) 기준으로 하네스 루트 계산 (정의의 위치)
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_ROOT="$(cd "$_LIB_DIR/.." && pwd)"
SESSION_DEFAULT="agents"  # 폴백 안의 폴백 (자동명이 보통 이김)

# PROJECT_ROOT 도출: HARNESS_PROJECT(--project) > cwd 의 git toplevel > PWD.
# 워커 cwd·.agent-harness 위치·settings.json 위치의 기준 (작업 대상 위치).
resolve_project_root() {
  if [ -n "${HARNESS_PROJECT:-}" ]; then
    printf '%s' "$HARNESS_PROJECT"
    return
  fi
  local r
  r="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null)"
  if [ -n "$r" ]; then
    printf '%s' "$r"
  else
    echo "경고: '$PWD' 는 git repo 아님 — PWD 를 PROJECT_ROOT 로 사용 (--project 로 명시 가능)" >&2
    printf '%s' "$PWD"
  fi
}

PROJECT_ROOT="$(resolve_project_root)"
# git repo 여부 별도 캐싱 (HARNESS_PROJECT 우선 경로에서도 정확)
if git -C "$PROJECT_ROOT" rev-parse --show-toplevel >/dev/null 2>&1; then
  PROJECT_ROOT_IS_GIT=1
else
  PROJECT_ROOT_IS_GIT=0
fi

# 경로 정합성 검증 (E4·F1·F4): sed 구분자·셸 메타문자·quoting 실수 위험 회피.
# 허용: [A-Za-z0-9/._-]. 공백·빈 문자열 미허용(F4 보수).
# lib.sh 는 source 파일이라 exit 금지 → 변수로 결과 전달 (F1).
# 호출 스크립트는 source 후 `[ "$PROJECT_ROOT_VALID" = "1" ] || exit 1`.
#
# 함수로 추출 — PROJECT_ROOT 와 HARNESS_ROOT 모두 같은 규칙 공유.
# 테스트(test-harness-root-valid.sh·test-path-validation.sh)는 이 함수를 직접 호출해
# case 패턴 복붙 없이 회귀 보장.
_validate_path_chars() {  # $1=path → stdout "0" or "1"
  case "${1:-}" in
    "") echo 0 ;;                              # 빈 문자열은 위험 (잘못된 자동 도출)
    *[!A-Za-z0-9/._-]*) echo 0 ;;
    *) echo 1 ;;
  esac
}

PROJECT_ROOT_VALID="$(_validate_path_chars "$PROJECT_ROOT")"
if [ "$PROJECT_ROOT_VALID" = "0" ]; then
  echo "오류: PROJECT_ROOT='$PROJECT_ROOT' 에 허용되지 않는 문자 포함." >&2
  echo "  허용: [A-Za-z0-9/._-] (공백·빈 문자열 미허용). 디렉터리 이름 정리 후 재시도." >&2
fi

# HARNESS_ROOT 도 동일 validation. sed `#` 구분자 안전성·토큰 치환 안전성 보장 (4차 P1 §2.2).
# 4차 spec 이전엔 HARNESS_ROOT 미검증 — 잠재 결함이었음.
HARNESS_ROOT_VALID="$(_validate_path_chars "$HARNESS_ROOT")"
if [ "$HARNESS_ROOT_VALID" = "0" ]; then
  echo "오류: HARNESS_ROOT='$HARNESS_ROOT' 에 허용되지 않는 문자 포함." >&2
  echo "  허용: [A-Za-z0-9/._-] (공백·빈 문자열 미허용). 하네스 설치 경로 정리 후 재시도." >&2
fi

WORKSPACE="$PROJECT_ROOT/.agent-harness"

# basename sanitize: tmux 세션명 규칙([A-Za-z0-9_-]).
# bash 3.2 ${var//pattern} 의 glob/정규식 모호성 회피 위해 sed (D3).
_session_autoname() {
  local b safe
  b="$(basename "$PROJECT_ROOT")"
  safe="$(printf '%s' "$b" | sed 's/[^A-Za-z0-9_-]/_/g')"
  printf 'agents-%s' "$safe"
}

# SESSION 결정 우선순위: SESSION_OVERRIDE > PROFILE_SESSION > SESSION env > 자동명.
# 자동명은 PROJECT_ROOT basename 기반이라 멀티 프로젝트 동시 가동 시 자연 격리.
# SESSION_DEFAULT 와 session_exists() 는 호환 위해 유지 (Q9, 후속 cleanup).
resolve_session() {
  printf '%s' "${SESSION_OVERRIDE:-${PROFILE_SESSION:-${SESSION:-$(_session_autoname)}}}"
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

# 워커 역할 → settings 사본 산출 (4차 P0). 매핑 없으면 빈 echo + rc=0.
# 호출자는 빈 echo 면 --settings 안 붙임.
#   $1=worker_role (dev/test/reviewer-quality/...) → echo path 또는 빈 출력
generate_worker_settings() {
  local role="$1"
  local tpl_name=""
  case "$role" in
    dev|security|researcher) tpl_name="dev" ;;
    tester) tpl_name="test" ;;
    reviewer-*) tpl_name="reviewer" ;;
    *) return 0 ;;   # 매핑 없음 — settings 없이 부트 (lead/LEAD/unknown 포함). 빈 stdout.
  esac
  local tpl="$HARNESS_ROOT/templates/settings.${tpl_name}.json.tpl"
  local out_dir="$PROJECT_ROOT/.agent-harness/.boot-settings"
  local out="$out_dir/${role}.json"
  if [ ! -f "$tpl" ]; then
    echo "오류: settings 템플릿 없음 ($tpl) — 워커 '$role'" >&2
    return 1
  fi
  mkdir -p "$out_dir"
  sed -e "s#{{PROJECT_ROOT}}#$PROJECT_ROOT#g" \
      -e "s#{{HARNESS_ROOT}}#$HARNESS_ROOT#g" \
      "$tpl" > "$out"
  # 광범위 토큰 검증 — 화이트리스트 외 잔존도 fail (템플릿 오류 사전 차단).
  if grep -qE '\{\{[A-Z_]+\}\}' "$out"; then
    echo "오류: $out 에 토큰 미치환 잔존: $(grep -oE '\{\{[A-Z_]+\}\}' "$out" | sort -u | tr '\n' ' ')" >&2
    return 1
  fi
  echo "$out"
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

# 현재 배정 task 기록 (R3). dispatch 가 워커별로 기록 → log-event hook 이
# HARNESS_TASK env 부재 시 이 파일에서 task 를 읽어 events.log task필드를 채움.
# claude 무상태·파일기반 (spec). 1워커=1현재task.
write_harness_task() {  # $1=worker $2=task_id
  printf '%s' "$2" > "${WORKSPACE}/.harness-task.$1"
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
    v="$(grep -m1 -i 'verdict' "$f" 2>/dev/null | grep -io 'VIOLATION\|OK' | head -1 | tr 'a-z' 'A-Z')"
    if [ "$v" = "VIOLATION" ]; then printf 'VIOLATION'; return 0; fi
  done
  if [ "$found" = "1" ]; then printf 'OK'; else printf 'PENDING'; fi
}

# 시그널 유실 안전장치 (spec §6). wait-for 가 메인 대기 전 발화해도
# events.log 의 done 라인으로 완료를 확정 (멱등).
done_logged() {  # $1=events.log $2=worker $3=id → done 라인 있으면 0
  [ -f "$1" ] || return 1
  [ -n "${2:-}" ] && [ -n "${3:-}" ] || return 1
  awk -F'\t' -v w="$2" -v id="$3" \
    '("" $2)==("" w) && ("" $3)==("" id) && $4=="done"{f=1} END{exit f?0:1}' "$1"
}

# 프롬프트 안전 주입: 텍스트(리터럴)와 Enter 분리. spec §4.1.
send_prompt() {
  local target="$1" text="$2"
  tmux send-keys -t "$target" -l "$text"
  tmux send-keys -t "$target" Enter
}

# --project 인자 정규화 (E12·F2). stdout=절대경로, $?=0 성공, return 1 실패.
# subshell 안 exit silent failure 회피 위해 return 사용·호출자 명시 검사.
_normalize_project() {  # $1=raw → stdout=절대경로
  local raw="${1:-}"
  if [ ! -d "$raw" ]; then
    echo "오류: --project 경로 없음: $raw" >&2
    return 1
  fi
  ( cd "$raw" && pwd )
}

# pane 의 셸이 입력 받을 준비됐는지 sentinel echo 폴링.
# claude PATH 존재까지 확인해 PATH 갱신 지연 케이스도 잡음.
# return 0 = ready, return 1 = timeout.
# P2 spec §2.1.
shell_ready_wait() {  # $1=pane_id  $2=timeout_sec(기본 SHELL_READY_TIMEOUT 또는 15)
  local pid="$1"
  local timeout="${2:-${SHELL_READY_TIMEOUT:-15}}"
  # sentinel salt 는 부모 셸 (lib.sh source 한 셸) 의 $$/$RANDOM 으로 expand — pane 셸에선 추가 expand 없음.
  # split 형태 "__SHRDY"${salt}"_DONE__" 는 명령 라인 echo 와 실제 출력의 grep 매치 분리 효과 (위양성 차단).
  local salt="$$_$RANDOM"
  local sentinel="__SHRDY${salt}_DONE__"
  # claude 존재 검증 + sentinel 출력.
  # command -v, type, which 셋 중 하나라도 성공하면 OK (alias 환경 fallback).
  # sentinel 을 변수 concat 로 보내 명령 라인엔 prefix/suffix 가 분리된 채 보이게 함.
  tmux send-keys -t "$pid" "( command -v claude || type claude || which claude ) >/dev/null 2>&1 && echo \"__SHRDY\"${salt}\"_DONE__\"" Enter
  local max_iter=$((timeout * 5))   # 0.2s * 5 = 1s 단위.
  local i=0
  while [ "$i" -lt "$max_iter" ]; do
    # -S -200 으로 최근 200줄 history 검사 — 후속 출력에 sentinel 이 스크롤 아웃 되어도 잡음.
    if tmux capture-pane -p -S -200 -t "$pid" 2>/dev/null | grep -q "$sentinel"; then
      return 0
    fi
    sleep 0.2
    i=$((i + 1))
  done
  return 1
}

# ===== 5차 lead gateway 보조 함수 =====

# epoch seconds (정수). incidents/pending-asks/removal-requests 의 timestamp 필드 통일 단위 (F23).
timestamp() {
  date +%s
}

# 로그 한 줄을 400 byte 미만으로 truncate + append (SIGPIPE 가드).
# 한글 1자=3byte 고려. ${#line} 은 문자 수라 byte 와 다름 → head -c 로 byte 단위.
# set -euo pipefail 환경에서 큰 입력 시 head -c 가 stdin 닫으면 printf 가 SIGPIPE → || true 흡수.
# LOG 변수는 데몬 본체(watch-asks.sh)가 export 해 주입.
log_safe() {
  local line="$1"
  local truncated
  truncated=$(printf '%s' "${line}" | head -c 400 2>/dev/null || true)
  printf '%s\n' "${truncated}" >> "${LOG:-/dev/null}"
}

# tool 입력 JSON 을 200 byte 미만으로 요약 (로그용). SIGPIPE 가드.
# $1=tool $2=input_json
summarize_input() {
  local tool="$1" input="$2"
  printf '%s' "${input}" | head -c 200 2>/dev/null || true
}
