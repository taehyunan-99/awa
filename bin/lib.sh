#!/usr/bin/env bash
# 공통 함수/상수. 각 bin 스크립트가 source 한다.
# 직접 실행용 아님.

# 이 파일(bin/lib.sh) 기준으로 repo 루트 계산
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$_LIB_DIR/.." && pwd)"
WORKSPACE="$REPO_ROOT/workspace"
SESSION_DEFAULT="agents"

# SESSION 결정 단일화. 우선순위: SESSION_OVERRIDE > PROFILE_SESSION > SESSION_DEFAULT.
# dispatch.sh/wait-worker.sh/team-up.sh 가 모두 이 함수로 세션명을 얻어 불일치 제거(이슈 2).
resolve_session() {
  printf '%s' "${SESSION_OVERRIDE:-${PROFILE_SESSION:-${SESSION:-$SESSION_DEFAULT}}}"
}

# 윈도우·페인 인덱스 → tmux target. 세션명은 resolve_session().
# 2윈도우(team=0, review=1) 도입으로 window 고정 불가 → window 인자화(이슈 1·3).
target_in() {
  local win="$1" pane="$2"
  printf '%s:%s.%s' "$(resolve_session)" "$win" "$pane"
}

# 하위호환: 기존 호출부(window 0 가정)는 그대로. 내부적으로 target_in 위임.
target_of() {
  target_in 0 "$1"
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

# 세션 로컬로 pane title 자동 리네임 비활성화. 전역 ~/.tmux.conf 불변.
# spec §6: dispatch/wait-worker 가 pane title=워커명으로 워커를 조회하므로,
# 워커 셸의 OSC title escape 가 select-pane -T 로 지정한 title 을
# 덮어쓰지 못하도록 세션 로컬로 고정한다.
#
# tmux 3.6a 실측 + man tmux 근거:
#   - allow-rename  : \ek..\e\\ (window-name) 전용 — pane_title 에 무력
#   - allow-set-title: \e]0;..\007 / \e]2;..\007 (pane title) 를 차단 ← 핵심
# 따라서 pane_title 보존의 결정타는 allow-set-title off 이다.
# allow-rename/automatic-rename off 도 세션 로컬·무해하므로 함께 고정한다
# (window-name 까지 호스트명으로 흔들리지 않도록 방어).
fix_session_titles() {
  local s="$1"
  tmux set-option -t "$s" allow-set-title off 2>/dev/null || true
  tmux set-option -t "$s" allow-rename off 2>/dev/null || true
  tmux set-option -t "$s" automatic-rename off 2>/dev/null || true
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
