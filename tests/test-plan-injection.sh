#!/usr/bin/env bash
# --plan 인자 파싱·plan 합본 생성·하위호환 검증 (AGENT_CMD=cat 더미).
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh

ROOT="$(cd .. && pwd)"
export AGENT_CMD="cat"

# 격리 PROJECT_ROOT + plan 파일 2개.
PROJ="$(mktemp -d)"; ( cd "$PROJ" && git init -q )
PLAN_A="$PROJ/PRD.md"
PLAN_B="$PROJ/ARCH.md"
printf '# PRD\nplan A 내용\n' > "$PLAN_A"
printf '# ARCH\nplan B 내용\n' > "$PLAN_B"
SES="$(HARNESS_PROJECT="$PROJ" bash -c "source $ROOT/bin/lib.sh; resolve_session")"
cleanup() { tmux kill-session -t "$SES" 2>/dev/null || true; rm -rf "$PROJ"; }
trap cleanup EXIT

PLAN_BOOT="$PROJ/.agent-harness/.boot/plan.md"

# 케이스 1: --plan 단일 → 합본 생성 + 고정 식별 헤더 + 파일 내용 포함.
# rc 먼저 검증 — "합본 미생성" 과 "team-up 자체 실패" 를 구분(진단성, test-boot-tokens 패턴).
bash "$ROOT/bin/team-up.sh" --project "$PROJ" --plan "$PLAN_A" default >/tmp/_t-plan-out.log 2>/tmp/_t-plan-err.log
rc=$?
assert_eq "0" "$rc" "--plan 단일: team-up 성공 (rc=$rc, err=$(head -3 /tmp/_t-plan-err.log 2>/dev/null))"
sleep 0.8
[ -f "$PLAN_BOOT" ]
assert_success "$?" "--plan 단일: plan 합본 생성"
grep -qF "확정 plan (이번 가동의 작업 계획)" "$PLAN_BOOT"
assert_success "$?" "--plan 단일: 고정 식별 헤더 존재"
grep -qF "plan A 내용" "$PLAN_BOOT"
assert_success "$?" "--plan 단일: PLAN_A 내용 포함"
bash "$ROOT/bin/team-down.sh" --project "$PROJ" >/dev/null 2>&1

# 케이스 2: --plan 반복 → 합본에 두 파일 순서대로 + 파일명 헤더.
bash "$ROOT/bin/team-up.sh" --project "$PROJ" --plan "$PLAN_A" --plan "$PLAN_B" default >/dev/null 2>&1
sleep 0.8
grep -qF "plan A 내용" "$PLAN_BOOT" && grep -qF "plan B 내용" "$PLAN_BOOT"
assert_success "$?" "--plan 반복: 두 plan 내용 모두 포함"
grep -qF "## PRD.md" "$PLAN_BOOT"
assert_success "$?" "--plan 반복: 파일명 헤더(## PRD.md) 존재"
# 순서: PLAN_A(PRD) 줄번호 < PLAN_B(ARCH) 줄번호
la="$(grep -nF 'plan A 내용' "$PLAN_BOOT" | head -1 | cut -d: -f1)"
lb="$(grep -nF 'plan B 내용' "$PLAN_BOOT" | head -1 | cut -d: -f1)"
[ "$la" -lt "$lb" ]
assert_success "$?" "--plan 반복: 전달 순서 보존 (A 먼저)"
bash "$ROOT/bin/team-down.sh" --project "$PROJ" >/dev/null 2>&1

# 케이스 3: --plan 이 프로파일명 뒤 (순서 무관 — --project 와 같은 루프).
bash "$ROOT/bin/team-up.sh" default --project "$PROJ" --plan "$PLAN_A" >/dev/null 2>&1
sleep 0.8
[ -f "$PLAN_BOOT" ]
assert_success "$?" "--plan 순서무관: 프로파일명 뒤에서도 합본 생성"
bash "$ROOT/bin/team-down.sh" --project "$PROJ" >/dev/null 2>&1

# 케이스 4: --plan 없이 가동 (하위호환) → plan 합본 미생성.
bash "$ROOT/bin/team-up.sh" --project "$PROJ" default >/dev/null 2>&1
sleep 0.8
[ ! -f "$PLAN_BOOT" ]
assert_success "$?" "--plan 없음: plan 합본 미생성 (하위호환)"
bash "$ROOT/bin/team-down.sh" --project "$PROJ" >/dev/null 2>&1

# 케이스 5: --plan 비존재 파일 → 오류 (비-0).
bash "$ROOT/bin/team-up.sh" --project "$PROJ" --plan /nonexistent/xyz.md default 2>/dev/null
assert_fail "$?" "--plan 비존재 파일 → 비-0 종료"

# 케이스 6: --plan 값 누락 → 오류 (비-0).
bash "$ROOT/bin/team-up.sh" --project "$PROJ" --plan 2>/dev/null
assert_fail "$?" "--plan 값 누락 → 비-0 종료"

# 케이스 7: team-down 이 --plan 을 받아도 오류 없이 무시 (인자 대칭).
bash "$ROOT/bin/team-up.sh" --project "$PROJ" --plan "$PLAN_A" default >/dev/null 2>&1
sleep 0.8
bash "$ROOT/bin/team-down.sh" --project "$PROJ" --plan "$PLAN_A" >/dev/null 2>&1
assert_success "$?" "team-down --plan: 미지옵션 오류 없이 무시 (대칭)"

test_summary
