#!/usr/bin/env bash
# /loop+Monitor 실측: tmux pane 내 대화형 claude 가 /loop 으로
# events.log 커서 순회 자기반복을 실제로 도는지. run-all 비포함, 수동 실행.
set -uo pipefail
S="probe_loop_$$"
WS="/tmp/$S-ws"
cleanup() { tmux kill-session -t "$S" 2>/dev/null || true; rm -rf "$WS"; }
trap cleanup EXIT

rm -rf "$WS"; mkdir -p "$WS"
: > "$WS/events.log"; echo 0 > "$WS/.review-cursor"; : > "$WS/review-out.log"

# claude REPL 준비 대기: pane 에 프롬프트(❯) 가 뜰 때까지 폴링.
# /tmp 새 워크스페이스는 "Is this a project you trust?" 프롬프트가 먼저 뜨므로
# 그게 보이면 Enter(기본 "1. Yes, I trust") 로 통과시킨다. (고정 sleep 으로는
# 머신/부하별 기동 편차를 못 잡아 FAIL — 폴링으로 견고화)
wait_repl() {  # $1=session, 최대 ~90s
  local s="$1" i dump trusted=0
  for i in $(seq 1 45); do
    sleep 2
    dump="$(tmux capture-pane -t "$s" -p 2>/dev/null)"
    if [ "$trusted" = 0 ] && printf '%s' "$dump" | grep -q 'trust this folder'; then
      tmux send-keys -t "$s" Enter   # "1. Yes, I trust this folder"
      trusted=1
      continue
    fi
    # REPL 프롬프트 라인(❯) + 입력 가능 상태
    if printf '%s' "$dump" | grep -q 'bypass permissions on'; then
      return 0
    fi
  done
  return 1
}

tmux new-session -d -s "$S" -x 200 -y 50
tmux set-option -t "$S" allow-set-title off 2>/dev/null || true
tmux send-keys -t "$S" -l "cd $WS && claude --dangerously-skip-permissions"
tmux send-keys -t "$S" Enter
echo "[probe-loop] claude REPL 준비 폴링(trust 자동 통과 포함)..."
if ! wait_repl "$S"; then
  echo "[probe-loop] FAIL — claude REPL 미준비. pane 덤프:"
  tmux capture-pane -t "$S" -p | tail -30; exit 1
fi
echo "[probe-loop] REPL 준비 완료"
sleep 3

LOOP_PROMPT="/loop 감시: $WS/.review-cursor 의 숫자 N 읽고 $WS/events.log 의 0-based 라인오프셋 N부터 새 줄을 각각 \"REVIEWED: <내용>\" 으로 $WS/review-out.log 에 append, .review-cursor 를 events.log 총줄수로 갱신. 새 줄 없으면 아무것도 안함."
tmux send-keys -t "$S" -l "$LOOP_PROMPT"
sleep 1
tmux send-keys -t "$S" Enter
echo "[probe-loop] /loop 주입, 초기처리+Monitor 무장 25s 대기..."
sleep 25

echo "a	dev	101	modify	src/auth/login.ts" >> "$WS/events.log"
echo "b	dev	101	modify	src/auth/token.ts" >> "$WS/events.log"
echo "c	arch	102	write	docs/arch.md" >> "$WS/events.log"
echo "[probe-loop] 3줄 주입, Monitor 발화 75s 대기..."
sleep 75

echo "d	dev	101	modify	src/payment/charge.ts" >> "$WS/events.log"
echo "e	dev	101	done	-" >> "$WS/events.log"
echo "[probe-loop] 2줄 추가(증분 검증), 75s 대기..."
sleep 75

lines="$(wc -l < "$WS/review-out.log" | tr -d ' ')"
cursor="$(cat "$WS/.review-cursor")"
echo "[probe-loop] review-out.log 줄수=$lines (기대 5), cursor=$cursor (기대 5)"
if [ "$lines" = "5" ] && [ "$cursor" = "5" ]; then
  echo "[probe-loop] PASS"; exit 0
else
  echo "[probe-loop] FAIL — pane 덤프:"; tmux capture-pane -t "$S" -p | tail -30; exit 1
fi
