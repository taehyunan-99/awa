#!/usr/bin/env bash
# 층3: 실 dev 워커가 5축 ②출력계약(header-first) 을 실제로 따르는지 라이브 관측.
# 토큰 경계: dev=실 claude → 사용자가 ! 로. 어시스턴트는 claude 직접 실행 금지.
set -uo pipefail
cd "$(dirname "$0")"
ROOT="$(cd ../.. && pwd)"
SES="r5_$$"
PROJ="$(mktemp -d)"; WS="$PROJ/.agent-harness"
mkdir -p "$WS/tasks" "$WS/results"
echo "$PROJ" > /tmp/r5-last-proj
echo "$SES"  > "$WS/.session"

# 작은 task 1개 — dev 가 boot 의 _common.md 5축을 따라 results 를 써야 한다.
cat > "$WS/tasks/T1.md" <<'EOF'
# TASK T1
allowed_paths: ["scratch/hello.txt"]
forbidden_paths: []
지시: scratch/hello.txt 에 "hello" 한 줄을 쓴다. 그리고 결과를 results/T1.md 에
_common.md 의 결과 출력 계약(header-first: status 헤더 + EVIDENCE/HYPOTHESIS 본문)대로 기록하라.
EOF

# dev pane = 실 claude. _common.md + dev.md 합본을 boot 로 주입해야 5축이 적용된다.
# (정식 경로: awa-up 이 워커 boot 를 만든다. 여기선 관측이라 dev 1개만 직접 기동.)
DEV_BOOT="$WS/.boot-dev.md"
# source 는 stdout/stderr 모두 막아 $() 오염 방지(lib.sh source-safe·stdout 빈 것 실측, 미래 방어).
_dev_role="$(. "$ROOT/bin/lib.sh" >/dev/null 2>&1; resolve_role_file "$ROOT/prompts" dev)"
[ -n "$_dev_role" ] || { echo "오류: dev 역할파일 글롭 해석 실패 (Task1 적용됐나?)" >&2; exit 1; }
cat "$ROOT/prompts/_common.md" "$_dev_role" \
  | sed -e "s#{{WORKER_NAME}}#dev#g" -e "s#{{SESSION}}#$SES#g" -e "s#{{HARNESS_ROOT}}#$ROOT#g" > "$DEV_BOOT"

tmux new-session -d -s "$SES" -c "$PROJ" -x 200 -y 50 -n team
DEV_PANE="$(tmux display-message -p -t "$SES" '#{pane_id}')"
tmux send-keys -t "$DEV_PANE" -l "export HARNESS_WORKER=dev && claude --dangerously-skip-permissions"
tmux send-keys -t "$DEV_PANE" Enter
# REPL 준비 폴링 (m3-setup wait_repl 패턴 — -S -200 스크롤백 포함 필수).
for _i in $(seq 1 60); do
  sleep 2
  dump="$(tmux capture-pane -t "$DEV_PANE" -p -S -200 2>/dev/null)"
  printf '%s' "$dump" | grep -Eq 'trust this folder|Yes, I trust|accept the risk|bypass permissions and continue' && { tmux send-keys -t "$DEV_PANE" Enter; continue; }
  printf '%s' "$dump" | grep -qE 'Claude Code v[0-9]|Welcome back|bypass permissions on|accept edits on' && break
done
# boot 읽기 + task 지시 주입.
tmux send-keys -t "$DEV_PANE" -l "$DEV_BOOT 를 읽고 그 규약(특히 결과 출력 계약)을 그대로 따르라. 그다음 .agent-harness/tasks/T1.md 의 TASK T1 을 수행하라."
tmux send-keys -t "$DEV_PANE" Enter
echo "=== r5 셋업 완료 ===  세션 $SES  PROJECT_ROOT $PROJ"
echo "30~60초 뒤:  bash $ROOT/tests/role5axis/r5-score.sh"
