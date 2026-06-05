#!/usr/bin/env bash
# resolve_role_file 글롭 단일매칭 단위테스트 (0/1/2개 케이스).
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
source ./harness-paths.sh
ROOT="$(cd .. && pwd)"
# lib.sh 는 source-safe (line 37~38: source 파일이라 exit 금지, 변수로 결과 전달 — 실측 확인).
# source 해도 안 죽고, lib.sh 는 ROOT 전역을 안 건드림(HARNESS_ROOT/PROJECT_ROOT/WORKSPACE 만) → 충돌 0.
source "$HARNESS_BIN/lib.sh" >/dev/null 2>&1 || true

FIX="$(mktemp -d)"
mkdir -p "$FIX/roles/01-a" "$FIX/roles/02-b"
: > "$FIX/roles/01-a/dev.md"

# 케이스1: 정상 단일매칭
out="$(resolve_role_file "$FIX" "dev")"; rc=$?
assert_success "$rc" "단일매칭 rc=0"
assert_eq "$FIX/roles/01-a/dev.md" "$out" "단일매칭 경로 정확"

# 케이스2: 매칭 0개 → 오류
resolve_role_file "$FIX" "nonexist" >/dev/null 2>&1; rc=$?
assert_fail "$rc" "매칭 0개 rc≠0"

# 케이스3: 중복 2개 → 오류
: > "$FIX/roles/02-b/dev.md"
resolve_role_file "$FIX" "dev" >/dev/null 2>&1; rc=$?
assert_fail "$rc" "중복 2개 rc≠0 (역할명 고유성 위반)"

rm -rf "$FIX"
test_summary
