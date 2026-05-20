#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"
ORIG_PWD="$PWD"

# 서브셸 안 assert 는 카운터 부모 전파 안 됨(T1 교훈). 모두 메인 셸 평탄 호출.
# 케이스 간 오염 차단: source 부수효과 변수와 env/cwd 명시 복원.

# T3.1 — 폴백: agents-<basename>
unset SESSION_OVERRIDE PROFILE_SESSION SESSION HARNESS_PROJECT 2>/dev/null || true
G_PARENT="$(mktemp -d)"
G="$G_PARENT/projectA"
mkdir -p "$G"
( cd "$G" && git init -q )
cd "$G"
# shellcheck disable=SC1091
source "$ROOT/bin/lib.sh" 2>/dev/null
assert_eq "agents-projectA" "$(resolve_session)" "자동명 폴백"
cd "$ORIG_PWD"
rm -rf "$G_PARENT"
unset PROJECT_ROOT PROJECT_ROOT_VALID PROJECT_ROOT_IS_GIT

# T3.2 — sanitize: . → _
unset SESSION_OVERRIDE PROFILE_SESSION SESSION HARNESS_PROJECT 2>/dev/null || true
G_PARENT="$(mktemp -d)"
G="$G_PARENT/proj.A-1"
mkdir -p "$G"
( cd "$G" && git init -q )
cd "$G"
# shellcheck disable=SC1091
source "$ROOT/bin/lib.sh" 2>/dev/null
assert_eq "agents-proj_A-1" "$(resolve_session)" "sanitize . → _"
cd "$ORIG_PWD"
rm -rf "$G_PARENT"
unset PROJECT_ROOT PROJECT_ROOT_VALID PROJECT_ROOT_IS_GIT

# T3.3 — SESSION_OVERRIDE/PROFILE_SESSION 우선
unset SESSION_OVERRIDE PROFILE_SESSION SESSION HARNESS_PROJECT 2>/dev/null || true
G_PARENT="$(mktemp -d)"
G="$G_PARENT/projectA"
mkdir -p "$G"
( cd "$G" && git init -q )
cd "$G"
# shellcheck disable=SC1091
source "$ROOT/bin/lib.sh" 2>/dev/null
export SESSION_OVERRIDE="custom_x"
assert_eq "custom_x" "$(resolve_session)" "resolve_session OVERRIDE 우선"
unset SESSION_OVERRIDE
export PROFILE_SESSION="profile_x"
assert_eq "profile_x" "$(resolve_session)" "resolve_session PROFILE_SESSION 우선"
unset PROFILE_SESSION
assert_eq "agents-projectA" "$(resolve_session)" "자동명 폴백"
cd "$ORIG_PWD"
rm -rf "$G_PARENT"
unset PROJECT_ROOT PROJECT_ROOT_VALID PROJECT_ROOT_IS_GIT

test_summary
