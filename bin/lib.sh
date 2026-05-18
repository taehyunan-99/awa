#!/usr/bin/env bash
# 공통 함수/상수. 각 bin 스크립트가 source 한다.
# 직접 실행용 아님.

# 이 파일(bin/lib.sh) 기준으로 repo 루트 계산
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$_LIB_DIR/.." && pwd)"
WORKSPACE="$REPO_ROOT/workspace"
SESSION_DEFAULT="agents"

# 페인 인덱스 → tmux target (session:window.pane).
# 활성 세션(SESSION 변수, 없으면 SESSION_DEFAULT) 기준 — 세션 오버라이드/멀티팀 지원.
# 윈도우 0 고정 (team-up.sh가 세션 로컬 base-index=0 강제). pane은 1부터(pane-base-index=1).
# pane 1 은 오케스트레이터, 워커는 2 부터.
target_of() {
  local idx="$1"
  printf '%s:0.%s' "${SESSION:-$SESSION_DEFAULT}" "$idx"
}

# 세션 로컬로 인덱스 규약 고정. 전역 ~/.tmux.conf 설정에 비의존.
# 인자: 세션명. window base-index=0, pane-base-index=1 강제.
fix_session_indexing() {
  local s="$1"
  tmux set-option -t "$s" base-index 0 2>/dev/null || true
  tmux set-option -t "$s" pane-base-index 1 2>/dev/null || true
  # 이미 만들어진 윈도우/페인에도 즉시 반영되도록 재정렬
  tmux move-window -r -s "$s" 2>/dev/null || true
}

# 워커 페인에 escape-불변 식별자(@worker pane 옵션) 부여.
# spec §6: dispatch/wait-worker 가 워커 페인을 조회한다. pane_title 은
# 워커 셸의 OSC 0/2 escape(호스트명 등)로 항상 덮이며 tmux 의
# allow-rename/automatic-rename 은 window-name 에만 적용돼 막을 수 없다(실측).
# 따라서 셸 출력에 영향받지 않는 pane 사용자 옵션을 권위 식별자로 쓴다.
# 전역 ~/.tmux.conf 불변.
tag_worker_pane() {
  local target="$1" name="$2"
  tmux set-option -p -t "$target" @worker "$name" 2>/dev/null || true
}

# @worker 옵션으로 워커 페인의 영속 pane_id(%N) 조회. 없으면 빈 문자열.
# pane_index 는 select-layout 으로 흔들리므로 pane_id 를 권위 타깃으로 쓴다.
worker_pane() {
  local s="${SESSION:-$SESSION_DEFAULT}" name="$1"
  tmux list-panes -t "$s:0" \
    -F '#{pane_id}' \
    -f "#{==:#{@worker},$name}" 2>/dev/null | head -1
}

# 워커 이름 → 부트스트랩 합본 파일 경로
boot_file() {
  local worker="$1"
  printf '%s/.boot/%s.md' "$WORKSPACE" "$worker"
}

# 세션 존재 여부. 존재하면 0, 아니면 비-0.
session_exists() {
  local s="${1:-$SESSION_DEFAULT}"
  tmux has-session -t "$s" 2>/dev/null
}

# 프롬프트 안전 주입: 텍스트(리터럴)와 Enter 분리. spec §4.1.
send_prompt() {
  local target="$1" text="$2"
  tmux send-keys -t "$target" -l "$text"
  tmux send-keys -t "$target" Enter
}
