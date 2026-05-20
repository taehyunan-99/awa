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

# timeout 명령 해석: coreutils timeout / gtimeout / 폴백
run_with_timeout() {
  local secs="$1"; shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "$secs" "$@"
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$secs" "$@"
  else
    # 폴백(coreutils/gtimeout 둘 다 없을 때, 예: macOS 기본 환경):
    # 주의 1) 서브셸로 감싸면($pid=서브셸) 실제 `tmux wait-for` 손주 프로세스가
    #         고아로 남아 영원히 산다 → 서브셸 없이 직접 백그라운드 실행해
    #         $pid 가 곧 `tmux wait-for` 프로세스가 되게 한다.
    # 주의 2) `tmux wait-for` 는 SIGTERM 을 받으면 0 으로 정상 종료
    #         (연결 해제 클라이언트가 채널을 woken 처리) → SIGTERM 으로는
    #         타임아웃을 판별할 수 없다. SIGKILL 을 사용한다.
    # 결과: 자연 완료=종료코드 0, 워커가 죽인 경우=SIGKILL(137) → 124 로 변환.
    "$@" &
    local pid=$!
    ( sleep "$secs"; kill -KILL "$pid" 2>/dev/null ) &
    local watcher=$!
    local crc=0
    wait "$pid" 2>/dev/null || crc=$?
    kill -KILL "$watcher" 2>/dev/null || true
    wait "$watcher" 2>/dev/null || true
    if [ "$crc" -eq 0 ]; then
      return 0
    else
      return 124
    fi
  fi
}

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
