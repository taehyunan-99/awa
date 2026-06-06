#!/usr/bin/env bash
# tests/check-differentiation-status.sh — AWA 차별화 23 항목 자동 검증
# -e 의도적 미적용 — check() 안의 eval FAIL 후에도 다음 항목 계속 검사해야 진행도 추적기 의도 충족.
# 종료 코드는 FAIL > 0 분기로 명시 (line 121).
set -uo pipefail

HARNESS_ROOT="${HARNESS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
# 하니스 디렉토리(bin/config/prompts/profiles/templates) 단일 출처 — 이동 후에도 $HARNESS_* 가 추종.
# .claude/·tests/·README.md·docs/ 는 repo 루트에 잔류하므로 계속 $HARNESS_ROOT 사용.
source "$(dirname "$0")/harness-paths.sh"
SCRIPT_BIRTHDAY_FILE="${HARNESS_ROOT}/tests/differentiation-checkpoints/.birthday"

PASS=0; FAIL=0; SKIP=0; GRACE=0
declare -a RESULTS

check() {
  local cat="$1" id="$2" desc="$3" layer1_cmd="$4" layer2_cmd="${5:-skip}"
  if eval "$layer1_cmd" >/dev/null 2>&1; then
    if [[ "$layer2_cmd" == "skip" ]]; then
      RESULTS+=("[L1✅ L2⏭️] $cat$id $desc")
      PASS=$((PASS+1))
    elif eval "$layer2_cmd" >/dev/null 2>&1; then
      RESULTS+=("[L1✅ L2✅] $cat$id $desc")
      PASS=$((PASS+1))
    else
      RESULTS+=("[L1✅ L2❌] $cat$id $desc")
      FAIL=$((FAIL+1))
    fi
  else
    RESULTS+=("[L1❌] $cat$id $desc — Layer1: $layer1_cmd")
    FAIL=$((FAIL+1))
  fi
}

# D 카테고리 — 명시적 SKIP (회귀 FAIL 와 구분)
check_skip() {
  local cat="$1" id="$2" desc="$3" reason="$4"
  RESULTS+=("[SKIP] $cat$id $desc — $reason")
  SKIP=$((SKIP+1))
}

echo "=== AWA Differentiation Status ($(date +%Y-%m-%d)) ==="
echo

# A. Plan 인프라
check A 1 "Plan 스키마 강제" \
  "grep -q '검증가능성.*abort\\|검증가능성.*FAIL.*abort' ${HARNESS_ROOT}/.claude/skills/awa/SKILL.md" \
  "test -f ${HARNESS_ROOT}/tests/test-awa-plan-review.sh"
check A 2 "plan-defect 신호 채널" \
  "grep -q '@plan-defect' $HARNESS_PROMPTS/roles/01-orchestration/orch.md" \
  "test -f ${HARNESS_ROOT}/tests/test-plan-defect-e2e.sh"
check A 3 "ⓖ 섹션 — plan 결함 push" \
  "grep -q '## ⓖ' $HARNESS_PROMPTS/roles/01-orchestration/orch.md"
check A 4 "워커 _common.md plan-defect 한 줄" \
  "grep -q '@plan-defect' $HARNESS_PROMPTS/_common.md"

# B. 감시 (리뷰 매니저)
check B 1 "lead 게이트웨이 (사용자 단독 채널)" \
  "grep -q '사용자 대화 진입 금지\\|desk 경유' $HARNESS_PROMPTS/roles/01-orchestration/orch.md"
check B 2 "plan_alignment 필드 reviewer 출력" \
  "grep -rq 'plan_alignment' $HARNESS_PROMPTS/roles/03-quality/"
check B 3 "worker_turn_count watcher 트리거" \
  "grep -q 'worker_turn_count' $HARNESS_BIN/watcher.sh"
check B 4 "리뷰어 verdict 시계열 집계" \
  "grep -rq '시계열\\|plan-diff' $HARNESS_PROMPTS/roles/03-quality/review-manager.md"
check B 5 "review-manager 에이전트 존재 + profile 등록" \
  "test -f $HARNESS_PROMPTS/roles/03-quality/review-manager.md" \
  "grep -qE 'role:[[:space:]]*review-manager' $HARNESS_PROFILES/default.yaml"

# C. 권한 게이트 학습
check C 1 "permission-gate 자동 허용 카탈로그" \
  "test -f $HARNESS_CONFIG/orch-auto-allow.yaml"
check C 2 "classify 분류" \
  "test -f $HARNESS_BIN/classify.sh"
check C 3 "danger-check deny 카탈로그" \
  "test -f $HARNESS_BIN/danger-check.sh"
check C 4 "yaml 영구 누적 (add_to_allow)" \
  "grep -q 'orch-auto-allow.yaml' $HARNESS_BIN/lib.sh" \
  "test -f $HARNESS_CONFIG/orch-auto-allow-stats.yaml"
check C 5 "allow ∩ deny 충돌 검증" \
  "test -f ${HARNESS_ROOT}/tests/test-allow-deny-no-overlap.sh" \
  "bash ${HARNESS_ROOT}/tests/test-allow-deny-no-overlap.sh"

# D. 다벤더 (보류) — 명시적 SKIP (회귀 FAIL 와 구분)
check_skip D 1 "Codex/Antigravity CLI 통합" "다벤더 사이클까지 보류"
check_skip D 2 "리뷰어 풀 정책 문서" "다벤더 사이클 진입 후 활성화"
check_skip D 3 "M5 RDR 메트릭 정의" "다벤더 사이클 + 7일 운영 데이터 후 활성화"
check_skip D 4 "Anthropic blind spot task fixture" "다벤더 사이클 진입 후"

# E. 운영 메타
check E 1 "차별화 점검 자동화 자체" \
  "test -x ${HARNESS_ROOT}/tests/check-differentiation-status.sh"
check E 2 "rename-guard 가드" \
  "test -x ${HARNESS_ROOT}/tests/test-rename-guard.sh"
check E 3 "5어휘 어휘집 README/AGENTS.md grep" \
  "grep -lq 'plan-anchored' ${HARNESS_ROOT}/README.md 2>/dev/null && grep -lq 'drift-tracked' ${HARNESS_ROOT}/README.md 2>/dev/null && grep -lq 'permission-gated' ${HARNESS_ROOT}/README.md 2>/dev/null && grep -lq 'deny-bounded' ${HARNESS_ROOT}/README.md 2>/dev/null"
check E 4 "차별화 매핑 표 README" \
  "grep -q '5조건' ${HARNESS_ROOT}/README.md 2>/dev/null"
check E 5 "identity-AWA.md 풀버전" \
  "test -f ${HARNESS_ROOT}/docs/identity-AWA.md"

# Sanity log grace period (§9.9) — GRACE 별도 카운트 (영구 PASS 와 구분, §9.9 임시성 정합)
if [[ -f "$SCRIPT_BIRTHDAY_FILE" ]]; then
  birthday=$(cat "$SCRIPT_BIRTHDAY_FILE")
  now_epoch=$(date +%s)
  grace_end=$((birthday + 30*86400))
  if (( now_epoch < grace_end )); then
    RESULTS+=("[GRACE] sanity-log.md PASS 조건 임시 PASS (신설 후 30일 grace, ${grace_end} 까지)")
    GRACE=$((GRACE+1))
  else
    if ! find "${HARNESS_ROOT}/tests/differentiation-checkpoints/sanity-log.md" -mtime -30 2>/dev/null | grep -q .; then
      RESULTS+=("[FAIL] sanity-log.md 직전 30일 기록 없음")
      FAIL=$((FAIL+1))
    fi
  fi
fi

# 출력
printf '%s\n' "${RESULTS[@]}"
echo
echo "차별화 임계점: A 전수 + B ≥ 4/5 + C 전수 + D ≥ 1"
echo "외부 노출 임계점: 위 + E3·E4 + D4 + 조건 3 정량 증명 동반"
echo
echo "PASS=$PASS FAIL=$FAIL SKIP=$SKIP GRACE=$GRACE"

exit $(( FAIL > 0 ? 1 : 0 ))
