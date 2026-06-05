#!/usr/bin/env bash
# run_with_timeout: macOS(timeout 부재)에서도 동작. 자연완료=0, timeout=124.
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
source ./harness-paths.sh
ROOT="$(cd .. && pwd)"
export HARNESS_PROJECT="$(mktemp -d)"
( cd "$HARNESS_PROJECT" && git init -q )
# shellcheck disable=SC1091
source "$HARNESS_BIN/lib.sh"

echo "[RT1] 즉시 끝나는 명령 → rc 0"
run_with_timeout 5 true; assert_success "$?" "RT1 자연완료 rc0"

echo "[RT2] timeout 보다 오래 걸리는 명령 → rc 124"
rc=0; run_with_timeout 1 sleep 5 || rc=$?
assert_eq "124" "$rc" "RT2 timeout rc124"

echo "[RT3] 1초 timeout 이 실제 ~1초만에 끝남 (5초 대기 안 함)"
t0=$(date +%s); run_with_timeout 1 sleep 10 >/dev/null 2>&1 || true; t1=$(date +%s)
[ $((t1 - t0)) -le 3 ]; assert_success "$?" "RT3 신속 종료 ($((t1-t0))s)"

test_summary
