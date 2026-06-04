#!/usr/bin/env bash
# M3 라이브 관측 셋업 (13차 후속 — 매니저 YAGNI 완전 종결의 마지막 빈칸).
#
# 목적: 실 claude LEAD 가 다수 워커의 "동시 @done:" 을 받아 각 task 결과를
#   *올바른 task 에 귀속*해 종합하는지(오배달 0)를 결정론적으로 관측한다.
#   1단계 stress 는 "신호가 안 샌다"(M1·M4)만 입증했다. M3 = "LEAD 가 제대로
#   읽고 종합한다" 는 실 claude 가 있어야만 측정된다 → 이 스크립트가 그 자리.
#
# 토큰 경계: claude 기동이 들어가므로 **사용자가 `!` 로 실행**해야 한다.
#   (어시스턴트는 claude 직접 실행 금지.) 워커는 더미(토큰0), LEAD 만 실 claude.
#
# 구성:
#   - LEAD pane = 실 claude (--settings 없이 기본 — 관측이라 권한게이트 불필요).
#   - 더미 워커 pane N=6 (토폴로지 동형용. 부하는 스크립트가 events.log 로 직접 주입).
#   - watcher 백그라운드 (실경로): events.log done 라인 → LEAD 에 @done: 6연발.
#   - results/T1..T6.md 에 고유 MARKER 사전 주입 (ALPHA..FOXTROT). 내용도 task 별 구별.
#   - LEAD 에게 "각 @done task 의 results 를 읽고 MARKER 를 .harness-state 에
#     `T<n>: <marker>` 한 줄씩 atomic 기록" 지시 → 채점 가능한 결정론적 형식.
#
# 셋업 후: LEAD 가 6개 @done 을 받아 종합한다. ~30~60초 뒤 m3-score.sh 로 자동 채점.
set -uo pipefail
cd "$(dirname "$0")"
ROOT="$(cd ../.. && pwd)"

N=6
SES="m3_$$"
# PROJECT_ROOT: 격리된 임시 디렉터리. LEAD pane cwd 가 여기 → .agent-harness/ 가 여기 생성.
PROJ="$(mktemp -d)"
WS="$PROJ/.agent-harness"
EVENTS="$WS/events.log"
mkdir -p "$WS/results" "$WS/state/pending-asks"
: > "$EVENTS"   # 빈 events.log (watcher last_events=0 → 이후 주입분만 새 줄로 인지)

# 마커 테이블 (bash 3.2 — 연관배열 미지원, 인덱스 정렬 2배열).
MARKERS="ALPHA BRAVO CHARLIE DELTA ECHO FOXTROT"
# task 별 구별되는 요지 (혼선 시 내용까지 뒤바뀜이 드러나도록).
DESCS="인증모듈 결제연동 로그수집 캐시계층 알림발송 검색색인"

# --- results/T1..T6.md 사전 주입 (각 고유 MARKER + 구별 내용) ---
i=0
for m in $MARKERS; do
  i=$((i+1))
  desc="$(printf '%s\n' $DESCS | sed -n "${i}p")"
  {
    echo "# 결과 T$i"
    echo "MARKER: $m"
    echo "요지: $desc"
    echo "상태: SUCCESS"
  } > "$WS/results/T$i.md"
done

# --- 더미 세션: LEAD pane(곧 실 claude) + 더미 워커 pane N ---
# LEAD pane 은 PROJECT_ROOT 에서 셸로 시작 → 아래에서 claude 기동.
tmux new-session -d -s "$SES" -c "$PROJ" -x 220 -y 50 -n team
ORCH_PANE="$(tmux display-message -p -t "$SES" '#{pane_id}')"
tmux select-pane -t "$ORCH_PANE" -T "ORCH"
i=0
while [ "$i" -lt "$N" ]; do
  i=$((i+1))
  tmux split-window -t "$SES" -d -c "$PROJ" 2>/dev/null || true   # 토폴로지 동형(더미 셸)
done
tmux select-layout -t "$SES" tiled 2>/dev/null || true

# --- LEAD 에 실 claude 기동 ---
# 관측용 최소 기동: --settings/--session-id 없이 기본 claude.
# --dangerously-skip-permissions: 관측 격리라 권한게이트 불필요. 이게 없으면 LEAD 가
#   .harness-state atomic write(cat>tmp && mv) 시 권한 다이얼로그에서 멈춰 사람 개입을
#   요구한다 → "LEAD 단독 종합" 순수 관측이 깨지고 재현이 번거로움. 임시 PROJECT_ROOT
#   (mktemp)에서만 도는 격리 관측이라 안전.
tmux send-keys -t "$ORCH_PANE" -l "claude --dangerously-skip-permissions"
tmux send-keys -t "$ORCH_PANE" Enter
# REPL 준비 폴링 (awa-up wait_repl 패턴 축약).
ready=0
for _i in $(seq 1 60); do
  sleep 2
  # -S -200: 스크롤백 포함 캡처. 현 화면만 보면 welcome 박스 헤더(ready 신호)가
  # 위로 밀려 false negative → 영구 폴링 hang(실측 2026-05-25). awa-up
  # bootstrap_pane 과 동일 정책. [[wait-repl-pattern-fragility]] 회피.
  dump="$(tmux capture-pane -t "$ORCH_PANE" -p -S -200 2>/dev/null)"
  # trust 화면 + --dangerously-skip-permissions 첫 실행 경고 수락 화면 모두 기본선택 Enter 통과.
  # (경고 화면이 안 뜨면 안 매칭될 뿐 — 안전망.)
  if printf '%s' "$dump" | grep -Eq 'trust this folder|Yes, I trust|accept the risk|bypass permissions and continue|skip all permission'; then
    tmux send-keys -t "$ORCH_PANE" Enter; continue
  fi
  if printf '%s' "$dump" | grep -qE 'Claude Code v[0-9]|Welcome back|bypass permissions on|accept edits on'; then
    ready=1; break
  fi
done
if [ "$ready" != "1" ]; then
  echo "오류: LEAD claude REPL 준비 실패. tmux attach -t $SES 로 확인 필요." >&2
  echo "  (세션 유지 — 수동 디버그 후 tmux kill-session -t $SES)" >&2
  exit 1
fi

# --- LEAD 에게 관측용 규약 주입 (채점 가능한 결정론적 종합 형식) ---
# orch.md 책임 #2(@done→results 읽기)·#6(.harness-state atomic 기록)을 그대로 쓰되,
# 채점을 위해 "T<n>: <marker>" 고정 형식을 명시. 권한게이트/AskUserQuestion 불필요(관측).
LEAD_BRIEF="너는 이 관측의 LEAD 다. 잠시 후 watcher 가 '@done: dev<k>/T<k> 완료...' 형식의 완료 알림 6개를 연달아 보낸다(T1~T6). 각 알림을 받을 때마다 해당 .agent-harness/results/T<k>.md 를 읽고, 그 파일의 'MARKER:' 값을 추출하라. 6개를 모두 받으면 종합 결과를 .agent-harness/.harness-state 에 다음 고정 형식으로 atomic 기록하라(부분 read 방지: tmp 작성 후 mv). 형식은 정확히 한 줄에 하나씩 'T<번호>: <MARKER값>' (예 'T1: ALPHA'), T1부터 T6까지 6줄. 다른 설명/머리말 없이 6줄만. AskUserQuestion 호출하지 마라(이건 관측이라 사용자 판단 불필요). 지금은 알림을 기다려라."
tmux send-keys -t "$ORCH_PANE" -l "$LEAD_BRIEF"
tmux send-keys -t "$ORCH_PANE" Enter
sleep 3   # LEAD 가 브리핑 수신·idle 진입 여유

# --- watcher 백그라운드 기동 (실경로) ---
SESSION="$SES" ORCH_PANE="$ORCH_PANE" REVIEWER_PANES="" \
STATE_DIR="$WS/state" EVENTS="$EVENTS" SEEN="$WS/state/.watcher-seen" \
  bash "$ROOT/bin/watcher.sh" &
WPID=$!
# WPID 를 파일로 남겨 score/teardown 이 정리 (이 스크립트는 사용자 ! 로 떠서 곧 종료).
echo "$WPID" > "$WS/.watcher.pid"
echo "$SES"  > "$WS/.session"
echo "$PROJ" > /tmp/m3-last-proj   # score 가 읽을 PROJECT_ROOT 포인터
sleep 2.5   # 첫 폴링 사이클 보장 (last_events=0 확정)

# --- 부하 주입: done 6개 동시 (events.log 일괄 append) ---
# watcher done 검출: awk -F'\t' '$4=="done"{print $2"/"$3}'. 5필드: ts worker task action path.
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
{
  i=0
  while [ "$i" -lt "$N" ]; do
    i=$((i+1))
    printf '%s\tdev%s\tT%s\tdone\t-\n' "$ts" "$i" "$i"
  done
} >> "$EVENTS"

echo "=== M3 셋업 완료 ==="
echo "세션: $SES   PROJECT_ROOT: $PROJ"
echo "워커 N=$N, results/T1..T6 에 마커 ALPHA..FOXTROT 주입, done 6개 일괄 기록."
echo "watcher(PID $WPID)가 LEAD($ORCH_PANE)에 @done: 6연발 주입 → 실 claude LEAD 가 종합 중."
echo
echo "LEAD 종합을 눈으로 보려면:  tmux attach -t $SES"
echo "30~60초 뒤 자동 채점:        bash $ROOT/tests/m3/m3-score.sh"
echo "(채점은 토큰0 — .harness-state 대조만)"
