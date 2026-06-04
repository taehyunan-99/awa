#!/usr/bin/env bash
# /agpn 의 비대화 명령 조립 백엔드. 사용자 채팅 대화는 SKILL.md 가 수집.
# 7차 리뷰 [CRIT-7]: claude code Bash 도구는 stdin 닫혀있어 read 불가 — 모든 분기를 인자로 받음.
#
# Usage:
#   awa-main.sh resume
#       → live awa-* / _SYMPHONY 세션 TSV 출력
#   awa-main.sh attach --session <name>
#       → "tmux attach -t <name>" 한 줄 출력
#   awa-main.sh launch --project <path> --mode-launch <single|multi>
#                            [--preset <name>|--workers <spec>] [--plan <path>]
#       → 발진 명령 + AGPN_META 출력
set -uo pipefail
_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_DIR/lib.sh"
# 8차 리뷰: HARNESS_ROOT 는 lib.sh 가 도출 (단일 출처). main.sh 자체 도출 제거.
# lib.sh 의 _validate_path_chars 가 공백/특수문자 검증 — 부적합 시 HARNESS_ROOT_VALID=0
[ "${HARNESS_ROOT_VALID:-0}" = "1" ] || { echo "오류: HARNESS_ROOT 부적합 — '$HARNESS_ROOT'" >&2; exit 1; }

cmd_resume() {
  # live 세션 + 라벨 — TSV 출력 (SKILL 이 파싱하여 사용자에게 채팅으로 노출).
  # 8차 리뷰: 헤더 항상 출력 — SKILL 이 'session\tproject\tlabel' + body 0 줄로 'no live' 구분 가능.
  # 10차 리뷰 [CRIT-26]: cwd 매칭 제거 — SKILL Bash 도구 cwd=harness 라 사용자 프로젝트와 매치 불가.
  #   label 은 _SYMPHONY 만 'multi-view', 나머지는 빈 문자열. 사용자가 채팅에서 직접 선택.
  local live
  live=$(tmux list-sessions -F '#{session_name}' 2>/dev/null \
         | grep -E '^(awa-|_SYMPHONY$)' || true)
  printf 'session\tproject\tlabel\n'
  [ -z "$live" ] && return 0
  while IFS= read -r s; do
    [ -n "$s" ] || continue
    local proj="" label=""
    if [ "$s" = "_SYMPHONY" ]; then
      label="multi-view"
    else
      proj=$(tmux show-options -t "$s" -v @awa-project 2>/dev/null || echo "")
    fi
    printf '%s\t%s\t%s\n' "$s" "${proj:-}" "$label"
  done <<< "$live"
}

cmd_resolve_path() {
  # 8차 리뷰 [CRIT-15]: SKILL 이 사용자 alias 입력을 path 로 변환할 채널.
  # 입력 = alias 또는 path → 출력 stdout = 해석된 path (실패 시 빈 출력 + exit 1)
  local input=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --input) input="${2:-}"; shift 2 ;;
      --input=*) input="${1#--input=}"; shift ;;
      *) echo "오류: 알 수 없는 인자 $1" >&2; return 1 ;;
    esac
  done
  [ -n "$input" ] || { echo "오류: --input 필요" >&2; return 1; }
  local resolved
  resolved=$(bookmarks_resolve_alias "$input")
  if [ -n "$resolved" ]; then
    printf '%s\n' "$resolved"
    return 0
  fi
  # path 로 시도
  if [ -d "$input" ]; then
    printf '%s\n' "$input"
    return 0
  fi
  echo "오류: alias/path 해석 실패 — '$input'" >&2
  return 1
}

cmd_attach() {
  local session=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --session) session="${2:-}"; shift 2 ;;
      --session=*) session="${1#--session=}"; shift ;;
      *) echo "오류: 알 수 없는 인자 $1" >&2; return 1 ;;
    esac
  done
  [ -n "$session" ] || { echo "오류: --session 필요" >&2; return 1; }
  echo "Run this with ! :"
  echo "  tmux attach -t $session"
  echo "  (inside tmux: tmux switch-client -t $session)"
}

cmd_launch() {
  local project="" mode_launch="" preset="" workers_spec="" plan_path="" spec_file=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --project) project="${2:-}"; shift 2 ;;
      --project=*) project="${1#--project=}"; shift ;;
      --mode-launch) mode_launch="${2:-}"; shift 2 ;;
      --mode-launch=*) mode_launch="${1#--mode-launch=}"; shift ;;
      --preset) preset="${2:-}"; shift 2 ;;
      --preset=*) preset="${1#--preset=}"; shift ;;
      --workers) workers_spec="${2:-}"; shift 2 ;;
      --workers=*) workers_spec="${1#--workers=}"; shift ;;
      --plan) plan_path="${2:-}"; shift 2 ;;
      --plan=*) plan_path="${1#--plan=}"; shift ;;
      --spec) spec_file="${2:-}"; shift 2 ;;
      --spec=*) spec_file="${1#--spec=}"; shift ;;
      *) echo "오류: 알 수 없는 인자 $1" >&2; return 1 ;;
    esac
  done
  # 인자 검증
  [ -n "$project" ] || { echo "오류: --project 필요" >&2; return 1; }
  [ -d "$project" ] || { echo "오류: --project 경로 없음 — $project" >&2; return 1; }
  case "$mode_launch" in single|multi) ;;
    *) echo "오류: --mode-launch 는 single|multi" >&2; return 1 ;;
  esac
  # preset / workers / spec — 정확히 하나만 허용
  local _n=0
  [ -n "$preset" ] && _n=$((_n+1))
  [ -n "$workers_spec" ] && _n=$((_n+1))
  [ -n "$spec_file" ] && _n=$((_n+1))
  if [ "$_n" -eq 0 ]; then echo "오류: --preset 또는 --workers 또는 --spec 필요" >&2; return 1; fi
  if [ "$_n" -gt 1 ]; then echo "오류: --preset/--workers/--spec 중 하나만" >&2; return 1; fi
  # 15차 quality review: preset 가 unquoted 로 cmd 문자열에 들어감 → paste-to-shell 방어용
  # 화이트리스트. [A-Za-z0-9_-] 만 허용 (실 preset 이름 패턴과 일치).
  if [ -n "$preset" ]; then
    case "$preset" in
      *[!A-Za-z0-9_-]*) echo "오류: --preset 은 [A-Za-z0-9_-] 만 — '$preset'" >&2; return 1 ;;
    esac
  fi

  local session_name
  session_name="$(session_name_for "$project")"

  # 발진 명령 조립 — HARNESS_ROOT 절대경로 (검증 완료) + paste-safe 따옴표.
  # lib.sh _validate_path_chars 가 공백/특수문자 거부했으니 paste 시에도 안전,
  # 단 가독성·일관성 위해 모든 경로 인자 따옴표.
  local cmd="bash \"$HARNESS_ROOT/bin/awa-up.sh\""
  if [ -n "$spec_file" ]; then
    cmd="$cmd --spec \"$spec_file\""
  elif [ -n "$workers_spec" ]; then
    cmd="$cmd --workers \"$workers_spec\""
  else
    cmd="$cmd $preset"
  fi
  [ -n "$plan_path" ] && cmd="$cmd --plan \"$plan_path\""
  cmd="$cmd --project \"$project\""

  echo "Run this with ! :"
  echo ""
  echo "  $cmd"
  echo ""
  if [ "$mode_launch" = "multi" ]; then
    echo "After launch, claude code will auto-join _SYMPHONY. Then:"
    echo "  tmux attach -t _SYMPHONY"
    echo ""
    echo "# AGPN_META: session=$session_name mode=multi-view"
  else
    echo "After launch, attach:"
    echo "  tmux attach -t $session_name"
    echo ""
    echo "# AGPN_META: session=$session_name mode=single"
  fi
}

# === main ================================================================
sub="${1:-}"
shift || true
case "$sub" in
  resume) cmd_resume "$@" ;;
  attach) cmd_attach "$@" ;;
  launch) cmd_launch "$@" ;;
  resolve-path) cmd_resolve_path "$@" ;;
  ""|-h|--help)
    echo "Usage: $0 {resume | attach --session <n> | launch --project <p> --mode-launch <single|multi> [--preset <p>|--workers <s>] [--plan <p>] | resolve-path --input <alias|path>}"
    ;;
  *) echo "오류: 알 수 없는 subcommand '$sub'" >&2; exit 1 ;;
esac
