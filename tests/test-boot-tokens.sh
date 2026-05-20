#!/usr/bin/env bash
# T3 회귀: bootstrap_pane 이 {{HARNESS_ROOT}} 토큰을 절대경로로 치환.
# AGENT_CMD=cat 으로 team-up 실행 → .boot/<worker>.md 파일 검사.
# 워커·오케스트레이터·리뷰어 3종 boot 모두 sed 치환·토큰 검증 통과 확인.
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh

ROOT="$(cd .. && pwd)"
SESSION="t-boot-tokens-$$"
TMP_PROJ="$(mktemp -d)"
( cd "$TMP_PROJ" && git init -q )
FIX_BASE="$(mktemp -d)"
FIX_PROMPTS="$FIX_BASE/prompts"

cleanup() {
  tmux kill-session -t "$SESSION" 2>/dev/null || true
  [ -n "${TMP_PROJ:-}" ] && rm -rf "$TMP_PROJ"
  [ -n "${FIX_BASE:-}" ] && rm -rf "$FIX_BASE"
}
trap cleanup EXIT

# fixture: HARNESS_ROOT 의 prompts/ 복사 후 토큰 박힌 role 들 추가.
cp -r "$ROOT/prompts" "$FIX_PROMPTS"

# 워커용 test-role: {{HARNESS_ROOT}} 토큰 박기.
cat > "$FIX_PROMPTS/roles/test-role.md" <<'EOF'
# Test Role
도구는 {{HARNESS_ROOT}}/bin/dispatch.sh 절대경로로 호출.
EOF

# 리뷰어용 test-reviewer: {{HARNESS_ROOT}} 토큰 박기.
cat > "$FIX_PROMPTS/roles/test-reviewer.md" <<'EOF'
# Test Reviewer
리뷰는 {{HARNESS_ROOT}}/bin/log-event.sh 를 기준으로 한다.
EOF

# 오케 boot 도 토큰 검증 — orchestrator.md 사본에 {{HARNESS_ROOT}} 박기 (fixture 만).
cat >> "$FIX_PROMPTS/roles/orchestrator.md" <<'EOF'

## (fixture) 토큰 검증
dispatch: {{HARNESS_ROOT}}/bin/dispatch.sh
EOF

# 임시 profile — WORKERS + REVIEWERS 모두 정의.
PROF="$TMP_PROJ/profile.sh"
cat > "$PROF" <<'EOF'
LAYOUT=tiled
WORKERS=("dev:test-role")
REVIEWERS=("rev:test-reviewer")
ORCHESTRATOR_MODEL=sonnet
EOF

# team-up 호출 (AGENT_CMD=cat 더미).
export SESSION_OVERRIDE="$SESSION"
export HARNESS_PROJECT="$TMP_PROJ"
export AGENT_CMD="cat"
export PROMPTS_DIR="$FIX_PROMPTS"

bash "$ROOT/bin/team-up.sh" "$PROF" >/tmp/_t-boot-tokens-out.log 2>/tmp/_t-boot-tokens-err.log
rc=$?
assert_eq "0" "$rc" "team-up 성공 (rc=$rc, err=$(head -3 /tmp/_t-boot-tokens-err.log 2>/dev/null))"

WORKER_BOOT="$TMP_PROJ/.agent-harness/.boot/dev.md"
ORCH_BOOT="$TMP_PROJ/.agent-harness/.boot/ORCHESTRATOR.md"
REV_BOOT="$TMP_PROJ/.agent-harness/.boot/rev.md"

# T3.1: 워커 boot — 예약 토큰 잔존 0 + 절대경로 dispatch 등장.
if [ ! -f "$WORKER_BOOT" ]; then
  assert_eq "exists" "missing" "워커 boot 파일 존재 (stderr=$(cat /tmp/_t-boot-tokens-err.log))"
else
  if grep -qE '\{\{(WORKER_NAME|SESSION|HARNESS_ROOT)\}\}' "$WORKER_BOOT"; then
    assert_eq "no-tokens-remaining" "tokens-remaining" "워커 boot: 예약 토큰 잔존"
  else
    assert_eq "no-tokens-remaining" "no-tokens-remaining" "워커 boot: 모든 예약 토큰 치환됨"
  fi
  if grep -qF "$ROOT/bin/dispatch.sh" "$WORKER_BOOT"; then
    assert_eq "abs-path-present" "abs-path-present" "워커 boot: 절대경로 dispatch.sh 등장"
  else
    assert_eq "abs-path-present" "abs-path-missing" "워커 boot: 절대경로 dispatch.sh 등장 — 첫 5줄: $(head -5 "$WORKER_BOOT")"
  fi
fi

# T3.2: 오케스트레이터 boot — 예약 토큰 잔존 0 + 절대경로 dispatch 등장 (fixture 박은 토큰).
if [ ! -f "$ORCH_BOOT" ]; then
  assert_eq "exists" "missing" "오케 boot 파일 존재 (stderr=$(cat /tmp/_t-boot-tokens-err.log))"
else
  if grep -qE '\{\{(WORKER_NAME|SESSION|HARNESS_ROOT)\}\}' "$ORCH_BOOT"; then
    assert_eq "no-tokens-remaining" "tokens-remaining" "오케 boot: 예약 토큰 잔존"
  else
    assert_eq "no-tokens-remaining" "no-tokens-remaining" "오케 boot: 모든 예약 토큰 치환됨"
  fi
  if grep -qF "$ROOT/bin/dispatch.sh" "$ORCH_BOOT"; then
    assert_eq "abs-path-present" "abs-path-present" "오케 boot: 절대경로 dispatch.sh 등장"
  else
    assert_eq "abs-path-present" "abs-path-missing" "오케 boot: 절대경로 dispatch.sh 등장 — 첫 5줄: $(head -5 "$ORCH_BOOT")"
  fi
fi

# T3.3: 리뷰어 boot — 예약 토큰 잔존 0 + 절대경로 log-event 등장.
if [ ! -f "$REV_BOOT" ]; then
  assert_eq "exists" "missing" "리뷰어 boot 파일 존재 (stderr=$(cat /tmp/_t-boot-tokens-err.log))"
else
  if grep -qE '\{\{(WORKER_NAME|SESSION|HARNESS_ROOT)\}\}' "$REV_BOOT"; then
    assert_eq "no-tokens-remaining" "tokens-remaining" "리뷰어 boot: 예약 토큰 잔존"
  else
    assert_eq "no-tokens-remaining" "no-tokens-remaining" "리뷰어 boot: 모든 예약 토큰 치환됨"
  fi
  if grep -qF "$ROOT/bin/log-event.sh" "$REV_BOOT"; then
    assert_eq "abs-path-present" "abs-path-present" "리뷰어 boot: 절대경로 log-event.sh 등장"
  else
    assert_eq "abs-path-present" "abs-path-missing" "리뷰어 boot: 절대경로 log-event.sh 등장 — 첫 5줄: $(head -5 "$REV_BOOT")"
  fi
fi

test_summary
