#!/usr/bin/env bash
# vendor_gen_settings rc 1 → 워커 가동 거부(fail-safe). 어댑터 계약 검증.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT/tests/assert.sh"
TMPDIR_F="$(mktemp -d)"; trap 'rm -rf "$TMPDIR_F"' EXIT

# F1: codex gen_settings 가 쓰기 불가 CODEX_HOME 경로에서 rc1.
( set +u
  HARNESS_ROOT="$ROOT"; PROJECT_ROOT="/dev/null/awa-nodir"
  . "$ROOT/bin/vendors/codex.sh"
  vendor_gen_settings "dev" >/dev/null 2>&1 )
assert_fail "$?" "F1 codex gen_settings rc1 on 쓰기불가"

# F2: claude gen_settings 도 템플릿 부재 시 rc1 (generate_worker_settings 계약).
# lib.sh L7 이 source 시 HARNESS_ROOT 를 실제 루트로 재계산하므로, 템플릿 부재 상황은
# source *이후* HARNESS_ROOT 를 빈 디렉토리로 덮어써 재현한다(L7 우회).
( set +u
  PROJECT_ROOT="$TMPDIR_F/proj"; mkdir -p "$PROJECT_ROOT"
  . "$ROOT/bin/lib.sh"; . "$ROOT/bin/vendors/claude.sh"
  HARNESS_ROOT="$TMPDIR_F/no-templates"
  vendor_gen_settings "dev" >/dev/null 2>&1 )
assert_fail "$?" "F2 claude gen_settings rc1 on 템플릿부재"

# F3: codex lead → config.toml effort=high + model_reasoning_effort 키.
( set +u; HARNESS_ROOT="$ROOT"; PROJECT_ROOT="$TMPDIR_F/cx-lead"; mkdir -p "$PROJECT_ROOT"
  . "$ROOT/bin/vendors/codex.sh"; vendor_gen_settings "orch" "ORCH" >/dev/null 2>&1 )
cfg="$TMPDIR_F/cx-lead/.agent-harness/.codex/config.toml"
assert_contains "$(cat "$cfg" 2>/dev/null)" 'model_reasoning_effort = "high"' "F3 codex lead effort=high"

# F4: codex dev → effort=medium. reviewer 도 high(품질 우선).
( set +u; HARNESS_ROOT="$ROOT"; PROJECT_ROOT="$TMPDIR_F/cx-dev"; mkdir -p "$PROJECT_ROOT"
  . "$ROOT/bin/vendors/codex.sh"; vendor_gen_settings "dev" "d" >/dev/null 2>&1 )
assert_contains "$(cat "$TMPDIR_F/cx-dev/.agent-harness/.codex/config.toml" 2>/dev/null)" \
  'model_reasoning_effort = "medium"' "F4 codex dev effort=medium"
( set +u; HARNESS_ROOT="$ROOT"; PROJECT_ROOT="$TMPDIR_F/cx-rev"; mkdir -p "$PROJECT_ROOT"
  . "$ROOT/bin/vendors/codex.sh"; vendor_gen_settings "reviewer-quality" "r" >/dev/null 2>&1 )
assert_contains "$(cat "$TMPDIR_F/cx-rev/.agent-harness/.codex/config.toml" 2>/dev/null)" \
  'model_reasoning_effort = "high"' "F4b codex reviewer effort=high(품질우선)"

# F5: ready 오탐 차단 — boot 명령 자체가 wait_ready 의 ready 패턴(OpenAI Codex|❯)을 포함하면
#   pane 의 명령 echo 가 TUI 로드 전 ready 로 오판된다. boot_cmd 가 ready 패턴 미포함이어야 함.
bootcmd="$( set +u; PROJECT_ROOT="$TMPDIR_F/p"; . "$ROOT/bin/vendors/codex.sh"
  vendor_boot_cmd "gpt-5.5" "" "" "" )"
printf '%s' "$bootcmd" | grep -qE 'OpenAI Codex|❯'
assert_fail "$?" "F5 codex boot 명령이 ready 패턴 미포함(echo 오탐 차단)"

# F6: PreToolUse 게이트가 config.toml 의 [[hooks.PreToolUse]] + [hooks.state] trusted_hash 로
#   등록되는지 (P12 2026-05-31: codex 는 hooks.json 을 안 읽음 → config.toml 인라인 + trust 필수).
#   이게 없으면 codex 워커 권한 게이트(danger-check 포함)가 미발화 → 위험명령 우회.
if command -v python3 >/dev/null 2>&1; then
  ( set +u; HARNESS_ROOT="$ROOT"; PROJECT_ROOT="$TMPDIR_F/cx-hook"
    mkdir -p "$PROJECT_ROOT"; . "$ROOT/bin/vendors/codex.sh"
    vendor_gen_settings "dev" "d" >/dev/null 2>&1 )
  cfg="$(cat "$TMPDIR_F/cx-hook/.agent-harness/.codex/config.toml" 2>/dev/null)"
  assert_contains "$cfg" "[[hooks.PreToolUse]]" "F6 config.toml 에 PreToolUse hook 등록(P12)"
  assert_contains "$cfg" "codex-gate-bridge.sh" "F6b hook command=gate-bridge"
  assert_contains "$cfg" "trusted_hash" "F6c [hooks.state] trusted_hash(미발화 방지)"
  # hooks.json 은 더 이상 만들지 않는다(codex 가 안 읽음) — 잔존하면 혼란.
  assert_eq "1" "$([ -f "$TMPDIR_F/cx-hook/.agent-harness/.codex/hooks.json" ] && echo 0 || echo 1)" \
    "F6d hooks.json 미생성(P12 — codex 가 로드 안 함)"
else
  echo "  SKIP: python3 미설치 — F6 생략"
fi

# F7: gate-bridge 가 codex 가 안 주는 HARNESS_ROOT/PROJECT_ROOT env 없이도 동작 (P14 2026-05-31).
#   codex TUI 는 hook 실행 시 이 env 를 주지 않는다 → 기존 `${PROJECT_ROOT:?}` unbound 즉사 →
#   codex 가 hook 실패(exit 1)를 "통과"로 처리 → 위험명령 우회(deny-bounded 무력화, 실측).
#   해소: bridge 가 HARNESS_ROOT 를 자기위치(BASH_SOURCE)에서, PROJECT_ROOT 를 stdin cwd 에서 도출.
BR="$ROOT/bin/vendors/codex-gate-bridge.sh"
# F7a: env 전혀 없이(HARNESS_ROOT/PROJECT_ROOT 미설정) rm -rf → deny (danger). HOME/PATH 만 유지.
out7a="$(env -i PATH="$PATH" HOME="$HOME" GATE_SKIP_WAIT=1 bash "$BR" \
  <<<'{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"rm -rf /"},"cwd":"'"$TMPDIR_F"'"}' 2>/dev/null)"
assert_contains "$out7a" '"permissionDecision":"deny"' "F7a bridge env없이 rm -rf deny(자기도출+danger)"
# F7b: cwd 누락(PROJECT_ROOT 도출 불가) → fail-closed deny (hook 크래시 시 통과 금지).
out7b="$(env -i PATH="$PATH" HOME="$HOME" GATE_SKIP_WAIT=1 bash "$BR" \
  <<<'{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"echo x"}}' 2>/dev/null)"
assert_contains "$out7b" '"permissionDecision":"deny"' "F7b bridge cwd없으면 fail-closed deny"

# ★ F8/F9 셋업 (회귀 봉쇄 2026-06-03): bridge 는 stdin cwd 를 PROJECT_ROOT 로 도출하고
#   permission-gate 가 HARNESS_PROJECT=PROJECT_ROOT 로 고정(dcb4a18 격리 정확성) → auto-allow
#   카탈로그를 ${PROJECT_ROOT}/config/orch-auto-allow.yaml 에서 읽는다. 운영에서는 awa-up Step
#   (L285~)이 이 yaml 을 PROJECT/config 로 설치하므로 read-only(sed -n/echo) 가 auto-allow.
#   테스트도 그 설치를 재현해야 sed -n/echo 가 gray 로 안 떨어진다(미설치 시 lookup rc1 → gray
#   → timeout deny → F8a/F9a FAIL). 이전엔 lib.sh L27 이 HARNESS_PROJECT 부재로 PROJECT_ROOT
#   를 git toplevel(하니스 본체)로 덮어써 우연히 통과했을 뿐 — 격리 환경 의도와 어긋난 의존.
mkdir -p "$TMPDIR_F/config"
cp "$ROOT/config/orch-auto-allow.yaml" "$TMPDIR_F/config/orch-auto-allow.yaml"

# F8: sed -n(읽기) 자동허용 + sed -i(수정) 게이트 분리 (P15 2026-05-31). codex 는 파일을
#   sed -n/cat 으로 읽는다(claude 의 Read 도구와 다름) → sed 가 read-only 화이트리스트에 없으면
#   부트 파일 읽기조차 매번 게이트에 막혀 워커가 일을 못 시작. sed -n 만 허용(sed -i 는 게이트).
#   ★ P16(아래): allow 는 codex 0.130 에서 빈출력+exit0 이 통과신호(allow JSON 은 거부됨).
#   따라서 sed -n(allow)→빈출력, sed -i(deny)→JSON deny 로 검증한다.
out8a="$(env -i PATH="$PATH" HOME="$HOME" GATE_SKIP_WAIT=1 bash "$BR" \
  <<<'{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"sed -n 1,99p f.md"},"cwd":"'"$TMPDIR_F"'"}' 2>/dev/null)"
assert_eq "" "$out8a" "F8a sed -n 읽기 allow=빈출력(codex 통과신호, P16)"
out8b="$(env -i PATH="$PATH" HOME="$HOME" GATE_SKIP_WAIT=1 bash "$BR" \
  <<<'{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"sed -i s/a/b/ f.md"},"cwd":"'"$TMPDIR_F"'"}' 2>/dev/null)"
assert_contains "$out8b" '"permissionDecision":"deny"' "F8b sed -i 수정은 게이트(미응답 deny)"

# F9: codex 0.130 은 permissionDecision:"allow" 를 unsupported 로 거부 (P16 2026-05-31).
#   → bridge 는 allow 시 *빈 출력 + exit 0*(통과), deny 시에만 JSON. allow JSON 을 내면
#   codex 가 hook failed 처리 → 워커가 read-only 명령조차 못 하고 멈춤(실측 LEAD 4분+ 행).
out9a="$(env -i PATH="$PATH" HOME="$HOME" GATE_SKIP_WAIT=1 bash "$BR" \
  <<<'{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"echo hi"},"cwd":"'"$TMPDIR_F"'"}' 2>/dev/null)"
rc9a=$?
assert_eq "" "$out9a" "F9a allow(echo) 빈출력(codex unsupported:allow 회피)"
assert_eq "0" "$rc9a" "F9b allow exit 0(통과신호)"
# allow 출력에 'allow' 문자열이 절대 없어야 함(있으면 codex 거부 재발).
case "$out9a" in *allow*) assert_eq "no-allow-token" "found-allow-token" "F9c allow JSON 미출력";; *) :;; esac

test_summary
