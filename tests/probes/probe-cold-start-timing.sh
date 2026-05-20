#!/usr/bin/env bash
# 수동 실측 probe: team-up 직후 4 pane 모두 REPL ready 까지 < 30초 검증.
# P2 spec §1 목표 4 의 실측 토대.
# run-all 비포함 (수동 실행).

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HARNESS_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

TMP_PROJ="$(mktemp -d -t p2-cold-start.XXXXXX)"
trap "bash '$HARNESS_ROOT/bin/team-down.sh' --project '$TMP_PROJ' 2>/dev/null || true; rm -rf '$TMP_PROJ'" EXIT

cd "$TMP_PROJ"
git init -q 2>/dev/null || true

echo "team-up 시작 — 측정 중..."
START="$(date +%s)"
HARNESS_PROJECT="$TMP_PROJ" bash "$HARNESS_ROOT/bin/team-up.sh" default >/tmp/p2-team-up.log 2>&1
RC=$?
END="$(date +%s)"
elapsed=$((END - START))

echo "team-up 종료 — exit=$RC, elapsed=${elapsed}s"
echo "로그 (마지막 20줄):"
tail -20 /tmp/p2-team-up.log

if [ "$elapsed" -lt 30 ] && [ "$RC" = "0" ]; then
  echo "PASS: 30초 안 부트 완료"
else
  echo "FAIL: 30초 초과 또는 exit 0 아님"
fi
