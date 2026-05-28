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

# 인자 path 의 basename 을 sanitize 해서 'awa-<safe>' 세션명 반환.
# 순수 함수(외부 전역 미참조). _session_autoname 이 이 함수에 위임 (sanitize 단일 출처).
# basename sanitize: tmux 세션명 규칙([A-Za-z0-9_-]).
# bash 3.2 ${var//pattern} 의 glob/정규식 모호성 회피 위해 sed (D3).
session_name_for() {  # $1=project path → echo "awa-<sanitized>"
  local b safe
  b="$(basename "$1")"
  safe="$(printf '%s' "$b" | sed 's/[^A-Za-z0-9_-]/_/g')"
  printf 'awa-%s' "$safe"
}

# PROJECT_ROOT 기반 자동명 — session_name_for 위임으로 sanitize 로직 단일화.
# 호출부(resolve_session)는 인자 없이 쓰는 관습을 유지하기 위해 wrapper 함수로 남긴다.
_session_autoname() {
  session_name_for "$PROJECT_ROOT"
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
# spec §6: dispatch 가 pane title=워커명으로 워커를 조회하므로,
# 워커 셸의 OSC title escape 가 select-pane -T 로 지정한 title 을
# 덮어쓰지 못하도록 세션 로컬로 고정한다.
#
# tmux 3.6a 실측 + man tmux 근거:
#   - allow-rename  : \ek..\e\\ (window-name) 전용 — pane_title 에 무력
#   - allow-set-title: \e]0;..\007 / \e]2;..\007 (pane title) 를 차단 ← 핵심
# 따라서 pane_title 보존의 결정타는 allow-set-title off 이다.
# allow-rename/automatic-rename off 도 세션 로컬·무해하므로 함께 고정한다
# (window-name 까지 호스트명으로 흔들리지 않도록 방어).
# 14차 UX: pane-border-status/format 도 같은 함수에서 세팅 (title 관련 세션 로컬 단일 출처).
fix_session_titles() {
  local s="$1"
  tmux set-option -t "$s" allow-set-title off 2>/dev/null || true
  tmux set-option -t "$s" allow-rename off 2>/dev/null || true
  tmux set-option -t "$s" automatic-rename off 2>/dev/null || true
  # pane border 에 라벨 표시 — title 보존 옵션 옆 단일 출처 (UX 14차).
  tmux set-option -t "$s" pane-border-status top                                      2>/dev/null || true
  tmux set-option -t "$s" pane-border-format ' [ #{@awa-project-name} ] #{pane_title} ' 2>/dev/null || true
}

# 워커 이름 → 부트스트랩 합본 파일 경로
boot_file() {
  local worker="$1"
  printf '%s/.boot/%s.md' "$WORKSPACE" "$worker"
}

# 역할명 → 역할 프롬프트 파일 절대경로. roles/*/<role>.md 글롭 단일매칭 (파츠화).
# 0개=오류(없는 역할), 2개+=오류(역할명 중복 — 고유성 위반). fail-fast.
# 외부 전역 미의존(순수) — $1 로 prompts_dir 받음. macOS BSD find 호환(-mindepth/-maxdepth OK, 실측).
resolve_role_file() {  # $1=prompts_dir $2=role → echo 경로, rc 0/1
  local pdir="$1" role="$2" matches n
  matches="$(find "$pdir/roles" -mindepth 2 -maxdepth 2 -type f -name "$role.md" 2>/dev/null)"
  n="$(printf '%s\n' "$matches" | grep -c . || true)"
  if [ "$n" -eq 0 ]; then
    echo "오류: 역할 '$role' 프롬프트 없음 (roles/*/$role.md 매칭 0)" >&2; return 1
  elif [ "$n" -gt 1 ]; then
    echo "오류: 역할 '$role' 중복 ($n 개) — 역할명 고유해야 함:" >&2
    printf '%s\n' "$matches" >&2; return 1
  fi
  printf '%s\n' "$matches"
}

# 워커 역할 → settings 사본 산출 (5차: 2 인자).
# $1=entry_role (settings 파일명 결정: dev/test/reviewer-*/lead/...) → echo path
# $2=entry_name (settings 의 {{ENTRY_NAME}} 토큰 치환값 — WORKER env 통일, F22 옵션 A)
# 매핑 없는 역할은 default 템플릿 적용 (4차 P0 의 `*) return 0` 대체, F12·§5.13).
generate_worker_settings() {
  local role="$1" entry_name="${2:-}"
  local tpl_name=""
  case "$role" in
    dev|security|researcher) tpl_name="dev" ;;
    tester) tpl_name="test" ;;
    reviewer-*) tpl_name="reviewer" ;;
    lead|LEAD) tpl_name="lead" ;;
    pm|PM) tpl_name="pm" ;;
    *) tpl_name="default" ;;
  esac
  local tpl="$HARNESS_ROOT/templates/settings.${tpl_name}.json.tpl"
  local out_dir="$PROJECT_ROOT/.agent-harness/.boot-settings"
  local out="$out_dir/${role}.json"
  if [ ! -f "$tpl" ]; then
    echo "오류: settings 템플릿 없음 ($tpl) — 워커 '$role'" >&2
    return 1
  fi
  mkdir -p "$out_dir"
  # F39: 기존 PROJECT_ROOT·HARNESS_ROOT 치환 유지 + ENTRY_NAME 토큰 추가 (대체 아님).
  # 6차: ENTRY_ROLE 토큰 추가 — permission-gate.sh 가 역할별 matrix/settings 조회에 사용.
  sed -e "s#{{PROJECT_ROOT}}#$PROJECT_ROOT#g" \
      -e "s#{{HARNESS_ROOT}}#$HARNESS_ROOT#g" \
      -e "s#{{ENTRY_NAME}}#$entry_name#g" \
      -e "s#{{ENTRY_ROLE}}#$role#g" \
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
  # C-1: path traversal 차단 (10차 리뷰). ** → .* 로 풀리면 `..` 세그먼트를
  # 텍스트로 흡수해 {PROJECT_ROOT}/../../etc/... 가 auto-allow 된다.
  # path 가 `..` 라는 디렉터리 세그먼트를 포함하면 무조건 불일치.
  # 세그먼트 경계 기준 판정 — /proj/a..b/x 같은 정상 파일명은 오탐 안 함.
  case "/$path/" in
    *'/../'*) return 1 ;;
  esac
  for (( i=0; i<${#pat}; i++ )); do
    ch="${pat:i:1}"
    case "$ch" in
      '*')
        if [ "${pat:i+1:1}" = '*' ]; then re+='.*'; i=$((i+1)); else re+='[^/]*'; fi ;;
      '.') re+='\.' ;;
      '/') re+='/' ;;
      # I-1: 정규식 메타 이스케이프 (10차 리뷰). glob 메타가 아닌 일반 문자가
      # 정규식 특수문자면 \ 로 literal 화 — pat 의 +()[]{}$^|?\ 가 정규식
      # 으로 해석돼 의도보다 넓게 매칭되는 것을 막는다.
      '\' | '^' | '$' | '[' | ']' | '|' | '(' | ')' | '+' | '?' | '{' | '}')
        re+="\\$ch" ;;
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

# claude 의 Bash(prefix:*) 단어경계 의미론과 일치하는 prefix 매칭 (공식문서+probe 실측 확정,
# 8차). field 가 prefix 로 시작하고 prefix 직후가 (a)문자열 끝 또는 (b)공백일 때만 매칭.
# bash 3.2: case glob, "$prefix" 따옴표가 prefix 내 glob 메타(.·*)를 리터럴 처리(실측).
# $1=prefix $2=field → exit 0(매칭) | 1(비매칭)
prefix_match() {
  local prefix="$1" field="$2"
  [ -n "$prefix" ] || return 1            # 빈 prefix → 비매칭(전체매칭 폭주 방어)
  [ "$field" = "$prefix" ] && return 0    # 정확 일치(끝 경계)
  case "$field" in
    "$prefix "*) return 0 ;;              # prefix + 공백 경계
  esac
  return 1
}

# 로그 한 줄을 최대 400 byte (이하) 로 truncate + append (SIGPIPE 가드).
# 파일 줄 최대 = 400 byte 데이터 + newline 1 byte = 401 byte.
# 한글 1자=3byte 고려. ${#line} 은 문자 수라 byte 와 다름 → head -c 로 byte 단위.
# set -euo pipefail 환경에서 큰 입력 시 head -c 가 stdin 닫으면 printf 가 SIGPIPE → || true 흡수 (실측 exit 0).
# iconv //IGNORE 로 UTF-8 멀티바이트 경계 잘림 제거 (깨진 마지막 바이트 제거 → 유효 UTF-8).
# LOG 변수는 호출자(permission-gate hook 등)가 export 해 주입.
log_safe() {
  local line="$1"
  local truncated
  # 400 byte truncate + UTF-8 멀티바이트 경계 정리 (//IGNORE 가 깨진 마지막 바이트 제거).
  # SIGPIPE 가드: set -euo pipefail 환경 대용량 입력 시 || true 흡수 (실측 exit 0).
  truncated=$(printf '%s' "${line}" | head -c 400 2>/dev/null | iconv -f UTF-8 -t UTF-8//IGNORE 2>/dev/null || true)
  printf '%s\n' "${truncated}" >> "${LOG:-/dev/null}"
}

# tool 입력 JSON 을 최대 200 byte (이하) 로 요약 (로그용). SIGPIPE 가드.
# 200 byte truncate + UTF-8 경계 정리.
# $1=tool $2=input_json
summarize_input() {
  local tool="$1" input="$2"
  printf '%s' "${input}" | head -c 200 2>/dev/null | iconv -f UTF-8 -t UTF-8//IGNORE 2>/dev/null || true
}

# settings.allow 에 패턴 추가 (mkdir 원자성 락 + atomic write). entry_role 기준 settings.
# 6차: 병렬 워커 hook 이 직접 호출 → read-modify-write 를 mkdir 락으로 보호 (lost update 방지).
#   flock 은 macOS 기본 부재 → mkdir(POSIX 원자성).
# ★ RETURN trap 미사용 (이식성·단순성): 대신 (1) 명시적 rmdir 로 정상 정리,
#   (2) stale lock 자동 회수 — 락 보유자가 비정상 종료해 lock 이 남아도, 다음 호출이
#   "오래된(>15s) lock" 을 강제 제거하고 진입. 데드락 영구화 방지.
# $1=entry_role $2=pattern
add_to_allow() {
  local entry_role="$1" pattern="$2"
  # 방어적 가드: 빈 패턴은 settings.allow 를 오염시키므로 무시 (7차 결함3 이중 방어).
  [ -n "$pattern" ] || return 0
  local settings="${PROJECT_ROOT}/.agent-harness/.boot-settings/${entry_role}.json"
  [ -f "$settings" ] || return 1
  local lock="${settings}.lock"
  local tmp="${settings}.tmp.$$.${RANDOM}"
  local i=0 max=300   # 300 * 0.05s = 15s 상한
  while ! mkdir "$lock" 2>/dev/null; do
    # stale lock 회수: mtime 을 *읽을 수 있고*(mt>0) 15초 이상 묵었을 때만 강제 제거.
    # ★ 5차 실측 결함: mt=0(stat 실패 — lock 이 막 사라짐)이면 age=now-0=거대값이 되어
    #   "방금 다른 워커가 새로 만든 정상 lock" 을 15s 초과로 오판해 강제삭제 → 임계구역
    #   동시진입 → lost update 재발(이 함수의 존재 이유 무력화). mt>0 가드로 차단 (실측 확정,
    #   20병렬 부하 count=20·진짜 16s stale 회수 둘 다 통과). mt=0 면 강제삭제 금지·단순 재시도.
    local mt; mt="$(_mtime_epoch "$lock")"
    if [ "$mt" -gt 0 ]; then
      local age=$(( $(date +%s) - mt ))
      [ "$age" -ge 15 ] && rmdir "$lock" 2>/dev/null || true
    fi
    i=$((i + 1))
    [ "$i" -ge "$max" ] && { echo "add_to_allow: lock 획득 실패 ($settings)" >&2; return 1; }
    sleep 0.05
  done
  jq --arg p "${pattern}" \
    '.permissions.allow = ((.permissions.allow // []) + [$p] | unique)' \
    "${settings}" > "${tmp}" && mv "${tmp}" "${settings}"
  local rc=$?
  rmdir "$lock" 2>/dev/null || true
  return $rc
}

# 디렉터리/파일 mtime epoch (BSD stat). 못 읽으면 0 (호출부가 mt>0 가드로 처리). lib.sh 에 없으면 추가.
_mtime_epoch() { stat -f %m "$1" 2>/dev/null || echo 0; }

# 도구·입력·scope → claude allow 패턴 도출.
# $1=tool $2=input_json $3=scope (exact|command-group|tool)
# Bash: command 의 첫 토큰(또는 첫 2토큰)을 prefix 로. Edit/Write: file_path.
derive_pattern() {
  local tool="$1" input="$2" scope="$3"
  case "$scope" in
    tool)
      printf '%s' "${tool}"
      return
      ;;
  esac
  local key field
  case "$tool" in
    Bash) key="command" ;;
    Edit|Write) key="file_path" ;;
    *) key="" ;;
  esac
  if [ -z "$key" ]; then
    printf '%s' "${tool}"
    return
  fi
  field="$(printf '%s' "${input}" | jq -r --arg k "$key" '.[$k] // ""')"
  case "$scope" in
    exact)
      printf '%s(%s)' "${tool}" "${field}"
      ;;
    command-group)
      if [ "$tool" = "Bash" ]; then
        # 복합/멀티라인 명령은 안전한 단일 prefix 를 도출할 수 없다(첫 2토큰만 뽑으면
        # 메타 뒤 부분 누락 → 위험 패턴이 좁은 prefix 로 우회 학습). 빈 문자열 반환 →
        # 호출부(gate_gray)가 학습 생략 + approve-once 강등. (7차 결함3, 실측 규명)
        # 판정: 줄바꿈 또는 셸 메타문자(&& || ; | $( ` > <) 포함 시 복합.
        local NL; NL=$'\n'   # bash 3.2 ANSI-C 인용 (실측 지원 확인)
        case "$field" in
          *'&&'*|*'||'*|*';'*|*'|'*|*'$('*|*'`'*|*'>'*|*'<'*|*"$NL"*) printf ''; return ;;
        esac
        # 첫 2 토큰을 prefix 로 (예: "npm test foo" → "npm test"). 단일 토큰이면 그 토큰만.
        local first second prefix
        first="$(printf '%s' "$field" | awk '{print $1}')"
        second="$(printf '%s' "$field" | awk '{print $2}')"
        if [ -n "$second" ]; then prefix="$first $second"; else prefix="$first"; fi
        printf '%s(%s:*)' "${tool}" "${prefix}"
      else
        # Edit/Write: file_path 의 디렉터리. ★ 빈 file_path → dirname '' = '.' (위험) 회피:
        #   field 비면 tool 명만 (도구 전체 — exact 보다 좁힐 근거 없음, deny 보다 안전한 폴백).
        if [ -z "$field" ]; then printf '%s' "${tool}"; else printf '%s(%s:*)' "${tool}" "$(dirname "$field")"; fi
      fi
      ;;
  esac
}

# timeout 명령 해석: coreutils timeout / gtimeout / 폴백 (macOS 기본 환경 대응).
# tmux wait-for 같은 블로킹 명령을 N초 상한으로 실행. 자연완료=0, timeout=124.
# 주의 1: 폴백은 서브셸로 감싸지 않고 직접 백그라운드 → $pid 가 곧 대상 프로세스
#   (서브셸이면 tmux wait-for 손주가 고아로 영생).
# 주의 2: SIGKILL 사용. tmux 소스(cmd-wait-for.c) 검증 결과 — 클라이언트에 보내는
#   시그널은 서버의 채널 woken/waiter 를 *건드리지 않는다*(SIGTERM 도 다른 대기자를
#   안 깨움). SIGKILL 을 택한 실제 이유는 wait-for 클라이언트가 SIGTERM 을 자체
#   핸들러로 잡아 깔끔히 종료할 수 있어 "kill 로 죽였는지(timeout)" 판별이 모호하기
#   때문 — SIGKILL 은 핸들러 우회라 판별 명확. (채널 오염과는 무관.)
run_with_timeout() {
  local secs="$1"; shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "$secs" "$@"
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$secs" "$@"
  else
    "$@" &
    local pid=$!
    ( sleep "$secs"; kill -KILL "$pid" 2>/dev/null ) &
    local watcher=$!
    local crc=0
    wait "$pid" 2>/dev/null || crc=$?
    kill -KILL "$watcher" 2>/dev/null || true
    wait "$watcher" 2>/dev/null || true
    [ "$crc" -eq 0 ] && return 0 || return 124
  fi
}

# === bookmarks (15차) ===========================================================
# 단일 출처 — wrapper 스크립트는 이 7개 함수만 호출.
# 저장 형식: ~/.config/agenphony/bookmarks.tsv (TSV 5컬럼: path alias preset plan last_used).
BOOKMARKS_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/agenphony"
BOOKMARKS_FILE="$BOOKMARKS_DIR/bookmarks.tsv"

bookmarks_init() {
  mkdir -p "$BOOKMARKS_DIR"
  [ -f "$BOOKMARKS_FILE" ] || touch "$BOOKMARKS_FILE"
}

bookmarks_upsert() {
  local path="$1" preset="$2" plan="${3:-}"
  # 7차 리뷰 [MAJOR-9]: TSV 무결성 — path/preset/plan 에 tab/newline 들어가면 5컬럼 가정 깨짐
  for _f in "$path" "$preset" "$plan"; do
    case "$_f" in
      *$'\t'*|*$'\n'*) echo "오류: bookmark 필드에 tab/newline 불가 — '$_f'" >&2; return 1 ;;
    esac
  done
  local ts; ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  bookmarks_init
  local existing_alias=""
  existing_alias=$(awk -F'\t' -v p="$path" '$1==p{print $2; exit}' "$BOOKMARKS_FILE")
  local tmp="$BOOKMARKS_FILE.$$.tmp"
  awk -F'\t' -v p="$path" '$1!=p' "$BOOKMARKS_FILE" > "$tmp"
  printf '%s\t%s\t%s\t%s\t%s\n' "$path" "$existing_alias" "$preset" "$plan" "$ts" >> "$tmp"
  mv "$tmp" "$BOOKMARKS_FILE"
}

bookmarks_resolve_alias() {
  local input="$1"
  [ -f "$BOOKMARKS_FILE" ] || { echo ""; return; }
  awk -F'\t' -v a="$input" '$2==a{print $1; exit}' "$BOOKMARKS_FILE"
}

bookmarks_list() {
  bookmarks_init
  local i=0
  echo "  #  path                                       alias       preset        last_used         stale?"
  while IFS=$'\t' read -r path alias preset plan used; do
    [ -n "$path" ] || continue
    i=$((i+1))
    local stale=""
    [ -d "$path" ] || stale="[stale]"
    printf '  %d  %-42s %-10s  %-12s  %-18s %s\n' \
      "$i" "$path" "${alias:-}" "${preset:-}" "${used:-}" "$stale"
  done < "$BOOKMARKS_FILE"
  [ "$i" = 0 ] && echo "  (no bookmarks)"
}

bookmarks_set_alias() {
  local num="$1" new_alias="${2:-}"
  bookmarks_init
  # 6차 리뷰 [CRIT-2]: list 가 빈 라인 skip 하므로 set_alias 도 동일 필터로 i 정렬
  local target
  target=$(awk -F'\t' -v n="$num" '$1!=""{i++; if(i==n){print $1; exit}}' "$BOOKMARKS_FILE")
  [ -n "$target" ] || { echo "오류: bookmark $num 없음" >&2; return 1; }
  # 6차 리뷰 [MINOR-5]: spec §5.6 L737 "기존 path 우선" — 충돌 시 set 거부
  if [ -n "$new_alias" ]; then
    local conflict
    conflict=$(awk -F'\t' -v a="$new_alias" -v p="$target" '$2==a && $1!=p{print $1; exit}' "$BOOKMARKS_FILE")
    if [ -n "$conflict" ]; then
      echo "오류: alias '$new_alias' 이 이미 '$conflict' 에 부여됨 — 기존 path 우선 (set 거부)" >&2
      return 1
    fi
  fi
  local tmp="$BOOKMARKS_FILE.$$.tmp"
  awk -F'\t' -v OFS='\t' -v p="$target" -v a="$new_alias" \
    '$1==p { $2=a } { print }' "$BOOKMARKS_FILE" > "$tmp"
  mv "$tmp" "$BOOKMARKS_FILE"
}

bookmarks_remove() {
  local sel="$1"
  bookmarks_init
  # 6차 리뷰 [CRIT-2]: list 가 빈 라인 skip 하므로 i (논리 인덱스) 기준으로 통일
  local n
  n=$(awk -F'\t' '$1!=""{i++} END{print i+0}' "$BOOKMARKS_FILE")
  local indices=""
  if [ "$sel" = "all" ]; then
    # 6차 리뷰 [CRIT-3]: BSD seq 1 0 = '1\n0' (descending) → n=0 가드 필수
    [ "$n" -gt 0 ] && indices=$(seq 1 "$n")
  else
    indices=$(echo "$sel" | tr ',' '\n' | grep -E '^[0-9]+$' | sort -un)
  fi
  [ -n "$indices" ] || { echo "오류: 유효 선택 없음" >&2; return 1; }
  local tmp="$BOOKMARKS_FILE.$$.tmp"
  # i (논리 인덱스) 기준 삭제: 빈 라인이 있으면 NR 과 i 가 달라지므로 i 만 사용
  awk -F'\t' -v OFS='\t' -v sel="$indices" '
    BEGIN { n=split(sel, a, "\n"); for(k=1;k<=n;k++) d[a[k]]=1 }
    $1=="" { print; next }   # 빈 라인은 보존 (제거 대상 아님)
    { i++; if (!(i in d)) print }
  ' "$BOOKMARKS_FILE" > "$tmp"
  mv "$tmp" "$BOOKMARKS_FILE"
}

bookmarks_prune() {
  bookmarks_init
  local stale_count=0
  while IFS=$'\t' read -r path _; do
    [ -n "$path" ] || continue
    [ -d "$path" ] || stale_count=$((stale_count+1))
  done < "$BOOKMARKS_FILE"
  [ "$stale_count" = 0 ] && { echo "No stale bookmarks."; return 0; }
  read -r -p "Remove $stale_count stale bookmarks? (y/n): " ans
  [ "$ans" = "y" ] || return 0
  local tmp="$BOOKMARKS_FILE.$$.tmp"
  awk -F'\t' -v OFS='\t' '{
    cmd = "test -d \"" $1 "\""
    if (system(cmd) == 0) print
  }' "$BOOKMARKS_FILE" > "$tmp"
  mv "$tmp" "$BOOKMARKS_FILE"
}
