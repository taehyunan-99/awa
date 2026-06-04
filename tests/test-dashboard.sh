#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"

# 사용자 실 _DASHBOARD 보호 — 격리 세션명.
export AWA_DASH_NAME="_DASHBOARD_TEST_$$"
DASH="$AWA_DASH_NAME"

# bookmarks 격리 (awa-up.sh 가 ~/.config/awa/bookmarks.tsv 기록 — 본 테스트는 awa-up 미호출이나 방어).
_AWA15_XDG="$(mktemp -d)"
export XDG_CONFIG_HOME="$_AWA15_XDG"

trap '
  tmux kill-session -t "$DASH" 2>/dev/null
  for s in _S_A_$$ _S_B_$$ _S_C_$$ _S_D_$$; do tmux kill-session -t "$s" 2>/dev/null; done
  rm -rf "$_AWA15_XDG"
' EXIT

# fixture: team 윈도우에 lead|pm pane(@awa-role 세팅) + workers 윈도우.
# 운영에선 awa-up.sh 가 @awa-role 을 세팅하나, 테스트는 부트를 안 거치므로 fixture 가 모사.
mk_src() {
  local s="${1:-}"
  [ -n "$s" ] || { echo "오류: mk_src 인자 필요" >&2; return 1; }
  tmux kill-session -t "$s" 2>/dev/null || true
  tmux new-session -d -s "$s" -n team -x 200 -y 50
  local orch_p desk_p
  orch_p="$(tmux list-panes -t "${s}:team" -F '#{pane_id}' | head -1)"
  desk_p="$(tmux split-window -h -t "$orch_p" -d -P -F '#{pane_id}')"
  tmux set-option -p -t "$orch_p" @awa-role orch
  tmux set-option -p -t "$desk_p"   @awa-role desk
  tmux select-pane -t "$orch_p" -T "ORCH"
  tmux select-pane -t "$desk_p"   -T "DESK"
  tmux new-window -t "$s" -n workers
  tmux set-option -t "$s" @awa-project "/tmp/$s" 2>/dev/null || true
}

# grid 윈도우의 pane 들을 'top left @awa-project @awa-role' 로 덤프 (정렬 검증용).
dump_grid() {
  local win="$1"
  tmux list-panes -t "${DASH}:${win}" \
    -F '#{pane_top} #{pane_left} #{@awa-project} #{@awa-role}' 2>/dev/null | sort -n
}

echo "[D1] Merge 2 프로젝트 → grid-1 에 2행×2열, 좌=lead 우=pm"
mk_src _S_A_$$ ; mk_src _S_B_$$
bash "$ROOT/bin/awa-dashboard.sh" merge "_S_A_$$" "_S_B_$$" >/dev/null 2>&1
assert_eq "1" "$(tmux has-session -t "$DASH" 2>/dev/null && echo 1)" "D1a \$DASH 존재"
n="$(tmux list-panes -t "${DASH}:grid-1" -F '#{pane_id}' 2>/dev/null | wc -l | tr -d ' ')"
assert_eq "4" "$n" "D1b grid-1 에 4 pane"
# 행 수 = distinct pane_top 개수 = 2
rows="$(tmux list-panes -t "${DASH}:grid-1" -F '#{pane_top}' 2>/dev/null | sort -u | wc -l | tr -d ' ')"
assert_eq "2" "$rows" "D1c 2개 행(distinct top)"
# 각 lead 는 left=0, 각 pm 은 left>0
lead_lefts="$(tmux list-panes -t "${DASH}:grid-1" -F '#{@awa-role} #{pane_left}' 2>/dev/null | awk '$1=="orch"{print $2}')"
assert_eq "" "$(printf '%s\n' "$lead_lefts" | awk '$1!=0{print "BAD"}')" "D1d 모든 lead pane left=0"
pm_lefts="$(tmux list-panes -t "${DASH}:grid-1" -F '#{@awa-role} #{pane_left}' 2>/dev/null | awk '$1=="desk"{print $2}')"
# 공허한 참 방지: pm pane 이 0개면 left>0 검사가 빈 입력으로 무의미 통과 → 개수 먼저 단언.
pm_cnt="$(printf '%s\n' "$pm_lefts" | grep -c '[0-9]')"
assert_eq "2" "$pm_cnt" "D1e-pre pm pane 2개 존재 (공허한 참 방지)"
assert_eq "" "$(printf '%s\n' "$pm_lefts" | awk '$1==0{print "BAD"}')" "D1e 모든 pm pane left>0"

echo "[D2] 페이지네이션: 4 프로젝트 → grid-1(3행) + grid-2(1행)"
tmux kill-session -t "$DASH" 2>/dev/null
mk_src _S_A_$$ ; mk_src _S_B_$$ ; mk_src _S_C_$$ ; mk_src _S_D_$$
bash "$ROOT/bin/awa-dashboard.sh" merge "_S_A_$$" "_S_B_$$" "_S_C_$$" "_S_D_$$" >/dev/null 2>&1
wins="$(tmux list-windows -t "$DASH" -F '#W' 2>/dev/null)"
assert_contains "$wins" "grid-1" "D2a grid-1 존재"
assert_contains "$wins" "grid-2" "D2b grid-2 존재 (4번째 프로젝트)"
n1="$(tmux list-panes -t "${DASH}:grid-1" -F '#{pane_id}' 2>/dev/null | wc -l | tr -d ' ')"
n2="$(tmux list-panes -t "${DASH}:grid-2" -F '#{pane_id}' 2>/dev/null | wc -l | tr -d ' ')"
assert_eq "6" "$n1" "D2c grid-1 = 6 pane (3 프로젝트)"
assert_eq "2" "$n2" "D2d grid-2 = 2 pane (1 프로젝트)"

echo "[D3] 재패킹: 3 프로젝트 중 중간 detach → 남은 2개 grid-1 연속, grid-2 없음"
tmux kill-session -t "$DASH" 2>/dev/null
mk_src _S_A_$$ ; mk_src _S_B_$$ ; mk_src _S_C_$$
bash "$ROOT/bin/awa-dashboard.sh" merge "_S_A_$$" "_S_B_$$" "_S_C_$$" >/dev/null 2>&1
bash "$ROOT/bin/awa-dashboard.sh" detach "_S_B_$$" >/dev/null 2>&1
# B 원세션 team 복원
winb="$(tmux list-windows -t "_S_B_$$" -F '#W' 2>/dev/null)"
assert_contains "$winb" "team" "D3a B 원세션 team 복원"
# grid 에 A,C 만 (B 없음)
projs="$(dump_grid grid-1 | awk '{print $3}' | sort -u | grep -v '^$')"
assert_contains "$projs" "_S_A_$$" "D3b A 잔존"
assert_contains "$projs" "_S_C_$$" "D3c C 잔존"
assert_not_contains "$projs" "_S_B_$$" "D3d B grid 에서 제거"
# 2 프로젝트만 남았으니 grid-2 없어야 함
assert_eq "" "$(tmux list-windows -t "$DASH" -F '#W' 2>/dev/null | grep -x grid-2)" "D3e grid-2 사라짐 (재패킹)"

echo "[D4] 최상단: _DASHBOARD 이름순 + switch 가능"
# list-sessions 이름순에서 _DASHBOARD_TEST 가 임의 awa- 보다 앞 (실측 prefix '_')
tmux kill-session -t "$DASH" 2>/dev/null
mk_src _S_A_$$ ; mk_src _S_B_$$
bash "$ROOT/bin/awa-dashboard.sh" merge "_S_A_$$" "_S_B_$$" >/dev/null 2>&1
# _DASHBOARD_TEST_$$ 와 가짜 awa- 세션 중 이름순 첫째가 _ 로 시작하는지
tmux new-session -d -s "awa-zz_$$" 2>/dev/null || true
firstname="$(tmux list-sessions -F '#{session_name}' 2>/dev/null | sort | head -1)"
# 최상단(이름순 첫째)이 _ prefix 인지 — 첫 글자만 추출해 비교.
assert_eq "_" "${firstname:0:1}" "D4a 이름순 최상단이 _ prefix (got '$firstname')"
tmux kill-session -t "awa-zz_$$" 2>/dev/null || true
# switch-client 명령이 에러 없이 타깃을 인식 (detached 라 실제 전환은 안 되나 has-session 으로 대체 검증)
assert_eq "1" "$(tmux has-session -t "$DASH" 2>/dev/null && echo 1)" "D4b switch 타깃 \$DASH 존재"

echo "[D5] 마지막 1개 자동정리: 2→1 detach → \$DASH kill"
# 자기완결화 — D4 상태에 의존하지 않고 새로 구성 (테스트 간 누수 방지).
tmux kill-session -t "$DASH" 2>/dev/null
mk_src _S_A_$$ ; mk_src _S_B_$$
bash "$ROOT/bin/awa-dashboard.sh" merge "_S_A_$$" "_S_B_$$" >/dev/null 2>&1
# A detach → 1 남음 → 자동 detach + kill
bash "$ROOT/bin/awa-dashboard.sh" detach "_S_A_$$" >/dev/null 2>&1
assert_eq "" "$(tmux has-session -t "$DASH" 2>/dev/null && echo alive)" "D5a \$DASH kill"
winb="$(tmux list-windows -t "_S_B_$$" -F '#W' 2>/dev/null)"
assert_contains "$winb" "team" "D5b B auto-detach 복원"

echo "[D6] 식별 견고성: title 바꿔도 @awa-role 로 식별"
tmux kill-session -t "$DASH" 2>/dev/null
mk_src _S_A_$$
# title 을 엉뚱하게 변경 (식별이 title 의존이면 깨짐 — @awa-role 로 식별해야 통과)
orch_p="$(tmux list-panes -t "_S_A_$$:team" -F '#{@awa-role} #{pane_id}' | awk '$1=="orch"{print $2}')"
tmux select-pane -t "$orch_p" -T "ZZZ_NOT_LEAD" 2>/dev/null || true
mk_src _S_B_$$
bash "$ROOT/bin/awa-dashboard.sh" merge "_S_A_$$" "_S_B_$$" >/dev/null 2>&1
# A 가 grid 에 정상 들어갔는지 (lead 식별 성공)
projs="$(dump_grid grid-1 | awk '{print $3}' | sort -u | grep -v '^$')"
assert_contains "$projs" "_S_A_$$" "D6 title 변경에도 @awa-role 로 A 식별 성공"

echo "[D7] swap 후 @awa-role/@awa-project 보존 (cross-session 옵션 귀속)"
# grid 의 lead pane 이 @awa-role=lead 를 유지하는지
roles="$(tmux list-panes -s -t "$DASH" -F '#{@awa-role}' 2>/dev/null | sort -u | grep -v '^$')"
assert_contains "$roles" "orch" "D7a @awa-role orch 보존"
assert_contains "$roles" "desk" "D7b @awa-role desk 보존"

echo "[D8] 자기참조/부재 스킵 (계승)"
tmux kill-session -t "$DASH" 2>/dev/null
mk_src _S_A_$$
out="$(bash "$ROOT/bin/awa-dashboard.sh" merge "$DASH" "_S_A_$$" 2>&1)"
assert_contains "$out" "자신을 대상" "D8a 자기참조 거부 메시지"
# 부재 세션 스킵 — D8a 가 _S_A 유효로 $DASH 를 생성하며 _S_A 의 lead/pm pane 을 grid 로
# swap 해 가져갔다(원세션엔 빈 골격만 남음). 따라서 kill 후 _S_A 를 fixture 로 재생성해야
# D8b 가 "부재(_NOPE) 스킵 + 유효(_S_A) 생성" 경로를 실제로 탄다 (자기완결 격리).
tmux kill-session -t "$DASH" 2>/dev/null
mk_src _S_A_$$
out="$(bash "$ROOT/bin/awa-dashboard.sh" merge "_NOPE_$$" "_S_A_$$" 2>&1)"
assert_eq "1" "$(tmux has-session -t "$DASH" 2>/dev/null && echo 1)" "D8b 부재 스킵 후에도 유효 세션으로 생성"

echo "[D9] 원세션 부재 재생성 시 @awa-project 세션옵션 복원 (down-menu 경로 조회 보전)"
# 2 프로젝트 merge → 한쪽 원세션을 kill(grid pane 은 swap 으로 살아있음) → detach 로 재생성 경로 진입.
# detach 의 대화형 read 2개(y/n, 경로)를 stdin 으로 주입. 경로 입력 시 @awa-project 가 박혀야 함.
tmux kill-session -t "$DASH" 2>/dev/null
mk_src _S_A_$$ ; mk_src _S_B_$$
bash "$ROOT/bin/awa-dashboard.sh" merge "_S_A_$$" "_S_B_$$" >/dev/null 2>&1
tmux kill-session -t "_S_A_$$" 2>/dev/null   # 원세션 부재 상태 — grid 의 A pane 은 생존
# detach _S_A → 부재 감지 → "y"(재생성) + "/tmp/restored_A_$$"(경로) 주입
printf 'y\n/tmp/restored_A_%s\n' "$$" | bash "$ROOT/bin/awa-dashboard.sh" detach "_S_A_$$" >/dev/null 2>&1
restored="$(tmux show-options -t "_S_A_$$" -v @awa-project 2>/dev/null || echo "")"
assert_eq "/tmp/restored_A_$$" "$restored" "D9a 재생성 세션에 @awa-project(경로) 복원"
rname="$(tmux show-options -t "_S_A_$$" -v @awa-project-name 2>/dev/null || echo "")"
assert_eq "restored_A_$$" "$rname" "D9b @awa-project-name(basename) 복원"

test_summary
