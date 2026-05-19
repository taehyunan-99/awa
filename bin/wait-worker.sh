#!/usr/bin/env bash
set -euo pipefail

_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_DIR/lib.sh"

SESSION="$(resolve_session)"

WORKER="${1:-}"
TASK_ID="${2:-}"
TIMEOUT="${3:-300}"

if [ -z "$WORKER" ] || [ -z "$TASK_ID" ]; then
  echo "사용법: wait-worker.sh <worker> <task-id> [timeout_sec]" >&2
  exit 1
fi

CHANNEL="done-$WORKER-$TASK_ID"

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
