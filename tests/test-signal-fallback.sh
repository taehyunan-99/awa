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

test_summary
