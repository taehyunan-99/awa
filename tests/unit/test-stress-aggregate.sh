#!/usr/bin/env bash
# 13차+: 스트레스 측정 집계 함수 단위 검증 (세션 불요).
# 경로 패턴은 기존 unit/test-matrix-lookup.sh:4-6 과 동일 — tests/ 로 올라간 뒤 source.
set -uo pipefail
cd "$(dirname "$0")/.."   # tests/ 로 이동 (assert.sh 는 tests/ 에 있음)
source ./assert.sh
ROOT="$(cd .. && pwd)"   # repo 루트
source "$ROOT/tests/stress/stress-lib.sh"

echo "[A1] extract_done_ids — capture 덤프에서 worker/task 고유 집합 추출 (cat echo 중복 흡수)"
# cat 더미 LEAD pane 은 같은 @done 라인을 여러 번 echo 한다 (3주입→7카운트 실측).
# extract_done_ids 는 'worker/task' 식별자만 뽑아 sort -u 로 고유화해야 한다.
dump="$(printf '%s\n' \
  '@done: dev1/T1 완료. results/ 확인 후 종합.' \
  '@done: dev1/T1 완료. results/ 확인 후 종합.' \
  '@done: dev2/T2 완료. results/ 확인 후 종합.' \
  '@done: dev1/T1 완료. results/ 확인 후 종합.' \
  '@done: dev3/T3 완료. results/ 확인 후 종합.')"
ids="$(extract_done_ids "$dump")"
assert_eq "dev1/T1
dev2/T2
dev3/T3" "$ids" "A1 고유 done 식별자 3개 (중복 흡수)"

echo "[A2] extract_gate_ids — @gate 알림에서 uuid 고유 집합 추출"
gdump="$(printf '%s\n' \
  '@gate: 워커 승인 대기 (uuid=u1). pending-asks 처리.' \
  '@gate: 워커 승인 대기 (uuid=u1). pending-asks 처리.' \
  '@gate: 워커 승인 대기 (uuid=u2). pending-asks 처리.')"
gids="$(extract_gate_ids "$gdump")"
assert_eq "u1
u2" "$gids" "A2 고유 gate uuid 2개"

echo "[A3] missing_ids — 발생 집합 중 처리 집합에 없는 것 (유실 검출)"
expected="$(printf 'dev1/T1\ndev2/T2\ndev3/T3\ndev4/T4')"
processed="$(printf 'dev1/T1\ndev2/T2\ndev3/T3')"  # dev4/T4 유실
miss="$(missing_ids "$expected" "$processed")"
assert_eq "dev4/T4" "$miss" "A3 유실 식별자 검출"

echo "[A4] missing_ids — 유실 없으면 빈 출력"
miss2="$(missing_ids "$processed" "$processed")"
assert_eq "" "$miss2" "A4 유실 없음 → 빈 문자열"

echo "[A5] extract_* — 매칭 0건이어도 set -e 호출자에서 안전 (I-1 회귀)"
# grep -oE 는 매칭 0건이면 rc=1 → pipefail 하 파이프라인 rc=1 → set -e 호출자 사망.
# 함수가 || true 로 흡수해 빈 출력+rc0 을 보장해야 한다.
( set -e
  z1="$(extract_done_ids "마커 없는 잡음 라인")"
  z2="$(extract_gate_ids "uuid 없는 라인")"
  [ -z "$z1" ] && [ -z "$z2" ]
)
assert_eq "0" "$?" "A5 0건 매칭 시 set -e 환경 생존 (빈 출력·rc0)"

echo "[A6] inject_done_lines — events.log 에 N개 done 라인을 워커별로 append"
TMP="$(mktemp -d)"; EV="$TMP/events.log"
inject_done_lines "$EV" "dev1 dev2 dev3" "T"
# 워커 3명 × task 1개 = 3 done 라인. 형식: ts\tworker\tT<i>\tdone\t-
cnt="$(awk -F'\t' '$4=="done"{c++} END{print c+0}' "$EV")"
assert_eq "3" "$cnt" "A6a done 라인 3개"
ids="$(awk -F'\t' '$4=="done"{print $2"/"$3}' "$EV" | sort -u)"
assert_eq "dev1/T1
dev2/T2
dev3/T3" "$ids" "A6b 워커별 식별자 정확"

echo "[A7] inject_pending_asks — state/pending-asks/ 에 K개 .json 생성"
mkdir -p "$TMP/state/pending-asks"
inject_pending_asks "$TMP/state/pending-asks" "u1 u2 u3 u4"
jcnt="$(ls "$TMP/state/pending-asks"/*.json 2>/dev/null | wc -l | tr -d ' ')"
assert_eq "4" "$jcnt" "A7 pending-asks 4개 .json"
rm -rf "$TMP"

test_summary
