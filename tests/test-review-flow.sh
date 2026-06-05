#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
source ./harness-paths.sh
ROOT="$(cd .. && pwd)"
source "$HARNESS_BIN/lib.sh"

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

# 형식 변종 견고성 (T14 리뷰 Important — 프롬프트는 등호 지시, 파서 형식무관이어야)
RV2="$TMP/review2"; mkdir -p "$RV2"
printf -- 'verdict=VIOLATION, signal=weak, severity=high\n' > "$RV2/dev-1.spec-rev.md"
assert_eq "VIOLATION" "$(review_verdict "$RV2" dev 1)" "등호 형식 verdict=VIOLATION 인식"
printf -- 'verdict=OK\n' > "$RV2/test-2.spec-rev.md"
assert_eq "OK" "$(review_verdict "$RV2" test 2)" "등호 형식 verdict=OK 인식"
printf -- 'verdict:violation\n' > "$RV2/x-3.spec-rev.md"
assert_eq "VIOLATION" "$(review_verdict "$RV2" x 3)" "콜론무공백·소문자 verdict 인식"
printf -- '- verdict: OK (all checks passed)\n' > "$RV2/y-4.quality-rev.md"
assert_eq "OK" "$(review_verdict "$RV2" y 4)" "마크다운 불릿+괄호주석 verdict 인식"
printf -- 'verdict: VIOLATION\nseverity: high\n' > "$RV2/z-5.arch-rev.md"
assert_eq "VIOLATION" "$(review_verdict "$RV2" z 5)" "YAML 형식 회귀(기존 형식도 여전히)"

test_summary
