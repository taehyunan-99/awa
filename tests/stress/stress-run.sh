#!/usr/bin/env bash
# 13차+: 다수 워커 LEAD 부담 스트레스 실행. watcher-integration.sh 패턴을 N워커 확장.
# 더미 세션(claude 없음·토큰0) + watcher 백그라운드 → done N·gate K 동시 주입 →
# capture-pane 으로 LEAD pane 수신 신호 수집 → 발생-처리 집합 대조(M1·M4) → 결과 파일.
set -uo pipefail
cd "$(dirname "$0")"
source ../assert.sh
source ./stress-lib.sh
ROOT="$(cd ../.. && pwd)"

N="${STRESS_WORKERS:-5}"        # 워커 수
RESULT="${STRESS_RESULT:-$(mktemp -d)/stress-result.txt}"
SES="stress_$$"
TMP_STATE="$(mktemp -d)"
EVENTS="$TMP_STATE/events.log"
mkdir -p "$TMP_STATE/pending-asks"
: > "$EVENTS"   # 빈 events.log (watcher last_events=0 초기화)

cleanup() { tmux kill-session -t "$SES" 2>/dev/null || true; rm -rf "$TMP_STATE"; }
trap cleanup EXIT

# 더미 세션: LEAD pane 1개 (워커 pane 은 토폴로지 동형용 — 부하는 스크립트가 직접 주입).
tmux new-session -d -s "$SES" -x 200 -y 50
LEAD_PANE="$(tmux display-message -p -t "$SES" '#{pane_id}')"
WORKERS=""
i=0
while [ "$i" -lt "$N" ]; do
  i=$((i+1))
  WORKERS="$WORKERS dev$i"
  tmux split-window -t "$SES" -d 2>/dev/null || true   # 토폴로지 동형 (no space 무해)
done
WORKERS="${WORKERS# }"

# watcher 백그라운드 기동 (reviewer 없음 — done/gate 만 측정).
SESSION="$SES" LEAD_PANE="$LEAD_PANE" REVIEWER_PANES="" \
STATE_DIR="$TMP_STATE" EVENTS="$EVENTS" SEEN="$TMP_STATE/.watcher-seen" \
  bash "$ROOT/bin/watcher.sh" &
sleep 2.5   # 첫 폴링 사이클 보장

# --- 부하 주입: done N개 + gate K개 동시 ---
GATE_UUIDS="g1 g2 g3"
inject_done_lines "$EVENTS" "$WORKERS" "T"
inject_pending_asks "$TMP_STATE/pending-asks" "$GATE_UUIDS"
sleep 4   # watcher 가 누적분 수거·주입할 여유 (1초 폴링 × 부하 여유)

# --- 수집·대조 ---
DUMP="$(tmux capture-pane -p -S -500 -t "$LEAD_PANE")"
expected_done="$(i=0; for w in $WORKERS; do i=$((i+1)); printf '%s/T%s\n' "$w" "$i"; done)"
processed_done="$(extract_done_ids "$DUMP")"
miss_done="$(missing_ids "$expected_done" "$processed_done")"

expected_gate="$(printf '%s\n' $GATE_UUIDS | sort -u)"
processed_gate="$(extract_gate_ids "$DUMP")"
miss_gate="$(missing_ids "$expected_gate" "$processed_gate")"

# --- 결과 파일 (heavy-task-offload: 요약만 대화로) ---
{
  echo "# LEAD 부담 스트레스 결과 ($(date -u +%FT%TZ))"
  echo "워커 수 N=$N, gate K=$(printf '%s\n' $GATE_UUIDS | wc -w | tr -d ' ')"
  echo "## M1 (done 신호 유실)"
  echo "발생: $(printf '%s\n' "$expected_done" | wc -l | tr -d ' ') / 처리: $(printf '%s\n' "$processed_done" | grep -c . || true)"
  echo "유실: [${miss_done:-없음}]"
  echo "## M4 (gate 신호 유실)"
  echo "발생: $(printf '%s\n' "$expected_gate" | wc -l | tr -d ' ') / 처리: $(printf '%s\n' "$processed_gate" | grep -c . || true)"
  echo "유실: [${miss_gate:-없음}]"
} > "$RESULT"

# --- 판정 (assert) ---
assert_eq "" "$miss_done" "M1 done 신호 유실 0 (워커 $N)"
assert_eq "" "$miss_gate" "M4 gate 신호 유실 0"
echo "결과 파일: $RESULT"
test_summary
