#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"; source ../assert.sh
PROJ="${1:-$(cat /tmp/r5-last-proj 2>/dev/null || true)}"
R="$PROJ/.agent-harness/results/T1.md"
[ -f "$R" ] || { echo "오류: $R 없음 — dev 가 아직 results 미작성(대기 더) 또는 5축 미준수." >&2; exit 1; }
c="$(cat "$R")"
assert_contains "$c" "status:" "②헤더 status 존재"
echo "$c" | grep -qE '^status: (DONE|PARTIAL|BLOCKED)' && st=ok || st=ng
assert_eq "ok" "$st" "②status 값이 DONE|PARTIAL|BLOCKED"
assert_contains "$c" "EVIDENCE" "③EVIDENCE 섹션"
assert_contains "$c" "HYPOTHESIS" "③HYPOTHESIS 섹션"
echo "$c" | grep -qE '[0-9]+%' && pc=found || pc=none
assert_eq "none" "$pc" "③HYPOTHESIS 숫자% 없음(버킷)"
test_summary
