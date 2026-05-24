#!/usr/bin/env bash
# probe-clear-compact-injection.sh — 11차 설계 검증.
# LEAD 가 워커 pane 에 send-keys 로 /clear·/compact 를 주입해 컨텍스트를 관리할 수 있는가.
#
# 검증 질문:
#   Q1. /clear send-keys 가 실제로 워커 대화를 초기화하나? (이전에 심은 비밀이 사라지나)
#   Q2. /clear 후 워커가 역할(부트 prompt)을 잊나? → 역할 재주입 필요 여부 판정
#   Q3. /compact send-keys 가 실제 압축되나? + /compact 후엔 비밀이 유지되나(요약 보존)
#
# ★ claude 실기동 필요 (토큰 소모). claude -p 금지 — 사용자가 ! 로 실행.
# ★ 판정은 파일 부수효과(proof file) + capture-pane 토큰표시로 — 출력 텍스트 매칭은
#   거짓양성 위험(7차 교훈)이나, /clear 초기화 여부는 "심은 비밀 회상 가능?"로 행동검증.
#
# 사용법: bash tests/probes/probe-clear-compact-injection.sh
# 결과: 각 Q 의 PASS/FAIL + 해석.

set -u

WORK="/tmp/clearcompact-probe-$$"
mkdir -p "$WORK"
cd "$WORK" || exit 1

SES="ccprobe-$$"
PANE=""

cleanup() {
  [ -n "$PANE" ] && tmux kill-session -t "$SES" 2>/dev/null
  echo ""
  echo "정리: 세션 $SES, 작업디렉터리 $WORK"
}
trap cleanup EXIT

echo "=== probe-clear-compact-injection (claude 실기동) ==="
echo "작업디렉터리: $WORK"
echo ""

# claude REPL ready 판별
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

# 프롬프트 한 줄 주입 (literal + Enter 분리 — half-sent 방지)
inject() {
  tmux send-keys -t "$PANE" -l "$1"
  sleep 0.4
  tmux send-keys -t "$PANE" Enter
}

# proof 파일이 생길 때까지 대기 (최대 N*2초)
wait_proof() {
  local f="$1" n="${2:-30}" i
  for i in $(seq 1 "$n"); do sleep 2; [ -f "$f" ] && return 0; done
  return 1
}

# 세션 기동
tmux new-session -d -s "$SES" -c "$WORK" -x 200 -y 50
PANE="$(tmux display-message -p -t "$SES" '#{pane_id}')"
sleep 1
# ★ --dangerously-skip-permissions: probe 격리 환경. 없으면 Write 시 묻기모드로 멈춤(셋업 실패 원인).
#   haiku: 빠른 모델로 토큰·시간 절약 (probe 목적은 clear/compact 메커니즘이지 추론력 아님).
tmux send-keys -t "$PANE" "claude --model claude-haiku-4-5-20251001 --dangerously-skip-permissions" Enter
echo "claude 기동 중 (REPL ready 대기, 최대 ~120s)..."
if ! wait_repl "$PANE"; then
  echo "FAIL: claude REPL 준비 실패 (trust/로그인 확인)"
  exit 1
fi
echo "REPL ready."
echo ""

# ── 사전: 워커에 "역할"과 "비밀"을 심는다 ──────────────────────
# 역할: 앞으로 어떤 작업 요청에도 먼저 proof 파일에 ROLE_ALIVE 를 쓴다 (역할 유지 검증용).
# 비밀: 숫자 4172 를 기억하라 (clear 여부 검증용).
echo "--- 사전 셋업: 역할 + 비밀(4172) 심기 ---"
inject "규칙: (1) 너의 비밀 숫자는 4172 다. 기억해라. (2) 앞으로 내가 '작업'이라고 하면 무조건 먼저 ${WORK}/role.txt 파일에 ROLE_ALIVE 한 줄을 써라. 지금은 ${WORK}/setup.txt 에 SETUP_OK 만 써라."
if wait_proof "$WORK/setup.txt" 30; then
  echo "  셋업 OK ($(cat "$WORK/setup.txt"))"
else
  echo "  FAIL: 셋업 proof 안 생김 — 이후 검증 무의미. 중단."
  exit 1
fi
echo ""

# ── Q3 먼저: /compact 후 비밀 유지되나 (compact 는 비파괴라 먼저) ──
echo "--- Q3: /compact 주입 → 압축 후 비밀(4172) 회상 가능? ---"
rm -f "$WORK/compact-recall.txt"
inject "/compact"
echo "  /compact 처리 대기 (압축은 시간 걸림, ~40s)..."
sleep 40
# compact 후 비밀 회상 요청
inject "네 비밀 숫자를 ${WORK}/compact-recall.txt 에 그대로 써라. 숫자만."
if wait_proof "$WORK/compact-recall.txt" 30; then
  _v="$(tr -dc '0-9' < "$WORK/compact-recall.txt")"
  if [ "$_v" = "4172" ]; then
    echo "  Q3 PASS: /compact 후에도 비밀 유지됨 (회상=$_v) → 연속작업에 compact 안전"
  else
    echo "  Q3 PARTIAL: /compact 후 회상값=$_v (기대 4172) → 압축이 비밀 일부 손실?"
  fi
else
  echo "  Q3 FAIL: /compact 후 proof 안 생김 (compact 가 REPL 막았거나 미실행)"
fi
echo ""

# ── Q1+Q2: /clear 주입 → 비밀 사라지나(Q1) + 역할 사라지나(Q2) ──
echo "--- Q1+Q2: /clear 주입 → 초기화 검증 ---"
rm -f "$WORK/clear-recall.txt" "$WORK/role.txt"
inject "/clear"
echo "  /clear 처리 대기 (~8s)..."
sleep 8
# Q1: clear 후 비밀 회상 시도 — 못 하면 clear 가 실제로 초기화한 것
inject "네 비밀 숫자가 뭐였는지 ${WORK}/clear-recall.txt 에 써라. 모르면 UNKNOWN 이라고 써라."
if wait_proof "$WORK/clear-recall.txt" 30; then
  _cv="$(cat "$WORK/clear-recall.txt")"
  if printf '%s' "$_cv" | grep -q '4172'; then
    echo "  Q1 RESULT: clear 후에도 비밀 회상됨($_cv) → ⚠ /clear 가 초기화 안 했거나 send-keys 미실행"
  else
    echo "  Q1 PASS: clear 후 비밀 회상 불가($_cv) → /clear 가 실제 컨텍스트 초기화함 ✓"
  fi
else
  echo "  Q1 NOTE: clear-recall proof 안 생김 — clear 후 응답 자체가 안 옴(아래 Q2와 함께 해석)"
fi
echo ""

# Q2: clear 후 '작업' 이라고 했을 때 역할(role.txt 쓰기)이 살아있나?
echo "--- Q2: /clear 후 역할 유지 검증 ('작업' 트리거 → role.txt?) ---"
rm -f "$WORK/role.txt"
inject "작업"
if wait_proof "$WORK/role.txt" 25; then
  echo "  Q2 RESULT: clear 후에도 '작업'→role.txt 생김 → ⚠ 역할 유지됨(=clear 가 prompt 안 지웠나?)"
else
  echo "  Q2 PASS: clear 후 '작업' 해도 role.txt 안 생김 → 역할 망각됨 → /clear 후 역할 재주입 필수 ✓"
fi
echo ""

echo "================= 종합 해석 ================="
echo "Q1(clear 초기화) + Q2(역할망각) 둘 다 PASS → /clear 는 완전초기화. LEAD 는 새작업 시"
echo "  '/clear' 주입 후 반드시 역할 prompt 재주입 세트로 써야 함."
echo "Q3(compact 비밀유지) PASS → 연속작업은 /compact 로 컨텍스트 압축하며 역할·맥락 보존 가능."
echo "각 결과의 ⚠ 표시는 설계 가정과 다른 실측 — 그 경우 설계 재고 필요."
echo "=============================================="
