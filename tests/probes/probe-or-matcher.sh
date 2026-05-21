#!/usr/bin/env bash
# A.1: matcher OR 패턴 (Bash|Edit|Write|MultiEdit) 이 실제 작동?
#
# 시나리오:
#  33. matcher = "Bash|Edit" + Bash 호출 → BLOCKED?
#  34. matcher = "Bash|Edit" + Edit 호출 → BLOCKED?
#  35. matcher = "Bash|Edit" + Read 호출 → 통과? (매치 안 됨)

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HARNESS_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
OUT_DIR="$HARNESS_ROOT/docs/probe-results"
mkdir -p "$OUT_DIR"
OUT="$OUT_DIR/2026-05-21-or-matcher.md"

TMP_BASE="$(mktemp -d -t claude-or-mat.XXXXXX)"
trap 'rm -rf "$TMP_BASE"' EXIT

run() {
  local label="$1" matcher="$2" prompt="$3"
  local dir="$TMP_BASE/$label"
  mkdir -p "$dir/.claude"

  cat > "$dir/.claude/h.sh" <<EOF
#!/bin/sh
echo "FIRED" >> "$dir/hits.log"
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"test"}}\n'
EOF
  chmod +x "$dir/.claude/h.sh"

  cat > "$dir/.claude/settings.json" <<EOF
{"hooks":{"PreToolUse":[{"matcher":"$matcher","hooks":[{"type":"command","command":"bash $dir/.claude/h.sh"}]}]}}
EOF

  printf '%s\n' "$prompt" > "$dir/_p.txt"
  local out
  out="$(cd "$dir" && claude -p < "$dir/_p.txt" 2>&1)"

  local hits="0"
  [ -f "$dir/hits.log" ] && hits="$(wc -l < "$dir/hits.log" | tr -d ' ')"

  local sentinel verdict
  sentinel="$(printf '%s' "$prompt" | grep -oE 'SENT_[A-Z0-9_]+' | head -1)"
  if [ -n "$sentinel" ] && printf '%s' "$out" | grep -qF "$sentinel"; then
    verdict="EXECUTED"
  elif printf '%s' "$out" | grep -qiE 'deny|denied|차단|거부|허용되지'; then
    verdict="BLOCKED"
  else
    verdict="UNKNOWN"
  fi

  printf '\n## %s\n\n' "$label"
  printf '**matcher**: `%s` | **verdict**: `%s` | **hits**: %s\n\n' "$matcher" "$verdict" "$hits"
  printf '**prompt**: `%s`\n\n' "$prompt"
  printf '**output (truncated)**:\n```\n%s\n```\n\n---\n' "$(printf '%s' "$out" | head -25)"
}

{
  printf '# OR matcher 실측 — 2026-05-21\n\n'
  printf '환경: `%s`\n\n' "$(claude --version 2>&1 | head -1)"

  run "33-or-bash-call"  "Bash|Edit"        "Use the Bash tool to run: echo SENT_33"
  run "34-or-edit-call"  "Bash|Edit"        "Create a file /tmp/SENT_34.txt with content 'hi' using the Write tool"
  run "35-or-read-call"  "Bash|Edit"        "Use the Read tool to read /etc/hosts. Then echo SENT_35"

  printf '\n## 결론\n\n'
  printf '- 33 BLOCKED + hits ≥ 1 = OR 의 Bash 가지 작동\n'
  printf '- 34 BLOCKED + hits ≥ 1 = OR 의 Edit 가지 작동 (Edit/Write 가 의미상 매치)\n'
  printf '- 35 EXECUTED + hits = 0 = Read 는 매치 안 됨 (정상)\n'
  printf '- 33 EXECUTED 또는 hits=0 = OR matcher *문법 미지원* → spec §2.3.4 의 hook 정의를 4개 entry 분리 필요\n'
} > "$OUT"

printf 'probe 완료: %s\n' "$OUT"
grep -E '^## |verdict' "$OUT" | head -10
