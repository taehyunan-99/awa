#!/usr/bin/env bash
# PostToolUse hook 스크립트. stdin 으로 hook JSON 수신 →
# 수정 파일 경로를 repo 상대경로 5필드 라인으로 events.log 에 결정적 append.
# 워커명=HARNESS_WORKER, task=HARNESS_TASK (agenphony-up 이 pane env 로 주입).
# 자기보고 아님 — claude 가 Edit/Write 쓰면 hook 이 무조건 실행됨(이슈 6).
set -uo pipefail

REPO_ROOT="${REPO_ROOT:-$PWD}"
# 기본값을 .agent-harness/events.log 로 — spec §5.2 단일 로그 위치와 정합.
# settings.json.tpl 이 EVENTS_LOG 를 명시 주입하므로 정상 경로에선 무영향.
# 직접 실행(테스트·디버그) 시 사용자 홈으로 새지 않도록 안전 기본값.
EVENTS_LOG="${EVENTS_LOG:-$REPO_ROOT/.agent-harness/events.log}"
worker="${HARNESS_WORKER:-unknown}"
task="${HARNESS_TASK:-}"
if [ -z "$task" ]; then
  _htf="${REPO_ROOT}/.agent-harness/.harness-task.${worker}"
  if [ -f "$_htf" ]; then task="$(cat "$_htf" 2>/dev/null || true)"; fi
fi
[ -z "$task" ] && task="-"

raw="$(cat)"
# jq 있으면 사용, 없으면 grep 폴백 (의존성 최소화)
if command -v jq >/dev/null 2>&1; then
  fpath="$(printf '%s' "$raw" | jq -r '.tool_input.file_path // empty' 2>/dev/null)"
else
  fpath="$(printf '%s' "$raw" | grep -o '"file_path"[^,}]*' | head -1 | sed 's/.*: *"//; s/"$//')"
fi
[ -z "$fpath" ] && exit 0   # 경로 없는 도구 호출은 무시

# 메타 산출물 화이트리스트 skip (D6·F6).
# tasks/results 는 작업 흐름이라 기록 대상. 메타(events.log 자체·커서·상태·boot·review/) 만 skip.
# repo-relative 변환 전, 절대경로 기준으로 점검 (F6: 절대경로 Write 도 잡힘).
case "$fpath" in
  "$REPO_ROOT/.agent-harness/events.log") exit 0 ;;
  "$REPO_ROOT/.agent-harness/.review-cursor."*) exit 0 ;;
  "$REPO_ROOT/.agent-harness/.harness-task."*) exit 0 ;;
  "$REPO_ROOT/.agent-harness/.harness-state") exit 0 ;;
  "$REPO_ROOT/.agent-harness/.boot/"*) exit 0 ;;
  "$REPO_ROOT/.agent-harness/review/"*) exit 0 ;;
esac

# repo 상대경로화 (길이 억제 — spec §5.2)
case "$fpath" in
  "$REPO_ROOT"/*) rel="${fpath#"$REPO_ROOT"/}" ;;
  *) rel="$fpath" ;;
esac

ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
# hook 안전성: 로깅 실패가 워커 claude 흐름을 막으면 안 됨.
# 디렉터리 보장 + append 실패 흡수(둘 다 — 방어 깊이).
mkdir -p "$(dirname "$EVENTS_LOG")" 2>/dev/null || true
printf '%s\t%s\t%s\t%s\t%s\n' "$ts" "$worker" "$task" "modify" "$rel" >> "$EVENTS_LOG" 2>/dev/null || true
