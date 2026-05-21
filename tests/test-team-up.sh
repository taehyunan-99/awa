#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh

ROOT="$(cd .. && pwd)"
export SESSION_OVERRIDE="tu_$$"
# 워커 페인은 claude 대신 'cat' 더미 실행 (입력 대기만)
export AGENT_CMD="cat"

# T6: PROJECT_ROOT 분리 후엔 임시 git repo 가 PROJECT_ROOT 가 됨
TMP_PROJ="$(mktemp -d)"; ( cd "$TMP_PROJ" && git init -q )
export HARNESS_PROJECT="$TMP_PROJ"

cleanup() {
  tmux kill-session -t "$SESSION_OVERRIDE" 2>/dev/null || true
  # TMP_PROJ 가 이미 지워졌거나 비어 있어도 rm -rf 는 no-op (idempotent).
  [ -n "${TMP_PROJ:-}" ] && rm -rf "$TMP_PROJ"
}
trap cleanup EXIT

# 1) 정상 생성
bash "$ROOT/bin/team-up.sh" default
rc=$?
assert_eq "0" "$rc" "team-up default 성공 종료"

# 세션 존재
tmux has-session -t "$SESSION_OVERRIDE" 2>/dev/null
assert_eq "0" "$?" "세션 생성됨"

# 페인 3개 (lead1 + 워커2 — reviewer 워커 제거·일원화)
N="$(tmux list-panes -t "$SESSION_OVERRIDE:0" | wc -l | tr -d ' ')"
assert_eq "3" "$N" "페인 3개"

# 워커 title 결정적 검증: split-window -P 로 캡처한 pane_id 로 title 설정하므로
# select-layout 의 index 재배열과 무관하게 dev/test 가 정확히 걸려야 하고,
# 호스트명/기본값 title 이 섞이지 않아야 함 (layout 무관, pane_id 기반).
TITLES="$(tmux list-panes -t "$SESSION_OVERRIDE:0" -F '#{pane_title}' | sort | tr '\n' ',')"
assert_contains "$TITLES" "dev" "워커 title dev 설정됨(layout 무관, pane_id 기반)"
assert_contains "$TITLES" "test" "워커 title test 설정됨"
assert_contains "$TITLES" "LEAD" "lead title 설정됨"

# title 보존 결정적 검증: 워커 페인을 실제 셸로 띄워 OSC0 escape 를 흘려도
# allow-set-title off 덕에 select-pane -T 로 준 title 이 유지돼야 함 (spec §6 전제).
# 주의: respawn 이 pane 을 갈아끼우므로 위 title 집합 검증보다 반드시 뒤에 둔다.
TGT="$SESSION_OVERRIDE:0.2"
tmux respawn-pane -k -t "$TGT" bash
sleep 0.3
tmux select-pane -t "$TGT" -T "dev"
tmux send-keys -t "$TGT" -l 'printf "\033]0;HOSTNAME_FAKE\007"'
tmux send-keys -t "$TGT" Enter
sleep 0.5
T2="$(tmux display-message -p -t "$TGT" '#{pane_title}')"
assert_eq "dev" "$T2" "allow-set-title off: OSC title escape 후에도 pane_title 보존"

# 부트스트랩 파일이 워커별로 생성되고 치환됨
assert_eq "0" "$([ -f "$TMP_PROJ/.agent-harness/.boot/dev.md" ] && echo 0 || echo 1)" "dev.md boot 생성"
BOOT="$(cat "$TMP_PROJ/.agent-harness/.boot/dev.md")"
assert_contains "$BOOT" "워커 이름: dev" "{{WORKER_NAME}} → dev 치환됨"
assert_contains "$BOOT" "done-$SESSION_OVERRIDE-dev-" "신호 채널명 SESSION+WORKER 치환됨"
assert_contains "$BOOT" "역할: 개발자" "역할 프롬프트 합쳐짐"
if printf '%s' "$BOOT" | grep -qF '{{WORKER_NAME}}'; then r=0; else r=1; fi
assert_eq "1" "$r" "미치환 토큰 없음"

# 2) 중복 실행 거부
bash "$ROOT/bin/team-up.sh" default
assert_fail "$?" "기존 세션 존재 시 중복 생성 거부"

# 케이스 간 tmux 세션만 정리 — TMP_PROJ 는 EXIT trap 까지 살려둔다
# (HARNESS_PROJECT 가 가리키는 디렉터리가 사라진 비결정 상태 방지).
tmux kill-session -t "$SESSION_OVERRIDE" 2>/dev/null || true

# 3) 없는 프로파일 → 실패
bash "$ROOT/bin/team-up.sh" nonexistent_profile
assert_fail "$?" "없는 프로파일 → 실패"
tmux kill-session -t "$SESSION_OVERRIDE" 2>/dev/null || true
# TMP_PROJ 정리는 EXIT trap 이 일괄 수행.

# 4) 5차 리뷰 I1 회귀: .gitignore 부재 git repo → 안내 발화 (보호 강도 역전 차단).
#    spec L216: 룰 누락 안내. 파일 부재는 더 큰 누락 — 침묵 금지.
TMP_GI="$(mktemp -d)"; ( cd "$TMP_GI" && git init -q )
out="$(HARNESS_PROJECT="$TMP_GI" AGENT_CMD=cat bash "$ROOT/bin/team-up.sh" default 2>&1 >/dev/null)"
assert_contains "$out" ".gitignore 파일이 없습니다" ".gitignore 부재 안내 발화"
# cleanup: agents-* 세션 (HARNESS_PROJECT 가 SESSION_OVERRIDE 없는 호출이므로 autoname 사용)
_safe_gi="$(printf '%s' "$(basename "$TMP_GI")" | sed 's/[^A-Za-z0-9_-]/_/g')"
tmux kill-session -t "agents-$_safe_gi" 2>/dev/null || true
rm -rf "$TMP_GI"

test_summary
