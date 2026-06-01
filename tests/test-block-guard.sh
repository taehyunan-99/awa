#!/usr/bin/env bash
# tests/test-block-guard.sh — dispatch 차단 가드 (회로① 합의 게이트 집행)
# Layer 1: lead.md ⓒ 합의 분기 + dispatch.sh 가드 호출 grep (Task 2/4 에서 추가)
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

# Layer 2-c2: 손상 attempt (비숫자) 회귀 — set -u 치명사 안 나고 1 로 복구 후 ++
printf '{"worker":"carol","task_id":"T5","attempt":"corrupt","reason":"x"}' > "$STATE_DIR/blocked-workers/carol.json" 2>/dev/null || { mkdir -p "$STATE_DIR/blocked-workers"; printf '{"worker":"carol","task_id":"T5","attempt":"corrupt","reason":"x"}' > "$STATE_DIR/blocked-workers/carol.json"; }
record_block "carol" "T5" "손상 후 재기록"
assert_success "$?" "L2 손상 attempt 에도 record_block 성공(치명사 없음)"
att2="$(jq -r '.attempt' "$STATE_DIR/blocked-workers/carol.json")"
assert_eq "2" "$att2" "L2 손상 attempt 는 1 로 복구 후 ++ → 2"

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

# Layer 1: dispatch.sh 가 send 전 is_worker_blocked 가드를 호출하는가
grep -q 'is_worker_blocked' "$ROOT/bin/dispatch.sh"
assert_success "$?" "L1 dispatch.sh 가 is_worker_blocked 가드 호출"
# 가드가 write_harness_task/send_prompt *앞* 에 와야 차단이 dispatch 를 막는다
guard_ln="$(grep -n 'is_worker_blocked' "$ROOT/bin/dispatch.sh" | head -1 | cut -d: -f1)"
send_ln="$(grep -n 'send_prompt' "$ROOT/bin/dispatch.sh" | head -1 | cut -d: -f1)"
[ -n "$guard_ln" ] && [ -n "$send_ln" ] && [ "$guard_ln" -lt "$send_ln" ]
assert_success "$?" "L1 가드가 send_prompt 앞에 위치 (차단이 송신을 막음)"
# 가드가 TARGET 페인 탐색(TASK_FILE 확인 포함) *앞* 이어야 차단이 페인 존재와 독립 (통지 루프 방지)
taskfile_ln="$(grep -n 'TASK_FILE=' "$ROOT/bin/dispatch.sh" | head -1 | cut -d: -f1)"
[ -n "$guard_ln" ] && [ -n "$taskfile_ln" ] && [ "$guard_ln" -lt "$taskfile_ln" ]
assert_success "$?" "L1 가드가 TASK_FILE/페인 탐색 앞 (차단이 페인 존재와 독립)"

# Layer 1: watcher.sh 가 dispatch exit 2(차단)를 @dispatch-fail 로 오인하지 않는가
grep -qE '_dq_rc.*=.*2|= "2"' "$ROOT/bin/watcher.sh"
assert_success "$?" "L1 watcher 가 exit 2(차단)를 별도 분기로 skip"

# Layer 2-g: 전체 흐름 — 차단 → 재판정 OK 해소 → 다시 차단 누적 → 격리
clear_block "bob"; quarantine_block "bob" 2>/dev/null || true
record_block "bob" "T1" "1차 차단"
is_worker_blocked "bob"; assert_eq "0" "$?" "L2 흐름: 1차 차단됨"
clear_block "bob"
is_worker_blocked "bob"; assert_eq "1" "$?" "L2 흐름: 재판정 OK 로 해소"
# 다시 문제 → K 도달까지 누적
record_block "bob" "T1" "재발 1"
record_block "bob" "T1" "재발 2"
att="$(jq -r '.attempt' "$TMPDIR/state/blocked-workers/bob.json")"
[ "$att" -ge "$BLOCK_RETRY_LIMIT" ]
assert_success "$?" "L2 흐름: attempt($att) >= K($BLOCK_RETRY_LIMIT) — 격리 조건 충족"
quarantine_block "bob"
is_worker_blocked "bob"; assert_eq "1" "$?" "L2 흐름: 격리 후 워커는 다른 task dispatch 가능"
test -f "$TMPDIR/state/quarantine/bob.json"
assert_success "$?" "L2 흐름: 격리 task 는 quarantine 에 보존 (LEAD 가 사용자 push)"

# Layer 1: lead.md ⓒ 가 합의 게이트(만장일치 record_block / 불일치 push)를 명시
grep -q 'record_block' "$ROOT/prompts/roles/01-orchestration/lead.md"
assert_success "$?" "L1 lead.md 가 record_block 호출 명시"
grep -qE '만장일치|전원 blocking|투표인단' "$ROOT/prompts/roles/01-orchestration/lead.md"
assert_success "$?" "L1 lead.md 가 합의 게이트(만장일치) 분기 명시"
grep -q 'clear_block' "$ROOT/prompts/roles/01-orchestration/lead.md"
assert_success "$?" "L1 lead.md 가 재판정 OK 해소(clear_block) 명시"

test_summary
