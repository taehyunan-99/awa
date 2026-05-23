#!/usr/bin/env bash
# e2e dry-run: AGENT_CMD=cat 더미로 team-up→상태검사→team-down 전 배선을 무해 검증.
#   실 claude 미기동(토큰 0·TCC 위험 0). 검증 대상:
#   - 세션/윈도우/페인 구성 (lead + 워커 + 리뷰어, window0/1, 인덱스 고정)
#   - pane title (LEAD·워커명·리뷰어명)
#   - settings.json marker 생성 + 워커별 .boot-settings/*.json 생성 + hook 공존
#   - boot 합본 파일 (.boot/*.md) 토큰 치환
#   - lead-auto-allow.yaml·state 디렉터리 설치
#   - team-down 정리 (런타임 산출물 제거, marker 제거)
set -uo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd)"
PROFILE="${1:-feature-team}"   # 가장 풍부한 편성 (워커3+리뷰어3)
PROJ="$(mktemp -d)"
( cd "$PROJ" && git init -q )

PASS=0; FAIL=0
chk() { if [ "$1" = "$2" ]; then echo "  ok: $3"; PASS=$((PASS+1)); else echo "  FAIL: $3 (exp=$1 got=$2)"; FAIL=$((FAIL+1)); fi; }
has() { if [ -e "$1" ]; then echo "  ok: $2"; PASS=$((PASS+1)); else echo "  FAIL: $2 (없음: $1)"; FAIL=$((FAIL+1)); fi; }

echo "=== dry-run: profile=$PROFILE  proj=$PROJ ==="

# team-up (더미 cat 엔진). REPL 폴링은 cat 분기라 sleep 0.2 만 — 빠름.
AGENT_CMD=cat bash bin/team-up.sh --project "$PROJ" "$PROFILE" 2>&1 | sed 's/^/  [up] /'

SES="$(HARNESS_PROJECT="$PROJ" bash -c 'source bin/lib.sh; resolve_session')"
echo "=== 세션=$SES ==="

# 1) 세션·윈도우·페인 구성
tmux has-session -t "$SES" 2>/dev/null && chk yes yes "세션 생성됨" || chk yes no "세션 생성"
WINS="$(tmux list-windows -t "$SES" -F '#{window_index}:#{window_name}' 2>/dev/null | tr '\n' ' ')"
echo "  windows: $WINS"
W0="$(tmux list-windows -t "$SES" -F '#{window_index}' 2>/dev/null | head -1)"
chk 0 "$W0" "window 인덱스 0 부터 (세션 로컬 고정)"

# feature-team: window0 = lead+워커3 = 4 pane, window1(review) = 리뷰어3 = 3 pane
P0="$(tmux list-panes -t "$SES:0" -F '#{pane_id}' 2>/dev/null | wc -l | tr -d ' ')"
P1="$(tmux list-panes -t "$SES:1" -F '#{pane_id}' 2>/dev/null | wc -l | tr -d ' ')"
echo "  window0 pane=$P0  window1 pane=$P1"
chk 4 "$P0" "window0 = lead + 워커3 = 4 pane"
chk 3 "$P1" "window1(review) = 리뷰어3 = 3 pane"

# 2) pane title (LEAD·워커명·리뷰어명)
TITLES="$(tmux list-panes -t "$SES:0" -F '#{pane_title}' 2>/dev/null | tr '\n' ',')$(tmux list-panes -t "$SES:1" -F '#{pane_title}' 2>/dev/null | tr '\n' ',')"
echo "  titles: $TITLES"
case "$TITLES" in *LEAD*) chk yes yes "LEAD title";; *) chk yes no "LEAD title";; esac
case "$TITLES" in *dev*)  chk yes yes "dev 워커 title";;  *) chk yes no "dev title";; esac
case "$TITLES" in *spec-rev*) chk yes yes "spec-rev 리뷰어 title";; *) chk yes no "spec-rev title";; esac

# 3) settings.json marker + 워커별 .boot-settings + hook 공존
has "$PROJ/.claude/settings.json" "settings.json 생성"
has "$PROJ/.claude/.agent-harness-marker" "marker 생성"
chk '{}' "$(tr -d ' \n' < "$PROJ/.claude/settings.json")" "settings.json 은 빈 {} (hook 워커 이관)"
has "$PROJ/.agent-harness/.boot-settings/dev.json" "워커 dev settings 사본"
has "$PROJ/.agent-harness/.boot-settings/LEAD.json" "LEAD settings 사본"
# 워커 settings 에 PreToolUse(permission-gate) + PostToolUse(log-event) 공존
DEVSET="$PROJ/.agent-harness/.boot-settings/dev.json"
pre="$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "$DEVSET" 2>/dev/null)"
post="$(jq -r '.hooks.PostToolUse[0].hooks[0].command' "$DEVSET" 2>/dev/null)"
case "$pre" in *permission-gate.sh*) chk yes yes "워커 PreToolUse=permission-gate";; *) chk yes no "PreToolUse";; esac
case "$post" in *log-event.sh*) chk yes yes "워커 PostToolUse=log-event";; *) chk yes no "PostToolUse";; esac
# LEAD 는 hook 없음 (게이트 대상 아님)
lhook="$(jq -r '.hooks // "none"' "$PROJ/.agent-harness/.boot-settings/LEAD.json" 2>/dev/null)"
chk none "$lhook" "LEAD 는 hook 없음"

# 4) boot 합본 토큰 치환
has "$PROJ/.agent-harness/.boot/dev.md" "워커 dev boot 합본"
has "$PROJ/.agent-harness/.boot/LEAD.md" "LEAD boot 합본"
if [ -f "$PROJ/.agent-harness/.boot/dev.md" ]; then
  grep -qE '\{\{(WORKER_NAME|SESSION|HARNESS_ROOT)\}\}' "$PROJ/.agent-harness/.boot/dev.md" \
    && chk no yes "dev boot 토큰 잔존(실패)" || chk yes yes "dev boot 토큰 전부 치환"
fi

# 5) config·state 설치
has "$PROJ/config/lead-auto-allow.yaml" "lead-auto-allow.yaml 설치"
has "$PROJ/.agent-harness/state/pending-asks" "state/pending-asks 디렉터리"

# 6) team-down 정리
echo "=== team-down ==="
bash bin/team-down.sh --project "$PROJ" 2>&1 | sed 's/^/  [down] /'
tmux has-session -t "$SES" 2>/dev/null && chk no yes "team-down 후 세션 잔존(실패)" || chk yes yes "team-down 세션 종료"
[ -f "$PROJ/.claude/settings.json" ] && chk no yes "settings.json 잔존(실패)" || chk yes yes "settings.json 정리"
[ -f "$PROJ/.claude/.agent-harness-marker" ] && chk no yes "marker 잔존(실패)" || chk yes yes "marker 정리"
[ -d "$PROJ/.agent-harness/.boot-settings" ] && chk no yes ".boot-settings 잔존(실패)" || chk yes yes ".boot-settings 정리"

# 정리
tmux kill-session -t "$SES" 2>/dev/null || true
rm -rf "$PROJ"
echo "---- e2e-dryrun PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
