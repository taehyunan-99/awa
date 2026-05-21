#!/usr/bin/env bash
# C.7: --settings <path> 가 기존 .claude/settings.json 과 *합치* 인가 *대체* 인가?
#
# 시나리오:
#  22. .claude/settings.json = PostToolUse hook (A), --settings = PreToolUse hook (B)
#      → 두 hook 다 발화? (합치) vs --settings 만 발화? (대체)
#  23. .claude/settings.json = PostToolUse Bash matcher, --settings = PostToolUse Bash matcher (다른 명령)
#      → 둘 다 실행? (합집합) vs 후자만? (덮어쓰기)
#  24. .claude/settings.json 만 hook, --settings 는 hook 없음 (빈 permissions)
#      → 기존 hook 발화? (기본 유지) vs 미발화? (대체 — 빈 hooks 덮어쓰기)

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HARNESS_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
OUT_DIR="$HARNESS_ROOT/docs/probe-results"
mkdir -p "$OUT_DIR"
OUT="$OUT_DIR/2026-05-21-settings-merge.md"

TMP_BASE="$(mktemp -d -t claude-settings-merge.XXXXXX)"
trap 'rm -rf "$TMP_BASE"' EXIT

run() {
  local label="$1" base_json="$2" extra_json="$3" prompt="$4"
  local dir="$TMP_BASE/$label"
  mkdir -p "$dir/.claude"

  # 두 hook 사이드이펙트 — A.log / B.log 로 분리.
  cat > "$dir/.claude/hA.sh" <<EOF
#!/bin/sh
echo "A_FIRED_\$(date +%s)" >> "$dir/A.log"
EOF
  cat > "$dir/.claude/hB.sh" <<EOF
#!/bin/sh
echo "B_FIRED_\$(date +%s)" >> "$dir/B.log"
EOF
  chmod +x "$dir/.claude/hA.sh" "$dir/.claude/hB.sh"

  # 자리표시자 __DIR__ 치환.
  printf '%s' "$base_json" | sed "s#__DIR__#$dir#g" > "$dir/.claude/settings.json"
  printf '%s' "$extra_json" | sed "s#__DIR__#$dir#g" > "$dir/extra.json"

  local stdin_file="$dir/_prompt.txt"
  printf '%s\n' "$prompt" > "$stdin_file"
  local output exit_code
  output="$(cd "$dir" && claude --settings "$dir/extra.json" -p < "$stdin_file" 2>&1)"
  exit_code=$?

  local a_hits="0" b_hits="0"
  [ -f "$dir/A.log" ] && a_hits="$(wc -l < "$dir/A.log" | tr -d ' ')"
  [ -f "$dir/B.log" ] && b_hits="$(wc -l < "$dir/B.log" | tr -d ' ')"

  printf '\n## %s\n\n' "$label"
  printf '**.claude/settings.json (A)**:\n```json\n%s\n```\n\n' "$base_json"
  printf '**--settings extra.json (B)**:\n```json\n%s\n```\n\n' "$extra_json"
  printf '**prompt**: `%s`\n\n' "$prompt"
  printf '**A.log (기존 hook)**: %s 라인 | **B.log (--settings hook)**: %s 라인 | **exit**: %d\n\n' "$a_hits" "$b_hits" "$exit_code"
  printf '**output (truncated)**:\n```\n%s\n```\n\n---\n' "$(printf '%s' "$output" | head -20)"
}

{
  printf '# claude --settings 합치/대체 실측 — 2026-05-21\n\n'
  printf '환경: `%s`\n\n' "$(claude --version 2>&1 | head -1)"
  printf '핵심: A.log + B.log 둘 다 발화 = *합치*. B.log 만 = *대체*. A.log 만 = *역방향 우선*.\n\n'

  # 22: 다른 hookEvent (PostToolUse + PreToolUse)
  run "22-different-events" \
    '{"hooks":{"PostToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"bash __DIR__/.claude/hA.sh"}]}]}}' \
    '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"bash __DIR__/.claude/hB.sh"}]}]}}' \
    "Use the Bash tool to run: echo SENT_22"

  # 23: 같은 hookEvent / 같은 matcher (둘 다 PostToolUse Bash)
  run "23-same-event-same-matcher" \
    '{"hooks":{"PostToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"bash __DIR__/.claude/hA.sh"}]}]}}' \
    '{"hooks":{"PostToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"bash __DIR__/.claude/hB.sh"}]}]}}' \
    "Use the Bash tool to run: echo SENT_23"

  # 24: extra 가 hook 없음 — 기존 hook 살아있나?
  run "24-extra-empty" \
    '{"hooks":{"PostToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"bash __DIR__/.claude/hA.sh"}]}]}}' \
    '{"permissions":{"defaultMode":"acceptEdits"}}' \
    "Use the Bash tool to run: echo SENT_24"

  printf '\n## 결론\n\n'
  printf '- 22: A≥1 ∧ B≥1 = 합치 (둘 다 발화) / A=0 ∨ B=0 = 대체\n'
  printf '- 23: 같은 matcher 합치 가능 여부 (양쪽 다 발화하면 다중 hook 등록)\n'
  printf '- 24: A=0 = 대체 (extra 가 빈 hooks 로 덮어씀) / A≥1 = 추가 (extra 의 다른 필드만 영향)\n'
} > "$OUT"

printf 'probe 완료: %s\n' "$OUT"
grep -E '^## |A.log|B.log' "$OUT" | head -15
