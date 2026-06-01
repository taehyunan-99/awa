#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh

ROOT="$(cd .. && pwd)"
export SESSION_OVERRIDE="e2e_$$"
# 워커 페인에서 더미 워커 실행 (engineer 워커만 검증 대상; 나머지도 같은 더미)
export AGENT_CMD="bash $ROOT/tests/dummy-worker.sh engineer $SESSION_OVERRIDE"

# T12: PROJECT_ROOT 분리 후 임시 git repo 를 PROJECT_ROOT 로 사용
TMP_PROJ="$(mktemp -d)"; ( cd "$TMP_PROJ" && git init -q )
export HARNESS_PROJECT="$TMP_PROJ"

# 15th: bookmarks 격리 — awa-up.sh 가 ~/.config/awa/bookmarks.tsv 에 기록.
# 테스트 fixture 가 사용자 실 경로를 더럽히지 않도록 임시 dir 로 redirect.
_AGPN15_XDG="$(mktemp -d)"
export XDG_CONFIG_HOME="$_AGPN15_XDG"

cleanup() {
  tmux kill-session -t "$SESSION_OVERRIDE" 2>/dev/null || true
  [ -n "${TMP_PROJ:-}" ] && rm -rf "$TMP_PROJ"
  [ -n "${_AGPN15_XDG:-}" ] && rm -rf "$_AGPN15_XDG"
}
trap cleanup EXIT

bash "$ROOT/bin/awa-up.sh" default >/dev/null
sleep 0.5

# 작업 파일 작성
echo "# E1: E2E 더미 작업" > "$TMP_PROJ/.agent-harness/tasks/E1.md"

# dispatch → wait → 결과 확인
SESSION_OVERRIDE="$SESSION_OVERRIDE" bash "$ROOT/bin/dispatch.sh" engineer E1
assert_eq "0" "$?" "E2E dispatch 성공"

# P11 탈-tmux: dummy-worker 는 더 이상 wait-for -S 를 보내지 않고 events.log 에 done 라인을
# append 한다(워커 tmux 직접호출 0 규약). 완료를 events.log done 라인 폴링으로 확인(최대 ~5s).
EV="$TMP_PROJ/.agent-harness/events.log"
for _i in $(seq 1 50); do
  grep -q $'\tdone\t' "$EV" 2>/dev/null && break
  sleep 0.1
done

[ -f "$TMP_PROJ/.agent-harness/results/E1.md" ]; assert_eq "0" "$?" "결과 파일 생성됨"
RES="$(cat "$TMP_PROJ/.agent-harness/results/E1.md")"
assert_contains "$RES" "상태: SUCCESS" "결과에 SUCCESS"
assert_contains "$RES" "워커: engineer" "결과에 워커명"

test_summary
