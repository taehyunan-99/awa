#!/usr/bin/env bash
# 상태 3분할 — _state_config_dir 헬퍼 + stats/blocklist XDG 이전 검증
set -u
cd "$(dirname "$0")"
source ./assert.sh
source ./harness-paths.sh
ROOT="$(cd .. && pwd)"

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

# S1 — _state_config_dir 가 XDG_CONFIG_HOME/awa 를 반환
out="$(XDG_CONFIG_HOME="$TMPDIR/xdg" bash -c '
  source "'"$HARNESS_BIN"'/lib.sh"
  _state_config_dir
')"
assert_eq "$TMPDIR/xdg/awa" "$out" "S1 _state_config_dir = XDG/awa"

# S2 — XDG 미설정 시 ~/.config/awa 폴백 (HOME override 로 검증)
out="$(env -u XDG_CONFIG_HOME HOME="$TMPDIR/home" bash -c '
  source "'"$HARNESS_BIN"'/lib.sh"
  _state_config_dir
')"
assert_eq "$TMPDIR/home/.config/awa" "$out" "S2 XDG 미설정 → HOME/.config/awa"

# S3 — blocklist append(never) 후 contains 가 같은 베이스를 읽어 매치 (deny-bounded 정합)
#   _state_config_dir 가 시드를 자동 보장하므로 수동 시드 불필요 (헬퍼 멱등성 검증 겸).
XDG_CONFIG_HOME="$TMPDIR/xdg" HARNESS_PROJECT="$TMPDIR/proj" bash -c '
  source "'"$HARNESS_BIN"'/lib.sh"
  confirm_allow_yaml "Bash(neverpat:*)" "never"
'
match="$(XDG_CONFIG_HOME="$TMPDIR/xdg" bash -c '
  source "'"$HARNESS_BIN"'/lib.sh"
  blocklist_contains "Bash(neverpat:*)" && echo MATCH || echo NOMATCH
')"
assert_eq "MATCH" "$match" "S3 never→append 후 contains 매치 (읽기·쓰기 단일베이스)"

# S3b — 더 험한 메타문자 패턴(슬래시·공백·점·괄호·별표)도 contains 매치 (grep -qxF 회귀 가드)
XDG_CONFIG_HOME="$TMPDIR/xdgb" HARNESS_PROJECT="$TMPDIR/projb" bash -c '
  source "'"$HARNESS_BIN"'/lib.sh"
  confirm_allow_yaml "Bash(rm -rf /tmp/x.*:*)" "never"
'
matchb="$(XDG_CONFIG_HOME="$TMPDIR/xdgb" bash -c '
  source "'"$HARNESS_BIN"'/lib.sh"
  blocklist_contains "Bash(rm -rf /tmp/x.*:*)" && echo MATCH || echo NOMATCH
')"
assert_eq "MATCH" "$matchb" "S3b 험한 메타패턴(슬래시/점/별표) contains 매치"

# S4 — stats 가 HARNESS_ROOT/config 가 아닌 XDG 에 쓰임 (본체 비오염)
seeded="$HARNESS_CONFIG/orch-auto-allow-stats.yaml"
before="$(grep -c . "$seeded" 2>/dev/null || echo 0)"
XDG_CONFIG_HOME="$TMPDIR/xdg2" HARNESS_PROJECT="$TMPDIR/proj2" bash -c '
  source "'"$HARNESS_BIN"'/lib.sh"
  bump_stats_counter "Bash(xpat:*)" "accepted"
'
after="$(grep -c . "$seeded" 2>/dev/null || echo 0)"
assert_eq "$before" "$after" "S4 stats 쓰기가 본체 config 시드 비오염"

# S5 — 시드 자동 보장: 빈 XDG 에서 _state_config_dir 호출만으로 stats/blocklist 생성
XDG_CONFIG_HOME="$TMPDIR/xdg3" bash -c '
  source "'"$HARNESS_BIN"'/lib.sh"
  _state_config_dir >/dev/null
'
assert_eq "1" "$([ -f "$TMPDIR/xdg3/awa/orch-auto-allow-stats.yaml" ] && [ -f "$TMPDIR/xdg3/awa/orch-auto-allow-blocklist.yaml" ] && echo 1 || echo 0)" "S5 시드 자동 보장"

test_summary
