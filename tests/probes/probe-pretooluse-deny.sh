#!/usr/bin/env bash
# PreToolUse hook 의 permissionDecision: "deny" 실제 차단 능력 실측.
#
# 시나리오:
#   17. PreToolUse hook 이 Bash 매치 시 deny JSON 반환 → Bash 차단?
#   18. PreToolUse hook deny + 정상 Read 도구 호출 → Read 만 허용?
#
# 출력: docs/probe-results/2026-05-21-pretooluse-deny.md

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HARNESS_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
OUT_DIR="$HARNESS_ROOT/docs/probe-results"
mkdir -p "$OUT_DIR"
OUT="$OUT_DIR/2026-05-21-pretooluse-deny.md"

TMP_BASE="$(mktemp -d -t claude-pretooluse-probe.XXXXXX)"
trap 'rm -rf "$TMP_BASE"' EXIT

run_scenario() {
  local label="$1" hook_script="$2" matcher="$3" prompt="$4"
  local dir="$TMP_BASE/$label"
  mkdir -p "$dir/.claude"

  # hook 스크립트.
  cat > "$dir/.claude/deny-hook.sh" <<EOF
#!/bin/sh
echo "PreToolUse_FIRED_\$(date +%s)" >> "$dir/hits.log"
$hook_script
EOF
  chmod +x "$dir/.claude/deny-hook.sh"

  # settings.json — PreToolUse hook 등록.
  cat > "$dir/.claude/settings.json" <<EOF
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "$matcher",
        "hooks": [{"type": "command", "command": "bash $dir/.claude/deny-hook.sh"}]
      }
    ]
  }
}
EOF

  local stdin_file="$dir/_prompt.txt"
  printf '%s\n' "$prompt" > "$stdin_file"
  local output exit_code
  output="$(cd "$dir" && eval "claude -p < '$stdin_file' 2>&1")"
  exit_code=$?

  local hits_count="0"
  [ -f "$dir/hits.log" ] && hits_count="$(wc -l < "$dir/hits.log" | tr -d ' ')"

  local sentinel verdict
  sentinel="$(printf '%s' "$prompt" | grep -oE 'SENT_[A-Z0-9_]+' | head -1)"
  if [ -n "$sentinel" ] && printf '%s' "$output" | grep -qF "$sentinel"; then
    verdict="EXECUTED"
  elif printf '%s' "$output" | grep -qiE 'deny|denied|거부|차단|허용되지 않|blocked'; then
    verdict="BLOCKED"
  else
    verdict="UNKNOWN"
  fi

  printf '\n## %s\n\n' "$label"
  printf '**matcher**: `%s`\n\n' "$matcher"
  printf '**hook 출력 (deny JSON)**:\n```\n%s\n```\n\n' "$hook_script"
  printf '**prompt**: `%s`\n\n' "$prompt"
  printf '**verdict**: `%s` (exit=%d)\n\n' "$verdict" "$exit_code"
  printf '**hits.log**: %s 라인 (PreToolUse 발화 횟수)\n\n' "$hits_count"
  printf '**output (truncated)**:\n```\n%s\n```\n\n' "$(printf '%s' "$output" | head -40)"
  printf '---\n'
}

{
  printf '# claude PreToolUse hook deny 능력 실측 — 2026-05-21\n\n'
  printf '환경: `%s`\n\n' "$(claude --version 2>&1 | head -1)"
  printf 'hook JSON 스펙 (Anthropic 공식): `{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"...\"}}`\n\n'

  # 17. Bash 매치 시 deny JSON 반환.
  run_scenario "17-bash-deny" \
    "printf '{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"reviewer is read-only\"}}\n'" \
    "Bash" \
    "Use the Bash tool to run: echo SENT_17"

  # 18. Edit 매치 시 deny — 다른 도구 함께 검증.
  run_scenario "18-edit-deny-bash-allow" \
    "printf '{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"reviewer cannot edit\"}}\n'" \
    "Edit" \
    "Use the Bash tool to run: echo SENT_18"

  printf '\n## 결론\n\n'
  printf '17 = BLOCKED 이면 → PreToolUse hook 으로 reviewer Read-only 구현 가능. P0 spec 채택.\n'
  printf '17 = EXECUTED 이면 → PreToolUse hook 도 deny 불가. P0 spec 재설계 필요 (settings deny 만).\n'
  printf '18 = EXECUTED (Bash 허용) 이면 → matcher 별 deny 정확히 작동 (도구별 권한 매핑 가능).\n'
} > "$OUT"

printf 'probe 완료. 결과: %s\n' "$OUT"
printf '\n핵심 결과:\n'
grep -E '^## |verdict|hits.log' "$OUT" | head -15
