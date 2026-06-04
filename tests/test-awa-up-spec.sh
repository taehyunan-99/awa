#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"

echo "[S1] --spec 가 team.yaml 파싱·검증 통과 (dry-check)"
OUT="$(AGENT_CMD=cat bash "$ROOT/bin/awa-up.sh" --project "$ROOT" --spec "$ROOT/tests/fixtures/team-basic.yaml" --dry-check 2>&1)"; RC=$?
assert_success "$RC" "S1 --spec dry-check 성공"
assert_contains "$OUT" "dry-check" "S1 dry-check 출력"

echo "[S2] --spec 와 profile 동시 지정 거부"
OUT="$(AGENT_CMD=cat bash "$ROOT/bin/awa-up.sh" --project "$ROOT" --spec "$ROOT/tests/fixtures/team-basic.yaml" default --dry-check 2>&1)"; RC=$?
assert_fail "$RC" "S2 --spec + profile 동시 거부"

echo "[S3] --spec 의 불변식 위반 yaml 거부 (team-mgrless)"
OUT="$(AGENT_CMD=cat bash "$ROOT/bin/awa-up.sh" --project "$ROOT" --spec "$ROOT/tests/fixtures/team-mgrless.yaml" --dry-check 2>&1)"; RC=$?
assert_fail "$RC" "S3 불변식 위반 yaml 거부"

echo "[S4] --spec 와 --workers 동시 지정 거부"
OUT="$(AGENT_CMD=cat bash "$ROOT/bin/awa-up.sh" --project "$ROOT" --spec "$ROOT/tests/fixtures/team-basic.yaml" --workers "x:engineer" --dry-check 2>&1)"; RC=$?
assert_fail "$RC" "S4 --spec + --workers 동시 거부"

test_summary
