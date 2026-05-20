#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"
ORIG_PWD="$PWD"

# 서브셸 안 assert 는 카운터 부모 전파 안 됨(T1 교훈). 모두 메인 셸 평탄 호출.
# 케이스 간 오염 차단: source 부수효과 변수와 env/cwd 명시 복원.

# E1 — 같은 worker·task 라도 SESSION 다르면 채널명 다름 (멀티 프로젝트 동시 가동 시 신호 race 차단).

# projectA 채널명
unset SESSION_OVERRIDE PROFILE_SESSION SESSION HARNESS_PROJECT 2>/dev/null || true
PA_PARENT="$(mktemp -d)"
PA="$PA_PARENT/projectA"
mkdir -p "$PA"
( cd "$PA" && git init -q )
cd "$PA"
# shellcheck disable=SC1091
source "$ROOT/bin/lib.sh" 2>/dev/null
SESS_A="$(resolve_session)"
CH_A="done-$SESS_A-dev-T1"
assert_eq "done-agents-projectA-dev-T1" "$CH_A" "projectA 채널"
cd "$ORIG_PWD"
unset PROJECT_ROOT PROJECT_ROOT_VALID PROJECT_ROOT_IS_GIT

# projectB 채널명
unset SESSION_OVERRIDE PROFILE_SESSION SESSION HARNESS_PROJECT 2>/dev/null || true
PB_PARENT="$(mktemp -d)"
PB="$PB_PARENT/projectB"
mkdir -p "$PB"
( cd "$PB" && git init -q )
cd "$PB"
# shellcheck disable=SC1091
source "$ROOT/bin/lib.sh" 2>/dev/null
SESS_B="$(resolve_session)"
CH_B="done-$SESS_B-dev-T1"
assert_eq "done-agents-projectB-dev-T1" "$CH_B" "projectB 채널"
cd "$ORIG_PWD"
unset PROJECT_ROOT PROJECT_ROOT_VALID PROJECT_ROOT_IS_GIT

# 두 채널이 달라야 함
[ "$CH_A" != "$CH_B" ]; assert_success "$?" "두 SESSION 채널 다름"

rm -rf "$PA_PARENT" "$PB_PARENT"

# T9.bis — wait-worker.sh 의 CHANNEL 정의가 SESSION 포함하는지 정적 검증
grep -q 'CHANNEL="done-\$SESSION-\$WORKER-\$TASK_ID"' "$ROOT/bin/wait-worker.sh"
assert_success "$?" "wait-worker CHANNEL SESSION prefix 포함"

test_summary
