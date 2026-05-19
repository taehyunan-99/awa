#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh

ROOT="$(cd .. && pwd)"

source "$ROOT/profiles/default.sh"
assert_eq "agents" "$SESSION" "default SESSION"
assert_eq "tiled" "$LAYOUT" "default LAYOUT"
assert_eq "2" "${#WORKERS[@]}" "default 워커 2개(reviewer 워커 제거·일원화)"
assert_eq "dev:dev" "${WORKERS[0]}" "default 첫 워커"

source "$ROOT/profiles/code-review.sh"
assert_eq "1" "${#WORKERS[@]}" "code-review 워커 1개(reviewer 워커 제거·일원화)"
assert_contains "${WORKERS[*]}" "security" "code-review 에 security 포함"

source "$ROOT/profiles/research.sh"
assert_eq "3" "${#WORKERS[@]}" "research 워커 3개"

for f in _common roles/dev roles/tester roles/security roles/researcher roles/orchestrator roles/reviewer-spec roles/reviewer-quality roles/reviewer-arch; do
  [ -f "$ROOT/prompts/$f.md" ]; assert_success "$?" "prompts/$f.md 존재"
done

COMMON="$(cat "$ROOT/prompts/_common.md")"
assert_contains "$COMMON" '{{WORKER_NAME}}' "_common 에 치환 토큰"
assert_contains "$COMMON" 'wait-for -S done-{{WORKER_NAME}}' "_common 에 완료 신호 규약"
assert_contains "$COMMON" 'workspace/tasks/' "_common 에 tasks 읽기 규약"

test_summary
