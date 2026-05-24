#!/usr/bin/env bash
# probe-compact-queue-sync.sh — 11차 설계 검증 (해법 A).
# 질문: /compact 가 진행되는 동안 send-keys 로 들어온 "다음 명령"이
#        compact 후 정상 실행되나(큐잉)? 아니면 유실되나?
#
# 이게 PASS 면 → LEAD 는 compact 완료를 따로 감지할 필요 없이,
#   compact 직후 "작업지시 + ready 신호 쓰기"를 연달아 주입하면
#   compact 끝난 뒤 큐가 풀려 실행되고 ready 파일이 생긴다 → watcher 가 그걸 감지.
#   즉 "compact 그 자체 완료"가 아니라 "compact 뒤 명령 완료"를 파일로 동기화.
#
# 부가 측정: compact 주입~ready 파일 생성까지 소요시간 → 고정 sleep 대신 파일폴링 근거.
#
# ★ claude 실기동 (토큰). claude -p 금지 — 사용자가 ! 로 실행.
# ★ 판정 = proof 파일 부수효과 (출력매칭 거짓양성 회피, 7차 교훈).
#
# 사용법: bash tests/probes/probe-compact-queue-sync.sh

set -u

WORK="/tmp/compactsync-probe-$$"
mkdir -p "$WORK"
cd "$WORK" || exit 1

SES="csprobe-$$"
PANE=""

cleanup() {
  [ -n "$PANE" ] && tmux kill-session -t "$SES" 2>/dev/null
  rm -rf "$WORK"
  echo ""
  echo "정리: 세션 $SES, 작업디렉터리 삭제"
}
trap cleanup EXIT

echo "=== probe-compact-queue-sync (claude 실기동) ==="
echo "작업디렉터리: $WORK"
echo ""

wait_repl() {
  local s="$1" i dump
  for i in $(seq 1 60); do
    sleep 2
    dump="$(tmux capture-pane -t "$s" -p 2>/dev/null)"
    if printf '%s' "$dump" | grep -Eq 'trust this folder|Yes, I trust'; then
      tmux send-keys -t "$s" Enter; continue
    fi
    if printf '%s' "$dump" | grep -qE 'Claude Code v[0-9]|Welcome back|bypass permissions on|accept edits on'; then
      return 0
    fi
  done
  return 1
}

inject() {
  tmux send-keys -t "$PANE" -l "$1"; sleep 0.4; tmux send-keys -t "$PANE" Enter
}

wait_proof() {  # $1=file $2=max(*2초)
  local f="$1" n="${2:-30}" i
  for i in $(seq 1 "$n"); do sleep 2; [ -f "$f" ] && return 0; done
  return 1
}

# 기동
tmux new-session -d -s "$SES" -c "$WORK" -x 200 -y 50
PANE="$(tmux display-message -p -t "$SES" '#{pane_id}')"
sleep 1
tmux send-keys -t "$PANE" "claude --model claude-haiku-4-5-20251001 --dangerously-skip-permissions" Enter
echo "claude 기동 중 (REPL ready 대기, 최대 ~120s)..."
if ! wait_repl "$PANE"; then echo "FAIL: REPL 준비 실패"; exit 1; fi
echo "REPL ready."
echo ""

# ── 사전: 컨텍스트를 좀 쌓아 compact 가 의미있게 (몇 줄 대화) ──
echo "--- 사전: 컨텍스트 적재 + 셋업 확인 ---"
inject "안녕. 너는 지금부터 내 지시를 따른다. ${WORK}/setup.txt 에 SETUP_OK 만 써라."
if ! wait_proof "$WORK/setup.txt" 30; then echo "FAIL: 셋업 안 됨. 중단."; exit 1; fi
echo "  셋업 OK"
# 컨텍스트 부풀리기 (compact 가 압축할 거리)
inject "1부터 5까지 각 숫자에 대해 한 문장씩 설명해줘. 파일은 쓰지 마."
sleep 8
echo ""

# ── 핵심: /compact 직후 즉시 다음 명령 주입 (sleep 없이 연달아) ──
echo "--- 핵심 검증: /compact 직후 즉시 명령 큐잉 ---"
rm -f "$WORK/ready.txt"
T0="$(date +%s)"
inject "/compact"
echo "  /compact 주입 ($(date +%H:%M:%S)). ★sleep 없이 즉시 다음 명령 주입..."
sleep 1   # compact 가 시작될 최소 틈만 (큐잉 검증이지 완료 대기 아님)
inject "${WORK}/ready.txt 에 QUEUED_OK 라고 써라. 이것만 해라."
echo "  다음 명령 주입 완료. compact 끝나고 큐가 풀려 실행되길 대기 (최대 ~90s)..."

if wait_proof "$WORK/ready.txt" 45; then
  T1="$(date +%s)"
  _v="$(cat "$WORK/ready.txt")"
  echo ""
  echo "  ✅ PASS: compact 중 주입한 명령이 compact 후 실행됨 (ready=$_v)"
  echo "     소요: compact 주입~ready 생성 = $((T1 - T0))초"
  echo "     → 해법 A 유효: LEAD 는 compact 후 '작업+ready신호' 주입하면"
  echo "       큐잉됐다가 실행되고 watcher 가 ready 파일 감지로 동기화."
  echo "     → 고정 sleep 불필요, 파일폴링(wait_proof 동형)으로 완료 감지."
else
  echo ""
  echo "  ❌ FAIL: ready.txt 안 생김 → compact 중 주입 명령이 유실되거나 큐 비워짐"
  echo "     → 해법 A 불가. compact 완료를 별도 감지(B/C) 후 명령 보내야 함."
  echo "     (capture-pane 으로 현재 화면 덤프 — 수동 해석용:)"
  tmux capture-pane -t "$PANE" -p 2>/dev/null | grep -v '^$' | tail -12
fi
echo ""
echo "================= 결론 ================="
echo "PASS → compact 동기화 = '뒤 명령에 ready 신호 묶기'로 해결(별도 인프라 0)."
echo "FAIL → compact 자체 완료 감지 메커니즘 필요(설계 재고)."
echo "========================================"
