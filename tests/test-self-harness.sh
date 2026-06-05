#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
source ./harness-paths.sh
ROOT="$(cd .. && pwd)"
ORIG_PWD="$PWD"

# 평탄화: 서브셸 안 assert 는 카운터가 부모로 전파 안 됨 → ran=0 위장 통과.
# 메인 셸에서 cwd 저장 → cd → source → assert → cwd 복원, source 부수효과 변수 unset.

# T14.1 — cwd=HARNESS_ROOT 면 PROJECT_ROOT == HARNESS_ROOT (자기작업 대칭성)
unset HARNESS_PROJECT
unset PROJECT_ROOT PROJECT_ROOT_VALID PROJECT_ROOT_IS_GIT HARNESS_ROOT WORKSPACE
cd "$HARNESS"
# shellcheck disable=SC1091
source "$HARNESS_BIN/lib.sh" 2>/dev/null
assert_eq "$HARNESS_ROOT" "$PROJECT_ROOT" "자기작업: 두 변수 동등"
assert_eq "$HARNESS" "$PROJECT_ROOT" "자기작업: 값은 harness repo"

# T14.2 — 자기작업 시 .agent-harness/ 가 HARNESS_ROOT 안에 위치
# (위 source 부수효과 WORKSPACE 그대로 검증, 중복 source 회피)
expected="$HARNESS/.agent-harness"
assert_eq "$expected" "$WORKSPACE" "자기작업: WORKSPACE 가 HARNESS_ROOT 안"

cd "$ORIG_PWD"
unset PROJECT_ROOT PROJECT_ROOT_VALID PROJECT_ROOT_IS_GIT HARNESS_ROOT WORKSPACE

# T14.3 — .gitignore 에 .agent-harness/ 룰 (자기 repo 오염 차단)
grep -q '^\.agent-harness/$' "$ROOT/.gitignore"; assert_success "$?" ".gitignore .agent-harness/ 룰"

test_summary
