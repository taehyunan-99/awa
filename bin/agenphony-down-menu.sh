#!/usr/bin/env bash
set -uo pipefail
_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

live=$(tmux list-sessions -F '#{session_name}' 2>/dev/null | grep '^agenphony-' || true)
# 6차 리뷰 [CRIT-1]: 빈 live 안전 카운트 (grep -c + || echo 0 멀티라인 트랩 회피)
if [ -z "$live" ]; then N=0; else N=$(printf '%s\n' "$live" | wc -l | tr -d ' '); fi

case "$N" in
  0)
    echo "No live sessions."
    exit 0
    ;;
  1)
    s="$live"
    proj=$(tmux show-options -t "$s" -v @agenphony-project 2>/dev/null || echo "?")
    echo "Session: $s   Project: $proj"
    read -r -p "Kill this session? (y/n): " ans
    [ "$ans" = "y" ] || exit 0
    [ "$proj" = "?" ] && { echo "오류: @agenphony-project 옵션 없음 ($s)" >&2; exit 1; }
    bash "$_DIR/agenphony-down.sh" --project "$proj"
    ;;
  *)
    i=0
    declare -a names
    while IFS= read -r s; do
      [ -n "$s" ] || continue
      i=$((i+1))
      names[i]="$s"
      proj=$(tmux show-options -t "$s" -v @agenphony-project 2>/dev/null || echo "?")
      printf '  %d. %s   %s\n' "$i" "$s" "$proj"
    done <<< "$live"
    read -r -p "Select (e.g. '1,3,5' or 'all' or number): " sel
    if [ "$sel" = "all" ]; then
      indices=$(seq 1 $N)
    else
      indices=$(echo "$sel" | tr ',' '\n' | grep -E '^[0-9]+$' | sort -un)
    fi
    [ -n "$indices" ] || { echo "Invalid selection." >&2; exit 1; }
    invalid=$(echo "$indices" | awk -v n=$N '$1<1||$1>n')
    [ -z "$invalid" ] || { echo "Invalid: $invalid" >&2; exit 1; }
    selected=""
    for idx in $indices; do selected="$selected ${names[$idx]}"; done
    echo "Kill these sessions:$selected"
    read -r -p "Confirm? (y/n): " ans
    [ "$ans" = "y" ] || exit 0
    for s in $selected; do
      proj=$(tmux show-options -t "$s" -v @agenphony-project 2>/dev/null || echo "")
      [ -n "$proj" ] && bash "$_DIR/agenphony-down.sh" --project "$proj"
    done
    ;;
esac
