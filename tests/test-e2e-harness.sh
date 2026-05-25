#!/usr/bin/env bash
set -uo pipefail
# 검증 범위: lib.sh 헬퍼들의 결합(scope_match→cursor→review_verdict→done_logged)
# 배선만 검증한다. 실제 리뷰어 claude 가 /loop+Monitor 로 자율 수행하는지는
# 검증하지 않는다(그건 tests/probes/probe-loop.sh 담당, 수동 실행).
# E2E PASS = "메커니즘 배선 정상" ≠ "하네스 전체 동작 보장". 의도된 한계.
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"
source "$ROOT/bin/lib.sh"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export WORKSPACE="$TMP"
mkdir -p "$TMP/tasks" "$TMP/results" "$TMP/review"
EV="$TMP/events.log"; : > "$EV"

# 1. 메인: task 작성 (scope 포함)
cat > "$TMP/tasks/1.md" <<'T'
---
id: 1
worker: dev
allowed_paths:
  - src/auth/**
forbidden_paths:
  - src/payment/**
---
auth 구현
T

# 초기 커서 검증
assert_eq "0" "$(cursor_read quality-rev)" "초기 커서=0"

# 2. dummy 워커: 정상 변경 + scope 위반 + done
printf 'T\tdev\t1\tmodify\tsrc/auth/login.ts\n'   >> "$EV"
printf 'T\tdev\t1\tmodify\tsrc/payment/charge.ts\n' >> "$EV"   # 위반
printf 'T\tdev\t1\tdone\t-\n'                     >> "$EV"

# 3. dummy 리뷰어: events.log 새 줄을 커서로 읽고 scope 검사 → review 기록
while IFS= read -r line; do
  event_valid "$line" || continue
  act="$(event_field "$line" 4)"; p="$(event_field "$line" 5)"
  [ "$act" = "done" ] && continue
  if scope_match "$p" "src/payment/**"; then
    printf -- '---\nverdict: VIOLATION\nseverity: high\nsignal: weak\n---\n%s\n' "$p" \
      > "$TMP/review/dev-1.quality-rev.md"
  fi
done < <(cursor_new_lines quality-rev "$EV")
cursor_commit quality-rev "$(wc -l < "$EV" | tr -d ' ')"

# 4. 검증: scope 위반 잡힘
assert_success "$([ -f "$TMP/review/dev-1.quality-rev.md" ]; echo $?)" "scope 위반 review 생성"
assert_eq "VIOLATION" "$(review_verdict "$TMP/review" dev 1)" "종합 VIOLATION"

# 5. done 안전장치
done_logged "$EV" dev 1; assert_success "$?" "done 라인 감지"

# 6. 커서 멱등: 재처리 시 새 줄 없음
assert_eq "" "$(cursor_new_lines quality-rev "$EV")" "커서 멱등(새 줄 없음)"

# 7. agenphony-down 하네스 정리 검증 — results/tasks 보존, events/cursor/review 정리
echo "결과" > "$TMP/results/1.md"
# agenphony-down.sh 의 하네스 정리 로직을 직접 모사 검증(claude/tmux 미기동 — WORKSPACE 산출물만)
[ -f "$EV" ] && [ -f "$TMP/.review-cursor.quality-rev" ] && [ -d "$TMP/review" ] || { echo "사전조건 실패"; }
rm -f "$WORKSPACE"/events.log "$WORKSPACE"/.review-cursor.* "$WORKSPACE"/.harness-state 2>/dev/null || true
rm -rf "$WORKSPACE"/review 2>/dev/null || true
assert_success "$([ -f "$TMP/results/1.md" ]; echo $?)" "results 보존(정리 후에도 존재)"
assert_success "$([ -f "$TMP/tasks/1.md" ]; echo $?)" "tasks 보존(정리 후에도 존재)"
assert_fail "$([ -f "$EV" ]; echo $?)" "events.log 정리됨"
assert_fail "$([ -e "$TMP/.review-cursor.quality-rev" ]; echo $?)" ".review-cursor 정리됨"
assert_fail "$([ -d "$TMP/review" ]; echo $?)" "review/ 정리됨"

test_summary
