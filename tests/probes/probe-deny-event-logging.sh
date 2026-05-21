#!/usr/bin/env bash
# claude 권한 deny 시 PostToolUse hook 발화 여부 실측.
#
# 핵심 질문 (P0 spec 의 unknown):
#   settings.json permissions.deny 가 도구 호출을 차단할 때,
#   PostToolUse hook 도 같이 발화하는가?
#
# 시나리오:
#   A. 정상 도구 호출 (echo)        → PostToolUse 발화? (baseline)
#   B. deny 된 도구 호출 (rm)       → PostToolUse 발화? (핵심 질문)
#   C. PreToolUse hook 으로 deny  → PostToolUse 발화? (대조군)
#
# 출력: docs/probe-results/2026-05-21-deny-event-logging.md

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HARNESS_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
OUT_DIR="$HARNESS_ROOT/docs/probe-results"
mkdir -p "$OUT_DIR"
OUT="$OUT_DIR/2026-05-21-deny-event-logging.md"

TMP_BASE="$(mktemp -d -t claude-deny-probe.XXXXXX)"
trap 'rm -rf "$TMP_BASE"' EXIT

# 시나리오 실행기.
#   $1=label
#   $2=settings.json 내용 (자리표시자 __HITSDIR__ 는 시나리오 디렉터리로 치환)
#   $3=claude 인자
#   $4=프롬프트
run_scenario() {
  local label="$1" settings="$2" args="$3" prompt="$4"
  local dir="$TMP_BASE/$label"
  mkdir -p "$dir/.claude"

  # PostToolUse hook 으로 hits.log 에 한 줄 기록.
  cat > "$dir/.claude/hits-hook.sh" <<'EOF'
#!/bin/sh
# 인자 1: hits.log 디렉터리.
echo "PostToolUse_FIRED_$(date +%s)" >> "$1/hits.log"
EOF
  chmod +x "$dir/.claude/hits-hook.sh"

  # settings.json — 자리표시자 치환.
  printf '%s' "$settings" | sed "s#__HITSDIR__#$dir#g" > "$dir/.claude/settings.json"

  local stdin_file="$dir/_prompt.txt"
  printf '%s\n' "$prompt" > "$stdin_file"
  local output exit_code
  output="$(cd "$dir" && eval "claude $args -p < '$stdin_file' 2>&1")"
  exit_code=$?

  local hits_count="0"
  [ -f "$dir/hits.log" ] && hits_count="$(wc -l < "$dir/hits.log" | tr -d ' ')"

  local cmd_executed="0"
  local sentinel
  sentinel="$(printf '%s' "$prompt" | grep -oE 'SENT_[A-Z0-9_]+' | head -1)"
  if [ -n "$sentinel" ] && printf '%s' "$output" | grep -qF "$sentinel"; then
    cmd_executed="1"
  fi

  printf '\n## %s\n\n' "$label"
  printf '**settings.json**:\n```json\n%s\n```\n\n' "$settings"
  printf '**args**: `%s`\n\n' "$args"
  printf '**prompt**: `%s`\n\n' "$prompt"
  printf '**exit_code**: %d\n\n' "$exit_code"
  printf '**hits.log 라인 수**: `%s` (PostToolUse hook 발화 횟수)\n\n' "$hits_count"
  printf '**명령 실제 실행**: `%s` (sentinel 출력 검증)\n\n' "$cmd_executed"
  printf '**output (truncated)**:\n```\n%s\n```\n\n' "$(printf '%s' "$output" | head -50)"
  printf '---\n'
}

{
  printf '# claude deny 시 PostToolUse hook 발화 실측 — 2026-05-21\n\n'
  printf '환경: `%s`\n\n' "$(claude --version 2>&1 | head -1)"
  printf '핵심 질문: settings deny 가 차단할 때 PostToolUse 도 발화하는가?\n\n'
  printf '- `hits.log 라인 수 > 0` = PostToolUse 발화 = lead 가 events.log 로 deny 감지 가능\n'
  printf '- `hits.log 라인 수 = 0` = PostToolUse 미발화 = PreToolUse hook 별도 도입 필요\n\n'

  # A. 정상 도구 — baseline
  run_scenario "A-normal-echo" \
    '{
      "hooks": {
        "PostToolUse": [
          {
            "matcher": "Bash",
            "hooks": [{"type": "command", "command": "bash __HITSDIR__/.claude/hits-hook.sh __HITSDIR__"}]
          }
        ]
      }
    }' \
    "" \
    "Use the Bash tool to run: echo SENT_A_OK"

  # B. deny 된 도구 (rm) — 핵심
  run_scenario "B-deny-rm" \
    '{
      "permissions": {"deny": ["Bash(rm *)"]},
      "hooks": {
        "PostToolUse": [
          {
            "matcher": "Bash",
            "hooks": [{"type": "command", "command": "bash __HITSDIR__/.claude/hits-hook.sh __HITSDIR__"}]
          }
        ]
      }
    }' \
    "" \
    "Use the Bash tool to run: rm -fv /tmp/nonexistent_SENT_B_RM || echo SENT_B_FALLBACK"

  printf '\n## 종합\n\n'
  printf '시나리오 B 의 hits.log 라인수 = 0 → settings deny 는 events.log 신호 *안 만들음*.\n'
  printf '  → P0 spec 의 lead 감지 레이어에 PreToolUse hook 도입 필요.\n\n'
  printf '시나리오 B 의 hits.log 라인수 ≥ 1 → settings deny 도 PostToolUse 발화.\n'
  printf '  → 기존 PostToolUse 로 deny 이벤트 잡힘. PreToolUse 불필요.\n'
} > "$OUT"

printf 'probe 완료. 결과: %s\n' "$OUT"
printf '\n핵심 결과:\n'
grep -E '^## |hits.log 라인 수|명령 실제 실행' "$OUT" | head -20
