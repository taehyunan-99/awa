#!/usr/bin/env bash
# tests/test-criterion-gate.sh — criterion 입자도 게이트 (회로② 1차)
# Layer 1: orch.md ⓑ 가 criterion 크기(effort budget 내 done 가능) 검증을 명시
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
source ./harness-paths.sh
ROOT="$(cd .. && pwd)"
ORCH="$HARNESS_PROMPTS/roles/01-orchestration/orch.md"

# criterion 입자도 게이트 — 게이트 의미(criterion + budget/done 가능 크기)를 좁혀 검증.
# 느슨한 '입자도' 단독 매치(무관 문맥, M10)나 주석화(HTML 주석, M6b)로 무력화되는 것 방지.
grep -qE 'criterion 입자도 게이트' "$ORCH"
assert_success "$?" "L1 orch.md ⓑ 가 'criterion 입자도 게이트' 명시(좁은 패턴)"
grep -qE 'budget.*done|done 가능' "$ORCH"
assert_success "$?" "L1 게이트가 budget 내 done 가능 크기 점검을 명시"
# 게이트 문장이 HTML 주석(<!-- -->)으로 비활성화되지 않았는지
! grep -qE '<!--.*criterion 입자도' "$ORCH"
assert_success "$?" "L1 criterion 게이트가 주석화로 비활성화되지 않음"

test_summary
