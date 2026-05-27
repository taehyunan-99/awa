#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"

# 15th: bookmarks 격리 — agenphony-up.sh 가 ~/.config/agenphony/bookmarks.tsv 에 기록.
# 테스트 fixture 가 사용자 실 경로를 더럽히지 않도록 임시 dir 로 redirect.
_AGPN15_XDG="$(mktemp -d)"
export XDG_CONFIG_HOME="$_AGPN15_XDG"

trap '
  for s in agenphony-dm-a-$$ agenphony-dm-b-$$; do tmux kill-session -t "$s" 2>/dev/null; done
  rm -rf "$_AGPN15_XDG"
' EXIT

echo "[D1] N=0: 안내 메시지 + exit 0"
# 살아있는 agenphony-* 가 없는 상태 보장 — 환경 가정만 (실제 다른 세션 있을 수도)
# fallback: 단지 grep 결과가 0 일 때만 검증
# 6차 리뷰 [CRIT-1]: grep -c + || echo 0 도 0 매치 시 '0\n0' → 직접 count
live=$(tmux ls -F '#{session_name}' 2>/dev/null | grep -c '^agenphony-' 2>/dev/null) || live=0
if [ "$live" = 0 ]; then
  out="$(bash "$ROOT/bin/agenphony-down-menu.sh" 2>&1)"
  assert_contains "$out" "No live sessions" "D1 안내"
else
  echo "  (SKIP D1 — 외부 agenphony-* 세션 $live 개 존재)"
fi

echo "[D2] N=1: 단일 세션 → confirm y → down.sh 위임"
TMP="$(mktemp -d)"; ( cd "$TMP" && git init -q )
SAFE="$(basename "$TMP" | sed 's/[^A-Za-z0-9_-]/_/g')"
S="agenphony-$SAFE"
tmux new-session -d -s "$S"
tmux set-option -t "$S" @agenphony-project "$TMP"
# y 입력 → down.sh 가 marker 없어 거부하겠지만 메뉴 자체는 결정만
out="$(echo y | bash "$ROOT/bin/agenphony-down-menu.sh" 2>&1)"
assert_contains "$out" "$S" "D2a 세션명 표시"
# 단일 케이스라서 외부 N=1 가정 — 다른 agenphony-* 있으면 multi 분기
rm -rf "$TMP"
tmux kill-session -t "$S" 2>/dev/null

test_summary
