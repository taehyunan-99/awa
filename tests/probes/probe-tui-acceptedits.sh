#!/usr/bin/env bash
# C.1: TUI 모드에서 acceptEdits 가 *진짜로* 묻기 폭격 해소하는가?
#
# 자동 측정 어려움 — claude TUI 의 묻기 UI 가 화면에 뜨는지는 사용자 눈 또는 capture 분석 필요.
# 본 스크립트는 *세션을 띄우고 capture-pane 5회 떠서 결과를 디렉터리에 저장*.
# 사용자가 capture 파일을 보고 "묻기 UI 텍스트 있나" 판정.

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HARNESS_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
OUT_DIR="$HARNESS_ROOT/docs/probe-results/2026-05-21-tui-acceptedits"
mkdir -p "$OUT_DIR"

run_tui() {
  local label="$1" default_mode="$2"
  local dir="$HARNESS_ROOT/tmp-probe-tui-$label-$$"
  mkdir -p "$dir/.claude"
  cat > "$dir/.claude/settings.json" <<EOF
{"permissions":{"defaultMode":"$default_mode"}}
EOF

  local SESSION="probe-tui-$label-$$"

  echo "=== 시나리오 $label (defaultMode=$default_mode) ==="

  tmux new-session -d -s "$SESSION" -x 120 -y 40
  local PID="$(tmux display-message -p -t "$SESSION:0.0" '#{pane_id}')"

  tmux send-keys -t "$PID" "cd '$dir' && claude --model haiku" Enter

  sleep 30
  tmux capture-pane -p -S -500 -t "$PID" > "$OUT_DIR/${label}_t30s_boot.txt"

  tmux send-keys -t "$PID" "Use the Bash tool to run: echo SENT_${label}" Enter

  for t in 5 10 20 30; do
    sleep 5
    tmux capture-pane -p -S -500 -t "$PID" > "$OUT_DIR/${label}_t${t}s_after_bash.txt"
  done

  tmux kill-session -t "$SESSION" 2>/dev/null || true
  rm -rf "$dir"

  echo "  capture 5장 저장: $OUT_DIR/${label}_*.txt"
}

echo "C.1 TUI acceptEdits 실측 probe — 약 3분 (시나리오 2개)"
echo

run_tui "31-acceptEdits" "acceptEdits"
run_tui "32-default" "default"

cat > "$OUT_DIR/JUDGE-MANUAL.md" <<'EOF'
# TUI acceptEdits 묻기 폭격 해소 — 판정 가이드

## 검색 패턴

### 묻기 UI = ASK
- "Do you want to proceed?"
- "1. Yes" / "2. No"
- "권한 요청" / "Allow"

### 통과 = PASS
- `SENT_31` 또는 `SENT_32` 가 화면에 출력됨

## 판정

| 시나리오 | 기대 | 실측 |
|---|---|---|
| 31-acceptEdits | PASS | ___ |
| 32-default | ASK | ___ |

## 결론 매트릭스

- 31=PASS, 32=ASK → acceptEdits 가 묻기 폭격 해소. spec §1 핵심 가정 *유효*.
- 31=ASK → acceptEdits 도 묻기. spec §1 *재설계*.
- 31=PASS, 32=PASS → TUI 도 -p 처럼 묻지 않음. acceptEdits 효과 *미확정 — 무관*.
EOF

echo
echo "=== 완료 ==="
echo "결과: $OUT_DIR/"
echo "판정 가이드: $OUT_DIR/JUDGE-MANUAL.md"
