#!/usr/bin/env bash
# run-once.sh 의 wait_for_done 폴링 검증. 실 awa-up 없이 가짜 events.log 로.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/run-once.sh" --source-only   # 함수만 로드, main 실행 안 함

FAIL=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; FAIL=1; }

# 케이스 1: done 라인이 이미 있으면 즉시 0 반환
tmp1="$(mktemp)"
printf 'ts\tdev\tt1\ttask-start\tcycle=1\n' >> "$tmp1"
printf 'ts\tdev\tt1\tdone\t-\n' >> "$tmp1"
if wait_for_done "$tmp1" 2 1; then pass "done 존재 → 0"; else fail "done 존재인데 비0"; fi
rm -f "$tmp1"

# 케이스 2: done 없으면 타임아웃 후 비0
tmp2="$(mktemp)"
printf 'ts\tdev\tt1\ttask-start\tcycle=1\n' >> "$tmp2"
if wait_for_done "$tmp2" 2 1; then fail "done 없는데 0"; else pass "done 없음 → 타임아웃 비0"; fi
rm -f "$tmp2"

# 케이스 3: 파일 자체가 없으면 타임아웃 비0 (즉사 아님)
if wait_for_done "/tmp/__nonexist_$$__.log" 2 1; then fail "없는 파일인데 0"; else pass "없는 파일 → 비0"; fi

[ "$FAIL" = 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$FAIL"
