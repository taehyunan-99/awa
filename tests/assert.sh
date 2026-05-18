#!/usr/bin/env bash
# 의존성 zero 테스트 어서션. 각 test-*.sh 가 source 한다.

_TESTS_RUN=0
_TESTS_FAIL=0

assert_eq() {
  local expected="$1" actual="$2" msg="${3:-}"
  _TESTS_RUN=$((_TESTS_RUN + 1))
  if [ "$expected" = "$actual" ]; then
    echo "  ok: ${msg:-assert_eq}"
  else
    _TESTS_FAIL=$((_TESTS_FAIL + 1))
    echo "  FAIL: ${msg:-assert_eq}"
    echo "    expected: [$expected]"
    echo "    actual:   [$actual]"
  fi
}

assert_contains() {
  local haystack="$1" needle="$2" msg="${3:-}"
  _TESTS_RUN=$((_TESTS_RUN + 1))
  if printf '%s' "$haystack" | grep -qF -- "$needle"; then
    echo "  ok: ${msg:-assert_contains}"
  else
    _TESTS_FAIL=$((_TESTS_FAIL + 1))
    echo "  FAIL: ${msg:-assert_contains}"
    echo "    needle [$needle] not found in:"
    echo "    [$haystack]"
  fi
}

assert_success() {
  # 직전 명령이 성공(0)했어야 함. 호출자가 $? 를 인자로 넘긴다: assert_success "$?" "메시지"
  local rc="$1" msg="${2:-assert_success}"
  _TESTS_RUN=$((_TESTS_RUN + 1))
  if [ "$rc" -eq 0 ]; then
    echo "  ok: $msg"
  else
    _TESTS_FAIL=$((_TESTS_FAIL + 1))
    echo "  FAIL: $msg (expected zero exit, got $rc)"
  fi
}

assert_fail() {
  # 직전 명령이 실패(비-0)했어야 함
  local rc="$1" msg="${2:-assert_fail}"
  _TESTS_RUN=$((_TESTS_RUN + 1))
  if [ "$rc" -ne 0 ]; then
    echo "  ok: $msg"
  else
    _TESTS_FAIL=$((_TESTS_FAIL + 1))
    echo "  FAIL: $msg (expected non-zero exit, got 0)"
  fi
}

test_summary() {
  echo "----"
  echo "ran=$_TESTS_RUN fail=$_TESTS_FAIL"
  [ "$_TESTS_FAIL" -eq 0 ]
}
