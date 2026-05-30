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
  mkdir -p "${STATE_DIR}"   # ★ 5차: log_safe 가 state/ 없으면 로그 소실. awa-up Step3 가 보통 만들지만 부트순서 의존 제거 (hook 자기보장 — 견고).
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

queue_pending_ask() {
  local uuid="$1" worker="$2" role="$3" tool="$4" input="$5" gate_pid="$6" tuid="$7" channel="$8"
  mkdir -p "${STATE_DIR}/pending-asks"
  local f="${STATE_DIR}/pending-asks/${uuid}.json"
  local tmp="${f}.tmp.$$.${RANDOM}"
  jq -n --arg u "$uuid" --arg w "$worker" --arg r "$role" --arg tool "$tool" \
        --argjson inp "$input" --argjson ts "$(timestamp)" \
        --arg gp "$gate_pid" --arg tu "$tuid" --arg ch "$channel" \
    '{uuid:$u, worker:$w, entry_role:$r, tool:$tool, input:$inp, timestamp:$ts, gate_pid:($gp|tonumber), tool_use_id:$tu, channel:$ch}' \
    > "$tmp" && mv "$tmp" "$f"
}

cleanup_pending() {
  local uuid="$1"
  rm -f "${STATE_DIR}/pending-asks/${uuid}.json" "${STATE_DIR}/pending-asks/${uuid}.response"
}

gate_gray() {
  local tool="$1" input="$2" tuid="${3:-}"
  local uuid; uuid="${GATE_TEST_UUID:-$(uuidgen)}"   # pending-ask 파일명 (추적성 — uuid 유지)
  local poll_max="${GATE_POLL_MAX:-540}"
  # ★ 채널명 = 워커 고정 (3차 리뷰 채널 누수 해소): uuid 일회용이면 timeout 후 woken=1 채널이
  #   tmux 서버에 영구 잔존(정리 명령 없음). 워커 고정명이면 다음 회색명령이 같은 채널 재방문
  #   → cmd_wait_for_remove 로 정리 → 누수 상수 제한. hook 은 동기라 워커당 동시 1개만 → 충돌 X.
  #   채널명 비영숫자 정리(tmux 안전): entry_name 의 영숫자 외 문자를 - 로.
  local ch_safe; ch_safe="$(printf '%s' "$WORKER" | sed 's#[^a-zA-Z0-9]#-#g')"
  local channel="${GATE_TEST_CHANNEL:-harness-gate-${ch_safe}}"
  local resp="${STATE_DIR}/pending-asks/${uuid}.response"
  queue_pending_ask "$uuid" "$WORKER" "$ENTRY_ROLE" "$tool" "$input" "$$" "$tuid" "$channel"
  notify_gray_log "$uuid" "$tool"
  # wait-for 블로킹 (서버 부재면 즉시 rc=0). run_with_timeout 무응답 상한
  #   (macOS timeout 부재 → lib.sh 의 SIGKILL 폴백, Task 0). 결과 rc 무시 — .response 로만 판정.
  # ★ stale woken 안전 (4차 리뷰 — .response 단일 방어선이 자가치유로 흡수): 워커 고정 채널
  #   재사용 시 "이전 라운드 죽은 hook 에 -S → woken 잔존 → 이번 wait 즉시반환" 이 생길 수
  #   있으나, 즉시 깬 hook 도 아래 `.response` 존재 검증을 거치므로 resp 없으면 deny → 거짓
  #   allow 0, 회색명령 1회 거짓 deny 만(워커 재시도로 자가치유). stale 은 cmd_wait_for_remove
  #   로 1회만 소비(실측) → 다음 wait 정상 블로킹. 3차의 lead `kill -0` wake-gating 은 race 를
  #   못 막으면서(hook 셸 스폰~wait enqueue 사이 틈) 불필요 → 제거. hook 은 단순 유지.
  # GATE_SKIP_WAIT=1 (단위 테스트 전용): 실제 tmux wait-for 호출을 건너뛴다. 단위 테스트가
  #   외부 tmux 서버 상태에 의존하지 않도록 격리 — 서버가 있으면 대기자 없는 채널에 진짜
  #   블로킹돼 hang, 채널 woken 잔존에 따라 비결정적(실측 확인)이기 때문. 테스트는 .response 를
  #   미리 깔고 이 분기로 곧장 검증 로직(아래)만 본다. 실제 wait-for 블로킹 경로는 probe 가 커버.
  [ "${GATE_SKIP_WAIT:-0}" = "1" ] || run_with_timeout "$poll_max" tmux wait-for "$channel" >/dev/null 2>&1 || true
  # ★ 단일 방어선: .response 존재만이 allow 근거 (서버부재·서버사망·timeout 모두 파일 없음).
  if [ ! -f "$resp" ]; then
    cleanup_pending "$uuid"
    log_safe "[$(timestamp)] ${WORKER} gate DENY (응답없음) uuid=${uuid} ch=${channel}"
    emit_deny "gray:timeout-or-no-response"
    return
  fi
  local decision; decision="$(cat "$resp")"
  cleanup_pending "$uuid"
  case "$decision" in
    approve-once)
      emit_allow "gray:approve-once" ;;
    approve-permanent:*)
      local scope pattern
      scope="${decision#approve-permanent:}"
      pattern="$(derive_pattern "$tool" "$input" "$scope")"
      # 복합/멀티라인 명령은 derive_pattern 이 빈 문자열 반환(안전 prefix 불가) →
      # 학습 생략하고 이번 1회만 allow 로 강등 (7차 결함3). 학습 가능 패턴만 영구화.
      if [ -z "$pattern" ]; then
        emit_allow "gray:approve-permanent-downgraded-to-once"
      else
        add_to_allow "$ENTRY_ROLE" "$pattern"
        emit_allow "gray:approve-permanent:${scope}"
      fi
      ;;
    *)
      emit_deny "gray:deny" ;;
  esac
}

notify_gray_log() {
  log_safe "[$(timestamp)] ${WORKER} ${2} → USER-ASK (uuid=${1})"
}

# 라이브러리 모드(단위 테스트)면 main 미실행 — 함수만 로드 (stdin hang 회피).
if [ "${PERM_GATE_LIB_ONLY:-0}" != "1" ]; then
  main
  # main 이 정상 완료 + emit 했으면 _DECIDED=1 → EXIT trap 은 추가 deny 안 냄.
  # 만약 어떤 분기도 emit 안 했으면(논리 버그) trap 이 fail-closed deny 발행 (안전망).
  trap - EXIT
  [ "$_DECIDED" = "1" ] || printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"no-decision-fail-closed"}}\n'
fi
