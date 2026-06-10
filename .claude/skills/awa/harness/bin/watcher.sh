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
#   REVIEW_WAKE_REQUEUE  reviewer 깨움 재발화 임계 초 (기본 120) — 3c cursor 정체 감지
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

# ORCH 알림 송신 — raw send-keys 금지 (R5, 2026-06-10 B3 '명령 깨짐' 수정).
# 기존 raw `send-keys -l`+Enter 는 ① busy ORCH 에 침묵 유실(I-1 동형) ② Enter 씹힘 시 다음
# 알림이 같은 입력줄에 *병합*돼 깨진 명령으로 제출(라이브 관측). → lib.sh send_prompt 경유
# (ready 폴링 + 송신 전 잔류 flush + 잔류 Enter 재시도 — flush 는 send_prompt 내장, R7).
# ready 대기는 짧게(기본 10×0.5=5s) — @gate/@done/@verdict 는 재발화 큐가 유실을 복구하므로
# 긴 블로킹으로 watcher 폴링 루프를 막지 않는다. send_prompt 부재(lib source 실패)시 raw 폴백.
notify_orch() {
  pane_alive "$ORCH_PANE" || return 0
  if ! type send_prompt >/dev/null 2>&1; then
    tmux send-keys -t "$ORCH_PANE" -l "$1" 2>/dev/null
    tmux send-keys -t "$ORCH_PANE" Enter 2>/dev/null
    return 0
  fi
  SEND_PROMPT_READY_MAX="${ORCH_NOTIFY_READY_MAX:-10}" send_prompt "$ORCH_PANE" "$1" 2>/dev/null
}

# last_events 를 기동 시 events.log 현재 줄 수로 초기화 (R4 — 첫 폴링 stale done 폭주 방지).
# 0 으로 두면 기동 첫 사이클이 events.log 전체를 "새 줄"로 간주해 과거 done 라인을 일제히
# @done: 재발화한다. 정상 흐름은 awa-down 이 events.log 를 지워 무해하나, 비정상 종료 후
# 재가동(events.log 잔존) 시 lead 가 이미 끝난 task 들을 재종합 — 현재 줄 수에서 시작해 차단.
last_events="$(awk 'END{print NR}' "$EVENTS" 2>/dev/null || echo 0)"
debounced_rev=0
last_done_line=0   # 마지막 done 발생 시점의 events.log 줄수 — 3c) reviewer 깨움 재발화 기준

# ── Stall watchdog (2026-06-09) ─────────────────────────────────────────────
# 결함 배경: watcher 는 events.log 가 *늘어날 때*만 반응한다(§2). 아무 일도 안 일어나면
# (전역 정체 — 명령 깨짐·송신 실패·워커 멈춤) 그냥 폴링만 하고 침묵 → 무한 대기. ORCH 도
# "워커가 일하는 중"인지 "멈춘 것"인지 구분 못 함. → events.log 가 STALL_THRESHOLD 초 동안
# 한 줄도 안 늘고 + 미완료(진행중) 워커가 있으면 ORCH 에 @stall 알림. 감지만 — 복구(재배정)는
# 판단 주체인 ORCH 몫(watcher 는 ORCH 역할 침범 안 함). 디바운스: 알린 뒤 STALL_THRESHOLD 마다 재발화.
STALL_THRESHOLD="${STALL_THRESHOLD:-180}"
case "$STALL_THRESHOLD" in ''|*[!0-9]*) STALL_THRESHOLD=180 ;; esac
last_activity_ts="$(date +%s)"   # 마지막 events.log 증가 시각
last_stall_fire=0                 # 마지막 @stall 발화 시각(디바운스)

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
    notify_orch "@gate: 워커 승인 대기 (uuid=$uuid). pending-asks 처리."
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
      :   # 성공 — dispatch.sh 가 워커 페인에 TASK 주입(수신 ack 확인됨). lead 통지 불필요(조용).
    elif [ "$_dq_rc" = 2 ]; then
      :   # 차단(계획 B 합의 게이트) — dispatch.sh 가 거부. 실패 아님이라 @dispatch-fail 통지 안 함.
          #   LEAD 가 차단 워커를 재배정한 경우라 조용히 소비(통지 루프 방지). 해소는 clear_block.
    elif [ "$_dq_rc" = 3 ]; then
      # ★ (a) 유실 의심(I-1, 2026-06-09): dispatch.sh 가 송신은 했으나 워커 수신 흔적(events.log
      #   새 액션) 무 → busy pane 유실 가능성. .json 을 소비하지 *않고* 재발화(다음 폴링에 워커가
      #   idle 됐으면 (b) ready 폴링이 통과해 정상 송신). pending-asks 와 동형 — .dispatch-fired
      #   마커로 REQUEUE_AGE 디바운스 + 최대 재시도(DISPATCH_REQUEUE_MAX) 후 단념(무한루프 차단).
      _df_key="$(_pd_sanitize "$dq_worker")__$(_pd_sanitize "$dq_task")"
      _df_marker="$STATE_DIR/dispatch-queue/.dispatch-fired.$_df_key"
      _df_cnt=0
      if [ -f "$_df_marker" ]; then
        _df_cnt="$(cat "$_df_marker" 2>/dev/null || echo 0)"
        case "$_df_cnt" in ''|*[!0-9]*) _df_cnt=0 ;; esac
      fi
      if [ "$_df_cnt" -ge "${DISPATCH_REQUEUE_MAX:-5}" ]; then
        # 단념 — 재시도 소진. lead 통지 후 소비(영구 박힘 방지).
        notify_orch "@dispatch-fail: $dq_worker/$dq_task — 수신 ack ${DISPATCH_REQUEUE_MAX:-5}회 실패. 워커 상태 확인 후 수동 재배정."
        rm -f "$_df_marker" 2>/dev/null
        rm -f "$f" 2>/dev/null
      else
        echo "$((_df_cnt+1))" > "$_df_marker" 2>/dev/null || true
        continue   # .json 유지 → 다음 폴링에 재발화(소비 안 함)
      fi
    else
      # 진짜 실패만 lead 에 통지(세션/페인/task 파일 이상).
      notify_orch "@dispatch-fail: $dq_worker/$dq_task — dispatch.sh 실패(세션/페인/task 파일 확인)."
    fi
    # 성공(0)·차단(2)·진짜실패(기타)·ack단념(3 소진) → 소비. ack 재시도(3 미소진)는 위 continue 로 유지.
    rm -f "$STATE_DIR/dispatch-queue/.dispatch-fired.$(_pd_sanitize "$dq_worker")__$(_pd_sanitize "$dq_task")" 2>/dev/null
    rm -f "$f" 2>/dev/null   # 소비 완료
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
    # ORCH 가 @desk: 접두로 DESK 지시를 식별(사용자 입력과 구분).
    notify_orch "@desk: $desk_inst"
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
    # done 발생 줄수 기록 — 3c) cursor 정체 비교 기준(깨움 디바운스와 무관하게 갱신).
    [ "$new_done" -gt 0 ] && last_done_line="$cur"
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
          notify_orch "@done: $dw/$dt 완료. results/ 확인 후 종합."
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
          notify_orch "@plan-defect: $wt $desc"
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
          notify_orch "@allow-confirm: $payload"
        done
    last_events="$cur"   # 서브셸 밖에서 갱신 (R3 안전)
    last_activity_ts="$now"   # stall watchdog: events.log 증가 = 활동 있음 → 정체 타이머 리셋
  fi

  # 3) @done ack 큐 재발화 — events 증가와 무관하게 매 사이클. LEAD 가 점유 중이라 @done 을
  #    놓쳤어도(미ack=pending-done/ 잔존) REQUEUE_AGE 초 뒤 재발화 → idle 복귀 시 도달.
  #    LEAD 가 ⓒ 종합 완료 후 해당 .json 을 rm(ack)하면 더는 재발화 안 함. 회로① 침묵 차단.
  if [ -n "$STATE_DIR" ] && [ -d "$STATE_DIR/pending-done" ]; then
    requeue_pending_done "$STATE_DIR" "$REQUEUE_AGE" 2>/dev/null \
      | while IFS= read -r rq; do
          [ -n "$rq" ] || continue
          notify_orch "@done: $rq 완료. results/ 확인 후 종합."
        done
  fi

  # 3b) verdict glob — 투표 리뷰어 N 전원 도착 시 LEAD 재종합 깨움(단발 task 재종합 누락 차단).
  #     review/ Write 는 events.log 에 안 남으므로(log-event.sh:39 skip) 디렉토리를 직접 스캔.
  #     ★ R1b-v2(2026-06-10 B4): ack = ORCH 가 `.verdict-ack.<wid>` touch(최신 verdict 라운드
  #     처리 표시). ack 없거나 verdict 가 더 새로우면 REQUEUE_AGE 마다 재발화. 구 rm 방식은
  #     무한 재발화 루프였다(scan_verdict_quorum 헤더 참조).
  if [ -n "$STATE_DIR" ] && [ "$EXPECTED_VOTERS" -gt 0 ]; then
    _review_dir="$(dirname "$EVENTS")/review"
    scan_verdict_quorum "$_review_dir" "$STATE_DIR" "$EXPECTED_VOTERS" "$REQUEUE_AGE" 2>/dev/null \
      | while IFS= read -r wid; do
          [ -n "$wid" ] || continue
          notify_orch "@verdict-arrived: $wid 투표 ${EXPECTED_VOTERS}종 전원 도착. review/ 재종합 후 ack 필수: touch .agent-harness/state/.verdict-ack.$wid (review/ 파일 이동·삭제 금지)."
        done
  fi

  # 3c) reviewer 깨움 재발화(R7, 2026-06-10 B4: T6·T7·T8 깨움 누락 — Enter 씹힘/콜드스타트로
  #     유실되면 verdict 가 영영 안 와 quorum 정체). 리뷰어는 검토 후 `.review-cursor.<역할명>`
  #     을 events.log 줄수로 갱신하므로(reviewer-common.md) 그게 자연 ack 다: done 발생 줄수
  #     (last_done_line)보다 cursor 가 뒤처진 채 REVIEW_WAKE_REQUEUE 초 지나면 재깨움.
  #     증분검토는 멱등("새 줄 없으면 아무것도 안 함")이라 중복 깨움 안전. 긴 정상 검토(>2분)
  #     중 재깨움은 입력창에 큐잉됐다 검토 후 처리됨(무해 잡음).
  if [ "$EXPECTED_VOTERS" -gt 0 ] && [ "${last_done_line:-0}" -gt 0 ]; then
    _rw_now="$(date +%s)"
    if [ $((_rw_now - debounced_rev)) -ge "${REVIEW_WAKE_REQUEUE:-120}" ]; then
      _hdir="$(dirname "$EVENTS")"
      _cur_cnt=0; _cur_min=-1
      for cf in "$_hdir"/.review-cursor.reviewer-*; do
        [ -f "$cf" ] || continue
        _cv="$(cat "$cf" 2>/dev/null)"; case "$_cv" in ''|*[!0-9]*) _cv=0 ;; esac
        _cur_cnt=$((_cur_cnt+1))
        if [ "$_cur_min" -lt 0 ] || [ "$_cv" -lt "$_cur_min" ]; then _cur_min="$_cv"; fi
      done
      [ "$_cur_min" -lt 0 ] && _cur_min=0
      # cursor 파일 수 < N(아직 한 번도 검토 안 한 리뷰어 존재) 또는 최소 cursor 가 done 줄수
      # 미달(검토 안 끝남/깨움 유실) → 전 리뷰어 재깨움(멱등).
      if [ "$_cur_cnt" -lt "$EXPECTED_VOTERS" ] || [ "$_cur_min" -lt "$last_done_line" ]; then
        for rp in $REVIEWER_PANES; do
          pane_alive "$rp" || continue
          [ "$rp" = "$REVIEW_MANAGER_PANE" ] && continue
          send_prompt "$rp" "@review: done 라인 발생. cursor 부터 증분 검토." 2>/dev/null
        done
        debounced_rev="$_rw_now"
      fi
    fi
  fi

  # 4) Stall watchdog — events.log 가 STALL_THRESHOLD 초 무증가 + 진짜 미완료 워커 존재 시
  #    ORCH 에 @stall 알림(감지만, 복구는 ORCH). 진단정보 동봉 — ORCH 가 "어디서 멈췄나" 판단하도록
  #    worker별 마지막 (action,task) 을 함께 전달(사용자 요구: 어디서 깨지고 어디부터 누락인지).
  #    ★ false-positive 차단: events.log 의 done 라인만 보면, 워커가 results/<task>.md 는 썼는데
  #      done 라인을 직접 안 찍은 '완료-idle' 을 정체로 오판한다(course 폭주 트리거였음). 그래서
  #      각 워커의 마지막 task 에 대한 results/<task>.md 가 존재하면 완료로 간주해 제외한다.
  _wd_now="$(date +%s)"
  if [ "$((_wd_now - last_activity_ts))" -ge "$STALL_THRESHOLD" ] && pane_alive "$ORCH_PANE"; then
    # 미완료 후보 = task 생애주기 action(task-start/modify/done)의 마지막이 done 아닌 worker.
    # ★ R2(2026-06-10 B3 오탐 수정): 비-생애주기 라인이 last action 을 오염시켰다 —
    #   ① watcher 자신이 쓰는 drift-check(task='-')가 done 직후 워커를 덮어 영구 stall 후보화
    #   ② user-ask(게이트 대기)는 pending-asks 재발화가 전담하는 대기라 stall 지목은 이중 잡음.
    #   → 생애주기 3종만 추적하고, *전체* 마지막 action 이 user-ask/plan-defect 인 워커는
    #   의도된 대기로 보고 제외. worker '-'(시스템 라인)는 기존대로 제외.
    _RESULTS_DIR="$(dirname "$EVENTS")/results"
    _stuck_cand="$(awk -F'\t' '$2!="-" && $2!=""{
                            if($4=="task-start"||$4=="modify"||$4=="done"){la[$2]=$4; lt[$2]=$3}
                            oa[$2]=$4}
                          END{for(w in la) if(la[w]!="done" && oa[w]!="user-ask" && oa[w]!="plan-defect")
                            printf "%s|%s|%s\n", w, lt[w], la[w]}' \
              "$EVENTS" 2>/dev/null)"
    # results/<task>.md 존재 = 완료로 간주, _stuck 에서 제외(진짜 미완료만 남김).
    _stuck=""
    while IFS='|' read -r _w _t _a; do
      [ -n "$_w" ] || continue
      if [ -n "$_t" ] && [ -f "$_RESULTS_DIR/$_t.md" ]; then continue; fi  # 완료-idle → 제외
      _stuck="${_stuck}${_w}(${_a}@${_t}) "
    done <<EOF
$_stuck_cand
EOF
    if [ -n "$_stuck" ] && [ "$((_wd_now - last_stall_fire))" -ge "$STALL_THRESHOLD" ]; then
      _idle_sec="$((_wd_now - last_activity_ts))"
      # ⚠ ORCH 에게 AskUserQuestion 을 유발하지 않는다 — @stall 는 진단·재배정 트리거일 뿐.
      #   사용자 push 는 orch.md ⓙ 가 '재배정해도 2회+ 반복 정체' 일 때만(course 폭주 차단).
      notify_orch "@stall: ${_idle_sec}초간 events.log 무활동. results 미생성 미완료 워커: ${_stuck}— 각 워커 pane 을 capture-pane 으로 진단(입력창 박힘/오류정지/정상 장시간)하고 필요하면 dispatch-queue 로 재배정하라. 사용자에게 묻지 말고 직접 진단·복구하라."
      last_stall_fire="$_wd_now"
    fi
  fi

  sleep 1
done
