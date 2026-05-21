#!/usr/bin/env bash
# prompts/loop/lead.md 에 권한 이벤트 감지 단락 포함 검증.
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh

ROOT="$(cd .. && pwd)"
content="$(cat "$ROOT/prompts/loop/lead.md")"

assert_contains "$content" "권한 이벤트 감지" "단락 제목"
assert_contains "$content" "permission-events.log" "permission-events.log 채널"
assert_contains "$content" ".lead-perm-cursor" "lead 커서 파일"
assert_contains "$content" "rm" "deny 패턴 — rm"
assert_contains "$content" "git push" "deny 패턴 — git push"
assert_contains "$content" "reviewer" "reviewer 위반 감지"
assert_contains "$content" "review/" "review/ 외 Write 감지"

test_summary
