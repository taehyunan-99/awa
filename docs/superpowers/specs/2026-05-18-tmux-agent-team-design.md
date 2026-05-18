# tmux 멀티 에이전트 팀 — 설계 문서

작성일: 2026-05-18
상태: 설계 확정 (구현 전)

## 1. 목적

tmux 페인마다 Claude Code 인스턴스를 띄우고 각각에 역할/제약을 부여해, 1 오케스트레이터 + N 워커 구조의 멀티 에이전트 팀을 운영한다. 1차 목적은 범용 실험 및 구조 학습이며, 이후 사용자 방식대로 커스텀할 수 있도록 확장 포인트를 명확히 둔다.

핵심 철학: **세션은 일회용, 스크립트와 정의 파일이 유일한 진실 공급원.** 세션 상태를 저장/복원하지 않고, git으로 버전 관리되는 정의로부터 `team-up.sh`가 매번 동일한 팀을 수 초 만에 재생성한다.

## 2. 전제 / 환경

- 위치: `~/Desktop/Repo/Practice/tmux-agent-team/` — 독립 git repo (Practice 폴더 내 다른 형제 디렉토리와 동일 패턴), GitHub에 별도 repo로 push
- tmux 3.6+ (`send-keys -l`, `wait-for`, `capture-pane -p` 사용 — 공식 tmux.1 / cmd-wait-for.c 기준)
- claude CLI 설치됨 (대화형 세션 상주 모드로 실행)
- prefix는 tmux 기본값(C-b) 가정, `~/.tmux.conf`는 이 repo 범위 밖이며 수정하지 않음 — README에 전제만 문서화

## 3. 아키텍처

### 3.1 tmux 레이아웃

세션명 `agents`, 단일 윈도우, tiled 레이아웃 (프로파일에서 변경 가능):

```
┌─────────────┬─────────────┐
│ pane 1      │ pane 2      │
│ ORCHESTRATOR│ worker      │
│ (= 메인 사용자/Claude)     │ (claude)    │
├─────────────┼─────────────┤
│ pane 3      │ pane 4      │
│ worker      │ worker      │
│ (claude)    │ (claude)    │
└─────────────┴─────────────┘
```

- pane 1 = 오케스트레이터. 사용자가 직접 보는 페인. 메인 Claude가 여기서 dispatch/wait 스크립트를 호출하며 반자동 조율(작업을 쪼개 워커에 분배·취합, 사용자는 목표만 제시)
- pane 2~N = 워커. 각각 대화형 `claude` 상주, 부트스트랩 규약 주입됨
- target-pane은 공식 `session:window.pane` 형식 (`agents:0.<idx>`)
- **인덱스 규약 (정정)**: 사용자 전역 `~/.tmux.conf`의 `base-index`/`pane-base-index` 설정(예: 둘 다 1)과 무관하게 동작하도록, `team-up.sh`가 세션 생성 직후 해당 세션에 한해 `base-index=0`, `pane-base-index=1`을 세션 로컬로 명시 고정한다(`set-option -t <세션>` + 이미 만들어진 윈도우는 `move-window -r`로 0으로 재정렬). 전역 설정은 절대 변경하지 않으며 다른 세션에 영향이 없다. 따라서 target 형식은 그대로 `<세션>:0.<pane>`, pane 1 = 오케스트레이터, 워커는 pane 2부터.
- **title 규약 (정정·실측 검증)**: 워커 식별 권위는 pane title=워커명. dispatch/wait-worker 가 pane title=워커명으로 워커를 조회한다(§6). `team-up.sh` 는 워커 페인을 `tmux split-window -P -F '#{pane_id}'` 로 만들면서 새 페인의 **영속 pane_id(`%N`)** 를 즉시 캡처하고, 그 pane_id 로 `select-pane -T <워커명>` title 설정과 부트스트랩 주입(`send-keys`)을 수행한다. pane_id 는 `select-layout` 의 pane index 재배열에도 불변이므로 layout 재배열에 면역이다(이전 index 기반 주소지정 버그를 제거). title 보존의 결정타는 `team-up.sh` 가 세션 생성 직후 세션 로컬로 고정하는 **`allow-set-title off`** — 워커 셸의 OSC `\e]0;..\007`/`\e]2;..` title escape 를 차단한다. `allow-rename off`/`automatic-rename off` 는 window-name 전용 보강(무해)으로 함께 고정. 전역 `~/.tmux.conf` 는 불변이며 다른 세션에 영향이 없다(실측 검증: `allow-set-title off` 시 OSC 0 escape 후에도 `pane_title` 보존됨).
- "에이전트"는 tmux 개념이 아님 — 페인에서 claude를 실행하고 역할 프롬프트를 주입해 만들어내는 개념. tmux가 아는 것은 세션/윈도우/페인뿐

### 3.2 Repo 구조

```
~/Desktop/Repo/Practice/tmux-agent-team/
├── .gitignore
├── README.md                       # 사용법, 아키텍처, 전제(tmux 3.6+ 등)
├── profiles/                       # 상황·업무별 팀 정의 (source 가능한 .sh)
│   ├── default.sh                  # 1 오케 + dev/review/test
│   ├── code-review.sh              # 1 오케 + reviewer×2 + security
│   └── research.sh                 # 1 오케 + researcher×3
├── prompts/
│   ├── _common.md                  # 모든 워커 공통 규약 (작업 사이클·금지)
│   └── roles/
│       ├── dev.md
│       ├── reviewer.md
│       ├── tester.md
│       ├── security.md
│       └── researcher.md
├── bin/
│   ├── lib.sh                      # 공통 함수
│   ├── team-up.sh [profile]        # 팀 생성
│   ├── dispatch.sh <worker> <id>   # 작업 배정
│   ├── wait-worker.sh <worker> [timeout]  # 완료 대기
│   └── team-down.sh                # 세션 정리
├── docs/superpowers/specs/         # 이 설계 문서
└── workspace/                      # .gitignore (런타임 산출물)
    ├── .gitkeep
    ├── .boot/<worker>.md           # 부트스트랩 합본 (런타임 생성)
    ├── tasks/<id>.md               # 오케가 쓰는 작업 지시
    └── results/<id>.md             # 워커가 쓰는 결과
```

git 관리 대상: `bin/`, `profiles/`, `prompts/`, `README.md`, `.gitignore`, `docs/`. 제외: `workspace/tasks/`, `workspace/results/`, `workspace/.boot/`, `*.log`.

### 3.3 프로파일 시스템

`profiles/*.sh`는 source 가능한 셸 스크립트 (의존성 zero, macOS 기본 동작):

```sh
# profiles/default.sh
SESSION="agents"
LAYOUT="tiled"                    # tmux 공식 레이아웃명
# 형식: "워커이름:역할"  (역할 → prompts/roles/<역할>.md)
WORKERS=(
  "dev:dev"
  "review:reviewer"
  "test:tester"
)
```

`bin/` 스크립트는 프로파일에 무관하게 고정. 새 팀은 `profiles/*.sh` + 필요 시 `prompts/roles/*.md`만 추가하면 되고, git 커밋 해시로 "그때 그 팀"을 정확히 재현 가능.

## 4. 통신 프로토콜

### 4.1 오케 → 워커: 명령 주입 (send-keys)

공식 tmux.1 기준, 텍스트와 Enter를 분리해 주입(개행/특수문자 안전):

```sh
send_prompt() {
  local target="$1" text="$2"
  tmux send-keys -t "$target" -l "$text"   # -l: 리터럴 UTF-8, 키 룩업 비활성화
  tmux send-keys -t "$target" Enter        # Enter는 별도
}
```

긴 텍스트는 절대 직접 주입하지 않는다. `dispatch.sh`는 작업 내용이 아니라 `TASK <id>` 짧은 지시만 주입하고, 워커가 `workspace/tasks/<id>.md`를 읽는다.

### 4.2 워커 → 오케: 완료 신호 (wait-for)

공식 cmd-wait-for.c 기준, 폴링 없는 블로킹 동기화. 신호가 대기보다 먼저 와도 채널이 "woken"으로 기록되어 race 없음:

```sh
# 워커가 작업 종료 시 마지막으로 실행:
tmux wait-for -S done-<worker>-<id>

# 오케(wait-worker.sh)는 블로킹 대기:
tmux wait-for done-<worker>-<id>
```

채널명은 매 작업 `done-<worker>-<id>`로 유니크하게 하여 이전 작업의 신호가 다음 대기에 잘못 매칭되는 것을 방지한다.

### 4.3 결과 데이터: 파일

워커는 결과를 `workspace/results/<id>.md`(성공/실패 상태, 산출물 경로, 요약)에 기록한 뒤 완료 신호를 보낸다. 오케는 신호를 받으면 해당 파일을 Read 한다.

### 4.4 생존/디버그 (보조): capture-pane

워커가 멈춘 것으로 의심되면 오케가 `tmux capture-pane -p -t agents:0.<idx>`로 화면을 덤프해 상황을 판단한다.

### 4.5 한 사이클

```
오케:  tasks/T1.md 작성 → dispatch.sh dev T1 (send-keys 주입)
워커:  T1.md 읽기 → 작업 → results/T1.md 작성 → wait-for -S done-dev-T1
오케:  wait-for done-dev-T1 (블로킹 해제) → results/T1.md Read → 취합
```

## 5. 워커 부트스트랩 규약

`team-up.sh`가 페인 생성 직후 `prompts/_common.md` + `prompts/roles/<역할>.md`를 합쳐 `workspace/.boot/<worker>.md`에 쓰고, 워커에는 "workspace/.boot/<worker>.md 를 읽고 그 규약을 따르라" 한 줄만 주입한다 (긴 텍스트 파일 경유 원칙 일관 적용). 주입 전 `{{WORKER_NAME}}`을 실제 워커 이름으로 치환하여 워커마다 전용 신호 채널을 갖게 한다.

`prompts/_common.md` (공통 규약, 요지):

```markdown
너는 tmux 멀티 에이전트 팀의 워커다. 워커 이름: {{WORKER_NAME}}

## 작업 사이클 (반드시 준수)
1. "TASK <id>" 지시를 받으면 workspace/tasks/<id>.md 를 읽어 작업을 파악한다.
2. 작업을 수행한다.
3. 결과를 workspace/results/<id>.md 에 기록한다 (상태/산출물 경로/요약).
4. 마지막에 완료 신호: tmux wait-for -S done-{{WORKER_NAME}}-<id>
5. 다음 지시를 대기한다. 임의로 다른 작업을 시작하지 않는다.

## 금지
- tasks/ 외의 지시를 추측해 실행하지 않는다.
- 완료 신호 없이 작업을 끝났다고 간주하지 않는다.
- 다른 워커의 페인이나 파일에 간섭하지 않는다.
```

`prompts/roles/dev.md` (역할별 추가, 예시):

```markdown
## 역할: 개발자
- tasks 지시에 따라 코드를 구현/수정한다.
- 기존 코드 패턴을 따른다. 타입 에러를 남기지 않는다.
- 결과 파일에 변경한 파일 목록과 diff 요약을 포함한다.
```

## 6. 스크립트 책임 정의

| 스크립트 | 책임 | 핵심 동작 |
|---|---|---|
| `lib.sh` | 공통 함수 | `send_prompt()`, `target_of(idx)`, `boot_file(worker)`, 세션 존재 확인, `fix_session_titles()`(세션 로컬 `allow-set-title off` 결정타 + rename off 보강) |

> `target_of`는 활성 세션(`SESSION` 변수, 없으면 `SESSION_DEFAULT`)을 존중하여 세션 오버라이드/멀티팀을 지원한다. `team-up.sh`/`dispatch.sh`/`wait-worker.sh`는 `SESSION="${SESSION_OVERRIDE:-...}"`를 설정한 뒤 `target_of`를 호출한다.
| `team-up.sh [profile]` | 팀 생성 | 프로파일 source → 세션 생성 → 인덱스 고정 → `fix_session_titles`(allow-set-title off) → `split-window -P -F '#{pane_id}'`로 워커 페인 생성·**영속 pane_id 캡처** → 그 pane_id로 title=워커명 설정·부트스트랩 합본 작성·치환·주입. pane_id 기반이라 `select-layout`의 index 재배열에 면역. dispatch/wait-worker는 pane title=워커명으로 워커를 조회한다(team-up이 allow-set-title off로 보존, pane_id로 정확 설정) |
| `dispatch.sh <worker> <id>` | 작업 배정 | `tasks/<id>.md` 존재 확인 → target 페인 존재 검증 → `TASK <id>` 주입 |
| `wait-worker.sh <worker> [timeout]` | 완료 대기 | `timeout`으로 감싼 `tmux wait-for done-<worker>-<id>`; 타임아웃 시 capture-pane 덤프 |
| `team-down.sh` | 정리 | 세션 kill, `workspace/.boot/` 정리 |

## 7. 에러 처리

- 모든 스크립트 `set -euo pipefail` (조용한 실패 방지)
- **워커 부재**: `dispatch.sh`가 `tmux list-panes`로 target 검증, 없으면 즉시 명확한 에러
- **wait-for 무한 대기**: 워커 사망 시 신호가 영영 안 옴 → `wait-worker.sh`를 `timeout` 명령으로 래핑. 타임아웃 시 `capture-pane -p`로 워커 화면 덤프 출력 후 실패 반환 → 오케가 판단
- **race 안전**: 공식 cmd-wait-for.c 확인 — 워커가 먼저 `-S` 신호 보내도 누락 없음. 채널명을 작업별 유니크(`done-<worker>-<id>`)로 하여 신호 오매칭 방지
- **결과 파일 없음**: 신호는 왔으나 `results/<id>.md` 부재 → 오케가 실패로 간주, capture-pane으로 원인 확인
- **중복 실행**: `team-up.sh`가 기존 `agents` 세션 감지 시 중복 생성하지 않고 명확히 안내(attach 또는 team-down 권유)
- **continuum 오염 방지**: `team-up.sh`가 세션 생성 직후 해당 세션 자동저장을 사실상 비활성화하여, 인터랙티브 claude를 복원 못 하는 resurrect 한계를 우회하고 스크립트를 유일 재생성 경로로 유지
- **전역 tmux 인덱스 설정 비의존 (세션 로컬 옵션 고정)**: 사용자 전역 `base-index`/`pane-base-index` 값과 무관하게, `team-up.sh`가 세션 로컬로 `base-index=0`/`pane-base-index=1`을 강제하고 `move-window -r`로 기존 윈도우를 재정렬한다. 전역 conf 비침습, `target_of`의 `<세션>:0.<pane>` 가정과 항상 일치
- **pane title 훼손 방지 (세션 로컬 `allow-set-title off`)**: dispatch/wait-worker 가 pane title=워커명으로 워커를 조회하므로, `team-up.sh`가 세션 로컬로 `allow-set-title off`(결정타: 워커 셸의 OSC `\e]0;..`/`\e]2;..` pane title escape 차단)를 고정한다. `allow-rename off`/`automatic-rename off`는 window-name 전용 보강(무해)으로 함께 고정. 전역 `~/.tmux.conf` 불변(실측 검증: `allow-set-title off` 시 OSC0 escape 후에도 `pane_title` 보존)
- **layout 재배열 면역 (pane_id 기반 주소지정)**: `team-up.sh`가 워커 페인을 `split-window -P -F '#{pane_id}'`로 만들며 영속 pane_id를 캡처해 배열에 저장, title 설정·부트스트랩 주입을 모두 그 pane_id로 수행한다. `select-layout`이 pane index를 재배열해도 pane_id는 불변이므로 dev/review/test title이 정확한 페인에 안정적으로 걸린다(이전 index 기반 주소지정 버그 제거)

## 8. 검증 (구현 후 8 케이스)

정상 4:
1. `team-up.sh default` → 4페인 생성, 워커 3개 부트스트랩 주입 확인
2. `dispatch.sh dev T1` → 워커가 `tasks/T1.md` 읽고 `results/T1.md` 생성
3. `wait-worker.sh dev` → 신호 받고 즉시 반환
4. 한 사이클 전체(dispatch→wait→결과 Read) 정상 동작

엣지 4:
5. 존재하지 않는 워커로 dispatch → 즉시 명확한 에러
6. 워커가 결과 파일 안 쓰고 신호만 → 오케가 "결과 없음" 감지
7. `wait-worker.sh` 타임아웃 → capture-pane 덤프 출력 후 실패
8. `team-up.sh` 두 번 실행 → 기존 세션 감지, 중복 생성 안 함

## 9. 비목표 (YAGNI)

- 작업 큐/DAG 의존성 스케줄러 (워커 수십 개·복잡 의존 시점에 Python 오케로 점진 이행 — 현재 불필요)
- 세션 상태 영속화/복원 (스크립트 재생성으로 대체)
- 여러 팀 동시 상시 가동 (자원 낭비, 빠른 재생성으로 대체)
- ~/.tmux.conf 변경 (repo 범위 밖)
