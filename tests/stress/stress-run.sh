#!/usr/bin/env bash
# 13차+: 다수 워커 LEAD 부담 스트레스 실행. watcher-integration.sh 패턴을 N워커 확장.
# 더미 세션(claude 없음·토큰0) + watcher 백그라운드 → done N·gate K 동시 주입 →
# LEAD pane(cat sink)이 수신 신호를 파일에 그대로 기록 → 발생-처리 집합 대조(M1·M4) → 결과 파일.
#
# I-1 수정: LEAD pane 을 interactive shell 로 두면 watcher send-keys 가 셸 명령으로 해석돼
#   재가공(echo·command not found·프롬프트 redraw)되고, 큰 N 의 버스트 끝(마지막 1~2 워커)이
#   영구히 깨진 토큰으로 남아 capture-pane 정규식 추출에 안 잡힌다(거짓 FAIL, timeout 까지도 회복 불가).
#   → LEAD pane 을 `cat > sink` 수동 싱크로 바꿔 send-keys 라인을 가공 없이 파일에 적재한다.
#   여기에 "expected 전부 도착까지 폴링(timeout 상한)"을 더해 빠른 종료 + 진짜 유실 구분을 보존.
set -uo pipefail
cd "$(dirname "$0")"
source ../assert.sh
source ../harness-paths.sh
source ./stress-lib.sh
ROOT="$(cd ../.. && pwd)"

N="${STRESS_WORKERS:-5}"        # 워커 수
RESULT="${STRESS_RESULT:-$(mktemp -d)/stress-result.txt}"
SES="stress_$$"
TMP_STATE="$(mktemp -d)"
EVENTS="$TMP_STATE/events.log"
LEAD_SINK="$TMP_STATE/lead.sink"   # LEAD pane 수신 신호를 가공 없이 적재
mkdir -p "$TMP_STATE/pending-asks"
: > "$EVENTS"   # 빈 events.log (watcher last_events=0 초기화)
: > "$LEAD_SINK"

WPID=""   # watcher 백그라운드 PID (cleanup 에서 직접 kill — 1초 좀비 잔존 race 제거)
cleanup() { [ -n "$WPID" ] && { kill "$WPID" 2>/dev/null; wait "$WPID" 2>/dev/null; }; tmux kill-session -t "$SES" 2>/dev/null || true; rm -rf "$TMP_STATE"; }
trap cleanup EXIT INT TERM   # TERM 필수 — EXIT 만으론 SIGTERM(timeout-kill) 에 좀비 잔존(실측)

# 더미 세션: LEAD pane 1개 (워커 pane 은 토폴로지 동형용 — 부하는 스크립트가 직접 주입).
# LEAD pane 은 interactive shell 대신 `cat > sink` 수동 싱크 — send-keys 라인을 셸 가공 없이
# 그대로 파일에 적재(I-1: 큰 N 버스트 끝 토큰 mangling 방지).
tmux new-session -d -s "$SES" -x 200 -y 50 "cat > '$LEAD_SINK'"
ORCH_PANE="$(tmux display-message -p -t "$SES" '#{pane_id}')"
WORKERS=""
i=0
while [ "$i" -lt "$N" ]; do
  i=$((i+1))
  WORKERS="$WORKERS dev$i"
  tmux split-window -t "$SES" -d 2>/dev/null || true   # 토폴로지 동형 (no space 무해)
done
WORKERS="${WORKERS# }"

# watcher 백그라운드 기동 (reviewer 없음 — done/gate 만 측정).
SESSION="$SES" ORCH_PANE="$ORCH_PANE" REVIEWER_PANES="" \
STATE_DIR="$TMP_STATE" EVENTS="$EVENTS" SEEN="$TMP_STATE/.watcher-seen" \
  bash "$HARNESS_BIN/watcher.sh" &
WPID=$!
sleep 2.5   # 첫 폴링 사이클 보장

# --- 부하 주입: done N개 + gate K개 동시 ---
GATE_UUIDS="g1 g2 g3"
inject_done_lines "$EVENTS" "$WORKERS" "T"
inject_pending_asks "$TMP_STATE/pending-asks" "$GATE_UUIDS"

# --- 수집: expected 전부 도착할 때까지 폴링 (timeout 상한) ---
# 고정 sleep 은 N 에 비례 안 해 큰 N 에서 마지막 워커 알림 미도착→거짓 FAIL.
# watcher 가 N 개 @done 을 send-keys 로 순차 주입하므로 도착이 N 에 비례해 늘어난다.
# LEAD_SINK(cat) 에 적재된 신호를 폴링 — expected 가 다 보이면 즉시 종료, timeout 까지
# 안 오면 그게 실측 유실(도착률 한계).
expected_done="$(i=0; for w in $WORKERS; do i=$((i+1)); printf '%s/T%s\n' "$w" "$i"; done)"
expected_gate="$(printf '%s\n' $GATE_UUIDS | sort -u)"
TIMEOUT="${STRESS_TIMEOUT:-20}"   # 초 상한
DUMP=""; processed_done=""; processed_gate=""; miss_done=""; miss_gate=""
waited=0
while :; do
  DUMP="$(cat "$LEAD_SINK" 2>/dev/null || true)"
  processed_done="$(extract_done_ids "$DUMP")"
  processed_gate="$(extract_gate_ids "$DUMP")"
  miss_done="$(missing_ids "$expected_done" "$processed_done")"
  miss_gate="$(missing_ids "$expected_gate" "$processed_gate")"
  [ -z "$miss_done" ] && [ -z "$miss_gate" ] && break
  # timeout 까지 다 안 오면 그 미도착이 실측 유실 신호 — 루프 탈출해 그대로 판정.
  awk "BEGIN{exit !($waited >= $TIMEOUT)}" && break
  sleep 0.5
  waited="$(awk "BEGIN{print $waited + 0.5}")"
done

# --- 결과 파일 (heavy-task-offload: 요약만 대화로) ---
{
  echo "# LEAD 부담 스트레스 결과 ($(date -u +%FT%TZ))"
  echo "워커 수 N=$N, gate K=$(printf '%s\n' $GATE_UUIDS | wc -w | tr -d ' ')"
  echo "## M1 (done 신호 유실)"
  echo "발생: $(printf '%s\n' "$expected_done" | grep -c . || true) / 처리: $(printf '%s\n' "$processed_done" | grep -c . || true)"
  echo "유실: [${miss_done:-없음}]"
  echo "## M4 (gate 신호 유실)"
  echo "발생: $(printf '%s\n' "$expected_gate" | grep -c . || true) / 처리: $(printf '%s\n' "$processed_gate" | grep -c . || true)"
  echo "유실: [${miss_gate:-없음}]"
} > "$RESULT"

# --- 판정 (assert) ---
assert_eq "" "$miss_done" "M1 done 신호 유실 0 (워커 $N)"
assert_eq "" "$miss_gate" "M4 gate 신호 유실 0"
echo "결과 파일: $RESULT"
test_summary
