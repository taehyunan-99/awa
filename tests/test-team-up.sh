#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh

ROOT="$(cd .. && pwd)"
export SESSION_OVERRIDE="tu_$$"
# 워커 페인은 claude 대신 'cat' 더미 실행 (입력 대기만)
export AGENT_CMD="cat"

cleanup() { tmux kill-session -t "$SESSION_OVERRIDE" 2>/dev/null || true; rm -rf "$ROOT/workspace/.boot"; }
trap cleanup EXIT

# 1) 정상 생성
bash "$ROOT/bin/team-up.sh" default
rc=$?
assert_eq "0" "$rc" "team-up default 성공 종료"

# 세션 존재
tmux has-session -t "$SESSION_OVERRIDE" 2>/dev/null
assert_eq "0" "$?" "세션 생성됨"

# 페인 4개 (오케1 + 워커3)
N="$(tmux list-panes -t "$SESSION_OVERRIDE:0" | wc -l | tr -d ' ')"
assert_eq "4" "$N" "페인 4개"

# spec §6 전제: 워커 페인을 escape-불변 @worker 옵션으로 조회 가능해야 함.
# pane_title 은 워커 셸의 OSC escape 로 덮이므로 권위 식별자로 못 씀(아래 입증).
WTAGS="$(tmux list-panes -t "$SESSION_OVERRIDE:0" -F '#{@worker}' | tr '\n' ',')"
assert_contains "$WTAGS" "dev" "@worker 옵션에 dev 부여"
assert_contains "$WTAGS" "review" "@worker 옵션에 review 부여"
assert_contains "$WTAGS" "test" "@worker 옵션에 test 부여"

# worker_pane() 로 워커명→영속 pane_id 조회 (dispatch/wait-worker 가 쓰는 경로)
WP="$(SESSION="$SESSION_OVERRIDE" bash -c 'source "'"$ROOT"'/bin/lib.sh"; worker_pane dev')"
case "$WP" in %[0-9]*) wpok=0 ;; *) wpok=1 ;; esac
assert_eq "0" "$wpok" "worker_pane dev → 영속 pane_id(%N) 반환 ($WP)"
WPW="$(tmux display -t "$WP" -p '#{@worker}')"
assert_eq "dev" "$WPW" "조회된 pane_id 의 @worker 가 dev"

# 셸 OSC escape 가 pane_title 을 덮어도 @worker 조회는 영향 없음을 결정적으로 입증.
# 워커 페인(pane_id=$WP)에 셸을 띄워 호스트명 OSC0 을 실제 출력시킨다
# (send-keys 가 아닌 페인 출력 파서를 거쳐야 pane_title 이 실제로 덮인다).
tmux respawn-pane -k -t "$WP" "bash --norc -i" 2>/dev/null
sleep 0.4
tmux set-option -p -t "$WP" @worker dev
tmux send-keys -t "$WP" -l 'printf "\033]0;FAKEHOST\007"'
tmux send-keys -t "$WP" Enter
sleep 0.4
PT="$(tmux display -t "$WP" -p '#{pane_title}')"
assert_eq "FAKEHOST" "$PT" "셸 OSC0 가 pane_title 을 실제로 덮음(=title 은 권위 식별자 불가)"
WP2="$(SESSION="$SESSION_OVERRIDE" bash -c 'source "'"$ROOT"'/bin/lib.sh"; worker_pane dev')"
assert_eq "$WP" "$WP2" "title 덮인 뒤에도 @worker 로 dev 조회 정상(동일 pane_id)"

# 부트스트랩 파일이 워커별로 생성되고 치환됨
assert_eq "0" "$([ -f "$ROOT/workspace/.boot/dev.md" ] && echo 0 || echo 1)" "dev.md boot 생성"
BOOT="$(cat "$ROOT/workspace/.boot/dev.md")"
assert_contains "$BOOT" "워커 이름: dev" "{{WORKER_NAME}} → dev 치환됨"
assert_contains "$BOOT" "done-dev-" "신호 채널명 치환됨"
assert_contains "$BOOT" "역할: 개발자" "역할 프롬프트 합쳐짐"
if printf '%s' "$BOOT" | grep -qF '{{WORKER_NAME}}'; then r=0; else r=1; fi
assert_eq "1" "$r" "미치환 토큰 없음"

# 2) 중복 실행 거부
bash "$ROOT/bin/team-up.sh" default
assert_fail "$?" "기존 세션 존재 시 중복 생성 거부"

cleanup
trap - EXIT

# 3) 없는 프로파일 → 실패
bash "$ROOT/bin/team-up.sh" nonexistent_profile
assert_fail "$?" "없는 프로파일 → 실패"
tmux kill-session -t "$SESSION_OVERRIDE" 2>/dev/null || true

test_summary
