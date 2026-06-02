#!/usr/bin/env bash
# claude 벤더 어댑터 — awa-up.sh/lib.sh 의 claude 고유 로직 이관.
# source 전용 (진입점 없음). 호출 전 HARNESS_ROOT/PROJECT_ROOT 가 export 되어 있어야 함.

# 부트 명령 전체 (suffix 포함).
# $1=model $2=settings_path $3=session_id $4=plan_file(opt)
vendor_boot_cmd() {
  local model="$1" settings="${2:-}" sid="${3:-}" plan="${4:-}"
  local cmd
  cmd="$(printf 'claude --model %s' "$model")"
  [ -n "$settings" ] && cmd="$cmd --settings \"$settings\""
  [ -n "$sid" ] && cmd="$cmd --session-id $sid"
  [ -n "$plan" ] && cmd="$cmd --append-system-prompt-file \"$plan\""
  printf '%s' "$cmd"
}

# trust 통과 + REPL ready 폴링. $1=pane_id → rc 0/1. awa-up.sh:wait_repl 로직 이관.
# 화면 문자열·sleep 간격·반복 횟수는 wait_repl 과 바이트 일치 (역호환 회귀 안전망).
vendor_wait_ready() {
  local s="$1" i dump
  for i in $(seq 1 60); do
    sleep 2
    dump="$(tmux capture-pane -t "$s" -p 2>/dev/null)"
    # trust 화면이 보이면 매 폴링마다 Enter 재전송 (첫 전송 씹힘·재출현 대비).
    if printf '%s' "$dump" | grep -Eq 'trust this folder|Yes, I trust'; then
      tmux send-keys -t "$s" Enter
      continue
    fi
    # negative 신호 — 명백한 에러면 timeout 까지 안 기다리고 즉시 fail.
    if printf '%s' "$dump" | grep -qE 'Error:|Could not authenticate|not logged in|failed to start'; then
      return 1
    fi
    # ready 신호 — 다중 OR 매치. 하나라도 떴으면 REPL 준비됨.
    # ★ 2.1.160 라이브 발견(2026-06-02): 좁은 pane(4분할 220x12)에선 스플래시
    #   (Claude Code v·Welcome back)가 위로 스크롤돼 사라지고 'bypass permissions on'
    #   도 상태줄에서 빠져, 옛 4패턴 다 매칭 실패 → pane당 120s 풀 폴링(리뷰어 3개=8분).
    #   해소: REPL 기동 후에만 뜨는 토큰 게이지 'of N k tokens' 추가(명령 echo·일반
    #   출력엔 안 잡혀 false positive 무관 — test-wait-repl-patterns T3 가드 유지).
    #   2026-05-21 P2(v2.1.145 동종 사건)의 연장 — claude 버전 업마다 재발(wait_repl 취약성).
    if printf '%s' "$dump" | grep -qE 'Claude Code v[0-9]|Welcome back|bypass permissions on|accept edits on|of [0-9]+k tokens'; then
      return 0
    fi
  done
  return 1
}

# settings 생성. $1=role $2=entry_name → rc 0/1, echo settings 경로.
# lib.sh::generate_worker_settings 위임 — rc 그대로 전파(fail-safe).
vendor_gen_settings() {
  local role="$1" entry_name="${2:-$role}"
  generate_worker_settings "$role" "$entry_name"
}

# 역할/plan 주입. claude 는 plan 을 boot_cmd 의 --append-system-prompt-file 로 처리 → no-op.
# $1=pane_id $2=boot_file
vendor_inject_role() { :; }

# LEAD 부트 입력에 덧붙일 plan 지시문. claude 는 plan 이 이미 시스템 컨텍스트에
# 주입(--append-system-prompt-file)되어 LEAD 가 능동 탐색 불필요 → 빈 문자열.
# $1=plan_file → echo directive(없으면 빈 출력).
vendor_lead_plan_directive() { :; }

# 역할별 기본 모델. $1=role → echo model (claude CLI alias = 항상 최신 버전).
# 품질 우선: haiku 미사용. lead·reviewer 는 최고 모델 opus, 그 외 sonnet.
vendor_default_model() {
  case "$1" in
    lead|LEAD) echo "opus" ;;
    reviewer-*|review-manager) echo "opus" ;;   # 리뷰어/리뷰 총괄 — 품질 우선 최고 모델
    researcher) echo "opus" ;;   # 조사 워커 — 대량 정보를 컨텍스트에 담아 종합하므로 최고 모델
    pm|PM) echo "sonnet" ;;
    *) echo "sonnet" ;;   # engineer 포함 — 명세된 코드 구현은 sonnet 으로 충분
  esac
}
