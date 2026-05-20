# PROJECT_ROOT 분리 — 설계 문서

작성일: 2026-05-20
상태: 설계 확정 (구현 전)
선행:
- [2026-05-18-tmux-agent-team-design.md](2026-05-18-tmux-agent-team-design.md) (1차 토대)
- [2026-05-19-agent-harness-design.md](2026-05-19-agent-harness-design.md) (2차 하네스, main 머지 완료)

## 1. 목적

현재 `bin/lib.sh` 의 `REPO_ROOT` 단일 변수가 **두 가지 의미를 동시에 짊어진다**:

- (a) **하네스 자체 위치** — `bin/`, `profiles/`, `prompts/`, `templates/settings.json.tpl` 의 원본 자리 (`tmux-agent-team` 의 절대경로)
- (b) **작업 대상 프로젝트 위치** — 워커 cwd, `workspace/` 산출물 저장처, hook 의 EVENTS_LOG 기준, settings.json 출력처

이 결합 때문에 **어떤 디렉터리에서 team-up 을 호출해도 작업 대상은 항상 `tmux-agent-team` 자기 자신**으로 고정된다. 외부 프로젝트(예: `~/work/projectA`) 를 하네스로 작업할 수 없다.

이 설계는 (a)·(b) 를 별도 변수로 분리해 다음을 가능하게 한다:

1. 임의의 git 프로젝트 디렉터리에서 하네스 호출 → 그 프로젝트가 작업 대상
2. 여러 프로젝트 동시 가동 (SESSION 자동 분리)
3. 하네스 자기작업도 같은 메커니즘으로 자연스럽게 지원 (`tmux-agent-team` 자체가 git repo → PROJECT_ROOT=HARNESS_ROOT 동등)
4. 기존 "정의는 git, 결과는 일시" 철학 유지·강화 — 정의는 HARNESS_ROOT(공유), 결과는 PROJECT_ROOT/.agent-harness/ (프로젝트별)

## 2. 전제 / 환경

- 위치: `~/Desktop/Repo/Practice/tmux-agent-team/` — 독립 git repo, main 브랜치 (1·2차 모두 머지 완료)
- 2차 하네스 자산 전부 재사용: `bin/`, `prompts/`, `profiles/`, `tests/`, `workspace/.claude/settings.json.tpl`
- tmux 3.6+, git 2.x (rev-parse --show-toplevel), bash 3.2+ (macOS)
- 호환성: **깨끗한 전환** — 기존 `workspace/` 보존·마이그레이션 없음. 산출물은 아직 의미 있는 것이 거의 없으므로 손실 무시 가능. prompts·코드 일괄 경로 교체.

## 3. 결정 사항 (명확화 답변 요약)

- **멀티 프로젝트 동시 가동**: 허용 (동시성 설계 도입)
- **PROJECT_ROOT 결정**: 호출 cwd 자동감지 (`git rev-parse --show-toplevel`, git 아니면 경고 후 PWD)
- **하네스 자기작업**: 허용 (PROJECT_ROOT == HARNESS_ROOT 동등 처리, 별도 분기 없음)
- **SESSION 명명**: `agents-<sanitize(basename PROJECT_ROOT)>` 자동, 충돌 시 거부
- **settings.json 위치**: `$PROJECT_ROOT/.claude/settings.json` (프로젝트별 분리)
- **작업 디렉터리 이름**: `.agent-harness/` (hidden, 명확)
- **호환성**: 깨끗한 전환
- **하네스 정의 참조 방식**: boot 명령에 절대경로 대입 (env·PATH 폴루션 없음)
- **escape hatch**: 모든 bin/ 스크립트가 `--project /path` 옵션 지원. cwd 자동감지가 기본, `--project` 가 강제 override (D1)
- **tasks/results 정리 정책**: team-down 은 **보존** (사용자·메인 산출물). 단 가동 시점에 메인이 `.agent-harness/tasks/` 의 stale 파일을 `.harness-state` 와 대조해 활성/완료 판별. 메인 프롬프트에 명시 (D4)
- **settings.json 표식 메커니즘**: JSON 키 대신 **별도 marker 파일** `$PROJECT_ROOT/.claude/.agent-harness-marker` (Claude Code 스키마 의존성 회피, D2)
- **wait-for 채널명**: `done-<SESSION>-<worker>-<task>` (E1). tmux wait-for 채널은 서버 전역이라 멀티 동시 가동 시 worker·task 가 겹치면 신호 충돌. SESSION (이미 프로젝트별 자동명) prefix 로 격리.
- **PROJECT_ROOT 경로 정합성 검증**: sed 구분자 충돌·셸 메타문자 회피·셸 quoting 실수 위험 회피 위해 PROJECT_ROOT 절대경로의 각 문자가 `[A-Za-z0-9/._-]` 안에 있어야 함 (**공백 금지**, F4 보수적 결정). 벗어나면 거부 (E4). `--project` 인자는 `cd && pwd` 로 절대경로 정규화 후 검증 (E12).
- **lib.sh source 안전성**: lib.sh 는 source 되는 파일이므로 검증 실패 시 `exit` 금지. `PROJECT_ROOT_VALID=0/1` 변수로 셋, 호출 스크립트가 source 후 명시 검사 (F1).

## 4. 아키텍처

### 4.1 변수 분리

| 변수 | 의미 | 결정 시점 | 결정 방법 |
|---|---|---|---|
| `HARNESS_ROOT` | 하네스 자체(정의) | `lib.sh` source 시 | `bin/lib.sh` 파일 위치 기준 부모 |
| `PROJECT_ROOT` | 작업 대상 프로젝트(결과) | `lib.sh` source 시 | `resolve_project_root()` (git toplevel→PWD 폴백) |
| `WORKSPACE` | 작업 산출물 디렉터리 | `lib.sh` source 시 | `$PROJECT_ROOT/.agent-harness` |
| `SESSION` | tmux 세션명 | `resolve_session()` 호출 시 | `SESSION_OVERRIDE>PROFILE_SESSION>SESSION env>agents-<sanitize(basename PROJECT_ROOT)>` |

핵심 불변식:
- `HARNESS_ROOT` 는 늘 절대경로·불변(이 repo 의 위치)
- `PROJECT_ROOT` 는 호출 cwd 마다 다름(스크립트 source 시점 1회 확정, sub-shell 호출 가격 1회)
- `WORKSPACE` 는 항상 PROJECT_ROOT 안. 절대 HARNESS_ROOT 와 섞이지 않음

### 4.2 자기작업 대칭성

`cwd=tmux-agent-team` 에서 team-up 시:
- PROJECT_ROOT = `git rev-parse --show-toplevel` = `~/Desktop/Repo/Practice/tmux-agent-team`
- HARNESS_ROOT = `bin/lib.sh` 부모 = 같은 값
- 즉 `PROJECT_ROOT == HARNESS_ROOT` 가 자연스럽게 성립

이 때 동작은 분기 없이 일반 경로와 동일:
- `.agent-harness/` 가 하네스 repo 안에 생성 (gitignore 추가 필요 — 별도 안전장치)
- `.claude/settings.json` 도 하네스 측에 생성 (이미 `.gitignore` 룰 있음)
- 워커 cwd 가 하네스 repo → 하네스 자체의 코드를 수정 가능
- **수정 효과 적용 시점** (E6): `bin/lib.sh` 등 정의 파일 수정은 이미 source 된 현 인스턴스에 즉시 반영 안 됨. boot 합본도 가동 시점 스냅샷이라 이미 기동된 워커는 영향 없음. **다음 team-up 가동부터 적용**.

### 4.3 멀티 프로젝트 격리

projectA 가동 중 projectB 가동 시나리오:

| 자원 | projectA | projectB | 격리 방식 |
|---|---|---|---|
| tmux 세션 | `agents-projectA` | `agents-projectB` | basename 자동명 |
| 작업 디렉터리 | `~/work/projectA/.agent-harness/` | `~/work/projectB/.agent-harness/` | PROJECT_ROOT 다름 |
| settings.json | `~/work/projectA/.claude/settings.json` | `~/work/projectB/.claude/settings.json` | PROJECT_ROOT 다름 |
| hook 스크립트 | `$HARNESS_ROOT/bin/log-event.sh` | 같음 (read-only, env 로 분리) | settings.json 의 EVENTS_LOG·REPO_ROOT env 가 프로젝트별 |
| events.log append | PROJECT_ROOT 의 .agent-harness | 같음 | PIPE_BUF 이하 라인 원자성·다른 파일이라 무관 |
| wait-for 채널 | `done-agents-projectA-dev-T1` | `done-agents-projectB-dev-T1` | SESSION prefix 로 격리 (E1) |

basename 충돌(둘 다 `auth/`) 은 SESSION 충돌 → 중복가동 차단으로 자연 차단. 메시지에 PROJECT_ROOT 절대경로를 함께 노출해 사용자 식별 가능.

## 5. 컴포넌트별 변경

### 5.1 `bin/lib.sh` (핵심)

```bash
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_ROOT="$(cd "$_LIB_DIR/.." && pwd)"

# PROJECT_ROOT: HARNESS_PROJECT(--project) > cwd 의 git toplevel > PWD.
# HARNESS_PROJECT 는 각 bin 스크립트의 --project 옵션 파서가 export 한다.
# PROJECT_ROOT_IS_GIT 도 함께 셋: .gitignore 안내 조건 등에 사용 (E5).
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
# PROJECT_ROOT 가 git repo 인지 별도 확인 (HARNESS_PROJECT 우선 경로에서도 정확)
if git -C "$PROJECT_ROOT" rev-parse --show-toplevel >/dev/null 2>&1; then
  PROJECT_ROOT_IS_GIT=1
else
  PROJECT_ROOT_IS_GIT=0
fi

# 경로 정합성 검증 (E4): sed 구분자·셸 메타문자 충돌 방지.
# 허용: 영숫자, /, ., _, -. 공백 미허용(셸 quoting 실수 위험 — F4 보수적 결정).
# lib.sh 는 source 되는 파일이라 exit 1 금지(소스 셸 종료) — return 1 도 함수 밖에서
# 불가. 따라서 검증 결과를 변수로 셋, 호출 스크립트가 검사 (F1):
#   source bin/lib.sh
#   [ "$PROJECT_ROOT_VALID" = "1" ] || exit 1
PROJECT_ROOT_VALID=1
case "$PROJECT_ROOT" in
  *[!A-Za-z0-9/._-]*)
    echo "오류: PROJECT_ROOT='$PROJECT_ROOT' 에 허용되지 않는 문자 포함." >&2
    echo "  허용: [A-Za-z0-9/._-] (공백 미허용). 디렉터리 이름 정리 후 재시도." >&2
    PROJECT_ROOT_VALID=0 ;;
esac
WORKSPACE="$PROJECT_ROOT/.agent-harness"

# basename sanitize: tmux 세션명 규칙([A-Za-z0-9_-]).
# bash 3.2 ${var//pattern} 의 glob/정규식 모호성 회피 위해 sed 사용 (D3).
_session_autoname() {
  local b safe
  b="$(basename "$PROJECT_ROOT")"
  safe="$(printf '%s' "$b" | sed 's/[^A-Za-z0-9_-]/_/g')"
  printf 'agents-%s' "$safe"
}

resolve_session() {
  printf '%s' "${SESSION_OVERRIDE:-${PROFILE_SESSION:-${SESSION:-$(_session_autoname)}}}"
}

# 그 외 함수(target_in·scope_match·cursor_*·state_*·event_*·done_logged·review_verdict·write_harness_task·send_prompt) 는 무변경. WORKSPACE 변수 의미만 바뀌어 자동 흡수.
```

`REPO_ROOT` 변수는 사라진다. 기존 사용처는 의미별로 `HARNESS_ROOT` 또는 `PROJECT_ROOT` 로 치환.

**`--project` 옵션 파서** (각 bin 스크립트 진입부, lib.sh source **이전**):

```bash
# bin/team-up.sh·dispatch.sh·wait-worker.sh·team-down.sh 공통 진입부.
# 옵션은 첫 위치 인자 앞에서만 인식 (E7). 위치 인자 뒤에 오면 무시·혼란 → 거부보다는 단순 break.
# _normalize_project 는 stdout 으로 정규화 경로 출력, 실패 시 return 1.
# subshell 안 exit 1 silent failure 회피 위해 return 사용·호출자 명시 검사 (F2).
_normalize_project() {  # $1=raw → stdout=절대경로, $?=0 성공 (E12·F2)
  local raw="$1"
  if [ ! -d "$raw" ]; then
    echo "오류: --project 경로 없음: $raw" >&2
    return 1
  fi
  ( cd "$raw" && pwd )
}
while [ $# -gt 0 ]; do
  case "$1" in
    --project)
      if ! HARNESS_PROJECT="$(_normalize_project "$2")"; then exit 1; fi
      export HARNESS_PROJECT; shift 2 ;;
    --project=*)
      if ! HARNESS_PROJECT="$(_normalize_project "${1#--project=}")"; then exit 1; fi
      export HARNESS_PROJECT; shift ;;
    *) break ;;
  esac
done
# 그 후 lib.sh source — resolve_project_root() 가 HARNESS_PROJECT 우선 사용
source "$_DIR/lib.sh"
[ "$PROJECT_ROOT_VALID" = "1" ] || exit 1   # F1: source 후 검증 결과 확인
```

cwd 자동감지가 기본, `--project` 가 명시 override. 외부 자동화 스크립트나 사용자가 cwd 와 무관하게 특정 프로젝트를 가동·제어할 때 사용. **옵션은 첫 위치 인자(profile/worker 등) 앞에서만**. 뒤에 오면 인식 안 됨 (E7).

### 5.2 `bin/team-up.sh`

- `--project` 파서를 lib.sh source **이전**에 실행
- 초기 mkdir 대상: `$WORKSPACE/{.boot,tasks,results,review}` — 경로 의미 변경(이제 PROJECT_ROOT 안)
- settings.json·marker 생성 (표식은 별도 파일로, D2):
  ```bash
  if [ -f "$HARNESS_ROOT/templates/settings.json.tpl" ]; then
    MARKER="$PROJECT_ROOT/.claude/.agent-harness-marker"
    # 기존 settings.json 보호: marker 없으면 거부 (사용자 작성물 보호)
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
    # marker — team-up/team-down 모두 [ -f marker ] 로 식별
    printf 'generated by agent-harness — do not edit settings.json (regenerated by bin/team-up.sh)\n' > "$MARKER"
  fi
  ```
- `.gitignore` 안내(자동수정 금지): **PROJECT_ROOT_IS_GIT==1 일 때만** (`$PROJECT_ROOT/.gitignore` 에 `.agent-harness/` 룰 누락 시 stderr 1회). git repo 아니면 안내 자체 skip (E5). `.claude/` 관련은 사용자 의도(자기 settings) 가능성 있어 안내하지 않음 (D5)
- 워커·메인·리뷰어 기동: `cd "$PROJECT_ROOT" && $(agent_cmd_for ...)` (REPO_ROOT → PROJECT_ROOT)
- boot 합본 cat 소스: `$HARNESS_ROOT/prompts/...` (REPO_ROOT → HARNESS_ROOT)
- boot 파일 출력처: `$WORKSPACE/.boot/<name>.md` (PROJECT_ROOT 안)
- 카탈로그 desc 소스: `$HARNESS_ROOT/prompts/roles/...`

### 5.3 `bin/dispatch.sh` / `bin/wait-worker.sh`

본문 변경 거의 없음 — `--project` 파서를 lib.sh source 이전에 실행, lib.sh source 후 `WORKSPACE`·`SESSION` 자동 확정.
- `TASK_FILE="$WORKSPACE/tasks/$TASK_ID.md"` 그대로
- 호출 cwd 가 PROJECT_ROOT 와 무관하면 엉뚱한 .agent-harness 를 봄 → **task 파일 존재 검사가 1차 안전망** (찾지 못하면 즉시 에러). 메인 pane 의 cwd 가 PROJECT_ROOT 이므로 메인이 호출하면 항상 옳음 — 메인 프롬프트에 명시.
- 외부 자동화·다른 셸에서 호출할 땐 `--project /path` 로 강제 (escape hatch).

### 5.4 `bin/team-down.sh`

- `--project` 파서를 lib.sh source 이전에 실행
- `SESSION="$(resolve_session)"` 그대로 (자동명 폴백 사용)
- **marker 검사를 모든 정리 분기의 게이트로 사용** (E8): marker 파일이 없으면 settings.json·`.agent-harness/` 런타임 정리 둘 다 skip 후 경고. 사용자가 우연히 만든 `.agent-harness/` 디렉터리 보호.
- **살아있는 agents-* 세션 안내** (F8): marker 없을 때 시스템의 다른 `agents-*` 세션을 list. 사용자가 의도한 종료 가능성 안내.
  ```bash
  MARKER="$PROJECT_ROOT/.claude/.agent-harness-marker"
  if [ ! -f "$MARKER" ]; then
    echo "경고: marker 없음 ($MARKER) — '$PROJECT_ROOT' 는 하네스로 가동된 적 없는 것으로 판단." >&2
    echo "  세션($SESSION) 종료만 수행, .agent-harness/·settings.json 은 건드리지 않음." >&2
    # F8: 시스템에 살아있는 agents-* 세션 있으면 안내
    _alive="$(tmux list-sessions -F '#{session_name}' 2>/dev/null | grep '^agents-' || true)"
    if [ -n "$_alive" ]; then
      echo "  참고: 살아있는 agents-* 세션:" >&2
      echo "$_alive" | sed 's/^/    /' >&2
      echo "  특정 프로젝트 종료: '--project /path' 명시" >&2
    fi
    # tmux 세션만 종료 (있으면) 후 종료
    tmux kill-session -t "$SESSION" 2>/dev/null || true
    exit 0
  fi
  # marker 있으면 정상 정리
  ```
- `$WORKSPACE/{.boot,events.log,.harness-state,.review-cursor.*,.harness-task.*,review/}` 정리
- `$PROJECT_ROOT/.claude/settings.json` + marker 정리 (marker 자체도 마지막에)
- **tasks/results 보존** — 사용자·메인의 의미 있는 산출물. 다음 가동 시 메인이 stale 판별 (D4)

### 5.5 `bin/log-event.sh` (PostToolUse hook)

- settings.json.tpl 의 주입 env 변경:
  ```json
  "command": "EVENTS_LOG=\"__PROJECT_ROOT__/.agent-harness/events.log\" REPO_ROOT=\"__PROJECT_ROOT__\" bash \"__HARNESS_ROOT__/bin/log-event.sh\""
  ```
  (의미 명확화: hook 안에서 `REPO_ROOT` 변수는 작업 대상 = PROJECT_ROOT)
- 본문 변경:
  - `_htf="${REPO_ROOT}/.agent-harness/.harness-task.${worker}"` (경로 이름 변경)
  - **메타 산출물 화이트리스트 skip** — tasks/results 는 작업 흐름의 일부라 기록 대상. 메타(events.log 자체·커서·상태·boot·review/) 만 skip (D6). skip 검사는 **repo-relative 변환 전, 절대경로 기준으로** (F6: 절대경로 Write 도 잡힘):
    ```bash
    case "$fpath" in
      "$REPO_ROOT/.agent-harness/events.log") exit 0 ;;
      "$REPO_ROOT/.agent-harness/.review-cursor."*) exit 0 ;;
      "$REPO_ROOT/.agent-harness/.harness-task."*) exit 0 ;;
      "$REPO_ROOT/.agent-harness/.harness-state") exit 0 ;;
      "$REPO_ROOT/.agent-harness/.boot/"*) exit 0 ;;
      "$REPO_ROOT/.agent-harness/review/"*) exit 0 ;;
    esac
    # 그 후 repo-relative 변환
    case "$fpath" in
      "$REPO_ROOT"/*) rel="${fpath#"$REPO_ROOT"/}" ;;
      *) rel="$fpath" ;;
    esac
    ```
    `.agent-harness/tasks/*`·`.agent-harness/results/*` 는 기록 대상.
- 기본값(직접 실행 시): `EVENTS_LOG="${EVENTS_LOG:-$REPO_ROOT/.agent-harness/events.log}"` (workspace → .agent-harness)

### 5.6 `templates/settings.json.tpl` (위치 이동)

`workspace/.claude/settings.json.tpl` → `templates/settings.json.tpl`. 의미: 하네스 정의 자산임을 디렉터리로 표명.

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

표식은 별도 파일 `$PROJECT_ROOT/.claude/.agent-harness-marker` (D2). JSON 스키마 의존성 회피. team-up·team-down 이 `[ -f marker ]` 로 검사.

### 5.7 `prompts/_common.md`·`prompts/roles/*`·`prompts/loop/*`

`workspace/` → `.agent-harness/` 일괄 치환. 워커 cwd 가 PROJECT_ROOT 이므로 상대경로 의미 자동 보존.

영향 라인:
- `_common.md`:
  - tasks/results/events.log 경로 일괄 교체
  - **wait-for 채널명 갱신** (E11): `tmux wait-for -S done-{{WORKER_NAME}}-<id>` → `tmux wait-for -S done-{{SESSION}}-{{WORKER_NAME}}-<id>`. team-up 의 boot 합본 sed 치환에 `{{SESSION}}` 토큰 추가 처리.
  - **추가 1줄** (F7): "위 채널명의 `done-...-...-<id>` 부분은 이미 가동 시 치환되어 박혀있다. 너의 task id 만 채우고 다른 부분은 변형하지 마라."
- `roles/orchestrator.md`: tasks/review/.harness-state 경로 + **추가 사항 2건**:
  - "dispatch.sh·wait-worker.sh 는 cwd=PROJECT_ROOT(=현재 pane cwd) 에서 호출하라. 다른 위치에서 호출하면 잘못된 .agent-harness 를 본다"
  - "team-up 가동 직후 `.agent-harness/tasks/` 의 기존 파일들을 `.harness-state` 와 대조해 활성/완료 판별하라. stale 한(완료된) task 를 새로 배정하지 마라. 모호하면 사용자에게 확인" (D4 stale 코멘트)
- `roles/reviewer-*.md`: review/ 경로
- `loop/orchestrator.md`·`loop/reviewer.md`: review/·.review-cursor·events.log 경로

`bin/wait-worker.sh`·`bin/dispatch.sh` 의 `CHANNEL` 변수도 `done-$SESSION-$WORKER-$TASK_ID` 로 갱신 (E1).

### 5.8 `profiles/*.sh`

`SESSION="agents"` 라인 삭제(4개 파일 모두). 자동명을 항상 사용. WORKERS·REVIEWERS·LAYOUT·ORCHESTRATOR_MODEL 무변경.

### 5.9 `.gitignore` (HARNESS_ROOT 측)

기존 룰 정리:
- 제거: `workspace/tasks/`, `workspace/results/`, `workspace/.boot/` (workspace 폐기)
- 추가: `.agent-harness/` (자기작업 시 자기 repo 에 떨어지는 것 무시), `.claude/.agent-harness-marker` (자기작업 시 marker 도 무시)
- 유지: `.claude/settings.json`, `docs/`, OS·캐시 룰

### 5.10 사라지는 디렉터리·파일

- `workspace/` (HARNESS_ROOT 측) — 전체 삭제. 1차 토대 산출물 위치였으나 이제 PROJECT_ROOT 안으로 이주
- `workspace/.claude/settings.json.tpl` → `templates/settings.json.tpl` 로 이동
- `workspace/.gitkeep`, `workspace/results/`, `workspace/tasks/` — 삭제 (PROJECT_ROOT 의 .agent-harness/ 가 대체)

## 6. 데이터 흐름 (가동→완료)

### 6.1 가동

```
cd ~/work/projectA
~/Desktop/Repo/Practice/tmux-agent-team/bin/team-up.sh feature-team
# 또는 cwd 무관: ~/.../bin/team-up.sh --project ~/work/projectA feature-team
```

1. `--project` 파서 → `HARNESS_PROJECT` 셋 (있을 때만)
2. `lib.sh` source → HARNESS_ROOT, PROJECT_ROOT(HARNESS_PROJECT>cwd git>PWD), WORKSPACE, SESSION 확정 (D9: PROJECT_ROOT 결정은 source 시점의 `$PWD` 또는 `$HARNESS_PROJECT` 기준)
3. SESSION 충돌 검사 (`tmux has-session -t agents-projectA`) — 있으면 거부
4. 기존 settings.json 보호 검사 — marker 파일 없으면 거부
5. mkdir: `~/work/projectA/.agent-harness/{.boot,tasks,results,review}`
6. settings.json·marker 생성: `~/work/projectA/.claude/settings.json` + `.agent-harness-marker`
7. `.gitignore` 안내(누락 시) — 자동수정 X
8. tmux 세션 생성, pane 분할, 각 pane 에 `cd "$PROJECT_ROOT" && claude --model <m>` + boot 메시지 + `/loop` 주입

### 6.2 배정

메인 pane (cwd=PROJECT_ROOT) 에서 자연어 지시 → 메인이 `dispatch.sh dev T1` 호출
- dispatch source 시점에 PROJECT_ROOT 자동 추론 — 메인 cwd 이므로 일치
- write_harness_task → `$WORKSPACE/.harness-task.dev`
- send_prompt → 워커 pane

### 6.3 실행·완료

워커 cwd=PROJECT_ROOT, Edit/Write → hook → log-event.sh:
- EVENTS_LOG=PROJECT_ROOT/.agent-harness/events.log (env 주입)
- `.agent-harness/*` 경로는 skip
- 5필드 라인 append

완료 시 워커가 `tmux wait-for -S done-agents-projectA-dev-T1` (E1: 채널명에 SESSION prefix 포함, 멀티 동시 가동 시 신호 충돌 방지)

### 6.4 종료

```
~/.../bin/team-down.sh   # cwd=PROJECT_ROOT 가정
```

PROJECT_ROOT 기준 SESSION 종료 + `.agent-harness/` 런타임 정리 + settings.json (표식 있으면) 정리. tasks/results 보존.

### 6.5 동시 가동

projectA 가동 중 별 셸에서:
```
cd ~/work/projectB
~/.../bin/team-up.sh default
```
SESSION=agents-projectB ↔ agents-projectA 공존. settings.json 각자 cwd 의 절대경로 — 두 프로젝트 path 가 다르므로 위치 자체로 자동 분리, 충돌 없음(basename 동일해도). hook env(EVENTS_LOG·REPO_ROOT) 도 settings.json 마다 다른 PROJECT_ROOT 로 박혀있어 무충돌. attach 로 각자 들여다보기.

basename 동명 충돌(예: 둘 다 `auth/`)은 **선행 가동은 정상**, 후행 가동만 SESSION 동명 → 거부 (D8). 메시지에 선행의 PROJECT_ROOT 절대경로를 함께 노출해 사용자가 어느 것이 살아있는지 파악 가능. 회피 방법: 후행을 `SESSION_OVERRIDE=agents-auth2 ~/.../bin/team-up.sh ...` 로 강제.

## 7. 에러·엣지 처리

| 케이스 | 감지 | 대응 |
|---|---|---|
| git repo 아닌 cwd 에서 team-up | `git rev-parse` 실패 | stderr 경고 후 `$PWD` 폴백 (사용자 의도 존중). `--project` 가능 안내 |
| 같은 프로젝트 중복 가동 | `tmux has-session` | 거부 + "attach 또는 team-down 후 재시도" |
| basename 충돌 (둘 다 `auth/`) | SESSION 동명 → 위 케이스 | 메시지에 PROJECT_ROOT 절대경로 함께 표기. 회피: `SESSION_OVERRIDE` |
| basename 특수문자 | sed `[^A-Za-z0-9_-]` → `_` (D3) | 자동 sanitize, stderr 1회 안내 |
| 외부 cwd 에서 dispatch | task 파일 못 찾음 | 기존 task 존재 검사가 안전망. 권장 해법: `--project /path` |
| `team-down` 다른 cwd 에서 호출 | resolve_project_root 가 엉뚱한 PROJECT_ROOT → SESSION 못 찾음 | tmux has-session 확인 후 "세션 없음" 메시지 (현 코드 그대로). `--project` 로 정확 지정 (D1) |
| 자기작업 (PROJECT_ROOT == HARNESS_ROOT) | 별도 분기 없음 | `.agent-harness/` 가 하네스 repo 안에 생김, `.gitignore` 룰 보장 |
| 워커가 PROJECT_ROOT 외부 수정 | hook 의 repo-relative 변환 실패 | 절대경로 그대로 기록. scope 리뷰어가 약한 신호로 잡음 |
| 기존 settings.json 사용자 작성물 | marker 파일 검사 (D2) | 거부 (덮어쓰기 금지). team-down 도 marker 있을 때만 정리 |
| `.gitignore` `.agent-harness/` 룰 누락 | team-up 검사 | stderr 안내만, 자동수정 X (D5: settings.json 룰은 안내 안 함) |
| 메타 산출물 변경 로깅 | log-event 의 화이트리스트 skip (D6) | 메타만 skip, tasks/results 는 기록 |
| 동시 가동 hook 동시 실행 | env·EVENTS_LOG 가 settings.json 마다 다름 | 다른 파일이라 무충돌 |
| 동시 가동 task id 충돌 (둘 다 `1.md`) | 각자 `.agent-harness/tasks/1.md` 별개 파일 | 격리됨, 무충돌 (D7) |
| stale tasks (이전 가동 잔여) | team-down 이 tasks/results 보존 → 다음 가동 시 잔존 | 메인 프롬프트가 `.harness-state` 와 대조해 활성/완료 판별. 모호하면 사용자에게 확인 (D4) |
| PROJECT_ROOT 경로에 금지 문자 (`#`·`'`·`"` 등) | lib.sh 의 정합성 검증 | 즉시 거부, 디렉터리 이름 정리 후 재시도 안내 (E4) |
| `--project` 상대경로 입력 | _normalize_project 가 `cd && pwd` 정규화 | 절대경로화. 디렉터리 없으면 즉시 오류 (E12) |
| `--project` 위치 인자 뒤에 옴 | 파서가 첫 위치 인자에서 break | 옵션 미인식·후속 코드가 위치 인자로 해석. 사용자 혼란 → 문서·테스트로 "옵션은 앞에" 강조 (E7) |
| 하네스 디렉터리 이동 후 attach | settings.json 의 hook absolute path stale | 다음 team-up 까지 hook 동작 안 함. team-up 마다 settings.json 재생성으로 자동 복구. 그 전에 호출되는 dispatch 등 동작은 정상 (hook 만 안 잡힘). 사용자 책임 (E10) |
| `basename PROJECT_ROOT == /` (root) | sanitize 후 `agents-_` | 동작 가능. 비현실적 케이스지만 fail safe (E9) |
| 사용자가 우연히 만든 `.agent-harness/` 가 있는 PROJECT_ROOT 에서 team-down | marker 부재 검사 | settings.json·`.agent-harness/` 둘 다 안 건드림, 세션만 종료, 경고 (E8) |
| `lib.sh` 가 source 중 검증 실패 | PROJECT_ROOT_VALID=0 변수 셋 | 호출 스크립트가 source 후 명시 검사 후 종료. source 셸은 안 죽음 (F1) |
| `--project` bad path 입력 | `_normalize_project` return 1 + 호출자 명시 검사 | exit 1 — silent failure (HARNESS_PROJECT="" 폴백) 회피 (F2) |
| PROJECT_ROOT 에 공백 포함 | path validation 거부 | 디렉터리 이름 정리 후 재시도. 보수적 결정 (F4) |
| 워커가 PROJECT_ROOT 외부에 절대경로 Write | hook 의 skip 검사가 절대경로 기준으로도 점검 | 메타 산출물 경로면 skip, 일반 외부 변경은 절대경로 그대로 기록 (F6) |
| `team-down` marker 없는 채로 호출되어 사용자가 의도 종료 못 함 | tmux list-sessions 안내 | "살아있는 agents-* 세션 목록 + --project 안내" stderr (F8) |

## 8. 테스트 전략

### 8.1 기존 25 스위트 — 변수 의미 변경 흡수

- 임시 git repo(`git init` 후 source) 안에서 호출하도록 setup 수정
- AGENT_CMD=cat 더미 정책 유지
- SESSION_OVERRIDE 강제 패턴(`tu_<pid>`) 그대로 — 자동명과 무간섭

### 8.2 신규 스위트 (8)

1. **`test-project-root.sh`** — `resolve_project_root()` 단위
   - git repo 깊은 하위에서 toplevel 반환
   - git 아닌 디렉터리 → 경고·PWD 폴백
   - submodule 안 → submodule 자체 toplevel
   - **`HARNESS_PROJECT` env 셋이면 그것 우선** (D1)

2. **`test-session-autoname.sh`** — `resolve_session()` 자동명
   - SESSION_OVERRIDE·PROFILE_SESSION·SESSION env 없을 때 `agents-<basename>` 폴백
   - 특수문자 sanitize (sed 기반, bash 3.2 호환 검증, D3)
   - SESSION_OVERRIDE 우선순위 유지

3. **`test-self-harness.sh`** — 자기작업
   - cwd=HARNESS_ROOT 에서 PROJECT_ROOT==HARNESS_ROOT 동등
   - `.agent-harness/` 가 HARNESS_ROOT 안에 생성·정리

4. **`test-settings-protection.sh`** — 사용자 settings.json·`.agent-harness/` 보호 (D2·E8·F8)
   - marker 없는 settings.json 있을 때 team-up 거부
   - marker 있을 때 덮어쓰기 허용·team-down 정리 허용
   - marker 없는 채 team-down 호출 → settings.json·`.agent-harness/` 안 건드림 (E8)
   - marker 없는 채 team-down 호출 시 살아있는 agents-* 세션 list stderr 안내 (F8)

5. **`test-multi-project.sh`** — 동시 가동 격리
   - 임시 git repo 두 개에서 동시 team-up (AGENT_CMD=cat)
   - 두 SESSION 공존, 두 `.agent-harness/` 격리, 한쪽 team-down 이 다른쪽 무영향
   - 두 프로젝트가 같은 task id `1.md` 사용 시 격리 (D7)

6. **`test-project-flag.sh`** — `--project` 옵션 파서 (D1·E7·E12·F2)
   - `bin/team-up.sh --project /path/to/A feature-team` 가 cwd 무관하게 A 를 PROJECT_ROOT 로 사용
   - `--project=/path` 등호 형식
   - dispatch·wait-worker·team-down 도 동일 동작
   - 옵션 미지정 시 cwd 폴백
   - 상대경로 입력 → 절대경로 정규화 (E12)
   - `--project` 가 위치 인자 뒤에 오면 인식 안 됨 검증 (E7)
   - **존재하지 않는 경로 → 즉시 오류**, silent failure 없음 (F2: HARNESS_PROJECT 빈값으로 폴백되지 않는지)

7. **`test-path-validation.sh`** — PROJECT_ROOT 경로 정합성 (E4·F1·F4)
   - 금지 문자 (`#`, `'`, `"`, 공백) 포함 시 `PROJECT_ROOT_VALID=0` 셋 (F1)
   - source 자체는 성공 (exit 안 함, F1)
   - 공백 포함 디렉터리도 거부 (F4 보수)
   - 허용 문자만 있으면 정상 통과·`PROJECT_ROOT_VALID=1`

8. **`test-channel-name.sh`** — wait-for 채널명 격리 (E1)
   - 같은 worker·task 라도 SESSION 다르면 채널명 다름
   - dispatch 의 `done_logged` 헬퍼 호출과 정합 (기존 헬퍼는 채널 무관 events.log 기반이라 무영향 검증)

### 8.3 probe (수동 — `tests/probes/`)

- `probe-multi-project.sh` 신규: 실제 두 프로젝트에서 동시 가동, hook 이 자기 events.log 에만 기록되는지 실측 (probe-hook 의 멀티 버전)

### 8.4 E2E 한계 명시

`test-e2e-harness.sh` 는 메커니즘 배선만 검증, 실 claude 미기동 — 신규 스위트도 동일 원칙 (claude 실측은 probe 만).

## 9. 파일 표 (변경·신규·이동·삭제)

| 종류 | 경로 | 변경 내용 |
|---|---|---|
| 변경 | `bin/lib.sh` | HARNESS_ROOT·PROJECT_ROOT·WORKSPACE 분리, resolve_project_root(HARNESS_PROJECT 우선)·_session_autoname(sed) 신규, resolve_session 폴백 확장 |
| 변경 | `bin/team-up.sh` | --project 파서, cwd=PROJECT_ROOT, mkdir/.agent-harness/, settings.json 보호(marker)·생성 위치 변경, boot 합본 소스 HARNESS_ROOT |
| 변경 | `bin/dispatch.sh` | --project 파서, WORKSPACE 의미 변경 자동 흡수 |
| 변경 | `bin/wait-worker.sh` | --project 파서, 동상 |
| 변경 | `bin/team-down.sh` | --project 파서, `.agent-harness/` 정리, marker 검사 후 settings.json·marker 정리 |
| 변경 | `bin/log-event.sh` | 메타 산출물 화이트리스트 skip(D6), 경로명 변경, 기본값 회귀 |
| 이동 | `workspace/.claude/settings.json.tpl` → `templates/settings.json.tpl` | 토큰 `__PROJECT_ROOT__`·`__HARNESS_ROOT__` 로 분리, _marker 추가 |
| 변경 | `prompts/_common.md`·`prompts/roles/*`·`prompts/loop/*` | `workspace/` → `.agent-harness/` 일괄 |
| 변경 | `profiles/*.sh` (4개) | `SESSION="agents"` 라인 삭제 |
| 변경 | `.gitignore` | workspace/ 룰 제거, `.agent-harness/` 추가 |
| 삭제 | `workspace/` 전체 | 폐기 (PROJECT_ROOT 의 .agent-harness/ 가 대체) |
| 신규 | `tests/test-project-root.sh` | resolve_project_root 단위(HARNESS_PROJECT 우선 포함) |
| 신규 | `tests/test-session-autoname.sh` | _session_autoname·resolve_session 폴백 |
| 신규 | `tests/test-self-harness.sh` | PROJECT_ROOT==HARNESS_ROOT 동등 |
| 신규 | `tests/test-settings-protection.sh` | marker 검사 (D2) |
| 신규 | `tests/test-multi-project.sh` | 동시 가동 격리 |
| 신규 | `tests/test-project-flag.sh` | --project 파서·정규화·위치 (D1·E7·E12) |
| 신규 | `tests/test-path-validation.sh` | PROJECT_ROOT 경로 정합성 (E4) |
| 신규 | `tests/test-channel-name.sh` | wait-for 채널명 SESSION prefix (E1) |
| 신규 | `tests/probes/probe-multi-project.sh` | 수동 실측 (claude 기동) |
| 변경 | `tests/test-*.sh` 다수 | 임시 git repo 안에서 source 하도록 setup 보강 |
| 변경 | `bin/dispatch.sh`·`bin/wait-worker.sh` 의 CHANNEL | `done-$SESSION-$WORKER-$TASK_ID` (E1) |
| 변경 | `prompts/_common.md` | wait-for 채널명 토큰에 `{{SESSION}}` 포함 (E11) |
| 변경 | `README.md` | 호출 cwd·.agent-harness·동시 가동·`--project` 옵션 사용법 안내 (F10) |

## 10. 범위 밖

- 마이그레이션 도구 (깨끗한 전환 선택)
- HARNESS_ROOT/bin 의 PATH 등록(별도 셸 설정 — 사용자 재량, 문서 수준)
- codex 워커 실제 구현 (2차 spec 의 후속과제 유지)
- `.gitignore` 자동수정 (사용자 침범 금지 — 안내만)

## 11. 비고 — 1·2차와의 정합성

- 1차 토대(통신·식별·동기화·생명주기)·2차 하네스(/loop·hook·리뷰어·메인 책임 9개)의 모든 메커니즘 무변경. **변수 의미 분리만** 의 정밀 수술.
- 2차 결정 사항 중 영향:
  - "세션 일회용·정의는 git" 철학 강화 — 정의=HARNESS_ROOT(공유), 결과=PROJECT_ROOT/.agent-harness/(프로젝트별 격리)
  - PostToolUse hook 메커니즘 그대로, env 만 프로젝트별로 주입 (settings.json.tpl 토큰 의미 명확화)
  - `/loop`+Monitor 무변경 — 리뷰어 cwd 가 PROJECT_ROOT 라 `.agent-harness/events.log` 가 자연스레 감시 대상

## 12. 결정의 근거 — 왜 변수 두 개로 분리하는가

- 단일 변수로 두 의미를 표현하면 호출 위치를 바꿔도 동작이 바뀌지 않는 강결합이 생긴다. 분리는 그 결합을 해체하는 가장 작은 단위.
- "정의의 위치"는 git 추적 대상이고 변하지 않음 — 절대경로로 고정. "작업 대상의 위치"는 사용자 의도에 따라 매번 달라짐 — cwd 추론.
- 의미 분리가 코드 줄 수보다 중요한 이유는, 향후 추가 컴포넌트(예: codex 워커, 추가 hook, 외부 도구 통합)가 어느 변수를 써야 할지 한눈에 보이게 만들어 *지속적인 잘못된 결합을 막기* 때문.
