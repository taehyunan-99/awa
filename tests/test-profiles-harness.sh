#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"

# feature-team 프로파일: 형식 검증
( source "$ROOT/profiles/feature-team.sh"
  [ "${#WORKERS[@]}" -ge 1 ] && echo "W_OK"
  [ "${#REVIEWERS[@]}" -ge 1 ] && echo "R_OK"
  printf 'LEAD=%s\n' "$LEAD_MODEL"
  printf 'W0=%s\n' "${WORKERS[0]}"
) > /tmp/prof_out_$$ 2>&1
out="$(cat /tmp/prof_out_$$)"; rm -f /tmp/prof_out_$$
assert_contains "$out" "W_OK" "WORKERS 정의됨"
assert_contains "$out" "R_OK" "REVIEWERS 정의됨"
assert_contains "$out" "LEAD=" "LEAD_MODEL 정의됨"
assert_contains "$out" ":" "워커 엔트리에 역할 구분자(:) 존재"

# 리뷰어 역할명은 reviewer-<관점> 형식
( source "$ROOT/profiles/feature-team.sh"; printf '%s\n' "${REVIEWERS[@]}" ) > /tmp/rev_$$ 2>&1
revout="$(cat /tmp/rev_$$)"; rm -f /tmp/rev_$$
assert_contains "$revout" "reviewer-" "리뷰어 역할명이 reviewer-<관점> 형식"

# 워커 풀에 reviewer 역할 워커 없음 (감시 리뷰어로 일원화)
( source "$ROOT/profiles/default.sh"; printf '%s\n' "${WORKERS[@]}" ) > /tmp/w_$$ 2>&1
wout="$(cat /tmp/w_$$)"; rm -f /tmp/w_$$
if printf '%s' "$wout" | grep -q ':reviewer$'; then
  assert_eq "no-reviewer-worker" "found-reviewer-worker" "default WORKERS 에 reviewer 워커 없어야 함"
else
  assert_eq "ok" "ok" "default WORKERS 에 reviewer 워커 없음(일원화)"
fi

test_summary
