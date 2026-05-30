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
  # ★ .response 파일 폴링 (P11 탈-tmux 2026-05-31): 기존엔 `tmux wait-for "$channel"`
  #   1회 블로킹으로 lead 의 -S 깨움을 기다렸다. 그러나 hook 은 워커 프로세스 안에서 돌고,
  #   codex sandbox(seatbelt network deny)에선 tmux 소켓 connect 가 즉시 실패(rc≠0, 10ms)
  #   → wait-for 가 응답 전에 빠져나가 .response 없음 → 거짓 deny 양산(회색명령 사실상 전부
  #   차단). 해소: tmux 의존 제거하고 .response 파일이 나타날 때까지 폴링. lead 는 .response
  #   를 atomic write 만 하면 되고 -S 로 깨울 필요 없음(hook 이 능동 폴링). claude(비-sandbox)도
  #   동일 경로 — wait-for 즉시 wake 대비 최대 1s 지연만 추가(허용). 채널 누수·stale woken
  #   문제도 동반 소멸(tmux 채널 자체를 안 씀).
  # GATE_SKIP_WAIT=1 (단위 테스트 전용): 폴링 없이 곧장 .response 검증 로직만 본다(테스트가
  #   .response 를 미리 깔아둠). 실제 폴링 경로는 probe/통합 테스트가 커버.
  if [ "${GATE_SKIP_WAIT:-0}" != "1" ]; then
    local _i
    for _i in $(seq 1 "$poll_max"); do
      [ -f "$resp" ] && break
      # hook 자신이 살아있는 한 폴링. lead 가 응답 쓰면 즉시 종료. 1s 간격(watcher 폴링과 정합).
      sleep 1
    done
  fi
  # ★ 단일 방어선: .response 존재만이 allow 근거 (응답없음·timeout 모두 파일 없음).
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
