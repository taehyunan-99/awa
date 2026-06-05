#!/usr/bin/env bash
# 테스트 공통 경로 헬퍼 — harness 위치를 단일 출처로 제공
set -u
cd "$(dirname "$0")"
source ./assert.sh
source ./harness-paths.sh

# H1 — HARNESS 가 실제 bin/lib.sh 를 포함하는 디렉토리
assert_eq "1" "$([ -f "$HARNESS/bin/lib.sh" ] && echo 1 || echo 0)" "H1 HARNESS/bin/lib.sh 존재"
# H2 — 파생 변수 정합
assert_eq "$HARNESS/bin" "$HARNESS_BIN" "H2 HARNESS_BIN"
assert_eq "$HARNESS/profiles" "$HARNESS_PROFILES" "H3 HARNESS_PROFILES"
assert_eq "$HARNESS/prompts" "$HARNESS_PROMPTS" "H4 HARNESS_PROMPTS"
assert_eq "$HARNESS/templates" "$HARNESS_TEMPLATES" "H5 HARNESS_TEMPLATES"
assert_eq "$HARNESS/config" "$HARNESS_CONFIG" "H6 HARNESS_CONFIG"
test_summary
