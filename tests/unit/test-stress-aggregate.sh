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

test_summary
