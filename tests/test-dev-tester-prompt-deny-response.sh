#!/usr/bin/env bash
# dev.md / tester.md 에 "권한 거부 응답 시" 단락 포함 검증.
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh

ROOT="$(cd .. && pwd)"

for f in dev tester; do
  content="$(cat "$ROOT/prompts/roles/$f.md")"
  assert_contains "$content" "권한 거부" "$f.md: 단락 존재"
  assert_contains "$content" "재시도 금지" "$f.md: 재시도 금지 명시"
  assert_contains "$content" "메인" "$f.md: 사용자/메인 보고 지시"
done

test_summary
