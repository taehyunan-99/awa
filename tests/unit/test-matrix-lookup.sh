#!/usr/bin/env bash
# matrix_lookup + orch_auto_allow_lookup 단위 테스트.
set -uo pipefail
cd "$(dirname "$0")/.."   # tests/ 로 이동
source ./assert.sh
source ./harness-paths.sh
ROOT="$(cd .. && pwd)"
export HARNESS_PROJECT="$(mktemp -d)"
( cd "$HARNESS_PROJECT" && git init -q )
# shellcheck disable=SC1091
source "$HARNESS_BIN/lib.sh"
# shellcheck disable=SC1091
source "$HARNESS_BIN/matrix-lookup.sh"

BOOTSET="$HARNESS_PROJECT/.agent-harness/.boot-settings"
mkdir -p "$BOOTSET"

echo "[M1] matrix_lookup MATCH (Bash prefix)"
echo '{"permissions":{"allow":["Bash(ls:*)"]}}' > "$BOOTSET/dev.json"
matched="$(matrix_lookup dev Bash '{"command":"ls /tmp"}')"
assert_success "$?" "M1 exit 0"
assert_eq "Bash(ls:*)" "$matched" "M1 매칭 패턴"

echo "[M2] matrix_lookup NO_MATCH"
matrix_lookup dev Bash '{"command":"npm test"}' >/dev/null
assert_fail "$?" "M2 NO_MATCH exit 1"

echo "[M3] matrix_lookup allow 키 부재 (// [] fallback) → NO_MATCH"
echo '{"permissions":{"deny":["Bash(rm *)"]}}' > "$BOOTSET/dev.json"
matrix_lookup dev Bash '{"command":"ls"}' >/dev/null
assert_fail "$?" "M3 allow 부재 NO_MATCH"

echo "[M4] matrix_lookup Tool 단독 패턴"
echo '{"permissions":{"allow":["Read"]}}' > "$BOOTSET/dev.json"
matched="$(matrix_lookup dev Read '{"file_path":"/a"}')"
assert_eq "Read" "$matched" "M4 Tool 단독"

echo "[M5] matrix_lookup exact literal"
echo '{"permissions":{"allow":["Bash(npm test foo)"]}}' > "$BOOTSET/dev.json"
matched="$(matrix_lookup dev Bash '{"command":"npm test foo"}')"
assert_eq "Bash(npm test foo)" "$matched" "M5 exact"

echo "[M5b] matrix_lookup space-glob (4차 P0 컨벤션 호환)"
echo '{"permissions":{"deny":[],"allow":["Bash(git push *)"]}}' > "$BOOTSET/dev.json"
matched="$(matrix_lookup dev Bash '{"command":"git push origin"}')"
assert_eq "Bash(git push *)" "$matched" "M5b space-glob"

echo "[M6] orch_auto_allow_lookup safe-test 매칭"
mkdir -p "$HARNESS_PROJECT/.agent-harness/config"
cat > "$HARNESS_PROJECT/.agent-harness/config/orch-auto-allow.yaml" <<'EOF'
read-only:
  - "Bash(ls:*)"
safe-test:
  - "Bash(npm test:*)"
  - "Bash(pytest:*)"
EOF
out="$(orch_auto_allow_lookup Bash '{"command":"npm test foo"}')"
assert_success "$?" "M6 exit 0"
assert_eq "safe-test:Bash(npm test:*)" "$out" "M6 category:pattern"

echo "[M7] orch_auto_allow_lookup NO_MATCH"
orch_auto_allow_lookup Bash '{"command":"custom-tool"}' >/dev/null
assert_fail "$?" "M7 NO_MATCH"

echo "[M8] orch_auto_allow_lookup 위에서 아래로 — 첫 매칭 채택"
out="$(orch_auto_allow_lookup Bash '{"command":"ls /tmp"}')"
assert_eq "read-only:Bash(ls:*)" "$out" "M8 read-only 매칭"

test_summary
