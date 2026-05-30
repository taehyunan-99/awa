#!/usr/bin/env bash
# splash 렌더 단위 테스트 — 팀 요약 파일 기반 popup 렌더(python3 표시폭 정렬).
# awa-splash.sh 는 인자 없음, $AWA_SPLASH_TEAM_FILE 에서 팀을 읽는다.
# AWA_SPLASH_TIMEOUT=0 으로 read 즉시 반환시켜 테스트가 멈추지 않게 한다.
# 렌더는 /usr/bin/python3(시스템 stdlib)에 의존 — 표시폭(한글 2칸/블록 1칸) 정확 계산.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT/tests/assert.sh"
SP="$ROOT/bin/awa-splash.sh"

# ANSI 제거 헬퍼 — 색코드 섞인 출력에서 텍스트만 검증.
strip_ansi() { sed 's/\x1b\[[0-9;]*m//g'; }

# 팀 요약 fixture (탭 구분: 이름<TAB>역할<TAB>모델)
TMP_TEAM="$(mktemp)"
printf 'LEAD\tlead\topus\n'                >  "$TMP_TEAM"
printf 'PM\tpm\tsonnet\n'                  >> "$TMP_TEAM"
printf 'dev1\tdev\tsonnet\n'               >> "$TMP_TEAM"
printf 'tester1\ttester\tsonnet\n'         >> "$TMP_TEAM"
printf 'qrev\treviewer-quality\thaiku\n'   >> "$TMP_TEAM"
printf 'sec\tsecurity\tsonnet\n'           >> "$TMP_TEAM"

# 넓은 화면으로 고정(COLUMNS) — 정상 팀은 자르지 않아야 함.
raw="$(COLUMNS=120 LINES=50 AWA_SPLASH_TIMEOUT=0 AWA_SPLASH_TEAM_FILE="$TMP_TEAM" "$SP" 2>&1)"; rc=$?
out="$(printf '%s' "$raw" | strip_ansi)"

assert_success "$rc" "S1 정상 종료(read -t 0 즉시 반환)"
# 브랜딩
assert_contains "$out" "Agents Watching Agents" "S2 태그라인"
assert_contains "$out" "█" "S3 로고 블록문자 존재"
# 로고는 half-block(▀▄) 을 의도적으로 사용 — ghostty 등에서 ambiguous=1칸으로 폭 일치.
# (이전 'half-block 금지' 정책은 ghostty 실측으로 폐기 — AWA 로 또렷이 읽힘.)
assert_contains "$out" "▀" "S4a 로고에 half-block ▀ 사용(의도)"
assert_contains "$out" "▄" "S4b 로고에 half-block ▄ 사용(의도)"
# 팀 멤버 이름·모델
assert_contains "$out" "LEAD"    "S5a LEAD 이름"
assert_contains "$out" "PM"      "S5b PM 이름"
assert_contains "$out" "dev1"    "S5c dev1 이름"
assert_contains "$out" "tester1" "S5d tester1 이름"
assert_contains "$out" "qrev"    "S5e qrev 이름"
assert_contains "$out" "opus"    "S5f opus 모델"
assert_contains "$out" "haiku"   "S5g haiku 모델"
# 역할 → 한국어 요약 매핑 (splash_role_summary)
assert_contains "$out" "팀 감독"        "S6a lead 요약"
assert_contains "$out" "사용자 창구"    "S6b pm 요약"
assert_contains "$out" "개발"          "S6c dev 요약"
assert_contains "$out" "품질 검증"      "S6d tester 요약"
assert_contains "$out" "드리프트 추적"  "S6e reviewer-quality 요약"
assert_contains "$out" "안전 한계선"    "S6f security 요약"
# raw 역할 문자열은 표에 노출 안 됨(요약으로 치환).
assert_not_contains "$out" "reviewer-quality" "S6g raw role 미노출(요약으로 치환)"
# 구분선·닫힘 안내
assert_contains "$out" "팀 구성" "S7a 구분선 라벨"
assert_contains "$out" "시작"    "S7b 닫힘 안내 문구"

# 팀 요약 파일 부재 → 로고/태그라인만, 멤버 없음, 크래시 없음
raw2="$(COLUMNS=120 LINES=50 AWA_SPLASH_TIMEOUT=0 AWA_SPLASH_TEAM_FILE="/nonexistent/team.txt" "$SP" 2>&1)"; rc2=$?
out2="$(printf '%s' "$raw2" | strip_ansi)"
assert_success "$rc2" "S8a 파일 부재에도 정상 종료"
assert_contains "$out2" "Agents Watching Agents" "S8b 파일 부재에도 태그라인"
assert_not_contains "$out2" "dev1" "S8c 파일 부재 시 멤버 없음"
assert_not_contains "$out2" "팀 구성" "S8d 파일 부재 시 구분선 없음"

# 긴 이름 → … 로 잘림(좁은 화면). 모든 줄이 화면 폭 안.
TMP_LONG="$(mktemp)"
printf 'dev\tdev\tsonnet\n'                                       >  "$TMP_LONG"
printf 'super-long-reviewer-name-here\treviewer-quality\thaiku\n' >> "$TMP_LONG"
raw3="$(COLUMNS=80 LINES=40 AWA_SPLASH_TIMEOUT=0 AWA_SPLASH_TEAM_FILE="$TMP_LONG" "$SP" 2>&1)"; rc3=$?
out3="$(printf '%s' "$raw3" | strip_ansi)"
assert_success "$rc3" "S9a 긴 값에도 정상 종료"
assert_contains "$out3" "…" "S9b 긴 이름 … 로 잘림"
assert_not_contains "$out3" "super-long-reviewer-name-here" "S9c 원본 긴 이름 미노출(잘림)"
# 모든 줄 표시폭이 화면 폭(80) 이하 — python 으로 검증.
maxw="$(printf '%s\n' "$out3" | /usr/bin/python3 -c '
import sys,unicodedata as u
def w(s): return sum(2 if u.east_asian_width(c) in ("W","F") else 1 for c in s)
print(max((w(l.rstrip(chr(10))) for l in sys.stdin), default=0))')"
assert_eq "1" "$([ "$maxw" -le 80 ] && echo 1 || echo 0)" "S9d 모든 줄 폭<=80(=$maxw)"

# 소스 정적 검사
assert_contains "$(cat "$SP")" "NO_COLOR" "S10 NO_COLOR 가드 존재"
assert_contains "$(cat "$SP")" "AWA_SPLASH_TIMEOUT" "S11 타임아웃 env 존재"
assert_contains "$(cat "$SP")" "read -t" "S12 read -t 닫힘 메커니즘(tmux -k 미의존)"
assert_contains "$(cat "$SP")" "/usr/bin/python3" "S13 python3 렌더 의존"

rm -f "$TMP_TEAM" "$TMP_LONG"
test_summary
