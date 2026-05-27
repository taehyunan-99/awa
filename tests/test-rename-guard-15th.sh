#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"

echo "[R1] 제거 대상 잔존 0건"
# 검사 범위: .md/.sh, 단 메타 영역 제외:
#   - docs/superpowers/(specs|plans)/ 전체 (역사적 설계 문서 — 옛 사이클 spec 에 옛 명령 등장 정상)
#   - memory/ (외부 메모리)
#   - tests/test-window-layout.sh (14차 메타 주석 — 10차 리뷰 [MAJOR-30] YAGNI)
#   - tests/test-rename-guard-15th.sh (이 파일 자체 — 패턴 문자열 정의가 self-match)
# 6차 리뷰 [MINOR-6]·10차 리뷰 [MAJOR-30] 통합 보강.
# 15차 라이브 결정: deprecated 안내 자체 제거 (14차까지 1인 사용자 → 옛 명령 마이그레이션 불필요).
# 15차 머지 fix: docs 제외를 27일짜리 → 디렉토리 전체로 확장 (옛 docs/specs/plans 에 옛 명령 등장 정상).
patterns=(
  "/agpn plan"
  "/agpn stage"
  "/agpn list"
  "agenphony-list"
)
for p in "${patterns[@]}"; do
  hits=$(grep -rln --include='*.md' --include='*.sh' -F "$p" "$ROOT" 2>/dev/null \
    | grep -vE 'docs/superpowers/(specs|plans)/' \
    | grep -vE 'memory/' \
    | grep -vE 'tests/test-window-layout\.sh$' \
    | grep -vE 'tests/test-rename-guard-15th\.sh$' \
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
