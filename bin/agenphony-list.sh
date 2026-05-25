#!/usr/bin/env bash
# 12차: 살아있는 agenphony-* 세션 목록 + attach 명령 출력.
set -uo pipefail

sessions="$(tmux ls -F '#{session_name}' 2>/dev/null | grep '^agenphony-' || true)"
if [ -z "$sessions" ]; then
  echo "실행 중인 agenphony 세션 없음. 'agpn stage' 로 시작하세요."
  exit 0
fi

echo "살아있는 agenphony 세션:"
i=0
while IFS= read -r s; do
  [ -n "$s" ] || continue
  i=$((i+1))
  proj="$(tmux show-options -t "$s" -v @agenphony-project 2>/dev/null || true)"
  # 워커구성: pane title 집계(LEAD/PM/watcher 제외).
  workers="$(tmux list-panes -s -t "$s" -F '#{pane_title}' 2>/dev/null \
    | grep -vE '^(LEAD|PM|watcher)$' | sort | uniq -c \
    | awk '{printf "%s%s ", $2, $1}' | sed 's/ $//')"
  printf '  %d. %s   %s   (%s)\n' "$i" "$s" "${proj:-?}" "${workers:-?}"
  printf '     진입: tmux attach -t %s\n' "$s"
done <<< "$sessions"
