#!/usr/bin/env bash
# reviewer-quality.md 에 도구 제약 단락 포함 검증.
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh

ROOT="$(cd .. && pwd)"
F="$ROOT/prompts/roles/reviewer-quality.md"
content="$(cat "$F")"

assert_contains "$content" "도구 사용 제약" "제목 단락"
assert_contains "$content" "Bash" "Bash 금지 명시"
assert_contains "$content" "Edit" "Edit 금지 명시"
assert_contains "$content" "permission-events.log" "lead 감지 채널 명시"
assert_contains "$content" "review/" "Write 허용 경로 명시"

test_summary
