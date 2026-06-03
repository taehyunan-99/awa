#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh

ROOT="$(cd .. && pwd)"
SES="watch_$$"

# 더미 세션: lead/reviewer 역할 pane 을 셸로 띄움 (claude 아님 — send-keys 도착만 검증).
# pane 에 send-keys 된 텍스트는 셸 입력으로 보이므로 capture-pane 으로 알림 prefix 확인.
TMP_STATE="$(mktemp -d)"
EVENTS="$TMP_STATE/events.log"
mkdir -p "$TMP_STATE/pending-asks"
# R4 검증 셋업: 기동 전 events.log 에 과거 done 라인을 미리 넣음.
# watcher 가 last_events 를 현재 줄 수로 초기화하면 이 과거 줄은 재발화되지 않아야 한다.
printf '%s\tdev\tOLD\tdone\t-\n' "ts-old" > "$EVENTS"

cleanup() {
  [ -n "${WPID:-}" ] && { kill "$WPID" 2>/dev/null; wait "$WPID" 2>/dev/null; }
  tmux kill-session -t "$SES" 2>/dev/null || true
  rm -rf "$TMP_STATE"
}
trap cleanup EXIT INT TERM   # TERM 필수 — EXIT 만으론 SIGTERM(timeout-kill) 에 좀비 잔존(실측)

# lead pane (window0 pane1), reviewer pane (split)
tmux new-session -d -s "$SES" -x 200 -y 50
LEAD_PANE="$(tmux display-message -p -t "$SES" '#{pane_id}')"
REV_PANE="$(tmux split-window -t "$SES" -d -P -F '#{pane_id}')"
# 셸 프롬프트가 send-keys 텍스트를 그대로 받도록 (Enter 로 실행돼도 command not found 무해)

# watcher 를 백그라운드로 기동. env 로 pane_id·경로 주입.
SESSION="$SES" \
LEAD_PANE="$LEAD_PANE" \
REVIEWER_PANES="$REV_PANE" \
STATE_DIR="$TMP_STATE" \
EVENTS="$EVENTS" \
SEEN="$TMP_STATE/.watcher-seen" \
REV_DEBOUNCE=2 \
  bash "$ROOT/bin/watcher.sh" &
WPID=$!
sleep 2.5  # 첫 폴링 사이클 보장 (여유 — CI 부하 대비, OLD 재발화 검증 엄격화)

# --- 케이스 0: 기동 전 done 라인 재발화 방지 (R4 — last_events 초기화) ---
DUMP_INIT="$(tmux capture-pane -p -t "$LEAD_PANE")"
assert_not_contains "$DUMP_INIT" "OLD" "기동 전 과거 done(OLD) 재발화 안 함 (last_events 초기화)"

# --- 케이스 1: pending-ask → lead @gate: ---
echo '{"uuid":"u1"}' > "$TMP_STATE/pending-asks/u1.json"
sleep 2
DUMP_LEAD="$(tmux capture-pane -p -t "$LEAD_PANE")"
assert_contains "$DUMP_LEAD" "@gate:" "pending-ask → lead @gate: send-keys"
assert_contains "$DUMP_LEAD" "u1" "@gate: 알림에 uuid 포함"

# --- 케이스 2: 중복 방지 (.watcher-seen) ---
# u1.json 그대로 둠. 다음 사이클에 재전송 안 해야. capture 줄 수 안 늘어남으로 판정.
CNT_BEFORE="$(printf '%s' "$DUMP_LEAD" | grep -c '@gate:' || true)"
sleep 2
DUMP_LEAD2="$(tmux capture-pane -p -t "$LEAD_PANE")"
CNT_AFTER="$(printf '%s' "$DUMP_LEAD2" | grep -c '@gate:' || true)"
assert_eq "$CNT_BEFORE" "$CNT_AFTER" "중복 pending-ask 재전송 안 함 (.watcher-seen)"

# --- 케이스 3: events.log 증가 → reviewer @review: ---
printf '%s\tdev\tT1\tmodify\tfoo.txt\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$EVENTS"
sleep 2
DUMP_REV="$(tmux capture-pane -p -t "$REV_PANE")"
assert_contains "$DUMP_REV" "@review:" "events.log 증가 → reviewer @review: send-keys"

# --- 케이스 3.1: reviewer 깨움이 send_prompt(Enter 재시도 안전망)를 쓰는지 (소스 가드) ---
# 라이브 결함(2026-06-03): watcher 가 단발 'send-keys -l + Enter' 로 깨우면 codex TUI 가
# Enter 를 씹어(P17 리뷰어 변종) 검토 미시작 → quorum 영영 미충족. send_prompt 는 입력창
# 잔류 폴링으로 Enter 를 최대 8회 재시도(lib.sh) → codex 콜드스타트·렌더링 지연에도 제출 보장.
# 부트 경로(awa-up)는 send_prompt 를 쓰는데 watcher 깨움만 단발이라 안 썼던 게 결함. 통일.
WBODY="$(awk '/^[[:space:]]*for rp in \$REVIEWER_PANES/,/^[[:space:]]*done/' "$(dirname "$0")/../bin/watcher.sh")"
printf '%s' "$WBODY" | grep -q 'send_prompt'
assert_success "$?" "케이스3.1: reviewer 깨움이 send_prompt 재시도 안전망 사용 (단발 send-keys 아님)"
printf '%s' "$WBODY" | grep -Eq 'send-keys -t "\$rp" Enter'
assert_fail "$?" "케이스3.1b: reviewer 깨움에 단발 Enter send-keys 잔존 없음"

# --- 케이스 4: done 라인 → lead @done: worker/task ---
printf '%s\tdev\tT1\tdone\t-\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$EVENTS"
sleep 2
DUMP_LEAD3="$(tmux capture-pane -p -t "$LEAD_PANE")"
assert_contains "$DUMP_LEAD3" "@done:" "done 라인 → lead @done: send-keys"
assert_contains "$DUMP_LEAD3" "dev/T1" "@done: 알림에 worker/task 포함 (C2)"

# --- 케이스 5: 세션 kill 시 watcher 루프 종료 ---
tmux kill-session -t "$SES" 2>/dev/null || true
sleep 2.5
kill -0 "$WPID" 2>/dev/null
assert_fail "$?" "세션 kill 후 watcher 루프 종료 (has-session 가드)"

test_summary
