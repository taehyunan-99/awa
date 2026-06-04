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
#   이 probe 는 awa-up 과 동일한 2-스코프 구성을 재현하고, 워커가 파일 Edit 한 번 + 회색 명령
#   한 번을 실행해 *두 hook 이 동시에 살아있는지* 를 확인한다:
#     H1. Edit → .agent-harness/events.log 에 줄 기록    (PostToolUse 생존)
#     H2. 회색 명령 → permission-gate 가 pending-ask 생성 (PreToolUse 생존)
#   둘 다 PASS = 공존 확정(케이스 B). H1 FAIL = 병합 결함(케이스 A) → 워커 템플릿에 PostToolUse 합산 필요.
#
# RUN_LIVE=1 일 때만 (실제 claude REPL·토큰 + tmux). 더미 RUN_INTEGRATION 과 분리. CI skip.
set -uo pipefail
[ "${RUN_LIVE:-0}" = "1" ] || { echo "SKIP (RUN_LIVE 미설정)"; exit 0; }
cd "$(dirname "$0")/../.."
ROOT="$(pwd)"

PROBE_DIR="$(mktemp -d)"
SES="probehm_$$"
WUUID="$(uuidgen)"
# 중간 사망(kill·에러·timeout)에도 세션·임시디렉터리 정리 — 좀비 세션이 다음 실행 오염 방지.
cleanup() { tmux kill-session -t "$SES" 2>/dev/null || true; rm -rf "$PROBE_DIR"; }
trap cleanup EXIT INT TERM   # TERM 필수 — EXIT 만으론 SIGTERM(timeout-kill) 에 좀비 잔존(실측)

# ★ HARNESS_PROJECT export 필수: lib.sh:27 이 PROJECT_ROOT 를 resolve_project_root 로 무조건
#   재대입 → HARNESS_PROJECT 우선. 안 주면 PROJECT_ROOT 가 ROOT(repo)로 덮어써짐.
export HARNESS_PROJECT="$PROBE_DIR" PROJECT_ROOT="$PROBE_DIR" HARNESS_ROOT="$ROOT"
( cd "$PROBE_DIR" && git init -q )   # resolve_project_root 의 git toplevel 안정화
mkdir -p "$PROBE_DIR/.agent-harness/state/pending-asks" \
         "$PROBE_DIR/config" \
         "$PROBE_DIR/.agent-harness/.boot-settings" \
         "$PROBE_DIR/.claude"

cat > "$PROBE_DIR/config/orch-auto-allow.yaml" <<'YAML'
read-only:
  - "Bash(find:*)"
YAML

# shellcheck disable=SC1091
source "$ROOT/bin/lib.sh"

# ── 스코프 1: project .claude/settings.json — awa-up 과 동일 (6차: 빈 {}, hook 은 워커로 이관) ──
#   이게 빈 {} 인데도 events.log 가 찍혀야 함 = PostToolUse 가 워커 --settings 에서 산다는 증명.
sed -e "s#{{PROJECT_ROOT}}#$PROBE_DIR#g" \
    -e "s#{{HARNESS_ROOT}}#$ROOT#g" \
    "$ROOT/templates/settings.json.tpl" > "$PROBE_DIR/.claude/settings.json"

# ── 스코프 2: 워커 --settings — generate_worker_settings 로 실제 산출(PreToolUse + PostToolUse 공존) ──
#   awa-up 과 동일 경로. dev 템플릿엔 Edit allow 가 없어 회색 → H1 게이트 걸림 방지 위해
#   acceptEdits + Edit/Write allow 후처리 (Edit 이 확실히 게이트 없이 통과 → PostToolUse 도달 보장).
SET="$(generate_worker_settings dev dev-1)"
jq '.permissions.defaultMode="acceptEdits" | .permissions.allow=((.permissions.allow//[])+["Edit","Write"]|unique)' \
   "$SET" > "$SET.tmp" && mv "$SET.tmp" "$SET"

# Edit 대상 파일 (H1). 워커가 이걸 수정 → events.log 기록 기대.
echo 'line1' > "$PROBE_DIR/target.txt"

tmux kill-session -t "$SES" 2>/dev/null || true
tmux new-session -d -s "$SES" -c "$PROBE_DIR" -x 200 -y 50
# ★ HARNESS_WORKER pane env 주입 (awa-up 이 주는 것 — log-event 가 워커명에 사용).
tmux send-keys -t "$SES" "export HARNESS_WORKER=dev-1" Enter
tmux send-keys -t "$SES" "cd '$PROBE_DIR' && claude --model claude-haiku-4-5-20251001 --settings '$SET' --session-id $WUUID" Enter

# REPL 준비 대기 — ★ 확정 신호로 판정 (빈 화면을 ready 로 오인하지 않도록).
#   '❯' 단독은 부팅 중 빈 입력선에서 위양성 → 상태줄/박스 신호로 강화 (실측).
wait_repl() {
  for _ in $(seq 1 70); do
    sleep 2
    local d; d="$(tmux capture-pane -t "$SES" -p 2>/dev/null)"
    printf '%s' "$d" | grep -q 'trust this folder' && { tmux send-keys -t "$SES" Enter; continue; }
    printf '%s' "$d" | grep -qE 'accept edits on|bypass permissions|for shortcuts|esc to interrupt|Welcome back' && return 0
  done
  return 1
}
wait_repl || { echo "FAIL: REPL 미준비"; tmux kill-session -t "$SES" 2>/dev/null; rm -rf "$PROBE_DIR"; exit 1; }
sleep 3

PASS=0; FAIL=0
chk() { if [ "$1" = "$2" ]; then echo "  ok: $3"; PASS=$((PASS+1)); else echo "  FAIL: $3 (exp=$1 got=$2)"; FAIL=$((FAIL+1)); fi; }

EVLOG="$PROBE_DIR/.agent-harness/events.log"

# ── H1: PostToolUse 생존 — 워커가 파일 Edit → events.log 에 줄 기록 ──
# Edit 는 acceptEdits + allow 라 permission-gate 즉시 통과. PostToolUse(log-event)가 살아있으면 기록됨.
tmux send-keys -t "$SES" -l "Edit target.txt: replace the word line1 with line2"
sleep 1; tmux send-keys -t "$SES" Enter
# events.log 폴링 (최대 40s — 모델 응답 시간 편차 흡수).
for _w in $(seq 1 8); do
  sleep 5
  [ -s "$EVLOG" ] && break
done
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
