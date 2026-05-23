#!/usr/bin/env bash
# 통합 probe: hook 스코프 병합 — PostToolUse(project) 와 PreToolUse(--settings) 공존 여부.
#
# ★ 검증 대상 (코드로는 확정 불가, 실측 필수):
#   워커 claude 한 인스턴스에 hook 이 두 스코프에서 주입된다 —
#     · PROJECT_ROOT/.claude/settings.json (project 스코프)      → PostToolUse (events.log 기록)
#     · 워커 --settings <역할>.json        (command-line 스코프) → PreToolUse  (permission-gate)
#   공식 docs: "hooks ... the highest-precedence scope's hooks definition takes precedence;
#              they do not additively merge."
#   '병합 안 함' 의 단위가 (A) hooks 객체 전체인지 (B) 이벤트(PreToolUse/PostToolUse) 단위인지
#   문서에 미명시 → command-line 의 PreToolUse 가 project 의 PostToolUse 를 통째로 덮으면
#   events.log 가 죽어 리뷰어 감시·done 신호가 전부 무력화된다.
#
#   이 probe 는 team-up 과 동일한 2-스코프 구성을 재현하고, 워커가 파일 Edit 한 번 + 회색 명령
#   한 번을 실행해 *두 hook 이 동시에 살아있는지* 를 확인한다:
#     H1. Edit → .agent-harness/events.log 에 줄 기록    (PostToolUse 생존)
#     H2. 회색 명령 → permission-gate 가 pending-ask 생성 (PreToolUse 생존)
#   둘 다 PASS = 공존 확정(케이스 B). H1 FAIL = 병합 결함(케이스 A) → 워커 템플릿에 PostToolUse 합산 필요.
#
# RUN_INTEGRATION=1 일 때만 (실제 claude REPL + tmux). CI skip.
set -uo pipefail
[ "${RUN_INTEGRATION:-0}" = "1" ] || { echo "SKIP (RUN_INTEGRATION 미설정)"; exit 0; }
cd "$(dirname "$0")/../.."
ROOT="$(pwd)"

PROBE_DIR="$(mktemp -d)"
SES="probehm_$$"
WUUID="$(uuidgen)"

# ★ HARNESS_PROJECT export 필수: lib.sh:27 이 PROJECT_ROOT 를 resolve_project_root 로 무조건
#   재대입 → HARNESS_PROJECT 우선. 안 주면 PROJECT_ROOT 가 ROOT(repo)로 덮어써짐.
export HARNESS_PROJECT="$PROBE_DIR" PROJECT_ROOT="$PROBE_DIR" HARNESS_ROOT="$ROOT"
( cd "$PROBE_DIR" && git init -q )   # resolve_project_root 의 git toplevel 안정화
mkdir -p "$PROBE_DIR/.agent-harness/state/pending-asks" \
         "$PROBE_DIR/config" \
         "$PROBE_DIR/.agent-harness/.boot-settings" \
         "$PROBE_DIR/.claude"

# dev settings (PreToolUse permission-gate). matrix 는 비워 회색 유도(H2). Edit 는 게이트 통과 위해 허용.
echo '{"permissions":{"allow":["Edit"]}}' > "$PROBE_DIR/.agent-harness/.boot-settings/dev.json"
cat > "$PROBE_DIR/config/lead-auto-allow.yaml" <<'YAML'
read-only:
  - "Bash(find:*)"
YAML

# shellcheck disable=SC1091
source "$ROOT/bin/lib.sh"

# ── 스코프 1: project .claude/settings.json (PostToolUse log-event) — team-up 과 동일 ──
sed -e "s#{{PROJECT_ROOT}}#$PROBE_DIR#g" \
    -e "s#{{HARNESS_ROOT}}#$ROOT#g" \
    "$ROOT/templates/settings.json.tpl" > "$PROBE_DIR/.claude/settings.json"

# ── 스코프 2: 워커 --settings (PreToolUse permission-gate) ──
SET="$(generate_worker_settings dev dev-1)"

# Edit 대상 파일 (H1). 워커가 이걸 수정 → events.log 기록 기대.
echo 'line1' > "$PROBE_DIR/target.txt"

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
wait_repl || { echo "FAIL: REPL 미준비"; tmux kill-session -t "$SES" 2>/dev/null; rm -rf "$PROBE_DIR"; exit 1; }

PASS=0; FAIL=0
chk() { if [ "$1" = "$2" ]; then echo "  ok: $3"; PASS=$((PASS+1)); else echo "  FAIL: $3 (exp=$1 got=$2)"; FAIL=$((FAIL+1)); fi; }

EVLOG="$PROBE_DIR/.agent-harness/events.log"

# ── H1: PostToolUse 생존 — 워커가 파일 Edit → events.log 에 줄 기록 ──
# Edit 는 dev.json allow 라 permission-gate 즉시 통과. PostToolUse(log-event)가 살아있으면 기록됨.
tmux send-keys -t "$SES" "use the Edit tool to change 'line1' to 'line2' in target.txt" Enter
sleep 18
if [ -s "$EVLOG" ]; then
  chk yes yes "H1 PostToolUse 생존 (events.log 기록됨 → 두 스코프 hook 공존)"
  echo "    events.log 마지막 줄: $(tail -1 "$EVLOG")"
else
  chk yes no "H1 PostToolUse 소실 (events.log 비어있음 → --settings PreToolUse 가 project PostToolUse 덮음 = 병합 결함)"
fi

# ── H2: PreToolUse 생존 — 회색 명령 → permission-gate 가 pending-ask 생성 ──
# matrix·auto 미매치 명령(echo) → 회색 → gate_gray → pending-ask. PreToolUse 가 살아있어야 생성됨.
tmux send-keys -t "$SES" "run exactly: echo probe-gray-cmd" Enter
sleep 10
PJSON="$(ls "$PROBE_DIR/.agent-harness/state/pending-asks/"*.json 2>/dev/null | head -1)"
if [ -n "$PJSON" ]; then
  chk yes yes "H2 PreToolUse 생존 (pending-ask 생성됨)"
  # 워커 무한 대기 방지: 응답 깔고 wake.
  GUUID="$(jq -r .uuid "$PJSON")"; GCHAN="$(jq -r .channel "$PJSON")"
  PA="$PROBE_DIR/.agent-harness/state/pending-asks"
  printf 'deny' > "$PA/${GUUID}.response.tmp" && mv "$PA/${GUUID}.response.tmp" "$PA/${GUUID}.response"
  tmux wait-for -S "$GCHAN" 2>/dev/null || true
else
  chk yes no "H2 PreToolUse 소실 (pending-ask 없음 → permission-gate 미발화)"
fi

tmux kill-session -t "$SES" 2>/dev/null || true
rm -rf "$PROBE_DIR"
echo "---- probe-hook-merge PASS=$PASS FAIL=$FAIL"
echo ""
echo "해석:"
echo "  H1·H2 둘 다 ok → hook 공존 확정 (병합 결함 없음, 6차 종료)."
echo "  H1 FAIL        → 병합 결함: 워커 템플릿(dev/test/reviewer.tpl)에 PostToolUse(log-event) 합산 필요."
echo "  H2 FAIL        → permission-gate 미발화: matcher/--settings 경로 점검 필요."
[ "$FAIL" -eq 0 ]
