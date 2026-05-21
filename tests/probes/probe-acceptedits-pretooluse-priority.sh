#!/usr/bin/env bash
# B.3: acceptEdits + PreToolUse hook deny 공존 시 우선순위?
#
# 시나리오:
#  36. defaultMode=acceptEdits + PreToolUse matcher=Bash → deny JSON
#       → BLOCKED 인가 EXECUTED 인가?

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HARNESS_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
OUT_DIR="$HARNESS_ROOT/docs/probe-results"
mkdir -p "$OUT_DIR"
OUT="$OUT_DIR/2026-05-21-acceptedits-pretooluse-priority.md"

TMP_BASE="$(mktemp -d -t claude-ae-pre.XXXXXX)"
trap 'rm -rf "$TMP_BASE"' EXIT

dir="$TMP_BASE/scenario"
mkdir -p "$dir/.claude"
cat > "$dir/.claude/h.sh" <<EOF
#!/bin/sh
echo "FIRED" >> "$dir/hits.log"
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"test priority"}}\n'
EOF
chmod +x "$dir/.claude/h.sh"

cat > "$dir/.claude/settings.json" <<EOF
{
  "permissions": {"defaultMode": "acceptEdits"},
  "hooks": {
    "PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "bash $dir/.claude/h.sh"}]}]
  }
}
EOF

printf 'Use the Bash tool to run: echo SENT_36_PRIORITY\n' > "$dir/_p.txt"
out="$(cd "$dir" && claude -p < "$dir/_p.txt" 2>&1)"

hits="0"
[ -f "$dir/hits.log" ] && hits="$(wc -l < "$dir/hits.log" | tr -d ' ')"

if printf '%s' "$out" | grep -qF 'SENT_36_PRIORITY'; then
  verdict="EXECUTED (acceptEdits 가 우선 — hook deny 무시)"
elif printf '%s' "$out" | grep -qiE 'deny|denied|차단|거부|허용되지'; then
  verdict="BLOCKED (hook deny 가 우선 — spec §2.3.4 채택 가능)"
else
  verdict="UNKNOWN"
fi

{
  printf '# acceptEdits + PreToolUse hook 우선순위 — 2026-05-21\n\n'
  printf '환경: `%s`\n\n' "$(claude --version 2>&1 | head -1)"
  printf '## 36-acceptedits-pretooluse-deny\n\n'
  printf '**settings**:\n```json\n%s\n```\n\n' "$(cat "$dir/.claude/settings.json")"
  printf '**verdict**: `%s` | **hits**: %s\n\n' "$verdict" "$hits"
  printf '**output (truncated)**:\n```\n%s\n```\n\n' "$(printf '%s' "$out" | head -25)"
  printf '## 결론\n\n'
  printf '%s\n' "$verdict"
} > "$OUT"

printf 'probe 완료: %s\n' "$OUT"
echo "verdict: $verdict"
