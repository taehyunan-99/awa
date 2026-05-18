#!/usr/bin/env bash
# 공통 함수/상수. 각 bin 스크립트가 source 한다.
# 직접 실행용 아님.

# 이 파일(bin/lib.sh) 기준으로 repo 루트 계산
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$_LIB_DIR/.." && pwd)"
WORKSPACE="$REPO_ROOT/workspace"
SESSION_DEFAULT="agents"

# 페인 인덱스 → tmux target (session:window.pane). 윈도우는 0 고정.
# pane 1 은 오케스트레이터, 워커는 2 부터.
target_of() {
  local idx="$1"
  printf '%s:0.%s' "$SESSION_DEFAULT" "$idx"
}

# 워커 이름 → 부트스트랩 합본 파일 경로
boot_file() {
  local worker="$1"
  printf '%s/.boot/%s.md' "$WORKSPACE" "$worker"
}
