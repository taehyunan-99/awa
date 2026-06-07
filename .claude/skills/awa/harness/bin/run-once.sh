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

# ── main (--source-only 아닐 때만 도달) ────────────────────────────────
TASK_FILE="${1:-}"; PROJECT_DIR="${2:-}"; OUT_EVENTS="${3:-}"; TIMEOUT="${4:-540}"
if [ -z "$TASK_FILE" ] || [ -z "$PROJECT_DIR" ] || [ -z "$OUT_EVENTS" ]; then
  echo "사용: run-once.sh <task-file> <project-dir> <out-events-path> [timeout-sec]" >&2
  exit 2
fi
[ -f "$TASK_FILE" ] || { echo "오류: task 파일 없음: $TASK_FILE" >&2; exit 2; }
[ -d "$PROJECT_DIR" ] || { echo "오류: project dir 없음: $PROJECT_DIR" >&2; exit 2; }

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1; pwd)"
EVENTS="$PROJECT_DIR/.agent-harness/events.log"

# 정리 보장 — 성공·실패·중단 무관 awa-down. (set -e 아님: 데몬성, 실패 흡수)
cleanup() { bash "$HERE/awa-down.sh" --project "$PROJECT_DIR" >/dev/null 2>&1 || true; }
trap cleanup EXIT

# 가동 — --plan 으로 task 자동 주입(사람 ORCH 타이핑 불필요), 최소 워커 1.
if ! bash "$HERE/awa-up.sh" --workers "dev:engineer" --project "$PROJECT_DIR" --plan "$TASK_FILE"; then
  echo "run-once: awa-up 실패 — $TASK_FILE" >&2
  exit 1
fi

# 완료 대기 — done 라인 출현 폴링.
if wait_for_done "$EVENTS" "$TIMEOUT" 5; then
  status="done"
else
  status="timeout"
  echo "run-once: 완료 타임아웃(${TIMEOUT}s) — $TASK_FILE (부분 events.log 수집)" >&2
fi

# 수집 — events.log 를 out 경로로(없으면 빈 파일이라도 만들어 집계 일관성).
mkdir -p "$(dirname "$OUT_EVENTS")"
cp "$EVENTS" "$OUT_EVENTS" 2>/dev/null || : > "$OUT_EVENTS"
echo "run-once: $status — $(basename "$TASK_FILE") → $OUT_EVENTS"
[ "$status" = "done" ]   # done 이면 exit 0, timeout 이면 exit 1
