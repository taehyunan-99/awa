#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
source ./harness-paths.sh

ROOT="$(cd .. && pwd)"
source "$HARNESS_BIN/lib.sh"

TS="libtest_$$"

# session_exists: 없을 때 비-0
if session_exists "$TS"; then rc=0; else rc=1; fi
assert_eq "1" "$rc" "없는 세션 → session_exists 비-0"

# 더미 세션: 첫 페인에서 cat 이 입력을 파일로 기록.
# 전역 tmux 설정과 무관하게 fix_session_indexing 으로 세션 로컬 인덱스 고정.
OUT="$(mktemp)"
tmux new-session -d -s "$TS" -x 80 -y 24 "bash -c 'cat > $OUT'"
fix_session_indexing "$TS"
sleep 0.3

if session_exists "$TS"; then rc=0; else rc=1; fi
assert_eq "0" "$rc" "있는 세션 → session_exists 0"

# 인덱스 규약 검증: window 0 / pane 1 이 실제로 존재해야 함
WIN="$(tmux list-windows -t "$TS" -F '#{window_index}' | head -1)"
assert_eq "0" "$WIN" "세션 로컬 window base-index=0 적용됨"
PANE="$(tmux list-panes -t "$TS:0" -F '#{pane_index}' | head -1)"
assert_eq "1" "$PANE" "세션 로컬 pane-base-index=1 적용됨"

# send_prompt 로 텍스트 주입 (특수문자 포함). target_of 사용.
send_prompt "$TS:0.1" 'hello "world" $X'
sleep 0.3
tmux send-keys -t "$TS:0.1" C-d
sleep 0.3

GOT="$(cat "$OUT")"
assert_eq 'hello "world" $X' "$GOT" "send_prompt 가 리터럴 텍스트+개행 주입"

tmux kill-session -t "$TS" 2>/dev/null || true
rm -f "$OUT"

# === send_prompt 미전송 안전망 마커 회귀 (라이브 결함: claude REPL ❯ 미검출) ===
# Layer 1 — 잔류 검사 grep 이 claude 실제 입력 프롬프트 마커 '❯'(U+276F)를 포함해야 한다.
#   기존엔 '[›>]' 만 있어 claude 입력창 잔류를 못 잡아 Enter 재전송 미발동 → 부트지시 박힘.
assert_success "$(grep -q "grep -E '\^\[\[:space:\]\]\*\[❯›>\]'" "$HARNESS_BIN/lib.sh" && echo 0 || echo 1)" \
  "send_prompt 잔류 검사에 ❯ 마커 포함 (claude REPL 박힘 방지)"
# Layer 1 — 1회가 아닌 폴링 재시도 루프 (느린 Opus REPL 대비).
assert_success "$(grep -q 'SEND_PROMPT_RETRY_MAX' "$HARNESS_BIN/lib.sh" && echo 0 || echo 1)" \
  "send_prompt Enter 재전송이 폴링 재시도 (1회→N회)"

# Layer 2 — ❯ 프롬프트 라인에 잔류한 텍스트를 send_prompt 가 감지해 Enter 재전송하는가.
#   claude REPL 흉내: 입력을 즉시 소비하지 않고 '❯ <앞부분>' 을 화면에 띄운 더미 페인.
#   send_prompt 호출 시 폴링이 잔류를 보고 Enter 를 추가로 쏘는지 = capture 로 확인.
TS2="libtest2_$$"
HIT="$(mktemp)"
# 더미: ❯ 마커 + 고정 텍스트를 화면에 출력하고, Enter(빈 줄) 수신 시마다 HIT 에 기록.
tmux new-session -d -s "$TS2" -x 80 -y 24 \
  "bash -c 'printf \"❯ STUCKHEAD residual\n\"; while IFS= read -r ln; do echo enter >> $HIT; done'"
fix_session_indexing "$TS2"
sleep 0.3
# head 가 'STUCKHEAD residual' 앞 24자와 매치되도록 동일 텍스트 전송.
SEND_PROMPT_RETRY_MAX=3 SEND_PROMPT_RETRY_DELAY=0.3 send_prompt "$TS2:0.1" 'STUCKHEAD residual marker test'
sleep 0.5
tmux kill-session -t "$TS2" 2>/dev/null || true
# 잔류(❯+head)가 보였으므로 폴링이 Enter 를 1회 이상 재전송 → HIT 에 enter 기록.
ENTERS="$(wc -l < "$HIT" 2>/dev/null | tr -d ' ')"
assert_success "$([ "${ENTERS:-0}" -ge 1 ] && echo 0 || echo 1)" \
  "❯ 잔류 시 send_prompt 가 Enter 재전송 (Layer2 실동작, enters=${ENTERS:-0})"
rm -f "$HIT"

test_summary
