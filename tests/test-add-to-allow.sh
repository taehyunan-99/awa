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

echo "[A9] derive_pattern command-group 멀티라인 → 빈 문자열 (학습 불가)"
ml='{"command":"cd /tmp\n\n# 테스트\nrm -f x\n./todo.sh add y"}'
out="$(derive_pattern "Bash" "$ml" "command-group")"
assert_eq "" "$out" "A9 멀티라인 → 빈 문자열"

echo "[A10] derive_pattern command-group 셸 메타문자 → 빈 문자열"
for meta_cmd in 'cd x && ls' 'a || b' 'ls; pwd' 'grep x | wc -l' 'echo \$(date)' 'echo x > f' 'cat < f'; do
  out="$(derive_pattern "Bash" "$(jq -nc --arg c "$meta_cmd" '{command:$c}')" "command-group")"
  assert_eq "" "$out" "A10 메타 [$meta_cmd] → 빈 문자열"
done
out="$(derive_pattern "Bash" '{"command":"echo `date`"}' "command-group")"
assert_eq "" "$out" "A10 백틱 → 빈 문자열"

echo "[A11] derive_pattern command-group 단순 명령은 정상 prefix 유지 (회귀)"
out="$(derive_pattern "Bash" '{"command":"npm test foo"}' "command-group")"
assert_eq "Bash(npm test:*)" "$out" "A11 단순 2토큰 유지"
out="$(derive_pattern "Bash" '{"command":"git add file.sh"}' "command-group")"
assert_eq "Bash(git add:*)" "$out" "A11 git add 유지"
out="$(derive_pattern "Bash" '{"command":"ls"}' "command-group")"
assert_eq "Bash(ls:*)" "$out" "A11 단일 토큰 유지"

echo "[A12] derive_pattern exact 는 복합이어도 그대로 (학습 강등은 command-group 만)"
out="$(derive_pattern "Bash" '{"command":"cd x && ls"}' "exact")"
assert_eq "Bash(cd x && ls)" "$out" "A12 exact 는 불변"

echo "[A13] add_to_allow 빈 패턴은 settings 미변경 (방어적 가드)"
echo '{"permissions":{"allow":["Bash(ls:*)"]}}' > "$BOOTSET/devg.json"
add_to_allow devg ""
cnt="$(jq '.permissions.allow | length' "$BOOTSET/devg.json")"
assert_eq "1" "$cnt" "A13 빈 패턴 추가 안 됨 (length 그대로 1)"
content="$(cat "$BOOTSET/devg.json")"
assert_not_contains "$content" '""' "A13 빈 문자열 패턴 미삽입"

test_summary
