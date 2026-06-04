#!/usr/bin/env bash
# 6차: state mkdir, yaml 설치 (데몬 폐기).
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"
src="$(cat "$ROOT/bin/awa-up.sh")"

# 15th: bookmarks 격리 — awa-up.sh 가 ~/.config/awa/bookmarks.tsv 에 기록.
# 테스트 fixture 가 사용자 실 경로를 더럽히지 않도록 임시 dir 로 redirect.
_AGPN15_XDG="$(mktemp -d)"
export XDG_CONFIG_HOME="$_AGPN15_XDG"
trap 'rm -rf "$_AGPN15_XDG"' EXIT

echo "[U1] new-session 에 -c PROJECT_ROOT"
assert_contains "$src" 'new-session -d -s "$SESSION" -c "${PROJECT_ROOT}"' "U1 new-session -c"

echo "[U2] 워커 settings 2인자 호출 (벤더 위임 — Task3 부터 vendor_gen_settings)"
assert_contains "$src" 'vendor_gen_settings "$ENTRY_ROLE" "$ENTRY_NAME"' "U2 워커 2인자"

echo "[U3] lead settings 2인자 호출 (벤더 위임)"
assert_contains "$src" 'vendor_gen_settings "orch" "ORCH"' "U3 orch 2인자"

echo "[U6] cat 더미로 awa-up 성공 (데몬 폐기 후 cat 경로 무손상)"
TMP="$(mktemp -d)"; SAFE="$(basename "$TMP" | sed 's/[^A-Za-z0-9_-]/_/g')"; SESSION="awa-$SAFE"
( cd "$TMP" && git init -q )
HARNESS_PROJECT="$TMP" AGENT_CMD=cat bash "$ROOT/bin/awa-up.sh" feature-team >/dev/null 2>&1
rc=$?
tmux kill-session -t "$SESSION" 2>/dev/null || true
assert_eq "0" "$rc" "U6 awa-up 성공 (cat 경로)"

echo "[U-state] awa-up 부트 시 pending-asks/incidents/removal mkdir (marker 게이트 후)"
[ -d "$TMP/.agent-harness/state/pending-asks" ]; assert_success "$?" "U-state pending-asks 생성"
[ -d "$TMP/.agent-harness/state/incidents" ]; assert_success "$?" "U-state incidents 생성"
[ -d "$TMP/.agent-harness/state/removal-requests" ]; assert_success "$?" "U-state removal-requests 생성"

echo "[U7] ★ awa-up 가 PROJECT_ROOT/config/orch-auto-allow.yaml 설치 (실전 부트 경로)"
# 실전 결함: orch_auto_allow_lookup 은 PROJECT_ROOT/config/orch-auto-allow.yaml 을 읽는데
#   (spec §841 프로젝트별 커스텀), awa-up 이 설치 안 하면 파일 부재 → lookup 영구 rc=1 →
#   orch-auto-allow 전체 무동작. 부트 후 yaml 이 PROJECT_ROOT 에 있어야 함.
[ -f "$TMP/config/orch-auto-allow.yaml" ]; assert_success "$?" "U7 yaml PROJECT_ROOT 설치됨"
# 내용이 하네스 원본과 동일 (복사 검증)
if [ -f "$TMP/config/orch-auto-allow.yaml" ]; then
  assert_contains "$(cat "$TMP/config/orch-auto-allow.yaml")" "safe-test" "U7 yaml 내용 (safe-test 카테고리)"
fi

echo "[U8] ★ awa-up 가 기존 PROJECT_ROOT yaml 을 덮어쓰지 않음 (사용자 커스텀 보존)"
TMP8="$(mktemp -d)"; SAFE8="$(basename "$TMP8" | sed 's/[^A-Za-z0-9_-]/_/g')"; SESSION8="awa-$SAFE8"
( cd "$TMP8" && git init -q )
mkdir -p "$TMP8/config"
printf 'custom-marker:\n  - "Bash(my-custom:*)"\n' > "$TMP8/config/orch-auto-allow.yaml"
HARNESS_PROJECT="$TMP8" AGENT_CMD=cat bash "$ROOT/bin/awa-up.sh" feature-team >/dev/null 2>&1
tmux kill-session -t "$SESSION8" 2>/dev/null || true
assert_contains "$(cat "$TMP8/config/orch-auto-allow.yaml")" "my-custom" "U8 기존 커스텀 yaml 보존"
rm -rf "$TMP8"

rm -rf "$TMP"
test_summary
