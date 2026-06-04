#!/usr/bin/env bash
# _common.md 에 권한·rm 정책 섹션 포함 검증.
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"
content="$(cat "$ROOT/prompts/_common.md")"

assert_contains "$content" "권한·rm 정책" "섹션 제목"
assert_contains "$content" "@orch: rm" "rm 위임 보고 형식"
assert_contains "$content" "@orch: rm-r" "rm-r 보고 형식"
assert_contains "$content" "@orch: remove-dir" "remove-dir 보고 형식"
assert_contains "$content" "직접 호출 금지" "rm 직접 호출 금지"
assert_contains "$content" "자동 거부" "위험 명령 자동 거부 안내"
assert_contains "$content" "{{WORKER_NAME}}" "기존 _common.md 보존"

test_summary
