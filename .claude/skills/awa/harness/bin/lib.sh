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

# ★ 재발 방지 가드(B): PROJECT_ROOT 가 하네스 본체로 잡혔는지 *플래그만* 기록.
#   cwd=awa 에서 일회용 스크립트가 `export PROJECT_ROOT=$(mktemp -d)` 로 격리를 의도해도,
#   이 파일이 source 시 무조건 resolve_project_root 로 재계산해 본체를 잡는다
#   (2026-05-30 디렉토리 소실 근본원인 — 그 상태의 `rm -rf "$PROJECT_ROOT"` 가 본체 삭제).
#   여기서 echo 로 경고하면 awa-main.sh 등 정상 resolve-path 경로의 stdout/stderr 를
#   오염시켜 회귀를 깬다(M8/M3b 실측). → 출력 없는 플래그만 두고, 실제 차단은
#   danger-check.sh 의 harness-root-rm 규칙이 담당.
#   소비처: awa-up.sh 가 이 플래그로 본체 가동 경고를 발화(가동은 진행, --project 권장).
if [ -z "${HARNESS_PROJECT:-}" ] && [ "$PROJECT_ROOT" = "$HARNESS_ROOT" ]; then
  PROJECT_ROOT_IS_HARNESS=1
else
  PROJECT_ROOT_IS_HARNESS=0
fi

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

# 벤더 화이트리스트 = bin/vendors/<v>.sh 존재 여부. $1=vendor → rc 0/1.
is_known_vendor() {
  local v="$1"
  [ -n "$v" ] && [ -f "$HARNESS_ROOT/bin/vendors/${v}.sh" ]
}

# 오케스트레이터(LEAD/PM) 벤더 가드 — claude 강제. $1=요청벤더 $2=역할라벨(LEAD/PM) → echo 확정벤더.
#   AWA 방향(2026-05-31): codex 는 워커/리뷰어로만. LEAD/PM 베이스는 claude 전용.
#   사유=P17 — watcher 가 send-keys 로 LEAD/PM 입력창에 알림을 쏘는데 codex TUI 가 작업 중이면
#   큐잉만 하고 제출 안 함 → 알림 잔상 + 게이트 타임아웃 → dispatch 반복 실패(실측 cycledemo).
#   워커는 알림 받는 쪽이 아니라(events.log/results 쓰는 쪽) 무관 → codex 워커/리뷰어는 허용.
#   claude 가 아닌 벤더가 LEAD/PM 에 지정되면 claude 로 강등하고 경고(부트는 막지 않음).
#   재진입: codex LEAD/PM 은 P17(send-keys↔TUI 큐잉) 재설계 후. → 메모리 codex-vendor-worker-reviewer-only.
resolve_orchestrator_vendor() {
  local req="$1" role="${2:-LEAD}"
  if [ -n "$req" ] && [ "$req" != "claude" ] && [ "${AGENT_CMD:-claude}" = "claude" ]; then
    echo "경고: ${role} 벤더 '${req}' → claude 로 강제(AWA: LEAD/PM 은 claude 전용, codex 는 워커/리뷰어만). P17 알림 경합 회피." >&2
    printf 'claude'
    return 0
  fi
  printf '%s' "${req:-claude}"
}

# 벤더 어댑터 source. $1=vendor → 5함수 로드. 실패 시 rc 1.
# _test 강제 규칙: AGENT_CMD 가 claude 아닌 값이면 _test 어댑터 우선(역호환).
vendor_source() {
  local v="$1"
  if [ -n "${AGENT_CMD:-}" ] && [ "${AGENT_CMD}" != "claude" ]; then
    v="_test"
  fi
  if ! is_known_vendor "$v" && [ "$v" != "_test" ]; then
    echo "오류: 미지원 벤더 '$v' (bin/vendors/${v}.sh 없음)" >&2
    return 1
  fi
  # shellcheck disable=SC1090
  . "$HARNESS_ROOT/bin/vendors/${v}.sh"
}

# 워커 역할 → settings 사본 산출 (5차: 2 인자).
# $1=entry_role (settings 파일명 결정: dev/test/reviewer-*/lead/...) → echo path
# $2=entry_name (settings 의 {{ENTRY_NAME}} 토큰 치환값 — WORKER env 통일, F22 옵션 A)
# 매핑 없는 역할은 readonly 템플릿 적용 — 최소권한 fail-safe (4차 P0 의 `*) return 0` 대체, F12·§5.13).
generate_worker_settings() {
  local role="$1" entry_name="${2:-}"
  local tpl_name=""
  case "$role" in
    engineer|security|frontend|backend|infra) tpl_name="dev" ;;
    dev) tpl_name="dev" ;;   # dev = 구 역할명 하위호환(engineer 로 통합 2026-06-09) — 카탈로그 미노출
    researcher|review-manager) tpl_name="readonly" ;;
    tester) tpl_name="test" ;;
    reviewer-*) tpl_name="reviewer" ;;
    orch|ORCH|lead|LEAD) tpl_name="orch" ;;   # lead|LEAD = 구 역할명 하위호환
    desk|DESK|pm|PM) tpl_name="desk" ;;        # pm|PM = 구 역할명 하위호환
    *) tpl_name="readonly" ;;
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
# C-1 정정: action 별 필드5 의미 분기 — modify 만 path 디바운스.
# - modify: ($worker, $path) 키 — 같은 워커가 같은 파일을 여러 번 수정 → 1회로 압축
# - done/plan-defect/drift-check: ($worker, $action) 키 — payload 가 path 가 아니므로
#   path 디바운스 무의미. action 자체를 키로 (워커별 동종 이벤트 1회 압축).
debounce_pairs() {  # $1=file → "worker\tpath_or_action" 유니크
  local line w a p key
  while IFS= read -r line; do
    event_valid "$line" || continue
    w="$(event_field "$line" 2)"; a="$(event_field "$line" 4)"; p="$(event_field "$line" 5)"
    if [ "$a" = "modify" ]; then
      key="$p"
    else
      key="$a"
    fi
    printf '%s\t%s\n' "$w" "$key"
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
# P7 수정(2026-05-30 codex e2e): codex REPL 은 텍스트 입력 직후 Enter 를 즉시 처리 못 함
#   (텍스트 렌더링 전 Enter 무시 → 부트 프롬프트가 입력창에 잔류·미전송, 전 pane 멈춤 실측).
#   claude 는 간격 없이도 동작하나 codex 는 텍스트→Enter 사이 지연 + 미전송 시 재Enter 필요.
#   → 텍스트 후 짧은 지연 + Enter, 그래도 입력창에 텍스트 잔류하면(prompt 마커 '›'+텍스트
#   앞부분 매치) Enter 1회 재전송. claude 엔 무해(이미 전송됨 → 빈 Enter 또는 잔류 없음).
# 워커 pane 이 입력 받을 준비(idle)인지 — 화면 하단에 입력 프롬프트 마커('❯'/'›'/'>')가
# 떠 있으면 idle. busy(작업중 출력·스피너) 면 마커가 없다. send_prompt 송신 *전* 가드용.
#   $1=target pane.  return 0=idle(마커 있음), 1=busy/미확정(마커 없음).
_pane_idle() {
  tmux capture-pane -p -t "$1" 2>/dev/null \
    | grep -Eq '^[[:space:]]*[❯›>]'
}

send_prompt() {
  local target="$1" text="$2"
  # ★ (b) 송신 전 ready 폴링 (I-1, 2026-06-09): 워커가 busy(직전 task 처리 중)면 claude TUI 가
  #   입력을 큐잉만 하고 제출 안 함(P17 동형). 그 상태로 send-keys 하면 텍스트가 박히지도,
  #   잔류감지(아래)에 걸리지도 않아 *에러 없이 유실*된다(task-start 안 찍힘). 격리 재현:
  #   busy pane 에 dispatch → 0초 성공반환·워커 미수신. → 송신 전 idle 마커가 뜰 때까지 폴링.
  #   타임아웃(기본 30×0.5s=15s)까지 busy 면 진행은 하되(데드락 방지) 잔류감지·(a)의 task-start
  #   ack 가 유실을 잡는다. 부트 직후 첫 송신엔 마커가 아직 없을 수 있어 timeout 후 진행 허용.
  local _ri _rmax="${SEND_PROMPT_READY_MAX:-30}"
  for _ri in $(seq 1 "$_rmax"); do
    _pane_idle "$target" && break
    sleep "${SEND_PROMPT_READY_DELAY:-0.5}"
  done
  # ★ 송신 전 잔류 flush (R7, 2026-06-10 B4 실측): 입력창에 이전 텍스트가 박혀 있으면(직전
  #   송신의 Enter 씹힘 — half-sent. B4: 워커 입력창 'TASK t2' 박힘·리뷰어 3종 깨움 박힘)
  #   새 텍스트가 그 뒤에 *병합*돼 깨진 명령이 된다. 마커-줄 잔류 감지 시 Enter 로 먼저
  #   제출(원래 보내려던 텍스트라 제출이 정답 — 박힌 입력창의 자가 회복 경로이기도 하다).
  local _pre
  _pre="$(tmux capture-pane -p -t "$target" 2>/dev/null \
    | grep -E '^[[:space:]]*[❯›>]' | tail -1 \
    | sed -E 's/^[[:space:]]*[❯›>][[:space:]]*//')" || _pre=""
  if [ -n "$_pre" ]; then
    tmux send-keys -t "$target" Enter
    sleep "${SEND_PROMPT_RETRY_DELAY:-0.5}"
  fi
  tmux send-keys -t "$target" -l "$text"
  sleep "${SEND_PROMPT_ENTER_DELAY:-0.4}"   # codex 렌더링 여유 (claude 엔 무해한 짧은 지연)
  tmux send-keys -t "$target" Enter
  # 미전송 안전망 — 입력창 프롬프트 라인('›'/'>')에 텍스트 앞부분이 잔류하면 Enter 재전송.
  # ★ 폴링 재시도: 느린 REPL(Opus 리뷰어 콜드스타트)은 첫 Enter 가 렌더링 전 도착해 씹힌다.
  #   1회 재전송으론 부족 → 잔류가 사라질 때까지 최대 N회(기본 8×0.5s=4s) 재시도.
  #   라이브 결함: Opus 리뷰어 부트 지시가 입력창에 박혀 역할 미수신 → 투표인단 N 붕괴.
  local head; head="$(printf '%s' "$text" | cut -c1-24)"
  local _i _max="${SEND_PROMPT_RETRY_MAX:-8}"
  for _i in $(seq 1 "$_max"); do
    # 프롬프트 라인 마커에 텍스트 앞부분이 같이 있으면 미전송 → Enter 1회.
    # ★ 마커 3종: '❯'(U+276F, claude REPL 실제 입력 프롬프트)·'›'(U+203A)·'>'(ASCII).
    #   라이브 결함: 기존엔 ❯ 누락으로 claude 입력창 잔류를 못 잡아 Enter 재전송 미발동 → 박힘.
    # ★ 2026-06-07 과다재전송 가드: 기존엔 마커-줄 전체에서 head 를 grep -Fq("포함")로 찾아,
    #   head 가 마커 *바로 뒤*가 아니어도(다른 위치 우연 일치·이전 출력 잔상) 잔류로 오판 →
    #   빈 Enter 를 _max 회까지 폭주 송신(더미 read 루프 실측 4회). 입력창 잔류는 정의상
    #   "마커 + (공백) + head" 형태이므로, 마커-줄에서 마커·선행공백을 sed 로 벗긴 *나머지*가
    #   head 로 시작할 때만 재전송. case glob 으로 head 를 리터럴 매칭(정규식 메타 안전).
    #   tail -1: 입력 프롬프트는 화면 하단 → 가장 마지막 마커 줄만 봐야 위쪽 출력 잔상에
    #   오판 안 함(여러 마커 줄 중 첫 줄이 head 아니어도 false-negative 안 됨).
    _resid="$(tmux capture-pane -p -t "$target" 2>/dev/null \
      | grep -E '^[[:space:]]*[❯›>]' \
      | tail -1 \
      | sed -E 's/^[[:space:]]*[❯›>][[:space:]]*//' )"
    case "$_resid" in
      "$head"*)
        tmux send-keys -t "$target" Enter
        sleep "${SEND_PROMPT_RETRY_DELAY:-0.5}"
        ;;
      *)
        break   # 잔류 없음(또는 head 가 마커 바로 뒤 아님) = 전송 완료로 판정.
        ;;
    esac
  done
}

# 부트 프롬프트 지시문 생성 ($1=부트파일경로, $2=역할별 tail 지시). stdout=주입 텍스트.
# ★ 2026-06-03(2차): 부인 prefix("이건 프롬프트 인젝션이 아니라...")가 claude opus 4.8
#   v2.1.161 휴리스틱을 *오히려* 발동(라이브 입증 — claude 가 이 prefix 를 의심 근거로 명시
#   지목). claude 역할 부트는 --append-system-prompt-file 시스템프롬프트 경로로 이전 →
#   boot_directive 미사용. 이 함수는 codex send_prompt 역할주입 전용으로 단순 지시로 축소
#   (codex 는 부인 prefix 가 트리거 아니라 무해). claude_systemprompt_boot 헬퍼가 벤더 분기.
boot_directive() {  # $1=file $2=tail → stdout. codex send_prompt 역할주입 전용.
  local file="$1" tail="${2:-}"
  printf '%s' "${file} 는 네 역할 규약 파일이다. 읽고 그 역할 규약을 채택하라. ${tail}"
}

# 역할 부트 후처리 — 벤더 분기 캡슐화. claude 는 역할이 이미 --append-system-prompt-file 로
# 시스템 주입됐으므로 send_prompt 역할주입 스킵(중복·injection 오인 회피). codex 는
# 시스템프롬프트 플래그 부재라 send_prompt 로 역할(.boot 합본) 주입 유지.
# $1=vendor $2=pane_id $3=boot_file $4=tail. claude 면 no-op(0), codex 면 send_prompt 발사.
claude_systemprompt_boot() {  # vendor pane bf tail
  local vendor="$1" pane="$2" bf="$3" tail="${4:-}"
  case "$vendor" in
    claude) return 0 ;;  # 시스템프롬프트 경로 — send_prompt 불필요
    *) send_prompt "$pane" "$(boot_directive "$bf" "$tail")" ;;
  esac
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
shell_ready_wait() {  # $1=pane_id  $2=timeout_sec(기본 SHELL_READY_TIMEOUT 또는 15)  $3=cli_bin(기본 claude)
  local pid="$1"
  local timeout="${2:-${SHELL_READY_TIMEOUT:-15}}"
  # $3 = 검증할 CLI 바이너리명 — 벤더화(claude/codex). 빈값이면 claude(역호환 기본).
  #   codex 워커는 claude PATH 부재 환경에서도 부트돼야 하므로 bootstrap_pane 이 벤더별 bin 을 넘긴다.
  local cli_bin="${3:-claude}"
  # sentinel salt 는 부모 셸 (lib.sh source 한 셸) 의 $$/$RANDOM 으로 expand — pane 셸에선 추가 expand 없음.
  # split 형태 "__SHRDY"${salt}"_DONE__" 는 명령 라인 echo 와 실제 출력의 grep 매치 분리 효과 (위양성 차단).
  local salt="$$_$RANDOM"
  local sentinel="__SHRDY${salt}_DONE__"
  # cli_bin 존재 검증 + sentinel 출력.
  # command -v, type, which 셋 중 하나라도 성공하면 OK (alias 환경 fallback).
  # sentinel 을 변수 concat 로 보내 명령 라인엔 prefix/suffix 가 분리된 채 보이게 함.
  tmux send-keys -t "$pid" "( command -v $cli_bin || type $cli_bin || which $cli_bin ) >/dev/null 2>&1 && echo \"__SHRDY\"${salt}\"_DONE__\"" Enter
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

  # Task 7 NEW (§7) — Phase A 신호 발화 + 통계 카운터.
  # blocklist 검사 — Phase C 우회 시 신호 발화 안 함 (events.log·stats 모두 skip).
  # 기존 add_to_allow 동작 (settings.json 누적 + return rc) 보존 — 후크 append 만.
  # events.log 존재 가드 — 워커 컨텍스트(awa-up 후) 에서만 발화. 단위 테스트(HARNESS_PROJECT 격리,
  # events.log 없음) 에서는 stats/events 모두 skip → 운영 stats.yaml 오염 방지.
  if [ $rc -eq 0 ] && ! blocklist_contains "$pattern"; then
    local events_log="${EVENTS:-${PROJECT_ROOT}/.agent-harness/events.log}"
    if [ -f "$events_log" ]; then
      bump_stats_counter "$pattern" "confirm" 2>/dev/null || true
      # events.log 5필드: ts/worker(-)/task(-)/action(allow-confirm)/payload(key=value).
      # 필드5 = pattern=<...>;role=<...> (precondition fix C-1 정합 — key=value payload).
      # worker(2)=- · task(3)=- (allow-confirm 은 worker/task 의존 없음).
      printf '%s\t-\t-\tallow-confirm\tpattern=%s;role=%s\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$pattern" "$entry_role" \
        >> "$events_log" 2>/dev/null || true
    fi
  fi

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
        # ★ 후행 출력 리다이렉트만 스트립 후 판정 (2026-06-08): LLM 워커가 `du -sh . 2>&1`,
        #   `python3 --version 2>/dev/null` 처럼 *출력 폐기/병합* 리다이렉트를 습관적으로 덧붙여
        #   `>` 가드에 걸려 학습이 영구 강등(곡선 평평)됐다. 2>&1·>&2·>/dev/null·2>/dev/null 류는
        #   출력 *방향*만 바꿀 뿐 파일 쓰기·명령 실행이 없어 위험하지 않다 → 명령 끝의 이들만 제거.
        #   일반 파일 쓰기(`> out.txt`)·파이프·연결자는 스트립 대상 아님 → 아래 가드가 그대로 차단.
        # 공백 변형 정규화(`2> /dev/null`→`2>/dev/null`) 후 후행 리다이렉트 토큰 반복 제거.
        local cgfield="$field"
        cgfield="${cgfield//2> \/dev\/null/2>/dev/null}"
        cgfield="${cgfield//1> \/dev\/null/1>/dev/null}"
        cgfield="${cgfield//> \/dev\/null/>/dev/null}"
        while :; do
          case "$cgfield" in
            *' 2>&1'|*' >&2'|*' 1>&2'|*' &>/dev/null'|*' >/dev/null'|*' 1>/dev/null'|*' 2>/dev/null')
              cgfield="${cgfield% *}" ;;
            *) break ;;
          esac
        done
        case "$cgfield" in
          *'&&'*|*'||'*|*';'*|*'|'*|*'$('*|*'`'*|*'>'*|*'<'*|*"$NL"*) printf ''; return ;;
        esac
        field="$cgfield"
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
# 저장 형식: ~/.config/awa/bookmarks.tsv (TSV 5컬럼: path alias preset plan last_used).
# 사용자 단위 상태 디렉토리 — stats/blocklist 등 학습 영속 상태가 산다.
# 코드 위치(HARNESS_ROOT)와 분리: 재설치(코드 교체)해도 학습 보존.
# BOOKMARKS_DIR 와 동일 XDG 베이스 (단일 출처). 디렉토리·시드 파일을 보장한다
# (bump_stats_counter/append_to_yaml 은 파일 존재 가정 → 부재 시 silent drop 방지).
_state_config_dir() {
  local d="${XDG_CONFIG_HOME:-$HOME/.config}/awa"
  mkdir -p "$d" 2>/dev/null || true
  [ -f "$d/orch-auto-allow-stats.yaml" ] || printf '# 권한 학습 통계 — bump_stats_counter 누적\npatterns:\n' > "$d/orch-auto-allow-stats.yaml" 2>/dev/null || true
  [ -f "$d/orch-auto-allow-blocklist.yaml" ] || printf '# 사용자 영구 거부 패턴 — confirm_allow_yaml never 누적\npatterns:\n' > "$d/orch-auto-allow-blocklist.yaml" 2>/dev/null || true
  printf '%s' "$d"
}
BOOKMARKS_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/awa"
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

# worker_turn_count — events.log 의 worker 활동 (modify|done) 행 카운트
# events.log 형식: ts<TAB>worker<TAB>task<TAB>action<TAB>path
# 패턴: 필드 2 = worker, 필드 4 = action (modify|done|...)
# bash 3.2 호환 (awk 만 사용, associative array 미사용)
worker_turn_count() {
  local worker="$1" events_log="${2:-${EVENTS:-${WORKSPACE:-.}/events.log}}"
  [ -f "$events_log" ] || { echo 0; return 0; }
  awk -F'\t' -v w="$worker" '$2==w && ($4=="modify" || $4=="done") { n++ } END { print n+0 }' "$events_log"
}

# I-5 정정: worker_turn_count 가 modify+done 합산 → "총 활동" 의미. 의미 모호 해소를 위해
# action 별 분리 변형 2종 추가. drift-check 임계 (N=10) 는 기존 worker_turn_count 유지.
#
# worker_done_count — done 라인만 카운트 (완료 사이클 의미)
worker_done_count() {
  local worker="$1" events_log="${2:-${EVENTS:-${WORKSPACE:-.}/events.log}}"
  [ -f "$events_log" ] || { echo 0; return 0; }
  awk -F'\t' -v w="$worker" '$2==w && $4=="done" { n++ } END { print n+0 }' "$events_log"
}

# 계측 파서 (차별성 데이터 spec §4). worker_turn_count 와 동형 — awk -F'\t'.
worker_user_ask_count() {
  local worker="$1" events_log="${2:-${EVENTS:-${WORKSPACE:-.}/events.log}}"
  [ -f "$events_log" ] || { echo 0; return 0; }
  awk -F'\t' -v w="$worker" '$2==w && $4=="user-ask" { n++ } END { print n+0 }' "$events_log"
}
deny_count() {
  local events_log="${1:-${EVENTS:-${WORKSPACE:-.}/events.log}}"
  [ -f "$events_log" ] || { echo 0; return 0; }
  awk -F'\t' '$4=="deny" { n++ } END { print n+0 }' "$events_log"
}

# worker_modify_count — modify 라인만 카운트 (도구 호출 의미)
worker_modify_count() {
  local worker="$1" events_log="${2:-${EVENTS:-${WORKSPACE:-.}/events.log}}"
  [ -f "$events_log" ] || { echo 0; return 0; }
  awk -F'\t' -v w="$worker" '$2==w && $4=="modify" { n++ } END { print n+0 }' "$events_log"
}

# ===== 계획 B: dispatch 차단 가드 (회로① 합의 게이트 집행) =====
# 차단 상태 = .agent-harness/state/blocked-workers/<worker>.json (파일 불변식).
# LEAD 가 ⓒ 종합에서 만장일치 판정 시 record_block, 재판정 OK 시 clear_block,
# attempt>=K 시 quarantine_block. dispatch.sh 가 send 직전 is_worker_blocked 로 거부.
# STATE_DIR 은 permission-gate.sh 와 동일 패턴 (${PROJECT_ROOT}/.agent-harness/state).
BLOCK_RETRY_LIMIT=2   # 자동차단 task 재시도 한도. 초과 시 격리(헤드리스 데드락 방지). 운영 튜닝.

# 차단 상태 디렉토리 (STATE_DIR override 가능 — 테스트 격리). 기본은 운영 state.
_block_state_dir() {
  echo "${STATE_DIR:-${PROJECT_ROOT:-.}/.agent-harness/state}"
}

# _valid_worker <worker> — worker명 위생 검사(경로주입 차단). 유효=rc0, 무효=rc1.
# 영숫자·하이픈·언더스코어만 허용 (profiles 식별자 규약). / 나 .. 거부.
_valid_worker() {
  case "$1" in
    ""|*/*|*..*) return 1 ;;
    *) return 0 ;;
  esac
}

# is_worker_blocked <worker> — 차단되어 있으면 rc 0, 아니면 rc 1 (dispatch 가드용).
is_worker_blocked() {
  local worker="$1"
  _valid_worker "$worker" || return 1
  [ -f "$(_block_state_dir)/blocked-workers/${worker}.json" ]
}

# record_block <worker> <task_id> <reason> — 차단 기록 (atomic). 이미 있으면 attempt++.
# 호출처 = LEAD ⓒ 종합 단일 스레드 전제 (같은 워커 동시 record_block 없음). 락 불요(YAGNI).
# 단일 스레드라 read-modify-write race 없음 — attempt 카운터는 격리(K) 판정 근거라 정확성 중요.
record_block() {
  local worker="$1" task_id="$2" reason="$3"
  _valid_worker "$worker" || { echo "record_block: 잘못된 worker명 '$worker'" >&2; return 1; }
  local dir; dir="$(_block_state_dir)/blocked-workers"
  mkdir -p "$dir"
  local f="$dir/${worker}.json" attempt=1
  local qf; qf="$(_block_state_dir)/quarantine/${worker}.json"
  if [ -f "$f" ]; then
    attempt="$(jq -r '.attempt // 1' "$f" 2>/dev/null)"
    # 손상 json 으로 attempt 가 비숫자면 1 로 복구 (set -u 산술평가 치명사 방지).
    [[ "$attempt" =~ ^[0-9]+$ ]] || attempt=1
    attempt=$((attempt + 1))
  elif [ -f "$qf" ]; then
    # 격리 이력 워커 재차단: *같은 task* 면 이전 attempt 누적(무한 차단↔격리 방지),
    # *다른 task* 면 attempt=1 리셋(영속 낙인 방지 — 무관 task 의 1회 차단을 즉시 격리하지 않음).
    local q_task; q_task="$(jq -r '.task_id // empty' "$qf" 2>/dev/null)"
    if [ "$q_task" = "$task_id" ]; then
      attempt="$(jq -r '.attempt // 1' "$qf" 2>/dev/null)"
      [[ "$attempt" =~ ^[0-9]+$ ]] || attempt=1
      attempt=$((attempt + 1))
    fi
    # 다른 task 면 attempt=1 유지(초기값) — 리셋.
  fi
  # reason 에 따옴표/개행 들어가도 jq 가 안전하게 인코딩.
  if jq -n --arg w "$worker" --arg t "$task_id" --argjson a "$attempt" --arg r "$reason" \
    '{worker:$w, task_id:$t, attempt:$a, reason:$r}' > "$f.tmp" 2>/dev/null; then
    mv "$f.tmp" "$f"
  else
    rm -f "$f.tmp" 2>/dev/null   # jq 실패(부재 등) — 쓰레기 .tmp 정리. 차단 기록 실패는 호출처가 인지.
    echo "record_block: jq 실패 — 차단 기록 못 함 (worker=$worker)" >&2
    return 1
  fi
}

# clear_block <worker> — 차단 해제 (재판정 OK). 멱등.
# blocked-workers 와 quarantine 둘 다 청산 — 정상 복귀 시 격리 이력도 비워 영속 낙인 방지.
clear_block() {
  local worker="$1"
  _valid_worker "$worker" || return 0
  rm -f "$(_block_state_dir)/blocked-workers/${worker}.json" 2>/dev/null
  rm -f "$(_block_state_dir)/quarantine/${worker}.json" 2>/dev/null
  return 0
}

# quarantine_block <worker> — blocked-workers → quarantine 이동 (attempt>=K).
# 그 task 만 격리, 워커는 blocked-workers 비워져 다른 task dispatch 가능.
quarantine_block() {
  local worker="$1"
  _valid_worker "$worker" || return 1
  local src; src="$(_block_state_dir)/blocked-workers/${worker}.json"
  [ -f "$src" ] || return 0
  local qdir; qdir="$(_block_state_dir)/quarantine"
  mkdir -p "$qdir"
  mv "$src" "$qdir/${worker}.json"
}

# ===== Task 7: 권한 학습 영구화 (§7) =====
# 4 함수 — bump_stats_counter / append_to_yaml / blocklist_contains / confirm_allow_yaml.
# yq 부재 → awk fallback (Phase B/C 정확도 ↓ 인정).
# 결정은 외부 콜백 (lead pane 신호 경유) — interactive read 미사용.

# yq 검사 (lib.sh source 시 1회 캐시).
USE_YQ="${USE_YQ:-}"
if [ -z "$USE_YQ" ]; then
  if command -v yq >/dev/null 2>&1; then USE_YQ=1; else USE_YQ=0; fi
  export USE_YQ
fi

# bump_stats_counter — Phase A 카운터 갱신
# $1=pattern $2=field (confirm|accepted|rejected|never)
# I-9 정정 — 멀티 워커 동시 호출 시 lost update 차단 (add_to_allow 락 패턴 복제).
bump_stats_counter() {
  local pattern="$1" field="$2"
  local stats; stats="$(_state_config_dir)/orch-auto-allow-stats.yaml"
  [ -f "$stats" ] || return 1

  local lock="${stats}.lock"
  local i=0 max=300   # 300 * 0.05s = 15s 상한
  while ! mkdir "$lock" 2>/dev/null; do
    # stale lock 회수 — add_to_allow 와 동일 정책 (mt>0 가드).
    local mt; mt="$(_mtime_epoch "$lock")"
    if [ "$mt" -gt 0 ]; then
      local age=$(( $(date +%s) - mt ))
      [ "$age" -ge 15 ] && rmdir "$lock" 2>/dev/null || true
    fi
    i=$((i + 1))
    [ "$i" -ge "$max" ] && { echo "bump_stats_counter: lock 획득 실패 ($stats)" >&2; return 1; }
    sleep 0.05
  done

  local rc=0
  if [ "$USE_YQ" = "1" ]; then
    yq eval ".patterns.\"$pattern\".$field |= ((. // 0) + 1)" -i "$stats"
    rc=$?
  else
    # awk fallback — 단순 누적. patterns 노드 존재 가정.
    # 새 패턴이면 append, 기존 패턴이면 field 카운트 +1.
    awk -v p="$pattern" -v f="$field" '
      BEGIN { found_pat=0; field_done=0; in_patterns=0 }
      /^patterns:/ { in_patterns=1; print; next }
      in_patterns && /^[^ ]/ && !/^patterns:/ { in_patterns=0 }
      in_patterns && $0 ~ "  \""p"\":" { found_pat=1; print; next }
      found_pat && $0 ~ "    "f":" {
        # 기존 필드 — 값 +1
        match($0, /[0-9]+$/)
        if (RSTART > 0) {
          n = substr($0, RSTART) + 1
          print substr($0, 1, RSTART-1) n
        } else { print }
        field_done=1; next
      }
      found_pat && /^  [^ ]/ {
        # 다음 패턴 진입 — 현 패턴 끝
        if (!field_done) { print "    "f": 1" }
        found_pat=0; field_done=0
      }
      { print }
      END {
        if (found_pat && !field_done) { print "    "f": 1" }
        else if (!found_pat && in_patterns) {
          print "  \""p"\":"
          print "    "f": 1"
        }
      }
    ' "$stats" > "$stats.tmp" && mv "$stats.tmp" "$stats"
    rc=$?
  fi
  rmdir "$lock" 2>/dev/null || true
  return $rc
}

# append_to_yaml — yaml 카테고리에 패턴 append
# $1=yaml_path $2=pattern $3=category (기본 learned)
append_to_yaml() {
  local yaml="$1" pattern="$2" category="${3:-learned}"
  [ -f "$yaml" ] || return 1
  # I-8 정정 — 멱등성 검사를 *대상 카테고리* 컨텍스트로 좁힘. 다른 카테고리에 같은
  # 패턴이 있어도 대상 카테고리에는 추가 가능. awk `index` 매치로 정규식 함정 회피
  # (`Bash(ls:*)` 의 `*` 가 awk `~` 에서 "0회 이상" 으로 해석되는 문제 차단).
  local in_category
  in_category="$(awk -v c="$category" -v p="  - \"$pattern\"" '
    $0 ~ "^"c":" { in_cat=1; next }
    in_cat && /^[a-z][a-z_-]*:/ { in_cat=0 }
    in_cat && $0 == p { print "found"; exit }
  ' "$yaml")"
  [ "$in_category" = "found" ] && return 0
  if [ "$USE_YQ" = "1" ]; then
    yq eval ".$category += [\"$pattern\"]" -i "$yaml"
  else
    # awk fallback — category 키 다음에 들여쓰기 2칸 + `- "패턴"` append
    awk -v p="$pattern" -v c="$category" '
      BEGIN { found=0 }
      $0 ~ "^"c":" { found=1; print; next }
      found && /^[a-z][a-z_-]*:/ {
        # 다음 카테고리 진입 직전에 패턴 추가
        print "  - \""p"\""
        found=0
      }
      { print }
      END { if (found) print "  - \""p"\"" }
    ' "$yaml" > "$yaml.tmp" && mv "$yaml.tmp" "$yaml"
  fi
}

# blocklist_contains — 사용자 unsubscribe 검사 (Phase C 우회)
# $1=pattern, exit 0=block 매치, exit 1=매치 안 함
blocklist_contains() {
  local pattern="$1"
  local blocklist; blocklist="$(_state_config_dir)/orch-auto-allow-blocklist.yaml"
  [ -f "$blocklist" ] || return 1
  grep -qxF "  - \"$pattern\"" "$blocklist" 2>/dev/null
}

# confirm_allow_yaml — 사용자 결정 후 yaml 영구 추가 + stats 갱신
# $1=pattern $2=decision (accepted|rejected|never)
# blocklist 검사 + 사용자 결정에 따라 yaml/stats 분기.
confirm_allow_yaml() {
  local pattern="$1" decision="$2"
  # P2/P6 수정(2026-05-30) — learned 쓰기 경로를 프로젝트 영구 파일로 분리.
  #   기존: ${HARNESS_ROOT}/config/orch-auto-allow.yaml 에 써서
  #     ① matrix-lookup 읽기(${PROJECT_ROOT}/config)와 불일치 → 학습이 게이트에 미반영(매 task 재프롬프트)
  #     ② 본체 git 추적 yaml 오염(e2e 마다 learned 누적)
  #   수정: ${PROJECT_ROOT}/.agent-harness/learned-allow.yaml 에 쓰고 matrix 가 함께 읽음.
  #   awa-down 이 .agent-harness 디렉토리·learned-allow 를 보존하므로 동일 프로젝트 재부트 시 유지.
  local learned_yaml="${PROJECT_ROOT}/.agent-harness/learned-allow.yaml"

  # Phase C 우회 — blocklist 매치하면 즉시 종료 (어떤 결정이든)
  if blocklist_contains "$pattern"; then
    return 1
  fi

  case "$decision" in
    accepted)
      # C-2 정정 — append 전 사후 검증. learned 카테고리에 추가될 패턴이
      # 다중 probe (--force/-rf/-f/--hard/of=/sh) 로 danger 매치되면 거부.
      # 임시 yaml 사용 — HARNESS_ROOT/config 오염 차단. 거부 시 rejected 카운터 +1.
      # ★ 단위 테스트는 HARNESS_ROOT 를 격리 TMPDIR 로 override 하나 bin/ 은 복사 안 함 →
      #   bin/danger-check.sh 절대 경로는 *lib.sh 가 위치한 디렉터리* 기준으로 해석.
      #   _LIB_DIR 은 lib.sh source 시점에 계산되므로 동일 효과.
      local probe_yaml
      probe_yaml="$(mktemp)"
      printf 'probe:\n  - "%s"\n' "$pattern" > "$probe_yaml"
      if ! bash "${_LIB_DIR}/danger-check.sh" --check-allow-yaml "$probe_yaml" 2>/dev/null; then
        rm -f "$probe_yaml"
        echo "[REJECT] confirm_allow_yaml: 패턴 '$pattern' 다중 probe danger 매치 → 학습 거부" >&2
        bump_stats_counter "$pattern" "rejected" || echo "[WARN] bump_stats_counter rejected failed for: $pattern" >&2
        return 1
      fi
      rm -f "$probe_yaml"
      # learned 파일 없으면 헤더와 함께 생성 (append_to_yaml 은 파일·카테고리 존재 가정).
      if [ ! -f "$learned_yaml" ]; then
        mkdir -p "$(dirname "$learned_yaml")"
        printf '# 프로젝트 학습 패턴 — confirm_allow_yaml accepted 가 누적 (P2/P6 수정 2026-05-30)\nlearned:\n' > "$learned_yaml"
      fi
      append_to_yaml "$learned_yaml" "$pattern" "learned"
      bump_stats_counter "$pattern" "accepted" || echo "[WARN] bump_stats_counter accepted failed for: $pattern" >&2
      ;;
    rejected)
      bump_stats_counter "$pattern" "rejected" || echo "[WARN] bump_stats_counter rejected failed for: $pattern" >&2
      ;;
    never)
      # 사용자 영구 거부 — blocklist 추가
      append_to_yaml "$(_state_config_dir)/orch-auto-allow-blocklist.yaml" "$pattern" "patterns"
      bump_stats_counter "$pattern" "never" || echo "[WARN] bump_stats_counter never failed for: $pattern" >&2
      ;;
    *)
      return 1 ;;
  esac
}

# 계측 (차별성 데이터 spec §5) — events.log 5필드 보호 append.
# confirm_allow_yaml 의 events.log 가드 패턴 모방: events.log 존재 시에만 발화, append 실패 흡수.
# 직접 printf 금지(AGENTS.md HOW NOT) 계약을 이 보호 함수로 지킨다.
# task 폴백(C2): permission-gate hook 은 HARNESS_TASK 부재 → task 가 비거나 '-' 면
#   .harness-task.<worker> 에서 읽는다(log-event.sh:14-19 동형).
# $1=worker(- 가능) $2=task(- 가능) $3=action $4=payload(key=value;...)
log_gate_event() {
  local worker="${1:--}" task="${2:--}" action="$3" payload="${4:-}"
  local root="${PROJECT_ROOT:-$PWD}"
  if [ -z "$task" ] || [ "$task" = "-" ]; then
    local _htf="${root}/.agent-harness/.harness-task.${worker}"
    [ -f "$_htf" ] && task="$(cat "$_htf" 2>/dev/null || true)"
    [ -z "$task" ] && task="-"
  fi
  local events_log="${EVENTS:-${root}/.agent-harness/events.log}"
  [ -f "$events_log" ] || return 0
  printf '%s\t%s\t%s\t%s\t%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$worker" "$task" "$action" "$payload" \
    >> "$events_log" 2>/dev/null || true
}

# team 명세 yaml 파서 (동적 하네스 조합) — 함수 노출. HARNESS_ROOT 는 L7 에서 이미 정의.
# shellcheck disable=SC1090
. "$HARNESS_ROOT/bin/spec-parse.sh"
