#!/usr/bin/env bash
set -euo pipefail

_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_DIR/lib.sh"

SESSION="${SESSION_OVERRIDE:-$SESSION_DEFAULT}"

WORKER="${1:-}"
TASK_ID="${2:-}"

if [ -z "$WORKER" ] || [ -z "$TASK_ID" ]; then
  echo "사용법: dispatch.sh <worker> <task-id>" >&2
  exit 1
fi

# 세션 확인
if ! tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "오류: 세션 '$SESSION' 없음. team-up.sh 먼저 실행." >&2
  exit 1
fi

# 작업 파일 확인
TASK_FILE="$WORKSPACE/tasks/$TASK_ID.md"
if [ ! -f "$TASK_FILE" ]; then
  echo "오류: 작업 파일 없음 → $TASK_FILE" >&2
  exit 1
fi

# 워커 → 페인 인덱스: pane title 로 찾는다 (team-up 이 title=워커명 설정)
PANE_IDX=""
while IFS=$'\t' read -r pidx ptitle; do
  if [ "$ptitle" = "$WORKER" ]; then
    PANE_IDX="$pidx"
    break
  fi
done < <(tmux list-panes -t "$SESSION:0" -F $'#{pane_index}\t#{pane_title}')

if [ -z "$PANE_IDX" ]; then
  echo "오류: 워커 '$WORKER' 페인을 찾을 수 없음. 활성 워커: $(tmux list-panes -t "$SESSION:0" -F '#{pane_title}' | tr '\n' ' ')" >&2
  exit 1
fi

TARGET="$SESSION:0.$PANE_IDX"
send_prompt "$TARGET" "TASK $TASK_ID"
echo "배정 완료: 워커=$WORKER (pane $PANE_IDX) ← TASK $TASK_ID"
