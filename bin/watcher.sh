#!/usr/bin/env bash
# 파일 폴링 watcher (9차). tmux pane 으로 기동 — 세션 kill 시 자동 사망.
# 의존성 0(순수 셸). control mode/fswatch 배제.
#
# env (awa-up 이 주입):
#   SESSION              감시 대상 세션명 (has-session 가드)
#   LEAD_PANE            lead pane_id (%N) — @gate:/@done: 대상
#   REVIEWER_PANES       공백구분 reviewer pane_id 목록 (0~N, 빈 문자열 가능)
#   REVIEW_MANAGER_PANE  review-manager pane_id (있으면) — drift-check 전용 깨움 (I-3 정정)
#   STATE_DIR            .agent-harness/state (pending-asks/ 포함)
#   EVENTS               .agent-harness/events.log
#   SEEN                 .watcher-seen (처리한 uuid 누적)
#   REV_DEBOUNCE         reviewer 깨움 디바운스 초 (기본 3)
set -u

SESSION="${SESSION:-}"
LEAD_PANE="${LEAD_PANE:-}"
REVIEWER_PANES="${REVIEWER_PANES:-}"
REVIEW_MANAGER_PANE="${REVIEW_MANAGER_PANE:-}"
STATE_DIR="${STATE_DIR:-}"
EVENTS="${EVENTS:-}"
SEEN="${SEEN:-$STATE_DIR/.watcher-seen}"
REV_DEBOUNCE="${REV_DEBOUNCE:-3}"

# §5.7 drift-check 용 worker_turn_count 함수 — lib.sh 에서 끌어온다 (없으면 무해 진행).
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh" 2>/dev/null || true
# REV_DEBOUNCE 가 비정수로 주입되면 산술 비교에서 데몬이 즉사 → 정수 아니면 기본값으로.
case "$REV_DEBOUNCE" in ''|*[!0-9]*) REV_DEBOUNCE=3 ;; esac

# 대상 pane 생존 확인 (M2 — 죽은 pane 조용한 깨움 유실 방지).
pane_alive() {
  [ -n "${1:-}" ] || return 1
  tmux list-panes -a -F '#{pane_id}' 2>/dev/null | grep -qxF "$1"
}

# last_events 를 기동 시 events.log 현재 줄 수로 초기화 (R4 — 첫 폴링 stale done 폭주 방지).
# 0 으로 두면 기동 첫 사이클이 events.log 전체를 "새 줄"로 간주해 과거 done 라인을 일제히
# @done: 재발화한다. 정상 흐름은 awa-down 이 events.log 를 지워 무해하나, 비정상 종료 후
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
    # -l 과 Enter 를 독립 실행: && 체이닝이면 -l 성공·Enter 실패 시 텍스트만 입력되고 미제출
    # (half-sent) 되며 || true 가 그걸 삼킨다. set -e 없으니 분리해도 루프 안 죽음 (send_prompt 와 동형).
    tmux send-keys -t "$LEAD_PANE" -l "@gate: 워커 승인 대기 (uuid=$uuid). pending-asks 처리." 2>/dev/null
    tmux send-keys -t "$LEAD_PANE" Enter 2>/dev/null
  done

  # 2) events.log 증가 → reviewer 깨움(디바운스) + done 라인이면 lead 도
  cur="$(awk 'END{print NR}' "$EVENTS" 2>/dev/null || echo 0)"
  if [ "$cur" -gt "$last_events" ]; then
    now="$(date +%s)"
    # M3: reviewer 디바운스
    if [ "$((now - debounced_rev))" -ge "$REV_DEBOUNCE" ]; then
      for rp in $REVIEWER_PANES; do
        pane_alive "$rp" || continue
        # I-3 정정: review-manager 는 일반 @review: 깨움에서 제외 — drift-check 전용으로만 깨움.
        [ "$rp" = "$REVIEW_MANAGER_PANE" ] && continue
        tmux send-keys -t "$rp" -l "@review: events.log 새 줄. 증분 검토." 2>/dev/null
        tmux send-keys -t "$rp" Enter 2>/dev/null
      done
      debounced_rev="$now"
    fi
    # C2: done 라인 worker/task 추출 → lead 알림. R3: while 은 서브셸 — wt 만 쓰고 외부변수 갱신 금지.
    sed -n "$((last_events+1)),${cur}p" "$EVENTS" 2>/dev/null \
      | awk -F'\t' '$4=="done"{print $2"/"$3}' \
      | while IFS= read -r wt; do
          [ -n "$wt" ] || continue
          pane_alive "$LEAD_PANE" || continue
          tmux send-keys -t "$LEAD_PANE" -l "@done: $wt 완료. results/ 확인 후 종합." 2>/dev/null
          tmux send-keys -t "$LEAD_PANE" Enter 2>/dev/null
        done
    # @drift-check: worker_turn_count 임계 (N=10) 도달 → review-manager 깨움 트리거 (§5.7).
    # done 라인 발생 시 worker 별 turn 누적 검사. sort -u 로 동일 worker 중복 트리거 방지.
    # turn % 10 == 0 일 때만 발화 (drift-check 폭주 방지). events.log 5필드 컨벤션 유지.
    sed -n "$((last_events+1)),${cur}p" "$EVENTS" 2>/dev/null \
      | awk -F'\t' '$4=="done"{print $2}' \
      | sort -u \
      | while IFS= read -r w; do
          [ -n "$w" ] || continue
          turn="$(worker_turn_count "$w" "$EVENTS" 2>/dev/null || echo 0)"
          case "$turn" in ''|*[!0-9]*) turn=0 ;; esac
          [ "$turn" -ge 10 ] && [ $((turn % 10)) -eq 0 ] && {
            printf '%s\t%s\t-\tdrift-check\tturn=%s\n' \
              "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$w" "$turn" >> "$EVENTS" 2>/dev/null
            # I-3 정정: review-manager pane 전용 깨움 (drift 분석 책임 작동).
            # REVIEW_MANAGER_PANE 미설정 시 무해 건너뜀 (review-manager 가 없는 프로파일도 호환).
            if [ -n "$REVIEW_MANAGER_PANE" ] && pane_alive "$REVIEW_MANAGER_PANE"; then
              tmux send-keys -t "$REVIEW_MANAGER_PANE" -l "@drift-check: $w turn=$turn. plan-diff 시계열 갱신." 2>/dev/null
              tmux send-keys -t "$REVIEW_MANAGER_PANE" Enter 2>/dev/null
            fi
          }
        done
    # @plan-defect: 라인 worker/task/설명 추출 → lead ⓖ 라우팅 (§4 임시 채널). done 분기와 동일 패턴.
    sed -n "$((last_events+1)),${cur}p" "$EVENTS" 2>/dev/null \
      | awk -F'\t' '$4=="plan-defect"{print $2"/"$3"\t"$5}' \
      | while IFS=$'\t' read -r wt desc; do
          [ -n "$wt" ] || continue
          pane_alive "$LEAD_PANE" || continue
          tmux send-keys -t "$LEAD_PANE" -l "@plan-defect: $wt $desc" 2>/dev/null
          tmux send-keys -t "$LEAD_PANE" Enter 2>/dev/null
        done
    last_events="$cur"   # 서브셸 밖에서 갱신 (R3 안전)
  fi

  sleep 1
done
