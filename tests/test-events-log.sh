#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"
source "$ROOT/bin/lib.sh"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
EV="$TMP/e.log"
printf 'TS\tdev\t101\tmodify\tsrc/a.ts\n' >  "$EV"
printf 'BROKEN LINE NO TABS\n'            >> "$EV"
printf 'TS\tarch\t102\tdone\t-\n'         >> "$EV"

# event_field <line> <n> → n번째 탭 필드
line1="$(sed -n 1p "$EV")"
assert_eq "dev" "$(event_field "$line1" 2)" "필드2=worker"
assert_eq "modify" "$(event_field "$line1" 4)" "필드4=action"

# event_valid <line> → 5필드면 0, 아니면 1
event_valid "$line1"; assert_success "$?" "정상 5필드 valid"
event_valid "BROKEN LINE NO TABS"; assert_fail "$?" "파손 라인 invalid"

# events_valid_count <file> → valid 라인만 카운트 (파손 skip)
cnt="$(events_valid_count "$EV")"
assert_eq "2" "$cnt" "파손 1줄 skip → valid 2줄"

test_summary
