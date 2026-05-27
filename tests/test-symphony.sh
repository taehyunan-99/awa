#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"

# 11차 리뷰 [CRIT-32]: 사용자 실 _SYMPHONY 세션 보호 — 환경변수로 격리된 이름 사용.
# symphony.sh 본문은 SYM="${AGPN_SYM_NAME:-_SYMPHONY}" 로 받음.
export AGPN_SYM_NAME="_SYMPHONY_TEST_$$"
SYM="$AGPN_SYM_NAME"

trap '
  tmux kill-session -t "$SYM" 2>/dev/null
  for s in _S_A_$$ _S_B_$$ _S_C_$$ _ALONE_$$ _S_KA_$$; do tmux kill-session -t "$s" 2>/dev/null; done
' EXIT

# 헬퍼: 14차 윈도우 구조 흉내 (team + workers window).
# 11차 리뷰 [MAJOR-34/35]: ${1:-} 가드 + 멱등화 (이미 존재 시 kill 후 재생성).
mk_src() {
  local s="${1:-}"
  [ -n "$s" ] || { echo "오류: mk_src 인자 필요" >&2; return 1; }
  tmux kill-session -t "$s" 2>/dev/null || true
  tmux new-session -d -s "$s" -n team -x 200 -y 50
  tmux split-window -h -t "$s:team"
  tmux select-pane -t "$s:team.1" -T "LEAD"
  tmux select-pane -t "$s:team.2" -T "PM"
  tmux new-window -t "$s" -n workers   # 마지막 window 보장 (move-window 시 원세션 생존)
  tmux set-option -t "$s" @agenphony-project "/tmp/$s" 2>/dev/null || true
  tmux set-option -t "$s" @agenphony-project-name "$s" 2>/dev/null || true
}

echo "[S1] Compose: 2 세션 → \$SYM 생성"
mk_src _S_A_$$
mk_src _S_B_$$
bash "$ROOT/bin/agenphony-symphony.sh" compose "_S_A_$$" "_S_B_$$" >/dev/null 2>&1
assert_eq "1" "$(tmux has-session -t "$SYM" 2>/dev/null && echo 1)" "S1a \$SYM 존재"
windows="$(tmux list-windows -t "$SYM" -F '#W' 2>/dev/null)"
assert_contains "$windows" "_S_A_$$-team" "S1b A team window 들어감"
assert_contains "$windows" "_S_B_$$-team" "S1c B team window 들어감"

echo "[S2] 옵션 검증 (sym_init_session)"
v="$(tmux show-options -t "$SYM" -v allow-set-title 2>/dev/null)"
assert_eq "off" "$v" "S2a allow-set-title=off"
v="$(tmux show-options -t "$SYM" -v pane-border-status 2>/dev/null)"
assert_eq "top" "$v" "S2b pane-border-status=top"

echo "[S3] window 단위 border-format (프로젝트별 라벨)"
v="$(tmux show-options -w -t "$SYM:_S_A_$$-team" -v pane-border-format 2>/dev/null)"
assert_contains "$v" "_S_A_$$" "S3 window 단위 format 박힘"

echo "[S4] base-index 보장"
v="$(tmux show-options -t "$SYM" -v base-index 2>/dev/null)"
assert_eq "0" "$v" "S4 base-index=0"

# 정리
tmux kill-session -t "$SYM" 2>/dev/null
tmux kill-session -t "_S_A_$$" 2>/dev/null
tmux kill-session -t "_S_B_$$" 2>/dev/null

echo "[S5] Add: 기존 \$SYM 에 추가"
mk_src _S_A_$$
mk_src _S_B_$$
mk_src _S_C_$$
bash "$ROOT/bin/agenphony-symphony.sh" compose "_S_A_$$" "_S_B_$$" >/dev/null 2>&1
bash "$ROOT/bin/agenphony-symphony.sh" add "_S_C_$$" >/dev/null 2>&1
windows="$(tmux list-windows -t "$SYM" -F '#W' 2>/dev/null)"
assert_contains "$windows" "_S_C_$$-team" "S5 C 추가됨"

echo "[S6] Add: \$SYM 부재 시 거부 (Compose 안내)"
tmux kill-session -t "$SYM" 2>/dev/null
mk_src _S_A_$$
out="$(bash "$ROOT/bin/agenphony-symphony.sh" add "_S_A_$$" 2>&1)"
assert_contains "$out" "Compose" "S6 부재 시 Compose 안내"

echo "[S7] Add 안전 검사: 원세션에 team 외 window 없으면 거부"
tmux kill-session -t "$SYM" 2>/dev/null
tmux kill-session -t _ALONE_$$ 2>/dev/null
tmux new-session -d -s _ALONE_$$ -n team  # workers window 없음
tmux set-option -t _ALONE_$$ @agenphony-project "/tmp/_ALONE_$$" 2>/dev/null
# $SYM 만들고 add 시도
mk_src _S_B_$$
bash "$ROOT/bin/agenphony-symphony.sh" compose "_ALONE_$$" "_S_B_$$" >/dev/null 2>&1 || true
# _ALONE_$$ 은 거부됐어야 함 — $SYM 자체가 안 만들어졌거나, _S_B 만 들어감
out="$(bash "$ROOT/bin/agenphony-symphony.sh" add "_ALONE_$$" 2>&1)"
# sym_safe_check_origin 에러 메시지 매칭
assert_contains "$out" "team 외 window 가 없음" "S7 안전 검사 거부 메시지"
tmux kill-session -t _ALONE_$$ 2>/dev/null

test_summary
