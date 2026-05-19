#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"
source "$ROOT/bin/lib.sh"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
EV="$TMP/e.log"
# 같은 (dev, src/a.ts) 3번 + 다른 path 1번 + 다른 worker 같은 path 1번
printf 'T\tdev\t1\tmodify\tsrc/a.ts\n'  >  "$EV"
printf 'T\tdev\t1\tmodify\tsrc/a.ts\n'  >> "$EV"
printf 'T\tdev\t1\tmodify\tsrc/b.ts\n'  >> "$EV"
printf 'T\tdev\t1\tmodify\tsrc/a.ts\n'  >> "$EV"
printf 'T\ttest\t2\tmodify\tsrc/a.ts\n' >> "$EV"

# debounce_pairs <file> → 유니크 (worker,path) 줄 (1회 처리범위 접기)
out="$(debounce_pairs "$EV" | sort)"
expected="dev	src/a.ts
dev	src/b.ts
test	src/a.ts"
assert_eq "$expected" "$out" "(worker,path) 3쌍으로 접힘 (dev/a 3→1)"

test_summary
