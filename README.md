# tmux 멀티 에이전트 팀

tmux 페인마다 Claude Code 인스턴스를 띄우고 역할/제약을 부여해, 1 lead + N 워커 멀티 에이전트 팀을 운영한다.

## 전제

- tmux 3.6+ (`send-keys -l`, `wait-for`, `capture-pane` 사용)
- `claude` CLI 설치 및 PATH 등록
- prefix는 tmux 기본값(C-b) 가정. `~/.tmux.conf`는 이 repo가 수정하지 않음.
- 사용자 전역 tmux 의 base-index/pane-base-index 설정과 무관하게 동작 (awa-up 이 세션 로컬로 인덱스·title 옵션을 고정).

## 철학

세션은 일회용. git 으로 버전 관리되는 `profiles/` + `prompts/` 정의로부터 `awa-up.sh` 가 매번 동일한 팀을 재생성한다. 세션 상태를 저장/복원하지 않는다.

## 사용법

작업하려는 프로젝트의 디렉터리에서 호출한다(자동감지). 또는 어디서든 `--project /path` 로 명시.

```bash
# 1) 프로젝트로 이동 후 팀 가동 (작업 대상 = 현재 cwd 의 git toplevel)
cd ~/work/projectA
~/Desktop/Repo/Practice/agenphony/bin/awa-up.sh feature-team
# 또는 어디서든:
#   ~/.../bin/awa-up.sh --project ~/work/projectA feature-team
# 주의: --project 는 프로파일/위치 인자 앞에 와야 인식된다
#       (`--project ~/x default`, `--project=~/x default` 형식).

tmux attach -t awa-projectA   # 세션명은 basename 기반 자동

# 2) 작업 지시 작성
echo "# T1: 로그인 버그 수정" > ~/work/projectA/.agent-harness/tasks/T1.md

# 3) 워커에 배정 (메인 pane 이 dispatch 호출하는 게 일반적)
~/.../bin/dispatch.sh dev T1
# 외부 셸에서:  ~/.../bin/dispatch.sh --project ~/work/projectA dev T1

# 4) 완료는 watcher(셸 데몬)가 감지해 lead 를 깨운다 — 수동 대기 불필요.
#    진행상황은 events.log / results/ 를 읽어 확인.

# 5) 결과 확인
cat ~/work/projectA/.agent-harness/results/T1.md

# 6) 팀 정리 (tasks/results 는 보존, 런타임만 정리)
~/.../bin/awa-down.sh   # cwd=projectA 기준
# 또는:  ~/.../bin/awa-down.sh --project ~/work/projectA
```

## 멀티 프로젝트 동시 가동

서로 다른 프로젝트라면 동시에 가동 가능. SESSION 은 `awa-<basename>` 자동.

```bash
# 셸 1
cd ~/work/projectA && ~/.../bin/awa-up.sh default
# 셸 2
cd ~/work/projectB && ~/.../bin/awa-up.sh default
# → tmux 에 awa-projectA·awa-projectB 두 세션 공존
```

basename 충돌 시(둘 다 `auth/`) 후행 가동만 거부. 회피:
```bash
SESSION_OVERRIDE="awa-auth2" ~/.../bin/awa-up.sh default
```

## 프로파일

`profiles/*.sh` 로 팀 구성을 정의. `bin/awa-up.sh <프로파일명>` 으로 선택.

- `default` — 워커: dev / test, 리뷰어: quality-rev
- `code-review` — 워커: security, 리뷰어: spec-rev / quality-rev / arch-rev
- `research` — 워커: researcher×3, 리뷰어: quality-rev
- `feature-team` — 워커: dev / test / arch, 리뷰어: spec-rev / quality-rev / arch-rev (모델 차등)

새 팀: `profiles/<name>.sh` 추가 (`SESSION`, `LAYOUT`, `WORKERS=("이름:역할[:모델]" ...)`, 선택 `REVIEWERS=(...)`, `LEAD_MODEL`), 필요 시 `prompts/roles/<역할>.md` 추가. `bin/` 은 수정 불필요.

## 역할 추가 (파츠화 확장)

새 역할 추가:
1. `prompts/roles/NN-part/<역할>.md` 작성 (첫 줄 = 한 줄 desc. 워커는 5축 형식 — _common.md 참조. **lead/pm 은 전용 축**(lead=신호→반응 6절 ⓐ~ⓕ / pm=대화·pull·전달 3절 ⓐ~ⓒ)이며 `_common` 미상속).
2. 프로파일에 `WORKERS+=("이름:<역할>:모델")` 또는 `REVIEWERS+=(...)` 엔트리 추가.
3. 끝 — up 이 `roles/*/<역할>.md` 글롭으로 자동 해석·카탈로그 등록. **프롬프트는 코드수정 0.**

모든 역할 md 는 **100줄 캡**(가드레일: `tests/test-line-cap.sh`). **lead 권한 게이트 절차는 `prompts/_partials/lead-gate.md` 단일출처** — lead boot 시 sed 치환 *이전*에 합본 cat 으로 주입(`bin/awa-up.sh`), 본문 중복 금지.

권한(settings)은 자동이 아니다:
- 새 역할 권한이 기존 군(dev/test/reviewer/lead/pm)과 같으면 추가 작업 없음(default 또는 같은 case).
- 다르면 `bin/lib.sh` 의 `generate_worker_settings` case 에 1줄 추가 + 필요시 `templates/settings.<군>.json.tpl`. (reviewer-* 는 글롭이라 자동.)

불변식: 역할명은 전 파트에서 고유 (= 파일명). 중복 시 `resolve_role_file` 가 fail-fast.
새 파트: `roles/NN-newpart/` 디렉터리 생성 후 위 1~2. 번호 append.

## 통신 메커니즘

- 명령 주입: `tmux send-keys -l` (텍스트/Enter 분리)
- 완료 감지: watcher 데몬이 `events.log`·`pending-asks/` 를 폴링해 관련 pane 을 깨움(과거 `wait-for` 블로킹 대체).
- 결과 전달: `<PROJECT_ROOT>/.agent-harness/results/<id>.md` 파일
- 디버그: `tmux capture-pane -p`
- **역할간 신호 프로토콜** — pane 에 주입되는 텍스트 prefix 로 발신자/의도를 구분(코드 파싱이 아닌 수신 에이전트가 해석):
  | 신호 | 방향 | 발신 | 의미 |
  |---|---|---|---|
  | `@pm:` | pm → lead | pm 이 send-keys | 작업영향 결정 전달(새 작업·스펙변경·우선순위). lead 가 분해해 dispatch. |
  | `@lead:` | worker → lead | 워커 stdout 표기 | rm 위임(`@lead: rm <path> — <reason>`). lead 가 발견 후 승인·대행. |
  | `@gate:` | watcher → lead | watcher 가 send-keys | pending-asks 권한 대기. lead 가 전수 처리. |
  | `@done:` | watcher → lead | watcher 가 send-keys | 워커 완료(`@done: <worker>/<task>`). lead 가 results/ 확인·종합. |
  | `@review:` | watcher → reviewer | watcher 가 send-keys | events.log 증분 검토(디바운스). reviewer 가 1회 실행. |
- 워커 식별: pane title=워커명 (awa-up 이 split-window -P 의 pane_id 로 정확히 설정하고 `allow-set-title off` 로 셸 escape 로부터 보존)
- 부트 프롬프트는 `{{HARNESS_ROOT}}` 토큰을 통해 도구 절대경로를 박는다. awa-up 이 sed 치환으로 실제 경로로 변환. 워커는 항상 `{{HARNESS_ROOT}}/bin/<name>.sh` 절대경로로 도구 호출.

## 환경변수

| 이름 | 기본 | 의미 |
|---|---|---|
| `SHELL_READY_TIMEOUT` | 15 (초) | pane 셸 ready 폴링 timeout. conda init 등 느린 환경에서 늘림. |
| `BOOT_REPL_CHECK_DELAY` | 5 (초) | claude 명령 송신 후 trust/REPL 검출 매치 윈도우. (timeout 아님 — 검사 대기.) |
| `HARNESS_PROJECT` | (없음) | PROJECT_ROOT 강제 지정. 기본은 git toplevel 또는 PWD 폴백. |
| `PROMPTS_DIR` | `$HARNESS_ROOT/prompts` | 부트 프롬프트 디렉터리 override (주로 테스트 fixture 용). |

## 테스트

```bash
bash tests/run-all.sh
```

외부 의존성 없음. 실제 tmux 세션을 띄우되 워커 명령을 `AGENT_CMD` 환경변수로 더미 치환해 검증한다.

## 디렉터리

- **HARNESS_ROOT** (이 repo) — `bin/`·`profiles/`·`prompts/`·`templates/`. 정의 자산. 모든 프로젝트 공유.
- **PROJECT_ROOT** (각자 프로젝트) — `.agent-harness/{tasks,results,review,events.log,.harness-state,...}`, `.claude/settings.json`, `.claude/.agent-harness-marker`. 일시 산출물.

`.agent-harness/` 와 `.claude/.agent-harness-marker` 는 프로젝트 `.gitignore` 에 추가 권장(가동 시 안내).

- `docs/` — 로컬 설계/계획 문서 (.gitignore, git 추적 안 함)

## 에이전트 하네스 (2차)

사용자 창구(pm) + 순수 오케스트레이터(lead) 분리 + watcher 데몬 이벤트 반응형 감시 + scope 사전차단 + 모델 차등.

- 가동: `bin/awa-up.sh feature-team` (워커 + review 윈도우 + 모델 차등)
- 초회 가동 시 claude 가 폴더 신뢰를 1회 묻습니다 — awa-up 이 자동 통과하나, 응답이 없으면 각 pane 에서 수동 Enter(트러스트 확인) 필요할 수 있습니다.
- 단계 자동 전이 안 함 — 사용자가 pm 과 의논해 PRD→Arch→구현 단계를 수동 진행(pm→lead 전달). 단, `--plan` 으로 확정 plan 을 주입해 가동하면 LEAD 가 그 plan 을 분해·배정 트리 출력 후 사용자 승인(AskUserQuestion)을 받아 실행 착수한다(plan 실행은 자동전이가 아님 — 11차).
- 감시: watcher 가 events.log·pending-asks 를 폴링해 lead/reviewer 를 send-keys 로 깨움(약한 신호 scope 즉시 / 강한 신호 done 후 의미 판정)
- 설계: `docs/superpowers/specs/2026-05-19-agent-harness-design.md`
- 실측 프로브(claude 기동): `tests/probes/probe-{loop,hook}.sh` (수동)
- 3차(PROJECT_ROOT 분리): 임의 프로젝트 작업·동시 가동 지원. 설계: `docs/superpowers/specs/2026-05-20-project-root-separation-design.md`

## 확정 plan 자동주입 (11차)

Phase0(계획)에서 만든 확정 plan 문서를 가동 시 LEAD 에 자동주입한다.

- 가동: `bin/awa-up.sh --project <repo> --plan PRD.md --plan ARCH.md feature-team` (`--plan` 반복 가능)
- 여러 plan 파일은 `.agent-harness/.boot/plan.md` 단일 합본(고정 헤더 `# 확정 plan (이번 가동의 작업 계획)` + 파일별 `## <파일명>`)으로 cat 된 뒤, claude 분기에서 `--append-system-prompt-file` 로 LEAD 에 주입된다(send-keys 무관, 공식 보장 경로).
- LEAD 는 고정 헤더로 plan 주입을 인지 → boot 직후 분해 → 배정 트리 출력 → AskUserQuestion 승인 게이트 → dispatch. plan 미주입(`--plan` 없음)이면 기존대로 `@pm:` 지시 대기(하위호환).
- awa-down 은 `--plan` 을 무시한다(awa-up 과 인자 대칭).

## 권한 모델 (4차 P0)

워커별 settings.json 사본으로 위험 명령 자동 차단:

- **dev**: `git push`, `rm` (절대경로 포함), `gh pr` 차단. `templates/settings.dev.json.tpl`.
- **tester**: `rm` 만 차단.
- **reviewer (quality)**: `review/` 와 `.review-cursor.*` 에만 Write 허용(verdict·커서 기록), 그 외 Write 는 *prompt 단계 제약* + 게이트 회색(코드 수정 시 lead 감지). 기술적 완전차단 불가 (claude PreToolUse hook deny + acceptEdits 공존 시 무효 — probe 36). lead 가 `permission-gate.log`·`events.log` 감시.
- **pm**: 읽기전용 — `Write`·`Edit`·`NotebookEdit` deny 로 코드 강제(사용자 창구, 파일 안 씀).
- **lead**: 차단 없음 (조정자, `bypassPermissions`).

> **push-pull 창구 경계 (11차)**: PM 은 사용자 요청 전달 창구다(사용자가 pull). 단계 전이(PRD→Arch→구현 같은 *완료 단계에서 다음 단계로*)·스펙 변경 같은 "무엇을" 결정은 PM 창구를 거친다(사용자↔pm→`@pm:`→lead). 반면 LEAD 는 *작업 실행 판단*을 사용자에게 **직접 push(AskUserQuestion)** 한다 — 워커 회색 명령의 권한 게이트 판단(watcher `@gate:` 로 깨워짐), stale task·품질 게이트 진행 여부, 확정 plan 배정 트리 승인 등. 판단 불필요한 진도는 `.harness-state` 기록으로 조용히 보고(pm 이 pull-read). (9차의 `@lead-ask:` LEAD→PM 역방향 위임은 11차에 제거 — LEAD 가 막히면 PM 우회가 아니라 사용자에게 직접 push 한다.)

### 한계 (정직성)

- **reviewer Read-only 기술적 차단 불가** — probe 36 으로 PreToolUse hook deny 가 acceptEdits 와 공존 시 무효 확정. prompt 단계 제약 + lead 의 두 로그 감시로 *부드러운 차단* 만 가능. reviewer 가 prompt 어기면 행위는 기록되지만 실행은 막을 수 없음.
- **rm 경로 변형 미커버** — macOS 의 `/usr/bin/rm`·`/bin/rm` 만. Homebrew (`/usr/local/bin/rm`, `/opt/homebrew/bin/rm`), Linux (`/snap/bin/rm` 등) 환경에선 PATH 확인 후 `templates/settings.dev.json.tpl` 의 deny 에 직접 추가 필요.
- **wrapper 우회 차단됨** — `bash -c "rm ..."`·`sh -c`·`eval` 모두 `Bash(rm *)` 매치 (probe 37-40 확정).
- **|| fallback** — `rm X || echo OK` 시 rm 차단되지만 echo 실행. 명령 차단이지 의도 차단 아님.
- **settings.deny 미커버 위험 명령** — `chmod 777`, `sudo`, `dd`, `mv $HOME` 등 호출 시 claude 가 *묻기 모드* 로 들어가 pane 멈춤. deny 패턴 확장 필요 시 `templates/settings.dev.json.tpl` 수정.
- **MCP 도구·Read/Grep/Glob/WebFetch** 전부 자유. 본 spec 범위 밖.
- **claude 권한 모델 비결정성** — claude 버전 업그레이드마다 깨질 수 있음. `RUN_INTEGRATION=1 bash tests/run-all.sh` 로 정기 회귀.

상세: `docs/superpowers/specs/2026-05-21-harness-4th-P0-permissions-design.md`.
