#!/usr/bin/env bash
# 멀티 프로젝트 동시 가동 실측. run-all 비포함, 수동 실행.
# 두 임시 git repo 에서 동시에 team-up → hook 각자 events.log 에만 기록되는지.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP1="/tmp/probe_mp_$$/projectA"; mkdir -p "$TMP1" && ( cd "$TMP1" && git init -q )
TMP2="/tmp/probe_mp_$$/projectB"; mkdir -p "$TMP2" && ( cd "$TMP2" && git init -q )
cleanup() {
  tmux kill-session -t "agents-projectA" 2>/dev/null
  tmux kill-session -t "agents-projectB" 2>/dev/null
  rm -rf "/tmp/probe_mp_$$"
}
trap cleanup EXIT

echo "[probe-multi-project] A·B 동시 team-up..."
HARNESS_PROJECT="$TMP1" bash "$ROOT/bin/team-up.sh" default >/dev/null 2>&1
HARNESS_PROJECT="$TMP2" bash "$ROOT/bin/team-up.sh" default >/dev/null 2>&1
sleep 30  # claude REPL 준비

echo "[probe-multi-project] A 의 dev 페인에 Write 지시..."
TGT_A="$(tmux list-panes -t agents-projectA:0 -F '#{pane_index}\t#{pane_title}' | awk -F'\t' '$2=="dev"{print "agents-projectA:0."$1}')"
tmux send-keys -t "$TGT_A" -l "make a file named hello-a.txt with content hi using the Write tool"
sleep 1; tmux send-keys -t "$TGT_A" Enter
echo "[probe-multi-project] B 의 dev 페인에 Write 지시..."
TGT_B="$(tmux list-panes -t agents-projectB:0 -F '#{pane_index}\t#{pane_title}' | awk -F'\t' '$2=="dev"{print "agents-projectB:0."$1}')"
tmux send-keys -t "$TGT_B" -l "make a file named hello-b.txt with content hi using the Write tool"
sleep 1; tmux send-keys -t "$TGT_B" Enter

echo "[probe-multi-project] hook 발화 60s 대기..."
sleep 60

# 격리 검증: A 의 events.log 에 A 만, B 의 events.log 에 B 만
fail=0
if ! grep -q "hello-a.txt" "$TMP1/.agent-harness/events.log" 2>/dev/null; then
  echo "[probe-multi-project] FAIL — A events.log 에 hello-a.txt 없음"; fail=1
fi
if ! grep -q "hello-b.txt" "$TMP2/.agent-harness/events.log" 2>/dev/null; then
  echo "[probe-multi-project] FAIL — B events.log 에 hello-b.txt 없음"; fail=1
fi
if grep -q "hello-b.txt" "$TMP1/.agent-harness/events.log" 2>/dev/null; then
  echo "[probe-multi-project] FAIL — A events.log 에 B 의 파일 누출"; fail=1
fi
if grep -q "hello-a.txt" "$TMP2/.agent-harness/events.log" 2>/dev/null; then
  echo "[probe-multi-project] FAIL — B events.log 에 A 의 파일 누출"; fail=1
fi

if [ "$fail" = "0" ]; then
  echo "[probe-multi-project] PASS (hook env 격리 + 동시 가동 정상)"
  exit 0
else
  echo "[probe-multi-project] FAIL — pane 덤프(A·B):"
  tmux capture-pane -t "$TGT_A" -p | tail -20
  echo "---"
  tmux capture-pane -t "$TGT_B" -p | tail -20
  exit 1
fi
