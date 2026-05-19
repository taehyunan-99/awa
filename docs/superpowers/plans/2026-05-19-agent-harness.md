# 에이전트 하네스 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 1차 tmux 멀티 에이전트 토대 위에, 판단형 메인(프로젝트 관리자) + `/loop`·Monitor 상주 감시 리뷰어 + scope 사전차단 + 모델 차등을 올린다.

**Architecture:** 메인·워커·리뷰어가 파일(events.log/tasks/results/review/.harness-state/.review-cursor) + tmux wait-for 시그널로만 결합. 약한 신호(scope, 기계적·즉시)는 셸 헬퍼로, 강한 신호(의미 판정, done 후)는 리뷰어 claude로. 메인·리뷰어는 `/loop` dynamic 모드로 상주(claude 무상태는 상태 파일로 보완). events.log 파일변경 기록은 PostToolUse hook으로 결정적.

**Tech Stack:** bash 3.2(macOS), tmux 3.6a, Claude Code CLI(`/loop`·Monitor·PostToolUse hook), 의존성 제로 셸 테스트 하네스(`tests/assert.sh`).

**설계 근거:** `docs/superpowers/specs/2026-05-19-agent-harness-design.md` (v3, 커밋 `1739552`)

---

## 작업 전 필수 — 격리 브랜치

이 repo는 1차 토대가 main에 머지된 독립 git repo다. **main에서 바로 구현 시작 금지.** 첫 작업으로:

```bash
cd ~/Desktop/Repo/Practice/tmux-agent-team
git checkout -b feat/agent-harness
git branch --show-current   # feat/agent-harness 확인
```

---

## 파일 구조 (구현 대상)

| 파일 | 책임 | 태스크 |
|---|---|---|
| `bin/lib.sh` | `resolve_session`/`target_in`/`scope_match`/events.log 파싱 헬퍼 추가 | T2,T3,T4 |
| `bin/dispatch.sh` | `resolve_session` 사용, window 0/1 양쪽 pane 조회 | T5 |
| `bin/wait-worker.sh` | `resolve_session` 사용 | T5 |
| `bin/log-event.sh` | PostToolUse hook 스크립트 — events.log 5필드 결정적 기록 | T6 |
| `bin/team-up.sh` | review 윈도우, `pane:역할:모델` 파싱·`--model`, `/loop` 주입, `HARNESS_WORKER` env, 워커 카탈로그 주입 | T8 |
| `profiles/*.sh` | `REVIEWERS=()`·`pane:역할:모델`·`ORCHESTRATOR_MODEL` | T9 |
| `prompts/_common.md` | events.log 보조 규약 1줄 | T7 |
| `prompts/roles/{dev,tester,researcher,security}.md` | scope 준수 + events.log 보조 규칙 | T7 |
| `prompts/roles/reviewer-{spec,quality,arch}.md` | 관점별 리뷰어 + `/loop`·커서 규약 | T10 |
| `prompts/roles/orchestrator.md` | 책임 9개 + 워커 카탈로그 + 단계전이 금지 + `.harness-state` | T10 |
| `prompts/loop/{orchestrator,reviewer}.md` | `/loop`에 주입할 dynamic 감시 프롬프트 본문 | T10 |
| `workspace/.claude/settings.json` | PostToolUse hook 정의 | T6 |
| `tests/test-*.sh` (12 신규) | 메커니즘 검증 | 각 태스크 |
| `tests/probes/probe-{loop,hook}.sh` | claude 기동 실측 | T1 |
| `tests/run-all.sh` | 신규 스위트 등록 | 각 태스크 |

**의존 순서**: T1(프로브)·T2(session)·T3(target)·T4(scope) 독립 → T5(dispatch/wait 확장, T2·T3 의존) → T6(hook)·T7(워커 프롬프트) → T8(team-up, T2·T3·T6 의존) → T9(프로파일) → T10(프롬프트) → T11(커서)·T12(harness-state)·T13(디바운스)·T14(review-flow)·T15(signal-fallback) → T16(e2e).

---

### Task 1: 실측 프로브 — `/loop`+Monitor·PostToolUse hook 검증

미검증 가정을 구현 전 먼저 깬다(spec §8.1). probe-loop은 spec 작성 중 1차 PASS했으므로 스크립트로 고정·재현, probe-hook은 신규 검증.

**Files:**
- Create: `tests/probes/probe-loop.sh`
- Create: `tests/probes/probe-hook.sh`

- [ ] **Step 1: probe-loop.sh 작성**

```bash
#!/usr/bin/env bash
# /loop+Monitor 실측: tmux pane 내 대화형 claude 가 /loop 으로
# events.log 커서 순회 자기반복을 실제로 도는지. run-all 비포함, 수동 실행.
set -uo pipefail
S="probe_loop_$$"
WS="/tmp/$S-ws"
cleanup() { tmux kill-session -t "$S" 2>/dev/null || true; rm -rf "$WS"; }
trap cleanup EXIT

rm -rf "$WS"; mkdir -p "$WS"
: > "$WS/events.log"; echo 0 > "$WS/.review-cursor"; : > "$WS/review-out.log"

tmux new-session -d -s "$S" -x 200 -y 50
tmux set-option -t "$S" allow-set-title off 2>/dev/null || true
tmux send-keys -t "$S" -l "cd $WS && claude --dangerously-skip-permissions"
tmux send-keys -t "$S" Enter
echo "[probe-loop] claude 기동 35s 대기..."
sleep 35

LOOP_PROMPT="/loop 감시: $WS/.review-cursor 의 숫자 N 읽고 $WS/events.log 의 0-based 라인오프셋 N부터 새 줄을 각각 \"REVIEWED: <내용>\" 으로 $WS/review-out.log 에 append, .review-cursor 를 events.log 총줄수로 갱신. 새 줄 없으면 아무것도 안함."
tmux send-keys -t "$S" -l "$LOOP_PROMPT"
sleep 1
tmux send-keys -t "$S" Enter
echo "[probe-loop] /loop 주입, 초기처리+Monitor 무장 25s 대기..."
sleep 25

echo "a	dev	101	modify	src/auth/login.ts" >> "$WS/events.log"
echo "b	dev	101	modify	src/auth/token.ts" >> "$WS/events.log"
echo "c	arch	102	write	docs/arch.md" >> "$WS/events.log"
echo "[probe-loop] 3줄 주입, Monitor 발화 75s 대기..."
sleep 75

echo "d	dev	101	modify	src/payment/charge.ts" >> "$WS/events.log"
echo "e	dev	101	done	-" >> "$WS/events.log"
echo "[probe-loop] 2줄 추가(증분 검증), 75s 대기..."
sleep 75

lines="$(wc -l < "$WS/review-out.log" | tr -d ' ')"
cursor="$(cat "$WS/.review-cursor")"
echo "[probe-loop] review-out.log 줄수=$lines (기대 5), cursor=$cursor (기대 5)"
if [ "$lines" = "5" ] && [ "$cursor" = "5" ]; then
  echo "[probe-loop] PASS"; exit 0
else
  echo "[probe-loop] FAIL — pane 덤프:"; tmux capture-pane -t "$S" -p | tail -30; exit 1
fi
```

- [ ] **Step 2: probe-loop 실행 (수동, ~3분 30초)**

Run: `bash tests/probes/probe-loop.sh`
Expected: 마지막 줄 `[probe-loop] PASS`, exit 0

- [ ] **Step 3: probe-hook.sh 작성**

```bash
#!/usr/bin/env bash
# PostToolUse hook 실측: tmux pane 기동 claude 에 프로젝트 .claude/settings.json
# 의 PostToolUse hook 이 적용되고 HARNESS_WORKER env 가 전달되는지. 수동 실행.
set -uo pipefail
S="probe_hook_$$"
WS="/tmp/$S-ws"
cleanup() { tmux kill-session -t "$S" 2>/dev/null || true; rm -rf "$WS"; }
trap cleanup EXIT

rm -rf "$WS"; mkdir -p "$WS/.claude"
: > "$WS/events.log"

# 최소 hook: Write/Edit 후 tool_input.file_path 를 events.log 에 기록
cat > "$WS/.claude/settings.json" <<'JSON'
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit|MultiEdit",
        "hooks": [
          { "type": "command", "command": "jq -r '.tool_input.file_path // empty' | while read -r p; do [ -n \"$p\" ] && echo \"hook\t${HARNESS_WORKER:-NOENV}\t-\tmodify\t$p\" >> '$WS/events.log'; done" }
        ]
      }
    ]
  }
}
JSON
# settings.json 안의 $WS 를 실제 경로로 치환 (heredoc 내 변수 미전개 대응)
sed -i.bak "s#\$WS#$WS#g" "$WS/.claude/settings.json" && rm -f "$WS/.claude/settings.json.bak"

tmux new-session -d -s "$S" -x 200 -y 50
tmux set-option -t "$S" allow-set-title off 2>/dev/null || true
tmux send-keys -t "$S" -l "cd $WS && HARNESS_WORKER=probeworker claude --dangerously-skip-permissions"
tmux send-keys -t "$S" Enter
echo "[probe-hook] claude 기동 35s 대기..."
sleep 35

tmux send-keys -t "$S" -l "make a file named hello.txt with content hi using the Write tool"
sleep 1
tmux send-keys -t "$S" Enter
echo "[probe-hook] Write 지시, hook 발화 60s 대기..."
sleep 60

if grep -q "hello.txt" "$WS/events.log" 2>/dev/null; then
  echo "[probe-hook] events.log 기록됨:"; cat "$WS/events.log"
  if grep -q "probeworker" "$WS/events.log"; then
    echo "[probe-hook] PASS (hook 적용 + HARNESS_WORKER 전달)"; exit 0
  else
    echo "[probe-hook] PARTIAL — hook 적용되나 HARNESS_WORKER 미전달(NOENV). 폴백 설계 필요"; exit 2
  fi
else
  echo "[probe-hook] FAIL — hook 미적용. spec §5.6 폴백 발동:"; tmux capture-pane -t "$S" -p | tail -30; exit 1
fi
```

- [ ] **Step 4: probe-hook 실행 (수동, ~1분 35초)**

Run: `bash tests/probes/probe-hook.sh`
Expected 가지치기:
- exit 0 `PASS` → §5.6 hook 주경로 채택, 계획대로 진행
- exit 2 `PARTIAL` → hook은 되나 HARNESS_WORKER 미전달 → T6에서 워커명 대체 수단(pane title을 hook이 tmux로 조회) 적용
- exit 1 `FAIL` → hook 미적용 → spec §5.6 폴백(워커 프롬프트 규칙 + 리뷰어 diff 역추적)으로 T6·T7 변경. **이 경우 BLOCKED 보고 후 사용자 결정 대기**

- [ ] **Step 5: Commit**

```bash
git add tests/probes/probe-loop.sh tests/probes/probe-hook.sh
git commit -m "test: /loop·hook 실측 프로브 (구현 전 미검증 가정 검증)"
```

---

### Task 2: `resolve_session` — SESSION 결정 단일화 (이슈 2)

`dispatch.sh:7`(`$SESSION_DEFAULT`)과 `team-up.sh:21`(프로파일 `$SESSION`) 불일치를 단일 함수로 통일.

**Files:**
- Modify: `bin/lib.sh` (함수 추가)
- Test: `tests/test-session-resolve.sh`
- Modify: `tests/run-all.sh`

- [ ] **Step 1: 실패 테스트 작성**

`tests/test-session-resolve.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"
source "$ROOT/bin/lib.sh"

# 기본: 인자 없고 env 없으면 SESSION_DEFAULT
unset SESSION_OVERRIDE PROFILE_SESSION 2>/dev/null || true
assert_eq "agents" "$(resolve_session)" "기본 → SESSION_DEFAULT"

# PROFILE_SESSION 우선 (team-up: 프로파일 SESSION)
PROFILE_SESSION="featteam"
assert_eq "featteam" "$(resolve_session)" "PROFILE_SESSION 반영"

# SESSION_OVERRIDE 최우선 (테스트/멀티팀)
SESSION_OVERRIDE="ovr"
assert_eq "ovr" "$(resolve_session)" "SESSION_OVERRIDE 최우선"
unset SESSION_OVERRIDE PROFILE_SESSION

test_summary
```

- [ ] **Step 2: 실패 확인**

Run: `bash tests/test-session-resolve.sh`
Expected: FAIL — `resolve_session: command not found` 또는 빈 출력으로 assert FAIL

- [ ] **Step 3: `bin/lib.sh`에 `resolve_session` 추가**

`bin/lib.sh`의 `target_of()` 정의 바로 위에 삽입:

```bash
# SESSION 결정 단일화. 우선순위: SESSION_OVERRIDE > PROFILE_SESSION > SESSION_DEFAULT.
# dispatch.sh/wait-worker.sh/team-up.sh 가 모두 이 함수로 세션명을 얻어 불일치 제거(이슈 2).
resolve_session() {
  printf '%s' "${SESSION_OVERRIDE:-${PROFILE_SESSION:-$SESSION_DEFAULT}}"
}
```

- [ ] **Step 4: 통과 확인**

Run: `bash tests/test-session-resolve.sh`
Expected: PASS — `ran=3 fail=0`

- [ ] **Step 5: run-all.sh 등록**

`tests/run-all.sh`에서 테스트 목록 배열에 `test-session-resolve.sh` 추가(기존 파일의 목록 패턴을 따를 것).

- [ ] **Step 6: 회귀 확인**

Run: `bash tests/run-all.sh`
Expected: 전체 PASS (기존 8 + 신규 1)

- [ ] **Step 7: Commit**

```bash
git add bin/lib.sh tests/test-session-resolve.sh tests/run-all.sh
git commit -m "feat: resolve_session 세션 결정 단일화 (이슈 2)"
```

---

### Task 3: `target_in` — window 0/1 양쪽 pane 조회 (이슈 1·3)

`target_of()`의 `%s:0.%s`(window 0 고정)를 보완. 기존 `target_of`는 호환 유지하고 window 지정 가능한 `target_in` 신설.

**Files:**
- Modify: `bin/lib.sh`
- Test: `tests/test-target.sh`
- Modify: `tests/run-all.sh`

- [ ] **Step 1: 실패 테스트 작성**

`tests/test-target.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"
source "$ROOT/bin/lib.sh"

unset SESSION_OVERRIDE PROFILE_SESSION 2>/dev/null || true

# target_in <window> <pane> → session:window.pane (resolve_session 사용)
assert_eq "agents:0.2" "$(target_in 0 2)" "window 0 pane 2"
assert_eq "agents:1.3" "$(target_in 1 3)" "window 1(review) pane 3"

PROFILE_SESSION="ft"
assert_eq "ft:1.2" "$(target_in 1 2)" "세션명 resolve_session 반영"
unset PROFILE_SESSION

# 기존 target_of 회귀 (window 0 고정 유지)
assert_eq "agents:0.4" "$(target_of 4)" "target_of 기존 동작 유지"

test_summary
```

- [ ] **Step 2: 실패 확인**

Run: `bash tests/test-target.sh`
Expected: FAIL — `target_in: command not found`

- [ ] **Step 3: `bin/lib.sh`에 `target_in` 추가, `target_of` 재정의**

`target_of()` 정의를 다음으로 교체(동작 동일, `target_in` 위임으로 DRY):

```bash
# 윈도우·페인 인덱스 → tmux target. 세션명은 resolve_session().
# 2윈도우(team=0, review=1) 도입으로 window 고정 불가 → window 인자화(이슈 1·3).
target_in() {
  local win="$1" pane="$2"
  printf '%s:%s.%s' "$(resolve_session)" "$win" "$pane"
}

# 하위호환: 기존 호출부(window 0 가정)는 그대로. 내부적으로 target_in 위임.
target_of() {
  target_in 0 "$1"
}
```

주의: 기존 `target_of`는 `${SESSION:-$SESSION_DEFAULT}`를 썼다. `resolve_session`은 `SESSION_OVERRIDE>PROFILE_SESSION>SESSION_DEFAULT`다. 기존 테스트 `test-lib-paths.sh`가 `SESSION=myteam`으로 검증하므로(line 18-19), 호환을 위해 `resolve_session`에 `SESSION` 변수도 반영해야 한다 → Step 3b.

- [ ] **Step 3b: `resolve_session` 호환 보강**

`bin/lib.sh`의 `resolve_session`을 다음으로 교체(기존 `SESSION` 변수 호환 유지):

```bash
resolve_session() {
  printf '%s' "${SESSION_OVERRIDE:-${PROFILE_SESSION:-${SESSION:-$SESSION_DEFAULT}}}"
}
```

- [ ] **Step 4: 통과 + 회귀 확인**

Run: `bash tests/test-target.sh && bash tests/test-session-resolve.sh && bash tests/test-lib-paths.sh`
Expected: 3개 모두 PASS (`test-lib-paths.sh`의 `SESSION=myteam` 케이스 포함)

- [ ] **Step 5: run-all.sh 등록 + 전체 회귀**

`tests/run-all.sh`에 `test-target.sh` 추가.
Run: `bash tests/run-all.sh`
Expected: 전체 PASS

- [ ] **Step 6: Commit**

```bash
git add bin/lib.sh tests/test-target.sh tests/run-all.sh
git commit -m "feat: target_in window 0/1 조회 + target_of 호환 위임 (이슈 1·3)"
```

---

### Task 4: `scope_match` — glob 경로 매칭 (이슈 8)

bash `[[ ==  ]]`가 `**` 미지원 → 정규식 변환 방식(spec §5.1).

**Files:**
- Modify: `bin/lib.sh`
- Test: `tests/test-scope.sh`
- Modify: `tests/run-all.sh`

- [ ] **Step 1: 실패 테스트 작성**

`tests/test-scope.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"
source "$ROOT/bin/lib.sh"

# scope_match <path> <pattern> → 0(매치)/1(불일치)
scope_match "src/auth/login.ts" "src/auth/**"; assert_success "$?" "** 재귀 매치"
scope_match "src/auth/sub/x.ts"  "src/auth/**"; assert_success "$?" "** 다단계 매치"
scope_match "src/auth/login.ts" "src/*/login.ts"; assert_success "$?" "* 단일 세그먼트 매치"

scope_match "src/payment/x.ts"  "src/auth/**"; assert_fail "$?" "다른 디렉터리 불일치"
scope_match "src/authx/y.ts"    "src/auth/**"; assert_fail "$?" "경계 오매치 방지 (authx≠auth)"
scope_match "src/auth/a/b.ts"   "src/auth/*";  assert_fail "$?" "* 는 / 안 넘음 (a/b 불일치)"

test_summary
```

- [ ] **Step 2: 실패 확인**

Run: `bash tests/test-scope.sh`
Expected: FAIL — `scope_match: command not found`

- [ ] **Step 3: `bin/lib.sh`에 `scope_match` 추가**

```bash
# glob 경로 매칭. bash [[ == ]] 는 ** 재귀를 지원 안 함 → 정규식 변환(spec §5.1, 이슈 8).
#   **  → .*           (디렉터리 경계 넘는 재귀)
#   *   → [^/]*         (단일 세그먼트, / 안 넘음)
#   .   → \.            (literal)
# 전체 앵커(^...$)로 부분일치(authx vs auth) 차단.
# 반환: 매치 0, 불일치 1.
scope_match() {
  local path="$1" pat="$2" re=""
  local i ch
  for (( i=0; i<${#pat}; i++ )); do
    ch="${pat:i:1}"
    case "$ch" in
      '*')
        if [ "${pat:i+1:1}" = '*' ]; then re+='.*'; i=$((i+1)); else re+='[^/]*'; fi ;;
      '.') re+='\.' ;;
      '/') re+='/' ;;
      *) re+="$ch" ;;
    esac
  done
  [[ "$path" =~ ^${re}$ ]]
}
```

- [ ] **Step 4: 통과 확인**

Run: `bash tests/test-scope.sh`
Expected: PASS — `ran=6 fail=0`

- [ ] **Step 5: run-all.sh 등록 + 회귀**

`tests/run-all.sh`에 `test-scope.sh` 추가.
Run: `bash tests/run-all.sh`
Expected: 전체 PASS

- [ ] **Step 6: Commit**

```bash
git add bin/lib.sh tests/test-scope.sh tests/run-all.sh
git commit -m "feat: scope_match glob 경로 매칭 (이슈 8)"
```

---

### Task 5: dispatch.sh / wait-worker.sh — resolve_session·2윈도우 조회 (이슈 1·2)

**Files:**
- Modify: `bin/dispatch.sh`
- Modify: `bin/wait-worker.sh`
- Test: `tests/test-dispatch.sh` (기존 확장 — 회귀 + 신규)

- [ ] **Step 1: 기존 dispatch 테스트 확인**

Run: `bash tests/test-dispatch.sh`
Expected: 기존 PASS (변경 전 기준선 확보)

- [ ] **Step 2: `bin/dispatch.sh` 수정 — resolve_session + window 0/1 조회**

`bin/dispatch.sh:7` 교체:

```bash
SESSION="$(resolve_session)"
```

`bin/dispatch.sh:31-42` (워커→페인 조회 블록)을 window 0·1 양쪽 조회로 교체:

```bash
# 워커/리뷰어 → 페인: window 0(team)·1(review) 양쪽에서 pane title 로 찾는다.
TARGET=""
for win in 0 1; do
  tmux has-session -t "$SESSION" 2>/dev/null || break
  if ! tmux list-windows -t "$SESSION" -F '#{window_index}' | grep -qx "$win"; then
    continue
  fi
  while IFS=$'\t' read -r pidx ptitle; do
    if [ "$ptitle" = "$WORKER" ]; then
      TARGET="$SESSION:$win.$pidx"
      break
    fi
  done < <(tmux list-panes -t "$SESSION:$win" -F $'#{pane_index}\t#{pane_title}')
  [ -n "$TARGET" ] && break
done

if [ -z "$TARGET" ]; then
  echo "오류: 워커/리뷰어 '$WORKER' 페인을 찾을 수 없음 (window 0·1 조회)." >&2
  exit 1
fi
```

`bin/dispatch.sh` 마지막의 `TARGET="$SESSION:0.$PANE_IDX"` 줄은 위 블록이 TARGET을 직접 만들므로 **삭제**. `send_prompt "$TARGET" "TASK $TASK_ID"`는 유지.

- [ ] **Step 3: `bin/wait-worker.sh` 수정 — resolve_session**

`bin/wait-worker.sh`에서 `SESSION="${SESSION_OVERRIDE:-$SESSION_DEFAULT}"` 형태의 줄을 찾아 다음으로 교체:

```bash
SESSION="$(resolve_session)"
```

(wait-worker.sh는 wait-for 시그널만 쓰므로 window 조회 불필요 — 세션명 일치만 필요)

- [ ] **Step 4: 회귀 + 신규 검증**

Run: `bash tests/test-dispatch.sh`
Expected: PASS (기존 케이스 회귀). 신규 window 1 조회는 T8(team-up 2윈도우) 후 e2e(T16)에서 통합 검증 — 여기선 회귀 유지가 합격선.

- [ ] **Step 5: 전체 회귀**

Run: `bash tests/run-all.sh`
Expected: 전체 PASS

- [ ] **Step 6: Commit**

```bash
git add bin/dispatch.sh bin/wait-worker.sh
git commit -m "feat: dispatch/wait-worker resolve_session·2윈도우 조회 (이슈 1·2)"
```

---

### Task 6: log-event.sh + PostToolUse hook — events.log 결정적 기록 (이슈 6)

**전제**: T1 probe-hook 결과에 따름. PASS → 아래대로. PARTIAL → Step 3에서 워커명을 pane title 조회로 대체. FAIL → 사용자 결정(폴백 설계).

**Files:**
- Create: `bin/log-event.sh`
- Create: `workspace/.claude/settings.json`
- Test: `tests/test-log-event.sh`
- Modify: `tests/run-all.sh`

- [ ] **Step 1: 실패 테스트 작성**

`tests/test-log-event.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
EV="$TMP/events.log"; : > "$EV"

# log-event.sh 는 stdin 으로 hook JSON 받아 5필드 라인을 EVENTS_LOG 에 append.
# 워커명은 HARNESS_WORKER env. 경로는 REPO_ROOT 기준 상대경로화.
echo '{"tool_input":{"file_path":"'"$ROOT"'/src/auth/login.ts"}}' \
  | HARNESS_WORKER=dev HARNESS_TASK=101 EVENTS_LOG="$EV" REPO_ROOT="$ROOT" \
    bash "$ROOT/bin/log-event.sh"

line="$(cat "$EV")"
assert_contains "$line" "dev" "워커명 기록"
assert_contains "$line" "101" "task id 기록"
assert_contains "$line" "modify" "action=modify"
assert_contains "$line" "src/auth/login.ts" "repo 상대경로화"
fields="$(awk -F'\t' '{print NF}' "$EV")"
assert_eq "5" "$fields" "정확히 5필드(탭 구분)"

test_summary
```

- [ ] **Step 2: 실패 확인**

Run: `bash tests/test-log-event.sh`
Expected: FAIL — `bin/log-event.sh` 없음

- [ ] **Step 3: `bin/log-event.sh` 작성**

```bash
#!/usr/bin/env bash
# PostToolUse hook 스크립트. stdin 으로 hook JSON 수신 →
# 수정 파일 경로를 repo 상대경로 5필드 라인으로 events.log 에 결정적 append.
# 워커명=HARNESS_WORKER, task=HARNESS_TASK (team-up 이 pane env 로 주입).
# 자기보고 아님 — claude 가 Edit/Write 쓰면 hook 이 무조건 실행됨(이슈 6).
set -uo pipefail

EVENTS_LOG="${EVENTS_LOG:-$HOME/.agent-harness-events.log}"
REPO_ROOT="${REPO_ROOT:-$PWD}"
worker="${HARNESS_WORKER:-unknown}"
task="${HARNESS_TASK:--}"

raw="$(cat)"
# jq 있으면 사용, 없으면 grep 폴백 (의존성 최소화)
if command -v jq >/dev/null 2>&1; then
  fpath="$(printf '%s' "$raw" | jq -r '.tool_input.file_path // empty' 2>/dev/null)"
else
  fpath="$(printf '%s' "$raw" | grep -o '"file_path"[^,}]*' | head -1 | sed 's/.*: *"//; s/"$//')"
fi
[ -z "$fpath" ] && exit 0   # 경로 없는 도구 호출은 무시

# repo 상대경로화 (길이 억제 — spec §5.2)
case "$fpath" in
  "$REPO_ROOT"/*) rel="${fpath#"$REPO_ROOT"/}" ;;
  *) rel="$fpath" ;;
esac

ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf '%s\t%s\t%s\t%s\t%s\n' "$ts" "$worker" "$task" "modify" "$rel" >> "$EVENTS_LOG"
```

`chmod +x bin/log-event.sh`.

- [ ] **Step 4: 통과 확인**

Run: `chmod +x bin/log-event.sh && bash tests/test-log-event.sh`
Expected: PASS — `ran=5 fail=0`

- [ ] **Step 5: `workspace/.claude/settings.json` 작성**

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "EVENTS_LOG=\"$CLAUDE_PROJECT_DIR/../workspace/events.log\" REPO_ROOT=\"$CLAUDE_PROJECT_DIR/..\" bash \"$CLAUDE_PROJECT_DIR/../bin/log-event.sh\""
          }
        ]
      }
    ]
  }
}
```

주의: 실제 `EVENTS_LOG`/`REPO_ROOT` 경로는 T1 probe-hook에서 확인된 `CLAUDE_PROJECT_DIR` 실측값에 맞춘다. probe-hook이 PARTIAL이었으면 워커명을 `log-event.sh`가 `tmux display-message -p '#{pane_title}'`로 조회하도록 Step 3 스크립트에 분기 추가.

- [ ] **Step 6: run-all.sh 등록 + 회귀**

`tests/run-all.sh`에 `test-log-event.sh` 추가.
Run: `bash tests/run-all.sh`
Expected: 전체 PASS

- [ ] **Step 7: Commit**

```bash
git add bin/log-event.sh workspace/.claude/settings.json tests/test-log-event.sh tests/run-all.sh
git commit -m "feat: log-event.sh + PostToolUse hook events.log 결정적 기록 (이슈 6)"
```

---

### Task 7: 워커 프롬프트 확장 — scope 준수 + events.log 보조 규칙

**Files:**
- Modify: `prompts/_common.md`
- Modify: `prompts/roles/dev.md`, `prompts/roles/tester.md`, `prompts/roles/researcher.md`, `prompts/roles/security.md`
- Test: `tests/test-prompts-harness.sh`
- Modify: `tests/run-all.sh`

- [ ] **Step 1: 실패 테스트 작성**

`tests/test-prompts-harness.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"

common="$(cat "$ROOT/prompts/_common.md")"
assert_contains "$common" "events.log" "_common 에 events.log 보조 규약"
assert_contains "$common" "scope" "_common 에 scope 준수 언급"

dev="$(cat "$ROOT/prompts/roles/dev.md")"
assert_contains "$dev" "allowed_paths" "dev 역할에 scope 준수 규칙"

test_summary
```

- [ ] **Step 2: 실패 확인**

Run: `bash tests/test-prompts-harness.sh`
Expected: FAIL — assert_contains FAIL (문구 미존재)

- [ ] **Step 3: `prompts/_common.md` 끝에 추가**

```markdown

## 하네스 규약 (scope·events.log)

- 배정된 `workspace/tasks/<id>.md` 의 `allowed_paths` 안에서만 파일을 수정하라. `forbidden_paths` 는 절대 건드리지 마라. scope 밖 작업은 즉시 차단·재지시 대상이다.
- 파일을 수정하면 events.log 가 자동 기록된다(PostToolUse hook). 너는 별도 조치 불필요하나, hook 이 못 잡는 비-도구 변경을 했다면 `workspace/events.log` 에 한 줄(`<ISO>\t<너의이름>\t<task>\tmodify\t<상대경로>`)을 보조로 append 하라.
- 작업 완료 시 `workspace/results/<id>.md` 에 변경 요약을 쓰고, `workspace/events.log` 에 `<ISO>\t<너의이름>\t<task>\tdone\t-` 를 기록한 뒤 `tmux wait-for -S done-<너의이름>-<task>` 를 실행하라.
```

- [ ] **Step 4: 각 역할 파일에 scope 한 줄 추가**

`prompts/roles/dev.md`·`tester.md`·`researcher.md`·`security.md` 각 파일 끝에 추가:

```markdown

배정된 task 의 `allowed_paths` 범위를 반드시 지킨다. 범위 밖이 필요하면 작업을 멈추고 메인에 보고한다(직접 확장 금지).
```

- [ ] **Step 5: 통과 확인**

Run: `bash tests/test-prompts-harness.sh`
Expected: PASS — `ran=3 fail=0`

- [ ] **Step 6: run-all.sh 등록 + 회귀**

`tests/run-all.sh`에 `test-prompts-harness.sh` 추가.
Run: `bash tests/run-all.sh`
Expected: 전체 PASS

- [ ] **Step 7: Commit**

```bash
git add prompts/_common.md prompts/roles/ tests/test-prompts-harness.sh tests/run-all.sh
git commit -m "feat: 워커 프롬프트 scope 준수 + events.log 보조 규약"
```

---

### Task 8: team-up.sh — review 윈도우·모델 차등·/loop·env·카탈로그

**Files:**
- Modify: `bin/team-up.sh`
- Test: `tests/test-team-up-harness.sh`
- Modify: `tests/run-all.sh`

- [ ] **Step 1: 실패 테스트 작성**

`tests/test-team-up-harness.sh` (claude 미기동 — `AGENT_CMD=cat`, tmux만):

```bash
#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"

S="tuh_$$"
cleanup() { tmux kill-session -t "$S" 2>/dev/null || true; }
trap cleanup EXIT

# 임시 프로파일: WORKERS + REVIEWERS + 모델
PROF="$(mktemp -d)/p.sh"
cat > "$PROF" <<EOF
SESSION="$S"
LAYOUT="tiled"
WORKERS=("dev:dev:opus" "test:tester")
REVIEWERS=("qual:quality:haiku")
ORCHESTRATOR_MODEL="opus"
EOF

AGENT_CMD="cat" bash "$ROOT/bin/team-up.sh" "$PROF" >/dev/null 2>&1
rc=$?
assert_success "$rc" "team-up 2윈도우 가동"

wins="$(tmux list-windows -t "$S" -F '#{window_index}' | tr '\n' ' ')"
assert_contains "$wins" "0" "window 0(team) 존재"
assert_contains "$wins" "1" "window 1(review) 존재"

w0titles="$(tmux list-panes -t "$S:0" -F '#{pane_title}' | tr '\n' ' ')"
assert_contains "$w0titles" "ORCHESTRATOR" "team 윈도우에 orchestrator"
assert_contains "$w0titles" "dev" "team 윈도우에 dev 워커"
w1titles="$(tmux list-panes -t "$S:1" -F '#{pane_title}' | tr '\n' ' ')"
assert_contains "$w1titles" "qual" "review 윈도우에 리뷰어 qual"

tmux kill-session -t "$S" 2>/dev/null || true
test_summary
```

- [ ] **Step 2: 실패 확인**

Run: `bash tests/test-team-up-harness.sh`
Expected: FAIL — review 윈도우 미생성, REVIEWERS 미처리

- [ ] **Step 3: `bin/team-up.sh` — 프로파일 SESSION을 PROFILE_SESSION으로 export**

`bin/team-up.sh`에서 프로파일 source 직후, `SESSION="${SESSION_OVERRIDE:-$SESSION}"` 부분을 다음으로 교체:

```bash
# 프로파일이 정의한 SESSION 을 resolve_session 체인에 노출 (이슈 2, T2).
export PROFILE_SESSION="${SESSION:-}"
SESSION="$(resolve_session)"
```

- [ ] **Step 4: `bin/team-up.sh` — `pane:역할:모델` 파싱 헬퍼**

`bin/team-up.sh`의 워커 split 루프 진입 전에 추가:

```bash
# "pane:역할[:모델]" 파싱. 모델 생략 시 sonnet. (spec §7.1)
parse_entry() {  # $1=entry → ENTRY_NAME ENTRY_ROLE ENTRY_MODEL 설정
  local e="$1"
  ENTRY_NAME="${e%%:*}"
  local rest="${e#*:}"
  ENTRY_ROLE="${rest%%:*}"
  if [ "$rest" = "$ENTRY_ROLE" ]; then ENTRY_MODEL="sonnet"; else ENTRY_MODEL="${rest#*:}"; fi
  [ -z "$ENTRY_MODEL" ] && ENTRY_MODEL="sonnet"
}

# 엔진 명령 조립: claude 는 --model, 그 외 엔진은 분기점 한 곳(codex 후속 확장지점, spec §7.2)
agent_cmd_for() {  # $1=model → echo 실행 명령
  local model="$1"
  if [ "${AGENT_CMD:-claude}" = "claude" ]; then
    printf 'claude --model %s' "$model"
  else
    printf '%s' "$AGENT_CMD"   # 테스트(cat/dummy) 또는 codex 등
  fi
}
```

기존 워커 split 루프에서 `name="${entry%%:*}"`·`role="${entry##*:}"`를 `parse_entry "$entry"` 호출 + `ENTRY_NAME`/`ENTRY_ROLE`/`ENTRY_MODEL` 사용으로 교체. AGENT_CMD send-keys 부분을 `agent_cmd_for "$ENTRY_MODEL"` 결과로 교체. 워커 pane env 주입 추가(부트스트랩 send-keys 직전):

```bash
tmux send-keys -t "$tgt" -l "export HARNESS_WORKER=$ENTRY_NAME"
tmux send-keys -t "$tgt" Enter
```

- [ ] **Step 5: `bin/team-up.sh` — review 윈도우 생성**

워커 split 루프·`select-layout` 다음, 부트스트랩 루프 전에 추가:

```bash
# review 윈도우(window 1) 생성 — REVIEWERS 정의 시에만.
if [ "${#REVIEWERS[@]:-0}" -gt 0 ] 2>/dev/null && [ -n "${REVIEWERS+x}" ]; then
  tmux new-window -t "$SESSION" -n review
  # 1차 토대 함정 회귀: 새 윈도우에도 인덱스·title 고정 적용 (review 도 같은 세션이라 세션옵션 상속되나 명시 보강)
  REV_NAMES=(); REV_PIDS=()
  first=1
  for entry in "${REVIEWERS[@]}"; do
    parse_entry "$entry"
    if [ "$first" = "1" ]; then
      pid="$(tmux display-message -p -t "$SESSION:review" '#{pane_id}')"
      first=0
    else
      pid="$(tmux split-window -t "$SESSION:review" -d -P -F '#{pane_id}')"
    fi
    tmux select-pane -t "$pid" -T "$ENTRY_NAME"
    REV_NAMES+=("$ENTRY_NAME"); REV_PIDS+=("$pid")
  done
  tmux select-layout -t "$SESSION:review" "${LAYOUT:-tiled}"
fi
```

- [ ] **Step 6: 통과 확인**

Run: `bash tests/test-team-up-harness.sh`
Expected: PASS — window 0·1, ORCHESTRATOR·dev·qual title 확인

- [ ] **Step 7: 워커 카탈로그 + /loop 주입 (orchestrator·reviewer 부트스트랩)**

부트스트랩 루프에서, ORCHESTRATOR pane 에 워커 카탈로그 + `/loop` 주입 로직 추가. 카탈로그는 `WORKERS` 배열 + 각 역할 첫 줄:

```bash
# 워커 카탈로그 조립 (B-2): "dev(역할 dev): <roles/dev.md 첫 줄>" 식
catalog=""
for entry in "${WORKERS[@]}"; do
  parse_entry "$entry"
  desc="$(head -1 "$REPO_ROOT/prompts/roles/$ENTRY_ROLE.md" 2>/dev/null)"
  catalog+="- $ENTRY_NAME (역할 $ENTRY_ROLE): $desc"$'\n'
done
orch_boot="$REPO_ROOT/prompts/roles/orchestrator.md"
{ cat "$orch_boot"; printf '\n## 현재 팀 카탈로그\n%s\n' "$catalog"; } > "$(boot_file ORCHESTRATOR)"
```

ORCHESTRATOR·각 리뷰어 pane 기동 후 send-keys 로 `prompts/loop/orchestrator.md`·`prompts/loop/reviewer.md` 내용을 `/loop ...` 형태로 주입(프롬프트 본문은 T10에서 작성, 여기선 주입 메커니즘만; T10 전엔 빈 파일이라도 주입 코드는 둠). 주입 코드:

```bash
inject_loop() {  # $1=pane_id $2=loop프롬프트파일
  local pid="$1" pf="$2"
  [ -f "$pf" ] || return 0
  tmux send-keys -t "$pid" -l "/loop $(tr '\n' ' ' < "$pf")"
  sleep 1
  tmux send-keys -t "$pid" Enter
}
```

- [ ] **Step 8: run-all.sh 등록 + 전체 회귀**

`tests/run-all.sh`에 `test-team-up-harness.sh` 추가.
Run: `bash tests/run-all.sh`
Expected: 전체 PASS (claude 미기동, tmux 메커니즘만)

- [ ] **Step 9: Commit**

```bash
git add bin/team-up.sh tests/test-team-up-harness.sh tests/run-all.sh
git commit -m "feat: team-up review 윈도우·모델 차등·/loop·env·카탈로그"
```

---

### Task 9: 프로파일 확장 — REVIEWERS·모델·ORCHESTRATOR_MODEL

**Files:**
- Modify: `profiles/default.sh`, `profiles/code-review.sh`, `profiles/research.sh`
- Create: `profiles/feature-team.sh`
- Test: `tests/test-profiles-harness.sh`
- Modify: `tests/run-all.sh`

- [ ] **Step 1: 실패 테스트 작성**

`tests/test-profiles-harness.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"

# feature-team 프로파일: 형식 검증
( source "$ROOT/profiles/feature-team.sh"
  [ "${#WORKERS[@]}" -ge 1 ] && echo "W_OK"
  [ "${#REVIEWERS[@]}" -ge 1 ] && echo "R_OK"
  printf 'ORCH=%s\n' "$ORCHESTRATOR_MODEL"
  printf 'W0=%s\n' "${WORKERS[0]}"
) > /tmp/prof_out_$$ 2>&1
out="$(cat /tmp/prof_out_$$)"; rm -f /tmp/prof_out_$$
assert_contains "$out" "W_OK" "WORKERS 정의됨"
assert_contains "$out" "R_OK" "REVIEWERS 정의됨"
assert_contains "$out" "ORCH=" "ORCHESTRATOR_MODEL 정의됨"
assert_contains "$out" ":" "워커 엔트리에 역할 구분자(:) 존재"

test_summary
```

- [ ] **Step 2: 실패 확인**

Run: `bash tests/test-profiles-harness.sh`
Expected: FAIL — `profiles/feature-team.sh` 없음

- [ ] **Step 3: `profiles/feature-team.sh` 작성**

```bash
#!/usr/bin/env bash
# 기능 개발 팀: 구현/테스트/문서 워커 + 관점별 리뷰어. 모델 차등.
SESSION="agents"
LAYOUT="tiled"
WORKERS=("dev:dev:sonnet" "test:tester:haiku" "arch:researcher:sonnet")
REVIEWERS=("spec-rev:reviewer:sonnet" "quality-rev:reviewer:haiku" "arch-rev:reviewer:opus")
ORCHESTRATOR_MODEL="opus"
```

- [ ] **Step 4: 기존 3개 프로파일에 REVIEWERS·ORCHESTRATOR_MODEL 추가**

`profiles/default.sh`·`code-review.sh`·`research.sh` 각 파일 끝에 추가(기존 WORKERS는 모델 생략형이라 sonnet 기본 — 하위호환):

```bash
REVIEWERS=("quality-rev:reviewer:haiku")
ORCHESTRATOR_MODEL="opus"
```

- [ ] **Step 5: 통과 확인**

Run: `bash tests/test-profiles-harness.sh`
Expected: PASS — `ran=4 fail=0`

- [ ] **Step 6: 기존 프로파일 회귀 (team-up 가동)**

Run: `S=pf_$$; AGENT_CMD=cat bash bin/team-up.sh default >/dev/null 2>&1; echo $?; tmux kill-session -t agents 2>/dev/null`
Expected: `0` (기존 프로파일이 REVIEWERS 추가 후에도 정상 가동)

- [ ] **Step 7: run-all.sh 등록 + 전체 회귀**

`tests/run-all.sh`에 `test-profiles-harness.sh` 추가.
Run: `bash tests/run-all.sh`
Expected: 전체 PASS

- [ ] **Step 8: Commit**

```bash
git add profiles/ tests/test-profiles-harness.sh tests/run-all.sh
git commit -m "feat: 프로파일 REVIEWERS·모델 차등·ORCHESTRATOR_MODEL + feature-team"
```

---

### Task 10: 역할·loop 프롬프트 — orchestrator/reviewer 신규

**Files:**
- Create: `prompts/roles/orchestrator.md`
- Create: `prompts/roles/reviewer-spec.md`, `reviewer-quality.md`, `reviewer-arch.md`
- Create: `prompts/loop/orchestrator.md`, `prompts/loop/reviewer.md`
- Test: `tests/test-role-prompts.sh`
- Modify: `tests/run-all.sh`

- [ ] **Step 1: 실패 테스트 작성**

`tests/test-role-prompts.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"

orch="$(cat "$ROOT/prompts/roles/orchestrator.md")"
assert_contains "$orch" "단계" "orchestrator 단계전이 금지 규약"
assert_contains "$orch" ".harness-state" "orchestrator harness-state 규약"
assert_contains "$orch" "카탈로그" "orchestrator 워커 카탈로그 사용"

revl="$(cat "$ROOT/prompts/loop/reviewer.md")"
assert_contains "$revl" "events.log" "reviewer loop 가 events.log 감시"
assert_contains "$revl" ".review-cursor" "reviewer loop 커서 사용"

orchl="$(cat "$ROOT/prompts/loop/orchestrator.md")"
assert_contains "$orchl" "review/" "orchestrator loop 가 review/ 감시"

test_summary
```

- [ ] **Step 2: 실패 확인**

Run: `bash tests/test-role-prompts.sh`
Expected: FAIL — 파일 없음

- [ ] **Step 3: `prompts/roles/orchestrator.md` 작성**

```markdown
너는 프로젝트 관리자형 메인이다. 단순 분배자가 아니다.

## 책임 (9)
1. 업무 분담: 사용자 명령을 분해하고, 아래 "현재 팀 카탈로그"에서 적합한 워커를 골라 `workspace/tasks/<id>.md`(allowed_paths/forbidden_paths 포함)를 작성한 뒤 `bin/dispatch.sh <worker> <id>` 를 실행한다.
2. 완료 수신: `bin/wait-worker.sh <worker> <id>` 로 done 을 기다린다.
3. 리뷰 종합: `workspace/review/<worker>-<id>.*.md` 를 읽어 OK/VIOLATION·severity 를 종합한다.
4. 개입: VIOLATION(특히 severity=high) 시 해당 워커 pane 에 중단/수정을 send-keys 로 주입한다. 개입은 너만 한다(리뷰어는 보고만).
5. 산출물 연결: 사용자가 "이 PRD로 …" 처럼 이전 산출물을 지정하면, 다음 task 파일에 입력 경로를 명시한다.
6. 사용자 보고: 진행·결과·에스컬레이션을 사용자에게 종합 보고한다.
7. 진도 추적: 여러 task 상태를 `workspace/.harness-state` 에 기록·갱신한다.
8. 품질 게이트: 사용자가 이전 단계 리뷰 미통과 산출물을 다음 단계 입력으로 쓰려 하면 경고하고 확인을 요구한다(강제 차단은 하지 않는다 — 사용자 판단 존중).
9. 전체 맥락 유지: 단계별 결정·산출물을 `.harness-state` 에 보존하고 뒤 단계에서 참조한다.

## 금지
- 단계 자동 전이 금지. "PRD 끝났으니 구현 시작" 같은 판단을 하지 마라. 산출물 보고 후 사용자의 다음 명령을 기다린다. 단계 순서·전이는 전적으로 사용자가 통제한다.
- 워커를 새로 만들지 마라(고정 풀). 카탈로그 안에서만 배정한다.

## .harness-state
매 명령 처리 전 `workspace/.harness-state` 를 읽어 맥락을 복원하고, 처리 후 갱신한다. phase 는 사용자 명령에 따라서만 바꾼다(네가 임의 전이 금지).
```

- [ ] **Step 4: `prompts/roles/reviewer-{spec,quality,arch}.md` 작성**

`reviewer-spec.md`:

```markdown
너는 스펙·계획 준수 관점 리뷰어다. 워커를 조종하지 않는다 — 검사·보고만 한다.

## 약한 신호 (진행 중)
events.log 새 줄의 경로가 해당 task(`workspace/tasks/<id>.md`)의 allowed_paths 밖이거나 forbidden_paths 안이면 즉시 scope 위반이다. `workspace/review/<worker>-<id>.spec-rev.md` 에 verdict=VIOLATION, signal=weak, severity 로 기록한다. (진행 중 파일 내용 의미 판단은 하지 않는다 — 미완성이라 신뢰 불가)

## 강한 신호 (done 후)
events.log 에 `<worker> <id> done` 라인이 오면 `workspace/results/<id>.md` 와 산출물을 읽어 task 명세·완료기준 준수를 판정한다. 위배 시 verdict=VIOLATION, signal=strong 로 같은 경로에 기록한다. OK 면 verdict=OK 로 기록한다.
```

`reviewer-quality.md` (위와 동일 구조, 관점만 "코드 품질·안티패턴", 파일명 `.quality-rev.md`):

```markdown
너는 코드 품질·안티패턴 관점 리뷰어다. 워커를 조종하지 않는다 — 검사·보고만 한다.

## 약한 신호 (진행 중)
events.log 새 줄 경로가 task scope(allowed_paths/forbidden_paths) 위반이면 즉시 `workspace/review/<worker>-<id>.quality-rev.md` 에 verdict=VIOLATION, signal=weak, severity 기록. 진행 중 내용 의미 판단은 안 한다.

## 강한 신호 (done 후)
done 라인 후 `workspace/results/<id>.md`·산출물을 읽어 안티패턴·품질 문제(예: JWT 검증을 평문 비교)를 판정한다. 위배 시 verdict=VIOLATION, signal=strong, OK 면 verdict=OK 를 같은 경로에 기록.
```

`reviewer-arch.md` (관점 "아키텍처 일관성", 파일명 `.arch-rev.md`):

```markdown
너는 아키텍처 일관성 관점 리뷰어다. 워커를 조종하지 않는다 — 검사·보고만 한다.

## 약한 신호 (진행 중)
events.log 새 줄 경로가 task scope 위반이면 즉시 `workspace/review/<worker>-<id>.arch-rev.md` 에 verdict=VIOLATION, signal=weak, severity 기록. 진행 중 내용 의미 판단은 안 한다.

## 강한 신호 (done 후)
done 라인 후 `workspace/results/<id>.md`·산출물·관련 설계 문서를 읽어 아키텍처 일관성 위배를 판정한다. 위배 시 verdict=VIOLATION, signal=strong, OK 면 verdict=OK 를 같은 경로에 기록.
```

- [ ] **Step 5: `prompts/loop/reviewer.md` 작성** (`/loop`에 주입될 dynamic 감시 본문)

```markdown
감시 작업: workspace/.review-cursor.<나의리뷰어명> 의 숫자 N(없으면 0)을 읽고, workspace/events.log 의 0-based 라인 오프셋 N 부터 새 줄들을 읽어라. 각 새 줄에 대해 내 역할 프롬프트의 약한 신호 규칙(scope 위반 검사)을 적용하고, `done` 라인이면 강한 신호 규칙(결과물 의미 판정)을 적용하라. 위반/판정 결과를 workspace/review/ 에 기록하라. 처리 후 .review-cursor.<나의리뷰어명> 을 events.log 현재 총 줄 수로 갱신하라. 같은 (worker,path) 가 이번 처리 범위에 여러 번이면 scope 판정은 1회만 한다. 새 줄이 없으면 아무것도 하지 마라.
```

- [ ] **Step 6: `prompts/loop/orchestrator.md` 작성**

```markdown
관리 작업: workspace/review/ 디렉터리에 새 VIOLATION 파일이 있는지 확인하라. 있으면 해당 워커·task 를 파악해 severity 를 보고 개입 판단(high → 워커 pane 에 중단/수정 send-keys, low → .harness-state 기록 후 사용자 보고)을 하라. 처리한 review 파일은 .harness-state 에 처리 완료로 표시해 중복 개입을 막아라. 사용자의 새 명령이 있으면 그 명령을 우선 처리하라. 단계 자동 전이는 절대 하지 마라.
```

- [ ] **Step 7: 통과 확인**

Run: `bash tests/test-role-prompts.sh`
Expected: PASS — `ran=7 fail=0`

- [ ] **Step 8: run-all.sh 등록 + 전체 회귀**

`tests/run-all.sh`에 `test-role-prompts.sh` 추가.
Run: `bash tests/run-all.sh`
Expected: 전체 PASS

- [ ] **Step 9: Commit**

```bash
git add prompts/roles/ prompts/loop/ tests/test-role-prompts.sh tests/run-all.sh
git commit -m "feat: orchestrator·reviewer 역할/loop 프롬프트 (책임9·관점별·커서)"
```

---

### Task 11: 리뷰 커서 헬퍼 — `.review-cursor.<reviewer>` 증분·멱등

리뷰어 claude가 쓸 커서 read/write 를 셸 헬퍼로 제공(claude 가 호출, 무상태 보완). spec §5.7.

**Files:**
- Modify: `bin/lib.sh`
- Test: `tests/test-cursor.sh`
- Modify: `tests/run-all.sh`

- [ ] **Step 1: 실패 테스트 작성**

`tests/test-cursor.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"
source "$ROOT/bin/lib.sh"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export WORKSPACE="$TMP"
EV="$TMP/events.log"
printf 'l1\nl2\nl3\n' > "$EV"

# cursor_read <reviewer> → 없으면 0
assert_eq "0" "$(cursor_read specrev)" "초기 커서 0"

# cursor_new_lines <reviewer> <events.log> → 커서 이후 줄 출력, 커서 미변경
out="$(cursor_new_lines specrev "$EV")"
assert_eq "l1
l2
l3" "$out" "커서0 → 전체 3줄"

# cursor_commit <reviewer> <n> → 커서 갱신
cursor_commit specrev 3
assert_eq "3" "$(cursor_read specrev)" "커서 3 갱신"
out2="$(cursor_new_lines specrev "$EV")"
assert_eq "" "$out2" "커서3 → 새 줄 없음 (멱등)"

# 리뷰어별 독립
assert_eq "0" "$(cursor_read qualrev)" "다른 리뷰어 커서 독립(0)"

test_summary
```

- [ ] **Step 2: 실패 확인**

Run: `bash tests/test-cursor.sh`
Expected: FAIL — `cursor_read: command not found`

- [ ] **Step 3: `bin/lib.sh`에 커서 헬퍼 추가**

```bash
# 리뷰 커서 (spec §5.7). claude 무상태 보완 — 리뷰어가 호출해 증분·멱등.
_cursor_file() { printf '%s/.review-cursor.%s' "${WORKSPACE}" "$1"; }

cursor_read() {  # $1=reviewer → 현재 커서(없으면 0)
  local f; f="$(_cursor_file "$1")"
  if [ -f "$f" ]; then cat "$f"; else echo 0; fi
}

cursor_new_lines() {  # $1=reviewer $2=events.log → 커서 이후 줄 출력 (커서 불변)
  local n; n="$(cursor_read "$1")"
  tail -n +"$((n + 1))" "$2" 2>/dev/null || true
}

cursor_commit() {  # $1=reviewer $2=새 커서값
  printf '%s' "$2" > "$(_cursor_file "$1")"
}
```

- [ ] **Step 4: 통과 확인**

Run: `bash tests/test-cursor.sh`
Expected: PASS — `ran=5 fail=0`

- [ ] **Step 5: run-all.sh 등록 + 회귀**

`tests/run-all.sh`에 `test-cursor.sh` 추가.
Run: `bash tests/run-all.sh`
Expected: 전체 PASS

- [ ] **Step 6: Commit**

```bash
git add bin/lib.sh tests/test-cursor.sh tests/run-all.sh
git commit -m "feat: 리뷰 커서 헬퍼 cursor_read/new_lines/commit (증분·멱등)"
```

---

### Task 12: harness-state 헬퍼 — 메인 진도·맥락 (B-4)

spec §5.8. 메인 claude 가 호출하는 read/갱신 헬퍼.

**Files:**
- Modify: `bin/lib.sh`
- Test: `tests/test-harness-state.sh`
- Modify: `tests/run-all.sh`

- [ ] **Step 1: 실패 테스트 작성**

`tests/test-harness-state.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"
source "$ROOT/bin/lib.sh"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export WORKSPACE="$TMP"

# 초기: 파일 없음 → state_get 빈값
assert_eq "" "$(state_get phase)" "초기 phase 빈값"

# state_set 후 read 멱등
state_set phase architecture
assert_eq "architecture" "$(state_get phase)" "phase 기록·복원"
state_set phase implementation
assert_eq "implementation" "$(state_get phase)" "phase 갱신(사용자 명령 반영)"

# 다른 키 독립
state_set last_task 101
assert_eq "101" "$(state_get last_task)" "다른 키 독립 보존"
assert_eq "implementation" "$(state_get phase)" "기존 키 유지"

test_summary
```

- [ ] **Step 2: 실패 확인**

Run: `bash tests/test-harness-state.sh`
Expected: FAIL — `state_get: command not found`

- [ ] **Step 3: `bin/lib.sh`에 harness-state 헬퍼 추가**

```bash
# 메인 상태 (spec §5.8, B-4). key=value 평문(파싱 단순·셸 친화). claude 무상태 보완.
_state_file() { printf '%s/.harness-state' "${WORKSPACE}"; }

state_get() {  # $1=key → value (없으면 빈문자열)
  local f; f="$(_state_file)"
  [ -f "$f" ] || return 0
  local line; line="$(grep -m1 "^$1=" "$f" 2>/dev/null || true)"
  printf '%s' "${line#*=}"
}

state_set() {  # $1=key $2=value (있으면 교체, 없으면 추가)
  local f; f="$(_state_file)" key="$1" val="$2"
  touch "$f"
  if grep -q "^$key=" "$f" 2>/dev/null; then
    grep -v "^$key=" "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  fi
  printf '%s=%s\n' "$key" "$val" >> "$f"
}
```

- [ ] **Step 4: 통과 확인**

Run: `bash tests/test-harness-state.sh`
Expected: PASS — `ran=5 fail=0`

- [ ] **Step 5: run-all.sh 등록 + 회귀**

`tests/run-all.sh`에 `test-harness-state.sh` 추가.
Run: `bash tests/run-all.sh`
Expected: 전체 PASS

- [ ] **Step 6: Commit**

```bash
git add bin/lib.sh tests/test-harness-state.sh tests/run-all.sh
git commit -m "feat: harness-state 헬퍼 state_get/set (메인 진도·맥락, B-4)"
```

---

### Task 13: events.log 파싱 + 디바운스 헬퍼

spec §5.2·§5.5. 5필드 파싱, 파손 라인 skip, 1회 처리 범위 내 (worker,path) 접기.

**Files:**
- Modify: `bin/lib.sh`
- Test: `tests/test-events-log.sh`, `tests/test-debounce.sh`
- Modify: `tests/run-all.sh`

- [ ] **Step 1: 실패 테스트 작성 (파싱)**

`tests/test-events-log.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"
source "$ROOT/bin/lib.sh"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
EV="$TMP/e.log"
printf 'TS\tdev\t101\tmodify\tsrc/a.ts\n' >  "$EV"
printf 'BROKEN LINE NO TABS\n'            >> "$EV"
printf 'TS\tarch\t102\tdone\t-\n'         >> "$EV"

# event_field <line> <n> → n번째 탭 필드
line1="$(sed -n 1p "$EV")"
assert_eq "dev" "$(event_field "$line1" 2)" "필드2=worker"
assert_eq "modify" "$(event_field "$line1" 4)" "필드4=action"

# event_valid <line> → 5필드면 0, 아니면 1
event_valid "$line1"; assert_success "$?" "정상 5필드 valid"
event_valid "BROKEN LINE NO TABS"; assert_fail "$?" "파손 라인 invalid"

# events_each <file> 는 valid 라인만 콜백 (파손 skip)
cnt="$(events_valid_count "$EV")"
assert_eq "2" "$cnt" "파손 1줄 skip → valid 2줄"

test_summary
```

- [ ] **Step 2: 실패 확인**

Run: `bash tests/test-events-log.sh`
Expected: FAIL — `event_field: command not found`

- [ ] **Step 3: `bin/lib.sh`에 파싱 헬퍼 추가**

```bash
# events.log 파싱 (spec §5.2). 탭 5필드: ts worker task action path.
event_field() {  # $1=line $2=fieldno(1-5)
  printf '%s' "$1" | awk -F'\t' -v n="$2" '{print $n}'
}

event_valid() {  # $1=line → 정확히 5필드면 0
  local nf; nf="$(printf '%s' "$1" | awk -F'\t' '{print NF}')"
  [ "$nf" = "5" ]
}

events_valid_count() {  # $1=file → valid 라인 수
  local c=0 line
  while IFS= read -r line; do
    event_valid "$line" && c=$((c + 1))
  done < "$1"
  printf '%s' "$c"
}
```

- [ ] **Step 4: 통과 확인**

Run: `bash tests/test-events-log.sh`
Expected: PASS — `ran=5 fail=0`

- [ ] **Step 5: 실패 테스트 작성 (디바운스)**

`tests/test-debounce.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"
source "$ROOT/bin/lib.sh"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
EV="$TMP/e.log"
# 같은 (dev, src/a.ts) 3번 + 다른 path 1번 + 다른 worker 같은 path 1번
printf 'T\tdev\t1\tmodify\tsrc/a.ts\n'  >  "$EV"
printf 'T\tdev\t1\tmodify\tsrc/a.ts\n'  >> "$EV"
printf 'T\tdev\t1\tmodify\tsrc/b.ts\n'  >> "$EV"
printf 'T\tdev\t1\tmodify\tsrc/a.ts\n'  >> "$EV"
printf 'T\ttest\t2\tmodify\tsrc/a.ts\n' >> "$EV"

# debounce_pairs <file> → 유니크 (worker,path) 줄 (1회 처리범위 접기)
out="$(debounce_pairs "$EV" | sort)"
expected="dev	src/a.ts
dev	src/b.ts
test	src/a.ts"
assert_eq "$expected" "$out" "(worker,path) 3쌍으로 접힘 (dev/a 3→1)"

test_summary
```

- [ ] **Step 6: 디바운스 헬퍼 추가**

`bin/lib.sh`에 추가:

```bash
# 디바운스 (spec §5.5): 처리 범위 내 유니크 (worker,path). valid 라인만.
debounce_pairs() {  # $1=file → "worker\tpath" 유니크
  local line w p
  while IFS= read -r line; do
    event_valid "$line" || continue
    w="$(event_field "$line" 2)"; p="$(event_field "$line" 5)"
    printf '%s\t%s\n' "$w" "$p"
  done < "$1" | awk '!seen[$0]++'
}
```

- [ ] **Step 7: 통과 확인**

Run: `bash tests/test-debounce.sh`
Expected: PASS — `ran=1 fail=0`

- [ ] **Step 8: run-all.sh 등록 + 전체 회귀**

`tests/run-all.sh`에 `test-events-log.sh`·`test-debounce.sh` 추가.
Run: `bash tests/run-all.sh`
Expected: 전체 PASS

- [ ] **Step 9: Commit**

```bash
git add bin/lib.sh tests/test-events-log.sh tests/test-debounce.sh tests/run-all.sh
git commit -m "feat: events.log 파싱·디바운스 헬퍼 (§5.2·§5.5)"
```

---

### Task 14: 리뷰 종합 헬퍼 — review/*.md 판정 집계

spec §5.4·§6. 메인이 review 파일들을 종합해 통과/중단을 판단하는 헬퍼.

**Files:**
- Modify: `bin/lib.sh`
- Test: `tests/test-review-flow.sh`
- Modify: `tests/run-all.sh`

- [ ] **Step 1: 실패 테스트 작성**

`tests/test-review-flow.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"
source "$ROOT/bin/lib.sh"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
RV="$TMP/review"; mkdir -p "$RV"

mkfile() {  # $1=name $2=verdict $3=severity
  printf -- '---\nverdict: %s\nseverity: %s\n---\n' "$2" "$3" > "$RV/$1"
}

# 리뷰어 3개, 모두 OK → 종합 OK
mkfile "dev-1.spec-rev.md" OK low
mkfile "dev-1.quality-rev.md" OK low
mkfile "dev-1.arch-rev.md" OK low
assert_eq "OK" "$(review_verdict "$RV" dev 1)" "전 OK → 종합 OK"

# 하나라도 VIOLATION high → 종합 VIOLATION
mkfile "dev-1.quality-rev.md" VIOLATION high
assert_eq "VIOLATION" "$(review_verdict "$RV" dev 1)" "high 1개 → 종합 VIOLATION"

# 덮어쓰기 없음: 3개 파일 공존 확인
n="$(ls "$RV"/dev-1.*.md | wc -l | tr -d ' ')"
assert_eq "3" "$n" "리뷰어 3파일 공존(덮어쓰기 없음)"

# 다른 worker-id 격리
mkfile "test-2.spec-rev.md" OK low
assert_eq "OK" "$(review_verdict "$RV" test 2)" "다른 task 격리"
assert_eq "VIOLATION" "$(review_verdict "$RV" dev 1)" "기존 task 영향 없음"

test_summary
```

- [ ] **Step 2: 실패 확인**

Run: `bash tests/test-review-flow.sh`
Expected: FAIL — `review_verdict: command not found`

- [ ] **Step 3: `bin/lib.sh`에 종합 헬퍼 추가**

```bash
# 리뷰 종합 (spec §5.4·§6): review/<worker>-<id>.*.md 중 하나라도
# VIOLATION 이면 VIOLATION, 전부 OK 면 OK, 파일 없으면 PENDING.
review_verdict() {  # $1=review디렉터리 $2=worker $3=id
  local dir="$1" w="$2" id="$3" f found=0 v
  for f in "$dir/$w-$id."*.md; do
    [ -f "$f" ] || continue
    found=1
    v="$(grep -m1 '^verdict:' "$f" | awk '{print $2}')"
    if [ "$v" = "VIOLATION" ]; then printf 'VIOLATION'; return 0; fi
  done
  if [ "$found" = "1" ]; then printf 'OK'; else printf 'PENDING'; fi
}
```

- [ ] **Step 4: 통과 확인**

Run: `bash tests/test-review-flow.sh`
Expected: PASS — `ran=5 fail=0`

- [ ] **Step 5: run-all.sh 등록 + 회귀**

`tests/run-all.sh`에 `test-review-flow.sh` 추가.
Run: `bash tests/run-all.sh`
Expected: 전체 PASS

- [ ] **Step 6: Commit**

```bash
git add bin/lib.sh tests/test-review-flow.sh tests/run-all.sh
git commit -m "feat: review_verdict 리뷰 종합 헬퍼 (§5.4·§6)"
```

---

### Task 15: 시그널 유실 안전장치 — done 라인 폴링

spec §6 "시그널 유실". 메인이 wait-for 와 병행으로 events.log done 라인 확인.

**Files:**
- Modify: `bin/lib.sh`
- Test: `tests/test-signal-fallback.sh`
- Modify: `tests/run-all.sh`

- [ ] **Step 1: 실패 테스트 작성**

`tests/test-signal-fallback.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"
source "$ROOT/bin/lib.sh"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
EV="$TMP/e.log"; : > "$EV"

# done_logged <file> <worker> <id> → done 라인 있으면 0
done_logged "$EV" dev 101; assert_fail "$?" "done 라인 없음 → 미완료"

printf 'T\tdev\t101\tmodify\tsrc/a.ts\n' >> "$EV"
done_logged "$EV" dev 101; assert_fail "$?" "modify 만으론 미완료"

printf 'T\tdev\t101\tdone\t-\n' >> "$EV"
done_logged "$EV" dev 101; assert_success "$?" "done 라인 있음 → 완료"

# 다른 worker-id 격리
done_logged "$EV" dev 999; assert_fail "$?" "다른 id 는 미완료"

# 멱등: 두 번 호출해도 같은 결과
done_logged "$EV" dev 101; assert_success "$?" "재호출 멱등"

test_summary
```

- [ ] **Step 2: 실패 확인**

Run: `bash tests/test-signal-fallback.sh`
Expected: FAIL — `done_logged: command not found`

- [ ] **Step 3: `bin/lib.sh`에 추가**

```bash
# 시그널 유실 안전장치 (spec §6). wait-for 가 메인 대기 전 발화해도
# events.log 의 done 라인으로 완료를 확정 (멱등).
done_logged() {  # $1=events.log $2=worker $3=id → done 라인 있으면 0
  [ -f "$1" ] || return 1
  awk -F'\t' -v w="$2" -v id="$3" \
    '$2==w && $3==id && $4=="done"{f=1} END{exit f?0:1}' "$1"
}
```

- [ ] **Step 4: 통과 확인**

Run: `bash tests/test-signal-fallback.sh`
Expected: PASS — `ran=5 fail=0`

- [ ] **Step 5: run-all.sh 등록 + 회귀**

`tests/run-all.sh`에 `test-signal-fallback.sh` 추가.
Run: `bash tests/run-all.sh`
Expected: 전체 PASS

- [ ] **Step 6: Commit**

```bash
git add bin/lib.sh tests/test-signal-fallback.sh tests/run-all.sh
git commit -m "feat: done_logged 시그널 유실 안전장치 (§6)"
```

---

### Task 16: E2E — 디스패치→통지→감시→보고→종합 (dummy)

spec §8 `test-e2e-harness.sh`. claude 미기동 — dummy 워커/리뷰어가 파일·시그널만 흉내.

**Files:**
- Test: `tests/test-e2e-harness.sh`
- Modify: `tests/run-all.sh`

- [ ] **Step 1: E2E 테스트 작성**

`tests/test-e2e-harness.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"
source "$ROOT/bin/lib.sh"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export WORKSPACE="$TMP"
mkdir -p "$TMP/tasks" "$TMP/results" "$TMP/review"
EV="$TMP/events.log"; : > "$EV"

# 1. 메인: task 작성 (scope 포함)
cat > "$TMP/tasks/1.md" <<'T'
---
id: 1
worker: dev
allowed_paths:
  - src/auth/**
forbidden_paths:
  - src/payment/**
---
auth 구현
T

# 2. dummy 워커: 정상 변경 + scope 위반 + done
printf 'T\tdev\t1\tmodify\tsrc/auth/login.ts\n'   >> "$EV"
printf 'T\tdev\t1\tmodify\tsrc/payment/charge.ts\n' >> "$EV"   # 위반
printf 'T\tdev\t1\tdone\t-\n'                     >> "$EV"

# 3. dummy 리뷰어: events.log 새 줄을 커서로 읽고 scope 검사 → review 기록
cur="$(cursor_read qrev)"
while IFS= read -r line; do
  event_valid "$line" || continue
  act="$(event_field "$line" 4)"; p="$(event_field "$line" 5)"
  [ "$act" = "done" ] && continue
  if scope_match "$p" "src/payment/**"; then
    printf -- '---\nverdict: VIOLATION\nseverity: high\nsignal: weak\n---\n%s\n' "$p" \
      > "$TMP/review/dev-1.qrev.md"
  fi
done < <(cursor_new_lines qrev "$EV")
cursor_commit qrev "$(wc -l < "$EV" | tr -d ' ')"

# 4. 검증: scope 위반 잡힘
assert_success "$([ -f "$TMP/review/dev-1.qrev.md" ]; echo $?)" "scope 위반 review 생성"
assert_eq "VIOLATION" "$(review_verdict "$TMP/review" dev 1)" "종합 VIOLATION"

# 5. done 안전장치
done_logged "$EV" dev 1; assert_success "$?" "done 라인 감지"

# 6. 커서 멱등: 재처리 시 새 줄 없음
assert_eq "" "$(cursor_new_lines qrev "$EV")" "커서 멱등(새 줄 없음)"

# 7. team-down 정리 시뮬: results 보존, events/cursor/review 정리 대상
echo "결과" > "$TMP/results/1.md"
assert_success "$([ -f "$TMP/results/1.md" ]; echo $?)" "results 보존 대상 존재"

test_summary
```

- [ ] **Step 2: 실행 → 통과 확인**

Run: `bash tests/test-e2e-harness.sh`
Expected: PASS — `ran=5 fail=0` (전 경로 메커니즘 통합 동작)

- [ ] **Step 3: run-all.sh 등록 + 전체 회귀**

`tests/run-all.sh`에 `test-e2e-harness.sh` 추가.
Run: `bash tests/run-all.sh`
Expected: 전체 PASS (기존 8 + 신규 12 = 20 스위트)

- [ ] **Step 4: team-down.sh 정리 대상 확장**

`bin/team-down.sh`에서 `workspace/.boot/*.md` 정리 부분을 찾아, 같은 정리 블록에 추가(results/tasks 보존, 나머지 정리):

```bash
rm -f "$WORKSPACE"/events.log "$WORKSPACE"/.review-cursor.* "$WORKSPACE"/.harness-state 2>/dev/null || true
rm -rf "$WORKSPACE"/review 2>/dev/null || true
```

- [ ] **Step 5: team-down 회귀**

Run: `bash tests/test-team-down.sh`
Expected: 기존 PASS (results/tasks 보존 + 신규 정리 대상이 멱등)

- [ ] **Step 6: Commit**

```bash
git add tests/test-e2e-harness.sh tests/run-all.sh bin/team-down.sh
git commit -m "feat: E2E 통합 테스트 + team-down 하네스 정리 대상 확장"
```

---

### Task 17: 최종 검증 + README

**Files:**
- Modify: `README.md`

- [ ] **Step 1: 전체 테스트**

Run: `bash tests/run-all.sh`
Expected: 전체 PASS (기존 8 + 신규 12 스위트, 모든 어서션 통과)

- [ ] **Step 2: probe 재현 (선택, 수동)**

Run: `bash tests/probes/probe-loop.sh`
Expected: `[probe-loop] PASS` (회귀 — `/loop`+Monitor 여전히 동작)

- [ ] **Step 3: `README.md`에 하네스 섹션 추가**

`README.md` 끝에 추가:

```markdown

## 에이전트 하네스 (2차)

판단형 메인(프로젝트 관리자) + `/loop`·Monitor 상주 감시 리뷰어 + scope 사전차단 + 모델 차등.

- 가동: `bin/team-up.sh feature-team` (워커 + review 윈도우 + 모델 차등)
- 메인은 단계 자동 전이 안 함 — 사용자가 PRD→Arch→구현 단계를 수동 진행
- 감시: 약한 신호(scope, 즉시) / 강한 신호(done 후 의미 판정)
- 설계: `docs/superpowers/specs/2026-05-19-agent-harness-design.md`
- 실측 프로브(claude 기동): `tests/probes/probe-{loop,hook}.sh` (수동)
```

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs: README 에이전트 하네스 섹션"
```

- [ ] **Step 5: 최종 리뷰 후 finishing-a-development-branch**

전체 구현 완료. `superpowers:finishing-a-development-branch` 스킬로 브랜치 마무리(테스트 검증 → 머지/PR 선택).

---

## Self-Review (계획 작성자 점검)

**1. Spec coverage:**
- §3.1 2윈도우 → T8 ✓ / §3.2 프로파일 고정 → T9 ✓ / §4.1 메인 책임 9개 → T10 orchestrator.md ✓ / §4.3 리뷰어 약한·강한 → T10 reviewer-*.md ✓ / §5.1 scope glob → T4 ✓ / §5.2 events.log 파싱 → T13 ✓ / §5.4 review 종합 → T14 ✓ / §5.5 디바운스 → T13 ✓ / §5.6 hook → T1·T6 ✓ / §5.7 커서 → T11 ✓ / §5.8 harness-state → T12 ✓ / §6 시그널 유실 → T15, 이슈1·2·3 → T2·T3·T5 ✓ / §7.1 모델 차등 → T8·T9 ✓ / §7.2 codex 분기점 → T8 agent_cmd_for ✓ / §8 테스트 12 → T2~T16 ✓ / §8.1 프로브 → T1 ✓
- 갭 없음.

**2. Placeholder scan:** "TODO/TBD/적절히" 없음. 모든 코드 step에 완전한 코드 블록. T6는 probe 결과 분기를 명시(가지치기 조건 구체화)했으므로 placeholder 아님.

**3. Type consistency:** `resolve_session`(T2)→`target_in`(T3)→dispatch(T5) 일관. `parse_entry`/`ENTRY_NAME/ROLE/MODEL`(T8) 일관. `cursor_read/new_lines/commit`(T11) ↔ e2e(T16) 시그니처 일치. `scope_match`(T4) ↔ reviewer.md(T10)·e2e(T16) 일치. `review_verdict`(T14) ↔ e2e 일치. `event_field/valid`(T13) ↔ e2e 일치. `done_logged`(T15) ↔ e2e 일치. 불일치 없음.
