#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh

ROOT="$(cd .. && pwd)"

DUMP="$(bash -c 'source '"$ROOT"'/profiles/default.sh
  printf "WORKER\t%s\n" "${WORKERS[@]}"
  printf "REVIEWER\t%s\n" "${REVIEWERS[@]}"
')"

# 워커: engineer + researcher (더미 dev/test 제거)
assert_contains "$DUMP" "WORKER	engineer:engineer" "default 워커에 engineer"
assert_contains "$DUMP" "WORKER	researcher:researcher" "default 워커에 researcher"
assert_not_contains "$DUMP" "WORKER	dev:dev" "더미 dev 워커 제거됨"
assert_not_contains "$DUMP" "WORKER	test:tester" "더미 test 워커 제거됨"

# 투표 리뷰어: alignment + quality (N=2 → 회로① 자동차단 발동 가능)
assert_contains "$DUMP" "REVIEWER	alignment-rev:reviewer-alignment" "투표 리뷰어 alignment"
assert_contains "$DUMP" "REVIEWER	quality-rev:reviewer-quality" "투표 리뷰어 quality"
# 집계 리뷰어: review-mgr (pane 명 고정)
assert_contains "$DUMP" "REVIEWER	review-mgr:review-manager" "집계 리뷰어 review-mgr"

# 투표인단 수 N>=2 검증 (reviewer-alignment + reviewer-quality, review-manager 제외)
VOTERS="$(printf '%s\n' "$DUMP" | grep -c 'reviewer-alignment\|reviewer-quality')"
assert_eq "2" "$VOTERS" "투표인단 N=2 (회로① 자동차단 정족수)"

# 모든 역할이 resolve_role_file 로 해석되는지 (부팅 가능성 — fail-fast 방지)
for role in engineer researcher reviewer-alignment reviewer-quality review-manager; do
  RF="$(bash -c 'source '"$ROOT"'/bin/lib.sh
    resolve_role_file "'"$ROOT"'/prompts" "'"$role"'"')"
  assert_success "$?" "역할 $role resolve_role_file 성공"
  assert_contains "$RF" "$role" "역할 $role 파일 경로 해석"
done

test_summary
