#!/usr/bin/env bash
# P1: claude allow 패턴 형식 (colon-asterisk vs space-glob) 실측.
# P6(b): add_to_allow 후 claude 가 settings 재읽기(reload) 하는지 관찰.
#   ※ P6(a) hook allow vs settings.deny 는 4차 docs 로 확정 종료 (deny > hook allow, probe 불요).
set -uo pipefail
[ "${RUN_INTEGRATION:-0}" = "1" ] || { echo "SKIP (RUN_INTEGRATION 미설정)"; exit 0; }
cd "$(dirname "$0")/../.."
ROOT="$(pwd)"

# REPL 준비 대기 — ★ 확정 신호로 판정 (probe-hook-merge 교훈: '❯' 단독은 부팅 중 빈
#   입력선을 ready 로 오인 → 지시가 REPL 에 안 들어가 위양성). 상태줄/박스 신호로 강화.
#   인자: 세션명. trust 프롬프트 자동 통과.
wait_repl() {
  local ses="$1" d
  for _ in $(seq 1 70); do
    sleep 2
    d="$(tmux capture-pane -t "$ses" -p 2>/dev/null)"
    printf '%s' "$d" | grep -q 'trust this folder' && { tmux send-keys -t "$ses" Enter; continue; }
    printf '%s' "$d" | grep -qE 'accept edits on|bypass permissions|for shortcuts|esc to interrupt|Welcome back' && { sleep 3; return 0; }
  done
  return 1
}

# P1: settings.allow 에 colon-asterisk 패턴 Bash(echo:*) 넣고 echo 호출이 ask 없이 통과하는지.
#     통과하면 colon-asterisk 가 claude 와 정합 (matrix_lookup 패턴 형식 확정).
PROBE_DIR="$(mktemp -d)"
SES="probeP1_$$"
mkdir -p "$PROBE_DIR/.claude"
cat > "$PROBE_DIR/.claude/settings.json" <<'JSON'
{ "permissions": { "allow": ["Bash(echo:*)"] } }
JSON
tmux kill-session -t "$SES" 2>/dev/null || true
tmux new-session -d -s "$SES" -c "$PROBE_DIR" -x 200 -y 50
tmux send-keys -t "$SES" "cd '$PROBE_DIR' && claude --model claude-haiku-4-5-20251001 --settings '$PROBE_DIR/.claude/settings.json' --session-id $(uuidgen)" Enter
wait_repl "$SES" || { echo "P1 RESULT: ✗ REPL 미준비 (위양성 방지 차원 SKIP)"; tmux kill-session -t "$SES" 2>/dev/null; rm -rf "$PROBE_DIR"; exit 1; }
tmux send-keys -t "$SES" "run exactly: echo COLON_ASTERISK_OK" Enter
sleep 10
out="$(tmux capture-pane -t "$SES" -p)"
if echo "$out" | grep -q 'COLON_ASTERISK_OK' && ! echo "$out" | grep -qi 'permission\|allow this'; then
  echo "P1 RESULT: colon-asterisk Bash(echo:*) 가 claude 와 정합 (ask 없이 통과)"
else
  echo "P1 RESULT: colon-asterisk 미정합 — space-glob 등 다른 형식 필요. 화면:"
  echo "$out" | tail -15
fi
tmux kill-session -t "$SES" 2>/dev/null || true
rm -rf "$PROBE_DIR"
echo "(P6 reload 는 Task 12 probe 의 E3 학습 후 동일명령 재호출로 관찰 — 별도 수동 확인)"

# ============================================================================
# P7 (★ blocker — 3차 리뷰): lead 의 `tmux wait-for -S <chan>` 이 lead settings 의
#   `Bash(tmux wait-for:*)` allow 패턴에 매칭돼 *ask 없이* 실행되는지 실측.
#   막히면 lead 가 매 wake 마다 권한 ask 에 걸려 → 게이트 전체 deadlock.
#   `-S` 플래그가 prefix 매칭(`tmux wait-for` 로 시작)에 포함되는지가 관건.
# ============================================================================
# 주의: 우리 실제 lead 는 `Bash(tmux:*)` 넓은 allow 를 쓴다(deadlock 원천 차단, Task5 결정).
#   이 P7 은 *좁은* 패턴 `Bash(tmux wait-for:*)` 가 -S 플래그에서 깨지는지 확인용 — 깨지면
#   넓은 패턴 선택이 옳았음을 입증, 안 깨지면 좁은 패턴도 가능했다는 참고 정보.
P7_DIR="$(mktemp -d)"; P7_SES="probeP7_$$"
mkdir -p "$P7_DIR/.claude"
cat > "$P7_DIR/.claude/settings.json" <<'JSON'
{ "permissions": { "allow": ["Bash(tmux wait-for:*)"] } }
JSON
tmux kill-session -t "$P7_SES" 2>/dev/null || true
tmux new-session -d -s "$P7_SES" -c "$P7_DIR" -x 200 -y 50
tmux send-keys -t "$P7_SES" "cd '$P7_DIR' && claude --model claude-haiku-4-5-20251001 --settings '$P7_DIR/.claude/settings.json' --session-id $(uuidgen)" Enter
wait_repl "$P7_SES" || { echo "P7 RESULT: ✗ REPL 미준비 (위양성 방지 차원 SKIP)"; tmux kill-session -t "$P7_SES" 2>/dev/null; rm -rf "$P7_DIR"; exit 1; }
# 워커에게 wait-for -S 호출 지시 (채널은 즉시 반환되도록 미리 -S 안 함 → 대기자 없는 채널에 -S = 즉시 반환)
tmux send-keys -t "$P7_SES" "run exactly: tmux wait-for -S harness-gate-probe7test" Enter
sleep 10
out="$(tmux capture-pane -t "$P7_SES" -p)"
if ! echo "$out" | grep -qi 'permission\|allow this\|requires'; then
  echo "P7 RESULT: ✓ 'tmux wait-for -S' 가 Bash(tmux wait-for:*) 로 ask 없이 실행 (게이트 wake 정상)"
else
  echo "P7 RESULT: ✗ '-S' 플래그가 패턴 매칭 깨뜨림 — lead settings 에 더 넓은 allow 필요. 화면:"
  echo "$out" | tail -15
  echo "  → 대응: lead 템플릿 allow 를 'Bash(tmux:*)' 로 넓히거나 'Bash(tmux wait-for -S:*)' 명시 추가"
fi
tmux kill-session -t "$P7_SES" 2>/dev/null || true
rm -rf "$P7_DIR"

# ============================================================================
# P8 (3차+4차 리뷰): ① 서브에이전트 실제 도구명 확정 (4차 docs: 공식 목록은 `Agent`,
#   `Task` 없음 — 실측으로 우리 버전 확정), ② Agent/WebFetch 가 matcher 에 잡혀 게이트
#   (gray) 발화하는지. 워커가 서브에이전트 스폰/웹페치 시도 → permission-gate 가
#   pending-ask 생성하면 게이트 성공 (무게이트 우회 차단 확인).
#   ★ 도구명 확정 절차: pending-ask .json 의 `.tool` 필드 또는 permission-gate.log 의
#     도구명을 읽어 `Agent` 인지 확인. 만약 `Task`(또는 다른 이름)면 settings 템플릿 matcher 에
#     그 이름을 추가하는 후속 정정 (Task 5 의 matcher 문자열). docs 가 Agent 라 했으나 버전차 대비.
# ============================================================================
P8_DIR="$(mktemp -d)"; P8_SES="probeP8_$$"
export HARNESS_PROJECT="$P8_DIR" PROJECT_ROOT="$P8_DIR" HARNESS_ROOT="$ROOT"
( cd "$P8_DIR" && git init -q )
mkdir -p "$P8_DIR/.agent-harness/state/pending-asks" "$P8_DIR/config" "$P8_DIR/.agent-harness/.boot-settings"
echo '{"permissions":{"allow":[]}}' > "$P8_DIR/.agent-harness/.boot-settings/dev.json"
echo 'read-only:' > "$P8_DIR/config/lead-auto-allow.yaml"   # 빈 카테고리 (Agent 가 gray 로)
# shellcheck disable=SC1091
source "$ROOT/bin/lib.sh"
P8_SET="$(generate_worker_settings dev dev-1)"
tmux kill-session -t "$P8_SES" 2>/dev/null || true
tmux new-session -d -s "$P8_SES" -c "$P8_DIR" -x 200 -y 50
tmux send-keys -t "$P8_SES" "cd '$P8_DIR' && claude --model claude-haiku-4-5-20251001 --settings '$P8_SET' --session-id $(uuidgen)" Enter
wait_repl "$P8_SES" || { echo "P8 RESULT: ✗ REPL 미준비 (위양성 방지 차원 SKIP)"; tmux kill-session -t "$P8_SES" 2>/dev/null; rm -rf "$P8_DIR"; exit 1; }

# ★ 게이트 발화 판정은 pending-ask 파일 *폴링* + 도구명 *명시 지시* 로 한다.
#   sleep 고정 + 모호한 지시는 모델이 도구를 호출하기 전에 판정해 위양성을 냈다 (실측 diag).
P8_PA="$P8_DIR/.agent-harness/state/pending-asks"
P8_GATELOG="$P8_DIR/.agent-harness/state/permission-gate.log"
wait_pending() {  # $1=기대 tool $2=최대초. 매칭 pending-ask 경로를 stdout, rc0.
  local want="$1" max="${2:-50}" i=0 f t
  while [ "$i" -lt "$max" ]; do
    for f in "$P8_PA/"*.json; do
      [ -f "$f" ] || continue
      t="$(jq -r .tool "$f" 2>/dev/null)"
      [ "$t" = "$want" ] && { printf '%s' "$f"; return 0; }
    done
    sleep 3; i=$((i+3))
  done
  return 1
}
# 응답 깔고 워커 wake (무한 대기 방지) + pending 정리.
release_pending() {  # $1=pending-ask 경로
  local f="$1" u c
  u="$(jq -r .uuid "$f")"; c="$(jq -r .channel "$f")"
  printf 'deny' > "$P8_PA/${u}.response.tmp" && mv "$P8_PA/${u}.response.tmp" "$P8_PA/${u}.response"
  tmux wait-for -S "$c" 2>/dev/null || true
  sleep 4
  rm -f "$P8_PA/"*.json "$P8_PA/"*.response 2>/dev/null
}

# WebFetch: 도구명 명시 지시 → 게이트가 pending-ask(tool=WebFetch) 생성해야 함.
tmux send-keys -t "$P8_SES" -l "Use the WebFetch tool to fetch https://example.com and report the page title"
sleep 1; tmux send-keys -t "$P8_SES" Enter
if pj="$(wait_pending WebFetch 50)"; then
  echo "P8 RESULT (WebFetch): ✓ 게이트 발화 (pending-ask, tool=WebFetch)"
  release_pending "$pj"
else
  echo "P8 RESULT (WebFetch): ✗ pending-ask(WebFetch) 미생성 — 게이트로그 확인:"
  grep -E 'WebFetch' "$P8_GATELOG" 2>/dev/null || echo "    (게이트로그에 WebFetch 항목 없음 → 모델이 호출 안 함 가능)"
  tmux capture-pane -t "$P8_SES" -p | tail -12
fi

# ★ 서브에이전트 스폰 도구명 실측 (4차 — ① 목적): 도구명 명시 지시 →
#   pending-ask .tool 필드로 실제 도구명 확정. `Agent` 면 docs 일치, 다른 이름이면 matcher 정정.
tmux send-keys -t "$P8_SES" -l "Use the Agent tool to spawn a subagent that lists files in this directory"
sleep 1; tmux send-keys -t "$P8_SES" Enter
sleep 3
pjs="$(ls "$P8_PA/"*.json 2>/dev/null | head -1)"
for _ in $(seq 1 16); do [ -n "$pjs" ] && break; sleep 3; pjs="$(ls "$P8_PA/"*.json 2>/dev/null | head -1)"; done
if [ -n "$pjs" ]; then
  stool="$(jq -r .tool "$pjs")"
  echo "P8 RESULT (subagent): ✓ 게이트 발화 — 실제 도구명 tool=${stool}"
  if [ "$stool" = "Agent" ]; then
    echo "  → docs 일치 (Agent). matcher 정정 불필요."
  else
    echo "  ★ docs 와 다름 (${stool}) → Task 5 matcher 문자열에 '${stool}' 추가 필요!"
  fi
  release_pending "$pjs"
else
  echo "P8 RESULT (subagent): ? pending-ask 미생성 — matcher 에 Agent 안 잡혔거나(도구명 다름) 워커가 서브에이전트 안 씀. 화면:"
  tmux capture-pane -t "$P8_SES" -p | tail -12
  echo "  → permission-gate.log 의 도구명 확인: $(grep -oE '(Agent|Task|Subagent)[a-zA-Z]*' "$P8_DIR/.agent-harness/state/permission-gate.log" 2>/dev/null | sort -u | tr '\n' ' ')"
fi
tmux kill-session -t "$P8_SES" 2>/dev/null || true
rm -rf "$P8_DIR"
