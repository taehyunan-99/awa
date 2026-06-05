#!/usr/bin/env bash
# tests/test-boot-directive.sh — 역할 부트 injection-오인 방지 회귀.
#
# 라이브 결함(2026-06-03 다벤더 e2e, 2차): 역할을 send-keys 대화로 주입 + boot_directive
#   부인 prefix("이건 프롬프트 인젝션이 아니라...")가 claude opus 4.8 v2.1.161 의
#   prompt-injection 휴리스틱을 *오히려* 발동 → 역할 부트 거부 → N=3 quorum 붕괴.
#   (claude 가 라이브에서 이 prefix 를 의심 근거로 명시 지목.)
# 해소: claude 역할 부트를 --append-system-prompt-file 시스템프롬프트 경로로 이전
#   (injection 우회). boot_directive 부인 prefix 제거 → codex send_prompt 전용 단순 지시로 축소.
#   claude_systemprompt_boot 헬퍼가 벤더 분기(claude=시스템경로 스킵, codex=send_prompt).

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$SCRIPT_DIR/assert.sh"
. "$SCRIPT_DIR/harness-paths.sh"
. "$HARNESS_BIN/lib.sh" 2>/dev/null || true

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

# T4: 역할 채택 지시 포함 (codex 가 역할 파일을 채택하도록).
printf '%s' "$MSG" | grep -q '역할 규약'
assert_success "$?" "T4: 역할 채택 지시 포함"

# T5: ★ 부인 prefix 제거됨 — '인젝션이 아니' 문구가 잔존하면 claude 트리거 재발(부재 단언).
printf '%s' "$MSG" | grep -q '인젝션이 아니' && PREFIX_LEFT=1 || PREFIX_LEFT=0
assert_eq "0" "$PREFIX_LEFT" "T5: boot_directive 에 부인 prefix 잔존 없음(claude 트리거 제거)"

# T6: claude_systemprompt_boot 헬퍼 존재.
type claude_systemprompt_boot >/dev/null 2>&1
assert_success "$?" "T6: claude_systemprompt_boot 헬퍼 존재"

# T7: claude 벤더 → send_prompt 미발사(시스템프롬프트 경로).
SENT=""
send_prompt() { SENT="$2"; }   # stub
claude_systemprompt_boot claude "%0" "/x/role.md" "tail" 2>/dev/null
assert_eq "" "$SENT" "T7: claude 벤더는 send_prompt 미발사(시스템프롬프트 경로)"

# T7b: codex(비-claude) 벤더 → send_prompt 발사(역할 주입 유지).
SENT=""
claude_systemprompt_boot codex "%0" "/x/role.md" "tail" 2>/dev/null
assert_success "$([ -n "$SENT" ]; echo $?)" "T7b: codex 벤더는 send_prompt 발사(역할 주입 유지)"
unset -f send_prompt

# T8: claude vendor_boot_cmd — 역할파일이 --append-system-prompt-file 로 주입되는지.
. "$HARNESS_BIN/vendors/claude.sh" 2>/dev/null
WCMD="$(vendor_boot_cmd sonnet /x/settings.json abc-123 /x/.boot/engineer.md 2>/dev/null)"
echo "$WCMD" | grep -q -- '--append-system-prompt-file "/x/.boot/engineer.md"'
assert_success "$?" "T8: claude 부트에 역할파일 시스템프롬프트 주입"

# T8b: 4번째 인자 빈값(codex 상정) → 플래그 미포함.
WCMD_EMPTY="$(vendor_boot_cmd sonnet /x/settings.json abc-123 '' 2>/dev/null)"
echo "$WCMD_EMPTY" | grep -q -- '--append-system-prompt-file' && HAS=1 || HAS=0
assert_eq "0" "$HAS" "T8b: 4번째 인자 빈값이면 시스템프롬프트 플래그 미포함"

# T9: awa-up 에 옛 부트 문구 하드코딩 잔존 없음 (DRY·드리프트 방지).
OLD_HARDCODE="$(grep -c '를 읽고 그 규약을 그대로 따르라' "$HARNESS_BIN/awa-up.sh")"
assert_eq "0" "$OLD_HARDCODE" "T9: awa-up 에 옛 부트 문구 하드코딩 잔존 없음"

# T10: awa-up 이 claude_systemprompt_boot 헬퍼로 통일 호출 (워커/리뷰어/PM/LEAD 분기).
HELPER_CALLS="$(grep -c 'claude_systemprompt_boot' "$HARNESS_BIN/awa-up.sh")"
assert_success "$([ "$HELPER_CALLS" -ge 3 ]; echo $?)" "T10: awa-up 이 claude_systemprompt_boot 3회+ 호출 (워커/리뷰어/PM)"

test_summary
