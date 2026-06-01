#!/usr/bin/env bash
# tests/test-block-guard.sh — dispatch 차단 가드 (회로① 합의 게이트 집행)
# Layer 1: lead.md ⓒ 합의 분기 + dispatch.sh 가드 호출 grep
# Layer 2: lib.sh is_worker_blocked/record_block/clear_block/quarantine_block 동작
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

# lib.sh source (STATE_DIR 을 TMPDIR 로 격리)
source "$ROOT/bin/lib.sh"
STATE_DIR="$TMPDIR/state"   # 운영 state 오염 차단

# Layer 2-a: 차단 없으면 is_worker_blocked = 1 (비차단=rc 1)
is_worker_blocked "dev"
assert_eq "1" "$?" "L2 비차단 워커는 rc 1 (dispatch 허용)"

# Layer 2-b: record_block 후 is_worker_blocked = 0 (차단=rc 0)
record_block "dev" "T3" "보안 VIOLATION 만장일치"
assert_success "$?" "L2 record_block 성공"
test -f "$STATE_DIR/blocked-workers/dev.json"
assert_success "$?" "L2 blocked-workers/dev.json 생성됨"
is_worker_blocked "dev"
assert_eq "0" "$?" "L2 차단 워커는 rc 0 (dispatch 거부)"

# Layer 2-c: attempt 카운터 증가 (재차단)
record_block "dev" "T3" "재판정도 VIOLATION"
att="$(jq -r '.attempt' "$STATE_DIR/blocked-workers/dev.json")"
assert_eq "2" "$att" "L2 재 record_block 시 attempt=2"

# Layer 2-d: clear_block 후 비차단 복귀
clear_block "dev"
assert_success "$?" "L2 clear_block 성공"
is_worker_blocked "dev"
assert_eq "1" "$?" "L2 clear 후 비차단 (dispatch 재허용)"

# Layer 2-e: quarantine — attempt>=K 시 격리 큐로 이동
record_block "alice" "T9" "1차"
record_block "alice" "T9" "2차 (K=2 도달)"
quarantine_block "alice"
assert_success "$?" "L2 quarantine_block 성공"
test -f "$STATE_DIR/quarantine/alice.json"
assert_success "$?" "L2 quarantine/alice.json 으로 이동됨"
test ! -f "$STATE_DIR/blocked-workers/alice.json"
assert_success "$?" "L2 격리 후 blocked-workers 에서 제거됨"
is_worker_blocked "alice"
assert_eq "1" "$?" "L2 격리된 워커는 blocked-workers 비어 비차단 (다른 task 진행 가능)"

# Layer 2-f: BLOCK_RETRY_LIMIT 상수 노출
assert_eq "2" "$BLOCK_RETRY_LIMIT" "L2 BLOCK_RETRY_LIMIT=2 상수"

test_summary
