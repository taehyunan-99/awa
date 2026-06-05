#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
source ./harness-paths.sh
ROOT="$(cd .. && pwd)"
source "$HARNESS_BIN/lib.sh"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export WORKSPACE="$TMP"
EV="$TMP/events.log"
printf 'l1\nl2\nl3\n' > "$EV"

# cursor_read <reviewer> → 없으면 0
assert_eq "0" "$(cursor_read specrev)" "초기 커서 0"

# cursor_new_lines <reviewer> <events.log> → 커서 이후 줄 출력, 커서 미변경
out="$(cursor_new_lines specrev "$EV")"
assert_eq "l1
l2
l3" "$out" "커서0 → 전체 3줄"

# cursor_commit <reviewer> <n> → 커서 갱신
cursor_commit specrev 3
assert_eq "3" "$(cursor_read specrev)" "커서 3 갱신"
out2="$(cursor_new_lines specrev "$EV")"
assert_eq "" "$out2" "커서3 → 새 줄 없음 (멱등)"

# 리뷰어별 독립
assert_eq "0" "$(cursor_read qualrev)" "다른 리뷰어 커서 독립(0)"

test_summary
