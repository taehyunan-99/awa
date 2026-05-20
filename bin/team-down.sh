#!/usr/bin/env bash
set -euo pipefail

_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_DIR/lib.sh"

SESSION="$(resolve_session)"

if tmux has-session -t "$SESSION" 2>/dev/null; then
  tmux kill-session -t "$SESSION"
  echo "세션 '$SESSION' 종료."
else
  echo "세션 '$SESSION' 없음 (이미 정리됨)."
fi

# 부트스트랩 합본은 런타임 산출물 → 정리. tasks/results 는 보존.
if [ -d "$WORKSPACE/.boot" ]; then
  rm -f "$WORKSPACE/.boot"/*.md 2>/dev/null || true
  echo "workspace/.boot 정리 완료."
fi

# 하네스 런타임 산출물(events.log·리뷰 커서·메인 상태·리뷰 결과)도 정리.
# tasks/results 는 보존. 기존 .boot 정리 블록과 동일한 조건부 스타일 유지.
if [ -f "$WORKSPACE/events.log" ]; then
  rm -f "$WORKSPACE/events.log" || true
fi
if [ -f "$WORKSPACE/.harness-state" ]; then
  rm -f "$WORKSPACE/.harness-state" || true
fi
# .review-cursor.*/.harness-task.* 글롭: nullglob 없는 bash 3.2 환경에서 2>/dev/null || true 로 안전 처리
rm -f "$WORKSPACE"/.review-cursor.* 2>/dev/null || true
rm -f "$WORKSPACE"/.harness-task.* 2>/dev/null || true
if [ -d "$WORKSPACE/review" ]; then
  rm -rf "${WORKSPACE:?WORKSPACE unset}/review" || true
fi
# .claude/settings.json — team-up 이 __REPO__ 치환해 생성한 런타임 산출물.
# 세션 일회용 철학상 정리(다음 team-up 이 다시 생성). .gitignore 됨.
rm -f "$REPO_ROOT/.claude/settings.json" 2>/dev/null || true
echo "하네스 런타임 산출물 정리 완료."
