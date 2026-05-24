#!/usr/bin/env bash
# prefix_match 단어경계 + matrix_lookup/lead_auto_allow_lookup 통합 검증.
# claude 의 Bash(prefix:*) 단어경계 의미론(공식문서+probe 실측 확정)과 일치.
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"
# shellcheck disable=SC1091
source "$ROOT/bin/lib.sh"
# shellcheck disable=SC1091
source "$ROOT/bin/matrix-lookup.sh"

echo "[P1] prefix_match 매칭 (끝/공백 경계)"
prefix_match "git add" "git add";    assert_success "$?" "P1 정확일치(끝)"
prefix_match "git add" "git add .";  assert_success "$?" "P1 공백+인자"
prefix_match "git add" "git add -A"; assert_success "$?" "P1 공백+플래그"
prefix_match "echo" "echo";          assert_success "$?" "P1 단일토큰 끝"
prefix_match "echo" "echo hi";       assert_success "$?" "P1 단일토큰 공백"

echo "[P2] prefix_match 비매칭 (단어경계 위반)"
prefix_match "git add" "git addfoo";  assert_fail "$?" "P2 glued 차단"
prefix_match "git add" "git add-foo"; assert_fail "$?" "P2 hyphen 차단"
prefix_match "git add" "git ad";      assert_fail "$?" "P2 부분 차단"
prefix_match "echo" "echofoo";        assert_fail "$?" "P2 단일토큰 glued 차단"

echo "[P3] prefix_match 방어 (빈 값 + glob 메타 리터럴)"
prefix_match "" "anything"; assert_fail "$?" "P3 빈 prefix → 비매칭"
prefix_match "x" "";        assert_fail "$?" "P3 빈 field → 비매칭"
prefix_match "a.b" "a.b c"; assert_success "$?" "P3 glob메타(.) 리터럴 매칭"
prefix_match "a.b" "axb c"; assert_fail "$?" "P3 glob메타(.) 오매칭 안 함"

test_summary
