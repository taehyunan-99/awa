#!/usr/bin/env bash
# claude settings.deny 의 *패턴 형태별* 작동 확인.
# reviewer 의 'Bash 전체 차단' 가능 형식을 실측.
#
# 시나리오:
#   13. deny: ['Bash(*)']        → Bash 호출 전체 차단?
#   14. deny: ['Bash']           → tool 이름만 (인자 없이)?
#   15. deny: ['Edit', 'Write']  → 다른 도구 이름 명시?
#   16. deny: ['Bash(*)'] + allow: ['Read'] → 조합?
#
# 출력: docs/probe-results/2026-05-21-deny-patterns.md

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HARNESS_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
OUT_DIR="$HARNESS_ROOT/docs/probe-results"
mkdir -p "$OUT_DIR"
OUT="$OUT_DIR/2026-05-21-deny-patterns.md"

TMP_BASE="$(mktemp -d -t claude-deny-pat-probe.XXXXXX)"
trap 'rm -rf "$TMP_BASE"' EXIT

run_scenario() {
  local label="$1" settings="$2" prompt="$3"
  local dir="$TMP_BASE/$label"
  mkdir -p "$dir/.claude"
  printf '%s' "$settings" > "$dir/.claude/settings.json"

  local stdin_file="$dir/_prompt.txt"
  printf '%s\n' "$prompt" > "$stdin_file"
  local output exit_code
  output="$(cd "$dir" && eval "claude -p < '$stdin_file' 2>&1")"
  exit_code=$?

  local sentinel verdict
  sentinel="$(printf '%s' "$prompt" | grep -oE 'SENT_[A-Z0-9_]+' | head -1)"
  if [ -n "$sentinel" ] && printf '%s' "$output" | grep -qF "$sentinel"; then
    verdict="EXECUTED"
  elif printf '%s' "$output" | grep -qiE 'deny|denied|거부|차단|허용되지|권한 설정'; then
    verdict="BLOCKED"
  else
    verdict="UNKNOWN"
  fi

  printf '\n## %s\n\n' "$label"
  printf '**settings.json**:\n```json\n%s\n```\n\n' "$settings"
  printf '**prompt**: `%s`\n\n' "$prompt"
  printf '**verdict**: `%s` (exit=%d)\n\n' "$verdict" "$exit_code"
  printf '**output (truncated)**:\n```\n%s\n```\n\n' "$(printf '%s' "$output" | head -30)"
  printf '---\n'
}

{
  printf '# claude settings.deny 패턴 형태 실측 — 2026-05-21\n\n'
  printf '환경: `%s`\n\n' "$(claude --version 2>&1 | head -1)"
  printf '판정:\n'
  printf '- `EXECUTED` = 명령 실제 실행 (deny 실패)\n'
  printf '- `BLOCKED` = 차단 메시지 등장\n\n'

  # 13. Bash(*) — 인자 와일드카드.
  run_scenario "13-deny-Bash-wildcard" \
    '{"permissions": {"deny": ["Bash(*)"]}}' \
    "Use the Bash tool to run: echo SENT_13"

  # 14. Bash (이름만)
  run_scenario "14-deny-Bash-bare" \
    '{"permissions": {"deny": ["Bash"]}}' \
    "Use the Bash tool to run: echo SENT_14"

  # 15. Edit, Write — 다른 도구 이름 (Bash 는 허용 — 우리 우회 가능성 확인).
  run_scenario "15-deny-Edit-Write" \
    '{"permissions": {"deny": ["Edit", "Write"]}}' \
    "Use the Bash tool to run: echo SENT_15"

  # 16. Bash(*) + allow Read — reviewer 모델 후보.
  run_scenario "16-deny-Bash-allow-Read" \
    '{"permissions": {"deny": ["Bash(*)"], "allow": ["Read"]}}' \
    "Use the Bash tool to run: echo SENT_16"

  printf '\n## 결론\n\n'
  printf '13/14 의 verdict 가 BLOCKED → reviewer 의 Bash 전체 차단은 그 패턴 사용.\n'
  printf '15 가 EXECUTED → Edit/Write 만 deny 해도 Bash 는 허용 (예상 — 명시 deny 만 작동).\n'
  printf '16 verdict → reviewer 최종 권한 모델 결정.\n'
} > "$OUT"

printf 'probe 완료. 결과: %s\n' "$OUT"
printf '\n핵심 결과:\n'
grep -E '^## |verdict' "$OUT" | paste -d ' ' - - | head -10
