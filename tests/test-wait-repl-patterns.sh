#!/usr/bin/env bash
# wait_repl 의 ready/negative 패턴 회귀.
#
# 2026-05-21 P2 false negative fix:
#   claude v2.1.145 상태줄에서 'bypass permissions on' 사라짐 → 옛 단일 패턴은 timeout.
#   다중 OR 매치 + negative 즉시 fail 로 회복.
#
# 본 테스트는 wait_repl 함수를 *직접* 실행하지 않고 (그 함수는 tmux pane + 60회 sleep 의존 → 느림),
# 패턴 문자열 자체에 대해 fixture 캡처로 grep 매치만 검증. 통합은 probe 가 커버.

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HARNESS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$SCRIPT_DIR/assert.sh"

# wait_repl 의 ready/negative 패턴 (team-up.sh:218,222 와 동일 — 단일 진실원).
# 변경 시 team-up.sh 와 동시 갱신 필요.
READY_PAT='Claude Code v[0-9]|Welcome back|bypass permissions on|accept edits on'
NEG_PAT='Error:|Could not authenticate|not logged in|failed to start'

# T1: ready 패턴 매치 (4 fixture).
printf '%s' "┌─── Claude Code v2.1.145 ───┐" | grep -qE "$READY_PAT"
assert_success "$?" "T1.1: ready — Claude Code v 헤더"

printf '%s' "│  Welcome back 태현!  │" | grep -qE "$READY_PAT"
assert_success "$?" "T1.2: ready — Welcome back"

printf '%s' "bypass permissions on | sonnet" | grep -qE "$READY_PAT"
assert_success "$?" "T1.3: ready — 옛 bypass permissions on (역호환)"

printf '%s' "accept edits on | model: opus" | grep -qE "$READY_PAT"
assert_success "$?" "T1.4: ready — 옛 accept edits on (역호환)"

# T2: negative 패턴 — 즉시 fail 트리거.
printf '%s' "Error: connection refused" | grep -qE "$NEG_PAT"
assert_success "$?" "T2.1: negative — Error:"

printf '%s' "Could not authenticate. Run claude login." | grep -qE "$NEG_PAT"
assert_success "$?" "T2.2: negative — Could not authenticate"

printf '%s' "Error: not logged in" | grep -qE "$NEG_PAT"
assert_success "$?" "T2.3: negative — not logged in"

# T3: false positive 가드 — 빈 셸 / 일반 출력은 ready 매치 안 됨.
printf '%s' "(base) 🐍 base taehyunan@MacBook-Pro-2 ~/Desktop main " | grep -qE "$READY_PAT"
assert_fail "$?" "T3.1: false positive 가드 — 빈 셸"

printf '%s' "$ ls -la
total 0
drwxr-xr-x 2 user staff 64 May 21 ." | grep -qE "$READY_PAT"
assert_fail "$?" "T3.2: false positive 가드 — 일반 ls 출력"

# T4: 실제 final 캡처 시뮬레이션 (probe-cold-start-diag 결과 기반).
ORCH_FIXTURE="$(cat <<'EOF'
╭─── Claude Code v2.1.145 ───╮
│   Welcome back 태현!   │
│   Opus 4.7 · Claude Max  │
╰────────────────────────────╯
❯ /agent-harness/.boot/ORCHESTRATOR.md 를 읽고
EOF
)"
printf '%s' "$ORCH_FIXTURE" | grep -qE "$READY_PAT"
assert_success "$?" "T4: 실제 final 캡처 (orchestrator) ready 매치"

# T5: team-up.sh 안 wait_repl 함수에 옛 단일 패턴 잔존 없음 (회귀 가드).
# 'grep -q' (옵션 q 만, E 없음) + 'bypass permissions on' 단일 조합이 없어야 함.
WAIT_REPL_BODY="$(awk '/^wait_repl\(\)/,/^}/' "$HARNESS_ROOT/bin/team-up.sh")"
printf '%s' "$WAIT_REPL_BODY" | grep -E "grep -q 'bypass permissions on'$"
assert_fail "$?" "T5: wait_repl 안 옛 단일 패턴 잔존 없음"

# T6: 새 ready 다중 OR 패턴이 wait_repl 안에 있음.
printf '%s' "$WAIT_REPL_BODY" | grep -qE "Claude Code v\\[0-9\\].*Welcome back|Welcome back.*Claude Code v\\[0-9\\]"
assert_success "$?" "T6: 새 ready 다중 패턴 존재"

# T7: negative 패턴이 wait_repl 안에 있음.
printf '%s' "$WAIT_REPL_BODY" | grep -qE 'Could not authenticate|not logged in'
assert_success "$?" "T7: negative 패턴 존재"

test_summary
