#!/usr/bin/env bash
# 파일 폴링 watcher (9차). tmux pane 으로 기동 — 세션 kill 시 자동 사망.
# 의존성 0(순수 셸). control mode/fswatch 배제.
#
# env (awa-up 이 주입):
#   SESSION              감시 대상 세션명 (has-session 가드)
#   ORCH_PANE            lead pane_id (%N) — @gate:/@done: 대상
#   REVIEWER_PANES       공백구분 reviewer pane_id 목록 (0~N, 빈 문자열 가능)
#   REVIEW_MANAGER_PANE  review-manager pane_id (있으면) — drift-check 전용 깨움 (I-3 정정)
#   STATE_DIR            .agent-harness/state (pending-asks/ 포함)
#   EVENTS               .agent-harness/events.log
#   REV_DEBOUNCE         reviewer 깨움 디바운스 초 (기본 3)
set -u

SESSION="${SESSION:-}"
ORCH_PANE="${ORCH_PANE:-}"
REVIEWER_PANES="${REVIEWER_PANES:-}"
REVIEW_MANAGER_PANE="${REVIEW_MANAGER_PANE:-}"
STATE_DIR="${STATE_DIR:-}"
EVENTS="${EVENTS:-}"
REV_DEBOUNCE="${REV_DEBOUNCE:-3}"
EXPECTED_VOTERS="${EXPECTED_VOTERS:-0}"

# §5.7 drift-check 용 worker_turn_count 함수 — lib.sh 에서 끌어온다 (없으면 무해 진행).
# AWA_AUTO_LEARN 수집모드에서 confirm_allow_yaml 재호출 시 lib 경로 재사용 위해 변수화.
_WATCHER_DIR="$(dirname "$0")"
# shellcheck source=lib.sh
. "$_WATCHER_DIR/lib.sh" 2>/dev/null || true
# @done ack 큐 함수(enqueue_pending_done/requeue_pending_done) — 회로① 침묵 차단.
# shellcheck source=watcher-lib.sh
. "$(dirname "$0")/watcher-lib.sh" 2>/dev/null || true
# done 재발화 나이 임계(초). LEAD 가 idle 복귀할 시간을 준 뒤 미ack done 을 재발화.
REQUEUE_AGE="${REQUEUE_AGE:-20}"
case "$REQUEUE_AGE" in ''|*[!0-9]*) REQUEUE_AGE=20 ;; esac
# REV_DEBOUNCE 가 비정수로 주입되면 산술 비교에서 데몬이 즉사 → 정수 아니면 기본값으로.
case "$REV_DEBOUNCE" in ''|*[!0-9]*) REV_DEBOUNCE=3 ;; esac
# EXPECTED_VOTERS 비정수 주입 시 산술 비교 즉사 방지 → 정수 아니면 0(무력화).
case "$EXPECTED_VOTERS" in ''|*[!0-9]*) EXPECTED_VOTERS=0 ;; esac

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
  # 1) pending-asks 미처리 .json → lead 재발화(ack 큐, @done 동형 — 점유 중 소실 복구).
  #    결함 배경(2026-06-06 라이브): 과거엔 $SEEN 에 uuid 를 1회만 마킹하고 fire-and-forget
  #    send-keys 했다. ORCH 점유(작업/모달) 중이면 그 @gate 가 claude TUI 에서 소실되는데
  #    이미 SEEN 마킹돼 영영 재발화 안 함 → 워커 권한 USER-ASK 가 사용자에 push 안 됨.
  #    수정: @done 의 pending-done ack 큐와 동형으로, ack(=ORCH 가 .response 기록) 없는 .json 을
  #    REQUEUE_AGE 초마다 재발화. ack 메커니즘은 orch.md ⓓ — ORCH 가 <uuid>.response 를 atomic
  #    기록하면(hook 폴링) 그게 처리 완료 표시. .response 있으면 더는 재발화 안 함.
  for f in "$STATE_DIR"/pending-asks/*.json; do
    [ -f "$f" ] || continue
    uuid="$(basename "$f" .json)"
    # ack 확인: ORCH 가 응답을 기록했으면(<uuid>.response) 처리 완료 — 재발화 중단.
    [ -f "$STATE_DIR/pending-asks/$uuid.response" ] && continue
    # 재발화 디바운스: 마지막 발화 마커(.gate-fired.<uuid>) mtime 이 REQUEUE_AGE 안이면 건너뜀.
    #   @done ack 큐의 mtime touch 디바운스와 동형(매 사이클 폭주 방지).
    _gate_marker="$STATE_DIR/pending-asks/.gate-fired.$uuid"
    if [ -f "$_gate_marker" ]; then
      _gm="$(stat -f %m "$_gate_marker" 2>/dev/null || stat -c %Y "$_gate_marker" 2>/dev/null || echo 0)"
      case "$_gm" in ''|*[!0-9]*) _gm=0 ;; esac
      [ "$(( $(date +%s) - _gm ))" -ge "$REQUEUE_AGE" ] || continue
    fi
    pane_alive "$ORCH_PANE" || continue   # M2: 죽은 pane 이면 발화 보류(살아나면 재시도 — 마커 미갱신)
    touch "$_gate_marker" 2>/dev/null || true   # 발화 마커 갱신 → 다음 재발화를 REQUEUE_AGE 만큼 미룸
    # -l 과 Enter 를 독립 실행: && 체이닝이면 -l 성공·Enter 실패 시 텍스트만 입력되고 미제출
    # (half-sent) 되며 || true 가 그걸 삼킨다. set -e 없으니 분리해도 루프 안 죽음 (send_prompt 와 동형).
    tmux send-keys -t "$ORCH_PANE" -l "@gate: 워커 승인 대기 (uuid=$uuid). pending-asks 처리." 2>/dev/null
    tmux send-keys -t "$ORCH_PANE" Enter 2>/dev/null
  done

  # 1b) dispatch-queue 새 .json → dispatch.sh 실행 (P11 탈-tmux: lead 가 sandbox 안이라
  #     tmux has-session/send-keys 를 직접 못 함. lead 는 dispatch-queue/<id>.json 에 배정
  #     의도만 파일로 쓰고, watcher(sandbox 밖)가 폴링해 실제 dispatch.sh 를 대신 실행).
  #     pending-asks 분기와 동형. 처리 후 .json 삭제(재실행 방지 — seen 누적 대신 소비).
  for f in "$STATE_DIR"/dispatch-queue/*.json; do
    [ -f "$f" ] || continue
    dq_worker="$(jq -r '.worker // empty' "$f" 2>/dev/null)"
    dq_task="$(jq -r '.task_id // empty' "$f" 2>/dev/null)"
    if [ -z "$dq_worker" ] || [ -z "$dq_task" ]; then
      # 형식 불량 — 소비해 폐기(무한 재시도 방지). lead 가 재배정하면 새 .json 생성.
      rm -f "$f" 2>/dev/null
      continue
    fi
    # dispatch.sh 가 has-session/list-panes/send_prompt(tmux) 를 watcher(sandbox 밖)에서
    # 정상 실행. --project 로 PROJECT_ROOT 명시(watcher cwd=본체라 git toplevel 오인 방지).
    _dq_rc=0
    bash "$(dirname "$0")/dispatch.sh" \
      ${HARNESS_PROJECT:+--project "$HARNESS_PROJECT"} "$dq_worker" "$dq_task" >/dev/null 2>&1 || _dq_rc=$?
    if [ "$_dq_rc" = 0 ]; then
      :   # 성공 — dispatch.sh 가 워커 페인에 TASK 주입. lead 통지 불필요(조용).
    elif [ "$_dq_rc" = 2 ]; then
      :   # 차단(계획 B 합의 게이트) — dispatch.sh 가 거부. 실패 아님이라 @dispatch-fail 통지 안 함.
          #   LEAD 가 차단 워커를 재배정한 경우라 조용히 소비(통지 루프 방지). 해소는 clear_block.
    elif pane_alive "$ORCH_PANE"; then
      # 진짜 실패만 lead 에 통지(세션/페인/task 파일 이상). -l 과 Enter 분리(half-sent 방지).
      tmux send-keys -t "$ORCH_PANE" -l "@dispatch-fail: $dq_worker/$dq_task — dispatch.sh 실패(세션/페인/task 파일 확인)." 2>/dev/null
      tmux send-keys -t "$ORCH_PANE" Enter 2>/dev/null
    fi
    rm -f "$f" 2>/dev/null   # 소비 완료(성공·실패 무관 1회만 — 실패는 위에서 lead 통지)
  done

  # 1c) desk-queue 새 .json → ORCH 에 @desk: 전달 (P11 Phase4 탈-tmux: DESK 도 sandbox 안이라
  #     `tmux send-keys -t <orch> @desk:` 직접 못 함. DESK 는 desk-queue/<id>.json 에 지시를 파일로
  #     쓰고, watcher 가 폴링해 ORCH 페인에 대신 전달). dispatch-queue 분기와 동형. 처리 후 소비.
  for f in "$STATE_DIR"/desk-queue/*.json; do
    [ -f "$f" ] || continue
    desk_inst="$(jq -r '.instruction // empty' "$f" 2>/dev/null)"
    if [ -z "$desk_inst" ]; then
      rm -f "$f" 2>/dev/null   # 형식 불량 — 소비 폐기(무한 재시도 방지).
      continue
    fi
    pane_alive "$ORCH_PANE" || continue   # 죽은 pane 이면 소비 보류(살아나면 재시도 — .json 유지).
    # ORCH 가 @desk: 접두로 DESK 지시를 식별(사용자 입력과 구분). -l/Enter 분리(half-sent 방지).
    tmux send-keys -t "$ORCH_PANE" -l "@desk: $desk_inst" 2>/dev/null
    tmux send-keys -t "$ORCH_PANE" Enter 2>/dev/null
    rm -f "$f" 2>/dev/null   # 소비 완료.
  done

  # 2) events.log 증가 → reviewer 깨움(디바운스) + done 라인이면 lead 도
  cur="$(awk 'END{print NR}' "$EVENTS" 2>/dev/null || echo 0)"
  if [ "$cur" -gt "$last_events" ]; then
    now="$(date +%s)"
    # 새 구간에 done 라인이 있는지 — reviewer 깨움 게이트.
    # done 만이 강한 신호(결과물 의미 판정)이고 modify/allow-confirm 은 잡음이다.
    # 잡음마다 깨우면 Opus reviewer 가 매번 cursor~현재를 재검토해 처리량<유입량 적체
    # → 두 reviewer cursor 가 어긋나 합의 게이트 N 집계 불가(회로① 무력화, 라이브 실측).
    # done 시점에 reviewer 가 cursor 부터 전 구간을 처리하므로 그 사이 modify scope 위반도
    # 함께 검토된다 — 깨움을 done 으로 좁혀도 약한 신호 누락 없음.
    new_done="$(sed -n "$((last_events+1)),${cur}p" "$EVENTS" 2>/dev/null \
      | awk -F'\t' '$4=="done"{c++} END{print c+0}')"
    # M3: reviewer 디바운스 — 단 새 구간에 done 이 있을 때만 깨운다.
    if [ "$new_done" -gt 0 ] && [ "$((now - debounced_rev))" -ge "$REV_DEBOUNCE" ]; then
      for rp in $REVIEWER_PANES; do
        pane_alive "$rp" || continue
        # I-3 정정: review-manager 는 일반 @review: 깨움에서 제외 — drift-check 전용으로만 깨움.
        [ "$rp" = "$REVIEW_MANAGER_PANE" ] && continue
        # ★ 2026-06-03 라이브 수정: 단발 send-keys+Enter 는 codex TUI 가 Enter 를 씹어(P17
        #   리뷰어 변종) 검토 미시작 → quorum 미충족. send_prompt 는 입력창 잔류 폴링으로
        #   Enter 최대 8회 재시도 → codex 콜드스타트·렌더링 지연에도 제출 보장. 부트 경로와 통일.
        send_prompt "$rp" "@review: done 라인 발생. cursor 부터 증분 검토." 2>/dev/null
      done
      debounced_rev="$now"
    fi
    # C2: done 라인 worker/task 추출 → lead 알림 + ack 큐 적재. R3: while 은 서브셸 — wt 만 쓰고 외부변수 갱신 금지.
    # enqueue_pending_done 으로 pending-done/ 에 적재해 LEAD 점유 중 @done 소실 시 재발화 보장(회로① 침묵 차단).
    sed -n "$((last_events+1)),${cur}p" "$EVENTS" 2>/dev/null \
      | awk -F'\t' '$4=="done"{print $2"\t"$3}' \
      | while IFS=$'\t' read -r dw dt; do
          [ -n "$dw" ] && [ -n "$dt" ] || continue
          enqueue_pending_done "$STATE_DIR" "$dw" "$dt"   # ack 큐 적재(LEAD 가 종합 후 rm)
          pane_alive "$ORCH_PANE" || continue
          tmux send-keys -t "$ORCH_PANE" -l "@done: $dw/$dt 완료. results/ 확인 후 종합." 2>/dev/null
          tmux send-keys -t "$ORCH_PANE" Enter 2>/dev/null
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
          pane_alive "$ORCH_PANE" || continue
          tmux send-keys -t "$ORCH_PANE" -l "@plan-defect: $wt $desc" 2>/dev/null
          tmux send-keys -t "$ORCH_PANE" Enter 2>/dev/null
        done
    # @allow-confirm: 라인 payload(필드5 = pattern=...;role=...) 추출 → lead ⓘ 라우팅 (§7 Phase A).
    # AWA_AUTO_LEARN=1 (수집모드): ORCH push·사람 AskUserQuestion 우회 — watcher 가 직접
    #   confirm_allow_yaml accepted 호출해 learned-allow.yaml 영속화(무인 학습곡선 수집 전용).
    #   PROJECT_ROOT 는 awa-up 이 HARNESS_PROJECT 로 주입 → confirm_allow_yaml 이 PROJECT_ROOT 의존.
    sed -n "$((last_events+1)),${cur}p" "$EVENTS" 2>/dev/null \
      | awk -F'\t' '$4=="allow-confirm"{print $5}' \
      | while IFS= read -r payload; do
          [ -n "$payload" ] || continue
          if [ "${AWA_AUTO_LEARN:-0}" = "1" ]; then
            # payload = pattern=<...>;role=<...> → pattern 값만 추출(첫 key, ; 앞까지, pattern= 제거).
            _apat="${payload%%;*}"; _apat="${_apat#pattern=}"
            [ -n "$_apat" ] || continue
            # ★ HARNESS_PROJECT 로 전달 — lib.sh source 시 resolve_project_root 가 HARNESS_PROJECT 를
            #   최우선으로 PROJECT_ROOT 에 쓴다. PROJECT_ROOT 직접 주입은 source 시 git toplevel(본체)로
            #   덮어써져 무력화(실측). learned-allow.yaml 이 본체에 잘못 쓰이는 것 차단.
            HARNESS_PROJECT="${HARNESS_PROJECT:-}" LIB_PATH="$_WATCHER_DIR/lib.sh" bash -c \
              'source "$LIB_PATH" && confirm_allow_yaml "$1" accepted' _ "$_apat" >/dev/null 2>&1 || true
            continue
          fi
          pane_alive "$ORCH_PANE" || continue
          tmux send-keys -t "$ORCH_PANE" -l "@allow-confirm: $payload" 2>/dev/null
          tmux send-keys -t "$ORCH_PANE" Enter 2>/dev/null
        done
    last_events="$cur"   # 서브셸 밖에서 갱신 (R3 안전)
  fi

  # 3) @done ack 큐 재발화 — events 증가와 무관하게 매 사이클. LEAD 가 점유 중이라 @done 을
  #    놓쳤어도(미ack=pending-done/ 잔존) REQUEUE_AGE 초 뒤 재발화 → idle 복귀 시 도달.
  #    LEAD 가 ⓒ 종합 완료 후 해당 .json 을 rm(ack)하면 더는 재발화 안 함. 회로① 침묵 차단.
  if [ -n "$STATE_DIR" ] && [ -d "$STATE_DIR/pending-done" ]; then
    requeue_pending_done "$STATE_DIR" "$REQUEUE_AGE" 2>/dev/null \
      | while IFS= read -r rq; do
          [ -n "$rq" ] || continue
          pane_alive "$ORCH_PANE" || continue
          tmux send-keys -t "$ORCH_PANE" -l "@done: $rq 완료. results/ 확인 후 종합." 2>/dev/null
          tmux send-keys -t "$ORCH_PANE" Enter 2>/dev/null
        done
  fi

  # 3b) verdict glob — 투표 리뷰어 N 전원 도착 시 LEAD 재종합 깨움(단발 task 재종합 누락 차단).
  #     review/ Write 는 events.log 에 안 남으므로(log-event.sh:39 skip) 디렉토리를 직접 스캔.
  #     매 사이클 도되 .verdict-fired.<wid> 마커로 wid 당 1회만 발화. events 증가 무관(§2 아님).
  if [ -n "$STATE_DIR" ] && [ "$EXPECTED_VOTERS" -gt 0 ]; then
    _review_dir="$(dirname "$EVENTS")/review"
    scan_verdict_quorum "$_review_dir" "$STATE_DIR" "$EXPECTED_VOTERS" 2>/dev/null \
      | while IFS= read -r wid; do
          [ -n "$wid" ] || continue
          pane_alive "$ORCH_PANE" || continue
          tmux send-keys -t "$ORCH_PANE" -l "@verdict-arrived: $wid 투표 $EXPECTED_VOTERS종 전원 도착. review/ 재종합." 2>/dev/null
          tmux send-keys -t "$ORCH_PANE" Enter 2>/dev/null
        done
  fi

  sleep 1
done
