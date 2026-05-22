#!/usr/bin/env bash
# config/lead-auto-allow.yaml 의 카테고리 매칭 (실제 yaml + matrix-lookup).
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"
export HARNESS_PROJECT="$ROOT"   # config/lead-auto-allow.yaml 이 ROOT/config 에 있음
# shellcheck disable=SC1091
source "$ROOT/bin/lib.sh"
# shellcheck disable=SC1091
source "$ROOT/bin/matrix-lookup.sh"

[ -f "$ROOT/config/lead-auto-allow.yaml" ]; assert_success "$?" "yaml 존재"

echo "[Y1] read-only 매칭"
out="$(lead_auto_allow_lookup Bash '{"command":"ls /tmp"}')"
assert_eq "read-only:Bash(ls:*)" "$out" "Y1 ls → read-only"

echo "[Y2] safe-test 매칭"
out="$(lead_auto_allow_lookup Bash '{"command":"pytest tests/"}')"
assert_eq "safe-test:Bash(pytest:*)" "$out" "Y2 pytest → safe-test"

echo "[Y3] git-readonly 매칭"
out="$(lead_auto_allow_lookup Bash '{"command":"git status"}')"
assert_eq "git-readonly:Bash(git status:*)" "$out" "Y3 git status"

echo "[Y4] 위험 명령 미포함 (rm -rf 는 매칭 안 됨 — danger-check 영역)"
lead_auto_allow_lookup Bash '{"command":"rm -rf /tmp"}' >/dev/null
assert_fail "$?" "Y4 rm -rf 미매칭"

echo "[Y5] dev-deps lock-file 기반만 (npm install <pkg> 미매칭)"
lead_auto_allow_lookup Bash '{"command":"npm install evil-pkg"}' >/dev/null
assert_fail "$?" "Y5 npm install <pkg> 미매칭 (공급망 보수 정책)"
out="$(lead_auto_allow_lookup Bash '{"command":"npm ci"}')"
assert_eq "dev-deps:Bash(npm ci:*)" "$out" "Y5 npm ci 매칭"

test_summary
