#!/usr/bin/env bash
# probe-sendkeys-wake-safety.sh — 9차 설계 검증.
# D1(명령큐 + idle 일 때만 send-keys) 안전성 실측.
# 검증: claude REPL 이 (S1)idle / (S2)처리중 / (S3)AskUserQuestion 중일 때
#       각각 send-keys 주입이 어떻게 되는가.
#
# ★ claude 실기동 필요 (토큰 소모). claude -p 금지 — 사용자가 ! 로 실행.
# ★ 판정은 파일 부수효과(proof file)로 — 출력 텍스트 매칭은 거짓양성 위험(7차 교훈).
#
# 사용법: bash tests/probes/probe-sendkeys-wake-safety.sh
# 결과: 각 시나리오의 proof 파일 존재/내용으로 PASS/FAIL 보고.

set -u

WORK="/tmp/sendkeys-probe-$$"
mkdir -p "$WORK"
cd "$WORK" || exit 1

SES="skprobe-$$"
PANE=""

cleanup() {
  [ -n "$PANE" ] && tmux kill-session -t "$SES" 2>/dev/null
  echo "정리: 세션 $SES, 작업디렉터리 $WORK"
}
trap cleanup EXIT

echo "=== probe-sendkeys-wake-safety (claude 실기동) ==="
echo "작업디렉터리: $WORK"
echo ""

# claude REPL ready 판별 (wait_repl 패턴 이식)
wait_repl() {
  local s="$1" i dump
  for i in $(seq 1 60); do
    sleep 2
    dump="$(tmux capture-pane -t "$s" -p 2>/dev/null)"
    if printf '%s' "$dump" | grep -Eq 'trust this folder|Yes, I trust'; then
      tmux send-keys -t "$s" Enter
      continue
    fi
    if printf '%s' "$dump" | grep -qE 'Claude Code v[0-9]|Welcome back|bypass permissions on|accept edits on'; then
      return 0
    fi
  done
  return 1
}

# 세션 기동 (claude REPL)
tmux new-session -d -s "$SES" -c "$WORK" -x 200 -y 50
PANE="$(tmux display-message -p -t "$SES" '#{pane_id}')"
sleep 1
tmux send-keys -t "$PANE" "claude" Enter
echo "claude 기동 중 (REPL ready 대기, 최대 ~120s)..."
if ! wait_repl "$PANE"; then
  echo "FAIL: claude REPL 준비 실패 (trust/로그인 확인)"
  exit 1
fi
echo "REPL ready."
echo ""

# ── S1: idle 일 때 send-keys 주입 → lead 가 깨어나 proof 파일 쓰나? ──
echo "--- S1: idle 주입 ---"
rm -f "$WORK/s1-proof.txt"
tmux send-keys -t "$PANE" -l "지금 즉시 '$WORK/s1-proof.txt' 파일에 IDLE_WAKE 라고 써줘. 다른 말 하지 말고 그것만."
sleep 0.5
tmux send-keys -t "$PANE" Enter
echo "idle 주입 완료. 처리 대기..."
for i in $(seq 1 30); do sleep 2; [ -f "$WORK/s1-proof.txt" ] && break; done
if [ -f "$WORK/s1-proof.txt" ]; then
  echo "S1 PASS: idle 주입 → 깨어나 처리됨 (proof: $(cat "$WORK/s1-proof.txt"))"
else
  echo "S1 FAIL: idle 주입 무반응"
fi
echo ""

# ── S2: 처리중일 때 send-keys 주입 → 큐잉되나 유실되나? ──
echo "--- S2: 처리중 주입 (긴 작업 시작 직후 두번째 주입) ---"
rm -f "$WORK/s2-first.txt" "$WORK/s2-second.txt"
# 첫 작업: 5초 걸리는 일 (sleep 후 파일) — 처리중 상태 유발
tmux send-keys -t "$PANE" -l "Bash 로 'sleep 6 && echo FIRST > $WORK/s2-first.txt' 를 실행해줘."
sleep 0.5; tmux send-keys -t "$PANE" Enter
sleep 2  # 처리중으로 진입
# 처리중에 두번째 주입
tmux send-keys -t "$PANE" -l "그게 끝나면 '$WORK/s2-second.txt' 에 SECOND 라고 써줘."
sleep 0.5; tmux send-keys -t "$PANE" Enter
echo "처리중 주입 완료. 두 파일 대기..."
for i in $(seq 1 40); do sleep 2; [ -f "$WORK/s2-second.txt" ] && break; done
echo "S2 결과: first=$([ -f "$WORK/s2-first.txt" ] && echo Y || echo N) second=$([ -f "$WORK/s2-second.txt" ] && echo Y || echo N)"
if [ -f "$WORK/s2-second.txt" ]; then
  echo "S2 PASS: 처리중 주입이 큐잉되어 처리됨 (유실 아님)"
else
  echo "S2 FAIL/주의: 처리중 주입 유실 또는 미처리 — D1 의 'idle 일 때만' 조건 필요성 입증"
fi
echo ""

# ── S3 (가장 중요): AskUserQuestion 중 send-keys 주입 → 선택 오염되나? ──
echo "--- S3: AskUserQuestion 중 주입 (선택 오염 검증) — 사용자 조작 필요 ---"
rm -f "$WORK/s3-choice.txt"
# lead 에게 AskUserQuestion 유발 + 선택 결과를 파일로 남기게
tmux send-keys -t "$PANE" -l "AskUserQuestion 도구로 나에게 'A안 vs B안' 둘 중 무엇이냐고 물어봐. 내가 고르면 고른 값을 Bash 로 '$WORK/s3-choice.txt' 에 써줘."
sleep 0.5; tmux send-keys -t "$PANE" Enter
echo "AskUserQuestion 다이얼로그 뜰 때까지 대기 (~14s)..."
for i in $(seq 1 7); do
  sleep 2
  tmux capture-pane -t "$PANE" -p 2>/dev/null | grep -qiE 'A안|B안|Select|선택|❯ 1|1\.' && break
done
echo ""
echo "★★★ 다이얼로그가 떴습니다. 이제 watcher 오염 주입을 보냅니다 ★★★"
# AskUserQuestion 중에 watcher 알림 주입 — 이게 선택을 오염시키나?
tmux send-keys -t "$PANE" -l "@gate: 워커 승인 대기 (uuid=POLLUTE). watcher 알림."
sleep 0.3; tmux send-keys -t "$PANE" Enter
sleep 2
echo "=== 오염 주입 직후 다이얼로그 캡처 ==="
tmux capture-pane -t "$PANE" -p 2>/dev/null | tail -25
echo ""
echo "================================================================"
echo "★ 사용자 조작 필요: 다른 터미널에서 아래로 attach 해 다이얼로그를 직접 보세요:"
echo "    tmux attach -t $SES"
echo "  확인 포인트:"
echo "   (a) 다이얼로그가 깨졌나? @gate 텍스트가 선택지/입력란에 끼었나?"
echo "   (b) 정상이면 A안 또는 B안을 직접 선택하세요."
echo "   (c) 선택 후 detach (Ctrl-b d). s3-choice.txt 가 정상 기록되는지 봅니다."
echo "  ※ 이 스크립트는 60초 후 세션을 정리합니다. 그 안에 확인하세요."
echo "================================================================"
for i in $(seq 1 30); do sleep 2; [ -f "$WORK/s3-choice.txt" ] && break; done
echo ""
echo "S3 결과: s3-choice = $([ -f "$WORK/s3-choice.txt" ] && cat "$WORK/s3-choice.txt" || echo '(없음/미선택)')"
echo "최종 화면:"
tmux capture-pane -t "$PANE" -p 2>/dev/null | tail -12
