#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"

echo "[R1] 제거 대상 잔존 0건"
# 검사 범위: .md/.sh, 단 메타 영역 제외:
#   - spec/plan 자체 (이번 사이클의 설계 문서)
#   - memory/ (외부 메모리)
#   - SKILL.md (deprecated 안내 의도적 박음)
#   - tests/15th-live-checklist.md (deprecated 검증 시나리오)
#   - tests/test-window-layout.sh (14차 메타 주석 — 10차 리뷰 [MAJOR-30] YAGNI)
#   - tests/test-rename-guard-15th.sh (이 파일 자체 — 패턴 문자열 정의가 self-match)
#   - 11차 [MAJOR-33]: list.sh 가 본 task 시점에 아직 살아있어 코드/문서 참조 잔존
#     (Task 9 가 list.sh 함께 정리). 본 가드는 user-facing /agpn 서브커맨드 잔존
#     검출이 목적이므로 list.sh 코드 영역(up.sh 주석, bin/AGENTS.md 인벤토리,
#     test-agenphony-list.sh, window-layout-live-checklist.md) 도 함께 제외.
# 6차 리뷰 [MINOR-6]·10차 리뷰 [MAJOR-30] 통합 보강.
patterns=(
  "/agpn plan"
  "/agpn stage"
  "/agpn list"
  "agenphony-list"
)
for p in "${patterns[@]}"; do
  hits=$(grep -rln --include='*.md' --include='*.sh' -F "$p" "$ROOT" 2>/dev/null \
    | grep -vE 'docs/superpowers/(specs|plans)/2026-05-27-agpn-' \
    | grep -vE 'memory/' \
    | grep -vE '\.claude/skills/agpn/SKILL\.md$' \
    | grep -vE 'tests/15th-live-checklist\.md$' \
    | grep -vE 'tests/test-window-layout\.sh$' \
    | grep -vE 'tests/test-rename-guard-15th\.sh$' \
    | grep -vE 'bin/agenphony-up\.sh$' \
    | grep -vE 'bin/AGENTS\.md$' \
    | grep -vE 'tests/test-agenphony-list\.sh$' \
    | grep -vE 'tests/window-layout-live-checklist\.md$' \
    || true)
  if [ -z "$hits" ]; then
    echo "  ok: '$p' 잔존 0건"
    _TESTS_RUN=$((_TESTS_RUN+1))
  else
    echo "  FAIL: '$p' 잔존:"
    echo "$hits" | sed 's/^/    /'
    _TESTS_RUN=$((_TESTS_RUN+1)); _TESTS_FAIL=$((_TESTS_FAIL+1))
  fi
done

test_summary
