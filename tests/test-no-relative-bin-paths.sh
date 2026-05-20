#!/usr/bin/env bash
# T8 회귀: prompts/ 안 백틱 `bin/` 상대경로 prefix 가 0 줄이어야 함.
# {{HARNESS_ROOT}}/bin/ 는 통과 (절대경로 토큰 — 앞에 / 가 있어 백틱 직후 'bin/' 아님).
# 즉 backtick 직후 'bin/' 으로 시작하는 라인만 잡아 회귀 차단.

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HARNESS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$SCRIPT_DIR/assert.sh"

# grep -r: prompts/ 트리 전체.
# 패턴: 백틱(`) 직후 'bin/' 시작. {{HARNESS_ROOT}}/bin/ 는 'bin/' 앞에 /이 있어 미검출.
bad_lines="$(grep -rn '`bin/' "$HARNESS_ROOT/prompts/" 2>/dev/null || true)"

if [ -n "$bad_lines" ]; then
  echo "발견된 상대경로 라인:" >&2
  echo "$bad_lines" >&2
  assert_eq "no-bad-lines" "found-bad-lines" "prompts/ 안 백틱 'bin/' 상대경로 잔존"
else
  assert_eq "no-bad-lines" "no-bad-lines" "prompts/ 안 백틱 'bin/' 상대경로 없음"
fi

test_summary
