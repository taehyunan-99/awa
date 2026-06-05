#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
source ./harness-paths.sh

ROOT="$(cd .. && pwd)"

# desk 템플릿 생성 검증: generate_worker_settings "desk" "desk" 가 desk 템플릿을 산출하는지.
TMP_PROJ="$(mktemp -d)"; ( cd "$TMP_PROJ" && git init -q )
cleanup() { rm -rf "$TMP_PROJ"; }
trap cleanup EXIT

# lib.sh 가 PROJECT_ROOT·HARNESS_ROOT 를 요구하므로 HARNESS_PROJECT 로 격리 후 source.
OUT="$(HARNESS_PROJECT="$TMP_PROJ" bash -c '
  source '"$HARNESS_BIN"'/lib.sh
  generate_worker_settings desk desk
')"
rc=$?
assert_eq "0" "$rc" "generate_worker_settings desk 성공"

# 산출 경로가 .boot-settings/desk.json 인지
assert_contains "$OUT" ".boot-settings/desk.json" "desk settings 경로"
[ -f "$OUT" ]
assert_success "$?" "desk settings 파일 존재"

DESKSET="$(cat "$OUT")"
# desk 은 hook 없음 (게이트 비대상)
assert_not_contains "$DESKSET" "permission-gate.sh" "desk 은 PreToolUse 게이트 없음"
assert_not_contains "$DESKSET" "log-event.sh" "desk 은 PostToolUse 없음"
# desk 은 bypassPermissions 아님 (과권한 금지)
assert_not_contains "$DESKSET" "bypassPermissions" "desk 은 bypassPermissions 아님"
# 읽기 도구 + 전달용 tmux + pull-read bash allow
assert_contains "$DESKSET" "Read" "desk Read allow"
assert_contains "$DESKSET" "Grep" "desk Grep allow"
assert_contains "$DESKSET" "Bash(tmux:*)" "desk tmux allow (orch 전달용)"
# desk 은 Write/rm allow 없음 (읽기전용)
assert_not_contains "$DESKSET" '"Write(' "desk 은 Write allow 없음"
assert_not_contains "$DESKSET" "Bash(rm" "desk 은 rm allow 없음"

# ★ 쓰기 우회 통로 봉쇄 (2026-06-03 라이브 결함): DESK(Sonnet)이 시스템프롬프트(읽기전용)를
#   무시하고 `cat << EOF > file` 리다이렉션으로 직접 파일 작성 시도 → Write/Edit deny 로는
#   Bash 리다이렉션을 못 막는다. 근본수정: cat 을 allow 에서 제거(DESK 은 cat 사용 0건 — 파일
#   읽기는 Read 도구로). cat 없으면 `cat>file` 우회 통로 차단. pull-read 는 Read 가 담당(L33).
#   리다이렉션 일반 차단은 danger-check(B안)의 몫 — 여기선 불필요 명령 제거로 통로 축소.
assert_not_contains "$DESKSET" "Bash(cat:*)" "desk 은 cat allow 없음 (cat>file 우회 통로 제거)"
# desk-queue 작성에 필요한 명령은 유지 (jq -n > .tmp + mv — desk.md ⓒ 규약)
assert_contains "$DESKSET" "Bash(jq:*)" "desk jq allow (desk-queue jq -n 작성)"
assert_contains "$DESKSET" "Bash(mkdir:*)" "desk mkdir allow (desk-queue 디렉토리)"
assert_contains "$DESKSET" "Bash(mv:*)" "desk mv allow (desk-queue atomic tmp→mv)"

# I1: 읽기전용을 deny 로 코드 강제 (allow 부재만으론 default mode 에서 사용자 프롬프트 — desk 가
# 사용자 창구라 자기참조. deny 는 default mode 에서 확정 차단이라 불변식을 settings 로 보장).
_desk_deny="$(printf '%s' "$DESKSET" | jq -r '.permissions.deny[]?' 2>/dev/null)"
assert_contains "$_desk_deny" "Write" "desk deny 에 Write (읽기전용 코드 강제)"
assert_contains "$_desk_deny" "Edit" "desk deny 에 Edit"
assert_contains "$_desk_deny" "NotebookEdit" "desk deny 에 NotebookEdit"

# ★ 서브에이전트 우회 봉쇄 (2026-06-03 라이브 결함 2차): cat 차단 후 DESK(Sonnet)이 이번엔
#   Agent(general-purpose 서브에이전트)를 띄워 파일작성 우회. 근본원인 = DESK 은 hook 이 없어
#   (게이트 비대상 — 사용자 창구) 다른 워커/리뷰어와 달리 hook matcher(Bash|Edit|Write|Agent|*)
#   로 Agent 를 못 잡는다. settings deny 가 DESK 의 *유일한* 방어선이므로 Agent/Task 를 명시 deny.
#   (전수조사: engineer/researcher/reviewer 는 hook matcher 에 Agent/* 포함 → 게이트 커버. DESK 만
#   무방비였다.) defaultMode:dontAsk 화이트리스트는 라이브 검증서 DESK 정상 desk-queue 리다이렉션
#   (jq -n > .tmp)까지 거부 → 부적합 판정, deny 명시 채택.
assert_contains "$_desk_deny" "Agent" "desk deny 에 Agent (서브에이전트 우회 차단 — hook 부재 보완)"
assert_contains "$_desk_deny" "Task" "desk deny 에 Task (Agent 별칭 안전망)"

test_summary
