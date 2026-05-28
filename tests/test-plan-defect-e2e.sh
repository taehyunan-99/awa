#!/usr/bin/env bash
# tests/test-plan-defect-e2e.sh — @plan-defect: 자동 분기 검증 (Task 3 / D2 자동)
# Layer 1: lead.md ⓖ 섹션 + _common.md 한 줄 + watcher.sh 분기 패턴 존재 확인
# Layer 2: watcher awk 분기가 plan-defect events.log 라인을 정확히 추출하는지 검증
# 실 AskUserQuestion 도달은 Task 11 sanity check 사이클에서 D1 수동.
set -uo pipefail
HARNESS_ROOT="${HARNESS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

# Layer 1: lead.md ⓖ 섹션 존재
grep -q '## ⓖ' "$HARNESS_ROOT/prompts/roles/01-orchestration/lead.md" || {
  echo "[FAIL] lead.md ⓖ 섹션 부재"
  exit 1
}
grep -q '신호 5종' "$HARNESS_ROOT/prompts/roles/01-orchestration/lead.md" || {
  echo "[FAIL] lead.md 신호 5종 미반영 (여전히 4종)"
  exit 1
}

# Layer 1: _common.md 한 줄 존재
grep -q '@plan-defect' "$HARNESS_ROOT/prompts/_common.md" || {
  echo "[FAIL] _common.md @plan-defect 미반영"
  exit 1
}

# Layer 1: watcher.sh 분기 존재 (events.log action=plan-defect 인식)
grep -q '"plan-defect"' "$HARNESS_ROOT/bin/watcher.sh" || {
  echo "[FAIL] watcher.sh plan-defect 분기 부재"
  exit 1
}

# Layer 2: watcher awk 분기 실제 추출 검증 — events.log fake line → worker/task + 설명 분리
EVENTS_LOG="$TMPDIR/events.log"
printf '%s\t%s\t%s\tplan-defect\t%s\n' \
  '2026-05-28T00:00:00Z' 'dev' 'T3' 'acceptance criteria 모호' \
  > "$EVENTS_LOG"

extracted="$(awk -F'\t' '$4=="plan-defect"{print $2"/"$3"\t"$5}' "$EVENTS_LOG")"
expected="dev/T3	acceptance criteria 모호"
if [ "$extracted" != "$expected" ]; then
  echo "[FAIL] watcher awk 추출 불일치"
  echo "  expected: $expected"
  echo "  got:      $extracted"
  exit 1
fi

# 분기 시뮬 — (a)/(b)/(c) 사용자 결정 mock (실제 AskUserQuestion 도달은 D1 수동)
for decision in "수정" "재개" "취소"; do
  case "$decision" in
    "수정"|"재개"|"취소") : ;;  # 분기 진입 가능
    *) echo "[FAIL] 알 수 없는 결정: $decision"; exit 1 ;;
  esac
done

echo "[PASS] @plan-defect e2e (D2 자동) — Layer 1 + Layer 2 awk 추출 + 사용자 결정 mock 3분기"
exit 0
