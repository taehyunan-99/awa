#!/usr/bin/env bash
# parse_entry 4필드 + 모호성 해소(§2.2) + 폴백 체인(§2.3).
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT/tests/assert.sh"
. "$ROOT/tests/harness-paths.sh"

# P1: is_known_vendor — claude 존재(O), haiku/opus(모델, X)
( set +u; HARNESS_ROOT="$HARNESS"; . "$HARNESS_BIN/lib.sh"
  is_known_vendor claude && ! is_known_vendor haiku && ! is_known_vendor opus )
assert_success "$?" "P1 is_known_vendor claude=O, haiku/opus=X"

# parse_entry 격리 검증: 함수 정의부를 sed 로 떼어 eval (진입점 부수효과 회피).
extract_parse_entry() { sed -n '/^parse_entry() {/,/^}/p' "$HARNESS_BIN/awa-up.sh"; }
run_parse() {  # $1=entry $2=harness_vendor → "name|role|vendor|model"
  ( set +u
    HARNESS_ROOT="$HARNESS"; HARNESS_VENDOR="$2"
    . "$HARNESS_BIN/lib.sh"
    eval "$(extract_parse_entry)"
    parse_entry "$1"
    printf '%s|%s|%s|%s' "$ENTRY_NAME" "$ENTRY_ROLE" "${ENTRY_VENDOR:-}" "$ENTRY_MODEL" )
}

# P2: 2필드 — 벤더 빈값, 모델 미지정(빈값). 폴백 체인(awa-up L530)이 해석된 벤더의
#   vendor_default_model 로 채움 (P9 수정 2026-05-30: sonnet 하드코딩 제거 → codex 워커
#   sonnet 400 에러 해소. claude=sonnet·codex=gpt-5.5 를 폴백이 벤더별로 채우므로 여기선 빈값).
assert_eq "dev|dev||" "$(run_parse "dev:dev" "claude")" "P2 2필드 (모델 빈값 — 폴백 대상)"
# P3: 3필드 + 3번째=모델(haiku, 벤더 아님) → 역호환
assert_eq "quality-rev|reviewer-quality||haiku" "$(run_parse "quality-rev:reviewer-quality:haiku" "claude")" "P3 3필드 모델(역호환)"
# P4: 3필드 + 3번째=벤더(claude 화이트리스트) → 벤더, 모델 빈값(폴백 대상)
assert_eq "dev2|dev|claude|" "$(run_parse "dev2:dev:claude" "claude")" "P4 3필드 벤더"
# P5: 4필드 — 벤더+모델 명시
assert_eq "dev3|dev|claude|opus" "$(run_parse "dev3:dev:claude:opus" "claude")" "P5 4필드"

# P6: 모델 미지정 reviewer → vendor_default_model 폴백 (claude reviewer=opus)
out="$( set +u; HARNESS_ROOT="$HARNESS"; . "$HARNESS_BIN/lib.sh"; . "$HARNESS_BIN/vendors/claude.sh"
  vendor_default_model reviewer-quality )"
assert_eq "opus" "$out" "P6 claude reviewer 폴백=opus(품질우선)"
# P7: review-manager 도 opus (리뷰 총괄)
out="$( set +u; HARNESS_ROOT="$HARNESS"; . "$HARNESS_BIN/lib.sh"; . "$HARNESS_BIN/vendors/claude.sh"
  vendor_default_model review-manager )"
assert_eq "opus" "$out" "P7 claude review-manager 폴백=opus"

# P8: 5필드 이상 거부 — 모델에 콜론 잔존(필드 초과 오타) 사전 차단.
( set +u; HARNESS_ROOT="$HARNESS"; . "$HARNESS_BIN/lib.sh"
  eval "$(extract_parse_entry)"
  parse_entry "dev:dev:claude:opus:extra" ) >/dev/null 2>&1
assert_fail "$?" "P8 5필드 이상 거부"

# P9: 2필드 워커 + codex 벤더 폴백 (P9 수정 2026-05-30 회귀 — sonnet 400 방지).
#   parse_entry 가 빈 모델을 내면, 폴백 로직(awa-up L530)이 HARNESS_VENDOR 상속해
#   codex vendor_default_model=gpt-5.5 로 채워야 함(sonnet 아님). 폴백 로직을 직접 재현.
out="$( set +u; HARNESS_ROOT="$HARNESS"; HARNESS_VENDOR="codex"
  . "$HARNESS_BIN/lib.sh"
  eval "$(extract_parse_entry)"
  parse_entry "dev:dev"          # ENTRY_MODEL="" 기대
  if [ -z "$ENTRY_MODEL" ]; then
    . "$HARNESS_BIN/vendors/${ENTRY_VENDOR:-${HARNESS_VENDOR:-claude}}.sh"
    ENTRY_MODEL="$(vendor_default_model "$ENTRY_ROLE")"
  fi
  printf '%s' "$ENTRY_MODEL" )"
assert_eq "gpt-5.5" "$out" "P9 2필드 워커+codex → 폴백 gpt-5.5 (sonnet 400 방지)"
# P9b: 동일 2필드 워커 + claude → 폴백 sonnet (기존 동작 보존 확인).
out="$( set +u; HARNESS_ROOT="$HARNESS"; HARNESS_VENDOR="claude"
  . "$HARNESS_BIN/lib.sh"
  eval "$(extract_parse_entry)"
  parse_entry "dev:dev"
  if [ -z "$ENTRY_MODEL" ]; then
    . "$HARNESS_BIN/vendors/${ENTRY_VENDOR:-${HARNESS_VENDOR:-claude}}.sh"
    ENTRY_MODEL="$(vendor_default_model "$ENTRY_ROLE")"
  fi
  printf '%s' "$ENTRY_MODEL" )"
assert_eq "sonnet" "$out" "P9b 2필드 워커+claude → 폴백 sonnet (기존 동작 보존)"

test_summary
