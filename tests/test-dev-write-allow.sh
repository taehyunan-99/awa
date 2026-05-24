#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh

ROOT="$(cd .. && pwd)"

TMP_PROJ="$(mktemp -d)"; ( cd "$TMP_PROJ" && git init -q )
cleanup() { rm -rf "$TMP_PROJ"; }
trap cleanup EXIT

# dev 템플릿 치환 산출물 검증.
OUT="$(HARNESS_PROJECT="$TMP_PROJ" bash -c '
  source '"$ROOT"'/bin/lib.sh
  generate_worker_settings dev dev
')"
assert_success "$?" "dev settings 생성"
DEVSET="$(cat "$OUT")"

# 치환된 PROJECT_ROOT 절대경로로 Write/Edit allow 존재
assert_contains "$DEVSET" "Write($TMP_PROJ/**)" "dev Write PROJECT_ROOT 스코프 allow"
assert_contains "$DEVSET" "Edit($TMP_PROJ/**)" "dev Edit PROJECT_ROOT 스코프 allow"
# 토큰 미치환 없음
assert_not_contains "$DEVSET" "{{PROJECT_ROOT}}" "dev settings 토큰 치환됨"
# 기존 hook 보존 (회귀)
assert_contains "$DEVSET" "permission-gate.sh" "dev PreToolUse 게이트 보존"

# reviewer 템플릿엔 Write allow 없음 (격리 회귀)
RVOUT="$(HARNESS_PROJECT="$TMP_PROJ" bash -c '
  source '"$ROOT"'/bin/lib.sh
  generate_worker_settings reviewer-quality quality-rev
')"
RVSET="$(cat "$RVOUT")"
assert_not_contains "$RVSET" "Write(" "reviewer 는 Write allow 없음 (격리 유지)"

test_summary
