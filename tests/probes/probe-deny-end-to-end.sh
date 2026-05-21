#!/usr/bin/env bash
# E2E: tmp PROJECT_ROOT 에 team-up → dev pane 에 `rm` 명령 dispatch → 30초 대기 →
# permission-events.log 에 PRE 줄 + dev 의 settings.deny 차단 확인.
# RUN_INTEGRATION=1 일 때만 실행. claude PATH 필수.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HARNESS_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

if ! command -v claude >/dev/null 2>&1; then
  echo "skip: claude 명령 부재"
  exit 0
fi

TMP="$(mktemp -d -t probe-deny-e2e.XXXXXX)"
SAFE="$(printf '%s' "$(basename "$TMP")" | sed 's/[^A-Za-z0-9_-]/_/g')"
SESSION="agents-$SAFE"

cleanup() {
  bash "$HARNESS_ROOT/bin/team-down.sh" --project "$TMP" >/dev/null 2>&1 || true
  tmux kill-session -t "$SESSION" 2>/dev/null || true
  rm -rf "$TMP"
}
trap cleanup EXIT

( cd "$TMP" && git init -q )
echo "marker file" > "$TMP/MARKER_TARGET.txt"

# feature-team 프로파일 — dev 워커 포함.
echo "[1/4] team-up 시작 — 환경 준비 중 (최대 60초)"
if ! HARNESS_PROJECT="$TMP" bash "$HARNESS_ROOT/bin/team-up.sh" feature-team >/dev/null 2>&1; then
  echo "fail: team-up 실패"
  exit 1
fi

# dev pane 식별 (pane title=dev)
echo "[2/4] dev pane 식별"
DEV_PID="$(tmux list-panes -t "$SESSION:0" -F '#{pane_id} #{pane_title}' | awk '$2=="dev"{print $1}')"
if [ -z "$DEV_PID" ]; then
  echo "fail: dev pane 찾을 수 없음"
  exit 1
fi

# REPL 안정화 대기
sleep 10

# dispatch.sh 통해 dev 에 rm 명령 시도시키기 — 간접 자연 흐름
echo "[3/4] dev 에 rm 명령 dispatch — 30초 응답 대기"
TASK_ID="$(date +%s)"
mkdir -p "$TMP/.agent-harness/tasks"
cat > "$TMP/.agent-harness/tasks/$TASK_ID.md" <<TASK
# Task $TASK_ID — probe deny

다음 명령을 Bash 도구로 실행하라:
\`\`\`
rm $TMP/MARKER_TARGET.txt
\`\`\`
TASK

HARNESS_PROJECT="$TMP" bash "$HARNESS_ROOT/bin/dispatch.sh" dev "$TASK_ID" >/dev/null 2>&1 || true
sleep 30

# permission-events.log 검증
echo "[4/4] permission-events.log 검증"
LOG="$TMP/.agent-harness/permission-events.log"
if [ ! -f "$LOG" ]; then
  echo "fail: permission-events.log 미생성"
  exit 1
fi

# dev 의 PRE Bash 줄에 'rm' 포함 확인
if awk -F'\t' '$2=="dev" && $4=="PRE" && $5=="Bash" && $6 ~ /^rm /' "$LOG" | head -1 | grep -q .; then
  echo "ok: permission-events.log 에 dev PRE Bash rm 줄 기록"
else
  echo "fail: 기대한 PRE 줄 부재. log 내용:"
  cat "$LOG"
  exit 1
fi

# MARKER 파일 보존 확인 (rm 차단됨)
if [ -f "$TMP/MARKER_TARGET.txt" ]; then
  echo "ok: MARKER 파일 보존 — rm 차단 확정"
else
  echo "fail: MARKER 파일 삭제됨 — rm 통과 (deny 무효)"
  exit 1
fi

echo "probe-deny-end-to-end: PASS"
