#!/usr/bin/env bash
# 핵심 검증 — 권한 학습 생성 → 코드 재설치(HARNESS_ROOT 교체 모의) → 학습 보존
set -u
cd "$(dirname "$0")"
source ./assert.sh
source ./harness-paths.sh
ROOT="$(cd .. && pwd)"

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT
XDG="$TMPDIR/xdg"

# R1 — never 결정으로 blocklist 학습 생성 (XDG 에 영속)
XDG_CONFIG_HOME="$XDG" HARNESS_PROJECT="$TMPDIR/proj" bash -c '
  source "'"$ROOT"'/bin/lib.sh"
  mkdir -p "$(_state_config_dir)"
  printf "patterns:\n" > "$(_state_config_dir)/orch-auto-allow-blocklist.yaml"
  printf "# stats\npatterns:\n" > "$(_state_config_dir)/orch-auto-allow-stats.yaml"
  confirm_allow_yaml "Bash(persistpat:*)" "never"
'
assert_eq "1" "$([ -f "$XDG/awa/orch-auto-allow-blocklist.yaml" ] && echo 1 || echo 0)" "R1 blocklist XDG 에 생성"

# R2 — "재설치" 모의: HARNESS_ROOT 가 가리키는 코드를 새 위치로 (XDG 는 불변)
#   재설치는 코드 디렉토리만 교체. XDG 학습은 안 건드림.
NEW_HARNESS="$TMPDIR/new-harness"
mkdir -p "$NEW_HARNESS/bin" "$NEW_HARNESS/config"
cp "$HARNESS_BIN/lib.sh" "$NEW_HARNESS/bin/"
# lib.sh 가 source 하는 의존 스크립트도 복사(같은 _LIB_DIR/HARNESS_ROOT 기준) — danger-check,
#   spec-parse(lib.sh 말미 무조건 source). 재설치=코드 디렉토리 전체 교체 모의.
cp "$HARNESS_BIN/danger-check.sh" "$NEW_HARNESS/bin/" 2>/dev/null || true
cp "$HARNESS_BIN/spec-parse.sh" "$NEW_HARNESS/bin/" 2>/dev/null || true

# R3 — 새 코드 위치에서 같은 XDG 를 보고 학습이 보존됐는지 (contains 매치)
match="$(XDG_CONFIG_HOME="$XDG" bash -c '
  source "'"$NEW_HARNESS"'/bin/lib.sh"
  blocklist_contains "Bash(persistpat:*)" && echo MATCH || echo NOMATCH
')"
assert_eq "MATCH" "$match" "R3 재설치(코드 교체) 후 학습 보존 — XDG 불변"

test_summary
