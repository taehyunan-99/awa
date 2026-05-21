#!/usr/bin/env bash
# PreToolUse hook 으로 호출됨. *항상 통과* (deny 결정 안 함, 즉 빈 stdout).
# settings.json 의 permissions.deny 가 차단을 결정. 우리 역할은 *기록*.
# matcher 가 'Bash' 한정이므로 Read·Grep 등은 기록 안 됨.
# 별도 파일 PERMISSION_EVENTS_LOG 에 기록 — events.log 와 분리 (폭주 격리).
set -u
EVENT_JSON="$(cat)"
LOG_FILE="${PERMISSION_EVENTS_LOG:-}"
WORKER_NAME="${WORKER:-unknown}"

# env 미설정 시 시끄러운 실패 (조용한 실패 회피).
if [ -z "$LOG_FILE" ]; then
  echo "log-deny.sh: PERMISSION_EVENTS_LOG env 미설정 — 기록 skip" >&2
  exit 0
fi
# WORKER 미설정도 시끄러운 경고 — lead 의 worker 필터 (dev|test|reviewer) 가 'unknown' 으로
# 모두 무시되는 silent failure 차단. 기록은 진행 (lead 가 unknown 줄 보면 즉시 인지).
if [ -z "${WORKER:-}" ]; then
  echo "log-deny.sh: WORKER env 미설정 — 'unknown' 으로 기록 (settings 템플릿 점검 필요)" >&2
fi

# tool_name 추출 (grep fallback — jq 의존성 회피). prefix/suffix 따옴표만 잘라냄 (CMD 와 같은 패턴).
TOOL="$(printf '%s' "$EVENT_JSON" | grep -oE '"tool_name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed -E 's/^"tool_name"[[:space:]]*:[[:space:]]*"//; s/"$//')"

# tool_input.command 추출 (Bash 호출의 실제 명령). lead 의 deny 매치 판정에 필요.
# JSON "command":"..." 값 추출. grep -oE 가 매치 부분만 출력 → sed 가 prefix/suffix 따옴표만 잘라냄.
# 옛 패턴 `.*"command".*"\(.*\)"$/\1/` 는 BSD/GNU sed 양쪽에서 line-end anchor 가 안 맞으면 매치 fail.
CMD="$(printf '%s' "$EVENT_JSON" | grep -oE '"command"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed -E 's/^"command"[[:space:]]*:[[:space:]]*"//; s/"$//' | tr '\n\t\r' '   ' | head -c 200)"

# 형식: ts\tworker\t-\tPRE\ttool\tcmd (events.log 5필드 + 6번째 cmd).
# events.log 의 5필드 파서는 $5 까지만 보면 호환 (cmd 는 끝에 추가).
mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
printf '%s\t%s\t-\tPRE\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$WORKER_NAME" "$TOOL" "$CMD" >> "$LOG_FILE" 2>/dev/null || true

# 빈 출력 — claude 가 알아서 진행 (settings deny 가 차단 책임).
exit 0
