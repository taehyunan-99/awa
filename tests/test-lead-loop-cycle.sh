#!/usr/bin/env bash
# lead.md 9차: 게이트 3단계(pending/incident/removal) + reviewer 거버넌스 보존. 데몬·dedup·PRE폴링 폐기.
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"
source "$ROOT/bin/lib.sh" >/dev/null 2>&1 || true
content="$(cat "$(resolve_role_file "$ROOT/prompts" lead)")"

# 6차 게이트 3단계 (보존·핵심)
assert_contains "$content" "pending-asks" "1단계 pending-asks"
assert_contains "$content" "incidents" "2단계 incidents"
assert_contains "$content" "removal-requests" "3단계 removal-requests"
assert_contains "$content" "AskUserQuestion" "사용자 위임"
assert_contains "$content" "approve-permanent:command-group" "응답 형식"
# 6차 wake 메커니즘 (워커 고정 채널 + 단순 -S, wake-gating 없음)
assert_contains "$content" "wait-for -S" "hook wake (-S)"
assert_contains "$content" ".channel" "워커 고정 채널 필드로 wake"
# reviewer 거버넌스 보존 (회귀 방지 — spec §3.4 결함 6)
assert_contains "$content" "VIOLATION" "review VIOLATION 보존"

# ★ 6차 폐기 항목 *부재* 단언 (negative — 회귀하면 fail). assert.sh 의 (a) 헬퍼 사용.
assert_not_contains "$content" "watch-asks" "데몬 점검 폐기"
assert_not_contains "$content" ".lead-perm-cursor" "PRE 폴링 커서 폐기"
assert_not_contains "$content" "iso_to_epoch" "dedup 폐기"

test_summary
