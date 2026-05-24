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

echo "[Y6] safe-fs: chmod +x 매칭"
out="$(lead_auto_allow_lookup Bash '{"command":"chmod +x todo.sh"}')"
assert_eq "safe-fs:Bash(chmod +x:*)" "$out" "Y6 chmod +x → safe-fs"

echo "[Y7] safe-fs: mkdir / touch 매칭"
out="$(lead_auto_allow_lookup Bash '{"command":"mkdir tests"}')"
assert_eq "safe-fs:Bash(mkdir:*)" "$out" "Y7 mkdir → safe-fs"
out="$(lead_auto_allow_lookup Bash '{"command":"touch a.txt"}')"
assert_eq "safe-fs:Bash(touch:*)" "$out" "Y7 touch → safe-fs"

echo "[Y9] git-write: 로컬 git 쓰기 매칭 (add/commit 만 — checkout/switch 는 회색)"
out="$(lead_auto_allow_lookup Bash '{"command":"git add todo.sh"}')"
assert_eq "git-write:Bash(git add:*)" "$out" "Y9 git add → git-write"
out="$(lead_auto_allow_lookup Bash '{"command":"git commit -m x"}')"
assert_eq "git-write:Bash(git commit:*)" "$out" "Y9 git commit → git-write"

echo "[Y10] read-only 보강: diff / which / echo 매칭"
out="$(lead_auto_allow_lookup Bash '{"command":"diff -u a b"}')"
assert_eq "read-only:Bash(diff:*)" "$out" "Y10 diff → read-only"
out="$(lead_auto_allow_lookup Bash '{"command":"which jq"}')"
assert_eq "read-only:Bash(which:*)" "$out" "Y10 which → read-only"
out="$(lead_auto_allow_lookup Bash '{"command":"echo hi"}')"
assert_eq "read-only:Bash(echo:*)" "$out" "Y10 echo → read-only"

echo "[Y11] 의도적 회색 유지 (안전등급 차이로 사람 1회 승인)"
lead_auto_allow_lookup Bash '{"command":"bash ./test.sh"}' >/dev/null
assert_fail "$?" "Y11 bash ./X 는 회색 (auto 제외)"
lead_auto_allow_lookup Bash '{"command":"./todo.sh list"}' >/dev/null
assert_fail "$?" "Y11 ./X 는 회색 (auto 제외)"
lead_auto_allow_lookup Bash '{"command":"git checkout -- todo.sh"}' >/dev/null
assert_fail "$?" "Y11 git checkout 은 회색 (데이터손실 인지)"
lead_auto_allow_lookup Bash '{"command":"git switch main"}' >/dev/null
assert_fail "$?" "Y11 git switch 는 회색"
lead_auto_allow_lookup Bash '{"command":"bash /etc/passwd"}' >/dev/null
assert_fail "$?" "Y11 bash /절대경로 미매칭"

test_summary
