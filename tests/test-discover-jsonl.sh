#!/usr/bin/env bash
# discover_jsonl_and_record: cwd 인코딩·mtime 필터·workers.list 5필드 append.
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"
TMPHOME="$(mktemp -d)"
PROJ="$(mktemp -d)"
( cd "$PROJ" && git init -q )
export HARNESS_PROJECT="$PROJ"
export HOME="$TMPHOME"   # ~/.claude/projects 경로 격리
# shellcheck disable=SC1091
source "$ROOT/bin/lib.sh"

# claude 인코딩 (실측 확정, e2e probe): realpath(pwd -P) 후 [^a-zA-Z0-9]→'-'.
# macOS /var → /private/var 정규화 + . _ 등 모든 비영숫자 dash. 함수와 동일 규칙으로 독립 산출.
PROJ_REAL="$(cd "$PROJ" && pwd -P)"
cwd_encoded="$(printf '%s' "$PROJ_REAL" | sed 's#[^a-zA-Z0-9]#-#g')"
PROJDIR="$TMPHOME/.claude/projects/${cwd_encoded}"
mkdir -p "$PROJDIR"

echo "[D1] started 이후 mtime jsonl 발견 + 5필드 append"
started="$(date +%s)"
sleep 1
SID="abcd-1234"
touch "$PROJDIR/$SID.jsonl"
discover_jsonl_and_record "arch" "%5" "$PROJ" "$started" "researcher"
LIST="$PROJ/.agent-harness/state/workers.list"
[ -f "$LIST" ]; assert_success "$?" "D1 workers.list 생성"
line="$(cat "$LIST")"
assert_eq "arch %5 $SID $PROJDIR/$SID.jsonl researcher" "$line" "D1 5필드 정확"

echo "[D2] entry_role 이 5번째 필드"
fifth="$(awk '{print $5}' "$LIST")"
assert_eq "researcher" "$fifth" "D2 5번째=entry_role"

echo "[D3] started 이전 mtime jsonl 무시 → 미발견 경고 + rc=1"
PROJ2="$(mktemp -d)"; ( cd "$PROJ2" && git init -q )
PROJ2_REAL="$(cd "$PROJ2" && pwd -P)"
enc2="$(printf '%s' "$PROJ2_REAL" | sed 's#[^a-zA-Z0-9]#-#g')"
PD2="$TMPHOME/.claude/projects/${enc2}"
mkdir -p "$PD2"
touch -t 200001010000 "$PD2/old.jsonl"
started2="$(date +%s)"
DISCOVER_MAX_TRIES=1 discover_jsonl_and_record "x" "%1" "$PROJ2" "$started2" "dev" 2>/dev/null
rc=$?
assert_fail "$rc" "D3 미발견 rc=1"

rm -rf "$TMPHOME" "$PROJ" "$PROJ2"
test_summary
