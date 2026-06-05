#!/usr/bin/env bash
# reviewer 정상 산출물 경로(review/ verdict·.review-cursor)는 auto-allow(matrix),
# 그 외 경로 Write 는 회색(gray) 유지 — 라이브 검증 결함(reviewer 정상 Write USER-ASK) 가드.
# 설계 의도: verdict 기록·커서 갱신만 허용, 코드 수정 Write 는 lead 가 감지(회색).
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
source ./harness-paths.sh

ROOT="$(cd .. && pwd)"

TMP_PROJ="$(mktemp -d)"; ( cd "$TMP_PROJ" && git init -q )
cleanup() { rm -rf "$TMP_PROJ"; }
trap cleanup EXIT

# reviewer settings 생성 (entry_role=reviewer-quality → settings 파일 reviewer-quality.json).
# REVIEWERS 엔트리 "quality-rev:reviewer-quality:haiku" → parse_entry 결과
#   ENTRY_NAME=quality-rev, ENTRY_ROLE=reviewer-quality.
# generate_worker_settings 의 첫 인자(entry_role)=reviewer-quality 가 settings 파일명·classify 첫 인자.
RVOUT="$(HARNESS_PROJECT="$TMP_PROJ" PROJECT_ROOT="$TMP_PROJ" bash -c '
  source '"$HARNESS_BIN"'/lib.sh
  generate_worker_settings reviewer-quality quality-rev
')"
assert_success "$?" "reviewer settings 생성"
RVSET="$(cat "$RVOUT")"
assert_contains "$RVSET" "permissions" "reviewer settings 내용 존재"
# settings 파일명이 reviewer-quality.json 이어야 classify(matrix_lookup)가 찾는다.
assert_eq "reviewer-quality.json" "$(basename "$RVOUT")" "settings 파일명 = reviewer-quality.json"
# 토큰 미치환 없음
assert_not_contains "$RVSET" "{{PROJECT_ROOT}}" "reviewer settings 토큰 치환됨"

# classify verdict 추출 헬퍼 (entry_role=reviewer-quality 고정).
gate_verdict() {  # $1=tool $2=input_json → stdout: verdict 만
  PROJECT_ROOT="$TMP_PROJ" HARNESS_PROJECT="$TMP_PROJ" bash -c '
    set -uo pipefail
    source '"$HARNESS_BIN"'/lib.sh
    source '"$HARNESS_BIN"'/matrix-lookup.sh
    source '"$HARNESS_BIN"'/danger-check.sh
    source '"$HARNESS_BIN"'/classify.sh
    classify reviewer-quality "$1" "$2"
  ' _ "$1" "$2" | cut -f1
}

# (a) review/ verdict 파일 Write → matrix (auto-allow). 정상 산출물.
v="$(gate_verdict Write "{\"file_path\":\"$TMP_PROJ/.agent-harness/review/dev-T1.quality-rev.md\"}")"
assert_eq "matrix" "$v" "reviewer Write review/verdict → matrix (auto-allow)"

# (a2) review/ verdict Edit (재기록) → matrix.
v="$(gate_verdict Edit "{\"file_path\":\"$TMP_PROJ/.agent-harness/review/dev-T1.quality-rev.md\"}")"
assert_eq "matrix" "$v" "reviewer Edit review/verdict → matrix (재기록 auto-allow)"

# (b) .review-cursor.<reviewer> Write → matrix.
v="$(gate_verdict Write "{\"file_path\":\"$TMP_PROJ/.agent-harness/.review-cursor.quality-rev\"}")"
assert_eq "matrix" "$v" "reviewer Write .review-cursor → matrix (커서 갱신 auto-allow)"

# (b2) .review-cursor.<reviewer> Edit → matrix.
v="$(gate_verdict Edit "{\"file_path\":\"$TMP_PROJ/.agent-harness/.review-cursor.quality-rev\"}")"
assert_eq "matrix" "$v" "reviewer Edit .review-cursor → matrix (커서 갱신 auto-allow)"

# (c) 코드파일 Write → gray (여전히 회색 — 코드 수정 시 lead 감지). 과확대 금지.
v="$(gate_verdict Write "{\"file_path\":\"$TMP_PROJ/todo.sh\"}")"
assert_eq "gray" "$v" "reviewer Write 코드파일 → gray (auto-allow 과확대 안 됨)"

# (c2) 프로젝트 루트의 일반 .md 도 회색 (review/ 하위만 허용 — 정밀 스코프 검증).
v="$(gate_verdict Write "{\"file_path\":\"$TMP_PROJ/README.md\"}")"
assert_eq "gray" "$v" "reviewer Write 프로젝트 README.md → gray (review/ 밖)"

# (d) traversal review/../../../etc/x Write → matrix 아님 (C-1 traversal 차단 유지).
#     verdict 가 matrix 만 아니면 됨(gray/danger 무관).
v="$(gate_verdict Write "{\"file_path\":\"$TMP_PROJ/.agent-harness/review/../../../etc/x\"}")"
assert_eq "1" "$([ "$v" != "matrix" ] && echo 1 || echo 0)" "reviewer Write review/traversal → matrix 아님 (traversal 차단)"

# (d2) cursor 경로에 traversal 끼워넣기 → matrix 아님.
v="$(gate_verdict Write "{\"file_path\":\"$TMP_PROJ/.agent-harness/../../../etc/.review-cursor.x\"}")"
assert_eq "1" "$([ "$v" != "matrix" ] && echo 1 || echo 0)" "reviewer Write cursor traversal → matrix 아님 (traversal 차단)"

test_summary
