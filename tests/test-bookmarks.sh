#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"

# 격리: XDG_CONFIG_HOME 을 임시 디렉터리로
export XDG_CONFIG_HOME="$(mktemp -d)"
trap 'rm -rf "$XDG_CONFIG_HOME"' EXIT

source "$ROOT/bin/lib.sh"

echo "[B1] bookmarks_init: 디렉터리·파일 생성"
bookmarks_init
assert_eq "1" "$(test -d "$XDG_CONFIG_HOME/agenphony" && echo 1)" "B1a 디렉터리"
assert_eq "1" "$(test -f "$BOOKMARKS_FILE" && echo 1)" "B1b 파일"

echo "[B2] bookmarks_upsert: 신규 추가"
bookmarks_upsert "/tmp/proj-a" "default" ""
lines="$(wc -l < "$BOOKMARKS_FILE" | tr -d ' ')"
assert_eq "1" "$lines" "B2a 1 라인"
content="$(cat "$BOOKMARKS_FILE")"
assert_contains "$content" "/tmp/proj-a" "B2b path"
assert_contains "$content" "default" "B2c preset"

echo "[B3] bookmarks_upsert: 같은 path 갱신 (alias 보존)"
bookmarks_set_alias 1 "myalias"
bookmarks_upsert "/tmp/proj-a" "feature-team" "/tmp/proj-a/plan.md"
content="$(cat "$BOOKMARKS_FILE")"
assert_contains "$content" "myalias" "B3a alias 보존"
assert_contains "$content" "feature-team" "B3b preset 갱신"
lines="$(wc -l < "$BOOKMARKS_FILE" | tr -d ' ')"
assert_eq "1" "$lines" "B3c 중복 없음"

echo "[B4] bookmarks_resolve_alias"
result="$(bookmarks_resolve_alias "myalias")"
assert_eq "/tmp/proj-a" "$result" "B4a alias → path"
result="$(bookmarks_resolve_alias "nonexistent")"
assert_eq "" "$result" "B4b 없는 alias → 빈"

echo "[B5] bookmarks_list 출력"
bookmarks_upsert "/tmp/proj-b" "research" ""
out="$(bookmarks_list)"
assert_contains "$out" "/tmp/proj-a" "B5a path1"
assert_contains "$out" "/tmp/proj-b" "B5b path2"

echo "[B6] bookmarks stale 표시 (path 없는 케이스)"
out="$(bookmarks_list)"
assert_contains "$out" "[stale]" "B6 stale 마킹"

echo "[B6b] bookmarks_set_alias: 충돌 시 거부 (return 1, 기존 path 우선)"
# /tmp/proj-a (alias=myalias) 가 있는 상태 — /tmp/proj-b 에 같은 alias 시도 시 거부
if bookmarks_set_alias 2 "myalias" 2>/dev/null; then
  echo "  FAIL: B6b 충돌 alias 가 허용됨"; _TESTS_RUN=$((_TESTS_RUN+1)); _TESTS_FAIL=$((_TESTS_FAIL+1))
else
  # /tmp/proj-b 의 alias 컬럼이 비어있어야 함 (덮어쓰기 안 됨)
  b_alias=$(awk -F'\t' '$1=="/tmp/proj-b"{print $2}' "$BOOKMARKS_FILE")
  [ -z "$b_alias" ] && { echo "  ok: B6b 거부 + 미덮어쓰기"; _TESTS_RUN=$((_TESTS_RUN+1)); } \
                    || { echo "  FAIL: B6b alias 가 덮어써짐"; _TESTS_RUN=$((_TESTS_RUN+1)); _TESTS_FAIL=$((_TESTS_FAIL+1)); }
fi

echo "[B7] bookmarks_remove 단일"
mkdir -p /tmp/proj-c-real
bookmarks_upsert "/tmp/proj-c-real" "default" ""
bookmarks_remove "2"   # /tmp/proj-b (없는 것) 제거
content="$(cat "$BOOKMARKS_FILE")"
if ! printf '%s' "$content" | grep -qF "/tmp/proj-b"; then
  echo "  ok: B7 remove"
  _TESTS_RUN=$((_TESTS_RUN+1))
else
  echo "  FAIL: B7 remove (proj-b 잔존)"
  _TESTS_RUN=$((_TESTS_RUN+1)); _TESTS_FAIL=$((_TESTS_FAIL+1))
fi

echo "[B8] bookmarks_prune 자동 (stale 제거)"
echo "y" | bookmarks_prune > /dev/null
content="$(cat "$BOOKMARKS_FILE")"
if ! printf '%s' "$content" | grep -qF "/tmp/proj-a"; then
  echo "  ok: B8a stale /tmp/proj-a 제거됨"
  _TESTS_RUN=$((_TESTS_RUN+1))
else
  echo "  FAIL: B8a stale 잔존"
  _TESTS_RUN=$((_TESTS_RUN+1)); _TESTS_FAIL=$((_TESTS_FAIL+1))
fi
assert_contains "$(cat "$BOOKMARKS_FILE")" "/tmp/proj-c-real" "B8b 실재 path 보존"

rm -rf /tmp/proj-c-real

echo "[B9] wrapper: bash agenphony-bookmarks.sh list"
mkdir -p /tmp/proj-w
bookmarks_upsert "/tmp/proj-w" "default" ""
out="$(bash "$ROOT/bin/agenphony-bookmarks.sh" list 2>&1)"
assert_contains "$out" "/tmp/proj-w" "B9 wrapper list"
rm -rf /tmp/proj-w

test_summary
