#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
source ./harness-paths.sh
ROOT="$(cd .. && pwd)"
ORIG_PWD="$PWD"

# 서브셸 안에서 assert 를 부르면 _TESTS_RUN/_TESTS_FAIL 카운터가 부모로 전파되지 않아
# ran=0 위장 통과가 된다. 모든 케이스를 메인 셸에서 호출하고 cwd/env 는 명시 복원.

# T1.1 — HARNESS_PROJECT env 우선
unset HARNESS_PROJECT
TMP="$(mktemp -d)"
HARNESS_PROJECT="$TMP"
# shellcheck disable=SC1091
source "$HARNESS_BIN/lib.sh" 2>/dev/null
assert_eq "$TMP" "$PROJECT_ROOT" "HARNESS_PROJECT 우선"
assert_eq "$HARNESS" "$HARNESS_ROOT" "HARNESS_ROOT 는 bin/lib.sh 부모"
rm -rf "$TMP"
unset PROJECT_ROOT PROJECT_ROOT_VALID PROJECT_ROOT_IS_GIT HARNESS_PROJECT

# T1.2 — git repo 깊은 하위에서 toplevel 반환
# git -C "$PWD" 가 cwd 기반인지 검증 — deep/nested 에서 source 해도 toplevel 반환
G="$(mktemp -d)"
( cd "$G" && git init -q && mkdir -p deep/nested )
cd "$G/deep/nested"
# shellcheck disable=SC1091
source "$HARNESS_BIN/lib.sh" 2>/dev/null
# macOS mktemp 가 /var/folders/... 와 /private/var/folders/... 양쪽으로 해석되는 케이스 대응
pr_real="$(cd "$PROJECT_ROOT" && pwd -P)"
g_real="$(cd "$G" && pwd -P)"
assert_eq "$g_real" "$pr_real" "git toplevel 반환"
assert_eq "1" "$PROJECT_ROOT_IS_GIT" "git case → PROJECT_ROOT_IS_GIT=1"
cd "$ORIG_PWD"
rm -rf "$G"
unset PROJECT_ROOT PROJECT_ROOT_VALID PROJECT_ROOT_IS_GIT HARNESS_PROJECT

# T1.3 — git 아닌 디렉터리 → PWD 폴백 + stderr 경고
N="$(mktemp -d)"
cd "$N"
# stderr 와 PROJECT_ROOT 를 한 번의 source 로 동시 검증 (중복 source 제거).
# stderr 는 임시파일로 캡처, 본 셸의 PROJECT_ROOT 는 source 부수효과로 그대로 검사.
STDERR_FILE="$(mktemp)"
# shellcheck disable=SC1091
source "$HARNESS_BIN/lib.sh" 2>"$STDERR_FILE"
warn="$(cat "$STDERR_FILE")"
rm -f "$STDERR_FILE"
echo "$warn" | grep -q "git repo 아님"; assert_success "$?" "PWD 폴백 경고"
n_real="$(cd "$N" && pwd -P)"
pr_real="$(cd "$PROJECT_ROOT" && pwd -P)"
assert_eq "$n_real" "$pr_real" "PWD 폴백 값"
assert_eq "0" "$PROJECT_ROOT_IS_GIT" "non-git case → PROJECT_ROOT_IS_GIT=0"
cd "$ORIG_PWD"
rm -rf "$N"
unset PROJECT_ROOT PROJECT_ROOT_VALID PROJECT_ROOT_IS_GIT HARNESS_PROJECT

test_summary
