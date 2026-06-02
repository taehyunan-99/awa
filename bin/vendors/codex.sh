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
    # ★ ready 체크 최우선 (실부트 스모크 2026-05-30): ready 화면(OpenAI Codex 헤더)에
    #   도달하면 업데이트 알림 박스가 위쪽에 잔상으로 남아도(Update available 문자열 공존)
    #   즉시 성공 반환. 아래 update 분기보다 먼저 둬야 — 안 그러면 ready 후에도 잔상이
    #   매 루프 Down+Enter 를 재송신해 입력창을 오염시키고 ready 진입을 방해(실측 행).
    # ★ codex 0.130 라이브 발견(2026-06-02): 0.130 ready 화면엔 'OpenAI Codex' 헤더도
    #   '❯' 도 없고 모델 상태줄 'gpt-5.5 high · <path>' 만 뜬다(입력 프롬프트는 '›' U+203A).
    #   기존 두 패턴 다 매칭 실패 → codex pane 마다 60×2s=120s 풀 폴링 → 부트 5분+ 지연.
    #   해소: ready 패턴에 'gpt-N.N <effort> ·' 상태줄 추가(REPL 완전 기동 후에만 출력,
    #   명령 echo 엔 안 잡혀 안전). 구버전 'OpenAI Codex|❯' 는 호환 유지.
    if printf '%s' "$dump" | grep -qE 'OpenAI Codex|❯|gpt-[0-9.]+ (low|medium|high) ·'; then
      # P7 수정(2026-05-30 codex 1사이클 e2e): ready 도달했으나 Update 박스가 잔상으로
      #   공존하면, 직후 send_prompt 의 텍스트+Enter 중 Enter 가 업데이트 선택지로 새거나
      #   codex 가 입력을 무시 → 부트 프롬프트 미전송(전 pane 멈춤, 실측). send_prompt 는
      #   bootstrap_pane(=이 함수) 이후라 아직 부트 텍스트 전이므로, 여기서 박스를 Skip
      #   (Down→2.Skip + Enter)으로 닫아 깨끗한 입력 상태 확보 후 return. 박스 없으면
      #   순수 ready 라 건드리지 않음(❯ 입력 프롬프트에 Down+Enter 는 위험). 루프 아닌 1회.
      if printf '%s' "$dump" | grep -Eq 'Update available|Update now'; then
        tmux send-keys -t "$s" Down
        tmux send-keys -t "$s" Enter
        sleep 1
      fi
      return 0
    fi
    if printf '%s' "$dump" | grep -Eq 'Do you trust|trust the contents'; then
      tmux send-keys -t "$s" Enter
      continue
    fi
    # ★ 업데이트 프롬프트 Skip (실부트 스모크 2026-05-30): 신버전 출시 시 codex 가
    #   "Update available! / 1.Update now / 2.Skip" 선택 프롬프트를 띄운다(간헐적·버전 의존).
    #   기본 하이라이트=1(Update now) — Enter 시 npm install 실행돼 부트가 길어지거나 깨진다.
    #   Down 1회로 2.Skip 이동 후 Enter(실측: Down→'› 2.Skip' 이동 확인). update 박스가
    #   ready 와 공존하면 위 ready 분기가 이미 잡았으므로, 여기 오는 건 순수 업데이트 프롬프트.
    if printf '%s' "$dump" | grep -Eq 'Update available|Update now'; then
      tmux send-keys -t "$s" Down
      tmux send-keys -t "$s" Enter
      continue
    fi
    if printf '%s' "$dump" | grep -qE 'Error:|error:|not authenticated|failed to start'; then
      return 1
    fi
  done
  return 1
}

# settings/hook 생성. codex config.toml 의 [[hooks.PreToolUse]] + trusted_hash(P12) → gate-bridge.
# $1=role $2=entry_name(codex 미사용 — claude 와 시그니처만 맞춤).
# fail-safe: 디렉토리/파일 생성 실패 시 rc 1. echo CODEX_HOME 경로.
vendor_gen_settings() {
  local role="$1"
  local ch="${PROJECT_ROOT}/.agent-harness/.codex"
  mkdir -p "$ch" || { echo "오류: CODEX_HOME 생성 실패 ($ch)" >&2; return 1; }
  # ★ 인증 전파 (실부트 스모크 2026-05-30 발견): 어댑터가 CODEX_HOME 을 격리본으로
  #   override 하면 사용자의 ~/.codex/auth.json 이 안 보여 codex 가 로그인 화면을 띄우고
  #   vendor_wait_ready 가 ready/error 어느 패턴도 못 잡아 120s timeout → 부트 행.
  #   원본 auth.json 을 격리본에 symlink 해 사용자 로그인을 워커가 상속(codex 표준 UX).
  #   소스: $CODEX_HOME(기존 env) 우선, 없으면 ~/.codex. 격리본 자기 자신은 제외(무한참조).
  local _auth_src="${CODEX_HOME:-$HOME/.codex}/auth.json"
  if [ "$_auth_src" != "$ch/auth.json" ] && [ -f "$_auth_src" ] && [ ! -e "$ch/auth.json" ]; then
    ln -sf "$_auth_src" "$ch/auth.json" 2>/dev/null \
      || cp "$_auth_src" "$ch/auth.json" 2>/dev/null \
      || echo "경고: auth.json 전파 실패 — codex 워커가 로그인 화면에 멈출 수 있음" >&2
  fi
  # effort 매칭(품질 우선): lead·reviewer=high, 그 외=medium.
  # model_reasoning_effort 허용값=minimal|low|medium|high|xhigh.
  local effort
  case "$role" in
    lead|LEAD|reviewer-*|review-manager) effort="high" ;;
    *) effort="medium" ;;
  esac
  # ★ PreToolUse 권한 게이트 등록 (P12 수정 2026-05-31). 기존엔 hooks.json 을 만들었으나
  #   codex 는 그 파일을 로드조차 안 한다(config.toml 의 [hooks] 인라인 구조체 HooksToml 경유).
  #   게다가 인라인 등록만으론 user-config hook 이 trust_status=Untrusted → discovery 만 되고
  #   실행 안 됨. [hooks.state] 에 trusted_hash 가 매칭돼야 발화. 이게 없어서 codex 워커의
  #   권한 게이트(danger-check 포함)가 지금까지 한 번도 안 걸렸다(rm -rf 등 위험명령 우회 가능).
  #   → config.toml 에 [[hooks.PreToolUse]] + [hooks.state] trusted_hash 동적 계산해 등록.
  local gate_cmd="${HARNESS_ROOT}/bin/vendors/codex-gate-bridge.sh"
  # state-map 키는 config.toml 의 realpath(canonical) 경로여야 함(codex 가 sourcePath 를
  #   canonicalize — macOS /tmp→/private/tmp). 잘못된 경로면 state 조회 실패→Untrusted→미발화.
  local cfg_real
  cfg_real="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$ch/config.toml" 2>/dev/null)" \
    || cfg_real="$ch/config.toml"
  # trusted_hash = sha256: + sha256hex(canonical-json). codex currentHash 와 비트일치 검증된 형식
  #   (대상: event_name/hooks[async,command,timeout,type]/matcher, 키 재귀정렬, separators 없음).
  local thash
  thash="$(GATE_CMD="$gate_cmd" python3 - <<'PY' 2>/dev/null
import os,json,hashlib
cmd=os.environ["GATE_CMD"]
obj={"event_name":"pre_tool_use",
     "hooks":[{"async":False,"command":cmd,"timeout":600,"type":"command"}],
     "matcher":"*"}
def canon(o):
    if isinstance(o,dict): return {k:canon(o[k]) for k in sorted(o)}
    if isinstance(o,list): return [canon(x) for x in o]
    return o
s=json.dumps(canon(obj),separators=(',',':'))
print("sha256:"+hashlib.sha256(s.encode()).hexdigest())
PY
)"
  # ★ trust 프롬프트 사전 제거(2026-05-30): [projects.*] trust_level=trusted 로 "Do you trust" 차단.
  # config.toml 작성 — heredoc 보간(effort/PROJECT_ROOT/gate_cmd/cfg_real/thash).
  #   경로에 따옴표가 없다는 전제(PROJECT_ROOT 는 awa-up 이 _validate_path_chars 로 사전검증).
  if [ -n "$thash" ]; then
    cat > "$ch/config.toml" <<TOML || { echo "오류: config.toml 쓰기 실패" >&2; return 1; }
approval_policy = "never"
sandbox_mode = "workspace-write"
model_reasoning_effort = "$effort"

[projects."${PROJECT_ROOT}"]
trust_level = "trusted"

[[hooks.PreToolUse]]
matcher = "*"

[[hooks.PreToolUse.hooks]]
type = "command"
command = "${gate_cmd}"

[hooks.state."${cfg_real}:pre_tool_use:0:0"]
enabled = true
trusted_hash = "${thash}"
TOML
  else
    # 해시 계산 실패(python3 부재 등) — 게이트 없이 부트하면 위험명령 우회 위험.
    #   fail-loud: 경고 후에도 hook 미등록 config 로 진행(부트 자체는 막지 않음, 사용자 인지).
    echo "경고: trusted_hash 계산 실패 — codex 권한 게이트 미등록(위험명령 우회 가능). python3 확인 필요." >&2
    cat > "$ch/config.toml" <<TOML || { echo "오류: config.toml 쓰기 실패" >&2; return 1; }
approval_policy = "never"
sandbox_mode = "workspace-write"
model_reasoning_effort = "$effort"

[projects."${PROJECT_ROOT}"]
trust_level = "trusted"
TOML
  fi
  export CODEX_HOME="$ch"
  printf '%s' "$ch"
}

# 역할 주입. codex 는 AGENTS.md(레포 루트) 자동 로드 → no-op.
# $1=pane_id $2=boot_file
vendor_inject_role() { :; }

# LEAD 부트 입력에 덧붙일 plan 지시문 (P10 수정 2026-05-30). codex CLI 엔
# --append-system-prompt-file 이 없어(─ [PROMPT] 위치인자+config+AGENTS.md 자동로드만)
# plan 을 시스템 컨텍스트로 못 받는다 → LEAD 가 plan 을 능동 탐색해야 하나 비결정적이었음
# (첫 부트는 rg 로 찾아 성공, 재부트는 헤더 못 찾아 BLOCKED). 해소: plan 파일 절대경로를
# 부트 입력에 명시해 LEAD 가 반드시 Read 하게 → 결정적. plan 없으면 빈 출력.
# $1=plan_file → echo directive.
vendor_lead_plan_directive() {
  local plan="${1:-}"
  [ -n "$plan" ] || return 0
  printf '확정 plan 파일 `%s` 를 먼저 Read 로 읽어라 — 그 내용이 이번 가동의 확정 plan 이다(시스템 컨텍스트엔 없으니 반드시 직접 읽어라). ' "$plan"
}

# 역할별 기본 모델 — codex 는 모델명 고정(gpt-5.5), 급 차이는 effort 로(gen_settings).
# 미지정 시 codex 기본은 gpt-5.4 → gpt-5.5 명시. effort 매핑은 vendor_gen_settings 담당.
vendor_default_model() {
  echo "gpt-5.5"
}
