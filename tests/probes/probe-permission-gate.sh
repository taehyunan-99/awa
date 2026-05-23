#!/usr/bin/env bash
# 통합 probe: permission-gate hook 의 wait-for 게이트 전 경로.
# RUN_INTEGRATION=1 일 때만 (실제 claude REPL + tmux). CI skip.
set -uo pipefail
[ "${RUN_INTEGRATION:-0}" = "1" ] || { echo "SKIP (RUN_INTEGRATION 미설정)"; exit 0; }
cd "$(dirname "$0")/../.."
ROOT="$(pwd)"

PROBE_DIR="$(mktemp -d)"
SES="probe6_$$"
WUUID="$(uuidgen)"
# settings 생성 (dev 템플릿 + permission-gate).
# ★ HARNESS_PROJECT export 필수 (3차 리뷰): lib.sh:27 이 PROJECT_ROOT 를 resolve_project_root
#   로 무조건 재대입 → HARNESS_PROJECT 우선. 안 주면 PROJECT_ROOT 가 ROOT(repo)로 덮어써져
#   settings 가 엉뚱한 곳에 생성됨. 다른 단위 테스트도 전부 HARNESS_PROJECT 사용.
export HARNESS_PROJECT="$PROBE_DIR" PROJECT_ROOT="$PROBE_DIR" HARNESS_ROOT="$ROOT"
( cd "$PROBE_DIR" && git init -q )   # resolve_project_root 의 git toplevel 안정화
mkdir -p "$PROBE_DIR/.agent-harness/state/pending-asks" "$PROBE_DIR/config" "$PROBE_DIR/.agent-harness/.boot-settings"
echo '{"permissions":{"allow":["Bash(ls:*)"]}}' > "$PROBE_DIR/.agent-harness/.boot-settings/dev.json"
cat > "$PROBE_DIR/config/lead-auto-allow.yaml" <<'YAML'
read-only:
  - "Bash(find:*)"
YAML
# shellcheck disable=SC1091
source "$ROOT/bin/lib.sh"
SET="$(generate_worker_settings dev dev-1)"

tmux kill-session -t "$SES" 2>/dev/null || true
tmux new-session -d -s "$SES" -c "$PROBE_DIR" -x 200 -y 50
tmux send-keys -t "$SES" "cd '$PROBE_DIR' && claude --model claude-haiku-4-5-20251001 --settings '$SET' --session-id $WUUID" Enter

# REPL 준비 대기 (trust 프롬프트 자동 통과)
wait_repl() {
  for _ in $(seq 1 60); do
    sleep 2
    if tmux capture-pane -t "$SES" -p | grep -q 'trust this folder'; then tmux send-keys -t "$SES" Enter; fi
    tmux capture-pane -t "$SES" -p | grep -q '❯' && return 0
  done
  return 1
}
wait_repl || { echo "FAIL: REPL 미준비"; tmux kill-session -t "$SES"; exit 1; }

PASS=0; FAIL=0
chk() { if [ "$1" = "$2" ]; then echo "  ok: $3"; PASS=$((PASS+1)); else echo "  FAIL: $3 (exp=$1 got=$2)"; FAIL=$((FAIL+1)); fi; }

# E1: matrix-allow (ls) → ask 안 뜨고 실행
tmux send-keys -t "$SES" "run exactly: ls -la" Enter
sleep 12
out="$(tmux capture-pane -t "$SES" -p)"
echo "$out" | grep -q 'Waiting' && echo "  (ls 가 Waiting? 예상 외)"
echo "$out" | grep -qE 'total |drwx' && chk yes yes "E1 matrix-allow 즉시 실행" || chk yes no "E1 matrix-allow"

# E2: danger (rm -rf) → 차단 + incident
tmux send-keys -t "$SES" "run exactly: rm -rf /tmp/probe6test" Enter
sleep 10
inc="$(ls "$PROBE_DIR/.agent-harness/state/incidents/"*.json 2>/dev/null | wc -l | tr -d ' ')"
[ "$inc" -ge 1 ] && chk yes yes "E2 danger incident 생성" || chk yes no "E2 danger incident"

# E3: 회색 (npm test) → Waiting → lead approve → 실행
tmux send-keys -t "$SES" "run exactly: npm test" Enter
sleep 8
# pending-ask uuid 추출
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
  echo "$out2" | grep -qi 'permission\|Waiting' && echo "  (E3 아직 대기? 화면 확인)" || chk yes yes "E3 approve 후 워커 진행"
fi

tmux kill-session -t "$SES" 2>/dev/null || true
rm -rf "$PROBE_DIR"
echo "---- probe6 PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
