#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"

echo "[M1] --spec 가 launch 명령에 정확히 들어감"
OUT="$(bash "$ROOT/bin/awa-main.sh" launch --project "$ROOT" --mode-launch single --spec "$ROOT/profiles/default.yaml" 2>&1)"
assert_contains "$OUT" "--spec" "M1 launch 명령에 --spec 포함"
assert_contains "$OUT" "AGPN_META" "M1 AGPN_META 라인 출력"

echo "[M2] --spec 와 --preset 동시 거부"
OUT="$(bash "$ROOT/bin/awa-main.sh" launch --project "$ROOT" --mode-launch single --spec "$ROOT/profiles/default.yaml" --preset default 2>&1)"; RC=$?
assert_fail "$RC" "M2 spec+preset 동시 거부"

echo "[M3] --spec 와 --workers 동시 거부"
OUT="$(bash "$ROOT/bin/awa-main.sh" launch --project "$ROOT" --mode-launch single --spec "$ROOT/profiles/default.yaml" --workers "x:engineer" 2>&1)"; RC=$?
assert_fail "$RC" "M3 spec+workers 동시 거부"

echo "[M4] preset+workers 동시 거부 (--spec 무관 기존 가드 회귀)"
OUT="$(bash "$ROOT/bin/awa-main.sh" launch --project "$ROOT" --mode-launch single --preset default --workers "x:engineer" 2>&1)"; RC=$?
assert_fail "$RC" "M4 preset+workers 동시 거부"

echo "[M5] 셋 다 없음 거부"
OUT="$(bash "$ROOT/bin/awa-main.sh" launch --project "$ROOT" --mode-launch single 2>&1)"; RC=$?
assert_fail "$RC" "M5 preset/workers/spec 다 없으면 거부"

test_summary
