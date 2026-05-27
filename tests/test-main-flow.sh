#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"

# 격리: XDG 임시. 11차 리뷰 [CRIT-32]: 사용자 실 _SYMPHONY 보호 — 본 테스트는 _SYMPHONY 직접 조작 안 함.
# test-main-flow.sh 는 main.sh resume/attach/launch 의 *출력만* 검증 — _SYMPHONY 자체 kill 안 함.
export XDG_CONFIG_HOME="$(mktemp -d)"
trap '
  rm -rf "$XDG_CONFIG_HOME"
  tmux kill-session -t agenphony-mf-test-$$ 2>/dev/null
' EXIT

echo "[M1] mode=launch 단일 single + current cwd: 발진 명령 출력"
TMP="$(mktemp -d)"; ( cd "$TMP" && git init -q )
out="$(bash "$ROOT/bin/agenphony-main.sh" launch \
       --project "$TMP" --mode-launch single --preset default 2>&1)"
assert_contains "$out" "agenphony-up.sh" "M1a 발진 명령 출력"
assert_contains "$out" "default" "M1b preset 박힘"
assert_contains "$out" "$TMP" "M1c project 박힘"
assert_contains "$out" "AGPN_META" "M1d AGPN_META 줄"
assert_contains "$out" "mode=single" "M1e mode=single"
rm -rf "$TMP"

echo "[M2] mode=attach: attach 명령 출력 (live 검증 없이 그대로 인쇄)"
out="$(bash "$ROOT/bin/agenphony-main.sh" attach --session agenphony-foo 2>&1)"
assert_contains "$out" "tmux attach -t agenphony-foo" "M2 attach 명령"

echo "[M3] mode=resume: live 세션 목록 출력 (TSV 형태)"
S="agenphony-mf-test-$$"
TMP2="$(mktemp -d)"
tmux new-session -d -s "$S"
tmux set-option -t "$S" @agenphony-project "$TMP2" 2>/dev/null
out="$(bash "$ROOT/bin/agenphony-main.sh" resume 2>&1)"
assert_contains "$out" "session	project	label" "M3a TSV 헤더 출력"
assert_contains "$out" "$S" "M3b 세션명 출력"
tmux kill-session -t "$S" 2>/dev/null
rm -rf "$TMP2"

echo "[M3b] mode=resume 빈 케이스 — 헤더만 출력 (body 0 라인)"
# 외부 agenphony-* / _SYMPHONY 가 없을 때만 검증
live_check=$(tmux ls -F '#{session_name}' 2>/dev/null | grep -cE '^(agenphony-|_SYMPHONY$)' 2>/dev/null) || live_check=0
if [ "$live_check" = 0 ]; then
  out="$(bash "$ROOT/bin/agenphony-main.sh" resume 2>&1)"
  body_lines=$(printf '%s\n' "$out" | awk 'NR>1 && NF>0' | wc -l | tr -d ' ')
  assert_eq "0" "$body_lines" "M3b 빈 케이스 body 0"
  assert_contains "$out" "session	project	label" "M3b 헤더만"
else
  echo "  (SKIP M3b — 외부 agenphony-*/_SYMPHONY 존재)"
fi

echo "[M4] mode=launch --mode-launch multi: AGPN_META mode=multi-view"
TMP4="$(mktemp -d)"; ( cd "$TMP4" && git init -q )
out="$(bash "$ROOT/bin/agenphony-main.sh" launch \
       --project "$TMP4" --mode-launch multi --preset default 2>&1)"
assert_contains "$out" "mode=multi-view" "M4 multi-view 메타"
rm -rf "$TMP4"

echo "[M5] mode=launch --workers spec: --workers 박힘"
TMP5="$(mktemp -d)"; ( cd "$TMP5" && git init -q )
out="$(bash "$ROOT/bin/agenphony-main.sh" launch \
       --project "$TMP5" --mode-launch single --workers 'dev:dev:sonnet' 2>&1)"
assert_contains "$out" "--workers" "M5a --workers 박힘"
assert_contains "$out" "dev:dev:sonnet" "M5b spec 박힘"
rm -rf "$TMP5"

echo "[M6] mode=launch --plan: --plan 박힘"
TMP6="$(mktemp -d)"; ( cd "$TMP6" && git init -q )
PLAN6="$TMP6/p.md"; echo "plan" > "$PLAN6"
out="$(bash "$ROOT/bin/agenphony-main.sh" launch \
       --project "$TMP6" --mode-launch single --preset default --plan "$PLAN6" 2>&1)"
assert_contains "$out" "--plan" "M6 --plan 박힘"
rm -rf "$TMP6"

echo "[M7] 인자 검증: mode=launch --project 없으면 exit 1"
if bash "$ROOT/bin/agenphony-main.sh" launch --mode-launch single --preset default 2>/dev/null; then
  echo "  FAIL: M7 인자 부족 허용됨"; _TESTS_RUN=$((_TESTS_RUN+1)); _TESTS_FAIL=$((_TESTS_FAIL+1))
else
  echo "  ok: M7 인자 부족 거부"; _TESTS_RUN=$((_TESTS_RUN+1))
fi

echo "[M8] resolve-path: alias → path"
# bookmarks 에 alias 등록 (lib.sh 직접 사용)
source "$ROOT/bin/lib.sh"
mkdir -p /tmp/agpn-m8-real
bookmarks_upsert "/tmp/agpn-m8-real" "default" ""
bookmarks_set_alias 1 "m8alias"
out="$(bash "$ROOT/bin/agenphony-main.sh" resolve-path --input "m8alias" 2>&1)"
assert_eq "/tmp/agpn-m8-real" "$out" "M8a alias → path"
# path 직접 통과
out="$(bash "$ROOT/bin/agenphony-main.sh" resolve-path --input "/tmp/agpn-m8-real" 2>&1)"
assert_eq "/tmp/agpn-m8-real" "$out" "M8b path 직접"
# 실패 케이스
if bash "$ROOT/bin/agenphony-main.sh" resolve-path --input "/no-such-path-xyz" 2>/dev/null; then
  echo "  FAIL: M8c 실패 케이스 통과됨"; _TESTS_RUN=$((_TESTS_RUN+1)); _TESTS_FAIL=$((_TESTS_FAIL+1))
else
  echo "  ok: M8c 실패 거부"; _TESTS_RUN=$((_TESTS_RUN+1))
fi
rm -rf /tmp/agpn-m8-real

test_summary
