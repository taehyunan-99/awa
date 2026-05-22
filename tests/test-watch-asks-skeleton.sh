#!/usr/bin/env bash
# watch-asks 데몬 골격: PID 기록·lead skip·trap 정리.
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"
TMPHOME="$(mktemp -d)"
PROJ="$(mktemp -d)"
( cd "$PROJ" && git init -q )
export HOME="$TMPHOME"   # ~/.claude/projects 경로 격리 (실제 HOME 안 건드림 — T8 패턴 동일)
STATE="$PROJ/.agent-harness/state"
mkdir -p "$STATE"

# F1 정정: jsonl 을 *실제 claude 컨벤션 경로* (${HOME}/.claude/projects/-<enc>/<sid>.jsonl) 에 생성.
# PROJECT_ROOT 안 fixture (예: $PROJ/worker.jsonl) 는 위장 통과 — team-down 의 tail 정리가
# 실제 컨벤션 경로 tail 을 잡는지 검증 못 함 (re-review F1 지적).
enc="$(echo "$PROJ" | sed 's#^/##; s#/#-#g')"   # claude 단일 dash 컨벤션 (T8 과 동일 산출)
PROJDIR="$TMPHOME/.claude/projects/-${enc}"
mkdir -p "$PROJDIR"
WJSONL="$PROJDIR/sid-a.jsonl"
LJSONL="$PROJDIR/sid-l.jsonl"
touch "$WJSONL" "$LJSONL"
printf 'arch %%5 sid-a %s researcher\n' "$WJSONL" > "$STATE/workers.list"
printf 'LEAD %%9 sid-l %s lead\n' "$LJSONL" >> "$STATE/workers.list"

echo "[W1] 데몬 기동 → PID 파일"
PROJECT_ROOT="$PROJ" HARNESS_ROOT="$ROOT" bash "$ROOT/bin/watch-asks.sh" &
DPID=$!
for i in $(seq 1 20); do [ -f "$STATE/watch-asks.pid" ] && break; sleep 0.2; done
[ -f "$STATE/watch-asks.pid" ]; assert_success "$?" "W1 PID 파일 생성"

echo "[W2] 데몬 본체가 PROJECT_ROOT 로그 (F20)"
sleep 0.5
assert_contains "$(cat "$STATE/watch-asks.log" 2>/dev/null)" "$PROJ" "W2 PROJECT_ROOT 로그"

echo "[W3] tail 자식 존재 (worker jsonl 만 — lead skip)"
sleep 0.5
ntail="$(pgrep -P "$(cat "$STATE/watch-asks.pid")" 2>/dev/null | wc -l | tr -d ' ')"
[ "$ntail" -ge 1 ]; assert_success "$?" "W3 자식 프로세스 존재"

echo "[W4] SIGTERM → 자식·손자 정리 (실제 컨벤션 경로 tail)"
kill "$(cat "$STATE/watch-asks.pid")" 2>/dev/null || true
sleep 1
# tail 은 컨벤션 경로(PROJDIR)를 -F 하므로 패턴도 PROJDIR 기준 (PROJECT_ROOT 아님).
leftover="$(pgrep -f "tail -F.*$PROJDIR" 2>/dev/null | wc -l | tr -d ' ')"
assert_eq "0" "$leftover" "W4 tail 손자 정리"

wait "$DPID" 2>/dev/null || true
rm -rf "$PROJ" "$TMPHOME"
test_summary
