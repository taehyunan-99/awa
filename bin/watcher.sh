#!/usr/bin/env bash
# 파일 폴링 watcher (9차). tmux pane 으로 기동 — 세션 kill 시 자동 사망.
# 의존성 0(순수 셸). control mode/fswatch 배제.
#
# env (team-up 이 주입):
#   SESSION         감시 대상 세션명 (has-session 가드)
#   LEAD_PANE       lead pane_id (%N) — @gate:/@done: 대상
#   REVIEWER_PANES  공백구분 reviewer pane_id 목록 (0~N, 빈 문자열 가능)
#   STATE_DIR       .agent-harness/state (pending-asks/ 포함)
#   EVENTS          .agent-harness/events.log
#   SEEN            .watcher-seen (처리한 uuid 누적)
#   REV_DEBOUNCE    reviewer 깨움 디바운스 초 (기본 3)
set -u

SESSION="${SESSION:-}"
LEAD_PANE="${LEAD_PANE:-}"
REVIEWER_PANES="${REVIEWER_PANES:-}"
STATE_DIR="${STATE_DIR:-}"
EVENTS="${EVENTS:-}"
SEEN="${SEEN:-$STATE_DIR/.watcher-seen}"
REV_DEBOUNCE="${REV_DEBOUNCE:-3}"
# REV_DEBOUNCE 가 비정수로 주입되면 산술 비교에서 데몬이 즉사 → 정수 아니면 기본값으로.
case "$REV_DEBOUNCE" in ''|*[!0-9]*) REV_DEBOUNCE=3 ;; esac

# 대상 pane 생존 확인 (M2 — 죽은 pane 조용한 깨움 유실 방지).
pane_alive() {
  [ -n "${1:-}" ] || return 1
  tmux list-panes -a -F '#{pane_id}' 2>/dev/null | grep -qxF "$1"
}

# last_events 를 기동 시 events.log 현재 줄 수로 초기화 (R4 — 첫 폴링 stale done 폭주 방지).
# 0 으로 두면 기동 첫 사이클이 events.log 전체를 "새 줄"로 간주해 과거 done 라인을 일제히
# @done: 재발화한다. 정상 흐름은 team-down 이 events.log 를 지워 무해하나, 비정상 종료 후
# 재가동(events.log 잔존) 시 lead 가 이미 끝난 task 들을 재종합 — 현재 줄 수에서 시작해 차단.
last_events="$(awk 'END{print NR}' "$EVENTS" 2>/dev/null || echo 0)"
debounced_rev=0

while tmux has-session -t "$SESSION" 2>/dev/null; do
  # 1) pending-asks 새 .json → lead 깨움
  for f in "$STATE_DIR"/pending-asks/*.json; do
    [ -f "$f" ] || continue
    uuid="$(basename "$f" .json)"
    grep -qxF "$uuid" "$SEEN" 2>/dev/null && continue
    pane_alive "$LEAD_PANE" || continue   # M2: 죽은 pane 이면 seen 마킹 보류(살아나면 재시도)
    printf '%s\n' "$uuid" >> "$SEEN"
    tmux send-keys -t "$LEAD_PANE" -l "@gate: 워커 승인 대기 (uuid=$uuid). pending-asks 처리." 2>/dev/null && \
      tmux send-keys -t "$LEAD_PANE" Enter 2>/dev/null || true
  done

  # 2) events.log 증가 → reviewer 깨움(디바운스) + done 라인이면 lead 도
  cur="$(awk 'END{print NR}' "$EVENTS" 2>/dev/null || echo 0)"
  if [ "$cur" -gt "$last_events" ]; then
    now="$(date +%s)"
    # M3: reviewer 디바운스
    if [ "$((now - debounced_rev))" -ge "$REV_DEBOUNCE" ]; then
      for rp in $REVIEWER_PANES; do
        pane_alive "$rp" || continue
        tmux send-keys -t "$rp" -l "@review: events.log 새 줄. 증분 검토." 2>/dev/null && \
          tmux send-keys -t "$rp" Enter 2>/dev/null || true
      done
      debounced_rev="$now"
    fi
    # C2: done 라인 worker/task 추출 → lead 알림. R3: while 은 서브셸 — wt 만 쓰고 외부변수 갱신 금지.
    sed -n "$((last_events+1)),${cur}p" "$EVENTS" 2>/dev/null \
      | awk -F'\t' '$4=="done"{print $2"/"$3}' \
      | while IFS= read -r wt; do
          [ -n "$wt" ] || continue
          pane_alive "$LEAD_PANE" || continue
          tmux send-keys -t "$LEAD_PANE" -l "@done: $wt 완료. results/ 확인 후 종합." 2>/dev/null && \
            tmux send-keys -t "$LEAD_PANE" Enter 2>/dev/null || true
        done
    last_events="$cur"   # 서브셸 밖에서 갱신 (R3 안전)
  fi

  sleep 1
done
