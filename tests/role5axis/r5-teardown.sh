#!/usr/bin/env bash
# 층3 정리 (토큰0). r5-setup 은 사용자 ! 로 떠서 곧 종료 → tmux 세션·임시 PROJECT_ROOT 가 남는다.
# (r5 는 watcher 없음 — dev pane 1개라 백그라운드 데몬 미기동. m3 와 달리 PID kill 불필요.)
#
# 사용: bash r5-teardown.sh [PROJECT_ROOT]   인자 없으면 /tmp/r5-last-proj 에서 읽음.
set -uo pipefail
PROJ="${1:-}"
[ -z "$PROJ" ] && PROJ="$(cat /tmp/r5-last-proj 2>/dev/null || true)"
if [ -z "$PROJ" ] || [ ! -d "$PROJ" ]; then
  echo "정리할 PROJECT_ROOT 미상(이미 정리됨일 수 있음)." >&2
  exit 0
fi
WS="$PROJ/.agent-harness"
if [ -f "$WS/.session" ]; then
  SES="$(cat "$WS/.session" 2>/dev/null || true)"
  [ -n "$SES" ] && tmux kill-session -t "$SES" 2>/dev/null || true
fi
rm -rf "$PROJ"
rm -f /tmp/r5-last-proj
