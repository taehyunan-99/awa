#!/usr/bin/env bash
# reviewer-quality.md 에 도구 제약 단락 포함 검증.
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
source ./harness-paths.sh

ROOT="$(cd .. && pwd)"
source "$HARNESS_BIN/lib.sh" >/dev/null 2>&1 || true
F="$(resolve_role_file "$HARNESS_PROMPTS" reviewer-quality)"
content="$(cat "$F")"

assert_contains "$content" "도구 사용 제약" "제목 단락"
assert_contains "$content" "Bash" "Bash 금지 명시"
assert_contains "$content" "Edit" "Edit 금지 명시"
assert_contains "$content" "permission-gate" "lead 감지: hook 게이트 명시"
assert_contains "$content" "review/" "Write 허용 경로 명시"

revc="$(cat "$(resolve_role_file "$HARNESS_PROMPTS" reviewer-common)")"
assert_contains "$revc" "Bash" "reviewer-common ① Bash 금지 명시"
assert_contains "$revc" "신뢰" "reviewer-common ① 금지 근거(신뢰성)"

test_summary
