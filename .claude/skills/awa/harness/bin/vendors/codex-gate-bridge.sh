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

_TOOL="$(printf '%s' "$EVENT" | jq -r '.tool_name // ""' 2>/dev/null || true)"

# ★★ apply_patch 다중파일 경로 추출 (2026-06-03 라이브 결함): codex 의 주력 파일쓰기
#   도구 apply_patch 는 hook payload 의 tool_input.command(또는 .input) 에 *patch 본문*
#   (`*** Begin Patch` / `*** Add File: <path>` / `*** Update File: <path>` …) 을 통째로
#   담아 보낸다 — claude 의 `tool_input.file_path` 와 스키마가 다르다. 기존 bridge 는
#   tool_name 만 Edit 로 바꾸고 file_path 없는 채 위임 → permission-gate 가 빈 file_path →
#   gray → USER-ASK → 타임아웃 DENY → codex verdict 영구 소실(실측: review/ verdict 가
#   apply_patch 로는 절대 안 써지고 codex 가 Bash printf 폴백으로만 우회).
#   → apply_patch 면 patch 본문에서 모든 대상 경로를 뽑아 *각각* file_path 인 Edit 이벤트로
#   permission-gate 를 호출. 하나라도 deny 면 전체 deny(fail-safe, 패치는 원자적이므로
#   일부만 허용 불가). 경로 추출 0건이면 빈 file_path 로 위임 → 기존 gray 차단 보존
#   (보안 약화 없음: 못 읽으면 막는다).
if [ "$_TOOL" = "apply_patch" ]; then
  _PATCH="$(printf '%s' "$EVENT" | jq -r '.tool_input.command // .tool_input.input // .tool_input.patch // ""' 2>/dev/null || true)"
  # `*** Add/Update/Delete/Move File: <path>` 의 <path> 추출 ('Move' 는 출발지 기준 검사).
  _PATHS="$(printf '%s' "$_PATCH" | sed -E -n 's/^\*\*\* (Add|Update|Delete|Move) File: //p')"
  if [ -n "$_PATHS" ]; then
    OUT=""   # 빈 = 통과 누적. deny 발견 시 그 JSON 으로 채워 즉시 종료.
    while IFS= read -r _p; do
      [ -z "$_p" ] && continue
      _EV1="$(jq -nc --arg p "$_p" '{tool_name:"Edit", tool_input:{file_path:$p}}' 2>/dev/null || true)"
      [ -z "$_EV1" ] && { OUT='{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"apply_patch:path-encode-fail"}}'; break; }
      _O1="$(printf '%s' "$_EV1" | \
        PROJECT_ROOT="$PROJECT_ROOT" HARNESS_PROJECT="$PROJECT_ROOT" HARNESS_ROOT="$HARNESS_ROOT" \
        WORKER="${WORKER:-codex}" ENTRY_ROLE="${ENTRY_ROLE:-dev}" \
        bash "$HARNESS_ROOT/bin/permission-gate.sh")"
      _d1="$(printf '%s' "$_O1" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null || true)"
      if [ "$_d1" = "deny" ]; then OUT="$_O1"; break; fi   # 한 경로라도 deny → 전체 deny
      if [ -z "$_O1" ] || [ "$_d1" != "allow" ]; then       # 무출력/미지결정 → fail-closed
        OUT='{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"apply_patch:gate-indeterminate"}}'; break
      fi
      # allow 면 OUT 빈 채 유지(이 경로 통과). 다음 경로 검사.
    done <<EOF2
$_PATHS
EOF2
    # 루프 정상 종료(모든 경로 allow)면 OUT="" → 빈출력=통과. deny 면 OUT 에 JSON.
    if [ -z "$OUT" ]; then _EMITTED=1; exit 0; fi          # 전 경로 allow → 빈출력 통과
    _decision="$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null || true)"
    if [ "$_decision" = "deny" ]; then _EMITTED=1; printf '%s\n' "$OUT"; exit 0; fi
    exit 1   # 도달 불가(방어)
  fi
  # 경로 추출 0건 → 아래 일반 경로로 떨어져 빈 file_path Edit 위임 → gray 차단(보존).
fi

NORMALIZED="$(printf '%s' "$EVENT" | jq -c '
  if (.tool_name // "") == "apply_patch" then .tool_name = "Edit" else . end
' 2>/dev/null || true)"
[ -z "$NORMALIZED" ] && NORMALIZED="$EVENT"   # jq 실패 시 원본 (permission-gate 가 fail-closed)

OUT="$(printf '%s' "$NORMALIZED" | \
  PROJECT_ROOT="$PROJECT_ROOT" HARNESS_PROJECT="$PROJECT_ROOT" HARNESS_ROOT="$HARNESS_ROOT" \
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
