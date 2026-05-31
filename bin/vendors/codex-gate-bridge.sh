#!/usr/bin/env bash
# codex PreToolUse hook → 단일 정책 엔진(permission-gate.sh) 브리지.
# codex stdin 스키마는 claude 와 동일(tool_name/tool_input) — 공식 문서 확인.
# 차이: codex 고유 tool_name(apply_patch) 을 claude 등가(Edit)로 정규화 후 그대로 위임.
# 출력도 hookSpecificOutput.permissionDecision 동일 → permission-gate 출력 그대로 전달.
set -u

# ★★ fail-CLOSED 방어 (P14 2026-05-31): codex 는 hook 실행 시 HARNESS_ROOT/PROJECT_ROOT
#   env 를 주지 않는다 → 기존 `${PROJECT_ROOT:?}` 가 unbound 로 즉사(exit 1). codex 는
#   hook 크래시(exit 1)를 "통과"로 처리 → 위험명령 우회(deny-bounded 무력화, 실측).
#   permission-gate.sh 의 fail-closed trap 에 도달조차 못 하므로 bridge *자체*가 방어한다:
#   결정(allow/deny JSON) 미출력 상태로 종료하면 trap 이 deny JSON 발행 → codex 가 차단.
_EMITTED=0
_bridge_fail_closed() {
  local rc=$?
  if [ "$_EMITTED" != "1" ]; then
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"gate-bridge-crash-fail-closed(rc=%s)"}}\n' "$rc"
  fi
  exit 0   # JSON 으로 deny 전달했으니 exit 0 (codex 는 exit 0 + deny JSON 으로 차단).
}
trap _bridge_fail_closed EXIT

EVENT="$(cat)"

# ★ HARNESS_ROOT 자기도출 (P14): codex 가 env 를 안 주므로 이 스크립트 위치에서 계산.
#   bin/vendors/codex-gate-bridge.sh → ../../ = HARNESS_ROOT. env 로 받은 값이 있으면 우선.
if [ -z "${HARNESS_ROOT:-}" ]; then
  _self="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  HARNESS_ROOT="$_self"
fi
# ★ PROJECT_ROOT 자기도출 (P14): codex stdin 의 cwd 필드에서 취득. env 우선.
if [ -z "${PROJECT_ROOT:-}" ]; then
  PROJECT_ROOT="$(printf '%s' "$EVENT" | jq -r '.cwd // empty' 2>/dev/null || true)"
fi
# 둘 중 하나라도 못 구하면 fail-closed (trap 이 deny 발행) — 정책 엔진 호출 불가 시 차단.
if [ -z "${HARNESS_ROOT:-}" ] || [ -z "${PROJECT_ROOT:-}" ]; then
  exit 1   # trap → deny JSON
fi

NORMALIZED="$(printf '%s' "$EVENT" | jq -c '
  if (.tool_name // "") == "apply_patch" then .tool_name = "Edit" else . end
' 2>/dev/null || true)"
[ -z "$NORMALIZED" ] && NORMALIZED="$EVENT"   # jq 실패 시 원본 (permission-gate 가 fail-closed)

OUT="$(printf '%s' "$NORMALIZED" | \
  PROJECT_ROOT="$PROJECT_ROOT" HARNESS_ROOT="$HARNESS_ROOT" \
  WORKER="${WORKER:-codex}" ENTRY_ROLE="${ENTRY_ROLE:-dev}" \
  bash "$HARNESS_ROOT/bin/permission-gate.sh")"

# ★ allow/deny 분기 (P16 2026-05-31): permission-gate 는 claude wire 형식으로
#   permissionDecision:"allow"|"deny" 를 낸다. 그런데 codex 0.130 은 "allow" 값을
#   `unsupported permissionDecision:allow` 로 거부 → hook failed → 워커가 read-only
#   명령조차 진행 못 하고 멈춤(실측: LEAD 가 AUTO-ALLOW 로그 남기고도 4분+ 행).
#   codex 의 통과 신호는 "allow JSON" 이 아니라 *빈 출력 + exit 0*(deny 만 JSON 으로 명시).
#   → allow 면 무출력 종료(통과), deny 면 JSON 그대로 전달(차단). 빈 OUT 은 trap 이 fail-closed.
if [ -z "$OUT" ]; then
  exit 1   # 정책 엔진 무출력 = 비정상 → trap fail-closed deny
fi
_decision="$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null || true)"
case "$_decision" in
  deny)
    _EMITTED=1
    printf '%s\n' "$OUT" ;;      # deny JSON 그대로 → codex 차단
  allow)
    _EMITTED=1 ;;                # 빈 출력 + exit 0 → codex 통과 (allow JSON 금지)
  *)
    exit 1 ;;                    # 알 수 없는 결정 → fail-closed deny
esac
