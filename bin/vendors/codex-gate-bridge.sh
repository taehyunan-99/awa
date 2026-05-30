#!/usr/bin/env bash
# codex PreToolUse hook → 단일 정책 엔진(permission-gate.sh) 브리지.
# codex stdin 스키마는 claude 와 동일(tool_name/tool_input) — 공식 문서 확인.
# 차이: codex 고유 tool_name(apply_patch) 을 claude 등가(Edit)로 정규화 후 그대로 위임.
# 출력도 hookSpecificOutput.permissionDecision 동일 → permission-gate 출력 그대로 전달.
set -u

EVENT="$(cat)"

NORMALIZED="$(printf '%s' "$EVENT" | jq -c '
  if (.tool_name // "") == "apply_patch" then .tool_name = "Edit" else . end
' 2>/dev/null || true)"
[ -z "$NORMALIZED" ] && NORMALIZED="$EVENT"   # jq 실패 시 원본 (permission-gate 가 fail-closed)

printf '%s' "$NORMALIZED" | \
  PROJECT_ROOT="${PROJECT_ROOT:?}" HARNESS_ROOT="${HARNESS_ROOT:?}" \
  WORKER="${WORKER:-codex}" ENTRY_ROLE="${ENTRY_ROLE:-dev}" \
  bash "$HARNESS_ROOT/bin/permission-gate.sh"
