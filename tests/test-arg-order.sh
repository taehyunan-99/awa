#!/usr/bin/env bash
# --project 인자 순서(앞/뒤) 양방향 동작 검증 — 결함 C 수정 확인.
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh

ROOT="$(cd .. && pwd)"
export AGENT_CMD="cat"

# 두 개의 격리 PROJECT_ROOT — 각각 다른 위치로 --project 전달.
PROJ_A="$(mktemp -d)"; ( cd "$PROJ_A" && git init -q )
PROJ_B="$(mktemp -d)"; ( cd "$PROJ_B" && git init -q )
cleanup() {
  # 두 세션 모두 정리 시도 (resolve_session 은 PROJECT_ROOT basename 기반).
  for p in "$PROJ_A" "$PROJ_B"; do
    s="$(HARNESS_PROJECT="$p" bash -c "source $ROOT/bin/lib.sh; resolve_session" 2>/dev/null || true)"
    [ -n "$s" ] && tmux kill-session -t "$s" 2>/dev/null || true
  done
  rm -rf "$PROJ_A" "$PROJ_B"
}
trap cleanup EXIT

SES_A="$(HARNESS_PROJECT="$PROJ_A" bash -c "source $ROOT/bin/lib.sh; resolve_session")"
SES_B="$(HARNESS_PROJECT="$PROJ_B" bash -c "source $ROOT/bin/lib.sh; resolve_session")"

# 케이스 1: --project 가 프로파일명 앞 (기존에도 됨)
bash "$ROOT/bin/agenphony-up.sh" --project "$PROJ_A" default >/dev/null 2>&1
sleep 0.8  # agenphony-up 의 .agent-harness 마커 생성 여유 (저사양/CI 간헐 실패 방어)
tmux has-session -t "$SES_A" 2>/dev/null
assert_success "$?" "--project 앞: 세션 $SES_A 생성"
# .agent-harness 가 PROJ_A 안에 생성됐는지 (PROJECT_ROOT 인식 증거)
[ -d "$PROJ_A/.agent-harness" ]
assert_success "$?" "--project 앞: PROJ_A 에 .agent-harness"
bash "$ROOT/bin/agenphony-down.sh" --project "$PROJ_A" >/dev/null 2>&1

# 케이스 2: --project 가 프로파일명 뒤 (결함 C — 예전엔 무시됨)
bash "$ROOT/bin/agenphony-up.sh" default --project "$PROJ_B" >/dev/null 2>&1
sleep 0.8  # agenphony-up 의 .agent-harness 마커 생성 여유 (저사양/CI 간헐 실패 방어)
tmux has-session -t "$SES_B" 2>/dev/null
assert_success "$?" "--project 뒤: 세션 $SES_B 생성 (결함 C 수정)"
[ -d "$PROJ_B/.agent-harness" ]
assert_success "$?" "--project 뒤: PROJ_B 에 .agent-harness (PWD 아님)"
bash "$ROOT/bin/agenphony-down.sh" default --project "$PROJ_B" >/dev/null 2>&1
tmux has-session -t "$SES_B" 2>/dev/null
assert_fail "$?" "--project 뒤: agenphony-down 으로 세션 종료 (결함 C 양방향)"

# 케이스 3: --project 인자 누락 → 오류
bash "$ROOT/bin/agenphony-up.sh" --project 2>/dev/null
assert_fail "$?" "--project 값 누락 → 비-0 종료"

# 케이스 4: --project 경로 없음 → 오류
bash "$ROOT/bin/agenphony-up.sh" --project /nonexistent/path/xyz 2>/dev/null
assert_fail "$?" "--project 경로 없음 → 비-0 종료"

# 케이스 5: 등호형 --project=/path (분리형과 동등 동작)
PROJ_C="$(mktemp -d)"; ( cd "$PROJ_C" && git init -q )
SES_C="$(HARNESS_PROJECT="$PROJ_C" bash -c "source $ROOT/bin/lib.sh; resolve_session")"
bash "$ROOT/bin/agenphony-up.sh" "default" "--project=$PROJ_C" >/dev/null 2>&1
sleep 0.8
tmux has-session -t "$SES_C" 2>/dev/null
assert_success "$?" "등호형 --project=/path: 세션 $SES_C 생성"
[ -d "$PROJ_C/.agent-harness" ]
assert_success "$?" "등호형 --project=/path: PROJ_C 에 .agent-harness"
bash "$ROOT/bin/agenphony-down.sh" "--project=$PROJ_C" >/dev/null 2>&1
tmux kill-session -t "$SES_C" 2>/dev/null || true
rm -rf "$PROJ_C"

# 케이스 6: 알 수 없는 옵션(-*) → 즉시 거부 (오타 침묵 무시 방지)
bash "$ROOT/bin/agenphony-up.sh" --bogus-flag 2>/dev/null
assert_fail "$?" "미지 옵션 --bogus-flag → 비-0 종료"

test_summary
