#!/usr/bin/env bash
# T1 회귀: HARNESS_ROOT_VALID 변수가 PROJECT_ROOT_VALID 와 같은 패턴 적용.
# 4차 spec P1: sed `#` 구분자 안전성·토큰 치환 안전성 보장.
#
# 함수화(_validate_path_chars) 이후 — 테스트는 함수를 직접 호출.
# 이전엔 lib.sh 의 case 를 복붙해 검증해서, case 가 변형돼도 회귀 못 잡는 약점이 있었다.
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
source ./harness-paths.sh
ROOT="$(cd .. && pwd)"

# 서브셸 안 assert 는 카운터 부모 전파 안 됨(3차 T1 교훈). 모두 메인 셸 평탄 호출.

# lib.sh source 후 _validate_path_chars 함수 사용 가능.
# shellcheck disable=SC1091
source "$HARNESS_BIN/lib.sh" 2>/dev/null

# T1.1: 현재 HARNESS_ROOT 가 정상 (안전한 문자만) → VALID=1.
assert_eq "1" "$HARNESS_ROOT_VALID" "정상 HARNESS_ROOT 는 VALID=1"

# T1.2: 공백 포함 → 0.
out="$(_validate_path_chars "/tmp/has space")"
assert_eq "0" "$out" "공백 포함 경로 → 0"

# T1.3: `#` 포함 (sed 구분자 깨짐 위험) → 0.
out="$(_validate_path_chars "/tmp/has#hash")"
assert_eq "0" "$out" "# 포함 경로 → 0"

# T1.4: 빈 문자열 → 0 (자동 도출 실패 시그널 — 위험).
out="$(_validate_path_chars "")"
assert_eq "0" "$out" "빈 문자열 → 0"

# T1.5: 정상 경로 (영숫자·/._-) → 1.
out="$(_validate_path_chars "/normal/path-1.0/dir_a")"
assert_eq "1" "$out" "정상 경로 → 1"

test_summary
