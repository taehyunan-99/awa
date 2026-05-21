#!/usr/bin/env bash
# C.2: PreToolUse hook 의 사이드이펙트가 *실제로* events.log 에 기록되는가?
#
# 시나리오:
#  19. matcher 매치 + deny JSON 출력 → hits.log ≥ 1 인가? (deny 결정 후 사이드이펙트 실행?)
#  20. matcher 매치 + 빈 출력 → hits.log ≥ 1 인가? (normal pass-through)
#  21. matcher 미매치 → hits.log = 0 인가? (negative control)

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HARNESS_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
OUT_DIR="$HARNESS_ROOT/docs/probe-results"
mkdir -p "$OUT_DIR"
OUT="$OUT_DIR/2026-05-21-pretooluse-hook-fires.md"

TMP_BASE="$(mktemp -d -t claude-prehook-fires.XXXXXX)"
trap 'rm -rf "$TMP_BASE"' EXIT

run() {
  local label="$1" matcher="$2" hook_body="$3" prompt="$4"
  local dir="$TMP_BASE/$label"
  mkdir -p "$dir/.claude"

  cat > "$dir/.claude/h.sh" <<EOF
#!/bin/sh
# 핵심: hits.log 추가 *후* hook_body 실행.
echo "FIRED_\$(date +%s)" >> "$dir/hits.log"
$hook_body
EOF
  chmod +x "$dir/.claude/h.sh"

  cat > "$dir/.claude/settings.json" <<EOF
{"hooks":{"PreToolUse":[{"matcher":"$matcher","hooks":[{"type":"command","command":"bash $dir/.claude/h.sh"}]}]}}
EOF

  local stdin_file="$dir/_prompt.txt"
  printf '%s\n' "$prompt" > "$stdin_file"
  local output exit_code
  output="$(cd "$dir" && claude -p < "$stdin_file" 2>&1)"
  exit_code=$?

  local hits="0"
  [ -f "$dir/hits.log" ] && hits="$(wc -l < "$dir/hits.log" | tr -d ' ')"

  local sentinel verdict
  sentinel="$(printf '%s' "$prompt" | grep -oE 'SENT_[A-Z0-9_]+' | head -1)"
  if [ -n "$sentinel" ] && printf '%s' "$output" | grep -qF "$sentinel"; then
    verdict="EXECUTED"
  elif printf '%s' "$output" | grep -qiE 'deny|denied|차단|거부|허용되지'; then
    verdict="BLOCKED"
  else
    verdict="UNKNOWN"
  fi

  printf '\n## %s\n\n' "$label"
  printf '**matcher**: `%s` | **hook stdout**: `%s`\n\n' "$matcher" "$hook_body"
  printf '**prompt**: `%s`\n\n' "$prompt"
  printf '**verdict**: `%s` | **hits.log**: %s 라인 | **exit**: %d\n\n' "$verdict" "$hits" "$exit_code"
  printf '**output (truncated)**:\n```\n%s\n```\n\n---\n' "$(printf '%s' "$output" | head -30)"
}

{
  printf '# PreToolUse hook 발화 실측 — 2026-05-21\n\n'
  printf '환경: `%s`\n\n' "$(claude --version 2>&1 | head -1)"
  printf '핵심 질문: hook 의 *사이드이펙트* (hits.log append) 가 deny JSON 반환 *후* 에도 실행되는가?\n\n'

  # 19: deny JSON
  run "19-bash-deny" "Bash" \
    "printf '{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"test\"}}\n'" \
    "Use the Bash tool to run: echo SENT_19"

  # 20: 빈 출력 (pass-through)
  run "20-bash-passthrough" "Bash" \
    "" \
    "Use the Bash tool to run: echo SENT_20"

  # 21: matcher 미매치 (negative control — Edit matcher 에 Bash 호출)
  run "21-edit-matcher-bash-call" "Edit" \
    "printf '{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\"}}\n'" \
    "Use the Bash tool to run: echo SENT_21"

  printf '\n## 결론\n\n'
  printf '- 19 hits ≥ 1 = log-deny.sh / reviewer-deny.sh 의 events.log 기록 작동\n'
  printf '- 19 hits = 0 = hook 사이드이펙트 미실행 → spec 의 lead 감지 메커니즘 깨짐\n'
  printf '- 20 hits ≥ 1 = pass-through 시 hook 정상 (예상)\n'
  printf '- 21 hits = 0 = matcher 미매치 시 hook 안 뜸 (예상 — 정확도 검증)\n'
} > "$OUT"

printf 'probe 완료: %s\n' "$OUT"
grep -E '^## |verdict|hits.log' "$OUT" | head -15
