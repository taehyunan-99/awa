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

echo "[P3] 위험 문법 거부 (fail-fast)"
spec_parse_validate "$ROOT/tests/fixtures/team-anchor.yaml" 2>/dev/null
assert_fail "$?" "P3 yaml 앵커(&) 거부"
spec_parse_validate "$ROOT/tests/fixtures/team-flow.yaml" 2>/dev/null
assert_fail "$?" "P3 플로우([{) 거부"
spec_parse_validate "$ROOT/tests/fixtures/team-multiline.yaml" 2>/dev/null
assert_fail "$?" "P3 멀티라인(|) 거부"
echo "[P3b] 대괄호 경로는 정상 통과 (거짓양성 회귀 가드)"
spec_parse_validate "$ROOT/tests/fixtures/team-flowmap.yaml" 2>/dev/null
assert_fail "$?" "P3 인라인 flow map(- {) 거부"
spec_parse_validate "$ROOT/tests/fixtures/team-bracketpath.yaml" 2>/dev/null
assert_success "$?" "P3b plan 경로 내 대괄호 오탐 안 함"

echo "[P4] 정상 명세는 통과"
spec_parse_validate "$ROOT/tests/fixtures/team-basic.yaml" 2>/dev/null
assert_success "$?" "P4 정상 team-basic 통과"

echo "[P5] 리뷰어 불변식 — 투표 리뷰어≥1 이면 review-manager 필수"
spec_parse_invariants "$ROOT/tests/fixtures/team-mgrless.yaml" 2>/dev/null
assert_fail "$?" "P5 투표 리뷰어 있고 review-manager 없으면 거부"
spec_parse_invariants "$ROOT/tests/fixtures/team-basic.yaml" 2>/dev/null
assert_success "$?" "P5 투표+review-mgr 둘 다 있으면 통과"

echo "[P6] 무리뷰 팀(투표 0)은 통과 (research 류 정당)"
spec_parse_invariants "$ROOT/tests/fixtures/team-novote.yaml" 2>/dev/null
assert_success "$?" "P6 투표 리뷰어 0 통과"

echo "[P7-inv] 파일 미존재 거부"
spec_parse_invariants "/tmp/awa-nonexistent-$$.yaml" 2>/dev/null
assert_fail "$?" "P7-inv 파일 없으면 거부"

echo "[P8-inv] 대소문자 변형 role 도 투표 리뷰어로 인식 (거짓음성 방지)"
spec_parse_invariants "$ROOT/tests/fixtures/team-uc-rev.yaml" 2>/dev/null
assert_fail "$?" "P8-inv 대문자 role 도 voter 로 세고 mgr 없으면 거부"

test_summary
