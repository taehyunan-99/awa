#!/usr/bin/env bash
# P2/P6 수정 회귀(2026-05-30): 권한 학습(allow)이 프로젝트 .agent-harness/learned-allow.yaml 에
# 영구화되고 matrix-lookup 이 함께 읽어 게이트에 즉시 반영되는지 + 본체 yaml 무오염 검증.
# 근본 결함: confirm_allow_yaml 쓰기(HARNESS_ROOT) ≠ matrix-lookup 읽기(PROJECT_ROOT) 경로 불일치로
#   학습이 게이트에 미반영(매 task 재프롬프트) + 본체 git 추적 yaml 오염.
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"

# ── 격리: HARNESS_PROJECT 로만 (export PROJECT_ROOT 은 lib.sh 가 무시) ──
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# Task 2 후 lookup 카탈로그는 PROJECT_ROOT/.agent-harness/config 에서 읽음.
mkdir -p "$TMP/.agent-harness/config"
cp "$ROOT/config/orch-auto-allow.yaml" "$TMP/.agent-harness/config/"
# Task 1 후 stats/blocklist 는 XDG_CONFIG_HOME/awa 로 이전 — XDG 를 TMP 로 격리해 본체 오염 방지.
#   (_state_config_dir 가 없으면 자동 생성하므로 별도 cp 불필요.)
export XDG_CONFIG_HOME="$TMP"
export HARNESS_PROJECT="$TMP"
# shellcheck disable=SC1091
source "$ROOT/bin/lib.sh"
# shellcheck disable=SC1091
source "$ROOT/bin/matrix-lookup.sh"

# 격리 sanity — PROJECT_ROOT 가 실제 TMP 인지 (export PROJECT_ROOT 무시 함정 회귀)
assert_eq "$TMP" "$PROJECT_ROOT" "L0 HARNESS_PROJECT 격리 적용 (PROJECT_ROOT=TMP)"

# ── Layer 2 (동작): 학습 전 NO_MATCH → accepted → 학습 후 MATCH ──
# 임의 학습 대상(인프라 박제와 겹치지 않는 패턴 선택 — 순수 학습 경로 검증).
PAT='Bash(myproject-tool:*)'
CMD='{"command":"myproject-tool build"}'

echo "[L1] 학습 전 NO_MATCH"
orch_auto_allow_lookup Bash "$CMD" >/dev/null
assert_fail "$?" "L1 학습 전 myproject-tool 미매칭"

echo "[L2] confirm_allow_yaml accepted → 프로젝트 learned 파일 생성"
# stats/blocklist 쓰기는 XDG_CONFIG_HOME=TMP 격리로 본체 오염 방지 (Task 1 XDG 이전).
confirm_allow_yaml "$PAT" "accepted" >/dev/null 2>&1
assert_success "$?" "L2 accepted 성공"
[ -f "$TMP/.agent-harness/learned-allow.yaml" ]
assert_success "$?" "L2 프로젝트 .agent-harness/learned-allow.yaml 생성됨"

echo "[L3] 학습 후 MATCH (P2 해소 — 학습이 게이트에 즉시 반영)"
out="$(orch_auto_allow_lookup Bash "$CMD")"
assert_eq "learned:$PAT" "$out" "L3 학습 후 myproject-tool → learned 매칭"

echo "[L4] 본체 yaml 무오염 (P6 — config/orch-auto-allow.yaml learned 비어있음)"
# 본체 yaml 의 learned: 카테고리에 방금 학습한 패턴이 들어가지 않아야 함.
grep -q "^  - \"$PAT\"$" "$ROOT/config/orch-auto-allow.yaml"
assert_fail "$?" "L4 본체 orch-auto-allow.yaml 에 학습 패턴 미기록 (오염 없음)"
[ ! -f "$ROOT/.agent-harness/learned-allow.yaml" ] || \
  grep -q "^  - \"$PAT\"$" "$ROOT/.agent-harness/learned-allow.yaml" && \
  { echo "  (경고: 본체 .agent-harness/learned-allow.yaml 에 누출)"; }

echo "[L5] 영구성 — 재읽기(부트 시뮬레이션)에도 학습 유지"
# learned 파일이 보존되므로 새 매칭 호출에서도 여전히 매치.
out="$(orch_auto_allow_lookup Bash "$CMD")"
assert_eq "learned:$PAT" "$out" "L5 재읽기에도 학습 유지 (프로젝트 영구)"

test_summary
