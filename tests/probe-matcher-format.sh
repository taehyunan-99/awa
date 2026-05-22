#!/usr/bin/env bash
# F17/F34/F26: claude allow/deny matcher 형식 실측.
# 같은 명령에 대해 colon-asterisk vs space-glob vs pipe-literal 패턴을
# settings.allow 에 박고, tmux 세션에서 워커 claude 에 명령을 주입한 뒤
# ask 가 뜨는지(=매칭 실패) 안 뜨는지(=매칭 성공) capture-pane 으로 관찰.
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh

if [ "${RUN_INTEGRATION:-0}" != "1" ]; then
  echo "SKIP: RUN_INTEGRATION!=1 (matcher 형식 probe 는 claude 의존)"
  exit 0
fi

ROOT="$(cd .. && pwd)"
TMP="$(mktemp -d)"
SESSION="probe-matcher-$$"
cleanup() { tmux kill-session -t "$SESSION" 2>/dev/null || true; rm -rf "$TMP"; }
trap cleanup EXIT
( cd "$TMP" && git init -q )

probe_one() {  # $1=pattern $2=command $3=label
  local pattern="$1" cmd="$2" label="$3"
  local sdir="$TMP/.claude"
  mkdir -p "$sdir"
  printf '{"permissions":{"allow":["%s"]}}\n' "$pattern" > "$sdir/settings.json"
  tmux kill-session -t "$SESSION" 2>/dev/null || true
  tmux new-session -d -s "$SESSION" -c "$TMP" -x 200 -y 50
  local pane; pane="$(tmux display-message -p -t "$SESSION" '#{pane_id}')"
  tmux send-keys -t "$pane" -l "claude --settings \"$sdir/settings.json\""
  tmux send-keys -t "$pane" Enter
  sleep 8
  if tmux capture-pane -p -t "$pane" | grep -Eq 'trust this folder|Yes, I trust'; then
    tmux send-keys -t "$pane" Enter; sleep 3
  fi
  tmux send-keys -t "$pane" -l "$cmd"
  tmux send-keys -t "$pane" Enter
  sleep 5
  local dump; dump="$(tmux capture-pane -p -S -100 -t "$pane")"
  if printf '%s' "$dump" | grep -Eq 'Do you want|1\. Yes|Allow this'; then
    echo "  [$label] pattern='$pattern' → ASK (매칭 실패)"
  else
    echo "  [$label] pattern='$pattern' → NO-ASK (매칭 성공)"
  fi
  tmux kill-session -t "$SESSION" 2>/dev/null || true
}

probe_one 'Bash(ls:*)'        'ls /tmp'      'colon-단일'
probe_one 'Bash(ls *)'        'ls /tmp'      'space-단일'
probe_one 'Bash(kill -0:*)'   'kill -0 $$'   'colon-옵션'
probe_one 'Bash(kill -0 *)'   'kill -0 $$'   'space-옵션'
probe_one 'Bash(curl * | sh)' 'echo x | sh'  'pipe-literal'

echo "---- 형식 매트릭스 결과를 본 plan T5/T6 패턴 + spec §5.12 에 반영하라 ----"
