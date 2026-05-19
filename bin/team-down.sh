#!/usr/bin/env bash
set -euo pipefail

_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_DIR/lib.sh"

SESSION="${SESSION_OVERRIDE:-$SESSION_DEFAULT}"

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
# tasks/results 는 보존. 멱등 — 파일 없어도 || true 로 안전(set -e).
rm -f "$WORKSPACE"/events.log "$WORKSPACE"/.review-cursor.* "$WORKSPACE"/.harness-state 2>/dev/null || true
rm -rf "$WORKSPACE"/review 2>/dev/null || true
echo "하네스 런타임 산출물 정리 완료."
