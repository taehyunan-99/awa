#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"
source "$ROOT/bin/lib.sh"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
EV="$TMP/e.log"; : > "$EV"

# done_logged <file> <worker> <id> → done 라인 있으면 0
done_logged "$EV" dev 101; assert_fail "$?" "done 라인 없음 → 미완료"

printf 'T\tdev\t101\tmodify\tsrc/a.ts\n' >> "$EV"
done_logged "$EV" dev 101; assert_fail "$?" "modify 만으론 미완료"

printf 'T\tdev\t101\tdone\t-\n' >> "$EV"
done_logged "$EV" dev 101; assert_success "$?" "done 라인 있음 → 완료"

# 다른 worker-id 격리
done_logged "$EV" dev 999; assert_fail "$?" "다른 id 는 미완료"

# 멱등: 두 번 호출해도 같은 결과
done_logged "$EV" dev 101; assert_success "$?" "재호출 멱등"

# id 타입 비대칭 차단 (T15 리뷰 Important) — leading-zero 문자열 구분
EV2="$TMP/e2.log"
printf 'T\tdev\t01\tdone\t-\n' > "$EV2"
done_logged "$EV2" dev 01; assert_success "$?" "id=01 정확 매칭(문자열)"
done_logged "$EV2" dev 1;  assert_fail "$?" "id=1 은 01 과 다름(STRNUM 수치동치 차단)"
# review_verdict 와 동일 문자열 의미론인지 교차 확인
RVx="$TMP/rvx"; mkdir -p "$RVx"
printf 'verdict: OK\n' > "$RVx/dev-01.spec-rev.md"
rv01="$(review_verdict "$RVx" dev 01)"; rv1="$(review_verdict "$RVx" dev 1)"
assert_eq "OK" "$rv01" "review_verdict id=01 매칭"
assert_eq "PENDING" "$rv1" "review_verdict id=1 불매칭 — done_logged 와 일관(둘 다 문자열)"
# 빈 인자 가드 (T15 리뷰 Minor)
printf 'T\t\t\tdone\t-\n' > "$EV2"
done_logged "$EV2"; assert_fail "$?" "worker/id 인자 누락 → 미완료(빈필드 오매칭 차단)"
done_logged "$EV2" dev; assert_fail "$?" "id 인자 누락 → 미완료"

test_summary
