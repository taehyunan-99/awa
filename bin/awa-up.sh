#!/usr/bin/env bash
set -euo pipefail

_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --project 옵션 파서 (E7·F2). lib.sh source 이전 실행.
# lib.sh 의 _normalize_project 는 source 후에야 쓸 수 있으므로 별도 inline 함수.
_normalize_project_arg() {
  local raw="${1:-}"
  if [ -z "$raw" ]; then
    echo "오류: --project 인자 누락 (값 필요)" >&2
    return 1
  fi
  if [ ! -d "$raw" ]; then
    echo "오류: --project 경로 없음: $raw" >&2
    return 1
  fi
  ( cd "$raw" && pwd )
}
# --plan 옵션 정규화. 파일 존재 검사 + 절대경로화. --project 의 디렉터리 검사와 대칭.
_normalize_plan_arg() {
  local raw="${1:-}"
  if [ -z "$raw" ]; then
    echo "오류: --plan 인자 누락 (값 필요)" >&2
    return 1
  fi
  if [ ! -f "$raw" ]; then
    echo "오류: --plan 파일 없음: $raw" >&2
    return 1
  fi
  ( cd "$(dirname "$raw")" && printf '%s/%s\n' "$(pwd)" "$(basename "$raw")" )
}
PROFILE_ARG=""
WORKERS_ARG=""
SPEC_FILE=""
DRY_CHECK=0
# set -u 안전성을 위해 루프 앞에 선언 필수 (미선언 배열은 set -u 에서 unbound 오류).
PLAN_FILES=()
while [ $# -gt 0 ]; do
  case "$1" in
    --project)
      if ! HARNESS_PROJECT="$(_normalize_project_arg "${2:-}")"; then exit 1; fi
      export HARNESS_PROJECT; shift 2 ;;
    --project=*)
      if ! HARNESS_PROJECT="$(_normalize_project_arg "${1#--project=}")"; then exit 1; fi
      export HARNESS_PROJECT; shift ;;
    --plan)
      _plan_norm="$(_normalize_plan_arg "${2:-}")" || exit 1
      PLAN_FILES+=("$_plan_norm"); shift 2 ;;
    --plan=*)
      _plan_norm="$(_normalize_plan_arg "${1#--plan=}")" || exit 1
      PLAN_FILES+=("$_plan_norm"); shift ;;
    --workers)
      WORKERS_ARG="${2:-}"; [ -n "$WORKERS_ARG" ] || { echo "오류: --workers 인자 누락" >&2; exit 1; }
      shift 2 ;;
    --workers=*)
      WORKERS_ARG="${1#--workers=}"; shift ;;
    --spec)
      SPEC_FILE="${2:-}"; [ -n "$SPEC_FILE" ] || { echo "오류: --spec 인자 누락" >&2; exit 1; }
      shift 2 ;;
    --spec=*)
      SPEC_FILE="${1#--spec=}"; shift ;;
    --dry-check)
      # Task 7 (§7) — yaml 부정합 가드만 실행 후 종료 (boot 안 함).
      DRY_CHECK=1
      shift ;;
    -*) echo "오류: 알 수 없는 옵션 $1" >&2; exit 1 ;;
    *)
      # 비옵션 인자는 프로파일명. 정상 사용은 1개 — 여분이 오면 무음 무시 대신 경고.
      [ -n "$PROFILE_ARG" ] && echo "경고: 프로파일 인자 여러 개 — '$1' 로 덮어씀(이전: '$PROFILE_ARG')" >&2
      PROFILE_ARG="$1"; shift ;;
  esac
done

source "$_DIR/lib.sh"
[ "$PROJECT_ROOT_VALID" = "1" ] || exit 1

# P1 §2.2: HARNESS_ROOT validation. sed `#` 구분자 안전성 보장.
# {{HARNESS_ROOT}} 치환에서 절대경로의 `/` 가 sed 구분자 `/` 와 충돌하므로 `#` 사용.
# `#` 자체가 HARNESS_ROOT 안에 들어가면 깨지므로 사전 거부 (T1 _validate_path_chars).
# lib.sh 가 이미 stderr 에 오류 사유를 발화함 — 여기선 단순 exit 만 (메시지 책임 일원화, Minor #4).
[ "${HARNESS_ROOT_VALID:-0}" = "1" ] || exit 1

# ★ 재발 방지 가드(B): PROJECT_ROOT 가 하네스 본체로 잡혔으면 경고(가동은 진행).
#   lib.sh 가 PROJECT_ROOT_IS_HARNESS 플래그만 set 하고 출력은 안 한다(resolve-path
#   stdout 오염 회귀 회피, M8/M3b). 가동 진입점인 awa-up 에서만 사용자에게 경고 —
#   본체를 작업 대상으로 가동하면 워커 cwd 가 본체가 돼 2026-05-30 류 사고에 노출.
#   의도적 본체 작업도 있으므로 abort 아닌 경고(--project <tmp> 로 격리 권장).
if [ "${PROJECT_ROOT_IS_HARNESS:-0}" = "1" ]; then
  echo "경고: PROJECT_ROOT 가 하네스 본체($PROJECT_ROOT)로 잡혔습니다." >&2
  echo "  워커 cwd 가 본체가 됩니다 — 의도가 아니면 '--project <경로>' 또는 HARNESS_PROJECT=<경로> 로 격리하세요." >&2
fi

# Task 7 (§7) — yaml 부정합 검사 (boot 직전 가드, C5 PASS 조건).
# allow ∩ deny 충돌 시 ABORT — 사용자가 학습시킨 패턴이 위험 카탈로그와 겹치는 케이스 차단.
ALLOW_YAML="${HARNESS_ROOT}/config/orch-auto-allow.yaml"
if [ -f "$ALLOW_YAML" ]; then
  if ! bash "$_DIR/danger-check.sh" --check-allow-yaml "$ALLOW_YAML"; then
    echo "[ABORT] yaml 부정합 — allow ∩ deny 충돌 발견. boot 거부" >&2
    exit 1
  fi
fi

# prompts 디렉터리 — 기본 $HARNESS_ROOT/prompts, 테스트 fixture 용 PROMPTS_DIR env override.
PROMPTS_DIR="${PROMPTS_DIR:-$HARNESS_ROOT/prompts}"

# 3분기: --spec / --workers / profile(yaml 우선·sh 하위호환).
# REVIEWERS 미설정 — 기존 ${REVIEWERS+x} 가드가 빈/미정의를 안전 처리.
if [ -n "${SPEC_FILE:-}" ]; then
  [ -n "${PROFILE_ARG:-}" ] && { echo "오류: --spec 와 프로파일 동시 지정 불가" >&2; exit 1; }
  [ -n "${WORKERS_ARG:-}" ] && { echo "오류: --spec 와 --workers 동시 지정 불가" >&2; exit 1; }
  PROFILE="(spec)"
  spec_parse_load "$SPEC_FILE" || exit 1     # WORKERS/REVIEWERS/SESSION/LAYOUT 정의 (같은 셸 — 배열 보존)
elif [ -n "${WORKERS_ARG:-}" ]; then
  [ -n "${PROFILE_ARG:-}" ] && { echo "오류: --workers 와 프로파일 동시 지정 불가" >&2; exit 1; }
  PROFILE="(custom)"                    # 종료 메시지(팀 '$PROFILE' 가동 완료)용 라벨.
  # ORCH_MODEL/DESK_MODEL 디폴트 미지정 — EFF 폴백이 빈값을 보고 vendor_default_model 로 채움.
  WORKERS=()
  IFS=',' read -ra _wk <<< "$WORKERS_ARG"
  for _w in "${_wk[@]}"; do WORKERS+=("$_w"); done
  SESSION=""                            # profile SESSION 없음 — PROFILE_SESSION 빈값으로.
else
  PROFILE="${PROFILE_ARG:-default}"
  # PROFILE 이 실재 파일 경로면 그대로, 아니면 profiles/<이름>.yaml → .sh 우선순위로 해석.
  if [ -f "$PROFILE" ]; then
    PROFILE_FILE="$PROFILE"
  else
    if [ -f "$HARNESS_ROOT/profiles/$PROFILE.yaml" ]; then
      PROFILE_FILE="$HARNESS_ROOT/profiles/$PROFILE.yaml"
    else
      PROFILE_FILE="$HARNESS_ROOT/profiles/$PROFILE.sh"
    fi
  fi

  if [ ! -f "$PROFILE_FILE" ]; then
    echo "오류: 프로파일 없음 → $PROFILE_FILE" >&2
    echo "사용 가능: $(ls "$HARNESS_ROOT/profiles" 2>/dev/null | sed 's/\.\(sh\|yaml\)$//' | sort -u | tr '\n' ' ')" >&2
    exit 1
  fi

  # 프로파일 로드: yaml → spec_parse_load, sh → source (하위호환)
  case "$PROFILE_FILE" in
    *.yaml) spec_parse_load "$PROFILE_FILE" || exit 1 ;;
    # shellcheck disable=SC1090
    *)      source "$PROFILE_FILE" ;;
  esac
fi

# --dry-check: 파싱·검증 완료 후 boot 없이 종료. WORKERS 가 채워진 뒤여야 의미.
if [ "${DRY_CHECK:-0}" = "1" ]; then
  _rev_count=0
  if [ -n "${REVIEWERS+x}" ]; then _rev_count="${#REVIEWERS[@]}"; fi
  echo "[dry-check] PASS — workers=${#WORKERS[@]} reviewers=$_rev_count"
  exit 0
fi

# 프로파일이 정의한 SESSION 을 resolve_session 체인에 노출 (이슈 2, T2).
export PROFILE_SESSION="${SESSION:-}"
SESSION="$(resolve_session)"

# 워커 명령 (기본 claude, 테스트는 AGENT_CMD 로 더미 치환)
AGENT_CMD="${AGENT_CMD:-claude}"

# "이름:역할[:벤더][:모델]" 파싱. (spec §2.2 화이트리스트 모호성 해소)
parse_entry() {  # $1=entry → ENTRY_NAME ENTRY_ROLE ENTRY_VENDOR ENTRY_MODEL 설정
  local e="$1"
  ENTRY_NAME="${e%%:*}"
  local rest="${e#*:}"
  ENTRY_ROLE="${rest%%:*}"
  ENTRY_VENDOR=""
  if [ "$rest" = "$ENTRY_ROLE" ]; then
    # 2필드 (이름:역할) — 모델 미지정, 벤더 빈값. 폴백 체인(L530)이 해석된 벤더의
    # vendor_default_model 로 채움(P9 수정 2026-05-30: codex 벤더 워커가 sonnet 하드코딩 →
    # "model not supported" 400 에러였음. 빈값으로 두면 claude=sonnet·codex=gpt-5.5 정상 상속).
    ENTRY_MODEL=""
  else
    local f3 after_role="${rest#*:}"
    f3="${after_role%%:*}"
    if [ "$after_role" = "$f3" ]; then
      # 3필드 (이름:역할:X) — §2.2: X 가 알려진 벤더면 벤더, 아니면 모델.
      if is_known_vendor "$f3"; then
        ENTRY_VENDOR="$f3"; ENTRY_MODEL=""      # 모델은 폴백 체인이 채움
      else
        ENTRY_MODEL="$f3"                        # 역호환: 3번째=모델
      fi
    else
      # 4필드 (이름:역할:벤더:모델).
      ENTRY_VENDOR="$f3"; ENTRY_MODEL="${after_role#*:}"
    fi
  fi
  # 5필드 이상 거부 — ENTRY_MODEL 에 콜론 잔존 = 필드 초과(오타 silent 수용 차단).
  case "$ENTRY_MODEL" in
    *:*)
      echo "오류: 엔트리 '$e' 필드 초과 (이름:역할[:벤더][:모델] 4필드까지)" >&2
      exit 1
      ;;
  esac
  # ENTRY_NAME 은 path 아닌 워커 이름 — sed `#` 구분자·tmux pane title·boot 파일명에 쓰이므로
  # 좁게 [A-Za-z0-9_-] 만 허용 (메타문자 사전 차단, T3 Important 2).
  case "$ENTRY_NAME" in
    ""|*[!A-Za-z0-9_-]*)
      echo "오류: 워커 이름 '$ENTRY_NAME' 허용 문자 외 ([A-Za-z0-9_-] 만)" >&2
      exit 1
      ;;
  esac
  # ENTRY_ROLE 도 sed `#` 구분자에 직접 삽입되므로 ENTRY_NAME 과 동일 문자셋으로 제한.
  # (#, &, \, " 등이 sed s#...#$role#g 를 파손 — generate_worker_settings 의 -e "s#{{ENTRY_ROLE}}#$role#g").
  case "$ENTRY_ROLE" in
    ""|*[!A-Za-z0-9_-]*)
      echo "오류: 역할 이름 '$ENTRY_ROLE' 허용 문자 외 ([A-Za-z0-9_-] 만)" >&2
      exit 1
      ;;
  esac
  return 0
}

# 벤더 디스패처: 해석된 벤더 어댑터를 source 하고 vendor_boot_cmd 호출.
# $1=model $2=settings_path $3=session_id $4=plan_file(opt) $5=vendor(opt)
agent_cmd_for() {
  local model="$1" settings="${2:-}" sid="${3:-}" plan="${4:-}" vendor="${5:-}"
  [ -n "$vendor" ] || vendor="${HARNESS_VENDOR:-claude}"
  vendor_source "$vendor" || return 1
  vendor_boot_cmd "$model" "$settings" "$sid" "$plan"
}

# 중복 세션 거부
if tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "오류: 세션 '$SESSION' 이미 존재 (PROJECT_ROOT=$PROJECT_ROOT). attach 하거나 awa-down.sh 후 재시도." >&2
  exit 1
fi

# PROJECT_ROOT/.claude/settings.json 을 생성 (D2) + marker 기록 (사용자 보호 게이트).
# ★ 6차: hook(PreToolUse permission-gate + PostToolUse log-event)은 전부 워커 --settings 로 이관됨.
#   claude 는 hooks 를 스코프 간 병합하지 않고 최고 우선순위(--settings=command-line)가 통째로
#   이긴다(실측 — probe-hook-merge.sh). 모든 에이전트가 --settings 로 뜨므로 이 파일의 hooks 는
#   절대 적용 안 됨(죽은 설정). 따라서 settings.json.tpl 은 빈 {} — hook 을 여기 두면 "왜 안 먹지"
#   혼란만 남는다. 이 파일의 유일한 실역할은 (1) marker 생성 트리거 (2) 사용자 기존 settings.json
#   보호 게이트(아래 marker 없으면 덮어쓰기 거부)다.
# 사용자 기존 settings.json 보호: marker 없으면 덮어쓰기 거부.
if [ -f "$HARNESS_ROOT/templates/settings.json.tpl" ]; then
  MARKER="$PROJECT_ROOT/.claude/.agent-harness-marker"
  if [ -f "$PROJECT_ROOT/.claude/settings.json" ] && [ ! -f "$MARKER" ]; then
    echo "오류: $PROJECT_ROOT/.claude/settings.json 이미 존재 (하네스 생성물 아님)." >&2
    echo "  수동 처리 필요. 우리 hook 을 머지하거나 사용자 설정 백업 후 재시도." >&2
    exit 1
  fi
  mkdir -p "$PROJECT_ROOT/.claude"
  # sed # 구분자 안전성: T2 path validation 의 [A-Za-z0-9/._-] 가 # 제외 보장.
  # 토큰 컨벤션 {{...}} — P1 부트 토큰 패턴과 통일 (4차 P0 §2.5).
  sed -e "s#{{PROJECT_ROOT}}#$PROJECT_ROOT#g" \
      -e "s#{{HARNESS_ROOT}}#$HARNESS_ROOT#g" \
      "$HARNESS_ROOT/templates/settings.json.tpl" \
      > "$PROJECT_ROOT/.claude/settings.json"
  # 토큰 잔존 검증 — 빈 {} 라 정상적으로는 토큰 0개. 잔존하면 템플릿 오류 (fail-fast 유지).
  if grep -qE '\{\{[A-Z_]+\}\}' "$PROJECT_ROOT/.claude/settings.json"; then
    echo "오류: $PROJECT_ROOT/.claude/settings.json 토큰 미치환: $(grep -oE '\{\{[A-Z_]+\}\}' "$PROJECT_ROOT/.claude/settings.json" | sort -u | tr '\n' ' ')" >&2
    rm -f "$PROJECT_ROOT/.claude/settings.json"
    exit 1
  fi
  printf 'generated by agent-harness — do not edit settings.json (regenerated by bin/awa-up.sh)\n' > "$MARKER"
fi

# 12차: 타깃 .gitignore 에 하네스 산출물 멱등 자동추가 (git repo 만). 구 "안내" → "자동".
if [ "$PROJECT_ROOT_IS_GIT" = "1" ]; then
  _gi="$PROJECT_ROOT/.gitignore"
  # 기존 파일이 newline 없이 끝나면 첫 append 가 마지막 줄에 병합됨 → 사전 보정.
  if [ -f "$_gi" ] && [ -n "$(tail -c1 "$_gi" 2>/dev/null)" ]; then
    printf '\n' >> "$_gi"
  fi
  for _pat in ".agent-harness/" ".claude/"; do
    if [ ! -f "$_gi" ] || ! grep -qxF "$_pat" "$_gi" 2>/dev/null; then
      printf '%s\n' "$_pat" >> "$_gi"
    fi
  done
fi

# WORKSPACE 하위 디렉터리 생성은 marker 게이트 통과 후로 이동 (4차 리뷰).
# 이유: 거부 케이스에서 mkdir 부작용 leak 차단 — spec D2·E8 사용자 보호.
mkdir -p "$WORKSPACE/.boot" "$WORKSPACE/tasks" "$WORKSPACE/results" "$WORKSPACE/review"
# 6차: 게이트 state 디렉터리 (lead 가 매 사이클 ls — 데몬이 만들던 것을 이관). marker 게이트 통과 후라 leak 없음.
mkdir -p "$WORKSPACE/state/pending-asks" "$WORKSPACE/state/incidents" "$WORKSPACE/state/removal-requests"
# splash 팀 요약 파일 — attach 시 display-popup 안의 awa-splash.sh 가 읽는다.
# HOME 캐시에 둔다(awa-down 이 WORKSPACE 를 지워도 attach 첫 화면이 안전).
# splash 는 보조 기능 — 캐시 쓰기 실패가 set -e 로 부팅을 죽이면 안 된다. || true 로 흡수.
SPLASH_TEAM_FILE="$HOME/.cache/awa/team-summary.txt"
mkdir -p "$(dirname "$SPLASH_TEAM_FILE")" 2>/dev/null || true
: > "$SPLASH_TEAM_FILE" 2>/dev/null || true

# 멤버 한 줄 append: 이름<TAB>역할<TAB>모델. role 빈값(ORCH/DESK)은 orch/desk 으로 정규화.
# 쓰기 실패는 흡수(set -e 하에서 부팅 보호). splash 가 파일 부재 시 멤버 표만 생략.
splash_append_member() {  # $1=이름 $2=역할(bare, 빈값 가능) $3=모델
  local _n="$1" _r="${2:-}" _m="${3:-}"
  case "$_n" in
    ORCH) _r="orch" ;;
    DESK) _r="desk" ;;
  esac
  printf '%s\t%s\t%s\n' "$_n" "$_r" "$_m" >> "$SPLASH_TEAM_FILE" 2>/dev/null || true
}
# I-10 정정 — events.log 빈 파일 생성 보장. add_to_allow 가 `[ -f events.log ]` 가드로
# 신호 발화 — boot 직후 events.log 미생성 시 첫 호출 신호 silent drop. touch 로 빈 파일
# 생성하면 watcher 의 last_events 초기화(현재 줄 수=0) 와 정합 — 과거 done 폭주 없음.
touch "$WORKSPACE/events.log"

# 5차→8차: orch-auto-allow.yaml 설치 + marker 게이트 + 백업 갱신.
# orch_auto_allow_lookup 은 ${PROJECT_ROOT}/.agent-harness/config/orch-auto-allow.yaml 을 읽으므로,
#   파일이 없으면 lookup 이 영구 rc=1 → orch-auto-allow 전체 무동작. 부트 시 설치.
# 8차: settings.json marker 정책과 진짜로 통일(이전 주석은 "보존"이라 정반대였음).
#   marker 있음(하네스 생성물) = 재가동 시 하네스 최신으로 갱신(안전정책 전파).
#   marker 없음 + yaml 있음 = 사용자 직접 작성 → 보호(경고만, settings.json 게이트와 동일).
#   yaml 은 사용자 커스텀 가능(settings.json.tpl 은 빈 {} 라 다름) → 갱신 시 .bak 백업.
HARNESS_YAML="$HARNESS_ROOT/config/orch-auto-allow.yaml"
PROJ_YAML="$PROJECT_ROOT/.agent-harness/config/orch-auto-allow.yaml"
YAML_MARKER="$PROJECT_ROOT/.agent-harness/config/.orch-auto-allow-marker"
if [ -f "$HARNESS_YAML" ]; then
  mkdir -p "$PROJECT_ROOT/.agent-harness/config"
  if [ ! -f "$PROJ_YAML" ]; then
    # 최초 설치.
    cp "$HARNESS_YAML" "$PROJ_YAML"
    printf 'generated by agent-harness — do not edit (regenerated by bin/awa-up.sh)\n' > "$YAML_MARKER"
  elif [ -f "$YAML_MARKER" ]; then
    # 하네스 생성물: 내용 다를 때만 백업 후 갱신 (동일하면 .bak 더미 방지).
    # .bak 은 사람이 보고 복원하는 용도라 가독 날짜형식. 1초 이내 재실행 시 .bak 덮어써짐 — 비현실적 엣지로 수용.
    if ! cmp -s "$HARNESS_YAML" "$PROJ_YAML"; then
      cp "$PROJ_YAML" "${PROJ_YAML}.$(date +%Y%m%dT%H%M%S).bak"
      cp "$HARNESS_YAML" "$PROJ_YAML"
      printf 'generated by agent-harness — do not edit (regenerated by bin/awa-up.sh)\n' > "$YAML_MARKER"
    fi
  else
    # marker 없음 + yaml 있음 = 사용자 직접 작성 → 보호(덮어쓰지 않음, 경고만).
    echo "안내: $PROJ_YAML 이 하네스 생성물이 아님(marker 없음) — 보존합니다." >&2
    echo "  하네스 최신 안전정책으로 갱신하려면 이 파일을 지운 뒤(또는 marker 생성 후) 재가동하세요." >&2
  fi
fi

# P2/P6 수정(2026-05-30) — 프로젝트 학습 allow 파일 초기화.
#   confirm_allow_yaml accepted 가 여기에 누적, matrix-lookup 이 함께 읽음.
#   기본 카탈로그(PROJ_YAML)와 분리 → 부트 덮어쓰기 영향 없음 + 본체 yaml 무오염.
#   이미 있으면 보존(동일 프로젝트 재부트 시 학습 유지) — awa-down 도 이 파일 보존.
LEARNED_YAML="$PROJECT_ROOT/.agent-harness/learned-allow.yaml"
if [ ! -f "$LEARNED_YAML" ]; then
  mkdir -p "$PROJECT_ROOT/.agent-harness"
  printf '# 프로젝트 학습 패턴 — confirm_allow_yaml accepted 가 누적 (P2/P6 수정 2026-05-30)\nlearned:\n' > "$LEARNED_YAML"
fi

# lead 페인으로 세션 생성. 셸 유지.
tmux new-session -d -s "$SESSION" -c "${PROJECT_ROOT}" -x 220 -y 50 -n team

# 인덱스 규약 세션 로컬 고정: 사용자 전역 ~/.tmux.conf 의
# base-index/pane-base-index(예: 1) 와 무관하게 window 0 / pane 1 보장.
# move-window -r 로 이미 생성된 윈도우를 base-index(0)부터 재정렬.
fix_session_indexing "$SESSION"

# 적용 검증: window 0 이 실제로 존재하지 않으면 즉시 실패 (추측 우회 금지).
_w="$(tmux list-windows -t "$SESSION" -F '#{window_index}' | head -1)"
if [ "$_w" != "0" ]; then
  echo "오류: 세션 로컬 인덱스 고정 실패 (window=$_w, 기대=0). tmux 버전/설정 확인 필요." >&2
  tmux kill-session -t "$SESSION" 2>/dev/null || true
  exit 1
fi

# pane title 자동 리네임 세션 로컬 off: 워커 셸의 OSC title escape 가
# select-pane -T 로 지정한 워커명 title 을 덮어쓰지 못하게 함 (spec §6 전제).
fix_session_titles "$SESSION"

# lead 페인의 영속 pane_id 캡처 후 id 로 title 설정.
ORCH_PID="$(tmux display-message -p -t "$SESSION:0.1" '#{pane_id}')"
tmux select-pane -t "$ORCH_PID" -T "ORCH"
# 대시보드 grid 식별용 — title 매칭 대신 기계 식별 단일 출처 (awa-dashboard.sh 가 신뢰).
tmux set-option -p -t "$ORCH_PID" @awa-role orch 2>/dev/null || true

# pm pane: window 0(team) 에 lead 옆으로 가로 split (사용자 창구). pane_id 캡처(layout 면역).
# 14차 UX: -h 가로 명시. window 0 = LEAD+PM 만 (관제탑 swap-pane 단위).
DESK_PID="$(tmux split-window -h -t "$SESSION:0" -d -P -F '#{pane_id}')"
tmux select-pane -t "$DESK_PID" -T "DESK"
tmux set-option -p -t "$DESK_PID" @awa-role desk 2>/dev/null || true
tmux select-layout -t "$SESSION:0" even-horizontal

# 14차 UX: 워커 페인은 별도 windows 윈도우(1)에 세로 스택.
# 첫 워커는 new-window 의 auto-create pane 의 title 만 설정(pane_id 재캡처),
# 둘째부터 -v split 누적. watcher 는 워커 다 split 한 뒤 마지막 -v split → 최하단.
tmux new-window -t "$SESSION" -n workers
# allow-set-title 은 window-level 옵션 → 새 윈도우는 global 상속.
# workers 윈도우를 활성으로 두고 fix_session_titles 재적용.
fix_session_titles "$SESSION"

# workers 윈도우 생성 가드 (BSD grep -c 함정 회피 — wc -l 사용).
_wcount="$(tmux list-windows -t "$SESSION" -F '#{window_name}' 2>/dev/null \
  | grep '^workers$' | wc -l | tr -d ' ')"
if [ "$_wcount" != "1" ]; then
  echo "오류: workers 윈도우 생성 실패" >&2
  tmux kill-session -t "$SESSION" 2>/dev/null || true
  exit 1
fi

# bash 3.2(macOS 기본) 는 연관배열 미지원 → 인덱스 정렬 일반 배열 2개 사용.
WORKER_NAMES=()
WORKER_PIDS=()
_prev_worker_pid=""
first_w=1
for entry in "${WORKERS[@]}"; do
  parse_entry "$entry"
  if [ "$first_w" = "1" ]; then
    # workers 윈도우 auto-create pane 재사용.
    pid="$(tmux display-message -p -t "$SESSION:workers" '#{pane_id}')"
    first_w=0
  else
    # 이전 워커 pane_id 를 명시 타겟 → split 순서(상→하) 보장 (-d: focus 이동 없음).
    pid="$(tmux split-window -v -t "$_prev_worker_pid" -d -P -F '#{pane_id}')"
  fi
  tmux select-pane -t "$pid" -T "$ENTRY_NAME"
  WORKER_NAMES+=("$ENTRY_NAME")
  WORKER_PIDS+=("$pid")
  _prev_worker_pid="$pid"
done

# continuum 오염 방지.
tmux set-option -t "$SESSION" @continuum-save-interval '0' 2>/dev/null || true

# 12차: PROJECT_ROOT (풀경로) — /awa (Step 0 resume) 또는 /awa bookmarks list 가 읽음.
tmux set-option -t "$SESSION" @awa-project "$PROJECT_ROOT" 2>/dev/null || true
# 14차 UX: basename — pane-border-format 의 #{@awa-project-name} 으로 사용.
tmux set-option -t "$SESSION" @awa-project-name "$(basename "$PROJECT_ROOT")" 2>/dev/null || true

# review 윈도우 생성 — REVIEWERS 정의·비어있지 않을 때만.
REV_NAMES=()
REV_PIDS=()
REVIEW_MANAGER_PANE=""   # I-3 정정: review-manager 역할 pane 별도 추출 (drift-check 전용 깨움)
EXPECTED_VOTERS=0   # 투표 리뷰어(alignment/quality/security) 수 — watcher quorum 기준.
if [ -n "${REVIEWERS+x}" ] && [ "${#REVIEWERS[@]}" -gt 0 ]; then
  tmux new-window -t "$SESSION" -n reviewers
  # allow-set-title 은 window-level 옵션 → 새 윈도우는 global 상속.
  fix_session_titles "$SESSION"
  first=1
  _prev_rev_pid=""
  for entry in "${REVIEWERS[@]}"; do
    parse_entry "$entry"
    if [ "$first" = "1" ]; then
      pid="$(tmux display-message -p -t "$SESSION:reviewers" '#{pane_id}')"
      first=0
    else
      # 이전 리뷰어 pane_id 명시 타겟 → split 순서(상→하) 보장.
      pid="$(tmux split-window -v -t "$_prev_rev_pid" -d -P -F '#{pane_id}')"
    fi
    tmux select-pane -t "$pid" -T "$ENTRY_NAME"
    REV_NAMES+=("$ENTRY_NAME")
    REV_PIDS+=("$pid")
    # I-3: review-manager 역할 pane_id 별도 보존 (watcher 가 drift-check 분기에서만 사용).
    # REVIEWERS 배열에는 유지 (다른 reviewer 와 함께 부트되도록) — watcher 가 디바운스 분기에서 제외.
    [ "$ENTRY_ROLE" = "review-manager" ] && REVIEW_MANAGER_PANE="$pid"
    case "$ENTRY_ROLE" in
      reviewer-alignment|reviewer-quality|reviewer-security) EXPECTED_VOTERS=$((EXPECTED_VOTERS+1)) ;;
    esac
    _prev_rev_pid="$pid"
  done
  tmux select-layout -t "$SESSION:reviewers" even-vertical
fi

# claude REPL 준비 대기(trust 통과 + ready 폴링)는 bin/vendors/claude.sh 의
#   vendor_wait_ready 로 이관됨 (벤더 어댑터 규약). 화면 패턴·sleep·반복은 그곳이 단일 진실원.
#   회귀 가드: tests/test-wait-repl-patterns.sh (T5-T7 이 vendor_wait_ready 본문 검사).

# P2 §2.2: pane 부트스트랩 — 셸 ready 폴링 + Enter-만 재전송 안전망.
# 세 경로(워커/lead/리뷰어)에 동일한 흐름을 일원화.
#   $1=pane_id  $2=worker_name(HARNESS_WORKER 값)  $3=실행할 agent_cmd  $4=역할 라벨(메시지용)
# 흐름:
#   1) shell_ready_wait 로 셸·claude PATH 준비 확인 (claude 분기). timeout 시 SKIPPED_PANES 누적·return 0.
#   2) export HARNESS_WORKER + cd && cmd 송신 (1차, 정상 흐름).
#   3) BOOT_REPL_CHECK_DELAY(기본 5초) 후 capture 검사. claude REPL 흔적 미검출 시
#      Enter 만 1회 재전송 — 명령은 들어갔으나 Enter 만 사라진 케이스 보강.
#      새 명령 재송신 안 함 (REPL 입력란 박힘 차단).
#   4) wait_repl 로 trust 통과 + REPL ready 폴링 (기존 동작).
# cat 더미 분기는 claude PATH 없어 shell_ready_wait 가 timeout 되므로 skip,
# 기존 sleep 0.2 흐름 유지 (테스트 호환).
# SKIPPED_PANES 누적 → T5 (awa-up 끝부분 가시화) 가 소비. 본 함수 단독으론 변수만 누적.
# shell_ready_wait 의 timeout 동작은 tests/test-shell-ready-wait.sh 가 단위 커버 (T2.2·T2.3).
#   본 함수는 integration 수준 — Final probe (probe-cold-start-timing) 가 측정.
# 본 함수는 4 책임 (shell ready 폴링, claude 송신, Enter 재시도, REPL 폴링) 통합.
#   T5 후 회고적 정리에서 _send_worker_cmd / _boot_repl_ready 로 분해 검토.
bootstrap_pane() {  # $1=pane_id $2=worker_name $3=cmd $4=role_label $5=role $6=model $7=vendor(opt)
  local pid="$1" wname="$2" cmd="$3" label="$4" role="${5:-}" model="${6:-}" vendor="${7:-}"
  [ -n "$vendor" ] || vendor="${HARNESS_VENDOR:-claude}"
  # _test 강제 규칙 (vendor_source 와 동일) — AGENT_CMD 가 claude 아닌 값이면 더미 경로.
  if [ -n "${AGENT_CMD:-}" ] && [ "${AGENT_CMD}" != "claude" ]; then vendor="_test"; fi
  if [ "$vendor" = "_test" ]; then
    # 더미(cat) 경로: shell_ready_wait skip (claude PATH 부재 → 무의미 timeout 회피).
    tmux send-keys -t "$pid" -l "export HARNESS_WORKER=$wname"
    tmux send-keys -t "$pid" Enter
    tmux send-keys -t "$pid" -l "cd \"$PROJECT_ROOT\" && $cmd"
    tmux send-keys -t "$pid" Enter
    sleep 0.2
    return 0
  fi
  # CLI 바이너리 존재 검증 — 벤더별(claude→claude, codex→codex). codex 워커가 claude PATH
  #   부재 환경에서도 부트되도록 벤더명을 cli_bin 으로 넘긴다(=현재 벤더명이 곧 바이너리명).
  if ! shell_ready_wait "$pid" "" "$vendor"; then
    echo "경고: '$wname' pane shell_ready_wait timeout($vendor CLI 부재?) — 송신 skip" >&2
    SKIPPED_PANES="${SKIPPED_PANES:-} $wname"
    return 0   # 다른 pane 진행 (기존 동작 유지·set -e 충돌 회피).
  fi
  tmux send-keys -t "$pid" -l "export HARNESS_WORKER=$wname"
  tmux send-keys -t "$pid" Enter
  # 셸 splash 미주입 — attach 첫 화면은 client-attached 훅의 display-popup 이 담당
  # (셸 splash 는 claude 출력에 scrollback 으로 밀려 첫 화면 보존 실패 → popup 으로 이전).
  tmux send-keys -t "$pid" -l "cd \"$PROJECT_ROOT\" && $cmd"
  tmux send-keys -t "$pid" Enter
  # 2차: capture 검사 전 짧은 대기. CLI 기동·trust 화면 출력 여유.
  sleep "${BOOT_REPL_CHECK_DELAY:-5}"
  # 3차: Enter-만 재전송 안전망. claude 전용 화면 패턴이므로 claude 벤더에서만 검사
  #   (codex 의 trust/ready 는 vendor_wait_ready 가 담당 — 벤더별 화면 문자열 분리).
  if [ "$vendor" = "claude" ] && ! tmux capture-pane -p -S -200 -t "$pid" 2>/dev/null | \
       grep -qE 'trust this folder|Yes, I trust|bypass permissions on|accept edits on|Claude Code v[0-9]|Welcome back'; then
    tmux send-keys -t "$pid" Enter
  fi
  # 4차: REPL ready 폴링 — 벤더 어댑터 위임 (claude 는 vendor_wait_ready = 기존 wait_repl).
  vendor_source "$vendor" || { echo "경고: $label '$wname' 벤더 source 실패" >&2; return 0; }
  vendor_wait_ready "$pid" || echo "경고: $label '$wname' pane REPL 준비 실패(trust/기동 확인 필요)" >&2
  return 0
}

# 워커별 부트스트랩 합본 생성 + 치환, claude 실행, boot 읽기 지시 주입.
# 타겟은 split 단계에서 캡처한 pane_id (index 재배열 면역).
# 워커 boot 는 1차 그대로: _common.md + roles/<역할>.md + {{WORKER_NAME}} 치환.
i=0
for entry in "${WORKERS[@]}"; do
  parse_entry "$entry"
  bf="$(boot_file "$ENTRY_NAME")"
  # sed 구분자 `#`: {{HARNESS_ROOT}} 치환 시 절대경로의 `/` 충돌 회피.
  # HARNESS_ROOT_VALID 게이트가 `#` 포함을 사전 차단함.
  _role_file="$(resolve_role_file "$PROMPTS_DIR" "$ENTRY_ROLE")" || { echo "오류: 워커 '$ENTRY_NAME' 역할파일 해석 실패" >&2; exit 1; }
  cat "$PROMPTS_DIR/_common.md" "$_role_file" \
    | sed -e "s#{{WORKER_NAME}}#$ENTRY_NAME#g" \
          -e "s#{{SESSION}}#$SESSION#g" \
          -e "s#{{HARNESS_ROOT}}#$HARNESS_ROOT#g" > "$bf"
  # 토큰 잔존 검증 (P1 §3 에러 매트릭스): 하네스 예약 토큰만 화이트리스트로 fail (Minor #5).
  # 정상 prompt 의 `{{example}}` 등은 무시 — WORKER_NAME/SESSION/HARNESS_ROOT 셋만 검사.
  if grep -qE '\{\{(WORKER_NAME|SESSION|HARNESS_ROOT)\}\}' "$bf"; then
    echo "오류: $bf 에 토큰 미치환 잔존: $(grep -oE '\{\{(WORKER_NAME|SESSION|HARNESS_ROOT)\}\}' "$bf" | sort -u | tr '\n' ' ')" >&2
    exit 1
  fi

  tgt="${WORKER_PIDS[$i]}"
  # 4차 P0: 워커 역할 → settings 사본 *항상* 도출 (AGENT_CMD 무관 — 테스트 가능성).
  settings_path=""
  # settings 생성을 벤더에 위임 (claude=generate_worker_settings, codex=config.toml+hooks.json).
  # gen_settings 실패 시 워커 가동 거부(fail-safe).
  if ! vendor_source "${ENTRY_VENDOR:-${HARNESS_VENDOR:-claude}}"; then
    echo "오류: '$ENTRY_NAME' 벤더 source 실패 — 부트 skip" >&2
    SKIPPED_PANES="${SKIPPED_PANES:-} $ENTRY_NAME"; i=$((i + 1)); continue; fi
  if ! settings_path="$(vendor_gen_settings "$ENTRY_ROLE" "$ENTRY_NAME")"; then
    echo "오류: '$ENTRY_NAME' settings 생성 실패(fail-safe) — 부트 skip" >&2
    SKIPPED_PANES="${SKIPPED_PANES:-} $ENTRY_NAME"; i=$((i + 1)); continue; fi
  # 6차: 세션 ID 를 우리가 지정 → jsonl 파일명이 이 uuid 로 결정 (디버그 추적성). 데몬 discovery 폐기로 경로 계산은 불필요.
  worker_sid="$(uuidgen | tr 'A-Z' 'a-z')"
  # 모델 미지정(3필드 벤더·4필드 빈모델) → 해석된 벤더의 역할 기본 모델로 폴백.
  if [ -z "$ENTRY_MODEL" ]; then
    vendor_source "${ENTRY_VENDOR:-${HARNESS_VENDOR:-claude}}" 2>/dev/null \
      && ENTRY_MODEL="$(vendor_default_model "$ENTRY_ROLE")"
    [ -n "$ENTRY_MODEL" ] || ENTRY_MODEL="sonnet"
  fi
  # claude 면 역할을 --append-system-prompt-file 로 시스템 주입(injection 우회), codex 면 빈값(send_prompt 경로).
  _wv="${ENTRY_VENDOR:-${HARNESS_VENDOR:-claude}}"
  _sysprompt=""; [ "$_wv" = "claude" ] && _sysprompt="$bf"
  cmd="$(agent_cmd_for "$ENTRY_MODEL" "$settings_path" "$worker_sid" "$_sysprompt" "${ENTRY_VENDOR:-}")" || {
    echo "오류: '$ENTRY_NAME' 벤더 명령 조립 실패 — 부트 skip" >&2
    SKIPPED_PANES="${SKIPPED_PANES:-} $ENTRY_NAME"; i=$((i + 1)); continue; }
  bootstrap_pane "$tgt" "$ENTRY_NAME" "$cmd" "워커" "$ENTRY_ROLE" "$ENTRY_MODEL" "${ENTRY_VENDOR:-}"
  splash_append_member "$ENTRY_NAME" "$ENTRY_ROLE" "$ENTRY_MODEL"
  claude_systemprompt_boot "$_wv" "$tgt" "$bf" "준비되면 다음 지시를 대기하라."
  i=$((i + 1))
done

# 메인(LEAD) 부트: _common.md 제외. lead.md + 워커 카탈로그.
catalog=""
for entry in "${WORKERS[@]}"; do
  parse_entry "$entry"
  desc="$(head -1 "$(resolve_role_file "$PROMPTS_DIR" "$ENTRY_ROLE")" 2>/dev/null || true)"
  catalog+="- $ENTRY_NAME (역할 $ENTRY_ROLE): $desc"$'\n'
done
obf="$(boot_file LEAD)"
{ cat "$(resolve_role_file "$PROMPTS_DIR" orch)" 2>/dev/null || true
  cat "$PROMPTS_DIR/_partials/orch-gate.md" 2>/dev/null || true
  printf '\n## 현재 팀 카탈로그\n%s\n' "$catalog"; } > "$obf"
# lead boot 도 {{HARNESS_ROOT}}·{{SESSION}} 치환 + 토큰 잔존 검증 (일관성).
_tmp_obf="$obf.tmp"
sed -e "s#{{SESSION}}#$SESSION#g" \
    -e "s#{{HARNESS_ROOT}}#$HARNESS_ROOT#g" \
    "$obf" > "$_tmp_obf" && mv "$_tmp_obf" "$obf"
# 화이트리스트 검증 (Minor #5): 하네스 예약 토큰만 fail.
if grep -qE '\{\{(WORKER_NAME|SESSION|HARNESS_ROOT)\}\}' "$obf"; then
  echo "오류: $obf 에 토큰 미치환 잔존: $(grep -oE '\{\{(WORKER_NAME|SESSION|HARNESS_ROOT)\}\}' "$obf" | sort -u | tr '\n' ' ')" >&2
  exit 1
fi

# 11차: 확정 plan 합본 생성 (AGENT_CMD 무관 — 테스트 가능성, 워커 settings 와 동형).
# plan 은 사용자 산출물 → LEAD boot 의 sed 치환·예약토큰 잔존검증을 거치지 않는다(별도 파일).
# 우연히 {{HARNESS_ROOT}} 등이 들어있어도 그대로 전달되는 것이 의도.
# LEAD 시스템프롬프트 합본 = 역할(obf) + plan(있으면). claude --append-system-prompt-file 복수 불가 →
# 단일 파일로 cat 합본. 역할을 시스템으로 올려 injection 우회(워커/리뷰어와 동일 원리).
ORCH_SYSPROMPT_FILE="$WORKSPACE/.boot/lead-system.md"
# PLAN_BOOT_FILE = 순수 plan 합본(있을 때만). codex LEAD 의 vendor_orch_plan_directive 가
#   "이 파일 Read" 로 가리킬 대상 — 역할이 섞이면 안 되므로 plan 전용 유지.
#   (실제론 LEAD=claude 고정[resolve_orchestrator_vendor]이라 codex 경로 미발생 — 의미 명료성 위해 분리.)
PLAN_BOOT_FILE=""
if [ "${#PLAN_FILES[@]}" -gt 0 ]; then
  PLAN_BOOT_FILE="$WORKSPACE/.boot/plan.md"
  { printf '# 확정 plan (이번 가동의 작업 계획)\n'
    for _pf in "${PLAN_FILES[@]}"; do
      printf '\n## %s\n' "$(basename "$_pf")"
      cat "$_pf"
      printf '\n'
    done; } > "$PLAN_BOOT_FILE"
fi
# LEAD 시스템 합본 = 역할 + (plan 있으면 plan 합본). plan 없으면 역할만.
{ cat "$obf" 2>/dev/null || :
  [ -n "$PLAN_BOOT_FILE" ] && { printf '\n\n'; cat "$PLAN_BOOT_FILE" 2>/dev/null || :; }
} > "$ORCH_SYSPROMPT_FILE" 2>/dev/null || cp "$obf" "$ORCH_SYSPROMPT_FILE" 2>/dev/null

# ★ AWA 방향 가드(2026-05-31): LEAD 는 claude 전용(codex 는 워커/리뷰어만 — P17 회피).
#   ORCH_VENDOR 를 가드 통과값으로 고정 → 이후 모든 ${ORCH_VENDOR:-...} 참조가 claude 사용.
ORCH_VENDOR="$(resolve_orchestrator_vendor "${ORCH_VENDOR:-${LEAD_VENDOR:-${HARNESS_VENDOR:-claude}}}" "ORCH")"   # LEAD_VENDOR = 구 변수명 하위호환
# 5차: LEAD 도 settings 생성 (lead 템플릿 적용, F40). 벤더 위임(claude/codex).
settings_path=""
if ! vendor_source "${ORCH_VENDOR:-${HARNESS_VENDOR:-claude}}"; then
  echo "오류: LEAD 벤더 source 실패 — 부트 중단" >&2
  exit 1
fi
if ! settings_path="$(vendor_gen_settings "orch" "ORCH")"; then
  echo "오류: LEAD settings 생성 실패(fail-safe) — 부트 중단" >&2
  exit 1
fi
# 11차: plan 주입(--append-system-prompt-file)은 vendor_boot_cmd 가 처리 — claude 어댑터 내부 suffix.
lead_sid="$(uuidgen | tr 'A-Z' 'a-z')"
# LEAD 모델 미지정 → ORCH_VENDOR(미설정 시 HARNESS_VENDOR)의 lead 기본 모델로 폴백.
# splash/pane title 표기와 실제 boot 모델 일치를 위해 EFF 변수로 일원화.
ORCH_MODEL_EFF="${ORCH_MODEL:-${LEAD_MODEL:-}}"   # LEAD_MODEL = 구 변수명 하위호환
if [ -z "$ORCH_MODEL_EFF" ]; then
  vendor_source "${ORCH_VENDOR:-${HARNESS_VENDOR:-claude}}" 2>/dev/null \
    && ORCH_MODEL_EFF="$(vendor_default_model orch)"
  [ -n "$ORCH_MODEL_EFF" ] || ORCH_MODEL_EFF="opus"
fi
lead_cmd="$(agent_cmd_for "$ORCH_MODEL_EFF" "$settings_path" "$lead_sid" "$ORCH_SYSPROMPT_FILE" "${ORCH_VENDOR:-}")" || {
  echo "오류: LEAD 벤더 명령 조립 실패 — 부트 중단" >&2; exit 1; }
bootstrap_pane "$ORCH_PID" "ORCH" "$lead_cmd" "ORCH" "" "$ORCH_MODEL_EFF" "${ORCH_VENDOR:-}"
splash_append_member "ORCH" "" "$ORCH_MODEL_EFF"
# plan 주입 시 lead 부트 입력은 "확정 plan 즉시 진행" 으로 분기 — lead.md ⓑ 자동 착수 트리거를
# 부트 입력이 부정하던 결함 해결(13차 D 실험 발견). 워커·reviewer 는 대기형 유지.
# LEAD 역할/plan 은 시스템프롬프트로 주입됨(injection 우회). send_prompt 는 *착수 트리거*만 —
# 시스템프롬프트는 "어떻게"(맥락)이지 "지금 시작"(트리거)이 아니라, 능동 착수엔 send_prompt 필요.
_lv="${ORCH_VENDOR:-${HARNESS_VENDOR:-claude}}"
# LEAD 주입 방식 = INJECT_MODE (PM 과 일관성). LEAD 역할/plan 은 vendor_boot_cmd 가 이미
#   시스템프롬프트(ORCH_SYSPROMPT_FILE)로 주입 — INJECT_MODE 는 *plan 없는 부트의 화면/촉구*만 제어.
#   ★ PM 과 동일 결함: 시스템프롬프트만으론 역할 준수 약함(claude no-op 빈화면). 안정성>빈화면.
#   - system : send_prompt 생략(빈 화면 idle). 역할은 시스템프롬프트에만.
#   - stdin/hybrid : 짧은 역할 인지 촉구를 send_prompt 로 → 화면에 보이고 준수율↑. PM 과 통일.
_orch_inject="${ORCH_INJECT_MODE:-${LEAD_INJECT_MODE:-${INJECT_MODE:-hybrid}}}"   # LEAD_INJECT_MODE = 구 변수명 하위호환
[ "$_lv" = "claude" ] || _orch_inject="stdin"   # 비-claude 는 시스템프롬프트 없음 → 항상 send_prompt
if [ -n "$PLAN_BOOT_FILE" ]; then
  # 벤더별 plan 지시문 — claude=빈값(시스템 컨텍스트 주입), codex=plan 경로 명시 Read(P10).
  vendor_source "$_lv" 2>/dev/null || true
  _plan_directive="$(vendor_orch_plan_directive "$PLAN_BOOT_FILE" 2>/dev/null || true)"
  send_prompt "$ORCH_PID" "${_plan_directive}확정 plan 을 ⓑ 절차(분해→배정 트리→승인 게이트)로 즉시 진행하라."
else
  # plan 없는 부트. system=빈화면 idle, stdin/hybrid=역할 인지 촉구(준수율↑).
  case "$_orch_inject" in
    system)
      case "$_lv" in
        claude) : ;;  # no-op — 시스템프롬프트 orch.md ⓑ 가 @desk 대기. 빈 화면 idle.
        *) send_prompt "$ORCH_PID" "준비되면 다음 지시를 대기하라." ;;
      esac ;;
    *)
      # 역할은 시스템프롬프트에 있고, 여기선 짧은 인지 촉구만 — 작업은 직접 안 하고 @desk/플랜 대기.
      send_prompt "$ORCH_PID" "너는 orch(순수 오케스트레이터)다. 직접 코딩하지 말고 워커 dispatch·권한 판단·리뷰 종합만 한다. 확정 plan 이나 @desk 지시가 오면 ⓑ 절차로 진행, 없으면 대기하라." ;;
  esac
fi

# pm 부트: roles/pm.md 합본 + pm 템플릿 settings. 사용자 창구.
pbf="$(boot_file PM)"
{ cat "$(resolve_role_file "$PROMPTS_DIR" desk)" 2>/dev/null || true
  printf '\n## 현재 팀 카탈로그\n%s\n' "$catalog"
  # P11 Phase4: desk→orch 전달은 desk-queue 파일(watcher 대행). orch pane_id 주입 불필요
  #   (PM 은 tmux 직접호출 안 함 — 격리 경계 안에서 소켓 접근 차단 가능). pm.md ⓒ 규약 참조.
  : ; } > "$pbf"
_tmp_pbf="$pbf.tmp"
sed -e "s#{{SESSION}}#$SESSION#g" \
    -e "s#{{HARNESS_ROOT}}#$HARNESS_ROOT#g" \
    "$pbf" > "$_tmp_pbf" && mv "$_tmp_pbf" "$pbf"
if grep -qE '\{\{(WORKER_NAME|SESSION|HARNESS_ROOT)\}\}' "$pbf"; then
  echo "오류: $pbf 에 토큰 미치환 잔존: $(grep -oE '\{\{(WORKER_NAME|SESSION|HARNESS_ROOT)\}\}' "$pbf" | sort -u | tr '\n' ' ')" >&2
  exit 1
fi
# ★ AWA 방향 가드(2026-05-31): PM 도 claude 전용(LEAD 와 동일 — P17 회피).
DESK_VENDOR="$(resolve_orchestrator_vendor "${DESK_VENDOR:-${PM_VENDOR:-${HARNESS_VENDOR:-claude}}}" "DESK")"   # PM_VENDOR = 구 변수명 하위호환
settings_path=""
if ! vendor_source "${DESK_VENDOR:-${HARNESS_VENDOR:-claude}}"; then
  echo "오류: PM 벤더 source 실패 — 부트 중단" >&2
  exit 1
fi
if ! settings_path="$(vendor_gen_settings "desk" "DESK")"; then
  echo "오류: PM settings 생성 실패(fail-safe) — 부트 중단" >&2
  exit 1
fi
pm_sid="$(uuidgen | tr 'A-Z' 'a-z')"
# PM 모델 미지정 → DESK_VENDOR(미설정 시 HARNESS_VENDOR)의 pm 기본 모델로 폴백.
DESK_MODEL_EFF="${DESK_MODEL:-${PM_MODEL:-}}"   # PM_MODEL = 구 변수명 하위호환
if [ -z "$DESK_MODEL_EFF" ]; then
  vendor_source "${DESK_VENDOR:-${HARNESS_VENDOR:-claude}}" 2>/dev/null \
    && DESK_MODEL_EFF="$(vendor_default_model desk)"
  [ -n "$DESK_MODEL_EFF" ] || DESK_MODEL_EFF="sonnet"
fi
# PM 은 claude 고정(벤더 정책). 역할 주입 방식 = INJECT_MODE (기본 hybrid — 라이브 채택 2026-06-03).
#   ★ 2026-06-03 결함: 시스템프롬프트 주입(a8ef4ae 빈화면 전환)이 PM 역할 준수를 약화 —
#     Sonnet 이 시스템프롬프트의 읽기전용·desk-queue 경계를 대화 메시지보다 약하게 따라 작은
#     작업을 직접 실행 시도(cat>file). 안정성>빈화면 → 주입 방식을 토글로 비교 가능하게.
#   - system : 시스템프롬프트만 (--append-system-prompt-file). 빈 화면. 준수율 약함(실측).
#   - stdin  : send_prompt 로 역할을 대화 첫 메시지 주입. 화면에 역할 보임. 준수율 강함(a8ef4ae 이전 입증).
#   - hybrid : 시스템프롬프트 + 짧은 촉구 send_prompt(직접작업 금지·desk-queue 전달). LEAD 패턴.
_pv="${DESK_VENDOR:-${HARNESS_VENDOR:-claude}}"
# INJECT_MODE 는 PM·LEAD 공통(일관성). DESK_INJECT_MODE 는 PM 단독 override(하위호환).
_desk_inject="${DESK_INJECT_MODE:-${PM_INJECT_MODE:-${INJECT_MODE:-hybrid}}}"   # PM_INJECT_MODE = 구 변수명 하위호환
[ "$_pv" = "claude" ] || _desk_inject="stdin"   # 비-claude 는 시스템프롬프트 경로 없음 → stdin 고정
case "$_desk_inject" in
  system) _psysprompt="$pbf" ;;   # 역할=시스템, 대화 주입 없음 (빈 화면)
  hybrid) _psysprompt="$pbf" ;;   # 역할=시스템 + 아래서 짧은 촉구 send_prompt 추가
  *)      _psysprompt="" ;;       # stdin 은 역할 전문을 send_prompt 로 주입(시스템 비움)
esac
pm_cmd="$(agent_cmd_for "$DESK_MODEL_EFF" "$settings_path" "$pm_sid" "$_psysprompt" "${DESK_VENDOR:-}")" || {
  echo "오류: PM 벤더 명령 조립 실패 — 부트 중단" >&2; exit 1; }
bootstrap_pane "$DESK_PID" "DESK" "$pm_cmd" "DESK" "" "$DESK_MODEL_EFF" "${DESK_VENDOR:-}"
splash_append_member "DESK" "" "$DESK_MODEL_EFF"
case "$_desk_inject" in
  system)
    claude_systemprompt_boot "$_pv" "$DESK_PID" "$pbf" "사용자와 대화할 준비를 하라." ;;
  stdin)
    # 역할 전문을 대화 첫 메시지로 주입(a8ef4ae 이전 방식 — 준수율 강함).
    send_prompt "$DESK_PID" "$(boot_directive "$pbf" "사용자와 대화할 준비를 하라.")" ;;
  hybrid)
    # 역할=시스템프롬프트(맥락) + 짧은 촉구=대화(행동 트리거). LEAD 의 plan 착수 트리거와 동형.
    send_prompt "$DESK_PID" "너는 desk(사용자 창구)이다. 어떤 작업도 직접 실행하지 마라 — 모든 코딩·파일작업은 desk-queue 로 orch 에 전달한다(시스템프롬프트 ⓒ 절차). 사용자와 대화할 준비를 하라." ;;
esac

# 리뷰어 부트: _common.md 제외. roles/<리뷰어역할>.md 만.
if [ -n "${REVIEWERS+x}" ] && [ "${#REVIEWERS[@]}" -gt 0 ]; then
  j=0
  for entry in "${REVIEWERS[@]}"; do
    parse_entry "$entry"
    rbf="$(boot_file "$ENTRY_NAME")"
    # 리뷰어 부트: roles/<리뷰어역할>.md + reviewer-common.md 합본 (정체성+공통절차).
    # sed `#` 구분자 (HARNESS_ROOT 절대경로의 `/` 충돌 회피).
    _rev_file="$(resolve_role_file "$PROMPTS_DIR" "$ENTRY_ROLE")" || { echo "오류: 리뷰어 '$ENTRY_NAME' 역할파일 해석 실패" >&2; j=$((j+1)); continue; }
    _revc_file="$(resolve_role_file "$PROMPTS_DIR" reviewer-common)"
    cat "$_rev_file" "$_revc_file" \
      | sed -e "s#{{SESSION}}#$SESSION#g" \
            -e "s#{{HARNESS_ROOT}}#$HARNESS_ROOT#g" > "$rbf" 2>/dev/null || : > "$rbf"
    # `[ -s "$rbf" ]` 가드: 리뷰어 역할 파일이 없거나 비어있으면 빈 boot 허용 (의도된 묵살).
    # 워커 boot 와 일관성은 X — 리뷰어는 선택적 컴포넌트라 strict 미적용 (Minor #3).
    # 화이트리스트 검증 (Minor #5).
    if [ -s "$rbf" ] && grep -qE '\{\{(WORKER_NAME|SESSION|HARNESS_ROOT)\}\}' "$rbf"; then
      echo "오류: $rbf 에 토큰 미치환 잔존: $(grep -oE '\{\{(WORKER_NAME|SESSION|HARNESS_ROOT)\}\}' "$rbf" | sort -u | tr '\n' ' ')" >&2
      exit 1
    fi
    rtgt="${REV_PIDS[$j]}"
    # 4차 P0: 리뷰어 역할 (reviewer-quality·reviewer-arch·reviewer-spec) → reviewer 템플릿.
    settings_path=""
    if ! vendor_source "${ENTRY_VENDOR:-${HARNESS_VENDOR:-claude}}"; then
      echo "오류: 리뷰어 '$ENTRY_NAME' 벤더 source 실패 — 부트 skip" >&2
      SKIPPED_PANES="${SKIPPED_PANES:-} $ENTRY_NAME"; j=$((j + 1)); continue; fi
    if ! settings_path="$(vendor_gen_settings "$ENTRY_ROLE" "$ENTRY_NAME")"; then
      echo "오류: 리뷰어 '$ENTRY_NAME' settings 생성 실패(fail-safe) — 부트 skip" >&2
      SKIPPED_PANES="${SKIPPED_PANES:-} $ENTRY_NAME"; j=$((j + 1)); continue; fi
    rev_sid="$(uuidgen | tr 'A-Z' 'a-z')"
    # 모델 미지정 → 해석된 벤더의 역할 기본 모델로 폴백 (claude reviewer-* → opus).
    if [ -z "$ENTRY_MODEL" ]; then
      vendor_source "${ENTRY_VENDOR:-${HARNESS_VENDOR:-claude}}" 2>/dev/null \
        && ENTRY_MODEL="$(vendor_default_model "$ENTRY_ROLE")"
      [ -n "$ENTRY_MODEL" ] || ENTRY_MODEL="sonnet"
    fi
    # claude 리뷰어면 역할을 시스템 주입(injection 우회 — 라이브 결함 해소), codex 면 빈값(send_prompt 경로).
    _rv="${ENTRY_VENDOR:-${HARNESS_VENDOR:-claude}}"
    _rsysprompt=""; [ "$_rv" = "claude" ] && _rsysprompt="$rbf"
    rev_cmd="$(agent_cmd_for "$ENTRY_MODEL" "$settings_path" "$rev_sid" "$_rsysprompt" "${ENTRY_VENDOR:-}")" || {
      echo "오류: 리뷰어 '$ENTRY_NAME' 벤더 명령 조립 실패 — 부트 skip" >&2
      SKIPPED_PANES="${SKIPPED_PANES:-} $ENTRY_NAME"; j=$((j + 1)); continue; }
    bootstrap_pane "$rtgt" "$ENTRY_NAME" "$rev_cmd" "리뷰어" "$ENTRY_ROLE" "$ENTRY_MODEL" "${ENTRY_VENDOR:-}"
    splash_append_member "$ENTRY_NAME" "$ENTRY_ROLE" "$ENTRY_MODEL"
    claude_systemprompt_boot "$_rv" "$rtgt" "$rbf" "준비되면 다음 지시를 대기하라."
    j=$((j + 1))
  done
fi

# watcher 데몬 기동 (9차). 윈도우0 에 셸 pane 으로 split — 세션 kill 시 자동 사망.
# lead/reviewer pane_id + state 경로를 env 로 주입(index 재배열 면역).
# AGENT_CMD=cat 더미 모드에서도 watcher 는 실셸로 기동 (감시 로직 검증 가능).
# 14차 UX: watcher 도 workers 윈도우 마지막에 -v split (최하단 보장).
# _prev_worker_pid = 마지막 워커 pane_id 명시 타겟 → split 순서(상→하) 보장.
WATCHER_PANE="$(tmux split-window -v -t "$_prev_worker_pid" -d -P -F '#{pane_id}')"
tmux select-pane -t "$WATCHER_PANE" -T "watcher"
# reviewer pane_id 목록 (공백구분). 리뷰어 없으면 빈 문자열(set -u 안전 — watcher 가드).
_rev_panes=""
if [ "${#REV_PIDS[@]}" -gt 0 ]; then
  _rev_panes="${REV_PIDS[*]}"
fi
# workers 윈도우 layout 적용 — split 순서대로 상→하 (워커1→…→워커N→watcher).
tmux select-layout -t "$SESSION:workers" even-vertical
# watcher 가 list-panes 순서상 마지막인지 검증 — 깨지면 즉시 fail.
_last="$(tmux list-panes -t "$SESSION:workers" -F '#{pane_title}' 2>/dev/null | tail -1)"
if [ "$_last" != "watcher" ]; then
  echo "오류: workers 윈도우 마지막 pane=$_last (기대=watcher)" >&2
  tmux kill-session -t "$SESSION" 2>/dev/null || true
  exit 1
fi
# watcher 기동: pane 에 env 세팅 후 watcher.sh 실행 명령 주입.
tmux send-keys -t "$WATCHER_PANE" -l "SESSION=$SESSION ORCH_PANE=$ORCH_PID REVIEWER_PANES=\"$_rev_panes\" REVIEW_MANAGER_PANE=\"${REVIEW_MANAGER_PANE:-}\" EXPECTED_VOTERS=\"$EXPECTED_VOTERS\" STATE_DIR=\"$WORKSPACE/state\" EVENTS=\"$WORKSPACE/events.log\" SEEN=\"$WORKSPACE/state/.watcher-seen\" HARNESS_PROJECT=\"$PROJECT_ROOT\" bash \"$HARNESS_ROOT/bin/watcher.sh\""
tmux send-keys -t "$WATCHER_PANE" Enter

# 14차 UX: 첫 attach 시 항상 team(LEAD+PM) 윈도우로 접속 ('window 0=LEAD+PM' 확정과 정합).
# watcher split(-d, focus 미이동) 후라 review/workers 가 active 로 남는 문제 해소.
# window 0 은 fix_session_indexing 으로 base-index 무관히 0 고정 → $SESSION:0 안전.
tmux select-window -t "$SESSION:0"
# attach 첫 화면 splash — client-attached 훅이 attach 시 display-popup(모달)을 띄운다.
#
# ⚠️ 훅 값에 display-popup 을 *직접* 넣으면 안 된다(조용히 무시됨). 훅 컨텍스트의
#    display-popup 은 attach 중인 클라이언트를 타깃으로 잡지 못한다(실측: 훅은 발화하나
#    popup 안 뜸). run-shell 로 감싸 그 안에서 별도 `tmux display-popup` 을 호출하면
#    attach 클라이언트를 정상 타깃팅한다 — 첫 가동·재attach 모두 이 한 경로로 커버.
# -t $SESSION: awa 세션에만 설치(사용자 다른 세션 무영향). -E: awa-splash.sh 종료 시 자동 닫힘.
# -b rounded: 둥근 테두리. -w 100% -h 100%: 뒤 claude 화면을 가리는 전체 모달.
#   (하드웨어 커서는 awa-splash.sh 가 \033[?25l 로 숨긴다 — popup 크기로는 못 가림.)
# -e AWA_SPLASH_TEAM_FILE: 팀 요약 파일 경로를 popup 환경변수로 명시 전달(별도 프로세스
#   트리라 var 상속 안 됨). $SPLASH_TEAM_FILE 는 $HOME 해소된 절대경로·공백 없음.
# || true: splash 는 보조 기능 — set -e 하에서 set-hook 비정상 반환이 부팅을 죽이지 않게.
SPLASH_POPUP="run-shell 'tmux display-popup -E -b rounded -w 100% -h 100% -e AWA_SPLASH_TEAM_FILE=$SPLASH_TEAM_FILE \"$HARNESS_ROOT/bin/awa-splash.sh\"'"
tmux set-hook -t "$SESSION" client-attached "$SPLASH_POPUP" || true

echo "팀 '$PROFILE' 가동 완료. 세션='$SESSION', 워커=${#WORKERS[@]}개."
echo "attach: tmux attach -t $SESSION"

# 15차: bookmarks 자동 등록 (현재 발진의 path/preset/plan 기록).
# 7차 리뷰 [CRIT-8]: spec §5.5 의 ${PROFILE:-custom} 정합 — '(custom)' 괄호 라벨 정제.
_PLAN_FIRST=""
[ "${#PLAN_FILES[@]}" -gt 0 ] && _PLAN_FIRST="${PLAN_FILES[0]}"
_PRESET_LABEL="${PROFILE:-custom}"
[ "$_PRESET_LABEL" = "(custom)" ] && _PRESET_LABEL="custom"
[ "$_PRESET_LABEL" = "(spec)" ] && _PRESET_LABEL="spec"
bookmarks_upsert "$PROJECT_ROOT" "$_PRESET_LABEL" "$_PLAN_FIRST" 2>/dev/null || true

# P2 §2.3: SKIPPED_PANES 가시화. bootstrap_pane 에서 skip 시 누적된 변수.
# 성공 메시지 직후에 출력해 사용자가 success/주의를 함께 인지.
if [ -n "${SKIPPED_PANES:-}" ]; then
  # leading space 정리: SKIPPED_PANES 누적은 `${var:-} $wname` 패턴이라 항상 앞 공백 포함.
  echo "주의: REPL 준비 실패한 pane: ${SKIPPED_PANES# }" >&2
  echo "  - shell_ready_wait timeout 또는 send-keys 실패 가능성." >&2
  # 두 env 역할 분리: SHELL_READY_TIMEOUT 은 셸 ready timeout, BOOT_REPL_CHECK_DELAY 는
  # capture 직전 sleep 길이 (timeout 아님 — 큰 값은 부팅 지연).
  echo "  - SHELL_READY_TIMEOUT (셸 ready timeout) 또는 BOOT_REPL_CHECK_DELAY (REPL 검사 대기) env 로 조정 가능." >&2
fi
