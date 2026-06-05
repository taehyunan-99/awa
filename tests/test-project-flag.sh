#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
source ./harness-paths.sh
ROOT="$(cd .. && pwd)"
ORIG_PWD="$PWD"

# 서브셸 안 assert 는 카운터 부모 전파 안 됨(T1 교훈). 모두 메인 셸 평탄 호출.
# set -e 호출 금지(파일 상단에 -e 없음, T2 교훈).

# T4.1 — _normalize_project: 상대경로 → 절대경로 정규화
TMP="$(mktemp -d)"
trap 'cd "$ORIG_PWD"; rm -rf "$TMP"' EXIT
mkdir -p "$TMP/projectA"
unset HARNESS_PROJECT PROJECT_ROOT PROJECT_ROOT_VALID PROJECT_ROOT_IS_GIT 2>/dev/null || true
# shellcheck disable=SC1091
source "$HARNESS_BIN/lib.sh" 2>/dev/null

cd "$TMP"
result="$(_normalize_project "projectA")"
expected="$TMP/projectA"
result_real="$(cd "$result" && pwd -P)"
expected_real="$(cd "$expected" && pwd -P)"
cd "$ORIG_PWD"
assert_eq "$expected_real" "$result_real" "상대→절대 정규화"

# T4.2 — 존재하지 않는 경로 → return 1·stderr "경로 없음"
out="$(_normalize_project "/no/such/path" 2>&1 >/dev/null)"
rc=$?
assert_eq "1" "$rc" "bad path → return 1"
echo "$out" | grep -q "경로 없음"
assert_success "$?" "bad path stderr 경로 없음"

# T4.3 — 빈 인자도 안전하게 return 1 (set -u 보호)
out="$(_normalize_project "" 2>&1 >/dev/null)"
rc=$?
assert_eq "1" "$rc" "빈 인자 → return 1"

test_summary
