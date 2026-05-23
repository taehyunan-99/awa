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
while [ $# -gt 0 ]; do
  case "$1" in
    --project)
      if ! HARNESS_PROJECT="$(_normalize_project_arg "${2:-}")"; then exit 1; fi
      export HARNESS_PROJECT; shift 2 ;;
    --project=*)
      if ! HARNESS_PROJECT="$(_normalize_project_arg "${1#--project=}")"; then exit 1; fi
      export HARNESS_PROJECT; shift ;;
    *) break ;;
  esac
done

source "$_DIR/lib.sh"
[ "$PROJECT_ROOT_VALID" = "1" ] || exit 1

SESSION="$(resolve_session)"

WORKER="${1:-}"
TASK_ID="${2:-}"
TIMEOUT="${3:-300}"

if [ -z "$WORKER" ] || [ -z "$TASK_ID" ]; then
  echo "사용법: wait-worker.sh [--project DIR] <worker> <task-id> [timeout_sec]" >&2
  exit 1
fi

# E1: 채널명에 SESSION 포함 — 멀티 프로젝트 동시 가동 시 신호 race 차단.
# tmux wait-for 채널은 tmux 서버 전역이라 세션 분리만으로는 부족.
CHANNEL="done-$SESSION-$WORKER-$TASK_ID"

if run_with_timeout "$TIMEOUT" tmux wait-for "$CHANNEL"; then
  echo "완료 신호 수신: $CHANNEL"
  exit 0
else
  rc=$?
  echo "오류: 타임아웃(${TIMEOUT}s) — 채널 '$CHANNEL' 신호 없음 (워커=$WORKER)" >&2
  echo "---- capture-pane (워커 '$WORKER') ----" >&2
  # 워커/리뷰어 페인 찾아 덤프: window 0(team)·1(review) 양쪽 조회
  tgt=""
  for win in 0 1; do
    tmux list-windows -t "$SESSION" -F '#{window_index}' 2>/dev/null | grep -qx "$win" || continue
    while IFS=$'\t' read -r pi pt; do
      [ "$pt" = "$WORKER" ] && { tgt="$SESSION:$win.$pi"; break; }
    done < <(tmux list-panes -t "$SESSION:$win" -F $'#{pane_index}\t#{pane_title}' 2>/dev/null || true)
    [ -n "$tgt" ] && break
  done
  if [ -n "$tgt" ]; then
    tmux capture-pane -p -t "$tgt" -S -40 >&2 2>/dev/null || echo "(페인 캡처 실패)" >&2
  else
    echo "(워커/리뷰어 페인을 찾을 수 없음)" >&2
  fi
  echo "---- end capture ----" >&2
  exit "$rc"
fi
