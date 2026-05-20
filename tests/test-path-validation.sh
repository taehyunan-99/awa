#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"
ORIG_PWD="$PWD"

# 서브셸 안 assert 는 카운터 부모 전파 안 됨(T1 교훈). 모두 메인 셸 평탄 호출.
# 케이스 간 오염 차단: source 부수효과 변수와 env/cwd 명시 복원.

# T2.1 — 영숫자·/._- 만 포함된 경로 → PROJECT_ROOT_VALID=1
unset HARNESS_PROJECT
G="$(mktemp -d)"
( cd "$G" && git init -q )
cd "$G"
# shellcheck disable=SC1091
source "$ROOT/bin/lib.sh" 2>/dev/null
assert_eq "1" "$PROJECT_ROOT_VALID" "정상 경로 VALID=1"
cd "$ORIG_PWD"
rm -rf "$G"
unset PROJECT_ROOT PROJECT_ROOT_VALID PROJECT_ROOT_IS_GIT

# T2.2 — 공백 포함 → VALID=0, source 자체는 죽지 않음(F1: exit 금지)
B_PARENT="$(mktemp -d)"
B="$B_PARENT/has space"
mkdir -p "$B"
cd "$B"
set +e
# shellcheck disable=SC1091
source "$ROOT/bin/lib.sh" 2>/dev/null
rc=$?
set -e
assert_eq "0" "$rc" "source 자체는 exit 0 (F1)"
assert_eq "0" "$PROJECT_ROOT_VALID" "공백 포함 VALID=0"
cd "$ORIG_PWD"
rm -rf "$B_PARENT"
unset PROJECT_ROOT PROJECT_ROOT_VALID PROJECT_ROOT_IS_GIT

# T2.3 — `#` 포함 → VALID=0
H_PARENT="$(mktemp -d)"
H="$H_PARENT/has#hash"
mkdir -p "$H"
cd "$H"
# shellcheck disable=SC1091
source "$ROOT/bin/lib.sh" 2>/dev/null
assert_eq "0" "$PROJECT_ROOT_VALID" "# 포함 VALID=0"
cd "$ORIG_PWD"
rm -rf "$H_PARENT"
unset PROJECT_ROOT PROJECT_ROOT_VALID PROJECT_ROOT_IS_GIT

test_summary
