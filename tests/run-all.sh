#!/usr/bin/env bash
# 각 test-*.sh 는 마지막에 test_summary 를 호출해 종료코드로 통과/실패를 전달해야 한다.
set -euo pipefail
cd "$(dirname "$0")"

total_fail=0
for t in test-*.sh; do
  [ -e "$t" ] || continue
  echo "=== $t ==="
  rc=0; bash "$t" || rc=$?
  [ "$rc" -ne 0 ] && total_fail=$((total_fail + 1))
done

echo "===================="
if [ "$total_fail" -eq 0 ]; then
  echo "ALL SUITES PASSED"
  exit 0
else
  echo "$total_fail SUITE(S) FAILED"
  exit 1
fi
