#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"
source "$ROOT/bin/lib.sh"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
RV="$TMP/review"; mkdir -p "$RV"

mkfile() {  # $1=name $2=verdict $3=severity
  printf -- '---\nverdict: %s\nseverity: %s\n---\n' "$2" "$3" > "$RV/$1"
}

# 리뷰어 3개, 모두 OK → 종합 OK
mkfile "dev-1.spec-rev.md" OK low
mkfile "dev-1.quality-rev.md" OK low
mkfile "dev-1.arch-rev.md" OK low
assert_eq "OK" "$(review_verdict "$RV" dev 1)" "전 OK → 종합 OK"

# 하나라도 VIOLATION → 종합 VIOLATION
mkfile "dev-1.quality-rev.md" VIOLATION high
assert_eq "VIOLATION" "$(review_verdict "$RV" dev 1)" "high 1개 → 종합 VIOLATION"

# 덮어쓰기 없음: 3개 파일 공존 확인
n="$(ls "$RV"/dev-1.*.md | wc -l | tr -d ' ')"
assert_eq "3" "$n" "리뷰어 3파일 공존(덮어쓰기 없음)"

# 다른 worker-id 격리
mkfile "test-2.spec-rev.md" OK low
assert_eq "OK" "$(review_verdict "$RV" test 2)" "다른 task 격리"
assert_eq "VIOLATION" "$(review_verdict "$RV" dev 1)" "기존 task 영향 없음"

test_summary
