#!/usr/bin/env bash
# tests/test-review-manager-drift.sh — review-manager 드리프트 트리거 검증
# Layer 1: review-manager.md + reviewer plan_alignment + profiles + watcher drift-check
# Layer 2: worker_turn_count 함수 N=10 임계 동작
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

# Layer 1: review-manager.md 존재 + 책임 3층 명시
test -f "$ROOT/prompts/roles/03-quality/review-manager.md"
assert_success "$?" "L1 review-manager.md 존재"
grep -q '주 책임\|plan-diff 시계열' "$ROOT/prompts/roles/03-quality/review-manager.md"
assert_success "$?" "L1 review-manager 주 책임 명시"

# Layer 1: 개별 reviewer 4건 plan_alignment 출력 계약
ok=1
for f in "$ROOT"/prompts/roles/03-quality/reviewer-*.md; do
  grep -q 'plan_alignment' "$f" || ok=0
done
assert_eq "1" "$ok" "L1 reviewer 4건 plan_alignment 출력 계약"

# Layer 1: profiles/feature-team.sh review-manager 등록
grep -q 'review-mgr:review-manager:opus' "$ROOT/profiles/feature-team.sh"
assert_success "$?" "L1 profiles review-manager pane 등록"

# Layer 1: watcher.sh drift-check 트리거 + lib.sh worker_turn_count 함수
grep -q 'drift-check' "$ROOT/bin/watcher.sh"
assert_success "$?" "L1 watcher.sh drift-check 트리거"
grep -q 'worker_turn_count' "$ROOT/bin/lib.sh"
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
source "$ROOT/bin/lib.sh"
count=$(worker_turn_count "dev" "$EVENTS_LOG")
assert_eq "11" "$count" "L2 worker_turn_count dev = 11 (10턴 임계 초과)"

# 다른 worker 는 0
count=$(worker_turn_count "test" "$EVENTS_LOG")
assert_eq "0" "$count" "L2 worker_turn_count test = 0"

test_summary
