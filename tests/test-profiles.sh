#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"
source "$ROOT/bin/spec-parse.sh"

spec_parse_load "$ROOT/profiles/default.yaml"
assert_eq "tiled" "$LAYOUT" "default LAYOUT"
assert_eq "2" "${#WORKERS[@]}" "default 워커 2개"
assert_eq "engineer:engineer" "${WORKERS[0]}" "default 첫 워커"
assert_eq "4" "${#REVIEWERS[@]}" "default 리뷰어 4개(투표3+mgr)"
assert_contains "${REVIEWERS[*]}" "review-mgr:review-manager" "default review-manager 포함"
assert_contains "${REVIEWERS[*]}" "security-rev:reviewer-security:codex" "default security codex"

spec_parse_load "$ROOT/profiles/code-review.yaml"
assert_eq "1" "${#WORKERS[@]}" "code-review 워커 1개"
assert_contains "${WORKERS[*]}" "security:security" "code-review security"
assert_contains "${REVIEWERS[*]}" "review-mgr:review-manager" "code-review review-mgr 추가됨"

spec_parse_load "$ROOT/profiles/research.yaml"
assert_eq "3" "${#WORKERS[@]}" "research 워커 3개"
assert_contains "${REVIEWERS[*]}" "review-mgr:review-manager" "research review-mgr 추가됨"

spec_parse_load "$ROOT/profiles/web.yaml"
assert_eq "3" "${#WORKERS[@]}" "web 워커 3개"
assert_contains "${WORKERS[*]}" "frontend:frontend" "web frontend"

spec_parse_load "$ROOT/profiles/feature-team.yaml"
assert_eq "3" "${#WORKERS[@]}" "feature-team 워커 3개"

# 모든 profile 이 리뷰어 불변식 통과
for p in default web feature-team code-review research; do
  spec_parse_invariants "$ROOT/profiles/$p.yaml" 2>/dev/null
  assert_success "$?" "$p 리뷰어 불변식 통과"
done

test_summary
