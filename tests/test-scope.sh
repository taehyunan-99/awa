#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"
source "$ROOT/bin/lib.sh"

# scope_match <path> <pattern> → 0(매치)/1(불일치)
scope_match "src/auth/login.ts" "src/auth/**"; assert_success "$?" "** 재귀 매치"
scope_match "src/auth/sub/x.ts"  "src/auth/**"; assert_success "$?" "** 다단계 매치"
scope_match "src/auth/login.ts" "src/*/login.ts"; assert_success "$?" "* 단일 세그먼트 매치"

scope_match "src/payment/x.ts"  "src/auth/**"; assert_fail "$?" "다른 디렉터리 불일치"
scope_match "src/authx/y.ts"    "src/auth/**"; assert_fail "$?" "경계 오매치 방지 (authx≠auth)"
scope_match "src/auth/a/b.ts"   "src/auth/*";  assert_fail "$?" "* 는 / 안 넘음 (a/b 불일치)"

test_summary
