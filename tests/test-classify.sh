#!/usr/bin/env bash
# classify 순수함수: verdict<TAB>detail. colon 포함 패턴 안전.
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"
export HARNESS_PROJECT="$(mktemp -d)"
export PROJECT_ROOT="$HARNESS_PROJECT"
( cd "$HARNESS_PROJECT" && git init -q )
# shellcheck disable=SC1091
source "$ROOT/bin/lib.sh"
# shellcheck disable=SC1091
source "$ROOT/bin/matrix-lookup.sh"
# shellcheck disable=SC1091
source "$ROOT/bin/danger-check.sh"
# shellcheck disable=SC1091
source "$ROOT/bin/classify.sh"

BOOT="$HARNESS_PROJECT/.agent-harness/.boot-settings"
mkdir -p "$BOOT"
# matrix: dev settings 에 ls allow
echo '{"permissions":{"allow":["Bash(ls:*)"]}}' > "$BOOT/dev.json"
# orch-auto-allow.yaml: read-only 카테고리에 find
mkdir -p "$HARNESS_PROJECT/config"
cat > "$HARNESS_PROJECT/config/orch-auto-allow.yaml" <<'YAML'
read-only:
  - "Bash(find:*)"
YAML

TAB="$(printf '\t')"

echo "[C1] matrix MATCH → 'matrix<TAB>pattern'"
out="$(classify "dev" "Bash" '{"command":"ls -la"}')"
assert_eq "matrix${TAB}Bash(ls:*)" "$out" "C1 matrix"

echo "[C2] danger MATCH → 'danger<TAB>category'"
out="$(classify "dev" "Bash" '{"command":"rm -rf /tmp/x"}')"
assert_eq "danger${TAB}rm-recursive" "$out" "C2 danger"

echo "[C3] auto-allow MATCH → 'auto<TAB>category<TAB>pattern' (colon 보존)"
out="$(classify "dev" "Bash" '{"command":"find . -name x"}')"
assert_eq "auto${TAB}read-only${TAB}Bash(find:*)" "$out" "C3 auto colon 보존"

echo "[C4] 회색 → 'gray<TAB>'"
out="$(classify "dev" "Bash" '{"command":"npm test"}')"
assert_eq "gray${TAB}" "$out" "C4 gray"

echo "[C5] 우선순위: danger 가 auto 보다 먼저 (sudo find — sudo danger + find auto 동시 매칭)"
out="$(classify "dev" "Bash" '{"command":"sudo find ."}')"
assert_eq "danger${TAB}sudo" "$out" "C5 danger 우선 (sudo)"

echo "[C6] ★ 권한상승 차단: settings.allow 에 위험 패턴이 학습돼도 danger 가 matrix 우선 차단"
# 실수/악의로 dev.json allow 에 Bash(sudo:*) 가 끼어든 상태를 합성.
echo '{"permissions":{"allow":["Bash(sudo:*)"]}}' > "$BOOT/dev.json"
out="$(classify "dev" "Bash" '{"command":"sudo rm x"}')"
# matrix 가 먼저였다면 'matrix Bash(sudo:*)' (allow!) — danger 우선이라 'danger sudo' (deny).
assert_eq "danger${TAB}sudo" "$out" "C6 학습된 위험패턴도 danger 가 차단 (권한상승 방지)"
# 원복
echo '{"permissions":{"allow":["Bash(ls:*)"]}}' > "$BOOT/dev.json"

test_summary
