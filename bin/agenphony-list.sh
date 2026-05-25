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
  # 워커구성: 첫 window(워커·LEAD·PM·watcher 거주) pane title 집계, LEAD/PM/watcher 제외.
  # reviewer 는 별도 review window 에 있으므로 -s(세션 전체) 대신 첫 window 한정으로 자동 제외.
  # base-index 1 환경 대비 — 첫 window 인덱스를 실측해 타깃(하드코딩 금지).
  w0="$(tmux list-windows -t "$s" -F '#{window_index}' 2>/dev/null | head -1)"
  workers="$(tmux list-panes -t "$s:$w0" -F '#{pane_title}' 2>/dev/null \
    | grep -vE '^(LEAD|PM|watcher)$' | sort | uniq -c \
    | awk '{printf "%s%s ", $2, $1}' | sed 's/ $//')"
  printf '  %d. %s   %s   (%s)\n' "$i" "$s" "${proj:-?}" "${workers:-?}"
  printf '     진입: tmux attach -t %s\n' "$s"
done <<< "$sessions"
