#!/usr/bin/env bash
# parse_entry 4필드 + 모호성 해소(§2.2) + 폴백 체인(§2.3).
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT/tests/assert.sh"

# P1: is_known_vendor — claude 존재(O), haiku/opus(모델, X)
( set +u; HARNESS_ROOT="$ROOT"; . "$ROOT/bin/lib.sh"
  is_known_vendor claude && ! is_known_vendor haiku && ! is_known_vendor opus )
assert_success "$?" "P1 is_known_vendor claude=O, haiku/opus=X"

# parse_entry 격리 검증: 함수 정의부를 sed 로 떼어 eval (진입점 부수효과 회피).
extract_parse_entry() { sed -n '/^parse_entry() {/,/^}/p' "$ROOT/bin/awa-up.sh"; }
run_parse() {  # $1=entry $2=harness_vendor → "name|role|vendor|model"
  ( set +u
    HARNESS_ROOT="$ROOT"; HARNESS_VENDOR="$2"
    . "$ROOT/bin/lib.sh"
    eval "$(extract_parse_entry)"
    parse_entry "$1"
    printf '%s|%s|%s|%s' "$ENTRY_NAME" "$ENTRY_ROLE" "${ENTRY_VENDOR:-}" "$ENTRY_MODEL" )
}

# P2: 2필드 — 벤더 빈값, 모델 역할기본(기존 동작 보존)
assert_eq "dev|dev||sonnet" "$(run_parse "dev:dev" "claude")" "P2 2필드"
# P3: 3필드 + 3번째=모델(haiku, 벤더 아님) → 역호환
assert_eq "quality-rev|reviewer-quality||haiku" "$(run_parse "quality-rev:reviewer-quality:haiku" "claude")" "P3 3필드 모델(역호환)"
# P4: 3필드 + 3번째=벤더(claude 화이트리스트) → 벤더, 모델 빈값(폴백 대상)
assert_eq "dev2|dev|claude|" "$(run_parse "dev2:dev:claude" "claude")" "P4 3필드 벤더"
# P5: 4필드 — 벤더+모델 명시
assert_eq "dev3|dev|claude|opus" "$(run_parse "dev3:dev:claude:opus" "claude")" "P5 4필드"

# P6: 모델 미지정 reviewer → vendor_default_model 폴백 (claude reviewer=opus)
out="$( set +u; HARNESS_ROOT="$ROOT"; . "$ROOT/bin/lib.sh"; . "$ROOT/bin/vendors/claude.sh"
  vendor_default_model reviewer-quality )"
assert_eq "opus" "$out" "P6 claude reviewer 폴백=opus(품질우선)"
# P7: review-manager 도 opus (리뷰 총괄)
out="$( set +u; HARNESS_ROOT="$ROOT"; . "$ROOT/bin/lib.sh"; . "$ROOT/bin/vendors/claude.sh"
  vendor_default_model review-manager )"
assert_eq "opus" "$out" "P7 claude review-manager 폴백=opus"

# P8: 5필드 이상 거부 — 모델에 콜론 잔존(필드 초과 오타) 사전 차단.
( set +u; HARNESS_ROOT="$ROOT"; . "$ROOT/bin/lib.sh"
  eval "$(extract_parse_entry)"
  parse_entry "dev:dev:claude:opus:extra" ) >/dev/null 2>&1
assert_fail "$?" "P8 5필드 이상 거부"

test_summary
