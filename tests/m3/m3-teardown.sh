#!/usr/bin/env bash
# M3 관측 정리 (토큰0). m3-setup.sh 는 사용자 ! 로 떠서 곧 종료하므로 watcher 백그라운드
# PID·tmux 세션·임시 PROJECT_ROOT 가 남는다. 이 스크립트가 명시적으로 정리한다.
# (setup 은 trap 으로 못 정리 — 떠난 뒤에도 세션/워처가 살아있어야 LEAD 가 종합하니까.)
#
# 사용: bash m3-teardown.sh [PROJECT_ROOT]
#   인자 없으면 /tmp/m3-last-proj 에서 읽음.
set -uo pipefail

PROJ="${1:-}"
[ -z "$PROJ" ] && PROJ="$(cat /tmp/m3-last-proj 2>/dev/null || true)"
if [ -z "$PROJ" ] || [ ! -d "$PROJ" ]; then
  echo "정리할 PROJECT_ROOT 미상(이미 정리됨일 수 있음)." >&2
  exit 0
fi
WS="$PROJ/.agent-harness"

# watcher 정리 (PID 파일 → kill; has-session 가드라 세션 죽으면 어차피 자멸하지만 명시 kill).
if [ -f "$WS/.watcher.pid" ]; then
  WPID="$(cat "$WS/.watcher.pid" 2>/dev/null || true)"
  [ -n "$WPID" ] && kill "$WPID" 2>/dev/null || true
fi
# 세션 정리.
if [ -f "$WS/.session" ]; then
  SES="$(cat "$WS/.session" 2>/dev/null || true)"
  [ -n "$SES" ] && tmux kill-session -t "$SES" 2>/dev/null || true
fi
# 임시 PROJECT_ROOT 제거 + 포인터 파일 정리.
rm -rf "$PROJ"
rm -f /tmp/m3-last-proj
echo "M3 관측 정리 완료 (세션·watcher·임시 PROJECT_ROOT 제거)."
