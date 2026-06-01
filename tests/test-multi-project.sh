#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"

TMP1="$(mktemp -d)/projectA"; mkdir -p "$TMP1" && ( cd "$TMP1" && git init -q )
TMP2="$(mktemp -d)/projectB"; mkdir -p "$TMP2" && ( cd "$TMP2" && git init -q )

# 15th: bookmarks 격리 — awa-up.sh 가 ~/.config/awa/bookmarks.tsv 에 기록.
# 테스트 fixture 가 사용자 실 경로를 더럽히지 않도록 임시 dir 로 redirect.
_AGPN15_XDG="$(mktemp -d)"
export XDG_CONFIG_HOME="$_AGPN15_XDG"

trap '
  tmux kill-session -t "awa-projectA" 2>/dev/null
  tmux kill-session -t "awa-projectB" 2>/dev/null
  rm -rf "$(dirname "$TMP1")" "$(dirname "$TMP2")"
  rm -rf "$_AGPN15_XDG"
' EXIT

# A·B 동시 가동
HARNESS_PROJECT="$TMP1" AGENT_CMD=cat bash "$ROOT/bin/awa-up.sh" default >/dev/null 2>&1
sleep 0.3
HARNESS_PROJECT="$TMP2" AGENT_CMD=cat bash "$ROOT/bin/awa-up.sh" default >/dev/null 2>&1
sleep 0.3

# T16.1 — 두 SESSION 공존
tmux has-session -t awa-projectA 2>/dev/null; assert_success "$?" "awa-projectA 살아있음"
tmux has-session -t awa-projectB 2>/dev/null; assert_success "$?" "awa-projectB 살아있음"

# T16.2 — 두 .agent-harness/ 격리
[ -d "$TMP1/.agent-harness" ]; assert_success "$?" "A 의 .agent-harness/"
[ -d "$TMP2/.agent-harness" ]; assert_success "$?" "B 의 .agent-harness/"

# T16.3 — 두 워커 settings 각자 PROJECT_ROOT 박힘 (격리).
# 6차: project .claude/settings.json 은 빈 {} 로 이관 — 경로는 워커 --settings 에 박힘.
A_DEV="$TMP1/.agent-harness/.boot-settings/engineer.json"
B_DEV="$TMP2/.agent-harness/.boot-settings/engineer.json"
grep -q "$TMP1" "$A_DEV"; assert_success "$?" "A 워커 settings 에 A 경로"
grep -q "$TMP2" "$B_DEV"; assert_success "$?" "B 워커 settings 에 B 경로"
! grep -q "$TMP2" "$A_DEV" 2>/dev/null; assert_success "$?" "A 워커 settings 에 B 경로 없음"

# T16.4 — 같은 task id `1.md` 도 격리
echo "## A task" > "$TMP1/.agent-harness/tasks/1.md"
echo "## B task" > "$TMP2/.agent-harness/tasks/1.md"
grep -q "A task" "$TMP1/.agent-harness/tasks/1.md"; assert_success "$?" "A task 1.md"
grep -q "B task" "$TMP2/.agent-harness/tasks/1.md"; assert_success "$?" "B task 1.md"

# T16.5 — A awa-down 이 B 영향 없음
HARNESS_PROJECT="$TMP1" bash "$ROOT/bin/awa-down.sh" >/dev/null 2>&1
sleep 0.3
! tmux has-session -t awa-projectA 2>/dev/null; assert_success "$?" "A 세션 종료됨"
tmux has-session -t awa-projectB 2>/dev/null; assert_success "$?" "B 세션 여전히 살아있음"
[ -d "$TMP2/.agent-harness" ]; assert_success "$?" "B .agent-harness/ 여전히"

# T16.6 — B 도 정리
HARNESS_PROJECT="$TMP2" bash "$ROOT/bin/awa-down.sh" >/dev/null 2>&1
sleep 0.3
! tmux has-session -t awa-projectB 2>/dev/null; assert_success "$?" "B 세션 종료됨"

test_summary
