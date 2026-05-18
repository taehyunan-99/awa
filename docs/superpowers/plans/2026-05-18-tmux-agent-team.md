# tmux 멀티 에이전트 팀 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** tmux 페인마다 Claude Code 인스턴스를 띄우고 역할/제약을 부여해 1 오케스트레이터 + N 워커 멀티 에이전트 팀을 셸 스크립트로 재현 가능하게 운영한다.

**Architecture:** 의존성 zero 셸 스크립트. `profiles/*.sh`가 팀 구성을 정의(데이터), `bin/*.sh`가 고정 로직. 명령 주입은 `tmux send-keys -l`, 완료 동기화는 `tmux wait-for`, 결과 전달은 `workspace/results/*.md` 파일. 세션은 일회용 — git 관리되는 정의로부터 매번 재생성.

**Tech Stack:** bash, tmux 3.6+, claude CLI. 테스트는 외부 의존성 없는 순수 bash 어서션 하니스 + 실제 tmux 세션 통합 테스트.

---

## 파일 구조

생성할 파일과 책임:

| 파일 | 책임 |
|---|---|
| `.gitignore` | `workspace/` 런타임 산출물 제외 |
| `tests/assert.sh` | 의존성 zero 테스트 어서션/러너 (다른 테스트가 source) |
| `tests/run-all.sh` | `tests/test-*.sh` 전부 실행하는 진입점 |
| `bin/lib.sh` | 공통 함수: `target_of`, `boot_file`, `send_prompt`, `session_exists`, 경로 상수 |
| `profiles/default.sh` | 기본 팀 정의 (dev/review/test) |
| `profiles/code-review.sh` | 리뷰 팀 정의 (reviewer×2 + security) |
| `profiles/research.sh` | 리서치 팀 정의 (researcher×3) |
| `prompts/_common.md` | 모든 워커 공통 규약 |
| `prompts/roles/{dev,reviewer,tester,security,researcher}.md` | 역할별 규약 |
| `bin/team-up.sh` | 프로파일 읽고 세션/페인 생성, 부트스트랩 주입 |
| `bin/dispatch.sh` | 워커에 `TASK <id>` 주입 |
| `bin/wait-worker.sh` | `wait-for` 블로킹 대기 (timeout 래핑) |
| `bin/team-down.sh` | 세션 kill + `.boot/` 정리 |
| `README.md` | 사용법, 아키텍처, 전제 |

테스트 전략: 순수 로직 함수(`lib.sh`)는 단위 테스트. 세션 생성/주입/대기는 실제 tmux 세션을 띄우되 워커 명령을 `claude` 대신 `cat`/`bash` 같은 더미로 치환해 통합 테스트한다 (claude 실행을 환경변수로 오버라이드 가능하게 설계).

---

## Task 1: 프로젝트 골격 + 테스트 하니스

**Files:**
- Create: `.gitignore`
- Create: `tests/assert.sh`
- Create: `tests/run-all.sh`
- Create: `workspace/.gitkeep`

- [ ] **Step 1: .gitignore 작성**

Create `.gitignore`:

```gitignore
# 런타임 산출물 — 정의가 아닌 결과물
workspace/tasks/
workspace/results/
workspace/.boot/
*.log
.DS_Store
```

- [ ] **Step 2: 테스트 어서션 하니스 작성**

Create `tests/assert.sh`:

```bash
#!/usr/bin/env bash
# 의존성 zero 테스트 어서션. 각 test-*.sh 가 source 한다.

_TESTS_RUN=0
_TESTS_FAIL=0

assert_eq() {
  local expected="$1" actual="$2" msg="${3:-}"
  _TESTS_RUN=$((_TESTS_RUN + 1))
  if [ "$expected" = "$actual" ]; then
    echo "  ok: ${msg:-assert_eq}"
  else
    _TESTS_FAIL=$((_TESTS_FAIL + 1))
    echo "  FAIL: ${msg:-assert_eq}"
    echo "    expected: [$expected]"
    echo "    actual:   [$actual]"
  fi
}

assert_contains() {
  local haystack="$1" needle="$2" msg="${3:-}"
  _TESTS_RUN=$((_TESTS_RUN + 1))
  if printf '%s' "$haystack" | grep -qF -- "$needle"; then
    echo "  ok: ${msg:-assert_contains}"
  else
    _TESTS_FAIL=$((_TESTS_FAIL + 1))
    echo "  FAIL: ${msg:-assert_contains}"
    echo "    needle [$needle] not found in:"
    echo "    [$haystack]"
  fi
}

assert_success() {
  local msg="${1:-assert_success}"
  _TESTS_RUN=$((_TESTS_RUN + 1))
  if [ "$?" -eq 0 ]; then
    echo "  ok: $msg"
  else
    _TESTS_FAIL=$((_TESTS_FAIL + 1))
    echo "  FAIL: $msg (exit non-zero)"
  fi
}

assert_fail() {
  # 직전 명령이 실패(비-0)했어야 함
  local rc="$1" msg="${2:-assert_fail}"
  _TESTS_RUN=$((_TESTS_RUN + 1))
  if [ "$rc" -ne 0 ]; then
    echo "  ok: $msg"
  else
    _TESTS_FAIL=$((_TESTS_FAIL + 1))
    echo "  FAIL: $msg (expected non-zero exit, got 0)"
  fi
}

test_summary() {
  echo "----"
  echo "ran=$_TESTS_RUN fail=$_TESTS_FAIL"
  [ "$_TESTS_FAIL" -eq 0 ]
}
```

- [ ] **Step 3: 테스트 러너 작성**

Create `tests/run-all.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"

total_fail=0
for t in test-*.sh; do
  [ -e "$t" ] || continue
  echo "=== $t ==="
  bash "$t"
  rc=$?
  [ "$rc" -ne 0 ] && total_fail=$((total_fail + 1))
done

echo "===================="
if [ "$total_fail" -eq 0 ]; then
  echo "ALL SUITES PASSED"
  exit 0
else
  echo "$total_fail SUITE(S) FAILED"
  exit 1
fi
```

- [ ] **Step 4: workspace 디렉토리 유지 파일**

Create `workspace/.gitkeep` (빈 파일).

- [ ] **Step 5: 하니스 자체 동작 확인**

Create temporary `tests/test-harness.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh

assert_eq "a" "a" "동일 문자열 통과"
assert_contains "hello world" "wor" "부분 문자열 통과"
(exit 3); assert_fail "$?" "비-0 종료 감지"

test_summary
```

Run: `bash tests/run-all.sh`
Expected: `=== test-harness.sh ===` 아래 3개 `ok:`, 마지막 `ALL SUITES PASSED`, exit 0

- [ ] **Step 6: 임시 하니스 테스트 제거**

Run: `rm tests/test-harness.sh`
(하니스 검증용이었으므로 제거. 이후 실제 테스트가 들어온다.)

- [ ] **Step 7: 실행 권한 + 커밋**

```bash
chmod +x tests/run-all.sh
git add .gitignore tests/assert.sh tests/run-all.sh workspace/.gitkeep
git commit -m "chore: 프로젝트 골격 + 의존성 zero 테스트 하니스"
```

---

## Task 2: lib.sh 경로 상수와 target_of / boot_file

**Files:**
- Create: `bin/lib.sh`
- Test: `tests/test-lib-paths.sh`

`lib.sh`는 `bin/`에 위치하며, 자신의 위치 기준으로 repo 루트를 계산한다. `target_of <idx>`는 페인 인덱스를 tmux target 문자열로, `boot_file <worker>`는 워커 부트스트랩 파일 경로를 돌려준다.

> **중요:** `target_of`는 `SESSION` 변수를 우선 사용하고 없으면 `SESSION_DEFAULT`로 폴백한다(`${SESSION:-$SESSION_DEFAULT}`). 이로써 `team-up.sh`/`dispatch.sh`/`wait-worker.sh`가 `SESSION="${SESSION_OVERRIDE:-...}"`로 설정한 활성 세션을 존중하여 세션 오버라이드/멀티팀을 지원한다. `SESSION_DEFAULT` 하드코딩은 세션 오버라이드를 무시해 target 불일치를 일으키므로 금지.

- [ ] **Step 1: 실패하는 테스트 작성**

Create `tests/test-lib-paths.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh

ROOT="$(cd .. && pwd)"
source "$ROOT/bin/lib.sh"

assert_eq "$ROOT" "$REPO_ROOT" "REPO_ROOT 가 repo 루트"
assert_eq "$ROOT/workspace" "$WORKSPACE" "WORKSPACE 경로"
assert_eq "agents" "$SESSION_DEFAULT" "기본 세션명"

# SESSION 미설정 → SESSION_DEFAULT 폴백
assert_eq "agents:0.2" "$(target_of 2)" "SESSION 미설정 → 기본 세션"
assert_eq "agents:0.4" "$(target_of 4)" "페인 인덱스 4 → target"

# SESSION 설정 → 활성 세션 존중 (세션 오버라이드/멀티팀)
SESSION=myteam
assert_eq "myteam:0.3" "$(target_of 3)" "SESSION 설정 → 활성 세션 존중"
unset SESSION

assert_eq "$ROOT/workspace/.boot/dev.md" "$(boot_file dev)" "boot_file 경로"

test_summary
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `bash tests/test-lib-paths.sh`
Expected: FAIL — `bin/lib.sh` 없음 (`source: No such file`) 또는 함수 미정의

- [ ] **Step 3: lib.sh 최소 구현**

Create `bin/lib.sh`:

```bash
#!/usr/bin/env bash
# 공통 함수/상수. 각 bin 스크립트가 source 한다.
# 직접 실행용 아님.

# 이 파일(bin/lib.sh) 기준으로 repo 루트 계산
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$_LIB_DIR/.." && pwd)"
WORKSPACE="$REPO_ROOT/workspace"
SESSION_DEFAULT="agents"

# 페인 인덱스 → tmux target (session:window.pane).
# 활성 세션(SESSION 변수, 없으면 SESSION_DEFAULT) 기준 — 세션 오버라이드/멀티팀 지원.
# 윈도우 0 고정. pane 1 은 오케스트레이터, 워커는 2 부터.
target_of() {
  local idx="$1"
  printf '%s:0.%s' "${SESSION:-$SESSION_DEFAULT}" "$idx"
}

# 워커 이름 → 부트스트랩 합본 파일 경로
boot_file() {
  local worker="$1"
  printf '%s/.boot/%s.md' "$WORKSPACE" "$worker"
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `bash tests/test-lib-paths.sh`
Expected: 7개 `ok:`, `ran=7 fail=0`, exit 0

- [ ] **Step 5: 커밋**

```bash
git add bin/lib.sh tests/test-lib-paths.sh
git commit -m "feat: lib.sh 경로 상수 + target_of/boot_file"
```

---

## Task 3: lib.sh send_prompt / session_exists

**Files:**
- Modify: `bin/lib.sh`
- Test: `tests/test-lib-tmux.sh`

`send_prompt`는 spec §4.1대로 텍스트와 Enter를 분리 주입한다. `session_exists`는 세션 유무를 종료코드로 반환한다. 실제 tmux 세션을 띄워 검증한다.

- [ ] **Step 1: 실패하는 테스트 작성**

Create `tests/test-lib-tmux.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh

ROOT="$(cd .. && pwd)"
source "$ROOT/bin/lib.sh"

TS="libtest_$$"

# session_exists: 없을 때 비-0
if session_exists "$TS"; then rc=0; else rc=1; fi
assert_eq "1" "$rc" "없는 세션 → session_exists 비-0"

# 더미 세션: 첫 페인에서 cat 이 입력을 파일로 기록.
# 전역 tmux 설정과 무관하게 fix_session_indexing 으로 세션 로컬 인덱스 고정.
OUT="$(mktemp)"
tmux new-session -d -s "$TS" -x 80 -y 24 "bash -c 'cat > $OUT'"
fix_session_indexing "$TS"
sleep 0.3

if session_exists "$TS"; then rc=0; else rc=1; fi
assert_eq "0" "$rc" "있는 세션 → session_exists 0"

# 인덱스 규약 검증: window 0 / pane 1 이 실제로 존재해야 함
WIN="$(tmux list-windows -t "$TS" -F '#{window_index}' | head -1)"
assert_eq "0" "$WIN" "세션 로컬 window base-index=0 적용됨"
PANE="$(tmux list-panes -t "$TS:0" -F '#{pane_index}' | head -1)"
assert_eq "1" "$PANE" "세션 로컬 pane-base-index=1 적용됨"

# send_prompt 로 텍스트 주입 (특수문자 포함). target_of 사용.
send_prompt "$TS:0.1" 'hello "world" $X'
sleep 0.3
tmux send-keys -t "$TS:0.1" C-d
sleep 0.3

GOT="$(cat "$OUT")"
assert_eq 'hello "world" $X' "$GOT" "send_prompt 가 리터럴 텍스트+개행 주입"

tmux kill-session -t "$TS" 2>/dev/null || true
rm -f "$OUT"

test_summary
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `bash tests/test-lib-tmux.sh`
Expected: FAIL — `session_exists`/`send_prompt`/`fix_session_indexing` 미정의 또는 window 0 어서션 실패

- [ ] **Step 3: lib.sh에 함수 추가**

Append to `bin/lib.sh`:

```bash
# 세션 존재 여부. 존재하면 0, 아니면 비-0.
session_exists() {
  local s="${1:-$SESSION_DEFAULT}"
  tmux has-session -t "$s" 2>/dev/null
}

# 프롬프트 안전 주입: 텍스트(리터럴)와 Enter 분리. spec §4.1.
send_prompt() {
  local target="$1" text="$2"
  tmux send-keys -t "$target" -l "$text"
  tmux send-keys -t "$target" Enter
}

# 세션 로컬로 인덱스 규약 고정. 전역 ~/.tmux.conf 설정에 비의존.
# 인자: 세션명. window base-index=0, pane-base-index=1 강제.
fix_session_indexing() {
  local s="$1"
  tmux set-option -t "$s" base-index 0 2>/dev/null || true
  tmux set-option -t "$s" pane-base-index 1 2>/dev/null || true
  # 이미 만들어진 윈도우/페인에도 즉시 반영되도록 재정렬
  tmux move-window -r -s "$s" 2>/dev/null || true
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `bash tests/test-lib-tmux.sh`
Expected: 5개 `ok:` (없는세션 / 있는세션 / window0 / pane1 / send_prompt), `ran=5 fail=0`, exit 0

- [ ] **Step 5: 커밋**

```bash
git add bin/lib.sh tests/test-lib-tmux.sh
git commit -m "feat: lib.sh session_exists + send_prompt (텍스트/Enter 분리)"
```

---

## Task 4: 프로파일 + 프롬프트 정의 파일

**Files:**
- Create: `profiles/default.sh`
- Create: `profiles/code-review.sh`
- Create: `profiles/research.sh`
- Create: `prompts/_common.md`
- Create: `prompts/roles/dev.md`
- Create: `prompts/roles/reviewer.md`
- Create: `prompts/roles/tester.md`
- Create: `prompts/roles/security.md`
- Create: `prompts/roles/researcher.md`
- Test: `tests/test-profiles.sh`

- [ ] **Step 1: 실패하는 테스트 작성**

Create `tests/test-profiles.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh

ROOT="$(cd .. && pwd)"

# default 프로파일 source 후 변수 검증
( source "$ROOT/profiles/default.sh"
  [ "$SESSION" = "agents" ] && [ "$LAYOUT" = "tiled" ] && [ "${#WORKERS[@]}" -eq 3 ] )
assert_fail "$((1 - $?))" "default.sh: SESSION/LAYOUT/WORKERS 3개"
# 위 트릭: 성공(0)이면 1-0=1(비0)→assert_fail 통과. 가독성 위해 아래 방식 사용:

source "$ROOT/profiles/default.sh"
assert_eq "agents" "$SESSION" "default SESSION"
assert_eq "tiled" "$LAYOUT" "default LAYOUT"
assert_eq "3" "${#WORKERS[@]}" "default 워커 3개"
assert_eq "dev:dev" "${WORKERS[0]}" "default 첫 워커"

source "$ROOT/profiles/code-review.sh"
assert_eq "3" "${#WORKERS[@]}" "code-review 워커 3개"
assert_contains "${WORKERS[*]}" "security" "code-review 에 security 포함"

source "$ROOT/profiles/research.sh"
assert_eq "3" "${#WORKERS[@]}" "research 워커 3개"

# 모든 역할 프롬프트 + 공통 프롬프트 존재
for f in _common roles/dev roles/reviewer roles/tester roles/security roles/researcher; do
  [ -f "$ROOT/prompts/$f.md" ]; assert_eq "0" "$?" "prompts/$f.md 존재"
done

# 공통 프롬프트에 치환 토큰과 핵심 규약
COMMON="$(cat "$ROOT/prompts/_common.md")"
assert_contains "$COMMON" '{{WORKER_NAME}}' "_common 에 치환 토큰"
assert_contains "$COMMON" 'wait-for -S done-{{WORKER_NAME}}' "_common 에 완료 신호 규약"
assert_contains "$COMMON" 'workspace/tasks/' "_common 에 tasks 읽기 규약"

test_summary
```

(첫 `assert_fail` 트릭 줄은 혼란을 주므로 Step 3 작성 후 Step 4 전에 제거할 것 — 아래 Step 3.5 참조.)

- [ ] **Step 2: 테스트 실패 확인**

Run: `bash tests/test-profiles.sh`
Expected: FAIL — `profiles/default.sh` 없음

- [ ] **Step 3: 프로파일 3개 작성**

Create `profiles/default.sh`:

```bash
# 기본 팀: 개발/리뷰/테스트
SESSION="agents"
LAYOUT="tiled"
# 형식: "워커이름:역할"  (역할 → prompts/roles/<역할>.md)
WORKERS=(
  "dev:dev"
  "review:reviewer"
  "test:tester"
)
```

Create `profiles/code-review.sh`:

```bash
# 코드 리뷰 팀: 리뷰어 2 + 보안 1
SESSION="agents"
LAYOUT="tiled"
WORKERS=(
  "review1:reviewer"
  "review2:reviewer"
  "security:security"
)
```

Create `profiles/research.sh`:

```bash
# 리서치 팀: 리서처 3 병렬 조사
SESSION="agents"
LAYOUT="tiled"
WORKERS=(
  "research1:researcher"
  "research2:researcher"
  "research3:researcher"
)
```

- [ ] **Step 3.5: 테스트의 혼란스러운 첫 줄 제거**

`tests/test-profiles.sh`에서 아래 두 줄(주석 포함)을 삭제:

```bash
( source "$ROOT/profiles/default.sh"
  [ "$SESSION" = "agents" ] && [ "$LAYOUT" = "tiled" ] && [ "${#WORKERS[@]}" -eq 3 ] )
assert_fail "$((1 - $?))" "default.sh: SESSION/LAYOUT/WORKERS 3개"
# 위 트릭: 성공(0)이면 1-0=1(비0)→assert_fail 통과. 가독성 위해 아래 방식 사용:
```

남는 시작 지점은 `source "$ROOT/profiles/default.sh"` 부터.

- [ ] **Step 4: 공통 프롬프트 작성**

Create `prompts/_common.md`:

```markdown
너는 tmux 멀티 에이전트 팀의 워커다. 워커 이름: {{WORKER_NAME}}

## 작업 사이클 (반드시 준수)
1. 오케스트레이터가 "TASK <id>" 형식 지시를 주면, workspace/tasks/<id>.md 를 읽어 작업을 파악한다.
2. 작업을 수행한다.
3. 결과를 workspace/results/<id>.md 에 Markdown으로 기록한다. 다음을 포함한다:
   - 상태: SUCCESS 또는 FAILURE
   - 산출물 경로(있으면)
   - 작업 요약
4. 완료 신호를 보낸다. 반드시 마지막에 이 명령을 실행한다:
   tmux wait-for -S done-{{WORKER_NAME}}-<id>
5. 다음 지시를 대기한다. 임의로 다른 작업을 시작하지 않는다.

## 금지
- workspace/tasks/ 외의 지시를 추측해 실행하지 않는다.
- 완료 신호(wait-for -S) 없이 작업을 끝났다고 간주하지 않는다.
- 다른 워커의 페인이나 파일에 간섭하지 않는다.
```

- [ ] **Step 5: 역할 프롬프트 5개 작성**

Create `prompts/roles/dev.md`:

```markdown
## 역할: 개발자
- tasks 지시에 따라 코드를 구현/수정한다.
- 기존 코드 패턴을 따른다. 타입 에러를 남기지 않는다.
- 결과 파일에 변경한 파일 목록과 diff 요약을 포함한다.
```

Create `prompts/roles/reviewer.md`:

```markdown
## 역할: 코드 리뷰어
- tasks 가 가리키는 코드/변경을 읽고 리뷰한다.
- 버그, 설계 문제, 누락된 테스트를 우선순위와 함께 지적한다.
- 결과 파일에 발견 항목을 심각도(critical/major/minor)별로 정리한다.
```

Create `prompts/roles/tester.md`:

```markdown
## 역할: 테스터
- tasks 가 가리키는 대상에 대한 테스트를 작성/실행한다.
- 정상 케이스와 엣지 케이스를 모두 다룬다.
- 결과 파일에 실행한 테스트 목록과 통과/실패 결과를 포함한다.
```

Create `prompts/roles/security.md`:

```markdown
## 역할: 보안 검토자
- tasks 가 가리키는 코드/변경을 보안 관점에서 검토한다.
- 인젝션, 비밀정보 노출, 권한 문제, 안전하지 않은 의존성을 점검한다.
- 결과 파일에 위험 항목과 완화 방안을 정리한다.
```

Create `prompts/roles/researcher.md`:

```markdown
## 역할: 리서처
- tasks 가 지정한 주제를 조사한다 (코드베이스 분석/문서/자료 수집).
- 출처를 명시하고 추측과 사실을 구분한다.
- 결과 파일에 핵심 발견을 요약하고 근거 경로/링크를 포함한다.
```

- [ ] **Step 6: 테스트 통과 확인**

Run: `bash tests/test-profiles.sh`
Expected: 모든 `ok:`, `ran=` 값과 `fail=0`, exit 0 (assert가 17개 내외)

- [ ] **Step 7: 커밋**

```bash
git add profiles prompts tests/test-profiles.sh
git commit -m "feat: 프로파일 3종 + 공통/역할 프롬프트 정의"
```

---

## Task 5: team-up.sh — 세션/페인 생성 + 부트스트랩 주입

**Files:**
- Create: `bin/team-up.sh`
- Test: `tests/test-team-up.sh`

`team-up.sh [profile]`은 (1) 프로파일 source, (2) 기존 세션 있으면 거부, (3) 오케 페인 1개로 세션 생성, (4) 워커 수만큼 페인 분할 + 레이아웃 적용, (5) 워커별 부트스트랩 합본을 `{{WORKER_NAME}}` 치환해 `workspace/.boot/<worker>.md`에 작성, (6) 각 워커 페인에서 claude 실행 후 boot 파일 읽기 지시 주입.

claude 실행 명령은 환경변수 `AGENT_CMD`로 오버라이드 가능하게 한다(기본 `claude`, 테스트는 더미로 치환).

- [ ] **Step 1: 실패하는 테스트 작성**

Create `tests/test-team-up.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh

ROOT="$(cd .. && pwd)"
export SESSION_OVERRIDE="tu_$$"
# 워커 페인은 claude 대신 'cat' 더미 실행 (입력 대기만)
export AGENT_CMD="cat"

cleanup() { tmux kill-session -t "$SESSION_OVERRIDE" 2>/dev/null || true; rm -rf "$ROOT/workspace/.boot"; }
trap cleanup EXIT

# 1) 정상 생성
bash "$ROOT/bin/team-up.sh" default
rc=$?
assert_eq "0" "$rc" "team-up default 성공 종료"

# 세션 존재
tmux has-session -t "$SESSION_OVERRIDE" 2>/dev/null
assert_eq "0" "$?" "세션 생성됨"

# 페인 4개 (오케1 + 워커3)
N="$(tmux list-panes -t "$SESSION_OVERRIDE:0" | wc -l | tr -d ' ')"
assert_eq "4" "$N" "페인 4개"

# 부트스트랩 파일이 워커별로 생성되고 치환됨
assert_eq "0" "$([ -f "$ROOT/workspace/.boot/dev.md" ] && echo 0 || echo 1)" "dev.md boot 생성"
BOOT="$(cat "$ROOT/workspace/.boot/dev.md")"
assert_contains "$BOOT" "워커 이름: dev" "{{WORKER_NAME}} → dev 치환됨"
assert_contains "$BOOT" "done-dev-" "신호 채널명 치환됨"
assert_contains "$BOOT" "역할: 개발자" "역할 프롬프트 합쳐짐"
if printf '%s' "$BOOT" | grep -qF '{{WORKER_NAME}}'; then r=0; else r=1; fi
assert_eq "1" "$r" "미치환 토큰 없음"

# 2) 중복 실행 거부
bash "$ROOT/bin/team-up.sh" default
assert_fail "$?" "기존 세션 존재 시 중복 생성 거부"

cleanup
trap - EXIT

# 3) 없는 프로파일 → 실패
bash "$ROOT/bin/team-up.sh" nonexistent_profile
assert_fail "$?" "없는 프로파일 → 실패"
tmux kill-session -t "$SESSION_OVERRIDE" 2>/dev/null || true

test_summary
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `bash tests/test-team-up.sh`
Expected: FAIL — `bin/team-up.sh` 없음

- [ ] **Step 3: team-up.sh 구현**

Create `bin/team-up.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_DIR/lib.sh"

PROFILE="${1:-default}"
PROFILE_FILE="$REPO_ROOT/profiles/$PROFILE.sh"

if [ ! -f "$PROFILE_FILE" ]; then
  echo "오류: 프로파일 없음 → $PROFILE_FILE" >&2
  echo "사용 가능: $(ls "$REPO_ROOT/profiles" 2>/dev/null | sed 's/\.sh$//' | tr '\n' ' ')" >&2
  exit 1
fi

# 프로파일 로드 (SESSION, LAYOUT, WORKERS 정의)
# shellcheck disable=SC1090
source "$PROFILE_FILE"

# 테스트/멀티팀용 세션명 오버라이드
SESSION="${SESSION_OVERRIDE:-$SESSION}"

# 워커 명령 (기본 claude, 테스트는 AGENT_CMD 로 더미 치환)
AGENT_CMD="${AGENT_CMD:-claude}"

# 중복 세션 거부
if tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "오류: 세션 '$SESSION' 이미 존재. attach 하거나 team-down.sh 후 재시도." >&2
  exit 1
fi

mkdir -p "$WORKSPACE/.boot" "$WORKSPACE/tasks" "$WORKSPACE/results"

# 오케스트레이터 페인으로 세션 생성. 셸 유지.
tmux new-session -d -s "$SESSION" -x 220 -y 50 -n team

# 인덱스 규약 세션 로컬 고정: 사용자 전역 ~/.tmux.conf 의
# base-index/pane-base-index(예: 1) 와 무관하게 window 0 / pane 1 보장.
# move-window -r 로 이미 생성된 윈도우를 base-index(0)부터 재정렬.
fix_session_indexing "$SESSION"

# 적용 검증: window 0 이 실제로 존재하지 않으면 즉시 실패 (추측 우회 금지).
_w="$(tmux list-windows -t "$SESSION" -F '#{window_index}' | head -1)"
if [ "$_w" != "0" ]; then
  echo "오류: 세션 로컬 인덱스 고정 실패 (window=$_w, 기대=0). tmux 버전/설정 확인 필요." >&2
  tmux kill-session -t "$SESSION" 2>/dev/null || true
  exit 1
fi

tmux select-pane -t "$SESSION:0.1" -T "ORCHESTRATOR"

# 워커 페인 분할
idx=2
for entry in "${WORKERS[@]}"; do
  name="${entry%%:*}"
  tmux split-window -t "$SESSION:0" -d
  tmux select-layout -t "$SESSION:0" "$LAYOUT"
  tmux select-pane -t "$(target_of "$idx")" -T "$name"
  idx=$((idx + 1))
done
tmux select-layout -t "$SESSION:0" "$LAYOUT"

# continuum 오염 방지: 이 세션 자동저장 사실상 비활성화
tmux set-option -t "$SESSION" @continuum-save-interval '0' 2>/dev/null || true

# 워커별 부트스트랩 합본 생성 + 치환, claude 실행, boot 읽기 지시 주입
idx=2
for entry in "${WORKERS[@]}"; do
  name="${entry%%:*}"
  role="${entry##*:}"
  bf="$(boot_file "$name")"
  cat "$REPO_ROOT/prompts/_common.md" "$REPO_ROOT/prompts/roles/$role.md" \
    | sed "s/{{WORKER_NAME}}/$name/g" > "$bf"

  tgt="$(target_of "$idx")"
  tmux send-keys -t "$tgt" -l "$AGENT_CMD"
  tmux send-keys -t "$tgt" Enter
  sleep 0.2
  send_prompt "$tgt" "$bf 를 읽고 그 규약을 그대로 따르라. 준비되면 다음 지시를 대기하라."
  idx=$((idx + 1))
done

echo "팀 '$PROFILE' 가동 완료. 세션='$SESSION', 워커=${#WORKERS[@]}개."
echo "attach: tmux attach -t $SESSION"
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `bash tests/test-team-up.sh`
Expected: 모든 `ok:`, `fail=0`, exit 0

`send_prompt`가 `lib.sh`의 함수임에 유의 — `team-up.sh`가 `lib.sh`를 source 하므로 사용 가능.

- [ ] **Step 5: 실행 권한 + 커밋**

```bash
chmod +x bin/team-up.sh
git add bin/team-up.sh tests/test-team-up.sh
git commit -m "feat: team-up.sh 세션 생성 + 부트스트랩 주입"
```

---

## Task 6: dispatch.sh — 작업 배정

**Files:**
- Create: `bin/dispatch.sh`
- Test: `tests/test-dispatch.sh`

`dispatch.sh <worker> <id>`는 (1) `workspace/tasks/<id>.md` 존재 확인, (2) 세션 존재 확인, (3) 워커 이름 → 페인 인덱스 매핑(현재 활성 프로파일을 어떻게 알 것인가? → `workspace/.boot/<worker>.md` 존재로 워커 유효성 판단하고, 페인은 pane title로 찾는다), (4) 해당 페인에 `TASK <id>` 주입.

페인 인덱스는 프로파일을 다시 읽지 않고 `tmux list-panes` + pane_title로 워커 이름을 찾아 동적 해석한다 (team-up이 pane title을 워커명으로 설정함).

- [ ] **Step 1: 실패하는 테스트 작성**

Create `tests/test-dispatch.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh

ROOT="$(cd .. && pwd)"
export SESSION_OVERRIDE="dp_$$"
export AGENT_CMD="cat"

cleanup() { tmux kill-session -t "$SESSION_OVERRIDE" 2>/dev/null || true; rm -rf "$ROOT/workspace/.boot"; rm -f "$ROOT/workspace/tasks/T1.md"; }
trap cleanup EXIT

bash "$ROOT/bin/team-up.sh" default >/dev/null
sleep 0.3

# 작업 파일 준비
echo "# T1: 더미 작업" > "$ROOT/workspace/tasks/T1.md"

# 정상 dispatch
SESSION_OVERRIDE="$SESSION_OVERRIDE" bash "$ROOT/bin/dispatch.sh" dev T1
assert_eq "0" "$?" "정상 dispatch 성공"

# dev 페인(cat)이 받은 입력 확인: capture-pane
sleep 0.3
PANE="$(tmux capture-pane -p -t "$SESSION_OVERRIDE:0" -S -50 2>/dev/null || true)"
# cat 더미라 입력 에코가 페인에 남음. TASK T1 문자열 확인은 pane title 매칭이 핵심이므로
# 여기서는 종료코드 + 에러경로 위주로 검증한다.

# 존재하지 않는 작업 파일
SESSION_OVERRIDE="$SESSION_OVERRIDE" bash "$ROOT/bin/dispatch.sh" dev NOPE
assert_fail "$?" "없는 작업 파일 → 실패"

# 존재하지 않는 워커
SESSION_OVERRIDE="$SESSION_OVERRIDE" bash "$ROOT/bin/dispatch.sh" ghost T1
assert_fail "$?" "없는 워커 → 실패"

# 세션 없을 때
tmux kill-session -t "$SESSION_OVERRIDE" 2>/dev/null || true
SESSION_OVERRIDE="$SESSION_OVERRIDE" bash "$ROOT/bin/dispatch.sh" dev T1
assert_fail "$?" "세션 없음 → 실패"

test_summary
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `bash tests/test-dispatch.sh`
Expected: FAIL — `bin/dispatch.sh` 없음

- [ ] **Step 3: dispatch.sh 구현**

Create `bin/dispatch.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_DIR/lib.sh"

SESSION="${SESSION_OVERRIDE:-$SESSION_DEFAULT}"

WORKER="${1:-}"
TASK_ID="${2:-}"

if [ -z "$WORKER" ] || [ -z "$TASK_ID" ]; then
  echo "사용법: dispatch.sh <worker> <task-id>" >&2
  exit 1
fi

# 세션 확인
if ! tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "오류: 세션 '$SESSION' 없음. team-up.sh 먼저 실행." >&2
  exit 1
fi

# 작업 파일 확인
TASK_FILE="$WORKSPACE/tasks/$TASK_ID.md"
if [ ! -f "$TASK_FILE" ]; then
  echo "오류: 작업 파일 없음 → $TASK_FILE" >&2
  exit 1
fi

# 워커 → 페인 인덱스: pane title 로 찾는다 (team-up 이 title=워커명 설정)
PANE_IDX=""
while IFS=' ' read -r pidx ptitle; do
  if [ "$ptitle" = "$WORKER" ]; then
    PANE_IDX="$pidx"
    break
  fi
done < <(tmux list-panes -t "$SESSION:0" -F '#{pane_index} #{pane_title}')

if [ -z "$PANE_IDX" ]; then
  echo "오류: 워커 '$WORKER' 페인을 찾을 수 없음. 활성 워커: $(tmux list-panes -t "$SESSION:0" -F '#{pane_title}' | tr '\n' ' ')" >&2
  exit 1
fi

TARGET="$SESSION:0.$PANE_IDX"
send_prompt "$TARGET" "TASK $TASK_ID"
echo "배정 완료: 워커=$WORKER (pane $PANE_IDX) ← TASK $TASK_ID"
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `bash tests/test-dispatch.sh`
Expected: 모든 `ok:`, `fail=0`, exit 0

- [ ] **Step 5: 실행 권한 + 커밋**

```bash
chmod +x bin/dispatch.sh
git add bin/dispatch.sh tests/test-dispatch.sh
git commit -m "feat: dispatch.sh 작업 배정 (pane title 기반 워커 해석)"
```

---

## Task 7: wait-worker.sh — 완료 대기 (timeout 래핑)

**Files:**
- Create: `bin/wait-worker.sh`
- Test: `tests/test-wait-worker.sh`

`wait-worker.sh <worker> <id> [timeout_sec]`은 `tmux wait-for done-<worker>-<id>`를 `timeout` 명령으로 감싼다. 타임아웃이면 해당 워커 페인을 `capture-pane -p`로 덤프 출력하고 비-0 종료. macOS는 coreutils `timeout`이 없을 수 있으므로 `gtimeout` → `timeout` → 폴백(백그라운드+kill) 순으로 처리.

- [ ] **Step 1: 실패하는 테스트 작성**

Create `tests/test-wait-worker.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh

ROOT="$(cd .. && pwd)"
export SESSION_OVERRIDE="ww_$$"
export AGENT_CMD="cat"

cleanup() { tmux kill-session -t "$SESSION_OVERRIDE" 2>/dev/null || true; rm -rf "$ROOT/workspace/.boot"; }
trap cleanup EXIT

bash "$ROOT/bin/team-up.sh" default >/dev/null
sleep 0.3

# 신호가 먼저 와 있는 경우: 즉시 반환 (race 안전, spec §4.2)
tmux wait-for -S done-dev-PRE
START=$(date +%s)
SESSION_OVERRIDE="$SESSION_OVERRIDE" bash "$ROOT/bin/wait-worker.sh" dev PRE 5
rc=$?
END=$(date +%s)
assert_eq "0" "$rc" "선신호 → 즉시 0 종료"
[ $((END - START)) -le 2 ]; assert_eq "0" "$?" "선신호 → 2초 이내 반환"

# 신호를 나중에 보내는 경우: 백그라운드에서 1초 후 신호
( sleep 1; tmux wait-for -S done-dev-LATER ) &
START=$(date +%s)
SESSION_OVERRIDE="$SESSION_OVERRIDE" bash "$ROOT/bin/wait-worker.sh" dev LATER 5
rc=$?
assert_eq "0" "$rc" "지연 신호 → 0 종료"
wait

# 타임아웃: 아무도 신호 안 보냄 → 2초 타임아웃, 비-0, 페인 덤프 출력
OUT="$(SESSION_OVERRIDE="$SESSION_OVERRIDE" bash "$ROOT/bin/wait-worker.sh" dev NEVER 2 2>&1)"
rc=$?
assert_fail "$rc" "타임아웃 → 비-0 종료"
assert_contains "$OUT" "타임아웃" "타임아웃 메시지 출력"
assert_contains "$OUT" "capture" "페인 덤프 섹션 표기"

test_summary
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `bash tests/test-wait-worker.sh`
Expected: FAIL — `bin/wait-worker.sh` 없음

- [ ] **Step 3: wait-worker.sh 구현**

Create `bin/wait-worker.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_DIR/lib.sh"

SESSION="${SESSION_OVERRIDE:-$SESSION_DEFAULT}"

WORKER="${1:-}"
TASK_ID="${2:-}"
TIMEOUT="${3:-300}"

if [ -z "$WORKER" ] || [ -z "$TASK_ID" ]; then
  echo "사용법: wait-worker.sh <worker> <task-id> [timeout_sec]" >&2
  exit 1
fi

CHANNEL="done-$WORKER-$TASK_ID"

# timeout 명령 해석: coreutils timeout / gtimeout / 폴백
run_with_timeout() {
  local secs="$1"; shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "$secs" "$@"
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$secs" "$@"
  else
    # 폴백: 백그라운드 실행 + 감시 후 kill
    "$@" &
    local pid=$!
    ( sleep "$secs"; kill -TERM "$pid" 2>/dev/null ) &
    local watcher=$!
    if wait "$pid" 2>/dev/null; then
      kill -TERM "$watcher" 2>/dev/null || true
      return 0
    else
      return 124
    fi
  fi
}

if run_with_timeout "$TIMEOUT" tmux wait-for "$CHANNEL"; then
  echo "완료 신호 수신: $CHANNEL"
  exit 0
else
  rc=$?
  echo "오류: 타임아웃(${TIMEOUT}s) — 채널 '$CHANNEL' 신호 없음 (워커=$WORKER)" >&2
  echo "---- capture-pane (워커 '$WORKER') ----" >&2
  # 워커 페인 찾아 덤프
  pidx=""
  while IFS=' ' read -r pi pt; do
    [ "$pt" = "$WORKER" ] && { pidx="$pi"; break; }
  done < <(tmux list-panes -t "$SESSION:0" -F '#{pane_index} #{pane_title}' 2>/dev/null || true)
  if [ -n "$pidx" ]; then
    tmux capture-pane -p -t "$SESSION:0.$pidx" -S -40 >&2 2>/dev/null || echo "(페인 캡처 실패)" >&2
  else
    echo "(워커 페인을 찾을 수 없음)" >&2
  fi
  echo "---- end capture ----" >&2
  exit "$rc"
fi
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `bash tests/test-wait-worker.sh`
Expected: 모든 `ok:`, `fail=0`, exit 0

- [ ] **Step 5: 실행 권한 + 커밋**

```bash
chmod +x bin/wait-worker.sh
git add bin/wait-worker.sh tests/test-wait-worker.sh
git commit -m "feat: wait-worker.sh 완료 대기 + timeout 폴백 + 페인 덤프"
```

---

## Task 8: team-down.sh — 정리

**Files:**
- Create: `bin/team-down.sh`
- Test: `tests/test-team-down.sh`

`team-down.sh`는 세션을 kill 하고 `workspace/.boot/`를 정리한다. 세션이 없어도 에러 없이 멱등 동작한다. `tasks/`/`results/`는 사용자 산출물이므로 건드리지 않는다.

- [ ] **Step 1: 실패하는 테스트 작성**

Create `tests/test-team-down.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh

ROOT="$(cd .. && pwd)"
export SESSION_OVERRIDE="td_$$"
export AGENT_CMD="cat"

bash "$ROOT/bin/team-up.sh" default >/dev/null
sleep 0.2
[ -f "$ROOT/workspace/.boot/dev.md" ]; assert_eq "0" "$?" "boot 파일 사전 존재"

# 정상 정리
SESSION_OVERRIDE="$SESSION_OVERRIDE" bash "$ROOT/bin/team-down.sh"
assert_eq "0" "$?" "team-down 성공"

tmux has-session -t "$SESSION_OVERRIDE" 2>/dev/null; assert_fail "$?" "세션 제거됨"
[ -d "$ROOT/workspace/.boot" ] && [ -n "$(ls -A "$ROOT/workspace/.boot" 2>/dev/null)" ] && r=1 || r=0
assert_eq "0" "$r" ".boot 비워짐"

# 멱등: 세션 없어도 실패하지 않음
SESSION_OVERRIDE="$SESSION_OVERRIDE" bash "$ROOT/bin/team-down.sh"
assert_eq "0" "$?" "세션 없어도 멱등 성공"

test_summary
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `bash tests/test-team-down.sh`
Expected: FAIL — `bin/team-down.sh` 없음

- [ ] **Step 3: team-down.sh 구현**

Create `bin/team-down.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_DIR/lib.sh"

SESSION="${SESSION_OVERRIDE:-$SESSION_DEFAULT}"

if tmux has-session -t "$SESSION" 2>/dev/null; then
  tmux kill-session -t "$SESSION"
  echo "세션 '$SESSION' 종료."
else
  echo "세션 '$SESSION' 없음 (이미 정리됨)."
fi

# 부트스트랩 합본은 런타임 산출물 → 정리. tasks/results 는 보존.
if [ -d "$WORKSPACE/.boot" ]; then
  rm -f "$WORKSPACE/.boot"/*.md 2>/dev/null || true
  echo "workspace/.boot 정리 완료."
fi
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `bash tests/test-team-down.sh`
Expected: 모든 `ok:`, `fail=0`, exit 0

- [ ] **Step 5: 실행 권한 + 커밋**

```bash
chmod +x bin/team-down.sh
git add bin/team-down.sh tests/test-team-down.sh
git commit -m "feat: team-down.sh 세션 정리 (멱등, tasks/results 보존)"
```

---

## Task 9: 통합 사이클 E2E 테스트

**Files:**
- Test: `tests/test-e2e-cycle.sh`

spec §4.5 한 사이클을 더미 워커로 검증: dispatch → 워커가 결과 파일 작성 + 신호 → wait-worker 반환 → 결과 Read. 실제 claude 대신, 워커 페인에서 "TASK를 받으면 결과 쓰고 신호 보내는" 작은 bash 스크립트를 `AGENT_CMD`로 띄운다.

- [ ] **Step 1: 더미 워커 스크립트 + E2E 테스트 작성**

Create `tests/dummy-worker.sh`:

```bash
#!/usr/bin/env bash
# 테스트용 가짜 워커: stdin 으로 "<boot파일> 를 읽고..." 와 "TASK <id>" 를 받음.
# TASK 라인을 만나면 결과 파일 쓰고 wait-for -S 신호.
# 워커 이름은 인자로 받는다.
set -uo pipefail
WORKER="$1"
ROOT="$2"
while IFS= read -r line; do
  case "$line" in
    "TASK "*)
      id="${line#TASK }"
      echo "# 결과 $id" > "$ROOT/workspace/results/$id.md"
      echo "상태: SUCCESS" >> "$ROOT/workspace/results/$id.md"
      echo "워커: $WORKER" >> "$ROOT/workspace/results/$id.md"
      tmux wait-for -S "done-$WORKER-$id"
      ;;
  esac
done
```

Create `tests/test-e2e-cycle.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh

ROOT="$(cd .. && pwd)"
export SESSION_OVERRIDE="e2e_$$"
# 워커 페인에서 더미 워커 실행 (dev 워커만 검증 대상; 나머지도 같은 더미)
export AGENT_CMD="bash $ROOT/tests/dummy-worker.sh dev $ROOT"

cleanup() {
  tmux kill-session -t "$SESSION_OVERRIDE" 2>/dev/null || true
  rm -rf "$ROOT/workspace/.boot"
  rm -f "$ROOT/workspace/tasks/E1.md" "$ROOT/workspace/results/E1.md"
}
trap cleanup EXIT

bash "$ROOT/bin/team-up.sh" default >/dev/null
sleep 0.5

# 작업 파일 작성
echo "# E1: E2E 더미 작업" > "$ROOT/workspace/tasks/E1.md"

# dispatch → wait → 결과 확인
SESSION_OVERRIDE="$SESSION_OVERRIDE" bash "$ROOT/bin/dispatch.sh" dev E1
assert_eq "0" "$?" "E2E dispatch 성공"

SESSION_OVERRIDE="$SESSION_OVERRIDE" bash "$ROOT/bin/wait-worker.sh" dev E1 10
assert_eq "0" "$?" "E2E wait-worker 신호 수신"

[ -f "$ROOT/workspace/results/E1.md" ]; assert_eq "0" "$?" "결과 파일 생성됨"
RES="$(cat "$ROOT/workspace/results/E1.md")"
assert_contains "$RES" "상태: SUCCESS" "결과에 SUCCESS"
assert_contains "$RES" "워커: dev" "결과에 워커명"

test_summary
```

참고: `team-up.sh`는 모든 워커 페인에 동일 `AGENT_CMD`를 실행한다. 더미 워커는 인자 `dev`로 고정돼 있어 review/test 페인도 자신을 dev로 동작시키지만, 본 테스트는 dev 워커 사이클만 검증하므로 무해하다.

- [ ] **Step 2: 테스트 실패 확인 (사전 — 구현은 이미 됨, 통합 검증)**

Run: `bash tests/test-e2e-cycle.sh`
Expected: 이전 태스크 구현이 정확하면 통과. 실패 시 어느 단계(dispatch/wait/결과)인지 메시지로 진단.

- [ ] **Step 3: 통과 확인 + 전체 스위트 실행**

Run: `chmod +x tests/dummy-worker.sh && bash tests/run-all.sh`
Expected: 모든 스위트 통과, `ALL SUITES PASSED`, exit 0

- [ ] **Step 4: 커밋**

```bash
git add tests/dummy-worker.sh tests/test-e2e-cycle.sh
git commit -m "test: E2E 한 사이클 통합 테스트 (dispatch→wait→결과)"
```

---

## Task 10: README + 최종 점검

**Files:**
- Create: `README.md`

- [ ] **Step 1: README 작성**

Create `README.md`:

```markdown
# tmux 멀티 에이전트 팀

tmux 페인마다 Claude Code 인스턴스를 띄우고 역할/제약을 부여해, 1 오케스트레이터 + N 워커 멀티 에이전트 팀을 운영한다.

## 전제

- tmux 3.6+ (`send-keys -l`, `wait-for`, `capture-pane` 사용)
- `claude` CLI 설치 및 PATH 등록
- prefix는 tmux 기본값(C-b) 가정. `~/.tmux.conf`는 이 repo가 수정하지 않음.

## 철학

세션은 일회용. git으로 버전 관리되는 `profiles/` + `prompts/` 정의로부터 `team-up.sh`가 매번 동일한 팀을 재생성한다. 세션 상태를 저장/복원하지 않는다.

## 사용법

\`\`\`bash
# 1) 팀 가동 (기본 프로파일: dev/review/test)
bin/team-up.sh default
tmux attach -t agents

# 2) 작업 지시 작성
echo "# T1: 로그인 버그 수정" > workspace/tasks/T1.md

# 3) 워커에 배정
bin/dispatch.sh dev T1

# 4) 완료 대기 (기본 300초, 변경 가능)
bin/wait-worker.sh dev T1 300

# 5) 결과 확인
cat workspace/results/T1.md

# 6) 팀 정리
bin/team-down.sh
\`\`\`

## 프로파일

`profiles/*.sh`로 팀 구성을 정의. `bin/team-up.sh <프로파일명>`으로 선택.

- `default` — dev / review / test
- `code-review` — reviewer×2 / security
- `research` — researcher×3

새 팀: `profiles/<name>.sh` 추가 (`SESSION`, `LAYOUT`, `WORKERS=("이름:역할" ...)`), 필요 시 `prompts/roles/<역할>.md` 추가. `bin/`은 수정 불필요.

## 통신 메커니즘

- 명령 주입: `tmux send-keys -l` (텍스트/Enter 분리)
- 완료 동기화: `tmux wait-for` (폴링 없는 블로킹, race-safe)
- 결과 전달: `workspace/results/<id>.md` 파일
- 디버그: `tmux capture-pane -p`

## 테스트

\`\`\`bash
bash tests/run-all.sh
\`\`\`

외부 의존성 없음. 실제 tmux 세션을 띄우되 워커 명령을 `AGENT_CMD` 환경변수로 더미 치환해 검증한다.

## 디렉토리

- `bin/` — 고정 로직 (수정 거의 불필요)
- `profiles/` — 팀 구성 정의 (커스텀 지점)
- `prompts/` — 워커 규약 (커스텀 지점)
- `workspace/` — 런타임 산출물 (git 제외)
- `docs/superpowers/` — 설계/계획 문서
```

(주의: 위 README 안의 `\`\`\`` 는 실제 파일에서는 백틱 3개로 작성한다.)

- [ ] **Step 2: 전체 테스트 스위트 최종 실행**

Run: `bash tests/run-all.sh`
Expected: `ALL SUITES PASSED`, exit 0

- [ ] **Step 3: 잔존 세션/산출물 정리 확인**

Run: `tmux ls 2>/dev/null | grep -E '^(tu_|dp_|ww_|td_|e2e_|libtest_)' || echo "테스트 잔존 세션 없음"`
Expected: `테스트 잔존 세션 없음`

Run: `git status --porcelain workspace/ | grep -v '\.gitkeep' || echo "workspace 깨끗"`
Expected: `workspace 깨끗` (런타임 산출물이 .gitignore 됨)

- [ ] **Step 4: 커밋**

```bash
git add README.md
git commit -m "docs: README 작성 (사용법/프로파일/통신/테스트)"
```

- [ ] **Step 5: 최종 수동 검증 (실제 claude — 선택)**

실제 claude로 한 사이클 수동 확인 (자동 테스트 아님, 사용자가 직접 수행):

```bash
bin/team-up.sh default
tmux attach -t agents          # 워커 페인에 claude 부트스트랩 떴는지 확인
# (다른 터미널에서)
echo "# M1: README 의 오타를 찾아 보고만 하라" > workspace/tasks/M1.md
bin/dispatch.sh dev M1
bin/wait-worker.sh dev M1 600
cat workspace/results/M1.md
bin/team-down.sh
```

Expected: `workspace/results/M1.md`에 SUCCESS/요약 기록됨. spec §8 검증 1~4 정상 케이스 충족 확인.

---

## Self-Review 결과

**1. Spec 커버리지:**

| Spec 항목 | 구현 태스크 |
|---|---|
| §3.2 repo 구조 | Task 1(골격), 각 태스크에서 해당 파일 생성 |
| §3.3 프로파일 시스템 | Task 4 |
| §4.1 send-keys 주입 | Task 3 (`send_prompt`) |
| §4.2 wait-for 동기화 | Task 7 + E2E Task 9 |
| §4.3 결과 파일 | Task 9 (E2E에서 검증) |
| §4.4 capture-pane 디버그 | Task 7 (타임아웃 시 덤프) |
| §4.5 한 사이클 | Task 9 |
| §5 부트스트랩 규약 + 치환 | Task 4 (프롬프트) + Task 5 (치환·주입) |
| §6 스크립트 책임 | Task 2/3/5/6/7/8 |
| §7 에러 처리 (부재/타임아웃/race/중복/continuum) | Task 5(중복·continuum), 6(부재), 7(타임아웃·race) |
| §8 검증 8 케이스 | Task 5/6/7/9 + Task 10 Step 5(정상 1~4 수동) |
| §9 비목표 | 계획에 큐/DAG/영속화 미포함 — 준수 |

갭 없음.

**2. Placeholder 스캔:** "TBD/TODO/적절히 처리" 없음. 모든 코드 스텝에 완전한 코드 포함. README의 백틱 이스케이프는 명시적 주석으로 처리.

**3. 타입/이름 일관성:** `target_of`, `boot_file`, `send_prompt`, `session_exists`, `SESSION_OVERRIDE`, `AGENT_CMD`, 채널명 `done-<worker>-<id>`, pane title=워커명 규약 — Task 2~9 전반에서 동일하게 사용됨. team-up이 설정한 pane title을 dispatch/wait-worker가 동일 키로 조회 → 일관.

수정 사항 없음.
