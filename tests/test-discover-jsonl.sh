#!/usr/bin/env bash
# discover_jsonl_and_record: cwd 인코딩 + --session-id(uuid) 결정론 매칭 → workers.list 5필드.
# 5차 정정: mtime 폴링 폐기. claude --session-id 가 jsonl 파일명을 결정하므로
#   uuid 로 경로를 직접 계산 (race·타이밍 면역). 파일 존재 여부와 무관하게 기록.
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

# claude 인코딩 (실측 확정): realpath(pwd -P) 후 [^a-zA-Z0-9]→'-'.
# macOS /var → /private/var 정규화 + . _ 등 모든 비영숫자 dash. 함수와 동일 규칙으로 독립 산출.
PROJ_REAL="$(cd "$PROJ" && pwd -P)"
cwd_encoded="$(printf '%s' "$PROJ_REAL" | sed 's#[^a-zA-Z0-9]#-#g')"
PROJDIR="$TMPHOME/.claude/projects/${cwd_encoded}"
mkdir -p "$PROJDIR"
LIST="$PROJ/.agent-harness/state/workers.list"

echo "[D1] uuid 로 jsonl 경로 결정론 계산 + 5필드 append (파일 존재 시)"
SID="11111111-1111-4111-8111-111111111111"
touch "$PROJDIR/$SID.jsonl"
discover_jsonl_and_record "arch" "%5" "$PROJ" "$SID" "researcher"
[ -f "$LIST" ]; assert_success "$?" "D1 workers.list 생성"
line="$(grep '^arch ' "$LIST")"
assert_eq "arch %5 $SID $PROJDIR/$SID.jsonl researcher" "$line" "D1 5필드 정확"

echo "[D2] entry_role 이 5번째 필드"
fifth="$(grep '^arch ' "$LIST" | awk '{print $5}')"
assert_eq "researcher" "$fifth" "D2 5번째=entry_role"

echo "[D3] 파일 미생성이어도 uuid 경로로 기록 (tail -F 가 생성 대기 — race 면역)"
# claude jsonl 은 첫 메시지 후에야 생김. discover 는 파일 없어도 경로를 확정 기록해야 함.
SID3="33333333-3333-4333-8333-333333333333"
# 일부러 파일 안 만듦
discover_jsonl_and_record "lead" "%9" "$PROJ" "$SID3" "lead"
rc=$?
assert_success "$rc" "D3 파일 없어도 rc=0"
line3="$(grep '^lead ' "$LIST")"
assert_eq "lead %9 $SID3 $PROJDIR/$SID3.jsonl lead" "$line3" "D3 미생성 파일도 경로 기록"

echo "[D4] ★ race 재현: 여러 워커 동시 부트 시 각자 자기 uuid 로 정확히 매칭"
# 기존 mtime 방식의 결함 재현 — 여러 jsonl 이 같은 디렉터리에 거의 동시 생성될 때
#   mtime 최신순은 워커별 구분 불가 (전부 '최신 1등'을 가로챔).
# uuid 결정론이면 부트/생성 순서·mtime 과 무관하게 1:1 정확.
PROJ4="$(mktemp -d)"; ( cd "$PROJ4" && git init -q )
P4REAL="$(cd "$PROJ4" && pwd -P)"
enc4="$(printf '%s' "$P4REAL" | sed 's#[^a-zA-Z0-9]#-#g')"
PD4="$TMPHOME/.claude/projects/${enc4}"
mkdir -p "$PD4"
DEV_SID="aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
TEST_SID="bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
REV_SID="cccccccc-cccc-4ccc-8ccc-cccccccccccc"
# 생성 순서를 일부러 부트 순서와 어긋나게 (mtime 함정 재현): test → dev → rev
touch "$PD4/$TEST_SID.jsonl"; sleep 0.01
touch "$PD4/$DEV_SID.jsonl"; sleep 0.01
touch "$PD4/$REV_SID.jsonl"
LIST4="$PROJ4/.agent-harness/state/workers.list"
# 부트 순서대로 discover 호출 (dev 먼저) — mtime 최신은 rev 인데, dev 는 자기 uuid 잡아야 함
discover_jsonl_and_record "dev"  "%1" "$PROJ4" "$DEV_SID"  "dev"
discover_jsonl_and_record "test" "%2" "$PROJ4" "$TEST_SID" "tester"
discover_jsonl_and_record "rev"  "%3" "$PROJ4" "$REV_SID"  "reviewer-quality"
dev_sid="$(grep '^dev '  "$LIST4" | awk '{print $3}')"
test_sid="$(grep '^test ' "$LIST4" | awk '{print $3}')"
rev_sid="$(grep '^rev '  "$LIST4" | awk '{print $3}')"
assert_eq "$DEV_SID"  "$dev_sid"  "D4 dev → 자기 uuid (mtime 함정 면역)"
assert_eq "$TEST_SID" "$test_sid" "D4 test → 자기 uuid"
assert_eq "$REV_SID"  "$rev_sid"  "D4 rev → 자기 uuid"
# 중복 매칭 없음 (기존 결함: lead·quality-rev 가 같은 파일 가리킴)
uniq_count="$(awk '{print $3}' "$LIST4" | sort -u | wc -l | tr -d ' ')"
assert_eq "3" "$uniq_count" "D4 3개 워커 모두 서로 다른 jsonl (중복 매칭 0)"

rm -rf "$TMPHOME" "$PROJ" "$PROJ4"
test_summary
