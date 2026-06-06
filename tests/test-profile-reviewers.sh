#!/usr/bin/env bash
# tests/test-profile-reviewers.sh — default.yaml REVIEWERS 배열 정합 검증
# Layer 1: REVIEWERS 배열 4개 토큰 (review-manager 포함) 존재
# Layer 2: bin/awa-up.sh 가 REVIEWERS 토큰을 pane 배정 함수에 전달하는지 grep
# Layer 2: REVIEW_MANAGER_PANE env 주입/사용 검증 (I-3 정정 후 호환성)
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
source ./harness-paths.sh
ROOT="$(cd .. && pwd)"
source "$HARNESS_BIN/spec-parse.sh"

echo "test-profile-reviewers.sh"

# Layer 1: REVIEWERS 배열 4개 토큰 (yaml 파서로 로드)
spec_parse_load "$HARNESS_PROFILES/default.yaml"

assert_contains "${REVIEWERS[*]}" "alignment-rev:reviewer-alignment" "L1 alignment-rev 토큰"
assert_contains "${REVIEWERS[*]}" "quality-rev:reviewer-quality" "L1 quality-rev 토큰"
assert_contains "${REVIEWERS[*]}" "security-rev:reviewer-security" "L1 security-rev 토큰"
assert_contains "${REVIEWERS[*]}" "review-mgr:review-manager" "L1 review-mgr 토큰"

# Layer 2: awa-up.sh 가 REVIEWERS 배열을 처리하는지
grep -q 'REVIEWERS' "$HARNESS_BIN/awa-up.sh"
assert_success "$?" "L2 awa-up.sh REVIEWERS 처리"

# Layer 2: REVIEW_MANAGER_PANE env 주입 (I-3 정정 후)
grep -q 'REVIEW_MANAGER_PANE' "$HARNESS_BIN/awa-up.sh"
assert_success "$?" "L2 awa-up.sh REVIEW_MANAGER_PANE 주입"

# Layer 2: watcher.sh REVIEW_MANAGER_PANE env 사용 (I-3 정정)
grep -q 'REVIEW_MANAGER_PANE' "$HARNESS_BIN/watcher.sh"
assert_success "$?" "L2 watcher.sh REVIEW_MANAGER_PANE 사용"

test_summary
