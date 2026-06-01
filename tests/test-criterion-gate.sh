#!/usr/bin/env bash
# tests/test-criterion-gate.sh — criterion 입자도 게이트 (회로② 1차)
# Layer 1: lead.md ⓑ 가 criterion 크기(effort budget 내 done 가능) 검증을 명시
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"
LEAD="$ROOT/prompts/roles/01-orchestration/lead.md"

grep -qE 'criterion.*budget|budget 내 done|입자도' "$LEAD"
assert_success "$?" "L1 lead.md ⓑ 가 criterion 입자도(budget 내 done 가능) 게이트 명시"

test_summary
