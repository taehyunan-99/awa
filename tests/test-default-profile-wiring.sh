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

# 투표 리뷰어: alignment + quality(claude) + security(codex) (N=3 → 회로① 다벤더 자동차단)
assert_contains "$DUMP" "REVIEWER	alignment-rev:reviewer-alignment" "투표 리뷰어 alignment(claude)"
assert_contains "$DUMP" "REVIEWER	quality-rev:reviewer-quality" "투표 리뷰어 quality(claude)"
assert_contains "$DUMP" "REVIEWER	security-rev:reviewer-security:codex" "투표 리뷰어 security(codex — 다벤더)"
# 집계 리뷰어: review-mgr (pane 명 고정)
assert_contains "$DUMP" "REVIEWER	review-mgr:review-manager" "집계 리뷰어 review-mgr"

# 투표인단 수 N=3 검증 (alignment + quality + security, review-manager 제외)
VOTERS="$(printf '%s\n' "$DUMP" | grep -c 'reviewer-alignment\|reviewer-quality\|reviewer-security')"
assert_eq "3" "$VOTERS" "투표인단 N=3 (다벤더 회로① 자동차단 정족수)"

# 다벤더 입증: security 리뷰어가 codex 벤더로 명시됐는지 (claude 아닌 벤더 ≥1)
assert_contains "$DUMP" "reviewer-security:codex" "다벤더 — security 리뷰어 벤더=codex"

# 모든 역할이 resolve_role_file 로 해석되는지 (부팅 가능성 — fail-fast 방지)
for role in engineer researcher reviewer-alignment reviewer-quality reviewer-security review-manager; do
  RF="$(bash -c 'source '"$ROOT"'/bin/lib.sh
    resolve_role_file "'"$ROOT"'/prompts" "'"$role"'"')"
  assert_success "$?" "역할 $role resolve_role_file 성공"
  assert_contains "$RF" "$role" "역할 $role 파일 경로 해석"
done

test_summary
