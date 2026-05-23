#!/usr/bin/env bash
# PreToolUse hook: stdin JSON → permissionDecision JSON. 워커 프로세스 내 동기 실행.
# set -u 만 (set -e 금지 — 5차 결함 2: 분류 non-zero 가 조기종료 유발 방지).
set -u

# ★★ fail-CLOSED 방어 (3차 리뷰 — claude 는 hook exit 1 을 "non-blocking error → 도구 통과"
#   로 처리. exit 2 또는 deny JSON 만 차단). hook 이 크래시(set -u 사망·source 실패·jq 부재)
#   하면 도구가 *통과*하는 보안 구멍 → EXIT trap 으로 "결정 미출력 시 deny JSON 보장".
#   _DECIDED 플래그: emit_decision 이 세움. trap 은 미결정 시에만 deny 발행.
_DECIDED=0
_fail_closed() {
  local rc=$?
  if [ "$_DECIDED" != "1" ]; then
    # emit_decision 이 아직이면(크래시) 최소 deny JSON 을 직접 print (jq 없을 수도 → printf 폴백).
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"gate-crash-fail-closed(rc=%s)"}}\n' "$rc"
  fi
  exit 0   # JSON 으로 deny 전달했으니 exit 0 (claude 는 exit 0 + JSON 만 신뢰).
}
trap _fail_closed EXIT

# 라이브러리 모드(단위 테스트)면 trap·env 검증 스킵 — 함수만 로드.
if [ "${PERM_GATE_LIB_ONLY:-0}" != "1" ]; then
  PROJECT_ROOT="${PROJECT_ROOT:?}"
  HARNESS_ROOT="${HARNESS_ROOT:?}"
  WORKER="${WORKER:-unknown}"
  ENTRY_ROLE="${ENTRY_ROLE:-default}"
  STATE_DIR="${PROJECT_ROOT}/.agent-harness/state"
  mkdir -p "${STATE_DIR}"   # ★ 5차: log_safe 가 state/ 없으면 로그 소실. team-up Step3 가 보통 만들지만 부트순서 의존 제거 (hook 자기보장 — 견고).
  export LOG="${STATE_DIR}/permission-gate.log"   # hook 이 직접 설정 (데몬 폐기)
else
  trap - EXIT   # 라이브러리 모드는 trap 해제 (source 종료 시 deny 발행 방지)
  : "${PROJECT_ROOT:=}" "${HARNESS_ROOT:=}" "${WORKER:=x}" "${ENTRY_ROLE:=dev}" "${STATE_DIR:=}"
fi

# shellcheck disable=SC1091
source "${HARNESS_ROOT}/bin/lib.sh"
# shellcheck disable=SC1091
source "${HARNESS_ROOT}/bin/matrix-lookup.sh"
# shellcheck disable=SC1091
source "${HARNESS_ROOT}/bin/danger-check.sh"
# shellcheck disable=SC1091
source "${HARNESS_ROOT}/bin/classify.sh"

# ★ jq -n 으로 생성 (claude docs 권장): reason 에 따옴표·역슬래시 들어가도 JSON 안전.
#   printf 박기는 reason 에 특수문자 시 JSON 파손 (현 reason 은 안전하나 패턴 확장 대비).
#   stdout 엔 이 JSON 만 — 다른 출력 섞이면 claude 파싱 실패 (docs 확인).
emit_decision() {
  local decision="$1" reason="$2"
  # jq 부재/실패 시에도 deny 만은 printf 폴백 (fail-closed). allow 는 jq 성공 시에만.
  if jq -nc --arg d "$decision" --arg r "$reason" \
       '{hookSpecificOutput:{hookEventName:"PreToolUse", permissionDecision:$d, permissionDecisionReason:$r}}' 2>/dev/null; then
    _DECIDED=1
  elif [ "$decision" = "deny" ]; then
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"deny(jq-fallback)"}}\n'
    _DECIDED=1
  fi
  # allow + jq 실패 시 _DECIDED 안 세움 → EXIT trap 이 fail-closed deny (allow 누수 방지).
}
emit_allow() { emit_decision allow "$1"; }
emit_deny()  { emit_decision deny  "$1"; }

queue_incident() {
  local tool="$1" input="$2" category="$3"
  mkdir -p "${STATE_DIR}/incidents"
  local uuid; uuid="$(uuidgen)"
  local f="${STATE_DIR}/incidents/${uuid}.json"
  local tmp="${f}.tmp.$$.${RANDOM}"
  jq -n --arg w "$WORKER" --arg tool "$tool" --argjson inp "$input" \
        --arg cat "$category" --argjson ts "$(timestamp)" \
    '{worker:$w, tool:$tool, input:$inp, category:$cat, timestamp:$ts, notified:false}' \
    > "$tmp" && mv "$tmp" "$f"
}

main() {
  local EVENT tool input tuid verdict detail T
  T=$'\t'
  EVENT="$(cat)"
  # jq 가 깨진 EVENT 에 parse error → 빈 출력. set -u 라도 || true 로 빈 문자열 흡수 후 fallback.
  tool="$(printf '%s' "$EVENT" | jq -r '.tool_name // ""' 2>/dev/null || true)"
  input="$(printf '%s' "$EVENT" | jq -c '.tool_input // {}' 2>/dev/null || true)"
  tuid="$(printf '%s' "$EVENT" | jq -r '.tool_use_id // ""' 2>/dev/null || true)"
  # ★ input fallback: jq 실패(빈 문자열) 또는 "null" 모두 '{}' 로 — 이후 --argjson 파손 방지.
  case "$input" in ""|null) input='{}' ;; esac
  [ -z "$tool" ] && { emit_deny "gray:unparseable-event"; return; }   # tool 못 읽으면 fail-closed

  IFS="$T" read -r verdict detail <<EOF
$(classify "$ENTRY_ROLE" "$tool" "$input")
EOF

  case "$verdict" in
    matrix)
      emit_allow "matrix:${detail}"
      log_safe "[$(timestamp)] ${WORKER} ${tool} → MATRIX-ALLOW (${detail})" ;;
    danger)
      queue_incident "$tool" "$input" "$detail"
      emit_deny "danger:${detail}"
      log_safe "[$(timestamp)] ${WORKER} ${tool} → AUTO-DENY (${detail})" ;;
    auto)
      local acat apat
      IFS="$T" read -r acat apat <<EOF2
$detail
EOF2
      add_to_allow "$ENTRY_ROLE" "$apat"
      emit_allow "auto:${acat}:${apat}"
      log_safe "[$(timestamp)] ${WORKER} ${tool} → AUTO-ALLOW (${acat}: ${apat})" ;;
    gray)
      gate_gray "$tool" "$input" "$tuid" ;;
    *)
      emit_deny "unknown-verdict" ;;   # classify 는 항상 위 4종 — 방어적
  esac
}

# gate_gray 는 Task 4 에서 구현. 임시 placeholder (회색=deny).
gate_gray() { emit_deny "gray:not-implemented"; }

# 라이브러리 모드(단위 테스트)면 main 미실행 — 함수만 로드 (stdin hang 회피).
if [ "${PERM_GATE_LIB_ONLY:-0}" != "1" ]; then
  main
  # main 이 정상 완료 + emit 했으면 _DECIDED=1 → EXIT trap 은 추가 deny 안 냄.
  # 만약 어떤 분기도 emit 안 했으면(논리 버그) trap 이 fail-closed deny 발행 (안전망).
  trap - EXIT
  [ "$_DECIDED" = "1" ] || printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"no-decision-fail-closed"}}\n'
fi
