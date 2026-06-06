#!/usr/bin/env bash
# tests/test-review-manager-drift.sh — review-manager 드리프트 트리거 검증
# Layer 1: review-manager.md + reviewer plan_alignment + profiles + watcher drift-check
# Layer 2: worker_turn_count 함수 N=10 임계 동작
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
source ./harness-paths.sh
ROOT="$(cd .. && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

# Layer 1: review-manager.md 존재 + 책임 3층 명시
test -f "$HARNESS_PROMPTS/roles/03-quality/review-manager.md"
assert_success "$?" "L1 review-manager.md 존재"
grep -q '주 책임\|plan-diff 시계열' "$HARNESS_PROMPTS/roles/03-quality/review-manager.md"
assert_success "$?" "L1 review-manager 주 책임 명시"

# Layer 1: plan_alignment 렌즈 독립 — reviewer-alignment 전용 출력 계약
#   (reviewer-common 의 "plan_alignment 는 reviewer-alignment 전용" 불변식 검증.
#    grep 위양성 차단: 다른 리뷰어가 "출력하지 않는다"고 *언급*만 하는 건 허용하되,
#    실제 출력 지시(필드 필수/헤더 기록)는 alignment 만 가져야 한다.)
ALIGN="$HARNESS_PROMPTS/roles/03-quality/reviewer-alignment.md"
grep -qE 'plan_alignment: <0\.0~1\.0>.*필수' "$ALIGN"
assert_success "$?" "L1 reviewer-alignment 가 plan_alignment 출력 계약 보유"

# 나머지 리뷰어는 plan_alignment 출력을 *요구*하면 안 된다(렌즈 독립).
#   "출력하지 않는다" 부정 문장은 허용 → "필드 필수/헤더에 기록" 같은 출력 지시 패턴만 위반으로 본다.
leak=0
for f in "$HARNESS_PROMPTS"/roles/03-quality/reviewer-quality.md \
         "$HARNESS_PROMPTS"/roles/03-quality/reviewer-security.md \
         "$HARNESS_PROMPTS"/roles/03-quality/reviewer-alternative.md; do
  if grep -qE 'plan_alignment: <0\.0~1\.0>.*필수' "$f"; then leak=1; echo "  누출: $(basename "$f")"; fi
done
assert_eq "0" "$leak" "L1 quality/security/alternative 는 plan_alignment 출력 안 함(렌즈 독립)"

# Layer 1: profiles/default.yaml review-manager 등록 (yaml 파서로 로드)
source "$HARNESS_BIN/spec-parse.sh"
spec_parse_load "$HARNESS_PROFILES/default.yaml"
found_mgr=0
for entry in "${REVIEWERS[@]}"; do
  case "$entry" in *review-manager*) found_mgr=1 ;; esac
done
assert_eq "1" "$found_mgr" "L1 profiles default.yaml review-manager pane 등록"

# Layer 1: watcher.sh drift-check 트리거 + lib.sh worker_turn_count 함수
grep -q 'drift-check' "$HARNESS_BIN/watcher.sh"
assert_success "$?" "L1 watcher.sh drift-check 트리거"
grep -q 'worker_turn_count' "$HARNESS_BIN/lib.sh"
assert_success "$?" "L1 lib.sh worker_turn_count 함수"

# Layer 2: worker_turn_count 함수 N=10 동작 검증 (fake events.log)
EVENTS_LOG="$TMPDIR/events.log"
for i in 1 2 3 4 5 6 7 8 9 10 11; do
  printf '%s\t%s\t%s\t%s\t%s\n' \
    "2026-05-28T00:00:0${i}Z" "dev" "T${i}" "modify" "src/file${i}.md" \
    >> "$EVENTS_LOG"
done

# lib.sh source 후 worker_turn_count 호출
# shellcheck source=../bin/lib.sh
source "$HARNESS_BIN/lib.sh"
count=$(worker_turn_count "dev" "$EVENTS_LOG")
assert_eq "11" "$count" "L2 worker_turn_count dev = 11 (10턴 임계 초과)"

# 다른 worker 는 0
count=$(worker_turn_count "test" "$EVENTS_LOG")
assert_eq "0" "$count" "L2 worker_turn_count test = 0"

test_summary
