#!/usr/bin/env bash
set -uo pipefail
_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_DIR/lib.sh"

action="${1:-menu}"
case "$action" in
  list)
    bookmarks_list
    ;;
  set-alias)
    bookmarks_list
    read -r -p "Select bookmark number: " num
    read -r -p "New alias (empty to clear): " alias
    bookmarks_set_alias "$num" "$alias"
    ;;
  remove)
    bookmarks_list
    read -r -p "Select number(s) (e.g. '1,3' or 'all'): " sel
    bookmarks_remove "$sel"
    ;;
  prune)
    bookmarks_prune
    ;;
  menu|*)
    echo "awa bookmarks"
    echo "  (1) List       - show all bookmarks"
    echo "  (2) Set alias  - assign/change alias"
    echo "  (3) Remove     - delete selected"
    echo "  (4) Prune      - bulk remove [stale]"
    read -r -p "Select (1-4): " choice
    case "$choice" in
      1) bookmarks_list ;;
      2) "$0" set-alias ;;
      3) "$0" remove ;;
      4) "$0" prune ;;
      *) echo "Invalid choice." >&2; exit 1 ;;
    esac
    ;;
esac
