#!/usr/bin/env bash
# tests/test-boot-directive.sh — 부트 프롬프트 인젝션-오인 방지 회귀.
#
# 라이브 결함(2026-06-03 다벤더 e2e): awa-up send_prompt 가 워커/리뷰어/LEAD/PM 에
#   "$파일 를 읽고 그 규약을 그대로 따르라" 를 주입했는데, claude opus 4.8 이 이를
#   prompt-injection 으로 오인 → 파일을 읽지도 않고 거부 → 역할 미장착 → 후속 깨움 거부.
#   비결정적(quality 는 통과, alignment 는 거부)이라 회귀 안 잡힘. 모든 claude 부트 위험.
# 해소: boot_directive(file,tail) 헬퍼가 "인젝션 아님·하니스 생성 역할 부트" 맥락을
#   prefix 로 붙여 claude 가 정당한 부트로 인지하게 한다. awa-up 5곳이 이 헬퍼로 통일(DRY).

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$SCRIPT_DIR/assert.sh"
. "$ROOT/bin/lib.sh" 2>/dev/null || true

# T1: boot_directive 함수 존재.
type boot_directive >/dev/null 2>&1
assert_success "$?" "T1: boot_directive 헬퍼 존재"

MSG="$(boot_directive '/x/.boot/alignment-rev.md' '준비되면 다음 지시를 대기하라.' 2>/dev/null)"

# T2: 파일 경로 포함 (읽을 대상).
printf '%s' "$MSG" | grep -Fq '/x/.boot/alignment-rev.md'
assert_success "$?" "T2: 부트 파일 경로 포함"

# T3: tail 지시 포함 (역할별 후속).
printf '%s' "$MSG" | grep -Fq '준비되면 다음 지시를 대기하라.'
assert_success "$?" "T3: tail 지시 포함"

# T4: 인젝션-방지 맥락 — '인젝션' 단어로 claude 에게 정당성 명시.
printf '%s' "$MSG" | grep -q '인젝션'
assert_success "$?" "T4: prompt-injection 오인 방지 맥락 포함"

# T5: '하니스 생성/역할 부트' 정당성 단서 (claude 가 외부파일 신뢰하도록).
printf '%s' "$MSG" | grep -Eq '하니스|역할 부트|역할 규약'
assert_success "$?" "T5: 하니스 생성·역할 부트 정당성 단서 포함"

# T6: awa-up.sh 의 모든 send_prompt 부트 주입이 boot_directive 로 통일됐는지 (DRY·드리프트 방지).
#   옛 '를 읽고 그 규약을 그대로 따르라' 하드코딩 잔존 없어야 (한 곳만 빠지면 그 역할 거부 재발).
OLD_HARDCODE="$(grep -c '를 읽고 그 규약을 그대로 따르라' "$ROOT/bin/awa-up.sh")"
assert_eq "0" "$OLD_HARDCODE" "T6: awa-up 에 옛 부트 문구 하드코딩 잔존 없음 (boot_directive 통일)"

# T7: awa-up 이 boot_directive 를 실제 호출 (워커·리뷰어·LEAD·PM).
BD_CALLS="$(grep -c 'boot_directive' "$ROOT/bin/awa-up.sh")"
assert_success "$([ "$BD_CALLS" -ge 4 ]; echo $?)" "T7: awa-up 이 boot_directive 4회+ 호출 (워커/리뷰어/LEAD/PM)"

test_summary
