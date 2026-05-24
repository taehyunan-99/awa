#!/usr/bin/env bash
# 각 test-*.sh 는 마지막에 test_summary 를 호출해 종료코드로 통과/실패를 전달해야 한다.
# RUN_INTEGRATION=1 일 때 probes/ 의 통합 probe 도 실행 (claude 의존).
set -euo pipefail
cd "$(dirname "$0")"

total_fail=0
for t in test-*.sh; do
  [ -e "$t" ] || continue
  echo "=== $t ==="
  rc=0; bash "$t" || rc=$?
  [ "$rc" -ne 0 ] && total_fail=$((total_fail + 1))
done

# 5차: tests/unit/ 의 unit test 도 순회.
if [ -d unit ]; then
  for t in unit/test-*.sh; do
    [ -e "$t" ] || continue
    echo "=== $t ==="
    rc=0; bash "$t" || rc=$?
    [ "$rc" -ne 0 ] && total_fail=$((total_fail + 1))
  done
fi

# Integration — claude/tmux 의존, 느림. 명시적 opt-in.
# e2e-dryrun.sh 는 AGENT_CMD=cat 더미라 claude 토큰은 안 쓰나 실제 tmux 세션을 띄우므로
#   무조건 도는 test-*.sh 글롭이 아닌 여기(opt-in)에 둔다.
if [ "${RUN_INTEGRATION:-0}" = "1" ]; then
  for p in e2e-dryrun.sh \
           watcher-integration.sh \
           probes/probe-permission-gate.sh \
           probes/probe-matcher-and-reload.sh \
           probes/probe-hook-merge.sh; do
    [ -e "$p" ] || continue
    echo "=== $p (integration) ==="
    rc=0; bash "$p" || rc=$?
    [ "$rc" -ne 0 ] && total_fail=$((total_fail + 1))
  done
fi

echo "===================="
if [ "$total_fail" -eq 0 ]; then
  echo "ALL SUITES PASSED"
  exit 0
else
  echo "$total_fail SUITE(S) FAILED"
  exit 1
fi
