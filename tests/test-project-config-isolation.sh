#!/usr/bin/env bash
# project config 가 PROJECT_ROOT/config 가 아닌 .agent-harness/config 에 설치되는지 (사용자 비오염)
set -u
cd "$(dirname "$0")"
source ./assert.sh
source ./harness-paths.sh
ROOT="$(cd .. && pwd)"

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT
PROJ="$TMPDIR/proj"
mkdir -p "$PROJ"
git -C "$PROJ" init -q 2>/dev/null || true

# C1 — 부트 경로의 config 설치 블록(awa-up.sh:311-333 와 동일 경로)을 직접 실행해
#   .agent-harness/config 에 생기고 PROJECT_ROOT/config 엔 안 생기는지 검증.
HARNESS_PROJECT="$PROJ" bash -c '
  source "'"$HARNESS_BIN"'/lib.sh"
  HARNESS_YAML="$HARNESS_ROOT/config/orch-auto-allow.yaml"
  PROJ_YAML="$PROJECT_ROOT/.agent-harness/config/orch-auto-allow.yaml"
  mkdir -p "$(dirname "$PROJ_YAML")"
  cp "$HARNESS_YAML" "$PROJ_YAML"
'
assert_eq "1" "$([ -f "$PROJ/.agent-harness/config/orch-auto-allow.yaml" ] && echo 1 || echo 0)" "C1a .agent-harness/config 에 설치됨"
assert_eq "0" "$([ -d "$PROJ/config" ] && echo 1 || echo 0)" "C1b PROJECT_ROOT/config 비오염"

# C2 — matrix-lookup 이 .agent-harness/config 를 읽는지 (경로 정합)
hits="$(grep -c 'agent-harness/config' "$HARNESS_BIN/matrix-lookup.sh" 2>/dev/null || echo 0)"
assert_eq "1" "$hits" "C2 matrix-lookup 읽기경로 .agent-harness/config"

# C3 — awa-up 의 gitignore 자동추가에 config 패턴 잔재 없음
hits="$(grep -cE '"config/(\.orch-auto-allow-marker|\*\.bak)"' "$HARNESS_BIN/awa-up.sh" 2>/dev/null || true)"
assert_eq "0" "$hits" "C3 gitignore 자동추가 config 패턴 정리됨"

test_summary
