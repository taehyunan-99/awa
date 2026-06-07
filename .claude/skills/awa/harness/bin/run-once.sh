#!/usr/bin/env bash
# 단일 trial 무인 실행기 — B(AWA) 전용.
# 사용: run-once.sh <task-file> <project-dir> <out-events-path> [timeout-sec]
#   awa-up(--plan task)→events.log done 폴링→out-events 로 copy→awa-down.
# --source-only: 함수만 로드(테스트용), main 미실행.
set -uo pipefail

# events.log 에 done 라인이 나타날 때까지 폴링. $1=events경로 $2=총timeout초 $3=폴링간격초.
# done 출현 시 0, timeout 시 1. 파일 부재도 timeout 처리(즉사 아님).
wait_for_done() {
  local events="$1" timeout="${2:-540}" interval="${3:-5}" waited=0
  while [ "$waited" -lt "$timeout" ]; do
    if [ -f "$events" ] && awk -F'\t' '$4=="done"{found=1} END{exit !found}' "$events" 2>/dev/null; then
      return 0
    fi
    sleep "$interval"
    waited=$(( waited + interval ))
  done
  return 1
}

# 테스트가 함수만 로드할 수 있게 — --source-only 면 여기서 종료(main 미정의).
case "${1:-}" in
  --source-only) return 0 2>/dev/null || exit 0 ;;
esac
