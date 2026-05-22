#!/usr/bin/env bash
# add_to_allow (atomic) + derive_pattern 단위 테스트.
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"
export HARNESS_PROJECT="$(mktemp -d)"
( cd "$HARNESS_PROJECT" && git init -q )
# shellcheck disable=SC1091
source "$ROOT/bin/lib.sh"

BOOTSET="$HARNESS_PROJECT/.agent-harness/.boot-settings"
mkdir -p "$BOOTSET"

echo "[A1] allow 키 부재 settings 에 추가 (// [] fallback)"
echo '{"permissions":{"deny":["Bash(rm *)"]}}' > "$BOOTSET/dev.json"
add_to_allow dev "Bash(npm test:*)"
content="$(cat "$BOOTSET/dev.json")"
assert_contains "$content" "Bash(npm test:*)" "A1 allow 추가됨"
assert_contains "$content" "Bash(rm *)" "A1 기존 deny 보존"

echo "[A2] 중복 추가 시 unique"
add_to_allow dev "Bash(npm test:*)"
cnt="$(jq '.permissions.allow | length' "$BOOTSET/dev.json")"
assert_eq "1" "$cnt" "A2 중복 제거 (length=1)"

echo "[A3] atomic — tmp 파일 잔존 없음"
if ls "$BOOTSET"/dev.json.tmp.* >/dev/null 2>&1; then
  assert_eq "no-tmp" "tmp-exists" "A3 tmp 파일 잔존"
else
  assert_success 0 "A3 tmp 파일 잔존 없음"
fi

echo "[A4] derive_pattern exact (Bash)"
out="$(derive_pattern "Bash" '{"command":"npm test foo"}' "exact")"
assert_eq "Bash(npm test foo)" "$out" "A4 exact"

echo "[A5] derive_pattern command-group (Bash 첫 2 토큰)"
out="$(derive_pattern "Bash" '{"command":"npm test foo"}' "command-group")"
assert_eq "Bash(npm test:*)" "$out" "A5 command-group"

echo "[A6] derive_pattern tool"
out="$(derive_pattern "Bash" '{"command":"npm test foo"}' "tool")"
assert_eq "Bash" "$out" "A6 tool"

echo "[A7] derive_pattern command-group 단일 토큰"
out="$(derive_pattern "Bash" '{"command":"ls"}' "command-group")"
assert_eq "Bash(ls:*)" "$out" "A7 단일 토큰 command-group"

echo "[A8] derive_pattern exact (Edit → file_path)"
out="$(derive_pattern "Edit" '{"file_path":"/a/b.py"}' "exact")"
assert_eq "Edit(/a/b.py)" "$out" "A8 Edit exact"

test_summary
