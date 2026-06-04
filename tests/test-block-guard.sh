#!/usr/bin/env bash
# tests/test-block-guard.sh — dispatch 차단 가드 (회로① 합의 게이트 집행)
# Layer 1: orch.md ⓒ 합의 분기 + dispatch.sh 가드 호출 grep (Task 2/4 에서 추가)
# Layer 2: lib.sh is_worker_blocked/record_block/clear_block/quarantine_block 동작
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

# lib.sh source (STATE_DIR 을 TMPDIR 로 격리)
source "$ROOT/bin/lib.sh"
STATE_DIR="$TMPDIR/state"   # 운영 state 오염 차단

# Layer 2-a: 차단 없으면 is_worker_blocked = 1 (비차단=rc 1)
is_worker_blocked "dev"
assert_eq "1" "$?" "L2 비차단 워커는 rc 1 (dispatch 허용)"

# Layer 2-b: record_block 후 is_worker_blocked = 0 (차단=rc 0)
record_block "dev" "T3" "보안 VIOLATION 만장일치"
assert_success "$?" "L2 record_block 성공"
test -f "$STATE_DIR/blocked-workers/dev.json"
assert_success "$?" "L2 blocked-workers/dev.json 생성됨"
is_worker_blocked "dev"
assert_eq "0" "$?" "L2 차단 워커는 rc 0 (dispatch 거부)"

# Layer 2-c: attempt 카운터 증가 (재차단)
record_block "dev" "T3" "재판정도 VIOLATION"
att="$(jq -r '.attempt' "$STATE_DIR/blocked-workers/dev.json")"
assert_eq "2" "$att" "L2 재 record_block 시 attempt=2"

# Layer 2-c2: 손상 attempt (비숫자) 회귀 — set -u 치명사 안 나고 1 로 복구 후 ++
printf '{"worker":"carol","task_id":"T5","attempt":"corrupt","reason":"x"}' > "$STATE_DIR/blocked-workers/carol.json" 2>/dev/null || { mkdir -p "$STATE_DIR/blocked-workers"; printf '{"worker":"carol","task_id":"T5","attempt":"corrupt","reason":"x"}' > "$STATE_DIR/blocked-workers/carol.json"; }
record_block "carol" "T5" "손상 후 재기록"
assert_success "$?" "L2 손상 attempt 에도 record_block 성공(치명사 없음)"
att2="$(jq -r '.attempt' "$STATE_DIR/blocked-workers/carol.json")"
assert_eq "2" "$att2" "L2 손상 attempt 는 1 로 복구 후 ++ → 2"

# Layer 2-d: clear_block 후 비차단 복귀
clear_block "dev"
assert_success "$?" "L2 clear_block 성공"
is_worker_blocked "dev"
assert_eq "1" "$?" "L2 clear 후 비차단 (dispatch 재허용)"

# Layer 2-e: quarantine — attempt>=K 시 격리 큐로 이동
record_block "alice" "T9" "1차"
record_block "alice" "T9" "2차 (K=2 도달)"
quarantine_block "alice"
assert_success "$?" "L2 quarantine_block 성공"
test -f "$STATE_DIR/quarantine/alice.json"
assert_success "$?" "L2 quarantine/alice.json 으로 이동됨"
test ! -f "$STATE_DIR/blocked-workers/alice.json"
assert_success "$?" "L2 격리 후 blocked-workers 에서 제거됨"
is_worker_blocked "alice"
assert_eq "1" "$?" "L2 격리된 워커는 blocked-workers 비어 비차단 (다른 task 진행 가능)"

# Layer 2-f: BLOCK_RETRY_LIMIT 상수 노출
assert_eq "2" "$BLOCK_RETRY_LIMIT" "L2 BLOCK_RETRY_LIMIT=2 상수"

# Layer 1: dispatch.sh 가 send 전 is_worker_blocked 가드를 호출하는가
grep -q 'is_worker_blocked' "$ROOT/bin/dispatch.sh"
assert_success "$?" "L1 dispatch.sh 가 is_worker_blocked 가드 호출"
# 가드가 write_harness_task/send_prompt *앞* 에 와야 차단이 dispatch 를 막는다
guard_ln="$(grep -n 'is_worker_blocked' "$ROOT/bin/dispatch.sh" | head -1 | cut -d: -f1)"
send_ln="$(grep -n 'send_prompt' "$ROOT/bin/dispatch.sh" | head -1 | cut -d: -f1)"
[ -n "$guard_ln" ] && [ -n "$send_ln" ] && [ "$guard_ln" -lt "$send_ln" ]
assert_success "$?" "L1 가드가 send_prompt 앞에 위치 (차단이 송신을 막음)"
# 가드가 TARGET 페인 탐색(TASK_FILE 확인 포함) *앞* 이어야 차단이 페인 존재와 독립 (통지 루프 방지)
taskfile_ln="$(grep -n 'TASK_FILE=' "$ROOT/bin/dispatch.sh" | head -1 | cut -d: -f1)"
[ -n "$guard_ln" ] && [ -n "$taskfile_ln" ] && [ "$guard_ln" -lt "$taskfile_ln" ]
assert_success "$?" "L1 가드가 TASK_FILE/페인 탐색 앞 (차단이 페인 존재와 독립)"

# Layer 1: watcher.sh 가 dispatch exit 2(차단)를 @dispatch-fail 로 오인하지 않는가
grep -qE '_dq_rc.*=.*2|= "2"' "$ROOT/bin/watcher.sh"
assert_success "$?" "L1 watcher 가 exit 2(차단)를 별도 분기로 skip"

# Layer 2-g: 전체 흐름 — 차단 → 재판정 OK 해소 → 다시 차단 누적 → 격리
clear_block "bob"; quarantine_block "bob" 2>/dev/null || true
record_block "bob" "T1" "1차 차단"
is_worker_blocked "bob"; assert_eq "0" "$?" "L2 흐름: 1차 차단됨"
clear_block "bob"
is_worker_blocked "bob"; assert_eq "1" "$?" "L2 흐름: 재판정 OK 로 해소"
# 다시 문제 → K 도달까지 누적
record_block "bob" "T1" "재발 1"
record_block "bob" "T1" "재발 2"
att="$(jq -r '.attempt' "$TMPDIR/state/blocked-workers/bob.json")"
[ "$att" -ge "$BLOCK_RETRY_LIMIT" ]
assert_success "$?" "L2 흐름: attempt($att) >= K($BLOCK_RETRY_LIMIT) — 격리 조건 충족"
quarantine_block "bob"
is_worker_blocked "bob"; assert_eq "1" "$?" "L2 흐름: 격리 후 워커는 다른 task dispatch 가능"
test -f "$TMPDIR/state/quarantine/bob.json"
assert_success "$?" "L2 흐름: 격리 task 는 quarantine 에 보존 (LEAD 가 사용자 push)"

# Layer 1: orch.md ⓒ 가 합의 게이트(만장일치 record_block / 불일치 push)를 명시
grep -q 'record_block' "$ROOT/prompts/roles/01-orchestration/orch.md"
assert_success "$?" "L1 orch.md 가 record_block 호출 명시"
grep -qE '만장일치|전원 blocking|투표인단' "$ROOT/prompts/roles/01-orchestration/orch.md"
assert_success "$?" "L1 orch.md 가 합의 게이트(만장일치) 분기 명시"
grep -q 'clear_block' "$ROOT/prompts/roles/01-orchestration/orch.md"
assert_success "$?" "L1 orch.md 가 재판정 OK 해소(clear_block) 명시"


# Layer 2-h: quarantine 후 *같은 task* 재차단 시 attempt 누적 (무한 차단↔격리 방지)
clear_block "qw"; rm -f "$STATE_DIR/quarantine/qw.json" 2>/dev/null
record_block "qw" "T1" "1차"; record_block "qw" "T1" "2차"
quarantine_block "qw"
record_block "qw" "T1" "격리 후 같은 task 재차단"
att_q="$(jq -r '.attempt' "$STATE_DIR/blocked-workers/qw.json")"
[ "$att_q" -ge 3 ]
assert_success "$?" "L2 격리 후 같은 task 재차단은 attempt 누적($att_q>=3) — 무한반복 방지"

# Layer 2-i: worker명 경로주입 차단
record_block "../pwn" "T1" "공격" 2>/dev/null
assert_eq "1" "$?" "L2 ../ 포함 worker명은 record_block 거부(rc 1)"
test ! -f "$STATE_DIR/pwn.json"
assert_success "$?" "L2 경로주입 파일이 state 밖에 안 생김"
is_worker_blocked "../etc"
assert_eq "1" "$?" "L2 경로주입 worker명은 비차단 취급(안전)"

# Layer 2-j: 운영 state 비오염 단언 (테스트가 TMPDIR 격리됐는지)
case "$(_block_state_dir)" in
  "$TMPDIR"*) assert_success "0" "L2 _block_state_dir 가 TMPDIR 하위(운영 state 비오염)" ;;
  *) assert_success "1" "L2 격리 실패 — _block_state_dir 가 TMPDIR 밖: $(_block_state_dir)" ;;
esac

# Layer 1: orch.md ⓒ 가 실제 리뷰어 파일명 규약(.alignment-rev/.quality-rev/.security-rev)을 명시
# (모호한 <리뷰어> 토큰으로 되돌리면 blocking 집계 0건→만장일치 차단 영원히 미발동 — 회로 무력화 회귀 방지)
LEAD_F="$ROOT/prompts/roles/01-orchestration/orch.md"
grep -q 'alignment-rev' "$LEAD_F"
assert_success "$?" "L1 orch.md 가 .alignment-rev 파일명 규약 명시(토큰 되돌림 회귀 방지)"
grep -q 'quality-rev' "$LEAD_F"
assert_success "$?" "L1 orch.md 가 .quality-rev 파일명 규약 명시"
grep -q 'security-rev' "$LEAD_F"
assert_success "$?" "L1 orch.md 가 .security-rev 파일명 규약 명시"

# Layer 2: dispatch.sh 가 차단 워커에 정확히 exit 2 (exit 1 로 바뀌면 watcher 오통지 — M1 회귀)
# 격리 프로젝트 + tmux 세션에서 실제 실행. dispatch.sh 는 차단 가드(L55)가 세션 확인(L46) *뒤*라
# 세션이 있어야 차단 가드에 도달한다. resolve_session 은 SESSION_OVERRIDE 로 세션명 주입이 가능하므로
# 테스트가 만든 세션명을 정확히 맞춰 *정확한 exit 2* 를 단언한다(보수적 fallback 불필요).
if command -v tmux >/dev/null 2>&1; then
  DT="$(mktemp -d)"
  ( cd "$DT" && git init -q 2>/dev/null )
  mkdir -p "$DT/.agent-harness/state/blocked-workers" "$DT/.agent-harness/tasks"
  printf '{"worker":"blkw","task_id":"BT","attempt":1,"reason":"t"}' > "$DT/.agent-harness/state/blocked-workers/blkw.json"
  _sess="awatest_blk_$$"
  if tmux new-session -d -s "$_sess" 2>/dev/null; then
    _rc=0
    # SESSION_OVERRIDE 로 resolve_session 을 격리 세션명에 고정 → 세션 확인 통과 → 차단 가드 도달.
    SESSION_OVERRIDE="$_sess" \
      bash "$ROOT/bin/dispatch.sh" --project "$DT" blkw BT >/dev/null 2>&1 || _rc=$?
    tmux kill-session -t "$_sess" 2>/dev/null
    # 차단 파일이 있는데 통과(exit 0)면 명백한 가드 실패. exit 2 가 정상 차단 종료코드.
    assert_eq "2" "$_rc" "L2 차단 워커 dispatch 가 정확히 exit 2 (exit 1 회귀 직접 탐지)"
  fi
  rm -rf "$DT"
fi


# Layer 2-k: clear_block 이 quarantine 도 청산 (영속 낙인 방지)
clear_block "qc"; rm -f "$STATE_DIR/quarantine/qc.json" 2>/dev/null
record_block "qc" "T1" "1차"; record_block "qc" "T1" "2차"; quarantine_block "qc"
test -f "$STATE_DIR/quarantine/qc.json"
assert_success "$?" "L2 격리 파일 생성됨(전제)"
clear_block "qc"
test ! -f "$STATE_DIR/quarantine/qc.json"
assert_success "$?" "L2 clear_block 이 quarantine 도 청산(영속 낙인 방지)"

# Layer 2-l: 격리 후 *다른 task* 재차단은 attempt 리셋(낙인 안 찍힘)
clear_block "qd"; rm -f "$STATE_DIR/quarantine/qd.json" 2>/dev/null
record_block "qd" "TA" "1차"; record_block "qd" "TA" "2차"; quarantine_block "qd"
record_block "qd" "TB" "다른 task 1회 차단"
att_d="$(jq -r '.attempt' "$STATE_DIR/blocked-workers/qd.json")"
assert_eq "1" "$att_d" "L2 격리 후 다른 task(TB) 재차단은 attempt=1 리셋(영속 낙인 방지)"

# Layer 2-m: 격리 후 *같은 task* 재차단은 attempt 누적(무한반복 방지 — 기존 동작 유지)
clear_block "qe"; rm -f "$STATE_DIR/quarantine/qe.json" 2>/dev/null
record_block "qe" "TX" "1차"; record_block "qe" "TX" "2차"; quarantine_block "qe"
record_block "qe" "TX" "같은 task 재차단"
att_e="$(jq -r '.attempt' "$STATE_DIR/blocked-workers/qe.json")"
[ "$att_e" -ge 3 ]
assert_success "$?" "L2 격리 후 같은 task(TX) 재차단은 attempt 누적($att_e>=3) — 무한반복 방지 유지"

# Layer 2-n: 회로① 단계3 라이브 — watcher 가 차단 워커의 dispatch-queue 를 처리할 때
# dispatch.sh exit 2(차단) 를 *조용히 소비* 하는가(=@dispatch-fail 미발화 + 큐 .json rm).
# L74-76 의 grep 검증(분기 존재)을 *실 watcher 한 사이클 라이브 발동* 으로 보강한다.
#
# ⚠️ 양성신호 대조쌍(코드리뷰 Important): "차단 워커 @dispatch-fail 미발화" 만으론
# watcher 미기동/조기사망/형식불량 폐기(watcher.sh L75-78) 시에도 빈 캡처라 항상-PASS 된다
# (assert_not_contains "" "@dispatch-fail" 은 무조건 통과). 즉 exit 2 분기를 *실제로 탔다*는
# 양성 보장이 없다. 따라서 같은 watcher 사이클에 *비차단 대조* 워커를 함께 넣는다:
#   - 차단 워커(blkw2): blocked-workers 있음 → dispatch.sh exit 2 → @dispatch-fail: blkw2/ 미발화.
#   - 비차단 워커(okw): blocked-workers 없음 + task 파일 없음 → dispatch.sh L62 exit 1
#     → watcher 가 @dispatch-fail: okw/ *발화*. (세션은 둘 다 통과 — dispatch.sh L46 세션 확인.)
# 통지 문구가 `@dispatch-fail: $dq_worker/$dq_task — ...`(watcher.sh:92)라 워커명으로 구분한다.
# 비차단 발화 단언이 watcher 미기동 시 FAIL → "차단 미발화"가 빈 캡처 아닌 *차단 분기 때문*임을 입증.
#
# 메커니즘: watcher.sh 는 dispatch.sh 를 `--project "$HARNESS_PROJECT"` 로 대행 호출한다.
# 이때 dispatch.sh 의 PROJECT_ROOT = 격리 projdir → STATE_DIR 미설정이라
# is_worker_blocked 가 보는 _block_state_dir = "$projdir/.agent-harness/state".
# 또 dispatch.sh 는 SESSION_OVERRIDE 를 못 받으므로 resolve_session 이 자동명
# (awa-<basename(projdir)>) 으로 세션을 도출 → 우리가 그 자동명으로 tmux 세션을 만들어야
# 세션 확인(dispatch.sh:46)을 통과해 차단 가드(dispatch.sh:55, exit 2)에 도달한다.
if command -v tmux >/dev/null 2>&1; then
  WDIR="$(mktemp -d)"
  ( cd "$WDIR" && git init -q 2>/dev/null )
  mkdir -p "$WDIR/.agent-harness/state/blocked-workers" \
           "$WDIR/.agent-harness/state/dispatch-queue" \
           "$WDIR/.agent-harness/tasks"
  # 격리 projdir basename → dispatch.sh 가 도출할 세션 자동명과 일치시킨다.
  _wsess="awa-$(basename "$WDIR" | sed 's/[^A-Za-z0-9_-]/_/g')"
  _wevents="$WDIR/.agent-harness/events.log"
  : > "$_wevents"
  # watcher 좀비 방지: EXIT trap 에 세션 kill 누적(기존 TMPDIR rm 유지). 중간 실패에도 정리 보장.
  trap 'tmux kill-session -t "'"$_wsess"'" 2>/dev/null; rm -rf "'"$WDIR"'" "$TMPDIR"' EXIT
  if tmux new-session -d -s "$_wsess" 2>/dev/null; then
    _worch="$(tmux list-panes -t "$_wsess" -F '#{pane_id}' | head -1)"
    # 차단 워커 큐(q1): blocked-workers 있음 → exit 2. task 파일은 둬도 차단 가드(L55)가
    # task 확인(L60)보다 앞이라 무관 — 차단이 우선해 exit 2.
    printf '{"worker":"blkw2","task_id":"BQ","attempt":1,"reason":"t"}' \
      > "$WDIR/.agent-harness/state/blocked-workers/blkw2.json"
    _qfile="$WDIR/.agent-harness/state/dispatch-queue/q1.json"
    printf '{"worker":"blkw2","task_id":"BQ"}' > "$_qfile"
    # 비차단 대조 큐(q2): blocked-workers 없음(okw) + task 파일 없음 → dispatch.sh 가
    # 세션 통과(L46) → 차단 안 됨 → task 파일 없음(L62) → exit 1 → watcher 가 @dispatch-fail 발화.
    _qfile2="$WDIR/.agent-harness/state/dispatch-queue/q2.json"
    printf '{"worker":"okw","task_id":"OQ"}' > "$_qfile2"
    # watcher 한 사이클 라이브 기동(백그라운드). STATE_DIR/EVENTS/HARNESS_PROJECT 정확 주입.
    SESSION="$_wsess" ORCH_PANE="$_worch" \
      STATE_DIR="$WDIR/.agent-harness/state" EVENTS="$_wevents" \
      HARNESS_PROJECT="$WDIR" \
      bash "$ROOT/bin/watcher.sh" >/dev/null 2>&1 &
    _wpid=$!
    # 두 큐 파일 *모두* 소멸을 폴링(watcher sleep 1 주기 + 처리 여유). 무한 sleep 금지.
    # 비차단 대조 추가로 watcher 가 두 큐를 처리할 시간 필요 → 타임아웃 여유(20→30).
    for _i in $(seq 1 30); do
      [ -f "$_qfile" ] || [ -f "$_qfile2" ] || break
      sleep 0.5
    done
    # 발화 통지가 입력창에 쌓일 시간 한 박자 확보(send-keys 직후 capture 레이스 완화).
    sleep 0.5
    _wcap="$(tmux capture-pane -p -t "$_worch" 2>/dev/null || true)"
    # (a) 차단 워커는 @dispatch-fail 미발화 — exit 2 를 조용히 소비. 워커명으로 정밀 구분.
    assert_not_contains "$_wcap" "@dispatch-fail: blkw2/" \
      "L2 단계3: 차단 워커(blkw2) dispatch-queue 처리 시 @dispatch-fail 미발화(조용한 소비)"
    # (a') 양성신호 대조 — 비차단 워커(okw)는 exit 1 → @dispatch-fail 발화해야 한다.
    #      watcher 미기동/조기사망이면 빈 캡처라 이 단언이 FAIL → 항상-PASS 약점 차단.
    #      이게 발화하므로 (a)의 미발화가 빈 캡처 아닌 *차단 분기(exit 2)* 때문임이 입증된다.
    assert_contains "$_wcap" "@dispatch-fail: okw/" \
      "L2 단계3 양성신호: 비차단 워커(okw) exit 1 → @dispatch-fail 발화(차단 분기 실증·항상PASS 차단)"
    # (b) 두 큐 .json 모두 rm 소비 — watcher 가 처리 후 dispatch-queue/<id>.json 을 제거.
    test ! -f "$_qfile" && test ! -f "$_qfile2"
    assert_success "$?" "L2 단계3: watcher 가 차단·비차단 dispatch-queue .json 을 모두 rm 소비"
    # watcher 종료(세션 kill → while tmux has-session 탈출). trap 도 보강하지만 즉시 정리.
    tmux kill-session -t "$_wsess" 2>/dev/null
    wait "$_wpid" 2>/dev/null || true
  fi
  rm -rf "$WDIR"
  trap 'rm -rf "$TMPDIR"' EXIT   # EXIT trap 을 원복(다른 테스트/정리 영향 없게)
fi


test_summary
