#!/usr/bin/env bash
# T8 회귀: prompts/ 안 백틱 `bin/` 상대경로 prefix 가 0 줄이어야 함.
# {{HARNESS_ROOT}}/bin/ 는 통과 (절대경로 토큰 — 앞에 / 가 있어 백틱 직후 'bin/' 아님).
# 즉 backtick 직후 'bin/' 으로 시작하는 라인만 잡아 회귀 차단.

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/assert.sh"
. "$SCRIPT_DIR/harness-paths.sh"   # 하니스 경로 단일 출처 — 이동 시 harness-paths.sh 만 수정
HARNESS_ROOT="$HARNESS"

# 검사 대상: boot 합본에 실제 들어가는 파일만 — _common.md, _partials/*.md,
# roles/**/*.md. AGENTS.md / CLAUDE.md / LEARNED_CAUTIONS.md 같은 영역 가이드
# 문서는 워커 부트에 안 들어가니 false-positive 회피(13차 추가).
# 패턴: 백틱(`) 직후 'bin/' 시작. {{HARNESS_ROOT}}/bin/ 는 'bin/' 앞에 /이 있어 미검출.
boot_files="$(find "$HARNESS_ROOT/prompts" \
  \( -path "$HARNESS_ROOT/prompts/_common.md" \
     -o -path "$HARNESS_ROOT/prompts/_partials/*.md" \
     -o -path "$HARNESS_ROOT/prompts/roles/*/*.md" \) \
  -type f 2>/dev/null)"
if [ -z "$boot_files" ]; then
  bad_lines=""
else
  bad_lines="$(printf '%s\n' "$boot_files" | xargs grep -n '`bin/' 2>/dev/null || true)"
fi

if [ -n "$bad_lines" ]; then
  echo "발견된 상대경로 라인:" >&2
  echo "$bad_lines" >&2
  assert_eq "no-bad-lines" "found-bad-lines" "prompts/ 안 백틱 'bin/' 상대경로 잔존"
else
  assert_eq "no-bad-lines" "no-bad-lines" "prompts/ 안 백틱 'bin/' 상대경로 없음"
fi

test_summary
