#!/usr/bin/env bash
set -euo pipefail

_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_DIR/lib.sh"

PROFILE="${1:-default}"
PROFILE_FILE="$REPO_ROOT/profiles/$PROFILE.sh"

if [ ! -f "$PROFILE_FILE" ]; then
  echo "오류: 프로파일 없음 → $PROFILE_FILE" >&2
  echo "사용 가능: $(ls "$REPO_ROOT/profiles" 2>/dev/null | sed 's/\.sh$//' | tr '\n' ' ')" >&2
  exit 1
fi

# 프로파일 로드 (SESSION, LAYOUT, WORKERS 정의)
# shellcheck disable=SC1090
source "$PROFILE_FILE"

# 테스트/멀티팀용 세션명 오버라이드
SESSION="${SESSION_OVERRIDE:-$SESSION}"

# 워커 명령 (기본 claude, 테스트는 AGENT_CMD 로 더미 치환)
AGENT_CMD="${AGENT_CMD:-claude}"

# 중복 세션 거부
if tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "오류: 세션 '$SESSION' 이미 존재. attach 하거나 team-down.sh 후 재시도." >&2
  exit 1
fi

mkdir -p "$WORKSPACE/.boot" "$WORKSPACE/tasks" "$WORKSPACE/results"

# 오케스트레이터 페인으로 세션 생성. 셸 유지.
tmux new-session -d -s "$SESSION" -x 220 -y 50 -n team

# 인덱스 규약 세션 로컬 고정: 사용자 전역 ~/.tmux.conf 의
# base-index/pane-base-index(예: 1) 와 무관하게 window 0 / pane 1 보장.
# move-window -r 로 이미 생성된 윈도우를 base-index(0)부터 재정렬.
fix_session_indexing "$SESSION"

# 적용 검증: window 0 이 실제로 존재하지 않으면 즉시 실패 (추측 우회 금지).
_w="$(tmux list-windows -t "$SESSION" -F '#{window_index}' | head -1)"
if [ "$_w" != "0" ]; then
  echo "오류: 세션 로컬 인덱스 고정 실패 (window=$_w, 기대=0). tmux 버전/설정 확인 필요." >&2
  tmux kill-session -t "$SESSION" 2>/dev/null || true
  exit 1
fi

tmux select-pane -t "$SESSION:0.1" -T "ORCHESTRATOR"

# 워커 페인 분할.
# select-layout 재배치로 pane_index 가 바뀌므로 split 직후 영속 pane_id(%N)를
# -P -F 로 받아 식별한다. 표시용 title 은 셸 escape 로 덮이고 pane_index 는
# layout 으로 흔들리므로, escape-불변 권위 식별자는 @worker(pane 옵션)로 한다.
declare -a WORKER_PANE_IDS=()
for entry in "${WORKERS[@]}"; do
  name="${entry%%:*}"
  pid="$(tmux split-window -t "$SESSION:0" -d -P -F '#{pane_id}')"
  tmux select-layout -t "$SESSION:0" "$LAYOUT"
  tmux select-pane -t "$pid" -T "$name"
  tag_worker_pane "$pid" "$name"
  WORKER_PANE_IDS+=("$pid")
done
tmux select-layout -t "$SESSION:0" "$LAYOUT"

# continuum 오염 방지: 이 세션 자동저장 사실상 비활성화
tmux set-option -t "$SESSION" @continuum-save-interval '0' 2>/dev/null || true

# 워커별 부트스트랩 합본 생성 + 치환, claude 실행, boot 읽기 지시 주입.
# 페인 지정은 split 때 받은 영속 pane_id 사용(pane_index 불안정).
i=0
for entry in "${WORKERS[@]}"; do
  name="${entry%%:*}"
  role="${entry##*:}"
  bf="$(boot_file "$name")"
  cat "$REPO_ROOT/prompts/_common.md" "$REPO_ROOT/prompts/roles/$role.md" \
    | sed "s/{{WORKER_NAME}}/$name/g" > "$bf"

  tgt="${WORKER_PANE_IDS[$i]}"
  tmux send-keys -t "$tgt" -l "$AGENT_CMD"
  tmux send-keys -t "$tgt" Enter
  sleep 0.2
  send_prompt "$tgt" "$bf 를 읽고 그 규약을 그대로 따르라. 준비되면 다음 지시를 대기하라."
  i=$((i + 1))
done

echo "팀 '$PROFILE' 가동 완료. 세션='$SESSION', 워커=${#WORKERS[@]}개."
echo "attach: tmux attach -t $SESSION"
