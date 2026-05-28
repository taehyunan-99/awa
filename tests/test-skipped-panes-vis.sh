#!/usr/bin/env bash
# T5 회귀: SKIPPED_PANES 누적되면 awa-up 끝에서 stderr 출력.
# awa-up.sh 실제 통합 테스트 어려움 — 끝부분 가시화 로직만 wrapper 로 검증.
# 추가로 awa-up.sh 본체에 그 echo 라인이 실재하는지 정적 grep 으로 검증.
# T5.4 는 wording 한 글자 변경에 무감각하되 env 이름 계약은 정확 감지하도록
# T5.4a/T5.4b/T5.4c 로 분해 (코드 quality review 반영).

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HARNESS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$SCRIPT_DIR/assert.sh"

# 임시 wrapper — awa-up.sh 끝부분의 SKIPPED_PANES 가시화 로직만 추출 모방.
TMP_WRAP="$(mktemp)"
TMP_WRAP2="$(mktemp)"
trap "rm -f '$TMP_WRAP' '$TMP_WRAP2'" EXIT

cat > "$TMP_WRAP" <<'EOF'
#!/usr/bin/env bash
# awa-up.sh 끝부분의 SKIPPED_PANES 가시화 로직 모방.
SKIPPED_PANES=" dev quality-rev"
if [ -n "${SKIPPED_PANES:-}" ]; then
  echo "주의: REPL 준비 실패한 pane: ${SKIPPED_PANES# }" >&2
  echo "  - shell_ready_wait timeout 또는 send-keys 실패 가능성." >&2
  echo "  - SHELL_READY_TIMEOUT (셸 ready timeout) 또는 BOOT_REPL_CHECK_DELAY (REPL 검사 대기) env 로 조정 가능." >&2
fi
EOF

# T5.1: SKIPPED_PANES 있으면 stderr 에 "주의:" 출력.
output_err="$(bash "$TMP_WRAP" 2>&1 >/dev/null)"
if echo "$output_err" | grep -q "주의: REPL 준비 실패"; then
  assert_eq "has-warning" "has-warning" "SKIPPED_PANES 있음 → stderr 안내 출력"
else
  assert_eq "has-warning" "missing" "SKIPPED_PANES 있음 → stderr 안내 출력"
fi

# T5.2: SKIPPED_PANES 안에 워커명 포함.
if echo "$output_err" | grep -q "dev"; then
  assert_eq "has-dev" "has-dev" "SKIPPED_PANES 의 워커명 포함"
else
  assert_eq "has-dev" "missing" "SKIPPED_PANES 의 워커명 포함"
fi

# T5.3: SKIPPED_PANES 비어있으면 안내 X.
cat > "$TMP_WRAP2" <<'EOF'
#!/usr/bin/env bash
SKIPPED_PANES=""
if [ -n "${SKIPPED_PANES:-}" ]; then
  echo "주의: REPL 준비 실패한 pane: ${SKIPPED_PANES# }" >&2
fi
EOF
output_err2="$(bash "$TMP_WRAP2" 2>&1 >/dev/null)"
if [ -z "$output_err2" ]; then
  assert_eq "empty" "empty" "SKIPPED_PANES 비어있으면 안내 없음"
else
  assert_eq "empty" "$output_err2" "SKIPPED_PANES 비어있으면 stderr 없어야"
fi

# T5.4 분해: awa-up.sh 본체의 가시화 코드를 wording 무감각·env 계약 민감으로 검증.
# 단일 wording grep 은 한 글자 변경에도 깨졌었음 → 다중 grep 으로 strict 결합 해소.

# T5.4a: warning marker 존재 (약한 wording 결합 — "주의:" 또는 "warning" 류 허용).
if grep -qE '주의:|[Ww]arning' "$HARNESS_ROOT/bin/awa-up.sh"; then
  assert_eq "marker-present" "marker-present" "awa-up.sh 에 warning marker 존재 (주의/warning)"
else
  assert_eq "marker-present" "missing" "awa-up.sh 에 warning marker 존재 (주의/warning)"
fi

# T5.4b: SHELL_READY_TIMEOUT env 이름 멘션 (강한 계약 — env 이름은 README·코드 동시 계약).
if grep -q "SHELL_READY_TIMEOUT" "$HARNESS_ROOT/bin/awa-up.sh"; then
  assert_eq "shell-ready-timeout-mention" "shell-ready-timeout-mention" "awa-up.sh 가 SHELL_READY_TIMEOUT env 멘션"
else
  assert_eq "shell-ready-timeout-mention" "missing" "awa-up.sh 가 SHELL_READY_TIMEOUT env 멘션"
fi

# T5.4c: BOOT_REPL_CHECK_DELAY env 이름 멘션 (위와 동일 강한 계약).
if grep -q "BOOT_REPL_CHECK_DELAY" "$HARNESS_ROOT/bin/awa-up.sh"; then
  assert_eq "boot-repl-check-delay-mention" "boot-repl-check-delay-mention" "awa-up.sh 가 BOOT_REPL_CHECK_DELAY env 멘션"
else
  assert_eq "boot-repl-check-delay-mention" "missing" "awa-up.sh 가 BOOT_REPL_CHECK_DELAY env 멘션"
fi

test_summary
