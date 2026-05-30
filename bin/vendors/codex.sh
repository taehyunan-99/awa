#!/usr/bin/env bash
# codex 벤더 어댑터. source 전용. HARNESS_ROOT/PROJECT_ROOT export 가정.

# 부트 명령. codex 는 settings/sid 를 인자로 안 받음 — CODEX_HOME/config.toml + AGENTS.md 경유.
# plan 은 vendor_inject_role 책임이라 여기선 무시. sandbox 항상 켬(§3.3 필수).
# $1=model $2=settings_path(무시) $3=session_id(무시) $4=plan_file(무시)
vendor_boot_cmd() {
  local model="$1"
  printf 'CODEX_HOME="%s/.agent-harness/.codex" codex --cd "%s" -m %s -a never -s workspace-write' \
    "${PROJECT_ROOT}" "${PROJECT_ROOT}" "$model"
}

# trust 통과 + REPL ready. codex TUI 화면 문자열. $1=pane_id → rc 0/1.
# ★ ready 신호는 TUI '출력' 전용 문자열만 쓴다 — boot 명령 자체가 'codex ' 를 포함하므로
#   명령 echo 가 capture 에 잡혀 TUI 로드 전 오탐(ready 조기반환)하는 것을 차단(claude.sh 와 동형:
#   claude 도 'Claude Code v[0-9]' 같은 출력 전용 문자열만 사용). negative 도 'Error:'/'error:'
#   콜론 동반으로 좁혀 정상 출력 내 'error' 부분일치 오탐(false fail)을 방지.
vendor_wait_ready() {
  local s="$1" i dump
  for i in $(seq 1 60); do
    sleep 2
    dump="$(tmux capture-pane -t "$s" -p 2>/dev/null)"
    if printf '%s' "$dump" | grep -Eq 'Do you trust|trust the contents'; then
      tmux send-keys -t "$s" Enter
      continue
    fi
    if printf '%s' "$dump" | grep -qE 'Error:|error:|not authenticated|failed to start'; then
      return 1
    fi
    # ready — codex TUI 헤더/입력 프롬프트(출력 전용). 'codex ' 명령 토큰은 제외(echo 오탐 차단).
    if printf '%s' "$dump" | grep -qE 'OpenAI Codex|❯'; then
      return 0
    fi
  done
  return 1
}

# settings/hook 생성. codex config.toml + hooks.json(PreToolUse → codex-gate-bridge.sh).
# $1=role $2=entry_name(codex 미사용 — claude 와 시그니처만 맞춤).
# fail-safe: 디렉토리/파일 생성 실패 시 rc 1. echo CODEX_HOME 경로.
vendor_gen_settings() {
  local role="$1"
  local ch="${PROJECT_ROOT}/.agent-harness/.codex"
  mkdir -p "$ch" || { echo "오류: CODEX_HOME 생성 실패 ($ch)" >&2; return 1; }
  # hooks.json 은 jq 로 생성 — HARNESS_ROOT 에 따옴표/$/백슬래시가 있어도 JSON escape 안전.
  # (heredoc 직접 보간 시 특수문자가 JSON 을 파손할 수 있음 — 견고성.)
  jq -n --arg cmd "${HARNESS_ROOT}/bin/vendors/codex-gate-bridge.sh" \
    '{hooks: {PreToolUse: [{matcher: "*", command: $cmd}]}}' \
    > "$ch/hooks.json" || { echo "오류: hooks.json 쓰기 실패" >&2; return 1; }
  # effort 매칭(품질 우선): lead·reviewer=high, 그 외=medium.
  # model_reasoning_effort 허용값=minimal|low|medium|high|xhigh.
  local effort
  case "$role" in
    lead|LEAD|reviewer-*|review-manager) effort="high" ;;
    *) effort="medium" ;;
  esac
  cat > "$ch/config.toml" <<TOML || { echo "오류: config.toml 쓰기 실패" >&2; return 1; }
approval_policy = "never"
sandbox_mode = "workspace-write"
model_reasoning_effort = "$effort"
TOML
  export CODEX_HOME="$ch"
  printf '%s' "$ch"
}

# 역할 주입. codex 는 AGENTS.md(레포 루트) 자동 로드 → no-op.
# ★ 확정 plan 주입(claude --append-system-prompt-file 등가)은 이번 사이클 연기(§4 비목표).
# $1=pane_id $2=boot_file
vendor_inject_role() { :; }

# 역할별 기본 모델 — codex 는 모델명 고정(gpt-5.5), 급 차이는 effort 로(gen_settings).
# 미지정 시 codex 기본은 gpt-5.4 → gpt-5.5 명시. effort 매핑은 vendor_gen_settings 담당.
vendor_default_model() {
  echo "gpt-5.5"
}
