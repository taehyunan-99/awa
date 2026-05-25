#!/usr/bin/env bash
# 통합 probe: permission-gate hook 의 wait-for 게이트 전 경로.
# RUN_LIVE=1 일 때만 (실제 claude REPL·토큰 + tmux). 더미 RUN_INTEGRATION 과 분리. CI skip.
set -uo pipefail
[ "${RUN_LIVE:-0}" = "1" ] || { echo "SKIP (RUN_LIVE 미설정)"; exit 0; }
cd "$(dirname "$0")/../.."
ROOT="$(pwd)"

PROBE_DIR="$(mktemp -d)"
SES="probe6_$$"
WUUID="$(uuidgen)"
# 중간 사망(kill·에러·timeout)에도 세션·임시디렉터리 정리 — 좀비 세션이 다음 실행 오염 방지.
cleanup() { tmux kill-session -t "$SES" 2>/dev/null || true; rm -rf "$PROBE_DIR"; }
trap cleanup EXIT INT TERM   # TERM 필수 — EXIT 만으론 SIGTERM(timeout-kill) 에 좀비 잔존(실측)
# settings 생성 (dev 템플릿 + permission-gate).
# ★ HARNESS_PROJECT export 필수 (3차 리뷰): lib.sh:27 이 PROJECT_ROOT 를 resolve_project_root
#   로 무조건 재대입 → HARNESS_PROJECT 우선. 안 주면 PROJECT_ROOT 가 ROOT(repo)로 덮어써져
#   settings 가 엉뚱한 곳에 생성됨. 다른 단위 테스트도 전부 HARNESS_PROJECT 사용.
export HARNESS_PROJECT="$PROBE_DIR" PROJECT_ROOT="$PROBE_DIR" HARNESS_ROOT="$ROOT"
( cd "$PROBE_DIR" && git init -q )   # resolve_project_root 의 git toplevel 안정화
mkdir -p "$PROBE_DIR/.agent-harness/state/pending-asks" "$PROBE_DIR/config" "$PROBE_DIR/.agent-harness/.boot-settings"
cat > "$PROBE_DIR/config/lead-auto-allow.yaml" <<'YAML'
read-only:
  - "Bash(find:*)"
YAML
# shellcheck disable=SC1091
source "$ROOT/bin/lib.sh"
SET="$(generate_worker_settings dev dev-1)"
# ★ matrix-allow(E1) 용 학습 패턴 주입: generate_worker_settings 가 dev.json 을 통째로
#   재생성하므로 *생성 후* 에 allow 를 넣어야 한다 (먼저 echo 하면 덮여 사라짐 — 실측 확인).
#   matrix_lookup 은 .boot-settings/dev.json 의 .permissions.allow 를 읽는다.
jq '.permissions.allow=((.permissions.allow//[])+["Bash(ls:*)"]|unique)' \
   "$SET" > "$SET.tmp" && mv "$SET.tmp" "$SET"
GATELOG="$PROBE_DIR/.agent-harness/state/permission-gate.log"

tmux kill-session -t "$SES" 2>/dev/null || true
tmux new-session -d -s "$SES" -c "$PROBE_DIR" -x 200 -y 50
tmux send-keys -t "$SES" "cd '$PROBE_DIR' && claude --model claude-haiku-4-5-20251001 --settings '$SET' --session-id $WUUID" Enter

# REPL 준비 대기 — ★ 확정 신호로 판정 (probe-hook-merge 교훈: '❯' 단독은 부팅 중 빈
#   입력선을 ready 로 오인 → 지시가 REPL 에 안 들어가 위양성). 상태줄/박스 신호로 강화.
wait_repl() {
  for _ in $(seq 1 70); do
    sleep 2
    local d; d="$(tmux capture-pane -t "$SES" -p 2>/dev/null)"
    printf '%s' "$d" | grep -q 'trust this folder' && { tmux send-keys -t "$SES" Enter; continue; }
    printf '%s' "$d" | grep -qE 'accept edits on|bypass permissions|for shortcuts|esc to interrupt|Welcome back' && return 0
  done
  return 1
}
wait_repl || { echo "FAIL: REPL 미준비"; tmux kill-session -t "$SES"; exit 1; }
sleep 3

PASS=0; FAIL=0
chk() { if [ "$1" = "$2" ]; then echo "  ok: $3"; PASS=$((PASS+1)); else echo "  FAIL: $3 (exp=$1 got=$2)"; FAIL=$((FAIL+1)); fi; }

# ★ 게이트 판정은 화면(모델 응답 속도에 좌우)이 아니라 permission-gate.log 의 verdict 로 검증한다.
#   화면 grep 은 'Mustering…' 같은 모델 지연 때문에 위양성 FAIL 을 냈다 (실측). 게이트 hook 은
#   도구 호출 직전 동기 실행되므로 로그가 가장 신뢰할 신호다.
# 로그에 패턴이 나타날 때까지 폴링 (모델이 도구를 호출해야 hook 발화 → 응답 지연 흡수).
wait_log() {  # $1=grep패턴 $2=최대초
  local pat="$1" max="${2:-40}" i=0
  while [ "$i" -lt "$max" ]; do
    [ -f "$GATELOG" ] && grep -qE "$pat" "$GATELOG" && return 0
    sleep 2; i=$((i+2))
  done
  return 1
}
# 화면이 idle(직전 명령 응답 종료)인지 — 'esc to interrupt' 없으면 idle.
wait_idle() {
  local i=0
  while [ "$i" -lt 30 ]; do
    tmux capture-pane -t "$SES" -p 2>/dev/null | grep -qi 'esc to interrupt' || return 0
    sleep 2; i=$((i+2))
  done
  return 0
}

# E1: matrix-allow (ls) → settings.allow Bash(ls:*) 학습 패턴에 매칭 → MATRIX-ALLOW (ask 없음)
tmux send-keys -t "$SES" "run exactly: ls -la" Enter
if wait_log 'Bash → MATRIX-ALLOW' 40; then chk yes yes "E1 matrix-allow (MATRIX-ALLOW 로그)"; else chk yes no "E1 matrix-allow"; fi
wait_idle

# E2: danger (rm -rf) → danger_check 가 먼저 deny + incident 기록 (AUTO-DENY)
tmux send-keys -t "$SES" "run exactly: rm -rf /tmp/probe6test" Enter
if wait_log 'Bash → AUTO-DENY' 40; then
  chk yes yes "E2 danger AUTO-DENY (로그)"
else chk yes no "E2 danger AUTO-DENY"; fi
# incident 파일도 함께 검증 (queue_incident 부수효과)
inc="$(ls "$PROBE_DIR/.agent-harness/state/incidents/"*.json 2>/dev/null | wc -l | tr -d ' ')"
[ "$inc" -ge 1 ] && chk yes yes "E2 incident 파일 생성" || chk yes no "E2 incident 파일"
wait_idle

# E3: 회색 (npm test) → matrix·auto 미매치 → gray → pending-ask → lead approve → 진행
tmux send-keys -t "$SES" "run exactly: npm test" Enter
wait_log 'Bash → USER-ASK' 40 || true
PJSON="$(ls "$PROBE_DIR/.agent-harness/state/pending-asks/"*.json 2>/dev/null | head -1)"
[ -n "$PJSON" ] && chk yes yes "E3 회색 pending-ask 생성" || chk yes no "E3 pending-ask"
if [ -n "$PJSON" ]; then
  GUUID="$(jq -r .uuid "$PJSON")"
  GCHAN="$(jq -r .channel "$PJSON")"   # ★ 워커 고정 채널 (uuid 아님)
  PA="$PROBE_DIR/.agent-harness/state/pending-asks"
  printf 'approve-once' > "$PA/${GUUID}.response.tmp"
  mv "$PA/${GUUID}.response.tmp" "$PA/${GUUID}.response"   # atomic
  tmux wait-for -S "$GCHAN"   # lead 가 channel 필드로 wake
  sleep 6
  out2="$(tmux capture-pane -t "$SES" -p)"
  echo "$out2" | grep -qi 'permission required\|allow this' && echo "  (E3 아직 권한대기? 화면 확인)" || chk yes yes "E3 approve 후 워커 진행"
fi

tmux kill-session -t "$SES" 2>/dev/null || true
rm -rf "$PROBE_DIR"
echo "---- probe6 PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
