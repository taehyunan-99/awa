# 에이전트 하네스 — 설계 문서

작성일: 2026-05-19
상태: 설계 확정 (구현 전)
선행: [2026-05-18-tmux-agent-team-design.md](2026-05-18-tmux-agent-team-design.md) (1차 토대, main 머지 완료)

## 1. 목적

1차 토대(tmux 멀티 에이전트 팀: 통신·식별·동기화·생명주기)가 main에 머지된 상태에서, 그 위에 다음을 올린다:

1. **판단형 디스패처 메인** — 사용자 자연어 명령을 받아 스스로 작업을 분해하고, 고정 워커 풀 안에서 적합한 워커에 scope와 함께 분배
2. **준실시간 감시 리뷰어** — 워커가 올바른 방향으로 가는지(scope 준수, 안티패턴, 계획 준수) 감시. 약한 신호(진행 중 통지)로 사전 차단, 강한 신호(완료)로 결과 검사
3. **기능별 모델 차등** — 작업 성격에 맞춰 opus/sonnet/haiku 배분
4. **codex 연동 확장점** — 본격 구현은 후속이나 워커 계약을 명문화해 막지 않음

핵심 철학(1차 계승): **세션은 일회용, git 정의가 유일한 진실 공급원.** 작업 성격별 프로파일을 미리 만들어두고, 시작 시 선택해 `team-up.sh`가 동일한 팀을 재생성한다. 런타임 편성 변경 없음.

## 2. 전제 / 환경

- 위치: `~/Desktop/Repo/Practice/tmux-agent-team/` — 독립 git repo, main 브랜치 (1차 머지 완료)
- 1차 토대 자산 전부 재사용: `bin/lib.sh`, `bin/team-up.sh`, `bin/dispatch.sh`, `bin/wait-worker.sh`, `bin/team-down.sh`, `profiles/*.sh`, `prompts/`
- tmux 함정 3종(인덱스/title/layout)은 1차 토대에서 세션 로컬 옵션으로 해소됨 — review 윈도우에도 동일 적용 필요
- claude CLI 상주 모드. `AGENT_CMD` 오버라이드 구조 기존 존재 (테스트는 `cat`/dummy)

## 3. 아키텍처 (A안: 단일 통제점 + 리뷰 윈도우)

세 가지 통제 구조를 비교해 A안을 채택한다.

- **A. 메인 단일 오케스트레이터 + 리뷰 윈도우 (채택)** — 메인 claude가 디스패치·시그널 수신·리뷰 종합·재지시 독점. 리뷰어는 검사·보고만. 권한 분리 명확, 1차 토대 재사용, 디버그 용이.
- **B. 메인 + 독립 감시 데몬 (기각)** — 셸 데몬은 안티패턴 의미 판정 불가(경로 매칭만). 의미 검토하려면 결국 claude 리뷰어 필요 → 구조 중복.
- **C. 계층형 (기각)** — 현 규모(워커 3~5, 리뷰어 2~4)엔 과설계. YAGNI 위반.

### 3.1 tmux 레이아웃

1차 토대는 단일 윈도우였다. 하네스는 **window 1 (review)을 추가**한다 — 이것이 핵심 구조 변경.

```
tmux 세션: agents
├─ window 0: "team"  (작업 윈도우)
│   ├─ pane: orchestrator   ← 메인 claude (판단형 디스패처)
│   ├─ pane: dev            ← 워커 claude
│   ├─ pane: arch           ← 워커 claude
│   └─ pane: test           ← 워커 claude
│
└─ window 1: "review"  (리뷰 전담 윈도우)
    ├─ pane: spec-rev       ← 리뷰어 claude (스펙·계획 준수 관점)
    ├─ pane: quality-rev    ← 리뷰어 claude (코드 품질·안티패턴 관점)
    └─ pane: arch-rev       ← 리뷰어 claude (아키텍처 일관성 관점)
```

리뷰어 구체 라인업(spec/quality/arch)은 **예시**다. 확정된 것은 메커니즘이다: 리뷰어는 관점별로 분화하고, 편성은 프로파일이 결정하며, 리뷰어는 감시·보고만 한다. 라인업·개수·관점은 작업 성격별 프로파일이 정한다.

### 3.2 워커 편성 — 프로파일 기반 고정

런타임 동적 spawn은 하지 않는다. 작업 성격별 프로파일을 다수 준비하고 시작 시 선택한다.

```
사용자: 작업 성격 판단 → 프로파일 선택
        ↓
bin/team-up.sh profiles/<선택>.sh   ← 프로파일이 워커+리뷰어+모델 편성 결정
        ↓
세션 생성 (워커·리뷰어 pane 고정, 런타임 변경 없음)
        ↓
메인은 이 고정 풀 안에서 "할당"만 판단 (편성 판단 아님)
```

**근거**: (1) git 정의 단일 진실 철학 유지, (2) 런타임 split-window의 tmux 함정(index 재배열·title 덮어쓰기·layout) 회피, (3) 리뷰어 매핑·scope 단순화. "명령 도중 워커 추가 불가"는 의도된 제약.

### 3.3 통제 흐름 (1사이클)

```
[1] 사용자 ──자연어──> orchestrator pane

[2] 메인 claude 판단:
    - 작업 분해
    - 워커별 scope 결정 (allowed/forbidden paths)
    - workspace/tasks/<id>.md 작성
    - bin/dispatch.sh <worker> <id> 호출  ← 1차 스크립트를 도구로

[3] 워커 작업 중:
    - 파일 변경마다 workspace/events.log 한 줄 append
    - 완료 시 tmux wait-for -S done-<worker>-<id> + events.log done 라인

[4] 리뷰어 (window 1, 상시 가동):
    - events.log tail
    - 약한 신호: scope 위반 라인 즉시 감지 → review 파일 (사전 차단, 디바운스 예외)
    - 강한 신호: done 후 결과물 결정적 검사 → review 파일

[5] 메인:
    - bin/wait-worker.sh 로 done 수신 (+ events.log done 폴링 안전장치)
    - review/<worker>-<id>.*.md 종합
    - 판단: 통과 → 다음 / VIOLATION → 워커 재지시 or 사용자 보고
```

### 3.4 1차 토대 재사용 vs 신규

| 요소 | 상태 |
|---|---|
| `lib.sh`, `team-up.sh`, `dispatch.sh`, `wait-worker.sh`, `team-down.sh` | 재사용 (메인의 도구) |
| 단일 윈도우 → 2윈도우 (team+review) | 확장 (team-up.sh) |
| `events.log` append 관례 | 신규 |
| 리뷰어 상시 tail 루프 | 신규 |
| task 파일 scope 헤더 | 신규 (tasks/ 관례 확장) |
| 메인 자연어 판단 | 신규 (프롬프트, 스크립트 아님) |

## 4. 컴포넌트·역할

세 컴포넌트는 파일(events.log/tasks/results/review) + tmux 시그널로만 결합한다 (느슨한 결합).

### 4.1 메인 (orchestrator pane)

- **책임**: 자연어 수신 → 작업 분해 → scope 결정 → task 파일 작성 → 디스패치 → done 수신 → 리뷰 종합 → 통과/재지시/사용자보고 판단. 위반 시 워커 개입(send-keys)은 메인 독점.
- **입력**: 사용자 자연어 (orchestrator pane stdin)
- **출력/도구**: `tasks/<id>.md` 작성, `dispatch.sh`/`wait-worker.sh` 호출, `review/*.md` 읽기, 위반 시 워커 pane에 send-keys
- **역할 프롬프트**: `prompts/roles/orchestrator.md` (신규)

### 4.2 워커 (team 윈도우 pane)

- **책임**: task 파일을 읽고 자기 scope 안에서 작업, 파일 변경 시 events.log 통지, 완료 시 시그널+로그
- **입력**: `dispatch.sh`가 주입하는 `TASK <id>` → `tasks/<id>.md` 읽기
- **출력**: events.log append, `results/<id>.md`, `tmux wait-for -S done-<worker>-<id>`
- **역할 프롬프트**: `prompts/roles/{dev,tester,researcher,security}.md` (기존 확장: events.log append 규칙 + scope 밖 수정 금지), `prompts/_common.md` (events.log 규약 1줄 추가)

### 4.3 리뷰어 (review 윈도우 pane)

- **책임**: events.log 상시 tail → 약한 신호(scope 위반 즉시) → 강한 신호(done 후 결과 검사) → 위반을 review 파일에 기록. **워커 조종 안 함.**
- **입력**: `events.log` (tail), `tasks/<id>.md` (scope 확인), `results/<id>.md` (결정적 검사)
- **출력**: `review/<worker>-<id>.<reviewer>.md` 에만 기록 (메인만 읽음)
- **역할 프롬프트**: `prompts/roles/reviewer-{spec,quality,arch}.md` (신규, 1차 reviewer.md 분화 — 라인업은 프로파일별 디테일)

## 5. 데이터 흐름

### 5.1 task 파일 — `workspace/tasks/<id>.md`

생산자: 메인 / 소비자: 워커(작업 지시), 리뷰어(scope 확인)

```markdown
---
id: 101
worker: dev
allowed_paths:
  - src/auth/**
  - tests/auth/**
forbidden_paths:
  - src/payment/**
---

## 작업
auth 로그인 핸들러 구현. JWT 검증 포함.

## 완료 기준
- tests/auth/login.test.ts 통과
- results/101.md 에 변경 요약
```

`allowed_paths`/`forbidden_paths` = scope. glob 패턴. 1차 tasks/ 관례를 헤더로 확장.

### 5.2 이벤트 로그 — `workspace/events.log` (단일 append-only)

생산자: 모든 워커 / 소비자: 모든 리뷰어 (tail)

탭 구분 5필드 1줄 = 1이벤트 (1차 `IFS=$'\t'` 파싱 관례 재사용):

```
<ISO타임스탬프>\t<worker>\t<task_id>\t<action>\t<path>
```

```
2026-05-19T10:00:01Z	dev	101	modify	src/auth/login.ts
2026-05-19T10:00:03Z	dev	101	modify	src/payment/charge.ts
2026-05-19T10:00:05Z	dev	101	done	-
```

- `action`: `write` | `modify` | `delete` | `done`
- append는 워커가 `>>` (한 줄이 PIPE_BUF 이하라 동시 append 원자적; 경로는 repo 상대경로로 기록해 길이 억제)
- `done` 라인은 시그널 유실 대비 안전장치 (5.5)

### 5.3 tmux 시그널 (wait-for) — 1차 그대로

생산자: 워커 / 소비자: 메인. `tmux wait-for -S done-<worker>-<id>`. 메인은 `bin/wait-worker.sh`로 블로킹 수신(1차 timeout 폴백 포함).

### 5.4 리뷰 보고 — `workspace/review/<worker>-<id>.<reviewer>.md`

생산자: 리뷰어 / 소비자: 메인 (워커는 안 읽음)

```markdown
---
worker: dev
task_id: 101
reviewer: quality-rev
verdict: VIOLATION
severity: high
signal: weak
---

## 위반
10:00:03 — dev가 src/payment/charge.ts modify.
task 101 forbidden_paths(src/payment/**) 위반.

## 권고
즉시 중단, payment 변경 롤백.
```

- `verdict`: `OK` | `VIOLATION`
- `signal`: `weak`(scope 위반·진행 중) | `strong`(done 후 결과 검사)
- `severity`: `low` | `high` — 메인 판단 근거
- 파일명에 `<reviewer>` 포함 → 리뷰어 3명이 같은 worker-id에 써도 덮어쓰기 없음

### 5.5 디바운스 (병렬 부하 흡수)

리뷰어는 events.log를 읽되 메모리에서 `(worker, path)` → 최신 라인만 유지:
- 같은 (dev, src/auth/login.ts) 4번 → 1개로 접음 (헛검사 방지)
- **scope 위반 라인은 디바운스 예외** — `forbidden_paths` 매치 즉시 review 기록 (사전 차단)

확정 검사 트리거는 워커의 `done` 시그널. 병렬 워커가 N개여도 리뷰어는 각 워커 done 시 1회 검사 — 리소스가 워커 수에 비례 폭발하지 않음.

## 6. 에러·엣지 처리

| 케이스 | 감지 | 대응 | 자동/사용자 |
|---|---|---|---|
| 워커 무응답 | wait-worker timeout (1차 기능) | capture-pane 덤프 → 연장 or 보고 | 사용자 |
| 시그널 유실 | events.log done 라인 폴링 | 로그로 완료 확정 (멱등) | 자동 |
| 리뷰어 다운 | done 후 review 파일 미생성 | 보고, **자동 통과 안 함** | 사용자 |
| 로그 파손 | 필드 수 ≠ 5 | 해당 줄 skip + 경고 | 자동 |
| scope 위반(high) | forbidden 매치 | **메인이** send-keys로 중단 주입 | 자동 |
| scope 위반(low) | forbidden 매치 | 기록, done 후 종합 | 자동 |
| task 분해 오류 | spec 리뷰어 이의 | 메인 재검토, **재지시 2회 초과 시 사용자 에스컬레이션** | 사용자 |

핵심 결정:
- **리뷰어 다운 시 자동 통과 금지** — 리뷰어는 best-effort가 아니라 게이트. 감시 누락은 사용자 판단.
- **위반 중단 주입은 메인만** — 리뷰어는 review 파일 기록까지만. 통제권 단일화([[subagent-blocked-means-verify]] 원칙: 개입은 검증된 단일 주체).
- **재지시 2회 초과 시 사용자 에스컬레이션 강제** — 메인↔리뷰어 무한 핑퐁 방지.
- **로그 무한 증가**: 세션 일회용이라 `team-down.sh`가 events.log 삭제. 롤오버는 YAGNI(초기 미구현, 단일 로그).
- **시그널 유실**: 메인은 wait-for 대기와 병행으로 events.log done 라인 폴링. 둘 중 먼저 충족 시 완료, 중복 처리 안 함(멱등).

메인이 scope 위반(high)에 진행 중 개입하려면, done 대기와 별개로 디스패치 후 `review/` 디렉터리의 새 VIOLATION 파일을 주기 폴링하는 루프가 필요하다.

## 7. 모델 차등·codex 확장점

### 7.1 기능별 모델 차등

1차 `AGENT_CMD` 오버라이드를 에이전트별로 분화. 프로파일 포맷을 `pane:역할` 2분할에서 `pane:역할:모델` 3분할로 확장:

```sh
# profiles/feature-team.sh
SESSION="agents"
LAYOUT="tiled"
WORKERS=("dev:dev:opus" "test:tester:haiku" "arch:researcher:sonnet")
REVIEWERS=("spec-rev:spec:sonnet" "quality-rev:quality:haiku" "arch-rev:arch:opus")
ORCHESTRATOR_MODEL="opus"
```

- 포맷: `<pane명>:<역할>:<모델>`. 모델 생략 시 기본값 `sonnet`.
- `team-up.sh`: pane별 부트스트랩 시 `claude --model "$model"` 주입. `AGENT_CMD`가 이미 pane별 주입 가능 → 포맷 파싱 + `--model` 추가만으로 됨.
- 비용 원칙: 판단·아키텍처·종합 → opus(메인, arch 리뷰어) / 통합·패턴매칭 → sonnet(구현 워커, spec 리뷰어) / 기계적·경량 → haiku(테스트 작성, 단순 품질).

### 7.2 codex 확장점

tmux pane은 프로세스 무관. 결합은 파일+시그널 규약뿐. codex 워커가 충족할 **계약 4가지**:

| 계약 | claude 워커 | codex 워커 |
|---|---|---|
| task 입력 | `tasks/<id>.md` 읽기 | 동일 |
| 변경 통지 | `events.log` 5필드 append | 동일 포맷 |
| 완료 시그널 | `tmux wait-for -S done-<w>-<id>` | 동일 명령 |
| 산출 | `results/<id>.md` | 동일 경로 |

이번 범위: codex 본격 구현 **안 함**(YAGNI). 단 (1) 워커 계약 4가지 명문화, (2) `team-up.sh`의 엔진 분기점을 `AGENT_CMD` 파싱 한 곳으로 격리 — codex 추가가 국소 변경이 되도록 보장.

## 8. 테스트 전략

1차 의존성 제로 셸 하네스(`tests/assert.sh`, `run-all.sh`) 확장. **claude를 띄우지 않고**(`AGENT_CMD`=`cat`/dummy) 메커니즘만 검증. 1차 8스위트(64 어서션)는 회귀로 유지.

| 스위트 | 검증 대상 |
|---|---|
| 기존 8개 | 1차 토대 (회귀 유지) |
| `test-events-log.sh` | 5필드 파싱, 파손 라인 skip, 동시 append 무손상 |
| `test-scope.sh` | allowed/forbidden glob 매칭, 경계 오매치 방지 |
| `test-debounce.sh` | (worker,path) 접힘, forbidden 디바운스 예외, 다른 worker 별개 |
| `test-review-flow.sh` | 리뷰어 3 파일 덮어쓰기 없음, severity=high → 중단 종합, 전 OK → 통과 |
| `test-signal-fallback.sh` | wait-for 선발화 시 done 라인 폴링 완료, 중복 멱등 |
| `test-team-up-harness.sh` | 2윈도우 생성, `pane:역할:모델` 파싱, 모델 생략 기본값, review 윈도우 함정 회귀(base-index/allow-set-title/pane_id) |
| `test-profiles-harness.sh` | 확장 프로파일 형식 검증, 잘못된 포맷 명확 에러 |
| `test-e2e-harness.sh` | dummy로 디스패치→통지→감시→보고→종합 전 경로 + team-down 정리(results 보존) |

`run-all.sh`에 신규 스위트 등록. 전부 의존성 제로, claude 미기동.

## 9. 신규/확장 파일 요약

| 파일 | 신규/확장 |
|---|---|
| `prompts/roles/orchestrator.md` | 신규 |
| `prompts/roles/reviewer-{spec,quality,arch}.md` | 신규 (reviewer.md 분화, 라인업은 프로파일별) |
| `prompts/roles/{dev,tester,researcher,security}.md` | 확장 (events.log·scope 규칙) |
| `prompts/_common.md` | 확장 (events.log append 규약 1줄) |
| `profiles/*.sh` | 확장 (`REVIEWERS=(...)`, `pane:역할:모델`, `ORCHESTRATOR_MODEL`) |
| `bin/team-up.sh` | 확장 (review 윈도우 생성, 모델 파싱·`--model` 주입, 엔진 분기점 격리) |
| `bin/lib.sh` | 확장 (scope glob 매칭, events.log 파싱 헬퍼, review 윈도우 함정 적용 함수) |
| `tests/test-*.sh` (8 신규) | 신규 |

## 10. 범위 밖 (YAGNI)

- codex 본격 구현 (계약 명문화 + 분기점 격리만)
- events.log 롤오버 (단일 로그 유지)
- 동적 워커 spawn (프로파일 고정 편성)
- 계층형 디스패처 (단일 통제점)
