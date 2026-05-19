#!/usr/bin/env bash
set -uo pipefail
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

# 2. dummy 워커: 정상 변경 + scope 위반 + done
printf 'T\tdev\t1\tmodify\tsrc/auth/login.ts\n'   >> "$EV"
printf 'T\tdev\t1\tmodify\tsrc/payment/charge.ts\n' >> "$EV"   # 위반
printf 'T\tdev\t1\tdone\t-\n'                     >> "$EV"

# 3. dummy 리뷰어: events.log 새 줄을 커서로 읽고 scope 검사 → review 기록
cur="$(cursor_read qrev)"
while IFS= read -r line; do
  event_valid "$line" || continue
  act="$(event_field "$line" 4)"; p="$(event_field "$line" 5)"
  [ "$act" = "done" ] && continue
  if scope_match "$p" "src/payment/**"; then
    printf -- '---\nverdict: VIOLATION\nseverity: high\nsignal: weak\n---\n%s\n' "$p" \
      > "$TMP/review/dev-1.qrev.md"
  fi
done < <(cursor_new_lines qrev "$EV")
cursor_commit qrev "$(wc -l < "$EV" | tr -d ' ')"

# 4. 검증: scope 위반 잡힘
assert_success "$([ -f "$TMP/review/dev-1.qrev.md" ]; echo $?)" "scope 위반 review 생성"
assert_eq "VIOLATION" "$(review_verdict "$TMP/review" dev 1)" "종합 VIOLATION"

# 5. done 안전장치
done_logged "$EV" dev 1; assert_success "$?" "done 라인 감지"

# 6. 커서 멱등: 재처리 시 새 줄 없음
assert_eq "" "$(cursor_new_lines qrev "$EV")" "커서 멱등(새 줄 없음)"

# 7. team-down 정리 시뮬: results 보존, events/cursor/review 정리 대상
echo "결과" > "$TMP/results/1.md"
assert_success "$([ -f "$TMP/results/1.md" ]; echo $?)" "results 보존 대상 존재"

test_summary
