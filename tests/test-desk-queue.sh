#!/usr/bin/env bash
# P11 Phase4 — desk-queue 탈-tmux 검증.
# DESK 가 tmux 를 직접 안 건드리고 desk-queue/<id>.json 만 쓰면, watcher(sandbox 밖)가 폴링해
# orch 페인에 @desk: <지시> 를 대신 전달한다. orch 페인은 cat(AGENT_CMD)이라 입력이 화면에
# 그대로 찍히므로 capture-pane 으로 @desk: 도착을 확인. DESK sandbox 동일조건(tmux 명령 0) 검증.
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
source ./harness-paths.sh

ROOT="$(cd .. && pwd)"
export SESSION_OVERRIDE="desk_$$"
export AGENT_CMD="cat"   # orch/desk/워커 전부 cat — 입력이 페인에 그대로 표시.

TMP_PROJ="$(mktemp -d)"; ( cd "$TMP_PROJ" && git init -q )
export HARNESS_PROJECT="$TMP_PROJ"

_XDG="$(mktemp -d)"; export XDG_CONFIG_HOME="$_XDG"

cleanup() {
  tmux kill-session -t "$SESSION_OVERRIDE" 2>/dev/null || true
  [ -n "${TMP_PROJ:-}" ] && rm -rf "$TMP_PROJ"
  [ -n "${_XDG:-}" ] && rm -rf "$_XDG"
}
trap cleanup EXIT

bash "$HARNESS_BIN/awa-up.sh" default >/dev/null
sleep 0.5

# orch 페인 찾기 (pane_title=ORCH).
ORCH_PANE=""
while IFS=$'\t' read -r pid ptitle; do
  [ "$ptitle" = "ORCH" ] && ORCH_PANE="$pid"
done < <(tmux list-panes -t "$SESSION_OVERRIDE" -a -F $'#{pane_id}\t#{pane_title}' 2>/dev/null)
assert_eq "0" "$([ -n "$ORCH_PANE" ] && echo 0 || echo 1)" "ORCH 페인 식별"

WS="$TMP_PROJ/.agent-harness"
# 1) DESK 가 할 일을 모사: desk-queue 에 지시 json atomic write (tmux 명령 0 — sandbox DESK 동일조건).
MARK="PMQ-MARK-$$"
mkdir -p "$WS/state/desk-queue"
jq -n --arg i "$MARK truncate 작업 추가하라" '{instruction:$i}' \
  > "$WS/state/desk-queue/p1.json.tmp"
mv "$WS/state/desk-queue/p1.json.tmp" "$WS/state/desk-queue/p1.json"

# 2) watcher 가 큐를 소비해 orch 페인에 @desk: 전달 → 화면에 마커 출현까지 대기(최대 ~8s).
got=1
for _i in $(seq 1 80); do
  if tmux capture-pane -t "$ORCH_PANE" -p 2>/dev/null | grep -q "@desk: $MARK"; then
    got=0; break
  fi
  sleep 0.1
done
assert_eq "0" "$got" "watcher 가 desk-queue 소비→orch 에 @desk: 전달(화면 도착)"

# 3) 큐 .json 소비(삭제) — 무한 재전달 방지. send-keys 후 rm 까지 한 폴링 사이클 여유.
for _i in $(seq 1 30); do
  [ -f "$WS/state/desk-queue/p1.json" ] || break
  sleep 0.1
done
assert_eq "1" "$([ -f "$WS/state/desk-queue/p1.json" ] && echo 0 || echo 1)" "처리된 desk-queue .json 소비됨(삭제)"

test_summary
