#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
source ./harness-paths.sh
ROOT="$(cd .. && pwd)"
ORIG_PWD="$PWD"

# 평탄화: 서브셸 안 assert 는 카운터가 부모로 전파 안 됨 → ran=0 위장 통과.
# 메인 셸에서 cwd 저장 → cd → source → assert → cwd 복원, source 부수효과 변수 unset.

# T14.1 — 하니스가 repo 안 스킬 서브디렉토리로 이동한 뒤(harness/ 이동) PROJECT_ROOT 와
# HARNESS_ROOT 는 더 이상 동등하지 않다. cwd=HARNESS 에서 lib.sh 가 PROJECT_ROOT 를
# git toplevel(=호스트 repo 루트 $ROOT)로, HARNESS_ROOT 를 bin/lib.sh 부모(=$HARNESS)로
# 잡는다. 이동 전엔 하니스 자체가 git repo 라 둘이 같았으나, 이제 분리됨이 정상.
unset HARNESS_PROJECT
unset PROJECT_ROOT PROJECT_ROOT_VALID PROJECT_ROOT_IS_GIT HARNESS_ROOT WORKSPACE
cd "$HARNESS"
# shellcheck disable=SC1091
source "$HARNESS_BIN/lib.sh" 2>/dev/null
assert_eq "$ROOT" "$PROJECT_ROOT" "자기작업: PROJECT_ROOT = 호스트 repo 루트(git toplevel)"
assert_eq "$HARNESS" "$HARNESS_ROOT" "자기작업: HARNESS_ROOT = bin/lib.sh 부모(harness/)"

# T14.2 — WORKSPACE 는 항상 PROJECT_ROOT 안(산출물 격리 불변식). 이동 후엔 repo 루트 아래.
# (위 source 부수효과 WORKSPACE 그대로 검증, 중복 source 회피)
expected="$ROOT/.agent-harness"
assert_eq "$expected" "$WORKSPACE" "자기작업: WORKSPACE 가 PROJECT_ROOT 안"

cd "$ORIG_PWD"
unset PROJECT_ROOT PROJECT_ROOT_VALID PROJECT_ROOT_IS_GIT HARNESS_ROOT WORKSPACE

# T14.3 — .gitignore 에 .agent-harness/ 룰 (자기 repo 오염 차단)
grep -q '^\.agent-harness/$' "$ROOT/.gitignore"; assert_success "$?" ".gitignore .agent-harness/ 룰"

test_summary
