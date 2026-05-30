#!/usr/bin/env bash
# add_to_allow mkdir 락 동시성: 병렬 호출 시 lost update 없음.
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"
export HARNESS_PROJECT="$(mktemp -d)"
( cd "$HARNESS_PROJECT" && git init -q )
# shellcheck disable=SC1091
source "$ROOT/bin/lib.sh"

BOOT="$HARNESS_PROJECT/.agent-harness/.boot-settings"
mkdir -p "$BOOT"
echo '{"permissions":{"allow":[]}}' > "$BOOT/dev.json"

echo "[L1] 20개 패턴 병렬 add_to_allow → 전부 보존 (lost update 없음, 부하 강화)"
# ★ 10개론 stale-회수 race 가 우연히 안 터질 수 있어 20개로 부하 2배 (5차 실측 — race 노출 확률↑).
for i in $(seq 1 20); do
  add_to_allow "dev" "Bash(cmd${i}:*)" &
done
wait
count="$(jq '.permissions.allow | length' "$BOOT/dev.json")"
assert_eq "20" "$count" "L1 병렬 20개 전부 보존"

echo "[L2] lock 디렉터리 정리됨 (잔존 없음)"
[ ! -d "$BOOT/dev.json.lock" ]; assert_success "$?" "L2 lock 정리"

echo "[L3] 중복 패턴은 unique (1개만)"
add_to_allow "dev" "Bash(dup:*)"
add_to_allow "dev" "Bash(dup:*)"
dups="$(jq '[.permissions.allow[] | select(. == "Bash(dup:*)")] | length' "$BOOT/dev.json")"
assert_eq "1" "$dups" "L3 중복 unique"

echo "[L4] ★ 진짜 stale lock(16s 묵음)은 회수, mt=0 오인삭제 race 없음 (5차 실측 결함)"
# 16초 전 mtime 의 lock 을 깔면(보유자 사망 시뮬) 다음 add_to_allow 가 회수 후 진입해야.
mkdir "$BOOT/dev.json.lock"
touch -t "$(date -v-16S +%Y%m%d%H%M.%S 2>/dev/null || date -d '16 seconds ago' +%Y%m%d%H%M.%S)" "$BOOT/dev.json.lock"
add_to_allow "dev" "Bash(after-stale:*)"
has="$(jq -r '[.permissions.allow[] | select(. == "Bash(after-stale:*)")] | length' "$BOOT/dev.json")"
assert_eq "1" "$has" "L4 16s stale lock 회수 후 추가됨"
[ ! -d "$BOOT/dev.json.lock" ]; assert_success "$?" "L4 회수 후 lock 정리"

test_summary
