#!/usr/bin/env bash
# team-up.sh 의 5차 변경: new-session -c, settings 2인자, 데몬 기동 코드 존재.
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"
src="$(cat "$ROOT/bin/team-up.sh")"

echo "[U1] new-session 에 -c PROJECT_ROOT"
assert_contains "$src" 'new-session -d -s "$SESSION" -c "${PROJECT_ROOT}"' "U1 new-session -c"

echo "[U2] 워커 settings 2인자 호출"
assert_contains "$src" 'generate_worker_settings "$ENTRY_ROLE" "$ENTRY_NAME"' "U2 워커 2인자"

echo "[U3] lead settings 2인자 호출"
assert_contains "$src" 'generate_worker_settings "LEAD" "LEAD"' "U3 lead 2인자"

echo "[U4] discover_jsonl_and_record 3곳 호출"
n="$(printf '%s' "$src" | grep -c 'discover_jsonl_and_record')"
[ "$n" -ge 3 ]; assert_success "$?" "U4 discovery 3곳 ($n)"

echo "[U5] watch-asks 데몬 기동 (nohup)"
assert_contains "$src" 'nohup bash "${HARNESS_ROOT}/bin/watch-asks.sh"' "U5 데몬 nohup"

echo "[U6] cat 더미로 team-up 성공 (데몬 코드가 cat 경로 안 깨뜨림)"
TMP="$(mktemp -d)"; SAFE="$(basename "$TMP" | sed 's/[^A-Za-z0-9_-]/_/g')"; SESSION="agents-$SAFE"
( cd "$TMP" && git init -q )
# cat 더미는 jsonl 미생성 → team-up 의 discovery 는 claude 분기에서만 호출되므로 hang 없음 (T18 정정).
HARNESS_PROJECT="$TMP" AGENT_CMD=cat bash "$ROOT/bin/team-up.sh" feature-team >/dev/null 2>&1
rc=$?
tmux kill-session -t "$SESSION" 2>/dev/null || true
[ -f "$TMP/.agent-harness/state/watch-asks.pid" ] && kill "$(cat "$TMP/.agent-harness/state/watch-asks.pid")" 2>/dev/null || true
assert_eq "0" "$rc" "U6 team-up 성공 (cat 경로)"

echo "[U7] ★ team-up 가 PROJECT_ROOT/config/lead-auto-allow.yaml 설치 (실전 부트 경로)"
# 실전 결함: lead_auto_allow_lookup 은 PROJECT_ROOT/config/lead-auto-allow.yaml 을 읽는데
#   (spec §841 프로젝트별 커스텀), team-up 이 설치 안 하면 파일 부재 → lookup 영구 rc=1 →
#   lead-auto-allow 전체 무동작. 부트 후 yaml 이 PROJECT_ROOT 에 있어야 함.
[ -f "$TMP/config/lead-auto-allow.yaml" ]; assert_success "$?" "U7 yaml PROJECT_ROOT 설치됨"
# 내용이 하네스 원본과 동일 (복사 검증)
if [ -f "$TMP/config/lead-auto-allow.yaml" ]; then
  assert_contains "$(cat "$TMP/config/lead-auto-allow.yaml")" "safe-test" "U7 yaml 내용 (safe-test 카테고리)"
fi

echo "[U8] ★ team-up 가 기존 PROJECT_ROOT yaml 을 덮어쓰지 않음 (사용자 커스텀 보존)"
TMP8="$(mktemp -d)"; SAFE8="$(basename "$TMP8" | sed 's/[^A-Za-z0-9_-]/_/g')"; SESSION8="agents-$SAFE8"
( cd "$TMP8" && git init -q )
mkdir -p "$TMP8/config"
printf 'custom-marker:\n  - "Bash(my-custom:*)"\n' > "$TMP8/config/lead-auto-allow.yaml"
HARNESS_PROJECT="$TMP8" AGENT_CMD=cat bash "$ROOT/bin/team-up.sh" feature-team >/dev/null 2>&1
tmux kill-session -t "$SESSION8" 2>/dev/null || true
[ -f "$TMP8/.agent-harness/state/watch-asks.pid" ] && kill "$(cat "$TMP8/.agent-harness/state/watch-asks.pid")" 2>/dev/null || true
assert_contains "$(cat "$TMP8/config/lead-auto-allow.yaml")" "my-custom" "U8 기존 커스텀 yaml 보존"
rm -rf "$TMP8"

rm -rf "$TMP"
test_summary
