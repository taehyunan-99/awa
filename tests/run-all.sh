#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"

total_fail=0
for t in test-*.sh; do
  [ -e "$t" ] || continue
  echo "=== $t ==="
  bash "$t"
  rc=$?
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
