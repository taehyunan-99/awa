#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh

ROOT="$(cd .. && pwd)"
export SESSION_OVERRIDE="tu_$$"
# 워커 페인은 claude 대신 'cat' 더미 실행 (입력 대기만)
export AGENT_CMD="cat"

cleanup() { tmux kill-session -t "$SESSION_OVERRIDE" 2>/dev/null || true; rm -rf "$ROOT/workspace/.boot"; }
trap cleanup EXIT

# 1) 정상 생성
bash "$ROOT/bin/team-up.sh" default
rc=$?
assert_eq "0" "$rc" "team-up default 성공 종료"

# 세션 존재
tmux has-session -t "$SESSION_OVERRIDE" 2>/dev/null
assert_eq "0" "$?" "세션 생성됨"

# 페인 4개 (오케1 + 워커3)
N="$(tmux list-panes -t "$SESSION_OVERRIDE:0" | wc -l | tr -d ' ')"
assert_eq "4" "$N" "페인 4개"

# 부트스트랩 파일이 워커별로 생성되고 치환됨
assert_eq "0" "$([ -f "$ROOT/workspace/.boot/dev.md" ] && echo 0 || echo 1)" "dev.md boot 생성"
BOOT="$(cat "$ROOT/workspace/.boot/dev.md")"
assert_contains "$BOOT" "워커 이름: dev" "{{WORKER_NAME}} → dev 치환됨"
assert_contains "$BOOT" "done-dev-" "신호 채널명 치환됨"
assert_contains "$BOOT" "역할: 개발자" "역할 프롬프트 합쳐짐"
if printf '%s' "$BOOT" | grep -qF '{{WORKER_NAME}}'; then r=0; else r=1; fi
assert_eq "1" "$r" "미치환 토큰 없음"

# 2) 중복 실행 거부
bash "$ROOT/bin/team-up.sh" default
assert_fail "$?" "기존 세션 존재 시 중복 생성 거부"

cleanup
trap - EXIT

# 3) 없는 프로파일 → 실패
bash "$ROOT/bin/team-up.sh" nonexistent_profile
assert_fail "$?" "없는 프로파일 → 실패"
tmux kill-session -t "$SESSION_OVERRIDE" 2>/dev/null || true

test_summary
