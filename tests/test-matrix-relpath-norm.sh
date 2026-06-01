#!/usr/bin/env bash
# matrix_lookup 의 Write/Edit file_path 상대경로 정규화 회귀.
# 결함(2026-06-01 라이브 e2e): 리뷰어가 review/ 에 Write 를 *상대경로*(.agent-harness/review/x.md)로
# 호출하면 settings allow 의 절대패턴(Write(/abs/review/**))과 매칭 실패 → gray → 게이트 봉쇄.
# 한 리뷰어는 절대, 다른 리뷰어는 상대로 호출해 N=2 합의가 무작위로 깨짐(회로① 바이패스).
# 수정: matrix_lookup 이 file_path 를 매칭 전 절대경로로 정규화(공통산출 특례와 동일 dirname+pwd -P).
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"
# shellcheck disable=SC1091
source "$ROOT/bin/lib.sh"
# shellcheck disable=SC1091
source "$ROOT/bin/matrix-lookup.sh"

PT="$(mktemp -d)"
mkdir -p "$PT/.agent-harness/.boot-settings"
mkdir -p "$PT/.agent-harness/review"
# 리뷰어 settings: review/ 와 cursor 절대패턴 allow (실제 reviewer 템플릿과 동형).
cat > "$PT/.agent-harness/.boot-settings/reviewer-alignment.json" <<JSON
{"permissions":{"allow":[
  "Write($PT/.agent-harness/review/**)",
  "Write($PT/.agent-harness/.review-cursor.*)",
  "Edit($PT/.agent-harness/review/**)"
]}}
JSON
export PROJECT_ROOT="$PT"

echo "[R1] 절대경로 file_path → MATRIX 매칭 (기존 동작 보존)"
out="$(matrix_lookup reviewer-alignment Write "{\"file_path\":\"$PT/.agent-harness/review/v.md\"}")"
assert_success "$?" "R1 절대경로 Write 매칭 성공"
assert_contains "$out" "review/**" "R1 매칭 패턴 review/**"

echo "[R2] 상대경로 file_path → 정규화 후 MATRIX 매칭 (결함 수정 핵심)"
# 리뷰어가 .agent-harness/review/x.md 처럼 PROJECT_ROOT 기준 상대경로로 Write 호출.
# 정규화 전엔 rc=1(gray), 정규화 후엔 rc=0(matrix).
( cd "$PT" && \
  out="$(matrix_lookup reviewer-alignment Write '{"file_path":".agent-harness/review/x.md"}')" && \
  [ -n "$out" ] )
assert_success "$?" "R2 상대경로 Write 정규화 매칭 성공"

echo "[R3] 상대경로 Edit 도 동일 정규화"
( cd "$PT" && \
  out="$(matrix_lookup reviewer-alignment Edit '{"file_path":".agent-harness/review/y.md"}')" && \
  [ -n "$out" ] )
assert_success "$?" "R3 상대경로 Edit 정규화 매칭 성공"

echo "[R4] scope 밖 상대경로 → 여전히 비매칭 (과허용 방지)"
# review/ 밖(예: src/) 상대경로는 정규화돼도 allow 패턴 밖 → gray 유지.
( cd "$PT" && \
  out="$(matrix_lookup reviewer-alignment Write '{"file_path":"src/secret.sh"}')"
  [ -z "$out" ] )
assert_success "$?" "R4 scope 밖 상대경로 비매칭(gray 유지)"

echo "[R5] .. 트래버설 상대경로 → 비매칭 (탈출 방어)"
( cd "$PT/.agent-harness/review" && \
  out="$(matrix_lookup reviewer-alignment Write '{"file_path":"../../../etc/x"}')"
  [ -z "$out" ] )
assert_success "$?" "R5 .. 트래버설 비매칭"

rm -rf "$PT"
test_summary
