#!/usr/bin/env bash
# watcher 의 @done ack 큐(pending-done/) 재발화 회귀.
# 결함(2026-06-01 라이브 e2e): watcher 가 done 라인 감지 시 @done 을 LEAD 에 send-keys 한 번만 쏘고 끝.
# LEAD 가 점유(작업/모달) 중이면 그 입력이 TUI 에서 소실 → last_events 는 이미 올라가 영영 재발화 안 함
# → 종합 트리거 유실(회로① 침묵). parity-001 때 사용자 명시 깨움이 필요했던 근본 원인.
# 수정: done 발화 시 pending-done/<worker>__<task>.json 적재(ack 큐) + 매 사이클 미해소분 재발화.
#   LEAD 는 종합 완료 후 그 .json 을 rm(ack) → 큐 소비. ack 없으면 재발화 지속(LEAD idle 복귀 시 도달).
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"
# shellcheck disable=SC1091
source "$ROOT/bin/watcher-lib.sh"

# ── Layer 1: 함수/큐 디렉토리 계약 존재 (grep) ──────────────────────────────
echo "[L1] watcher-lib.sh 에 큐 적재/재발화 함수 존재"
assert_success "$(grep -q 'enqueue_pending_done' "$ROOT/bin/watcher-lib.sh"; echo $?)" \
  "L1a enqueue_pending_done 정의"
assert_success "$(grep -q 'requeue_pending_done' "$ROOT/bin/watcher-lib.sh"; echo $?)" \
  "L1b requeue_pending_done 정의"
echo "[L1] watcher.sh 가 두 함수를 메인 루프에서 호출"
assert_success "$(grep -q 'enqueue_pending_done' "$ROOT/bin/watcher.sh"; echo $?)" \
  "L1c watcher.sh enqueue 호출"
assert_success "$(grep -q 'requeue_pending_done' "$ROOT/bin/watcher.sh"; echo $?)" \
  "L1d watcher.sh requeue 호출"
echo "[L1] orch.md ⓒ 가 종합 후 pending-done ack(rm) 의무 명시"
assert_success "$(grep -q 'pending-done' "$ROOT/prompts/roles/01-orchestration/orch.md"; echo $?)" \
  "L1e orch.md pending-done ack 명시"

# ── Layer 2: 실제 동작 (큐 적재 → 재발화 → ack 소비) ────────────────────────
PT="$(mktemp -d)"
trap 'rm -rf "$PT"' EXIT
SD="$PT/.agent-harness/state"
mkdir -p "$SD/pending-done"

echo "[L2-A] enqueue_pending_done: done 1건 → pending-done/<worker>__<task>.json 적재(atomic)"
enqueue_pending_done "$SD" "engineer" "parity-001"
assert_success "$([ -f "$SD/pending-done/engineer__parity-001.json" ]; echo $?)" \
  "A1 큐 파일 생성됨"
# .tmp 잔재 없음(atomic mv 확인)
assert_eq "0" "$(find "$SD/pending-done" -name '*.tmp' | wc -l | tr -d ' ')" \
  "A2 .tmp 잔재 없음(atomic)"
# 내용에 worker/task 포함
content="$(cat "$SD/pending-done/engineer__parity-001.json")"
assert_contains "$content" "engineer" "A3 worker 포함"
assert_contains "$content" "parity-001" "A4 task 포함"

echo "[L2-B] enqueue 멱등: 같은 done 재적재해도 1개 유지(중복 큐 방지)"
enqueue_pending_done "$SD" "engineer" "parity-001"
assert_eq "1" "$(find "$SD/pending-done" -name 'engineer__parity-001.json' | wc -l | tr -d ' ')" \
  "B1 중복 적재 안 됨"

echo "[L2-C] requeue_pending_done: 미해소(나이≥임계) 큐 → 재발화 대상 목록 emit"
# mtime 을 과거로 밀어 나이 임계 초과 모사(touch -t). REQUEUE_AGE 기본 20s.
touch -t 202001010000 "$SD/pending-done/engineer__parity-001.json"
out="$(requeue_pending_done "$SD" 20)"
assert_contains "$out" "engineer/parity-001" "C1 임계 초과 큐 재발화 emit"

echo "[L2-D] requeue: 갓 적재된(나이<임계) 큐 → 재발화 안 함(디바운스)"
# C1 에서 parity-001 을 emit 하며 touch 로 mtime 갱신 → 이제 신규나 다름없어 디바운스(의도).
enqueue_pending_done "$SD" "researcher" "survey-001"   # 방금 적재 → 나이 0
out="$(requeue_pending_done "$SD" 20)"
assert_not_contains "$out" "researcher/survey-001" "D1 신규 큐 재발화 제외(디바운스)"
assert_not_contains "$out" "engineer/parity-001" "D2 직전 emit 큐도 재디바운스(폭주 방지)"

echo "[L2-E] ack(rm) 후 재발화 중단 — LEAD 종합 완료 모사"
rm -f "$SD/pending-done/engineer__parity-001.json"
touch -t 202001010000 "$SD/pending-done/researcher__survey-001.json"  # researcher 도 늙힘
out="$(requeue_pending_done "$SD" 20)"
assert_not_contains "$out" "engineer/parity-001" "E1 ack 된 큐 재발화 중단"
assert_contains "$out" "researcher/survey-001" "E2 미ack 큐는 계속 emit"

echo "[L2-F] task-id 에 __ 안전성: enqueue 파일명 구분자 충돌 회피"
# worker/task 에 '/' 가 들어오면 파일명 깨짐 → enqueue 가 sanitize 하거나 거부해야.
enqueue_pending_done "$SD" "engineer" "sub/task-001"
# '/' 가 그대로 파일명에 들어가면 디렉토리 생성 시도로 실패. sanitize 된 단일 파일이어야.
bad="$(find "$SD/pending-done" -type d -name 'sub' 2>/dev/null | wc -l | tr -d ' ')"
assert_eq "0" "$bad" "F1 task-id 의 / 가 디렉토리 깨짐 유발 안 함(sanitize)"

test_summary
