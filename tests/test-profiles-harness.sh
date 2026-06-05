#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
source ./harness-paths.sh
ROOT="$(cd .. && pwd)"
source "$HARNESS_BIN/spec-parse.sh"

# feature-team 프로파일: 형식 검증 (yaml 파서로 로드)
spec_parse_load "$HARNESS_PROFILES/feature-team.yaml"
[ "${#WORKERS[@]}" -ge 1 ] && out_w="W_OK" || out_w="W_FAIL"
[ "${#REVIEWERS[@]}" -ge 1 ] && out_r="R_OK" || out_r="R_FAIL"

assert_contains "$out_w" "W_OK" "WORKERS 정의됨"
assert_contains "$out_r" "R_OK" "REVIEWERS 정의됨"

# LEAD_MODEL 미하드코딩: yaml 로드 후 LEAD_MODEL 은 미설정
assert_eq "" "${LEAD_MODEL:-}" "LEAD_MODEL 미하드코딩(벤더 기본 위임)"

# 워커 엔트리에 역할 구분자(:) 존재
assert_contains "${WORKERS[0]}" ":" "워커 엔트리에 역할 구분자(:) 존재"

# 리뷰어 역할명은 reviewer-<관점> 형식
found_reviewer_prefix=0
for entry in "${REVIEWERS[@]}"; do
  case "$entry" in *:reviewer-*) found_reviewer_prefix=1 ;; esac
done
assert_eq "1" "$found_reviewer_prefix" "리뷰어 역할명이 reviewer-<관점> 형식"

# 워커 풀에 reviewer 역할 워커 없음 (감시 리뷰어로 일원화)
spec_parse_load "$HARNESS_PROFILES/default.yaml"
found_reviewer_worker=0
for entry in "${WORKERS[@]}"; do
  case "$entry" in *:reviewer) found_reviewer_worker=1 ;; esac
done
assert_eq "0" "$found_reviewer_worker" "default WORKERS 에 reviewer 워커 없음(일원화)"

test_summary
