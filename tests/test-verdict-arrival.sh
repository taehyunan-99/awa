#!/usr/bin/env bash
# @verdict-arrived 회로 회귀 — review/ glob 으로 투표 리뷰어 N 전원 도착 감지 → LEAD 재종합 깨움.
# 결함(2026-06-02 라이브): 단발 task + 비동기 verdict 도착 시 LEAD 가 "verdict 미도착" 으로
#   종합 마친 뒤 재종합 트리거(다음 @done) 없어 늦게 온 VIOLATION 영영 미반영.
# review/ Write 는 events.log 에 안 남으므로(log-event.sh:39 skip) 디렉토리 직접 glob.
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
source ./harness-paths.sh
ROOT="$(cd .. && pwd)"
# shellcheck disable=SC1091
source "$HARNESS_BIN/watcher-lib.sh"

# ── L2: scan_verdict_quorum 함수 동작 (fixture review/ + mktemp -d 격리) ──────
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
REVIEW="$WORK/review"; STATE="$WORK/state"
mkdir -p "$REVIEW" "$STATE"

# helper: voter verdict 파일 1개 생성
mkverdict() { : > "$REVIEW/$1.$2-rev.md"; }   # $1=wid $2=voter

# S1: N 미만 도착(voter 1개, N=2) → 무출력, 마커 미생성
mkverdict "engineer-slug-001" "alignment"
out="$(scan_verdict_quorum "$REVIEW" "$STATE" 2)"
assert_eq "" "$out" "S1: N미만(1/2)은 무출력"
[ -f "$STATE/.verdict-fired.engineer-slug-001" ]; assert_fail "$?" "S1: 마커 미생성"

# S2: N 도달(voter 2개) → wid emit + 마커 생성
mkverdict "engineer-slug-001" "quality"
out="$(scan_verdict_quorum "$REVIEW" "$STATE" 2)"
assert_eq "engineer-slug-001" "$out" "S2: quorum 도달 wid emit"
[ -f "$STATE/.verdict-fired.engineer-slug-001" ]; assert_success "$?" "S2: 마커 생성"

# S3: 마커 후 재호출 → 무출력(재발화 차단)
out="$(scan_verdict_quorum "$REVIEW" "$STATE" 2)"
assert_eq "" "$out" "S3: 마커 있으면 재발화 안 함"

# S4: N=0 → 무출력(무력화)
out="$(scan_verdict_quorum "$REVIEW" "$STATE" 0)"
assert_eq "" "$out" "S4: N=0 무력화"
# S4b: N=비정수 → 무출력
out="$(scan_verdict_quorum "$REVIEW" "$STATE" abc)"
assert_eq "" "$out" "S4b: N=비정수 무력화"

# S5: 다중 wid 동시 — A(2 voter)·B(1 voter), N=2 → A만 emit
REVIEW2="$WORK/review2"; STATE2="$WORK/state2"; mkdir -p "$REVIEW2" "$STATE2"
: > "$REVIEW2/A-001.alignment-rev.md"; : > "$REVIEW2/A-001.quality-rev.md"
: > "$REVIEW2/B-002.alignment-rev.md"
out="$(scan_verdict_quorum "$REVIEW2" "$STATE2" 2)"
assert_eq "A-001" "$out" "S5: A만 quorum(B 미달 제외)"

# S6: 사이클 분리 도착 — 1차 1개(무출력) → 파일 추가 → 2차 quorum emit
REVIEW3="$WORK/review3"; STATE3="$WORK/state3"; mkdir -p "$REVIEW3" "$STATE3"
: > "$REVIEW3/C-003.alignment-rev.md"
out="$(scan_verdict_quorum "$REVIEW3" "$STATE3" 2)"
assert_eq "" "$out" "S6a: 1차 사이클 미달"
: > "$REVIEW3/C-003.quality-rev.md"
out="$(scan_verdict_quorum "$REVIEW3" "$STATE3" 2)"
assert_eq "C-003" "$out" "S6b: 2차 사이클 quorum"

# S7: 비투표 파일 무시 — alternative·review-mgr 메타는 voter 집계 제외
REVIEW4="$WORK/review4"; STATE4="$WORK/state4"; mkdir -p "$REVIEW4" "$STATE4"
: > "$REVIEW4/D-004.alignment-rev.md"
: > "$REVIEW4/D-004.alternative.md"
: > "$REVIEW4/D-004.review-mgr.md"
out="$(scan_verdict_quorum "$REVIEW4" "$STATE4" 2)"
assert_eq "" "$out" "S7: 비투표 파일은 voter 안 셈(1/2 미달)"

# S8: worker 명에 '-' 포함 → wid 전체 정확 추출
REVIEW5="$WORK/review5"; STATE5="$WORK/state5"; mkdir -p "$REVIEW5" "$STATE5"
: > "$REVIEW5/review-mgr-x-001.alignment-rev.md"
: > "$REVIEW5/review-mgr-x-001.quality-rev.md"
out="$(scan_verdict_quorum "$REVIEW5" "$STATE5" 2)"
assert_eq "review-mgr-x-001" "$out" "S8: 하이픈 포함 worker wid 정확 추출"

# S9: review/ 디렉토리 없음 → 무출력, 무해
out="$(scan_verdict_quorum "$WORK/nonexistent" "$STATE" 2)"
assert_eq "" "$out" "S9: review/ 없으면 무해 빈 emit"

# ── L1: watcher.sh 배선 (grep 구조) ──────────────────────────────────────────
WSH="$(cat "$HARNESS_BIN/watcher.sh")"
assert_contains "$WSH" "scan_verdict_quorum" "L1-watcher: scan_verdict_quorum 호출"
assert_contains "$WSH" "@verdict-arrived:" "L1-watcher: @verdict-arrived 발화"
assert_contains "$WSH" 'EXPECTED_VOTERS' "L1-watcher: EXPECTED_VOTERS env 수신"
assert_contains "$WSH" 'dirname "$EVENTS"' "L1-watcher: review_dir 를 EVENTS 에서 도출"

# ── L1: awa-up.sh 배선 (grep 구조) ───────────────────────────────────────────
AUP="$(cat "$HARNESS_BIN/awa-up.sh")"
assert_contains "$AUP" "EXPECTED_VOTERS=0" "L1-awaup: EXPECTED_VOTERS 초기화"
assert_contains "$AUP" "reviewer-alignment|reviewer-quality|reviewer-security" "L1-awaup: 투표 리뷰어 카운트 case"
assert_contains "$AUP" 'EXPECTED_VOTERS=\"$EXPECTED_VOTERS\"' "L1-awaup: watcher env 주입"

# ── L1: orch.md 규약 (grep 구조) ─────────────────────────────────────────────
ORCH="$(cat "$HARNESS_PROMPTS/roles/01-orchestration/orch.md")"
assert_contains "$ORCH" "@verdict-arrived:" "L1-orch: @verdict-arrived 신호 등록"
assert_contains "$ORCH" "신호 9종" "L1-orch: 신호 8종→9종 갱신"
assert_contains "$ORCH" ".verdict-fired" "L1-orch: 마커 ack 규약"

test_summary
