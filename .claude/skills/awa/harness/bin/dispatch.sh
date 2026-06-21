#!/usr/bin/env bash
set -euo pipefail

_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --project 옵션 파서 (E7·F2). lib.sh source 이전 실행.
# lib.sh 의 _normalize_project 는 source 후에야 쓸 수 있으므로 별도 inline 함수.
_normalize_project_arg() {
  local raw="${1:-}"
  if [ -z "$raw" ]; then
    echo "오류: --project 인자 누락 (값 필요)" >&2
    return 1
  fi
  if [ ! -d "$raw" ]; then
    echo "오류: --project 경로 없음: $raw" >&2
    return 1
  fi
  ( cd "$raw" && pwd )
}
while [ $# -gt 0 ]; do
  case "$1" in
    --project)
      if ! HARNESS_PROJECT="$(_normalize_project_arg "${2:-}")"; then exit 1; fi
      export HARNESS_PROJECT; shift 2 ;;
    --project=*)
      if ! HARNESS_PROJECT="$(_normalize_project_arg "${1#--project=}")"; then exit 1; fi
      export HARNESS_PROJECT; shift ;;
    *) break ;;
  esac
done

source "$_DIR/lib.sh"
[ "$PROJECT_ROOT_VALID" = "1" ] || exit 1

SESSION="$(resolve_session)"

WORKER="${1:-}"
TASK_ID="${2:-}"

if [ -z "$WORKER" ] || [ -z "$TASK_ID" ]; then
  echo "사용법: dispatch.sh <worker> <task-id>" >&2
  exit 1
fi

# 세션 확인
if ! tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "오류: 세션 '$SESSION' 없음. awa-up.sh 먼저 실행." >&2
  exit 1
fi

# 계획 B: 차단 가드 — 합의 게이트로 자동차단된 워커는 dispatch 거부 (파일 불변식 집행).
# 페인·task 파일 존재와 독립(파일 불변식)이라 페인 탐색보다 *앞*에 둔다 — 차단 워커의 페인이
# 죽어도 exit 1(진짜 실패) 아닌 exit 2(차단)가 나와 watcher 통지 루프를 막는다.
# 해소는 LEAD 가 재판정 OK 후 clear_block 호출 시. watcher 대행 경로도 dispatch.sh 경유라 자동 적용.
if is_worker_blocked "$WORKER"; then
  echo "차단됨: 워커 '$WORKER' 는 합의 게이트로 자동차단 상태 (.agent-harness/state/blocked-workers/$WORKER.json). 재판정 OK(clear_block) 또는 격리 전까지 dispatch 거부." >&2
  exit 2
fi

# 작업 파일 확인
TASK_FILE="$WORKSPACE/tasks/$TASK_ID.md"
if [ ! -f "$TASK_FILE" ]; then
  echo "오류: 작업 파일 없음 → $TASK_FILE" >&2
  exit 1
fi

# 워커/리뷰어 → 페인: 세션의 전 window 를 pane title 로 스캔한다.
# (이전엔 window 0·1 만 봤으나 review window 가 2 에 배치된 레이아웃에서 리뷰어를
#  못 찾아 dispatch 실패했다. window 인덱스 하드코딩 대신 list-panes -a 로 전수 조회.)
TARGET=""
tmux has-session -t "$SESSION" 2>/dev/null || { echo "오류: 세션 '$SESSION' 없음." >&2; exit 1; }
while IFS=$'\t' read -r ptarget ptitle; do
  if [ "$ptitle" = "$WORKER" ]; then
    TARGET="$ptarget"
    break
  fi
done < <(tmux list-panes -s -t "$SESSION" -F $'#{session_name}:#{window_index}.#{pane_index}\t#{pane_title}')

if [ -z "$TARGET" ]; then
  echo "오류: 워커/리뷰어 '$WORKER' 페인을 찾을 수 없음 (세션 '$SESSION' 전 window 조회)." >&2
  exit 1
fi

write_harness_task "$WORKER" "$TASK_ID"

# 계측(H1 사이클축·H6 리드타임·H7 속도): task-start 라인.
# cycle = 프로젝트 누적 dispatch 순번(학습곡선 x축). scope = task 헤더(Stage B drift-detect).
# 서브셸+|| true 로 격리 — 계측 실패(.cycle-count 손상 등)가 dispatch(send_prompt)를 막지 않는다.
(
  _cyc_file="$WORKSPACE/.cycle-count"
  _cyc="$(cat "$_cyc_file" 2>/dev/null || echo 0)"; _cyc="$(( ${_cyc//[^0-9]/} + 1 ))"
  echo "$_cyc" > "$_cyc_file" 2>/dev/null || true
  _scope="$(awk -F'scope:[[:space:]]*' '/^scope:/{print $2; exit}' "$TASK_FILE" 2>/dev/null || true)"
  _scope="${_scope%/}"   # trailing slash 제거(m1: build/ → build, prefix 매칭 정합)
  log_gate_event "$WORKER" "$TASK_ID" "task-start" "cycle=${_cyc};scope=${_scope:-*}"
) || true

# ★ (a) dispatch ack (I-1, 2026-06-09): send_prompt 가 busy pane 에 *에러 없이* 유실할 수 있어
#   (격리 재현: busy→0초 성공반환·워커 미수신), 송신 자체의 성공/실패만으론 워커 수신을 보장
#   못 한다. → 송신 후 워커가 실제로 task 를 받았다는 증거(events.log 에 이 worker 의 새 액션
#   라인 출현)를 짧게 폴링. 안 나타나면 exit 3(유실 의심) → watcher 가 dispatch-queue .json 을
#   소비 않고 재발화(@done ack 큐와 동형). task-start 는 dispatch 가 직접 찍으므로 ack 증거가
#   아님 — task-start *이후* 늘어난 이 worker 라인(modify/user-ask/done 등)이 수신 증거.
_ev_before="$(awk 'END{print NR}' "$WORKSPACE/events.log" 2>/dev/null || echo 0)"

# ★ (a2) 송신 신뢰도 ack (R4, 2026-06-10 B3 실측 수정): 워커의 첫 events.log 라인은 수신 후
#   20~60s(task 읽기·사고는 로그에 안 남음) — 아래 (a) 8s 폴링이 매번 '유실 의심' 오판 →
#   watcher 재발화로 같은 TASK 를 3~4중 송신했다(B3: t2 cycle=4·5·6·7). I-1 유실의 실체는
#   "busy pane 송신"이므로, ①송신 전 idle 도달 + ②송신 후 입력창 잔류 없음 이면 수신 확정으로
#   exit 0(events 폴링 생략). idle 미도달(busy 송신)일 때만 (a) events 폴링 → exit 3 재발화.
#   잔존 위험(idle 송신인데 미수신)은 @stall watchdog 이 잡는다(R2 로 오탐 제거됨).
_was_idle=0
for _ri in $(seq 1 "${SEND_PROMPT_READY_MAX:-30}"); do
  if _pane_idle "$TARGET"; then _was_idle=1; break; fi
  sleep "${SEND_PROMPT_READY_DELAY:-0.5}"
done
send_prompt "$TARGET" "TASK $TASK_ID"
echo "배정 완료: 워커=$WORKER ($TARGET) ← TASK $TASK_ID"

if [ "$_was_idle" = 1 ]; then
  # send_prompt 가 잔류 Enter 재시도까지 마친 뒤의 최종 잔류만 확인(grep 무매치 rc 는 || true 로 흡수).
  _resid="$(tmux capture-pane -p -t "$TARGET" 2>/dev/null \
    | grep -E '^[[:space:]]*[❯›>]' | tail -1 \
    | sed -E 's/^[[:space:]]*[❯›>][[:space:]]*//')" || _resid=""
  case "$_resid" in
    "TASK"*) : ;;   # 입력창 잔류(미제출) → 아래 (a) events 폴링이 판정
    *) exit 0 ;;    # idle 송신 + 잔류 없음 = 수신 확정 — 재발화 불필요
  esac
fi

# 송신 후 워커 수신 확인 폴링. 새 라인 중 이 worker 의 비-task-start 액션이 1줄이라도 나오면 ack.
# 타임아웃(기본 16×0.5s=8s)까지 무흔적이면 유실 의심 — exit 3. (watcher 가 재발화 판단)
_ack_max="${DISPATCH_ACK_MAX:-16}"
_ack_ok=0
for _ai in $(seq 1 "$_ack_max"); do
  _ev_now="$(awk 'END{print NR}' "$WORKSPACE/events.log" 2>/dev/null || echo 0)"
  if [ "$_ev_now" -gt "$_ev_before" ]; then
    # 새 구간에서 이 worker 의 task-start 아닌 액션 라인이 있으면 수신 확정.
    _new_worker_action="$(sed -n "$((_ev_before+1)),${_ev_now}p" "$WORKSPACE/events.log" 2>/dev/null \
      | awk -F'\t' -v w="$WORKER" '$2==w && $4!="task-start"{c++} END{print c+0}')"
    if [ "${_new_worker_action:-0}" -gt 0 ]; then _ack_ok=1; break; fi
  fi
  sleep "${DISPATCH_ACK_DELAY:-0.5}"
done
if [ "$_ack_ok" != 1 ]; then
  echo "경고: 워커=$WORKER 가 TASK $TASK_ID 수신 흔적 없음(${_ack_max}회 폴링) — 유실 의심. 재발화 위임." >&2
  exit 3
fi
