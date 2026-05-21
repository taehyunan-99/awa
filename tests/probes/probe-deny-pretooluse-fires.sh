#!/usr/bin/env bash
# B.1: settings.deny 가 차단할 때, PreToolUse hook 가 *발화* 하는가?
# spec v4 의 핵심 가치 (lead 감지) 검증.
#
# 시나리오:
#  41. settings.deny=["Bash(rm *)"] + PreToolUse matcher=Bash + Bash 'rm /tmp/X'
#       → hits.log ≥ 1 (hook 발화) ? OR 0 (settings.deny 가 우선 차단)
#  42. settings.deny=["Bash(rm *)"] + PreToolUse matcher=Bash + Bash 'echo OK' (deny 미매치)
#       → hits.log ≥ 1 (정상 발화) — control

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HARNESS_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
OUT_DIR="$HARNESS_ROOT/docs/probe-results"
mkdir -p "$OUT_DIR"
OUT="$OUT_DIR/2026-05-21-deny-pretooluse-fires.md"

TMP_BASE="$(mktemp -d -t deny-pre-fires.XXXXXX)"
trap 'rm -rf "$TMP_BASE"' EXIT

run() {
  local label="$1" prompt="$2"
  local dir="$TMP_BASE/$label"
  mkdir -p "$dir/.claude"

  cat > "$dir/.claude/h.sh" <<EOF
#!/bin/sh
# 기록만 — deny 결정 안 함 (settings.deny 가 차단 책임).
echo "FIRED" >> "$dir/hits.log"
exit 0
EOF
  chmod +x "$dir/.claude/h.sh"

  cat > "$dir/.claude/settings.json" <<EOF
{
  "permissions": {"deny": ["Bash(rm *)"]},
  "hooks": {
    "PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "bash $dir/.claude/h.sh"}]}]
  }
}
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
  elif printf '%s' "$out" | grep -qiE 'deny|denied|차단|거부|허용되지|권한'; then
    verdict="BLOCKED"
  else
    verdict="UNKNOWN"
  fi

  printf '\n## %s\n\n' "$label"
  printf '**prompt**: `%s`\n\n' "$prompt"
  printf '**verdict**: `%s` | **hits.log**: %s 라인\n\n' "$verdict" "$hits"
  printf '**output (truncated)**:\n```\n%s\n```\n\n---\n' "$(printf '%s' "$out" | head -25)"
}

{
  printf '# settings.deny + PreToolUse hook 공존 발화 실측 — 2026-05-21\n\n'
  printf '환경: `%s`\n\n' "$(claude --version 2>&1 | head -1)"
  printf '핵심 질문: settings.deny 가 차단할 때 PreToolUse hook *도* 발화하는가?\n\n'
  printf '- 41 hits ≥ 1 = lead 가 deny 시도 *감지 가능* → spec §2.7 가치 유효\n'
  printf '- 41 hits = 0 = settings.deny 가 PreToolUse 보다 먼저 → spec 의 lead 감지 *무효*\n\n'

  run "41-deny-match-rm"   "Use the Bash tool to run: rm /tmp/SENT_41_NOFILE 2>&1; echo SENT_41_RAN"
  run "42-deny-miss-echo"  "Use the Bash tool to run: echo SENT_42"

  printf '\n## 결론\n\n'
  printf '41 hits 결과로 spec v4 의 lead 감지 메커니즘 채택 가능성 결정.\n'
} > "$OUT"

printf 'probe 완료: %s\n' "$OUT"
grep -E '^## |hits.log|verdict' "$OUT" | head -10
