# PROJECT_ROOT 분리 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `bin/lib.sh` 의 `REPO_ROOT` 단일 변수가 짊어지던 (a) 하네스 정의 위치와 (b) 작업 대상 프로젝트 위치를 `HARNESS_ROOT`·`PROJECT_ROOT` 두 변수로 분리해 멀티 프로젝트 작업·동시 가동을 가능하게 한다.

**Architecture:** `lib.sh` 가 source 시점에 두 변수를 확정(`HARNESS_ROOT`=bin/lib.sh 부모, `PROJECT_ROOT`=`HARNESS_PROJECT` env > cwd git toplevel > PWD). 산출물은 `$PROJECT_ROOT/.agent-harness/`, settings.json 은 `$PROJECT_ROOT/.claude/settings.json`, 표식은 `$PROJECT_ROOT/.claude/.agent-harness-marker`. SESSION 은 `agents-<sanitize(basename PROJECT_ROOT)>` 자동, `wait-for` 채널은 `done-<SESSION>-<worker>-<task>`. 모든 bin/ 스크립트가 `--project /path` escape hatch 지원.

**Tech Stack:** bash 3.2+ (macOS 호환), tmux 3.6+, git 2.x, 외부 의존 없음(jq optional).

**Spec:** `docs/superpowers/specs/2026-05-20-project-root-separation-design.md`

**선행:** 2차 하네스(`docs/superpowers/plans/2026-05-19-agent-harness.md`) main 머지 완료.

---

## 파일 구조 결정 (전체 작업 매핑)

### 변경 대상

| 파일 | 책임 |
|---|---|
| `bin/lib.sh` | HARNESS_ROOT·PROJECT_ROOT·WORKSPACE 분리. resolve_project_root·_session_autoname·_validate_project_root 신규. resolve_session 폴백 확장. set -e 호환·source 안전성. |
| `bin/team-up.sh` | `--project` 파서 + lib.sh source 후 PROJECT_ROOT_VALID 검사. mkdir 대상 `$WORKSPACE/{.boot,tasks,results,review}`. settings.json·marker 생성. `.gitignore` 안내(조건부). 워커 cwd=`$PROJECT_ROOT`. boot 소스 = `$HARNESS_ROOT/prompts/...`. |
| `bin/dispatch.sh` | `--project` 파서. WORKSPACE 의미 변경 자동 흡수. CHANNEL = `done-$SESSION-$WORKER-$TASK_ID`. |
| `bin/wait-worker.sh` | 동상. CHANNEL 갱신. |
| `bin/team-down.sh` | `--project` 파서. marker 게이트(없으면 .agent-harness/·settings.json 안 건드림 + 살아있는 agents-* 안내). marker 있으면 정상 정리 (tasks/results 보존). |
| `bin/log-event.sh` | 메타 화이트리스트 skip (절대경로 기준). 경로 이름 `.agent-harness/`. 기본값 회귀. |
| `templates/settings.json.tpl` | **신규 위치** (workspace/.claude/ 에서 이동). 토큰 `__PROJECT_ROOT__`·`__HARNESS_ROOT__`. |
| `prompts/_common.md` | `workspace/` → `.agent-harness/` 일괄. wait-for 채널명에 `{{SESSION}}` 토큰. 채널명 변형 금지 1줄. |
| `prompts/roles/orchestrator.md` | 경로 일괄 + dispatch cwd 명시 + stale tasks 판별 명시. |
| `prompts/roles/reviewer-*.md` | review/ 경로 일괄. |
| `prompts/loop/*.md` | review/·.review-cursor·events.log 경로 일괄. |
| `profiles/{default,code-review,research,feature-team}.sh` | `SESSION="agents"` 라인 삭제 (자동명 사용). |
| `.gitignore` | `workspace/...` 룰 제거, `.agent-harness/`·`.claude/.agent-harness-marker` 추가. |
| `README.md` | 호출 cwd·.agent-harness·동시 가동·`--project` 사용법. |

### 신규 테스트

| 파일 | 검증 대상 |
|---|---|
| `tests/test-project-root.sh` | resolve_project_root (HARNESS_PROJECT 우선, git toplevel, PWD 폴백, submodule) |
| `tests/test-session-autoname.sh` | _session_autoname·resolve_session 폴백 (sed sanitize, SESSION_OVERRIDE 우선) |
| `tests/test-self-harness.sh` | PROJECT_ROOT == HARNESS_ROOT 동등 |
| `tests/test-settings-protection.sh` | marker 게이트 (D2·E8·F8) |
| `tests/test-multi-project.sh` | 동시 가동 격리 |
| `tests/test-project-flag.sh` | `--project` 파서·정규화·위치·silent failure 회피 (D1·E7·E12·F2) |
| `tests/test-path-validation.sh` | 경로 정합성 (E4·F1·F4 - PROJECT_ROOT_VALID 변수) |
| `tests/test-channel-name.sh` | wait-for 채널명 SESSION prefix (E1) |
| `tests/probes/probe-multi-project.sh` | 수동 실측 |

### 삭제 대상

- `workspace/` 디렉터리 전체 (HARNESS_ROOT 측, 1차 토대 산출물 위치). 1·2차에서 빈 `.gitkeep`·`tasks/`·`results/`·`review/`·`.claude/` 구성.

### 기존 테스트 setup 보강

`tests/test-*.sh` 다수 — 임시 git repo 안에서 source 하도록. 기존 SESSION_OVERRIDE 패턴(`tu_<pid>`) 유지.

---

## Task 진행 순서 (의존성 기반)

핵심 변경 = `bin/lib.sh` 의 변수 분리. 모든 후속 작업이 이 변수에 의존. 따라서:

1. **T1~T4 인프라**: `lib.sh` 의 신규 함수·변수 (resolve_project_root → path validation → resolve_session 폴백 → --project 파서 helper)
2. **T5~T7 정의 자산 이동**: `templates/` 신설, settings.json.tpl 토큰 변경, `workspace/` 제거 준비
3. **T8~T13 bin/ 스크립트 갱신**: team-up·dispatch·wait-worker·team-down·log-event
4. **T14~T16 프롬프트·프로파일**: `_common.md`·roles·loop·profiles 일괄
5. **T17~T18 통합 테스트·README**: multi-project·self-harness·channel-name·settings-protection 통합·문서

**Task 패턴 분류** (R7):
- **TDD 5단계** (T1~T4·T7·T9): failing test → fail → 구현 → pass → commit. lib.sh 신규 함수·hook skip 가드·CHANNEL 변경 같은 동작 변경.
- **신규 통합 테스트** (T14·T15·T16·T17): T1~T13 의 의존 코드가 만들어진 후 신규 test 작성. failing 시점 없이 처음부터 PASS — 의도된 패턴. 검증 자체가 목적.
- **자산 이동·삭제·갱신** (T5·T11·T13·T18): TDD 적용 약함. sanity 검증·회귀 PASS 로 대체.
- **대규모 코드 변경 + 기존 테스트 보강** (T6·T8·T10·T12): 기존 테스트 setup 보강 후 동작 변경 → 보강된 테스트가 fail 후 코드 변경 → pass.

**기존 25 스위트는 task 마지막마다 `tests/run-all.sh` 로 회귀 검증**. T11 끝까지는 일부 fail 허용, T13 이후 모두 PASS.

---

## Task 1: lib.sh — HARNESS_ROOT 분리 + resolve_project_root 신규

**의도**: 변수 두 개로 명시 분리. cwd 자동감지·`HARNESS_PROJECT` env 우선·PWD 폴백.

**Files:**
- Modify: `bin/lib.sh` (기존 6-15 라인 영역)
- Create: `tests/test-project-root.sh`

- [ ] **Step 1: failing test 작성**

`tests/test-project-root.sh`:
```bash
#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"

# T1.1 — HARNESS_PROJECT env 우선
unset HARNESS_PROJECT
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
HARNESS_PROJECT="$TMP"
( source "$ROOT/bin/lib.sh" 2>/dev/null
  assert_eq "$TMP" "$PROJECT_ROOT" "HARNESS_PROJECT 우선"
  assert_eq "$ROOT" "$HARNESS_ROOT" "HARNESS_ROOT 는 bin/lib.sh 부모"
)
unset HARNESS_PROJECT

# T1.2 — git repo 깊은 하위에서 toplevel 반환
G="$(mktemp -d)"
( cd "$G" && git init -q && mkdir -p deep/nested && cd deep/nested
  source "$ROOT/bin/lib.sh" 2>/dev/null
  # macOS mktemp 가 /var/folders/... 와 /private/var/folders/... 양쪽으로 해석되는 케이스 대응
  pr_real="$(cd "$PROJECT_ROOT" && pwd -P)"
  g_real="$(cd "$G" && pwd -P)"
  assert_eq "$g_real" "$pr_real" "git toplevel 반환"
)
rm -rf "$G"

# T1.3 — git 아닌 디렉터리 → PWD 폴백 + stderr 경고
N="$(mktemp -d)"
( cd "$N"
  out="$(source "$ROOT/bin/lib.sh" 2>&1 >/dev/null)"
  echo "$out" | grep -q "git repo 아님"; assert_success "$?" "PWD 폴백 경고"
  n_real="$(cd "$N" && pwd -P)"
  pr_real="$(source "$ROOT/bin/lib.sh" 2>/dev/null; cd "$PROJECT_ROOT" && pwd -P)"
  assert_eq "$n_real" "$pr_real" "PWD 폴백 값"
)
rm -rf "$N"

test_summary
```

- [ ] **Step 2: fail 확인**

```
bash tests/test-project-root.sh
```
Expected: FAIL — `resolve_project_root` 미정의 / `HARNESS_ROOT` 미정의.

- [ ] **Step 3: lib.sh 최소 구현**

`bin/lib.sh` 의 상단 부분(`_LIB_DIR` 정의 다음)을 다음으로 변경:

```bash
# 이 파일(bin/lib.sh) 기준으로 하네스 루트 계산 (정의의 위치)
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_ROOT="$(cd "$_LIB_DIR/.." && pwd)"
SESSION_DEFAULT="agents"  # 폴백 안의 폴백 (자동명이 보통 이김)

# PROJECT_ROOT 도출: HARNESS_PROJECT(--project) > cwd 의 git toplevel > PWD.
# 워커 cwd·.agent-harness 위치·settings.json 위치의 기준 (작업 대상 위치).
resolve_project_root() {
  if [ -n "${HARNESS_PROJECT:-}" ]; then
    printf '%s' "$HARNESS_PROJECT"
    return
  fi
  local r
  r="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null)"
  if [ -n "$r" ]; then
    printf '%s' "$r"
  else
    echo "경고: '$PWD' 는 git repo 아님 — PWD 를 PROJECT_ROOT 로 사용 (--project 로 명시 가능)" >&2
    printf '%s' "$PWD"
  fi
}

PROJECT_ROOT="$(resolve_project_root)"
# git repo 여부 별도 캐싱 (HARNESS_PROJECT 우선 경로에서도 정확)
if git -C "$PROJECT_ROOT" rev-parse --show-toplevel >/dev/null 2>&1; then
  PROJECT_ROOT_IS_GIT=1
else
  PROJECT_ROOT_IS_GIT=0
fi

WORKSPACE="$PROJECT_ROOT/.agent-harness"
```

기존 `REPO_ROOT="$(cd "$_LIB_DIR/.." && pwd)"` + `WORKSPACE="$REPO_ROOT/workspace"` 줄은 위 블록이 대체.

- [ ] **Step 4: pass 확인**

```
bash tests/test-project-root.sh
```
Expected: PASS (3 tests).

- [ ] **Step 5: 회귀 — 기존 25 스위트는 아직 깨질 수 있음 (`REPO_ROOT` 참조)**

다음 task 까지는 `REPO_ROOT` 호환 별칭 유지. **위치: `WORKSPACE="$PROJECT_ROOT/.agent-harness"` 라인 바로 다음** (T2·T3·T4 가 그 아래·끝에 다른 코드 추가하므로 별칭은 변수 정의 영역 안에 둠):
```bash
# 마이그레이션 호환 별칭 — T11 에서 제거. spec §5.1 의 "REPO_ROOT 변수 사라진다"
# 는 최종 상태. 그 전까지 기존 25 스위트의 'workspace/' 참조 호환 위해 유지.
REPO_ROOT="$HARNESS_ROOT"
```

```
bash tests/run-all.sh 2>&1 | tail -3
```
Expected: 일부 fail 가능 (workspace 경로 의미 변경 — T6·T7·T8·T9·T10·T13 진행 전까지). 다음 task 로 진행.

- [ ] **Step 6: commit**

```bash
git add bin/lib.sh tests/test-project-root.sh
git commit -m "feat: T1 lib.sh — HARNESS_ROOT/PROJECT_ROOT 분리 + resolve_project_root

REPO_ROOT 단일 변수의 (a) 하네스 정의·(b) 작업 대상 결합 해체 1단계.
HARNESS_ROOT=bin/lib.sh 부모(불변), PROJECT_ROOT=cwd git toplevel >
PWD 폴백. HARNESS_PROJECT env (--project) 우선. PROJECT_ROOT_IS_GIT
캐싱. REPO_ROOT 호환 별칭은 T11 끝에 제거.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: lib.sh — path validation (PROJECT_ROOT_VALID)

**의도**: sed 구분자·셸 메타문자 충돌 회피. lib.sh 가 source 되는 파일이라 `exit` 금지 — 변수로 검증 결과 전달 (F1).

**Files:**
- Modify: `bin/lib.sh` (T1 의 PROJECT_ROOT_IS_GIT 다음에 추가)
- Create: `tests/test-path-validation.sh`

- [ ] **Step 1: failing test 작성**

`tests/test-path-validation.sh`:
```bash
#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"

# T2.1 — 영숫자·/._- 만 허용 → 정상
unset HARNESS_PROJECT
G="$(mktemp -d)"
( cd "$G" && git init -q
  source "$ROOT/bin/lib.sh" 2>/dev/null
  assert_eq "1" "$PROJECT_ROOT_VALID" "정상 경로 VALID=1"
)
rm -rf "$G"

# T2.2 — 공백 포함 → 거부 (VALID=0, source 자체는 죽지 않음 F1)
B="$(mktemp -d)/has space"; mkdir -p "$B"
( cd "$B"
  set +e
  source "$ROOT/bin/lib.sh" 2>/dev/null
  rc=$?
  set -e
  assert_eq "0" "$rc" "source 자체는 exit 0 (F1)"
  assert_eq "0" "$PROJECT_ROOT_VALID" "공백 포함 VALID=0"
)
rm -rf "$(dirname "$B")"

# T2.3 — `#` 포함 → 거부
H="$(mktemp -d)/has#hash"; mkdir -p "$H"
( cd "$H"
  source "$ROOT/bin/lib.sh" 2>/dev/null
  assert_eq "0" "$PROJECT_ROOT_VALID" "# 포함 VALID=0"
)
rm -rf "$(dirname "$H")"

test_summary
```

- [ ] **Step 2: fail 확인**

```
bash tests/test-path-validation.sh
```
Expected: FAIL — `PROJECT_ROOT_VALID` 미정의.

- [ ] **Step 3: lib.sh 추가 구현**

T1 의 `PROJECT_ROOT_IS_GIT` 블록 직후, `WORKSPACE=` 라인 **앞에** 추가:

```bash
# 경로 정합성 검증 (E4·F1·F4): sed 구분자·셸 메타문자·quoting 실수 위험 회피.
# 허용: [A-Za-z0-9/._-]. 공백 미허용(F4 보수).
# lib.sh 는 source 파일이라 exit 금지 → 변수로 결과 전달 (F1).
# 호출 스크립트는 source 후 `[ "$PROJECT_ROOT_VALID" = "1" ] || exit 1`.
PROJECT_ROOT_VALID=1
case "$PROJECT_ROOT" in
  *[!A-Za-z0-9/._-]*)
    echo "오류: PROJECT_ROOT='$PROJECT_ROOT' 에 허용되지 않는 문자 포함." >&2
    echo "  허용: [A-Za-z0-9/._-] (공백 미허용). 디렉터리 이름 정리 후 재시도." >&2
    PROJECT_ROOT_VALID=0 ;;
esac
```

- [ ] **Step 4: pass 확인**

```
bash tests/test-path-validation.sh
```
Expected: PASS (3 tests).

- [ ] **Step 5: commit**

```bash
git add bin/lib.sh tests/test-path-validation.sh
git commit -m "feat: T2 lib.sh path validation — PROJECT_ROOT_VALID 변수 (F1·F4)

source 안전성 위해 exit 대신 변수 전달. 호출자가 명시 검사.
허용: [A-Za-z0-9/._-]. 공백 금지(셸 quoting 실수 위험·F4 보수).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: lib.sh — _session_autoname + resolve_session 폴백 확장

**의도**: `agents-<sanitize(basename)>` 자동명. sed 기반 sanitize (bash 3.2 호환).

**Files:**
- Modify: `bin/lib.sh` (기존 resolve_session 영역)
- Create: `tests/test-session-autoname.sh`

- [ ] **Step 1: failing test 작성**

`tests/test-session-autoname.sh`:
```bash
#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"

# T3.1 — 폴백: agents-<basename>
unset SESSION_OVERRIDE PROFILE_SESSION SESSION HARNESS_PROJECT
G="$(mktemp -d)/projectA"; mkdir -p "$G" && ( cd "$G" && git init -q )
( cd "$G"
  source "$ROOT/bin/lib.sh" 2>/dev/null
  assert_eq "agents-projectA" "$(resolve_session)" "자동명 폴백"
)
rm -rf "$(dirname "$G")"

# T3.2 — sanitize: 특수문자 → _
G="$(mktemp -d)/proj.A-1"; mkdir -p "$G" && ( cd "$G" && git init -q )
( cd "$G"
  source "$ROOT/bin/lib.sh" 2>/dev/null
  # . 는 허용 문자 아님(_session_autoname 의 [^A-Za-z0-9_-] 기준)
  assert_eq "agents-proj_A-1" "$(resolve_session)" "sanitize . → _"
)
rm -rf "$(dirname "$G")"

# T3.3 — SESSION_OVERRIDE 우선 (resolve_session 호출 검증) — P5: 죽은 코드 제거
G="$(mktemp -d)/projectA"; mkdir -p "$G" && ( cd "$G" && git init -q )
( cd "$G"
  source "$ROOT/bin/lib.sh" 2>/dev/null
  export SESSION_OVERRIDE="custom_x"
  assert_eq "custom_x" "$(resolve_session)" "resolve_session OVERRIDE 우선"
  unset SESSION_OVERRIDE
  # PROFILE_SESSION 우선 (OVERRIDE 없을 때)
  export PROFILE_SESSION="profile_x"
  assert_eq "profile_x" "$(resolve_session)" "resolve_session PROFILE_SESSION 우선"
  unset PROFILE_SESSION
  # 둘 다 없으면 자동명
  assert_eq "agents-projectA" "$(resolve_session)" "자동명 폴백"
)
rm -rf "$(dirname "$G")"

test_summary
```

- [ ] **Step 2: fail 확인**

```
bash tests/test-session-autoname.sh
```
Expected: FAIL — 기존 `resolve_session` 은 `SESSION_DEFAULT="agents"` 폴백만 사용.

- [ ] **Step 3: lib.sh 수정**

기존 `resolve_session()` 정의를 다음으로 교체:

```bash
# basename sanitize: tmux 세션명 규칙([A-Za-z0-9_-]).
# bash 3.2 ${var//pattern} 의 glob/정규식 모호성 회피 위해 sed (D3).
_session_autoname() {
  local b safe
  b="$(basename "$PROJECT_ROOT")"
  safe="$(printf '%s' "$b" | sed 's/[^A-Za-z0-9_-]/_/g')"
  printf 'agents-%s' "$safe"
}

# SESSION 결정 우선순위: SESSION_OVERRIDE > PROFILE_SESSION > SESSION env > 자동명.
# 자동명은 PROJECT_ROOT basename 기반이라 멀티 프로젝트 동시 가동 시 자연 격리.
resolve_session() {
  printf '%s' "${SESSION_OVERRIDE:-${PROFILE_SESSION:-${SESSION:-$(_session_autoname)}}}"
}
```

**Q9: `SESSION_DEFAULT` 와 `session_exists()` 처리**
- `SESSION_DEFAULT="agents"` 는 새 `resolve_session()` 에서 미사용 (자동명 폴백이 대체).
- 그러나 기존 lib.sh 의 `session_exists()` 함수가 `local s="${1:-$SESSION_DEFAULT}"` 사용 — 별도 호출자가 인자 없이 호출하면 폴백.
- 검색:
  ```bash
  grep -rn "session_exists\|SESSION_DEFAULT" bin/ tests/
  ```
  결과 분석:
  - `session_exists` 호출처 없으면 → 함수+SESSION_DEFAULT 제거 가능 (깨끗한 전환)
  - 호출처 있으면 → SESSION_DEFAULT 유지 (호환)
- 보수적: 두 라인 모두 유지 (테스트가 직접 참조하던 케이스 대비). 제거는 후속 cleanup.

- [ ] **Step 4: pass 확인**

```
bash tests/test-session-autoname.sh
```
Expected: PASS (3 tests).

- [ ] **Step 5: 기존 회귀**

```
bash tests/test-session-resolve.sh 2>&1 | tail -10
```
Expected: 기존 5 케이스 모두 PASS (SESSION_OVERRIDE·PROFILE_SESSION 패턴 그대로).

- [ ] **Step 6: commit**

```bash
git add bin/lib.sh tests/test-session-autoname.sh
git commit -m "feat: T3 _session_autoname + resolve_session 폴백 확장 (D3)

자동명 agents-<sanitize(basename PROJECT_ROOT)>. sed 기반 sanitize
(bash 3.2 \${var//pattern} glob 모호성 회피). SESSION_OVERRIDE·
PROFILE_SESSION·SESSION env 우선순위 유지·기존 호환.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: --project 옵션 파서 helper (lib.sh 끝부분)

**의도**: 각 bin 스크립트가 lib.sh source 이전에 같은 파서를 쓰게 함. silent failure 회피(F2).

**Files:**
- Modify: `bin/lib.sh` (파일 끝)
- Create: `tests/test-project-flag.sh`

**중요**: 이 task 는 `--project` 파서 함수만 lib.sh 에 넣음. 실제 bin 스크립트 진입부 사용은 T8~T12 에서. lib.sh 가 source 되기 전에는 함수 사용 불가하므로, 이 단계에서는 **각 bin 스크립트 진입부에 inline 으로 작성하기 위한 표준 코드 블록 검증**.

- [ ] **Step 1: failing test 작성**

`tests/test-project-flag.sh`:
```bash
#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"

# T4.1 — _normalize_project: 절대경로 정규화
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/projectA"
unset HARNESS_PROJECT
source "$ROOT/bin/lib.sh" 2>/dev/null

# 상대경로 → 절대경로
( cd "$TMP"
  result="$(_normalize_project "projectA")"
  expected="$TMP/projectA"
  # macOS pwd -P symlink 정규화
  result_real="$(cd "$result" && pwd -P)"
  expected_real="$(cd "$expected" && pwd -P)"
  assert_eq "$expected_real" "$result_real" "상대→절대 정규화"
)

# T4.2 — 존재하지 않는 경로 → return 1·stderr
set +e
out="$(_normalize_project "/no/such/path" 2>&1 >/dev/null)"
rc=$?
set -e
assert_eq "1" "$rc" "bad path → return 1"
echo "$out" | grep -q "경로 없음"; assert_success "$?" "bad path stderr"

test_summary
```

- [ ] **Step 2: fail 확인**

```
bash tests/test-project-flag.sh
```
Expected: FAIL — `_normalize_project` 미정의.

- [ ] **Step 3: lib.sh 끝에 추가**

`bin/lib.sh` 의 `send_prompt()` 함수 정의 뒤(파일 끝)에 추가:

```bash
# --project 인자 정규화 (E12·F2). stdout=절대경로, $?=0 성공, return 1 실패.
# subshell 안 exit silent failure 회피 위해 return 사용·호출자 명시 검사.
_normalize_project() {  # $1=raw → stdout=절대경로
  local raw="$1"
  if [ ! -d "$raw" ]; then
    echo "오류: --project 경로 없음: $raw" >&2
    return 1
  fi
  ( cd "$raw" && pwd )
}
```

- [ ] **Step 4: pass 확인**

```
bash tests/test-project-flag.sh
```
Expected: PASS (2 tests).

- [ ] **Step 5: commit**

```bash
git add bin/lib.sh tests/test-project-flag.sh
git commit -m "feat: T4 _normalize_project helper (E12·F2)

--project 인자 절대경로 정규화. return 1 + stderr 로 silent failure
회피 (subshell 안 exit 가 HARNESS_PROJECT 빈값 폴백되던 위험).
실제 bin/ 스크립트 진입부 사용은 T8~T12 에서.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: templates/settings.json.tpl 신설 (workspace/.claude/ 에서 이동)

**의도**: 토큰 이름 의미 분리(`__PROJECT_ROOT__`·`__HARNESS_ROOT__`). 디렉터리 자리도 정의 자산임을 명확히.

**Files:**
- Create: `templates/settings.json.tpl`
- Delete: `workspace/.claude/settings.json.tpl` (실제 삭제는 T13)

- [ ] **Step 1: 신규 파일 작성**

`templates/settings.json.tpl`:
```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "EVENTS_LOG=\"__PROJECT_ROOT__/.agent-harness/events.log\" REPO_ROOT=\"__PROJECT_ROOT__\" bash \"__HARNESS_ROOT__/bin/log-event.sh\""
          }
        ]
      }
    ]
  }
}
```

- [ ] **Step 2: 디렉터리 mkdir + 파일 생성 확인**

```bash
mkdir -p templates
# (위 파일이 이미 그 자리에 만들어졌어야 함)
[ -f templates/settings.json.tpl ] && echo "OK" || echo "FAIL"
```
Expected: `OK`.

- [ ] **Step 3: 토큰 sed 치환 sanity 검사**

```bash
sed -e 's#__PROJECT_ROOT__#/tmp/projA#g' -e 's#__HARNESS_ROOT__#/tmp/hr#g' templates/settings.json.tpl | grep -o '__[A-Z_]*__' | head -3
```
Expected: (빈 출력) — 모든 토큰 치환됨.

- [ ] **Step 4: commit**

```bash
git add templates/settings.json.tpl
git commit -m "feat: T5 templates/settings.json.tpl 신설

workspace/.claude/settings.json.tpl 의 위치·토큰 명확화. 토큰
__PROJECT_ROOT__·__HARNESS_ROOT__ 로 의미 분리. 디렉터리 자리도
하네스 정의 자산임을 표명. 기존 파일 삭제는 T13 cleanup 에서.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: bin/team-up.sh — --project 파서 + lib.sh 검증 + 새 경로

**의도**: 가장 큰 변경. team-up 이 PROJECT_ROOT 기반으로 모든 자원 배치.

**Files:**
- Modify: `bin/team-up.sh` (대부분)
- Modify: `tests/test-team-up.sh`·`tests/test-team-up-harness.sh` (workspace → .agent-harness 경로)

- [ ] **Step 1: 기존 테스트 setup 보강 (P8·P19 구체화)**

`tests/test-team-up.sh`·`tests/test-team-up-harness.sh` 의 실제 사용처(2026-05-20 시점):
```
tests/test-team-up.sh:11:cleanup() { tmux kill-session -t "$SESSION_OVERRIDE" 2>/dev/null || true; rm -rf "$ROOT/workspace/.boot"; }
tests/test-team-up.sh:49:assert_eq "0" "$([ -f "$ROOT/workspace/.boot/dev.md" ] && echo 0 || echo 1)" "dev.md boot 생성"
tests/test-team-up.sh:50:BOOT="$(cat "$ROOT/workspace/.boot/dev.md")"
```

`tests/test-team-up.sh` 상단(`SESSION_OVERRIDE=...; export ...` 다음) 에 추가:
```bash
# T6: PROJECT_ROOT 분리 후엔 임시 git repo 가 PROJECT_ROOT 가 됨
TMP_PROJ="$(mktemp -d)"; ( cd "$TMP_PROJ" && git init -q )
export HARNESS_PROJECT="$TMP_PROJ"
```

기존 cleanup() 함수를 다음으로 변경 (P8: SESSION_OVERRIDE + HARNESS_PROJECT 양쪽 정리):
```bash
cleanup() {
  tmux kill-session -t "$SESSION_OVERRIDE" 2>/dev/null || true
  rm -rf "$TMP_PROJ"
}
```

라인 49·50 의 `$ROOT/workspace/.boot/dev.md` 를 `$TMP_PROJ/.agent-harness/.boot/dev.md` 로 변경:
```bash
assert_eq "0" "$([ -f "$TMP_PROJ/.agent-harness/.boot/dev.md" ] && echo 0 || echo 1)" "dev.md boot 생성"
BOOT="$(cat "$TMP_PROJ/.agent-harness/.boot/dev.md")"
```

`tests/test-team-up-harness.sh` 도 동일 패턴:
```bash
grep -n "workspace/\|/workspace" tests/test-team-up-harness.sh
```
결과 라인 각각 `$TMP_PROJ/.agent-harness/...` 로 변경. trap·cleanup 도 위 패턴 적용.

- [ ] **Step 2: team-up.sh 진입부 (옵션 파서)**

`bin/team-up.sh` 의 shebang 다음 줄들을 다음으로 시작:

```bash
#!/usr/bin/env bash
set -euo pipefail

_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --project 옵션 파서 (E7·F2). lib.sh source 이전 실행.
# _normalize_project 는 lib.sh 안에 있으나 함수 정의가 필요해 inline 복제.
_normalize_project_arg() {
  local raw="${1:-}"
  if [ -z "$raw" ]; then
    echo "오류: --project 인자 누락 (값 필요)" >&2
    return 1
  fi
  if [ ! -d "$raw" ]; then
    echo "오류: --project 경로 없음: $raw" >&2
    return 1
  fi
  ( cd "$raw" && pwd )
}
while [ $# -gt 0 ]; do
  case "$1" in
    --project)
      # P6: set -u 환경에서 $2 미정의 보호. ${2:-} 으로 함수 안에서 누락 검사.
      if ! HARNESS_PROJECT="$(_normalize_project_arg "${2:-}")"; then exit 1; fi
      export HARNESS_PROJECT; shift 2 ;;
    --project=*)
      if ! HARNESS_PROJECT="$(_normalize_project_arg "${1#--project=}")"; then exit 1; fi
      export HARNESS_PROJECT; shift ;;
    *) break ;;
  esac
done

source "$_DIR/lib.sh"
[ "$PROJECT_ROOT_VALID" = "1" ] || exit 1
```

(`_normalize_project_arg` 가 lib.sh 의 `_normalize_project` 와 동명 충돌 안 하도록 별도 이름. lib.sh source 후엔 동일 logic 의 함수가 있지만 inline 으로 미리 정의해도 무해.)

- [ ] **Step 3: team-up.sh 본문 — PROFILE 로딩**

기존 `PROFILE="${1:-default}"` 줄 그대로. 이전 줄들(`SESSION` 설정·`AGENT_CMD` 등) 검토:

```bash
PROFILE="${1:-default}"
if [ -f "$PROFILE" ]; then
  PROFILE_FILE="$PROFILE"
else
  PROFILE_FILE="$HARNESS_ROOT/profiles/$PROFILE.sh"
fi
if [ ! -f "$PROFILE_FILE" ]; then
  echo "오류: 프로파일 없음 → $PROFILE_FILE" >&2
  echo "사용 가능: $(ls "$HARNESS_ROOT/profiles" 2>/dev/null | sed 's/\.sh$//' | tr '\n' ' ')" >&2
  exit 1
fi
# shellcheck disable=SC1090
source "$PROFILE_FILE"
export PROFILE_SESSION="${SESSION:-}"
SESSION="$(resolve_session)"
AGENT_CMD="${AGENT_CMD:-claude}"
```

기존의 `REPO_ROOT/profiles` 참조를 `HARNESS_ROOT/profiles` 로 변경. 이외 본문(`parse_entry`·`agent_cmd_for` 함수)은 무변경.

- [ ] **Step 4: team-up.sh — 중복 가동 검사 + mkdir**

```bash
if tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "오류: 세션 '$SESSION' 이미 존재 (PROJECT_ROOT=$PROJECT_ROOT). attach 하거나 team-down.sh 후 재시도." >&2
  exit 1
fi

mkdir -p "$WORKSPACE/.boot" "$WORKSPACE/tasks" "$WORKSPACE/results" "$WORKSPACE/review"
```

- [ ] **Step 5: team-up.sh — settings.json·marker 생성 (marker 게이트 D2)**

기존 settings.json 생성 블록을 다음으로 교체:

```bash
# PostToolUse hook 설정을 머신 절대경로로 치환해 생성 (T6, 이슈 6·7).
# D2·E8: marker 파일로 보호 — marker 없는 settings.json 은 사용자 작성물로 간주, 거부.
if [ -f "$HARNESS_ROOT/templates/settings.json.tpl" ]; then
  MARKER="$PROJECT_ROOT/.claude/.agent-harness-marker"
  if [ -f "$PROJECT_ROOT/.claude/settings.json" ] && [ ! -f "$MARKER" ]; then
    echo "오류: $PROJECT_ROOT/.claude/settings.json 이미 존재 (하네스 생성물 아님)." >&2
    echo "  수동 처리 필요. 우리 hook 을 머지하거나 사용자 설정 백업 후 재시도." >&2
    exit 1
  fi
  mkdir -p "$PROJECT_ROOT/.claude"
  sed -e "s#__PROJECT_ROOT__#$PROJECT_ROOT#g" \
      -e "s#__HARNESS_ROOT__#$HARNESS_ROOT#g" \
      "$HARNESS_ROOT/templates/settings.json.tpl" \
      > "$PROJECT_ROOT/.claude/settings.json"
  printf 'generated by agent-harness — do not edit settings.json (regenerated by bin/team-up.sh)\n' > "$MARKER"
fi

# .gitignore 안내 (E5: git repo 일 때만, D5: settings.json 룰은 안내 X).
if [ "$PROJECT_ROOT_IS_GIT" = "1" ] && [ -f "$PROJECT_ROOT/.gitignore" ]; then
  if ! grep -q '^\.agent-harness/' "$PROJECT_ROOT/.gitignore" 2>/dev/null; then
    echo "안내: $PROJECT_ROOT/.gitignore 에 '.agent-harness/' 룰 추가 권장" >&2
  fi
fi
```

- [ ] **Step 6: team-up.sh — `$REPO_ROOT` 사용처 의미별 분류·교체 (전체 14곳)**

먼저 사용처 전수:
```bash
grep -n "REPO_ROOT" bin/team-up.sh
```

각 라인의 의미별 분류·교체 규칙:

| 라인(원본) | 의미 | 교체 |
|---|---|---|
| `PROFILE_FILE="$REPO_ROOT/profiles/..."` | 정의 자산 | `$HARNESS_ROOT` |
| `ls "$REPO_ROOT/profiles"` (사용 가능 안내) | 정의 자산 | `$HARNESS_ROOT` |
| `[ -f "$REPO_ROOT/workspace/.claude/settings.json.tpl" ]` | T5 후 위치 변경 → `$HARNESS_ROOT/templates/settings.json.tpl` (§Step 5 에서 이미 처리) | (§Step 5) |
| `mkdir -p "$REPO_ROOT/.claude"` | settings.json 출력 위치 (작업 대상) | `$PROJECT_ROOT/.claude` (§Step 5) |
| `sed "s#__REPO__#$REPO_ROOT#g" ... > "$REPO_ROOT/.claude/settings.json"` | T5 후 토큰 변경 → `__PROJECT_ROOT__`·`__HARNESS_ROOT__` (§Step 5) | (§Step 5) |
| `cat "$REPO_ROOT/prompts/_common.md" "$REPO_ROOT/prompts/roles/..."` | 정의 자산 | `$HARNESS_ROOT/prompts/...` |
| `tmux send-keys ... "cd \"$REPO_ROOT\" && $(agent_cmd_for ...)"` (워커 루프) | 워커 cwd = 작업 대상 | `cd \"$PROJECT_ROOT\"` |
| `head -1 "$REPO_ROOT/prompts/roles/$ENTRY_ROLE.md"` (카탈로그) | 정의 자산 | `$HARNESS_ROOT/prompts/...` |
| `cat "$REPO_ROOT/prompts/roles/orchestrator.md"` | 정의 자산 | `$HARNESS_ROOT/prompts/...` |
| `tmux send-keys ... "cd \"$REPO_ROOT\" && $(agent_cmd_for ...)"` (오케) | 메인 cwd = 작업 대상 | `cd \"$PROJECT_ROOT\"` |
| `inject_loop "$ORCH_PID" "$REPO_ROOT/prompts/loop/orchestrator.md"` | 정의 자산 | `$HARNESS_ROOT/prompts/...` |
| `cat "$REPO_ROOT/prompts/roles/$ENTRY_ROLE.md"` (리뷰어 boot) | 정의 자산 | `$HARNESS_ROOT/prompts/...` |
| `tmux send-keys ... "cd \"$REPO_ROOT\" && $(agent_cmd_for ...)"` (리뷰어) | 리뷰어 cwd = 작업 대상 | `cd \"$PROJECT_ROOT\"` |
| `inject_loop "$rtgt" "$REPO_ROOT/prompts/loop/reviewer.md"` | 정의 자산 | `$HARNESS_ROOT/prompts/...` |

요약: `cd "$REPO_ROOT"` 3곳 → `$PROJECT_ROOT`, 그 외 모두 → `$HARNESS_ROOT`. settings.json·mkdir 관련은 §Step 5 에서 이미 처리.

교체 후 검증:
```bash
grep -n "REPO_ROOT" bin/team-up.sh
```
Expected: (빈 출력) — REPO_ROOT 잔존 없음.

- [ ] **Step 7: 테스트 setup 보강 (test-team-up.sh)**

```bash
grep -n 'workspace/' tests/test-team-up.sh tests/test-team-up-harness.sh
```
각 결과 라인을 `.agent-harness/` 로 변경. 또 두 파일 상단(setup 영역)에:
```bash
# T6: PROJECT_ROOT 분리 후엔 임시 git repo 가 PROJECT_ROOT 가 됨
TMP_PROJ="$(mktemp -d)"; ( cd "$TMP_PROJ" && git init -q )
export HARNESS_PROJECT="$TMP_PROJ"
trap 'tmux kill-session -t "$SESSION_OVERRIDE" 2>/dev/null; rm -rf "$TMP_PROJ"' EXIT
```
기존 trap 이 있으면 합쳐서 사용.

- [ ] **Step 8: 회귀 검증**

```bash
bash tests/test-team-up.sh 2>&1 | tail -20
bash tests/test-team-up-harness.sh 2>&1 | tail -10
```
Expected: 모두 PASS.

```bash
bash tests/run-all.sh 2>&1 | tail -3
```
Expected: 여전히 일부 fail 가능 (T8~T12 의 dispatch·wait-worker·team-down·log-event 가 아직 안 바뀌어서 workspace 경로 의존).

- [ ] **Step 9: commit**

```bash
git add bin/team-up.sh tests/test-team-up.sh tests/test-team-up-harness.sh
git commit -m "feat: T6 team-up.sh — --project + PROJECT_ROOT 기반 가동

--project 파서 (lib.sh source 이전), PROJECT_ROOT_VALID 검사,
mkdir \\\$WORKSPACE/{.boot,tasks,results,review} (=PROJECT_ROOT/
.agent-harness/), settings.json + marker 생성, .gitignore 안내
(git repo 한정·D5·E5), 워커 cwd=PROJECT_ROOT, boot 소스
HARNESS_ROOT.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: bin/log-event.sh — 메타 화이트리스트 skip + 경로 이름

**의도**: hook 이 메타 산출물 변경은 무시(루프 차단·일관성). skip 검사를 절대경로 기준으로(F6).

**Files:**
- Modify: `bin/log-event.sh`
- Modify: `tests/test-log-event.sh`

- [ ] **Step 1: 테스트 보강 — 메타 skip 검증**

`tests/test-log-event.sh` 의 마지막 `test_summary` 직전에 추가:

```bash
# T7.1 — events.log 자기자신 변경은 skip
TMP="$(mktemp -d)"; mkdir -p "$TMP/.agent-harness"
EVENTS_LOG="$TMP/.agent-harness/events.log"
REPO_ROOT="$TMP"
HARNESS_WORKER=worker1
input='{"tool_input":{"file_path":"'"$TMP"'/.agent-harness/events.log"}}'
out="$(printf '%s' "$input" | EVENTS_LOG="$EVENTS_LOG" REPO_ROOT="$REPO_ROOT" HARNESS_WORKER="$HARNESS_WORKER" bash "$ROOT/bin/log-event.sh")"
assert_eq "" "$(cat "$EVENTS_LOG" 2>/dev/null)" "events.log 자기변경 skip"

# T7.2 — tasks/results 변경은 기록됨
input='{"tool_input":{"file_path":"'"$TMP"'/.agent-harness/results/1.md"}}'
printf '%s' "$input" | EVENTS_LOG="$EVENTS_LOG" REPO_ROOT="$REPO_ROOT" HARNESS_WORKER="$HARNESS_WORKER" bash "$ROOT/bin/log-event.sh"
grep -q "results/1.md" "$EVENTS_LOG"; assert_success "$?" "results/ 는 기록됨"

# T7.3 — .review-cursor.* 는 skip
: > "$EVENTS_LOG"
input='{"tool_input":{"file_path":"'"$TMP"'/.agent-harness/.review-cursor.spec-rev"}}'
printf '%s' "$input" | EVENTS_LOG="$EVENTS_LOG" REPO_ROOT="$REPO_ROOT" HARNESS_WORKER="$HARNESS_WORKER" bash "$ROOT/bin/log-event.sh"
assert_eq "" "$(cat "$EVENTS_LOG")" ".review-cursor.* skip"

rm -rf "$TMP"
```

- [ ] **Step 2: fail 확인**

```
bash tests/test-log-event.sh 2>&1 | tail -10
```
Expected: T7.1·T7.3 FAIL (skip 가드 없음).

- [ ] **Step 3: log-event.sh 수정**

`bin/log-event.sh` 의 hook 본문, `fpath` 추출 직후·`rel` 변환 **이전**에 추가:

```bash
[ -z "$fpath" ] && exit 0   # 경로 없는 도구 호출은 무시 (기존)

# 메타 산출물 화이트리스트 skip (D6·F6).
# tasks/results 는 작업 흐름이라 기록 대상. 메타(events.log 자체·커서·상태·boot·review/) 만 skip.
# repo-relative 변환 전, 절대경로 기준으로 점검 (F6: 절대경로 Write 도 잡힘).
case "$fpath" in
  "$REPO_ROOT/.agent-harness/events.log") exit 0 ;;
  "$REPO_ROOT/.agent-harness/.review-cursor."*) exit 0 ;;
  "$REPO_ROOT/.agent-harness/.harness-task."*) exit 0 ;;
  "$REPO_ROOT/.agent-harness/.harness-state") exit 0 ;;
  "$REPO_ROOT/.agent-harness/.boot/"*) exit 0 ;;
  "$REPO_ROOT/.agent-harness/review/"*) exit 0 ;;
esac

# repo 상대경로화 (길이 억제 — spec §5.2)
case "$fpath" in
  "$REPO_ROOT"/*) rel="${fpath#"$REPO_ROOT"/}" ;;
  *) rel="$fpath" ;;
esac
```

또 기존 `_htf="${REPO_ROOT}/workspace/.harness-task.${worker}"` 를:
```bash
_htf="${REPO_ROOT}/.agent-harness/.harness-task.${worker}"
```

기본값 줄:
```bash
EVENTS_LOG="${EVENTS_LOG:-$REPO_ROOT/.agent-harness/events.log}"
```
(기존 `workspace/events.log` 에서 `.agent-harness/events.log` 로)

- [ ] **Step 4: pass 확인**

```
bash tests/test-log-event.sh 2>&1 | tail -15
```
Expected: 모두 PASS (기존 5 + 신규 3 = 8).

- [ ] **Step 5: commit**

```bash
git add bin/log-event.sh tests/test-log-event.sh
git commit -m "feat: T7 log-event 메타 화이트리스트 skip (D6·F6)

tasks/results 는 기록 대상, 메타(events.log·커서·상태·boot·review/)
만 skip. skip 검사는 repo-relative 변환 이전 절대경로 기준 — 워커가
절대경로 Write 해도 잡힘 (F6). 경로명 .agent-harness/ 로 갱신.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 8: bin/dispatch.sh — --project 파서 + CHANNEL 갱신

**의도**: dispatch 도 cwd 의존 깨는 escape hatch 지원. 채널명에 SESSION prefix(E1) — 단 dispatch 는 채널을 쓰는 워커 쪽 send_prompt 와 무관, write_harness_task 만 호출. CHANNEL 변경은 wait-worker 에서.

**Files:**
- Modify: `bin/dispatch.sh`
- Modify: `tests/test-dispatch.sh` (HARNESS_PROJECT setup)

- [ ] **Step 1: 테스트 setup 보강 (P19 구체화)**

`tests/test-dispatch.sh` 의 실제 사용처:
```
tests/test-dispatch.sh:10:cleanup() { tmux kill-session -t "$SESSION_OVERRIDE" 2>/dev/null || true; rm -rf "$ROOT/workspace/.boot"; rm -f "$ROOT/workspace/tasks/T1.md"; }
tests/test-dispatch.sh:17:echo "# T1: 더미 작업" > "$ROOT/workspace/tasks/T1.md"
```

`tests/test-dispatch.sh` 상단(SESSION_OVERRIDE 셋 다음)에 추가:
```bash
TMP_PROJ="$(mktemp -d)"; ( cd "$TMP_PROJ" && git init -q )
export HARNESS_PROJECT="$TMP_PROJ"
mkdir -p "$TMP_PROJ/.agent-harness/tasks"   # team-up 이 mkdir 하지만 이 테스트는 dispatch 단독이라 미리
```

cleanup() 함수를 다음으로 변경:
```bash
cleanup() {
  tmux kill-session -t "$SESSION_OVERRIDE" 2>/dev/null || true
  rm -rf "$TMP_PROJ"
}
```

라인 17 의 task 파일 작성을:
```bash
echo "# T1: 더미 작업" > "$TMP_PROJ/.agent-harness/tasks/T1.md"
```

- [ ] **Step 2: dispatch.sh 진입부 (옵션 파서)**

```bash
#!/usr/bin/env bash
set -euo pipefail

_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

_normalize_project_arg() {
  local raw="${1:-}"
  if [ -z "$raw" ]; then
    echo "오류: --project 인자 누락 (값 필요)" >&2
    return 1
  fi
  if [ ! -d "$raw" ]; then
    echo "오류: --project 경로 없음: $raw" >&2
    return 1
  fi
  ( cd "$raw" && pwd )
}
while [ $# -gt 0 ]; do
  case "$1" in
    --project)
      # P6: set -u 환경에서 $2 미정의 보호. ${2:-} 으로 함수 안에서 누락 검사.
      if ! HARNESS_PROJECT="$(_normalize_project_arg "${2:-}")"; then exit 1; fi
      export HARNESS_PROJECT; shift 2 ;;
    --project=*)
      if ! HARNESS_PROJECT="$(_normalize_project_arg "${1#--project=}")"; then exit 1; fi
      export HARNESS_PROJECT; shift ;;
    *) break ;;
  esac
done

source "$_DIR/lib.sh"
[ "$PROJECT_ROOT_VALID" = "1" ] || exit 1

SESSION="$(resolve_session)"
```

- [ ] **Step 3: dispatch.sh 본문 — TASK_FILE 경로**

기존 `TASK_FILE="$WORKSPACE/tasks/$TASK_ID.md"` 그대로 (WORKSPACE 의미 변경 자동 흡수).

`write_harness_task` 호출도 그대로. `send_prompt` 도 그대로.

- [ ] **Step 4: pass 확인**

```
bash tests/test-dispatch.sh 2>&1 | tail -10
```
Expected: PASS.

- [ ] **Step 5: commit**

```bash
git add bin/dispatch.sh tests/test-dispatch.sh
git commit -m "feat: T8 dispatch.sh --project + PROJECT_ROOT 자동 흡수

옵션 파서 lib.sh source 이전, PROJECT_ROOT_VALID 검사. WORKSPACE
의미 변경(.agent-harness/) 자동 흡수. 테스트 setup 에 HARNESS_PROJECT
임시 git repo 패턴 추가.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 9: bin/wait-worker.sh — --project + CHANNEL SESSION prefix (E1)

**의도**: 채널명에 SESSION 포함 — 멀티 동시 가동 시 신호 충돌 차단.

**Files:**
- Modify: `bin/wait-worker.sh`
- Create: `tests/test-channel-name.sh`
- Modify: `tests/test-wait-worker.sh` (HARNESS_PROJECT setup + 새 채널명)

- [ ] **Step 1: 신규 테스트 작성**

`tests/test-channel-name.sh`:
```bash
#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"

# E1: 같은 worker·task 라도 SESSION 다르면 채널명 다름
TMP1="$(mktemp -d)/projectA"; mkdir -p "$TMP1" && ( cd "$TMP1" && git init -q )
TMP2="$(mktemp -d)/projectB"; mkdir -p "$TMP2" && ( cd "$TMP2" && git init -q )

# projectA 에서 채널명 추론
( cd "$TMP1"
  source "$ROOT/bin/lib.sh" 2>/dev/null
  SESS="$(resolve_session)"
  ch="done-$SESS-dev-T1"
  assert_eq "done-agents-projectA-dev-T1" "$ch" "projectA 채널"
)

# projectB
( cd "$TMP2"
  source "$ROOT/bin/lib.sh" 2>/dev/null
  SESS="$(resolve_session)"
  ch="done-$SESS-dev-T1"
  assert_eq "done-agents-projectB-dev-T1" "$ch" "projectB 채널"
)

# 두 채널이 달라야 함
ch_a="done-agents-projectA-dev-T1"
ch_b="done-agents-projectB-dev-T1"
[ "$ch_a" != "$ch_b" ]; assert_success "$?" "두 SESSION 채널 다름"

rm -rf "$(dirname "$TMP1")" "$(dirname "$TMP2")"
test_summary
```

- [ ] **Step 2: wait-worker CHANNEL grep 검증 케이스 추가 (TDD fail 확보)**

위 `test-channel-name.sh` 끝(`test_summary` 직전)에 추가:
```bash
# T9.bis — wait-worker.sh 의 CHANNEL 정의가 SESSION 포함하는지 정적 검증
grep -q 'CHANNEL="done-\$SESSION-\$WORKER-\$TASK_ID"' "$ROOT/bin/wait-worker.sh"
assert_success "$?" "wait-worker CHANNEL SESSION prefix 포함"
```

```
bash tests/test-channel-name.sh
```
Expected: 마지막 케이스 FAIL — 현 `wait-worker.sh` 는 `done-$WORKER-$TASK_ID` (SESSION 미포함). Step 3 의 수정 후 PASS.

- [ ] **Step 3: wait-worker.sh 수정**

기존:
```bash
CHANNEL="done-$WORKER-$TASK_ID"
```
을:
```bash
CHANNEL="done-$SESSION-$WORKER-$TASK_ID"
```
(E1)

진입부도 dispatch 와 동일하게 `--project` 파서 + `PROJECT_ROOT_VALID` 검사 추가.

- [ ] **Step 4: test-wait-worker.sh setup 보강 (P16 구체화)**

`tests/test-wait-worker.sh` 의 실제 사용처:
```
tests/test-wait-worker.sh:10:cleanup() { tmux kill-session -t "$SESSION_OVERRIDE" 2>/dev/null || true; rm -rf "$ROOT/workspace/.boot"; }
```

먼저 채널명 hardcode 검색:
```bash
grep -nE "done-[a-z]" tests/test-wait-worker.sh
```
결과 라인의 채널명을 `done-$SESSION-...` 패턴으로 갱신 (이때 `$SESSION` 은 테스트가 사용하는 SESSION_OVERRIDE 값). 예시:
- `tmux wait-for -S done-dev-PRE` → `tmux wait-for -S "done-$SESSION_OVERRIDE-dev-PRE"`
- `bin/wait-worker.sh dev PRE` 호출은 그대로 — wait-worker 의 새 CHANNEL 정의가 SESSION 자동 포함

상단(SESSION_OVERRIDE 셋 다음)에:
```bash
TMP_PROJ="$(mktemp -d)"; ( cd "$TMP_PROJ" && git init -q )
export HARNESS_PROJECT="$TMP_PROJ"
```

cleanup() 변경:
```bash
cleanup() {
  tmux kill-session -t "$SESSION_OVERRIDE" 2>/dev/null || true
  rm -rf "$TMP_PROJ"
}
```

- [ ] **Step 5: pass 확인**

```
bash tests/test-wait-worker.sh 2>&1 | tail -10
bash tests/test-channel-name.sh
```
Expected: 모두 PASS.

- [ ] **Step 6: commit**

```bash
git add bin/wait-worker.sh tests/test-wait-worker.sh tests/test-channel-name.sh
git commit -m "feat: T9 wait-worker CHANNEL SESSION prefix (E1)

tmux wait-for 채널이 서버 전역이라 멀티 동시 가동 시 같은
worker·task 면 신호 race. CHANNEL=done-\\\$SESSION-\\\$WORKER-\\\$TASK_ID
로 SESSION(=프로젝트별 자동명) prefix 추가해 격리. 신규
test-channel-name.sh 가 두 SESSION 채널이 다름을 검증.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 10: bin/team-down.sh — --project + marker 게이트 + 살아있는 세션 안내

**의도**: marker 없는 PROJECT_ROOT 에서 호출되어도 사용자 자료 보호. UX 위해 다른 agents-* 세션 안내(F8).

**Files:**
- Modify: `bin/team-down.sh`
- Modify: `tests/test-team-down.sh`

- [ ] **Step 1: 테스트 setup 보강 (P19 구체화)**

`tests/test-team-down.sh` 의 실제 사용처:
```
tests/test-team-down.sh:12:[ -f "$ROOT/workspace/.boot/dev.md" ]; assert_eq "0" "$?" "boot 파일 사전 존재"
tests/test-team-down.sh:19:[ -d "$ROOT/workspace/.boot" ] && [ -n "$(ls -A "$ROOT/workspace/.boot" 2>/dev/null)" ] && r=1 || r=0
```

기존 setup(SESSION_OVERRIDE 등) 다음에 추가:
```bash
# T10 setup: PROJECT_ROOT 분리 + marker 사전 설치
TMP_PROJ="$(mktemp -d)"; ( cd "$TMP_PROJ" && git init -q )
export HARNESS_PROJECT="$TMP_PROJ"
mkdir -p "$TMP_PROJ/.agent-harness/.boot" "$TMP_PROJ/.claude"
touch "$TMP_PROJ/.claude/.agent-harness-marker"   # 기존 시나리오 = marker 있는 정상 정리
echo "boot" > "$TMP_PROJ/.agent-harness/.boot/dev.md"
```

기존 cleanup() 가 있으면 `rm -rf "$TMP_PROJ"` 추가.

라인 12·19 의 `$ROOT/workspace/.boot/...` 를 `$TMP_PROJ/.agent-harness/.boot/...` 로 교체.

또 marker 검증 케이스 신규(나중에 settings-protection 에서 강화 — 여기는 기본만):

```bash
# T10.1 — marker 있을 때 정상 정리
TMP_PROJ="$(mktemp -d)"; ( cd "$TMP_PROJ" && git init -q )
export HARNESS_PROJECT="$TMP_PROJ"
mkdir -p "$TMP_PROJ/.claude" "$TMP_PROJ/.agent-harness"
touch "$TMP_PROJ/.claude/.agent-harness-marker"
echo '{}' > "$TMP_PROJ/.claude/settings.json"
echo "x" > "$TMP_PROJ/.agent-harness/events.log"
# (세션은 이 테스트 컨텍스트에서 SESSION_OVERRIDE 로)
SESSION_OVERRIDE="td_test_$$" tmux new-session -d -s "td_test_$$" 2>/dev/null
SESSION_OVERRIDE="td_test_$$" bash "$ROOT/bin/team-down.sh"
[ ! -f "$TMP_PROJ/.agent-harness/events.log" ]; assert_success "$?" "events.log 정리됨 (marker 있음)"
[ ! -f "$TMP_PROJ/.claude/settings.json" ]; assert_success "$?" "settings.json 정리됨"
[ ! -f "$TMP_PROJ/.claude/.agent-harness-marker" ]; assert_success "$?" "marker 정리됨"
rm -rf "$TMP_PROJ"
```

- [ ] **Step 2: team-down.sh 수정**

`bin/team-down.sh` 의 lib.sh source 이전·이후 흐름 갱신:

```bash
#!/usr/bin/env bash
set -euo pipefail

_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

_normalize_project_arg() {
  local raw="${1:-}"
  if [ -z "$raw" ]; then
    echo "오류: --project 인자 누락 (값 필요)" >&2
    return 1
  fi
  if [ ! -d "$raw" ]; then
    echo "오류: --project 경로 없음: $raw" >&2
    return 1
  fi
  ( cd "$raw" && pwd )
}
while [ $# -gt 0 ]; do
  case "$1" in
    --project)
      # P6: set -u 환경에서 $2 미정의 보호. ${2:-} 으로 함수 안에서 누락 검사.
      if ! HARNESS_PROJECT="$(_normalize_project_arg "${2:-}")"; then exit 1; fi
      export HARNESS_PROJECT; shift 2 ;;
    --project=*)
      if ! HARNESS_PROJECT="$(_normalize_project_arg "${1#--project=}")"; then exit 1; fi
      export HARNESS_PROJECT; shift ;;
    *) break ;;
  esac
done

source "$_DIR/lib.sh"
[ "$PROJECT_ROOT_VALID" = "1" ] || exit 1

SESSION="$(resolve_session)"

# 세션 종료 (있으면) — marker 유무와 무관하게 사용자가 종료 의도. R4: 중복 kill 제거.
if tmux has-session -t "$SESSION" 2>/dev/null; then
  tmux kill-session -t "$SESSION"
  echo "세션 '$SESSION' 종료."
else
  echo "세션 '$SESSION' 없음 (이미 정리됨)."
fi

# E8·F8: marker 없는 PROJECT_ROOT 의 .agent-harness/·settings.json 보호.
# 세션은 이미 위에서 종료됨. 여기서는 파일 정리만 skip.
MARKER="$PROJECT_ROOT/.claude/.agent-harness-marker"
if [ ! -f "$MARKER" ]; then
  echo "경고: marker 없음 ($MARKER) — '$PROJECT_ROOT' 는 하네스로 가동된 적 없는 것으로 판단." >&2
  echo "  .agent-harness/·settings.json 은 건드리지 않음 (세션은 위에서 종료됨)." >&2
  _alive="$(tmux list-sessions -F '#{session_name}' 2>/dev/null | grep '^agents-' || true)"
  if [ -n "$_alive" ]; then
    echo "  참고: 살아있는 agents-* 세션:" >&2
    echo "$_alive" | sed 's/^/    /' >&2
    echo "  특정 프로젝트 종료: '--project /path' 명시" >&2
  fi
  exit 0
fi

# marker 있으면 정상 정리.
if [ -d "$WORKSPACE/.boot" ]; then
  rm -f "$WORKSPACE/.boot"/*.md 2>/dev/null || true
  echo "$WORKSPACE/.boot 정리 완료."
fi

if [ -f "$WORKSPACE/events.log" ]; then
  rm -f "$WORKSPACE/events.log" || true
fi
if [ -f "$WORKSPACE/.harness-state" ]; then
  rm -f "$WORKSPACE/.harness-state" || true
fi
rm -f "$WORKSPACE"/.review-cursor.* 2>/dev/null || true
rm -f "$WORKSPACE"/.harness-task.* 2>/dev/null || true
if [ -d "$WORKSPACE/review" ]; then
  rm -rf "${WORKSPACE:?WORKSPACE unset}/review" || true
fi

# settings.json + marker 정리 (marker 자체도 마지막에)
rm -f "$PROJECT_ROOT/.claude/settings.json" 2>/dev/null || true
rm -f "$MARKER" 2>/dev/null || true

echo "하네스 런타임 산출물 정리 완료 (tasks/results 보존)."
```

- [ ] **Step 3: pass 확인**

```
bash tests/test-team-down.sh 2>&1 | tail -15
```
Expected: 기존 + 신규 모두 PASS.

- [ ] **Step 4: commit**

```bash
git add bin/team-down.sh tests/test-team-down.sh
git commit -m "feat: T10 team-down marker 게이트 + 살아있는 세션 안내 (E8·F8)

marker 없으면 settings.json·.agent-harness/ 안 건드림 — 우연히 만든
디렉터리 보호. 살아있는 agents-* 세션 목록 + --project 안내 stderr.
marker 있으면 정상 정리 (tasks/results 는 보존).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 11: REPO_ROOT 호환 별칭 제거 + 잔여 사용처 정리

**의도**: T1 에서 임시로 남긴 `REPO_ROOT="$HARNESS_ROOT"` 호환 별칭 제거. 모든 사용처가 의미별로 분리됐는지 검증.

**Files:**
- Modify: `bin/lib.sh` (T1 의 호환 별칭 라인 제거)
- 잠재 Modify: 검색 후 잔여 `REPO_ROOT` 사용처 발견되면 의미 분류 후 교체

- [ ] **Step 1: 별칭 의존 검색 + 분류 (P11 구체화)**

```bash
grep -rn "REPO_ROOT" bin/ tests/ prompts/ templates/ 2>/dev/null
```

결과를 다음 분류로 검증:

| 위치 | 정책 | 처리 |
|---|---|---|
| `bin/log-event.sh` 안 `REPO_ROOT` (hook env) | settings.json.tpl 인터페이스 — env 이름 유지 | 그대로 둠 |
| `bin/team-up.sh`·`dispatch.sh`·`wait-worker.sh`·`team-down.sh` | T6~T10 에서 교체됐어야 함 | 잔존 시 의미별 분류 후 `HARNESS_ROOT`·`PROJECT_ROOT` 로 교체 |
| `tests/*.sh` 안 `$ROOT/workspace/...` 같은 사용 | T6·T8·T9·T10 setup 보강에서 `$TMP_PROJ/.agent-harness/...` 로 교체됐어야 함 | 잔존 시 추적·교체 |
| `prompts/*` | `workspace/` → `.agent-harness/` T12 일괄 처리 후 잔존 없어야 함 | 잔존 시 T12 보강 |
| `templates/settings.json.tpl` 의 `REPO_ROOT=` (hook command) | hook env 주입 변수명 — 유지 | 그대로 둠 |

잔존 발견 시 위 분류 기준으로 의미 분류 후 의미별로 교체.

- [ ] **Step 2: lib.sh 의 별칭 제거**

`bin/lib.sh` 의 다음 줄 제거:
```bash
# 마이그레이션 호환 별칭 — 이후 task 에서 모든 사용처 교체 후 제거 (T11 끝).
REPO_ROOT="$HARNESS_ROOT"
```

- [ ] **Step 3: 회귀 검증**

```bash
bash tests/run-all.sh 2>&1 | tail -3
```
Expected: 25 + 신규 합쳐 모두 PASS.

만약 fail 발생하면 stderr 에서 어느 스크립트가 `REPO_ROOT` 미정의로 죽었는지 확인 후, 의미별로 `HARNESS_ROOT`·`PROJECT_ROOT` 로 교체.

- [ ] **Step 4: commit**

```bash
git add bin/lib.sh
git commit -m "refactor: T11 REPO_ROOT 호환 별칭 제거 — 의미 분리 완성

T1~T10 에서 모든 사용처를 HARNESS_ROOT(정의)·PROJECT_ROOT(작업
대상)로 교체. 단 hook env 로 주입되는 REPO_ROOT(=PROJECT_ROOT)는
settings.json.tpl 인터페이스라 그대로 유지.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 12: prompts/ 일괄 — workspace/ → .agent-harness/ + {{SESSION}} 토큰

**의도**: 모든 프롬프트가 새 경로 사용. 채널명에 SESSION 토큰. 자기작업 시 즉시 반영은 다음 team-up 부터(E6).

**Files:**
- Modify: `prompts/_common.md`
- Modify: `prompts/roles/orchestrator.md`
- Modify: `prompts/roles/reviewer-spec.md`·`reviewer-quality.md`·`reviewer-arch.md`
- Modify: `prompts/loop/orchestrator.md`·`prompts/loop/reviewer.md`
- Modify: `bin/team-up.sh` (boot 합본 sed 에 `{{SESSION}}` 토큰 추가)

- [ ] **Step 1: _common.md 갱신**

`prompts/_common.md` 의 모든 `workspace/` 를 `.agent-harness/` 로 변경. 또 wait-for 채널명 줄:
```
tmux wait-for -S done-{{WORKER_NAME}}-<id>
```
→
```
tmux wait-for -S done-{{SESSION}}-{{WORKER_NAME}}-<id>
```

그 줄 다음에 새 줄 추가:
```
주의: 위 채널명의 `done-...-...-<id>` 부분 중 `done-{{SESSION}}-{{WORKER_NAME}}` 은 이미 가동 시 치환되어 박혀있다(예: `done-agents-projectA-dev`). 너의 task id 만 채우고 다른 부분은 변형하지 마라.
```
(F7)

같은 라인의 `printf` 예시 안 채널명도 갱신:
```
printf '%s\t%s\t%s\tdone\t-\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "<너의이름>" "<task>" >> .agent-harness/events.log
```
보조 라인 경로도 `.agent-harness/events.log`.

- [ ] **Step 2: roles/orchestrator.md 갱신**

`prompts/roles/orchestrator.md` 의 `workspace/` → `.agent-harness/` 일괄.

§9 "전체 맥락 유지" 책임 뒤(끝)에 다음 두 줄 추가:
```
10. **호출 위치 책임**: `bin/dispatch.sh`·`bin/wait-worker.sh` 는 cwd=PROJECT_ROOT(=현재 pane cwd) 에서 호출하라. 다른 위치에서 호출하면 잘못된 `.agent-harness` 를 본다. 외부 위치에서 호출 필요 시 `--project /path` 명시.
11. **stale tasks 판별**: team-up 가동 직후 `.agent-harness/tasks/` 의 기존 파일들을 `.harness-state` 와 대조해 활성/완료 판별하라. stale 한(완료된) task 를 새로 배정하지 마라. 모호하면 사용자에게 확인.
```

- [ ] **Step 3: roles/reviewer-*.md 갱신**

3 파일 모두 `workspace/` → `.agent-harness/` 일괄.

- [ ] **Step 4: loop/*.md 갱신**

`prompts/loop/orchestrator.md`·`prompts/loop/reviewer.md` 의 `workspace/` → `.agent-harness/` 일괄.

- [ ] **Step 5: team-up.sh 의 boot 합본 sed 에 `{{SESSION}}` 토큰**

`bin/team-up.sh` 의 워커 boot 합본 생성 라인:
```bash
cat "$HARNESS_ROOT/prompts/_common.md" "$HARNESS_ROOT/prompts/roles/$ENTRY_ROLE.md" \
  | sed "s/{{WORKER_NAME}}/$ENTRY_NAME/g" > "$bf"
```
을:
```bash
cat "$HARNESS_ROOT/prompts/_common.md" "$HARNESS_ROOT/prompts/roles/$ENTRY_ROLE.md" \
  | sed -e "s/{{WORKER_NAME}}/$ENTRY_NAME/g" -e "s/{{SESSION}}/$SESSION/g" > "$bf"
```

리뷰어 boot 도 동일하게 (지금은 `_common.md` 제외라 `{{SESSION}}` 영향 없지만 일관성):
```bash
cat "$HARNESS_ROOT/prompts/roles/$ENTRY_ROLE.md" \
  | sed -e "s/{{SESSION}}/$SESSION/g" > "$rbf" 2>/dev/null || : > "$rbf"
```
(기존 `cat > "$rbf"` 단순화 줄 변경)

- [ ] **Step 6: test-prompts-harness.sh·test-role-prompts.sh 회귀 검증**

```bash
bash tests/test-prompts-harness.sh 2>&1 | tail -5
bash tests/test-role-prompts.sh 2>&1 | tail -5
```
기존 검증 항목이 `workspace/` 문자열 검사하면 깨질 가능성. grep 결과 보고 `.agent-harness/` 로 교체.

```bash
grep -n "workspace/" tests/test-prompts-harness.sh tests/test-role-prompts.sh
```
→ 결과 라인을 `.agent-harness/` 로 교체.

- [ ] **Step 7: 전체 회귀**

```bash
bash tests/run-all.sh 2>&1 | tail -3
```
Expected: 모두 PASS.

- [ ] **Step 8: commit**

```bash
git add prompts/ bin/team-up.sh tests/test-prompts-harness.sh tests/test-role-prompts.sh
git commit -m "feat: T12 prompts workspace→.agent-harness + {{SESSION}} 토큰 (E11·F7)

_common.md·roles·loop 의 workspace/ 모두 .agent-harness/ 로. wait-for
채널명 토큰에 {{SESSION}} 추가, team-up boot 합본 sed 에 치환 추가.
워커 프롬프트에 채널명 변형 금지 1줄 (F7). orchestrator 에 호출 위치
책임·stale tasks 판별 2건 추가.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 13: profiles/*.sh SESSION 라인 삭제 + workspace/ 삭제 + .gitignore 갱신

**의도**: 깨끗한 전환 마무리. 정의 자산만 남기고 1차 토대의 빈 산출물 디렉터리 제거.

**Files:**
- Modify: `profiles/default.sh`·`code-review.sh`·`research.sh`·`feature-team.sh`
- Modify: `.gitignore`
- Delete: `workspace/` 전체

- [ ] **Step 1: profiles 4개 SESSION 라인 삭제**

각 파일에서:
```
SESSION="agents"
```
줄 제거. 나머지 라인(LAYOUT·WORKERS·REVIEWERS·ORCHESTRATOR_MODEL) 그대로.

```bash
for p in profiles/default.sh profiles/code-review.sh profiles/research.sh profiles/feature-team.sh; do
  sed -i.bak '/^SESSION="agents"$/d' "$p" && rm -f "$p.bak"
done
```

- [ ] **Step 2: .gitignore 갱신 (P13 구체화)**

현재 `.gitignore` 의 `workspace/` 관련 라인 검색:
```bash
grep -n "^workspace/" .gitignore
```
Expected (현 main 기준):
```
2:workspace/tasks/
3:workspace/results/
4:workspace/.boot/
```

3개 라인 삭제 + 신규 룰 추가 (macOS BSD/GNU sed 양쪽 호환):
```bash
# 3 라인 제거
sed -i.bak -e '/^workspace\/tasks\/$/d' \
           -e '/^workspace\/results\/$/d' \
           -e '/^workspace\/\.boot\/$/d' .gitignore
rm -f .gitignore.bak

# 신규 룰 추가 (이미 있는지 확인 후)
grep -q '^\.agent-harness/$' .gitignore || echo '.agent-harness/' >> .gitignore
grep -q '^\.claude/\.agent-harness-marker$' .gitignore || echo '.claude/.agent-harness-marker' >> .gitignore
```

검증:
```bash
grep -nE '^(workspace/|\.agent-harness/|\.claude/\.agent-harness-marker)' .gitignore
```
Expected: `workspace/...` 모두 제거됨, `.agent-harness/` 와 `.claude/.agent-harness-marker` 존재. `.claude/settings.json` 룰은 그대로.

- [ ] **Step 3: workspace/ 삭제**

```bash
rm -rf workspace/
```

- [ ] **Step 4: 전체 회귀**

```bash
bash tests/run-all.sh 2>&1 | tail -3
```
Expected: 모두 PASS. fail 시 `grep -rn 'workspace/' tests/ bin/ prompts/` 로 잔여 참조 추적·교체.

- [ ] **Step 5: 프로파일 회귀 검증**

```bash
bash tests/test-profiles.sh 2>&1 | tail -5
bash tests/test-profiles-harness.sh 2>&1 | tail -5
```
Expected: PASS. SESSION 라인 제거가 워커 명·역할·모델 파싱과 무관해야 함. 기존 테스트가 `SESSION="agents"` 검증하면 그 줄 제거.

- [ ] **Step 6: commit**

```bash
git add profiles/ .gitignore
git rm -r workspace/
git commit -m "feat: T13 profiles SESSION 삭제 + workspace/ 폐기 + .gitignore (D8·E8)

profiles 4개 SESSION='agents' 라인 제거 — _session_autoname 폴백
사용으로 멀티 프로젝트 동시 가동 시 자연 격리. .gitignore 에
.agent-harness/·marker 추가. workspace/ 디렉터리 전체 삭제 — 정의는
HARNESS_ROOT 공유, 결과는 PROJECT_ROOT/.agent-harness/.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 14: test-self-harness.sh (자기작업 검증)

**의도**: cwd=HARNESS_ROOT 에서 PROJECT_ROOT==HARNESS_ROOT 동등 검증. `.agent-harness/` 가 하네스 repo 안에 생성됨.

**Files:**
- Create: `tests/test-self-harness.sh`

- [ ] **Step 1: 신규 테스트 작성**

`tests/test-self-harness.sh`:
```bash
#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"

# T14.1 — cwd=HARNESS_ROOT 면 PROJECT_ROOT == HARNESS_ROOT
unset HARNESS_PROJECT
( cd "$ROOT"
  source "$ROOT/bin/lib.sh" 2>/dev/null
  assert_eq "$HARNESS_ROOT" "$PROJECT_ROOT" "자기작업: 두 변수 동등"
  assert_eq "$ROOT" "$PROJECT_ROOT" "자기작업: 값은 hardness repo"
)

# T14.2 — 자기작업 시 .agent-harness/ 가 HARNESS_ROOT 안 (시뮬: mkdir 후 정리)
# 실제 team-up 안 띄움 — WORKSPACE 변수만 검증
( cd "$ROOT"
  source "$ROOT/bin/lib.sh" 2>/dev/null
  expected="$ROOT/.agent-harness"
  assert_eq "$expected" "$WORKSPACE" "자기작업: WORKSPACE 가 HARNESS_ROOT 안"
)

# T14.3 — .gitignore 에 .agent-harness/ 룰 있어 자기작업이 git 오염 안 함
grep -q '^\.agent-harness/$' "$ROOT/.gitignore"; assert_success "$?" ".gitignore .agent-harness/ 룰"

test_summary
```

- [ ] **Step 2: pass 확인**

```
bash tests/test-self-harness.sh
```
Expected: PASS (3 tests).

- [ ] **Step 3: commit**

```bash
git add tests/test-self-harness.sh
git commit -m "test: T14 self-harness — 자기작업 대칭성 검증

cwd=HARNESS_ROOT 면 PROJECT_ROOT==HARNESS_ROOT 동등. WORKSPACE 도
HARNESS_ROOT 안. .gitignore 의 .agent-harness/ 룰로 자기 repo
오염 차단. 별도 분기 없이 일반 경로와 동일하게 동작.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 15: test-settings-protection.sh (marker 게이트 통합)

**의도**: D2·E8·F8 통합 검증. marker 검사 패턴이 team-up·team-down 양쪽에서 일관 동작.

**Files:**
- Create: `tests/test-settings-protection.sh`

- [ ] **Step 1: 신규 테스트 작성**

`tests/test-settings-protection.sh`:
```bash
#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"

# T15.1 — marker 없는 settings.json 있을 때 team-up 거부
# Q3·Q6: SESSION 명은 mktemp basename 의 '.' 가 sanitize 되어 _ 가 됨 → lib.sh
#         의 _session_autoname 결과를 사용해야 정확. 와일드카드 cleanup 으로 회피.
TMP="$(mktemp -d)"
_session_cleanup() {
  # agents-* 세션 중 이 PROJECT_ROOT 와 매치 가능한 것 모두 정리 (느슨하지만 안전)
  tmux list-sessions -F '#{session_name}' 2>/dev/null \
    | grep '^agents-' | while read -r s; do tmux kill-session -t "$s" 2>/dev/null || true; done
}
trap '_session_cleanup; rm -rf "$TMP"' EXIT
( cd "$TMP" && git init -q )
mkdir -p "$TMP/.claude"
echo '{"existing":"user_setting"}' > "$TMP/.claude/settings.json"
# marker 없음
set +e
out="$(HARNESS_PROJECT="$TMP" AGENT_CMD=cat bash "$ROOT/bin/team-up.sh" default 2>&1)"
rc=$?
set -e
assert_fail "$rc" "team-up 거부 (rc != 0)"
echo "$out" | grep -q "이미 존재"; assert_success "$?" "거부 메시지"
# 사용자 settings.json 보존
content="$(cat "$TMP/.claude/settings.json")"
echo "$content" | grep -q "user_setting"; assert_success "$?" "사용자 settings.json 보존"
rm -f "$TMP/.claude/settings.json"

# T15.2 — marker 있을 때 team-up 정상 (덮어쓰기 허용 — AGENT_CMD=cat 으로 빠른 검증)
echo '{"old":"hadness_made"}' > "$TMP/.claude/settings.json"
touch "$TMP/.claude/.agent-harness-marker"
HARNESS_PROJECT="$TMP" AGENT_CMD=cat bash "$ROOT/bin/team-up.sh" default >/dev/null 2>&1
sleep 0.3
# settings.json 이 우리 hook 으로 덮어써졌는지 검증
grep -q "log-event.sh" "$TMP/.claude/settings.json"; assert_success "$?" "settings.json 덮어쓰기"
[ -f "$TMP/.claude/.agent-harness-marker" ]; assert_success "$?" "marker 유지"
# Q3·Q6: 정확한 SESSION 명 추론 (basename sanitize 적용)
_safe="$(printf '%s' "$(basename "$TMP")" | sed 's/[^A-Za-z0-9_-]/_/g')"
tmux kill-session -t "agents-$_safe" 2>/dev/null || true
rm -f "$TMP/.claude/settings.json" "$TMP/.claude/.agent-harness-marker"

# T15.3 — marker 없는 team-down 호출 → 정리 skip + 안내
echo '{"user":"setting"}' > "$TMP/.claude/settings.json"
# marker 없음
mkdir -p "$TMP/.agent-harness"
echo "user_data" > "$TMP/.agent-harness/important.txt"
set +e
out="$(HARNESS_PROJECT="$TMP" bash "$ROOT/bin/team-down.sh" 2>&1)"
set -e
echo "$out" | grep -q "marker 없음"; assert_success "$?" "marker 없음 경고"
# settings.json·.agent-harness/ 보존
[ -f "$TMP/.claude/settings.json" ]; assert_success "$?" "settings.json 보존"
[ -f "$TMP/.agent-harness/important.txt" ]; assert_success "$?" ".agent-harness/ 보존"
rm -f "$TMP/.claude/settings.json"
rm -rf "$TMP/.agent-harness"

# T15.4 — 살아있는 agents-* 세션 안내 (F8)
tmux new-session -d -s "agents-otherproj" 2>/dev/null
set +e
out="$(HARNESS_PROJECT="$TMP" bash "$ROOT/bin/team-down.sh" 2>&1)"
set -e
echo "$out" | grep -q "agents-otherproj"; assert_success "$?" "다른 세션 안내"
tmux kill-session -t "agents-otherproj" 2>/dev/null || true

test_summary
```

- [ ] **Step 2: pass 확인**

```
bash tests/test-settings-protection.sh 2>&1 | tail -15
```
Expected: PASS (4 케이스).

> NOTE: T15.2 의 team-up 호출이 실패할 수 있음(AGENT_CMD=cat 으로도 워커 pane 분할은 됨, 단 trust 프롬프트 미발생 — 더미 명령이라). 만약 setup 디테일 부족하면 `assert` 다음 줄들 정리.

- [ ] **Step 3: commit**

```bash
git add tests/test-settings-protection.sh
git commit -m "test: T15 settings.json marker 게이트 통합 (D2·E8·F8)

marker 없으면 team-up 거부, team-down 정리 skip+안내. 사용자
settings.json 보호. 살아있는 agents-* 세션 list stderr 안내.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 16: test-multi-project.sh (동시 가동 격리)

**의도**: 두 임시 git repo 가 동시에 PROJECT_ROOT 로 가동되어 SESSION·.agent-harness/·settings.json 모두 격리됨을 검증.

**Files:**
- Create: `tests/test-multi-project.sh`

- [ ] **Step 1: 신규 테스트 작성**

`tests/test-multi-project.sh`:
```bash
#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
source ./assert.sh
ROOT="$(cd .. && pwd)"

TMP1="$(mktemp -d)/projectA"; mkdir -p "$TMP1" && ( cd "$TMP1" && git init -q )
TMP2="$(mktemp -d)/projectB"; mkdir -p "$TMP2" && ( cd "$TMP2" && git init -q )
trap '
  tmux kill-session -t "agents-projectA" 2>/dev/null
  tmux kill-session -t "agents-projectB" 2>/dev/null
  rm -rf "$(dirname "$TMP1")" "$(dirname "$TMP2")"
' EXIT

# A·B 동시 가동
HARNESS_PROJECT="$TMP1" AGENT_CMD=cat bash "$ROOT/bin/team-up.sh" default >/dev/null 2>&1
sleep 0.3
HARNESS_PROJECT="$TMP2" AGENT_CMD=cat bash "$ROOT/bin/team-up.sh" default >/dev/null 2>&1
sleep 0.3

# T16.1 — 두 SESSION 공존
tmux has-session -t agents-projectA 2>/dev/null; assert_success "$?" "agents-projectA 살아있음"
tmux has-session -t agents-projectB 2>/dev/null; assert_success "$?" "agents-projectB 살아있음"

# T16.2 — 두 .agent-harness/ 격리
[ -d "$TMP1/.agent-harness" ]; assert_success "$?" "A 의 .agent-harness/"
[ -d "$TMP2/.agent-harness" ]; assert_success "$?" "B 의 .agent-harness/"

# T16.3 — 두 settings.json 각자 PROJECT_ROOT 박힘
grep -q "$TMP1" "$TMP1/.claude/settings.json"; assert_success "$?" "A settings 에 A 경로"
grep -q "$TMP2" "$TMP2/.claude/settings.json"; assert_success "$?" "B settings 에 B 경로"
! grep -q "$TMP2" "$TMP1/.claude/settings.json" 2>/dev/null; assert_success "$?" "A settings 에 B 경로 없음"

# T16.4 — 같은 task id `1.md` 도 격리
echo "## A task" > "$TMP1/.agent-harness/tasks/1.md"
echo "## B task" > "$TMP2/.agent-harness/tasks/1.md"
grep -q "A task" "$TMP1/.agent-harness/tasks/1.md"; assert_success "$?" "A task 1.md"
grep -q "B task" "$TMP2/.agent-harness/tasks/1.md"; assert_success "$?" "B task 1.md"

# T16.5 — A team-down 이 B 영향 없음
HARNESS_PROJECT="$TMP1" bash "$ROOT/bin/team-down.sh" >/dev/null 2>&1
sleep 0.3
! tmux has-session -t agents-projectA 2>/dev/null; assert_success "$?" "A 세션 종료됨"
tmux has-session -t agents-projectB 2>/dev/null; assert_success "$?" "B 세션 여전히 살아있음"
[ -d "$TMP2/.agent-harness" ]; assert_success "$?" "B .agent-harness/ 여전히"

# T16.6 — B 도 정리
HARNESS_PROJECT="$TMP2" bash "$ROOT/bin/team-down.sh" >/dev/null 2>&1
sleep 0.3
! tmux has-session -t agents-projectB 2>/dev/null; assert_success "$?" "B 세션 종료됨"

test_summary
```

- [ ] **Step 2: pass 확인**

```
bash tests/test-multi-project.sh 2>&1 | tail -15
```
Expected: PASS.

- [ ] **Step 3: commit**

```bash
git add tests/test-multi-project.sh
git commit -m "test: T16 동시 가동 격리 (D7·E1·E8)

두 임시 git repo 가 동시에 PROJECT_ROOT 로 가동. SESSION 자동명·
.agent-harness/·settings.json 모두 격리. 같은 task id 충돌 X. A
team-down 이 B 무영향. marker 게이트가 양쪽 깨끗한 정리.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 17: probe-multi-project.sh (수동 실측)

**의도**: 실제 claude 두 인스턴스 동시 가동 시 hook env 격리·channel 격리·`/loop` 무장이 모두 정상인지 실측. 기존 probe-loop·probe-hook 의 멀티 버전.

**Files:**
- Create: `tests/probes/probe-multi-project.sh`

- [ ] **Step 1: 신규 probe 작성**

`tests/probes/probe-multi-project.sh`:
```bash
#!/usr/bin/env bash
# 멀티 프로젝트 동시 가동 실측. run-all 비포함, 수동 실행.
# 두 임시 git repo 에서 동시에 team-up → hook 각자 events.log 에만 기록되는지.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP1="/tmp/probe_mp_$$/projectA"; mkdir -p "$TMP1" && ( cd "$TMP1" && git init -q )
TMP2="/tmp/probe_mp_$$/projectB"; mkdir -p "$TMP2" && ( cd "$TMP2" && git init -q )
cleanup() {
  tmux kill-session -t "agents-projectA" 2>/dev/null
  tmux kill-session -t "agents-projectB" 2>/dev/null
  rm -rf "/tmp/probe_mp_$$"
}
trap cleanup EXIT

echo "[probe-multi-project] A·B 동시 team-up..."
HARNESS_PROJECT="$TMP1" bash "$ROOT/bin/team-up.sh" default >/dev/null 2>&1
HARNESS_PROJECT="$TMP2" bash "$ROOT/bin/team-up.sh" default >/dev/null 2>&1
sleep 30  # claude REPL 준비

echo "[probe-multi-project] A 의 dev 페인에 Write 지시..."
TGT_A="$(tmux list-panes -t agents-projectA:0 -F '#{pane_index}\t#{pane_title}' | awk -F'\t' '$2=="dev"{print "agents-projectA:0."$1}')"
tmux send-keys -t "$TGT_A" -l "make a file named hello-a.txt with content hi using the Write tool"
sleep 1; tmux send-keys -t "$TGT_A" Enter
echo "[probe-multi-project] B 의 dev 페인에 Write 지시..."
TGT_B="$(tmux list-panes -t agents-projectB:0 -F '#{pane_index}\t#{pane_title}' | awk -F'\t' '$2=="dev"{print "agents-projectB:0."$1}')"
tmux send-keys -t "$TGT_B" -l "make a file named hello-b.txt with content hi using the Write tool"
sleep 1; tmux send-keys -t "$TGT_B" Enter

echo "[probe-multi-project] hook 발화 60s 대기..."
sleep 60

# 격리 검증: A 의 events.log 에 A 만, B 의 events.log 에 B 만
fail=0
if ! grep -q "hello-a.txt" "$TMP1/.agent-harness/events.log" 2>/dev/null; then
  echo "[probe-multi-project] FAIL — A events.log 에 hello-a.txt 없음"; fail=1
fi
if ! grep -q "hello-b.txt" "$TMP2/.agent-harness/events.log" 2>/dev/null; then
  echo "[probe-multi-project] FAIL — B events.log 에 hello-b.txt 없음"; fail=1
fi
if grep -q "hello-b.txt" "$TMP1/.agent-harness/events.log" 2>/dev/null; then
  echo "[probe-multi-project] FAIL — A events.log 에 B 의 파일 누출"; fail=1
fi
if grep -q "hello-a.txt" "$TMP2/.agent-harness/events.log" 2>/dev/null; then
  echo "[probe-multi-project] FAIL — B events.log 에 A 의 파일 누출"; fail=1
fi

if [ "$fail" = "0" ]; then
  echo "[probe-multi-project] PASS (hook env 격리 + 동시 가동 정상)"
  exit 0
else
  echo "[probe-multi-project] FAIL — pane 덤프(A·B):"
  tmux capture-pane -t "$TGT_A" -p | tail -20
  echo "---"
  tmux capture-pane -t "$TGT_B" -p | tail -20
  exit 1
fi
```

- [ ] **Step 2: 실행 가능 권한 부여**

```
chmod +x tests/probes/probe-multi-project.sh
```

- [ ] **Step 3: 수동 실행 안내 — 자동 run-all 비포함**

수동 실행 확인:
```
bash tests/probes/probe-multi-project.sh
```
Expected: 실제 claude 2 인스턴스 기동 → 약 2분 → PASS. (이 task 는 실행을 plan 단계에선 의무화 안 함, probe 스크립트 작성·커밋까지)

- [ ] **Step 4: commit**

```bash
git add tests/probes/probe-multi-project.sh
git commit -m "test: T17 probe-multi-project — 실제 claude 동시 가동 격리 실측

probe-loop·probe-hook 의 멀티 버전. 두 임시 git repo 에서 동시
team-up, 각자 dev 페인에 Write 지시 → hook env 격리로 events.log
가 자기 PROJECT_ROOT 만 기록하는지 실측. run-all 비포함, 수동.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 18: README 갱신 + 최종 회귀

**의도**: 사용자 가이드 갱신 — 호출 cwd·.agent-harness·동시 가동·`--project` 사용법. 전체 회귀 PASS 확인.

**Files:**
- Modify: `README.md`

- [ ] **Step 1: README "사용법" 섹션 갱신**

`README.md` 의 "사용법" 섹션을 다음으로 교체 (기존 5 단계 구조 유지·갱신):

````markdown
## 사용법

작업하려는 프로젝트의 디렉터리에서 호출한다(자동감지). 또는 어디서든 `--project /path` 로 명시.

```bash
# 1) 프로젝트로 이동 후 팀 가동 (작업 대상 = 현재 cwd 의 git toplevel)
cd ~/work/projectA
~/Desktop/Repo/Practice/tmux-agent-team/bin/team-up.sh feature-team
# 또는 어디서든:
#   ~/.../bin/team-up.sh --project ~/work/projectA feature-team

tmux attach -t agents-projectA   # 세션명은 basename 기반 자동

# 2) 작업 지시 작성
echo "# T1: 로그인 버그 수정" > ~/work/projectA/.agent-harness/tasks/T1.md

# 3) 워커에 배정 (메인 pane 이 dispatch 호출하는 게 일반적)
~/.../bin/dispatch.sh dev T1
# 외부 셸에서:  ~/.../bin/dispatch.sh --project ~/work/projectA dev T1

# 4) 완료 대기
~/.../bin/wait-worker.sh dev T1 300

# 5) 결과 확인
cat ~/work/projectA/.agent-harness/results/T1.md

# 6) 팀 정리 (tasks/results 는 보존, 런타임만 정리)
~/.../bin/team-down.sh   # cwd=projectA 기준
# 또는:  ~/.../bin/team-down.sh --project ~/work/projectA
```

## 멀티 프로젝트 동시 가동

서로 다른 프로젝트라면 동시에 가동 가능. SESSION 은 `agents-<basename>` 자동.

```bash
# 셸 1
cd ~/work/projectA && ~/.../bin/team-up.sh default
# 셸 2
cd ~/work/projectB && ~/.../bin/team-up.sh default
# → tmux 에 agents-projectA·agents-projectB 두 세션 공존
```

basename 충돌 시(둘 다 `auth/`) 후행 가동만 거부. 회피:
```bash
SESSION_OVERRIDE="agents-auth2" ~/.../bin/team-up.sh default
```

## 디렉터리

- **HARNESS_ROOT** (이 repo) — `bin/`·`profiles/`·`prompts/`·`templates/`. 정의 자산. 모든 프로젝트 공유.
- **PROJECT_ROOT** (각자 프로젝트) — `.agent-harness/{tasks,results,review,events.log,.harness-state,...}`, `.claude/settings.json`, `.claude/.agent-harness-marker`. 일시 산출물.

`.agent-harness/` 와 `.claude/.agent-harness-marker` 는 프로젝트 `.gitignore` 에 추가 권장(가동 시 안내).
````

(원래 README 의 "디렉토리" 섹션이 있으면 위 내용으로 통합·교체)

- [ ] **Step 2: README 의 "에이전트 하네스 (2차)" 섹션 갱신**

기존 섹션 끝에 다음 한 줄 추가:
```
- 3차(PROJECT_ROOT 분리): 임의 프로젝트 작업·동시 가동 지원. 설계: `docs/superpowers/specs/2026-05-20-project-root-separation-design.md`
```

- [ ] **Step 3: 전체 회귀**

```bash
bash tests/run-all.sh 2>&1 | tail -3
```
Expected: 25 (기존) + 8 (신규: project-root·session-autoname·self-harness·settings-protection·multi-project·project-flag·path-validation·channel-name) = 33 스위트, **모두 PASS**.

- [ ] **Step 4: commit**

```bash
git add README.md
git commit -m "docs: T18 README 3차 사용법 — 호출 cwd·--project·동시 가동 (F10)

PROJECT_ROOT 분리 후 사용법 전면 갱신. cwd 자동감지·--project escape
hatch·.agent-harness/ 위치·SESSION 자동명·멀티 프로젝트 시나리오·
basename 충돌 회피. 기존 사용 패턴은 'cd PROJECT_ROOT 후 호출' 로 자연
호환. 모든 25 기존 + 8 신규 스위트 PASS.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## 셀프리뷰 (작성 완료 후)

### 1. spec coverage

| spec 요구사항 | 담당 task |
|---|---|
| HARNESS_ROOT/PROJECT_ROOT 분리 (§4.1) | T1 |
| PROJECT_ROOT_IS_GIT (E5) | T1 |
| path validation + PROJECT_ROOT_VALID (E4·F1·F4) | T2 |
| _session_autoname + sed sanitize (D3) | T3 |
| _normalize_project (E12·F2) | T4 |
| templates/settings.json.tpl 이동·토큰 분리 (§5.6) | T5 |
| team-up: --project·marker·mkdir·cwd=PROJECT_ROOT (§5.2·D2·E5) | T6 |
| log-event 메타 화이트리스트 (D6·F6) | T7 |
| dispatch --project (§5.3) | T8 |
| wait-worker --project·CHANNEL SESSION prefix (§5.3·E1·E11) | T9 |
| team-down marker 게이트·살아있는 세션 안내 (E8·F8) | T10 |
| REPO_ROOT 호환 별칭 제거 (cleanup) | T11 |
| prompts workspace→.agent-harness·{{SESSION}}·orchestrator 추가 2건 (§5.7·E11·F7·D4) | T12 |
| profiles SESSION 삭제·workspace/ 폐기·.gitignore (§5.8·§5.9·§5.10) | T13 |
| self-harness (§4.2) | T14 |
| settings-protection 통합 (D2·E8·F8) | T15 |
| multi-project 격리 (§4.3·D7·E1·E8) | T16 |
| probe-multi-project (§8.3) | T17 |
| README (F10) | T18 |

모든 spec 결정·결함(D1~D9·E1~E12·F1~F10) 커버. **G2 (basename=`/` edge case) 는 의도적으로 단순화 — spec 도 fail safe 만 명시, 별도 task 불필요**.

### 2. placeholder 검사

- "TBD"·"TODO"·"appropriate handling" 등 — 없음.
- 모든 step 에 실제 코드·실제 명령·예상 출력 포함.
- "Similar to Task N" 같은 참조 — 없음. `_normalize_project_arg` 같은 inline 함수도 각 task 에서 명시 복제.

### 3. type/이름 일관성

- `PROJECT_ROOT`·`HARNESS_ROOT`·`WORKSPACE`·`SESSION`·`HARNESS_PROJECT`·`PROJECT_ROOT_VALID`·`PROJECT_ROOT_IS_GIT` — task 간 일관.
- `resolve_project_root`·`_session_autoname`·`resolve_session`·`_normalize_project`·`_normalize_project_arg` — T4 의 lib.sh 안 `_normalize_project` 와 T6~T10 bin/ 스크립트 진입부의 `_normalize_project_arg` 는 **의도적 분리** (lib.sh source 이전/이후 구분). 두 함수 본문 동일 — 단순 복제, 이름만 다름. spec 가 plain inline 패턴을 권하므로 OK.
- `marker` 파일명 `.agent-harness-marker` — T6·T10·T13·T15 모두 일치.
- 채널명 `done-$SESSION-$WORKER-$TASK_ID` — T9·T12·T16 모두 일치.

이상 18 task 가 spec 의 모든 결정·결함을 커버, 의존성 순서대로 진행 가능.

---

## 실행 가이드

이 plan 은 **subagent-driven-development** 로 실행 권장 — 각 task 가 독립적이며 (1) failing test → (2) fail 확인 → (3) 구현 → (4) pass → (5) commit 의 TDD bite-sized 패턴. 두 단계 리뷰(spec compliance·code quality) 가능.

또는 **executing-plans** 인라인 실행도 가능.

각 task 완료 후 `bash tests/run-all.sh` 로 회귀 확인. T11 끝까지는 일부 fail 허용(점진적 마이그레이션), T13 이후는 모두 PASS 여야 함.
