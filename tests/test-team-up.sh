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

# 15th: bookmarks 격리 — awa-up.sh 가 ~/.config/awa/bookmarks.tsv 에 기록.
# 테스트 fixture 가 사용자 실 경로를 더럽히지 않도록 임시 dir 로 redirect.
_AGPN15_XDG="$(mktemp -d)"
export XDG_CONFIG_HOME="$_AGPN15_XDG"

cleanup() {
  tmux kill-session -t "$SESSION_OVERRIDE" 2>/dev/null || true
  # TMP_PROJ 가 이미 지워졌거나 비어 있어도 rm -rf 는 no-op (idempotent).
  [ -n "${TMP_PROJ:-}" ] && rm -rf "$TMP_PROJ"
  [ -n "${_AGPN15_XDG:-}" ] && rm -rf "$_AGPN15_XDG"
}
trap cleanup EXIT

# 1) 정상 생성
bash "$ROOT/bin/awa-up.sh" default
rc=$?
assert_eq "0" "$rc" "awa-up default 성공 종료"

# 세션 존재
tmux has-session -t "$SESSION_OVERRIDE" 2>/dev/null
assert_eq "0" "$?" "세션 생성됨"

# 14차 UX: 윈도우 분리 후 구조 검증.
# team 윈도우(0): LEAD + PM (2 pane), workers 윈도우(1): 워커2 + watcher (3 pane).
N_TEAM="$(tmux list-panes -t "$SESSION_OVERRIDE:team" | wc -l | tr -d ' ')"
assert_eq "2" "$N_TEAM" "team 윈도우 pane 2개 (lead+pm)"
N_WORKERS="$(tmux list-panes -t "$SESSION_OVERRIDE:workers" | wc -l | tr -d ' ')"
assert_eq "3" "$N_WORKERS" "workers 윈도우 pane 3개 (워커2+watcher)"

# workers 윈도우의 title 결정적 검증.
TITLES="$(tmux list-panes -t "$SESSION_OVERRIDE:workers" -F '#{pane_title}' | sort | tr '\n' ',')"
assert_contains "$TITLES" "engineer" "워커 title engineer 설정됨(layout 무관, pane_id 기반)"
assert_contains "$TITLES" "researcher" "워커 title researcher 설정됨"
assert_contains "$TITLES" "watcher" "watcher pane title 설정됨"
# team 윈도우 title 검증.
TEAM_TITLES="$(tmux list-panes -t "$SESSION_OVERRIDE:team" -F '#{pane_title}' | sort | tr '\n' ',')"
assert_contains "$TEAM_TITLES" "PM" "pm pane title 설정됨"
assert_contains "$TEAM_TITLES" "LEAD" "lead title 설정됨"

# title 보존 결정적 검증: 워커 페인을 실제 셸로 띄워 OSC0 escape 를 흘려도
# allow-set-title off 덕에 select-pane -T 로 준 title 이 유지돼야 함 (spec §6 전제).
# 주의: respawn 이 pane 을 갈아끼우므로 위 title 집합 검증보다 반드시 뒤에 둔다.
# 14차 UX: workers 윈도우 첫 pane (워커1=engineer) 으로 타겟 변경.
TGT="$SESSION_OVERRIDE:workers.1"
tmux respawn-pane -k -t "$TGT" bash
sleep 0.3
tmux select-pane -t "$TGT" -T "engineer"
tmux send-keys -t "$TGT" -l 'printf "\033]0;HOSTNAME_FAKE\007"'
tmux send-keys -t "$TGT" Enter
sleep 0.5
T2="$(tmux display-message -p -t "$TGT" '#{pane_title}')"
assert_eq "engineer" "$T2" "allow-set-title off: OSC title escape 후에도 pane_title 보존"

# 부트스트랩 파일이 워커별로 생성되고 치환됨
assert_eq "0" "$([ -f "$TMP_PROJ/.agent-harness/.boot/engineer.md" ] && echo 0 || echo 1)" "engineer.md boot 생성"
BOOT="$(cat "$TMP_PROJ/.agent-harness/.boot/engineer.md")"
assert_contains "$BOOT" "워커 이름: engineer" "{{WORKER_NAME}} → engineer 치환됨"
# P11 탈-tmux: done 채널(`done-{{SESSION}}-...`) 폐지 → {{SESSION}} 토큰이 워커 부트에서 소멸.
#   완료 신호는 events.log done 라인. 부트에 done 라인 규약 + 워커 tmux 직접호출 금지가 주입됐는지 검증.
assert_contains "$BOOT" "done 라인" "완료 신호=events.log done 라인 규약 주입됨"
case "$BOOT" in *"tmux wait-for -S done-"*) assert_eq 1 0 "워커 부트에 wait-for 채널 잔존(P11 위반)";; *) assert_eq 0 0 "워커 부트 wait-for 채널 제거 확인(P11)";; esac
assert_contains "$BOOT" "역할: 엔지니어" "역할 프롬프트 합쳐짐"
if printf '%s' "$BOOT" | grep -qF '{{WORKER_NAME}}'; then r=0; else r=1; fi
assert_eq "1" "$r" "미치환 토큰 없음"

# 2) 중복 실행 거부
bash "$ROOT/bin/awa-up.sh" default
assert_fail "$?" "기존 세션 존재 시 중복 생성 거부"

# 케이스 간 tmux 세션만 정리 — TMP_PROJ 는 EXIT trap 까지 살려둔다
# (HARNESS_PROJECT 가 가리키는 디렉터리가 사라진 비결정 상태 방지).
tmux kill-session -t "$SESSION_OVERRIDE" 2>/dev/null || true

# 3) 없는 프로파일 → 실패
bash "$ROOT/bin/awa-up.sh" nonexistent_profile
assert_fail "$?" "없는 프로파일 → 실패"
tmux kill-session -t "$SESSION_OVERRIDE" 2>/dev/null || true
# TMP_PROJ 정리는 EXIT trap 이 일괄 수행.

# 4) 12차: .gitignore 부재 git repo → 하네스 산출물 자동추가 (구 "안내" → "자동").
#    상세 멱등/항목 커버는 test-gitignore-autosetup.sh. 여기선 가동 경로 회귀만 확인.
TMP_GI="$(mktemp -d)"; ( cd "$TMP_GI" && git init -q )
HARNESS_PROJECT="$TMP_GI" AGENT_CMD=cat bash "$ROOT/bin/awa-up.sh" default >/dev/null 2>&1
gi_out="$(cat "$TMP_GI/.gitignore" 2>/dev/null || true)"
assert_contains "$gi_out" ".agent-harness/" ".gitignore 부재 git repo → 산출물 자동추가"
# cleanup: awa-* 세션 (HARNESS_PROJECT 가 SESSION_OVERRIDE 없는 호출이므로 autoname 사용)
_safe_gi="$(printf '%s' "$(basename "$TMP_GI")" | sed 's/[^A-Za-z0-9_-]/_/g')"
tmux kill-session -t "awa-$_safe_gi" 2>/dev/null || true
rm -rf "$TMP_GI"

# 5) parse_entry — ENTRY_ROLE 금지 문자 거부 (ENTRY_NAME 검증과 대칭, sed 구분자 파손 방지)
#    bad#role 은 sed s#...#bad#role#g 를 파손 — 사전 거부 필수.
#    SESSION_OVERRIDE 해제: 기존 tu_$$ 세션과 충돌 방지 (autoname 경로 사용).
TMP_BR="$(mktemp -d)"; ( cd "$TMP_BR" && git init -q )
_pf_br="$(mktemp /tmp/profile_badXXXX.sh)"
printf 'WORKERS=("worker1:bad#role")\nREVIEWERS=()\nLEAD_MODEL="sonnet"\n' > "$_pf_br"
err_br="$(unset SESSION_OVERRIDE; HARNESS_PROJECT="$TMP_BR" AGENT_CMD=cat bash "$ROOT/bin/awa-up.sh" "$_pf_br" 2>&1 >/dev/null)"; rc_br=$?
_safe_br="$(printf '%s' "$(basename "$TMP_BR")" | sed 's/[^A-Za-z0-9_-]/_/g')"
tmux kill-session -t "awa-$_safe_br" 2>/dev/null || true
rm -f "$_pf_br"; rm -rf "$TMP_BR"
assert_fail "$rc_br" "ENTRY_ROLE 금지 문자(#) → exit 1"
assert_contains "$err_br" "역할 이름" "ENTRY_ROLE 거부 오류 메시지 발화"
assert_contains "$err_br" "bad#role" "ENTRY_ROLE 거부 시 문제 역할명 포함"

test_summary
