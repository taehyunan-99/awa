#!/usr/bin/env bash
# lead.md 에 5차 사이클 통합 처리 + dedup + watch-asks 점검 포함.
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"
content="$(cat "$ROOT/prompts/loop/lead.md")"

# 기존 4차 P0 보존
assert_contains "$content" "권한 이벤트 감지" "4차 P0 섹션 보존"
assert_contains "$content" ".lead-perm-cursor" "4차 P0 커서 보존"

# 5차 사이클
assert_contains "$content" "사이클 통합 처리" "5차 사이클 섹션"
assert_contains "$content" "pending-asks" "1단계 pending-asks"
assert_contains "$content" "incidents" "3단계 incidents"
assert_contains "$content" "removal-requests" "4단계 removal-requests"
assert_contains "$content" "AskUserQuestion" "사용자 위임"
assert_contains "$content" "approve-permanent:command-group" "응답 형식"
# dedup
assert_contains "$content" "iso_to_epoch" "ISO→epoch 변환"
assert_contains "$content" "60" "60s 윈도우"
assert_contains "$content" "notified" "incident dedup notified"
# watch-asks 점검
assert_contains "$content" "watch-asks.pid" "데몬 점검"
assert_contains "$content" "kill -0" "데몬 살아있음 확인"

test_summary
