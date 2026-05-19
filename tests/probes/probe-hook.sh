#!/usr/bin/env bash
# PostToolUse hook 실측: tmux pane 기동 claude 에 프로젝트 .claude/settings.json
# 의 PostToolUse hook 이 적용되고 HARNESS_WORKER env 가 전달되는지. 수동 실행.
set -uo pipefail
S="probe_hook_$$"
WS="/tmp/$S-ws"
cleanup() { tmux kill-session -t "$S" 2>/dev/null || true; rm -rf "$WS"; }
trap cleanup EXIT

rm -rf "$WS"; mkdir -p "$WS/.claude"
: > "$WS/events.log"

# 최소 hook: Write/Edit 후 tool_input.file_path 를 events.log 에 기록
cat > "$WS/.claude/settings.json" <<'JSON'
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit|MultiEdit",
        "hooks": [
          { "type": "command", "command": "jq -r '.tool_input.file_path // empty' | while read -r p; do [ -n \"$p\" ] && echo \"hook\t${HARNESS_WORKER:-NOENV}\t-\tmodify\t$p\" >> '$WS/events.log'; done" }
        ]
      }
    ]
  }
}
JSON
# settings.json 안의 $WS 를 실제 경로로 치환 (heredoc 내 변수 미전개 대응)
sed -i.bak "s#\$WS#$WS#g" "$WS/.claude/settings.json" && rm -f "$WS/.claude/settings.json.bak"

tmux new-session -d -s "$S" -x 200 -y 50
tmux set-option -t "$S" allow-set-title off 2>/dev/null || true
tmux send-keys -t "$S" -l "cd $WS && HARNESS_WORKER=probeworker claude --dangerously-skip-permissions"
tmux send-keys -t "$S" Enter
echo "[probe-hook] claude 기동 35s 대기..."
sleep 35

# cwd·CLAUDE_PROJECT_DIR 진단: settings.json 을 어디 둬야 claude 가 읽는지,
# hook 안에서 CLAUDE_PROJECT_DIR 이 무엇으로 잡히는지 확인 (T6 경로 확정 근거).
tmux send-keys -t "$S" -l "run: pwd; echo CLAUDE_PROJECT_DIR=\$CLAUDE_PROJECT_DIR"
sleep 1
tmux send-keys -t "$S" Enter
sleep 8
echo "[probe-hook] cwd·CLAUDE_PROJECT_DIR 진단 (pane 덤프):"
tmux capture-pane -t "$S" -p | grep -E 'CLAUDE_PROJECT_DIR|/tmp/probe_hook' | tail -5

tmux send-keys -t "$S" -l "make a file named hello.txt with content hi using the Write tool"
sleep 1
tmux send-keys -t "$S" Enter
echo "[probe-hook] Write 지시, hook 발화 60s 대기..."
sleep 60

if grep -q "hello.txt" "$WS/events.log" 2>/dev/null; then
  echo "[probe-hook] events.log 기록됨:"; cat "$WS/events.log"
  if grep -q "probeworker" "$WS/events.log"; then
    echo "[probe-hook] PASS (hook 적용 + HARNESS_WORKER 전달). 위 cwd·CLAUDE_PROJECT_DIR 진단을 T6 settings.json 경로에 반영하라."; exit 0
  else
    echo "[probe-hook] PARTIAL — hook 적용되나 HARNESS_WORKER 미전달(NOENV). T6 에서 워커명을 pane title 조회로 대체"; exit 2
  fi
else
  echo "[probe-hook] FAIL — hook 미적용(또는 settings.json 위치 부적합 — 위 cwd 진단 확인). spec §5.6 폴백 발동:"; tmux capture-pane -t "$S" -p | tail -30; exit 1
fi
