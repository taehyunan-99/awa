#!/usr/bin/env bash
# PostToolUse hook 스크립트. stdin 으로 hook JSON 수신 →
# 수정 파일 경로를 repo 상대경로 5필드 라인으로 events.log 에 결정적 append.
# 워커명=HARNESS_WORKER, task=HARNESS_TASK (team-up 이 pane env 로 주입).
# 자기보고 아님 — claude 가 Edit/Write 쓰면 hook 이 무조건 실행됨(이슈 6).
set -uo pipefail

EVENTS_LOG="${EVENTS_LOG:-$HOME/.agent-harness-events.log}"
REPO_ROOT="${REPO_ROOT:-$PWD}"
worker="${HARNESS_WORKER:-unknown}"
task="${HARNESS_TASK:--}"

raw="$(cat)"
# jq 있으면 사용, 없으면 grep 폴백 (의존성 최소화)
if command -v jq >/dev/null 2>&1; then
  fpath="$(printf '%s' "$raw" | jq -r '.tool_input.file_path // empty' 2>/dev/null)"
else
  fpath="$(printf '%s' "$raw" | grep -o '"file_path"[^,}]*' | head -1 | sed 's/.*: *"//; s/"$//')"
fi
[ -z "$fpath" ] && exit 0   # 경로 없는 도구 호출은 무시

# repo 상대경로화 (길이 억제 — spec §5.2)
case "$fpath" in
  "$REPO_ROOT"/*) rel="${fpath#"$REPO_ROOT"/}" ;;
  *) rel="$fpath" ;;
esac

ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf '%s\t%s\t%s\t%s\t%s\n' "$ts" "$worker" "$task" "modify" "$rel" >> "$EVENTS_LOG"
