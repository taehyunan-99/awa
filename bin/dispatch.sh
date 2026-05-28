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

if [ -z "$WORKER" ] || [ -z "$TASK_ID" ]; then
  echo "사용법: dispatch.sh <worker> <task-id>" >&2
  exit 1
fi

# 세션 확인
if ! tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "오류: 세션 '$SESSION' 없음. awa-up.sh 먼저 실행." >&2
  exit 1
fi

# 작업 파일 확인
TASK_FILE="$WORKSPACE/tasks/$TASK_ID.md"
if [ ! -f "$TASK_FILE" ]; then
  echo "오류: 작업 파일 없음 → $TASK_FILE" >&2
  exit 1
fi

# 워커/리뷰어 → 페인: window 0(team)·1(review) 양쪽에서 pane title 로 찾는다.
TARGET=""
for win in 0 1; do
  tmux has-session -t "$SESSION" 2>/dev/null || break
  if ! tmux list-windows -t "$SESSION" -F '#{window_index}' | grep -qx "$win"; then
    continue
  fi
  while IFS=$'\t' read -r pidx ptitle; do
    if [ "$ptitle" = "$WORKER" ]; then
      TARGET="$SESSION:$win.$pidx"
      break
    fi
  done < <(tmux list-panes -t "$SESSION:$win" -F $'#{pane_index}\t#{pane_title}')
  [ -n "$TARGET" ] && break
done

if [ -z "$TARGET" ]; then
  echo "오류: 워커/리뷰어 '$WORKER' 페인을 찾을 수 없음 (window 0·1 조회)." >&2
  exit 1
fi

write_harness_task "$WORKER" "$TASK_ID"
send_prompt "$TARGET" "TASK $TASK_ID"
echo "배정 완료: 워커=$WORKER ($TARGET) ← TASK $TASK_ID"
