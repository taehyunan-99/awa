#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
source ./harness-paths.sh
ROOT="$(cd .. && pwd)"
source "$HARNESS_BIN/spec-parse.sh"

spec_parse_load "$HARNESS_PROFILES/default.yaml"
assert_eq "tiled" "$LAYOUT" "default LAYOUT"
assert_eq "2" "${#WORKERS[@]}" "default 워커 2개"
assert_eq "engineer:engineer" "${WORKERS[0]}" "default 첫 워커"
assert_eq "4" "${#REVIEWERS[@]}" "default 리뷰어 4개(투표3+mgr)"
assert_contains "${REVIEWERS[*]}" "review-mgr:review-manager" "default review-manager 포함"
assert_contains "${REVIEWERS[*]}" "security-rev:reviewer-security:codex" "default security codex"

spec_parse_load "$HARNESS_PROFILES/web.yaml"
assert_eq "3" "${#WORKERS[@]}" "web 워커 3개"
assert_contains "${WORKERS[*]}" "frontend:frontend" "web frontend"

# 모든 profile 이 리뷰어 불변식 통과
for p in default web; do
  spec_parse_invariants "$HARNESS_PROFILES/$p.yaml" 2>/dev/null
  assert_success "$?" "$p 리뷰어 불변식 통과"
done

test_summary
