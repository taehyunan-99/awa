# tmux 멀티 에이전트 팀

tmux 페인마다 Claude Code 인스턴스를 띄우고 역할/제약을 부여해, 1 lead + N 워커 멀티 에이전트 팀을 운영한다.

## 전제

- tmux 3.6+ (`send-keys -l`, `wait-for`, `capture-pane` 사용)
- `claude` CLI 설치 및 PATH 등록
- prefix는 tmux 기본값(C-b) 가정. `~/.tmux.conf`는 이 repo가 수정하지 않음.
- 사용자 전역 tmux 의 base-index/pane-base-index 설정과 무관하게 동작 (team-up 이 세션 로컬로 인덱스·title 옵션을 고정).

## 철학

세션은 일회용. git 으로 버전 관리되는 `profiles/` + `prompts/` 정의로부터 `team-up.sh` 가 매번 동일한 팀을 재생성한다. 세션 상태를 저장/복원하지 않는다.

## 사용법

작업하려는 프로젝트의 디렉터리에서 호출한다(자동감지). 또는 어디서든 `--project /path` 로 명시.

```bash
# 1) 프로젝트로 이동 후 팀 가동 (작업 대상 = 현재 cwd 의 git toplevel)
cd ~/work/projectA
~/Desktop/Repo/Practice/tmux-agent-team/bin/team-up.sh feature-team
# 또는 어디서든:
#   ~/.../bin/team-up.sh --project ~/work/projectA feature-team
# 주의: --project 는 프로파일/위치 인자 앞에 와야 인식된다
#       (`--project ~/x default`, `--project=~/x default` 형식).

tmux attach -t agents-projectA   # 세션명은 basename 기반 자동

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

## 프로파일

`profiles/*.sh` 로 팀 구성을 정의. `bin/team-up.sh <프로파일명>` 으로 선택.

- `default` — 워커: dev / test, 리뷰어: quality-rev
- `code-review` — 워커: security, 리뷰어: spec-rev / quality-rev / arch-rev
- `research` — 워커: researcher×3, 리뷰어: quality-rev
- `feature-team` — 워커: dev / test / arch, 리뷰어: spec-rev / quality-rev / arch-rev (모델 차등)

새 팀: `profiles/<name>.sh` 추가 (`SESSION`, `LAYOUT`, `WORKERS=("이름:역할[:모델]" ...)`, 선택 `REVIEWERS=(...)`, `LEAD_MODEL`), 필요 시 `prompts/roles/<역할>.md` 추가. `bin/` 은 수정 불필요.

## 통신 메커니즘

- 명령 주입: `tmux send-keys -l` (텍스트/Enter 분리)
- 완료 감지: watcher 데몬이 `events.log`·`pending-asks/` 를 폴링해 관련 pane 을 깨움(과거 `wait-for` 블로킹 대체).
- 결과 전달: `<PROJECT_ROOT>/.agent-harness/results/<id>.md` 파일
- 디버그: `tmux capture-pane -p`
- **역할간 신호 프로토콜** — pane 에 주입되는 텍스트 prefix 로 발신자/의도를 구분(코드 파싱이 아닌 수신 에이전트가 해석):
  | 신호 | 방향 | 발신 | 의미 |
  |---|---|---|---|
  | `@pm:` | pm → lead | pm 이 send-keys | 작업영향 결정 전달(새 작업·스펙변경·우선순위). lead 가 분해해 dispatch. |
  | `@lead-ask:` | lead → pm | lead 가 send-keys | lead 가 막혀 pm 판단 요청(모호한 task·사용자 판단·단계전이). pm 이 사용자와 의논 후 `@pm:` 로 회신. |
  | `@lead:` | worker → lead | 워커 stdout 표기 | rm 위임(`@lead: rm <path> — <reason>`). lead 가 발견 후 승인·대행. |
  | `@gate:` | watcher → lead | watcher 가 send-keys | pending-asks 권한 대기. lead 가 전수 처리. |
  | `@done:` | watcher → lead | watcher 가 send-keys | 워커 완료(`@done: <worker>/<task>`). lead 가 results/ 확인·종합. |
  | `@review:` | watcher → reviewer | watcher 가 send-keys | events.log 증분 검토(디바운스). reviewer 가 1회 실행. |
- 워커 식별: pane title=워커명 (team-up 이 split-window -P 의 pane_id 로 정확히 설정하고 `allow-set-title off` 로 셸 escape 로부터 보존)
- 부트 프롬프트는 `{{HARNESS_ROOT}}` 토큰을 통해 도구 절대경로를 박는다. team-up 이 sed 치환으로 실제 경로로 변환. 워커는 항상 `{{HARNESS_ROOT}}/bin/<name>.sh` 절대경로로 도구 호출.

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

- 가동: `bin/team-up.sh feature-team` (워커 + review 윈도우 + 모델 차등)
- 초회 가동 시 claude 가 폴더 신뢰를 1회 묻습니다 — team-up 이 자동 통과하나, 응답이 없으면 각 pane 에서 수동 Enter(트러스트 확인) 필요할 수 있습니다.
- 단계 자동 전이 안 함 — 사용자가 pm 과 의논해 PRD→Arch→구현 단계를 수동 진행(pm→lead 전달)
- 감시: watcher 가 events.log·pending-asks 를 폴링해 lead/reviewer 를 send-keys 로 깨움(약한 신호 scope 즉시 / 강한 신호 done 후 의미 판정)
- 설계: `docs/superpowers/specs/2026-05-19-agent-harness-design.md`
- 실측 프로브(claude 기동): `tests/probes/probe-{loop,hook}.sh` (수동)
- 3차(PROJECT_ROOT 분리): 임의 프로젝트 작업·동시 가동 지원. 설계: `docs/superpowers/specs/2026-05-20-project-root-separation-design.md`

## 권한 모델 (4차 P0)

워커별 settings.json 사본으로 위험 명령 자동 차단:

- **dev**: `git push`, `rm` (절대경로 포함), `gh pr` 차단. `templates/settings.dev.json.tpl`.
- **tester**: `rm` 만 차단.
- **reviewer (quality)**: *prompt 단계 제약*. 기술적 차단 불가 (claude PreToolUse hook deny + acceptEdits 공존 시 무효 — probe 36). lead 가 `permission-events.log`·`events.log` 감시.
- **lead**: 차단 없음 (조정자).

### 한계 (정직성)

- **reviewer Read-only 기술적 차단 불가** — probe 36 으로 PreToolUse hook deny 가 acceptEdits 와 공존 시 무효 확정. prompt 단계 제약 + lead 의 두 로그 감시로 *부드러운 차단* 만 가능. reviewer 가 prompt 어기면 행위는 기록되지만 실행은 막을 수 없음.
- **rm 경로 변형 미커버** — macOS 의 `/usr/bin/rm`·`/bin/rm` 만. Homebrew (`/usr/local/bin/rm`, `/opt/homebrew/bin/rm`), Linux (`/snap/bin/rm` 등) 환경에선 PATH 확인 후 `templates/settings.dev.json.tpl` 의 deny 에 직접 추가 필요.
- **wrapper 우회 차단됨** — `bash -c "rm ..."`·`sh -c`·`eval` 모두 `Bash(rm *)` 매치 (probe 37-40 확정).
- **|| fallback** — `rm X || echo OK` 시 rm 차단되지만 echo 실행. 명령 차단이지 의도 차단 아님.
- **settings.deny 미커버 위험 명령** — `chmod 777`, `sudo`, `dd`, `mv $HOME` 등 호출 시 claude 가 *묻기 모드* 로 들어가 pane 멈춤. deny 패턴 확장 필요 시 `templates/settings.dev.json.tpl` 수정.
- **MCP 도구·Read/Grep/Glob/WebFetch** 전부 자유. 본 spec 범위 밖.
- **claude 권한 모델 비결정성** — claude 버전 업그레이드마다 깨질 수 있음. `RUN_INTEGRATION=1 bash tests/run-all.sh` 로 정기 회귀.

상세: `docs/superpowers/specs/2026-05-21-harness-4th-P0-permissions-design.md`.
