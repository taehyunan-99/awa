#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"
source "$ROOT/bin/spec-parse.sh"

echo "[P1] 평면 평탄화 — workers/reviewers TSV"
OUT="$(spec_parse_flatten "$ROOT/tests/fixtures/team-basic.yaml")"
assert_contains "$OUT" "worker	engineer	engineer	claude	sonnet" "P1 worker engineer 행"
assert_contains "$OUT" "worker	researcher	researcher		" "P1 worker researcher (vendor/model 빈칸)"
assert_contains "$OUT" "reviewer	security-rev	reviewer-security	codex	" "P1 reviewer security codex"
assert_contains "$OUT" "reviewer	review-mgr	review-manager		" "P1 reviewer review-mgr"

echo "[P2] 스칼라 키 추출"
assert_eq "my-feature" "$(spec_parse_scalar "$ROOT/tests/fixtures/team-basic.yaml" session)" "P2 session"
assert_eq "tiled" "$(spec_parse_scalar "$ROOT/tests/fixtures/team-basic.yaml" layout)" "P2 layout"
assert_eq "docs/superpowers/plans/foo.md" "$(spec_parse_scalar "$ROOT/tests/fixtures/team-basic.yaml" plan)" "P2 plan"

test_summary
