# 에이전트 하네스 — 설계 문서

작성일: 2026-05-19
개정: v3 — 방향성 리뷰 반영 (메인=프로젝트 관리자 책임 9개, 약한신호=scope 한정, codex 워커 한정 등)
상태: 설계 확정 (구현 전)
선행: [2026-05-18-tmux-agent-team-design.md](2026-05-18-tmux-agent-team-design.md) (1차 토대, main 머지 완료)

**검증 이력**:
- **v2** (구현 리뷰): 8개 이슈 발견. 핵심 미검증 가정 "리뷰어 상시 감시"를 tmux pane 실측 프로브로 검증 — `/loop` dynamic + claude 자율 `Monitor` 무장이 셸 watcher 없이 이벤트 구동 감시를 네이티브 수행함 확인(PASS).
- **v3** (방향성 리뷰): 사용자 원래 구상과 정합화. (A) 약한 신호 = scope 차단만, 의미 판정은 강한 신호(done 후)로 일원화 — 미완성 코드의 의미 판단은 거짓 양성/음성 불가피하므로. (B) 메인 = 단순 분배자 아닌 **프로젝트 관리자**(책임 9개: 분담·완료수신·리뷰종합·개입·산출물연결·보고·진도추적·품질게이트·전체맥락유지), 단계 전이는 사용자 통제, 맥락은 `.harness-state` 파일 보존. (C) codex=워커 한정·리뷰어=claude 전용. (E·F) 디바운스 claude 무상태 정합·done 라인 주체 명확화.

## 1. 목적

1차 토대(tmux 멀티 에이전트 팀: 통신·식별·동기화·생명주기)가 main에 머지된 상태에서, 그 위에 다음을 올린다:

1. **판단형 메인 = 프로젝트 관리자** — 사용자 자연어 명령을 받아 작업 분해·워커 매칭·scope 결정을 판단하는 데 그치지 않고, 진도 추적·품질 게이트·전체 맥락 유지까지 관장한다(책임 9개, §4.1). 단계 전이는 사용자가 통제하며 메인은 자동 전이하지 않는다.
2. **준실시간 감시 리뷰어** — 워커가 **올바른 방향으로 가는지** 감시. 두 신호로 역할을 분리한다:
   - **약한 신호(진행 중) = scope 차단만**: events.log 라인은 "어느 파일을 건드렸나"만 알려주므로 *기계적으로 확실한* scope(허용/금지 경로) 위반만 즉시 잡아 사전 차단한다. 진행 중 파일은 미완성 상태라 내용 기반 의미 판단은 거짓 양성/음성을 피할 수 없어 **약한 신호에서 의미 검토를 하지 않는다**(노이즈 배제 — 설계 결정).
   - **강한 신호(완료) = 의미 판정**: 워커 `done` 후 완성된 산출물을 리뷰어 claude가 읽어 task 의도 위배(예: JWT 검증을 평문 비교로 구현), 안티패턴, 계획 위배를 판정한다. 의미적 이탈을 *확실하게* 잡는 곳은 여기다 — 리뷰어가 claude인 본질적 이유.
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
      (자기보고 아님 — PostToolUse hook이 결정적으로 기록, §5.6)
    - 완료 시 tmux wait-for -S done-<worker>-<id> + events.log done 라인

[4] 리뷰어 (window 1, /loop dynamic 모드로 상주):
    - 기동 시 send-keys 로 /loop 프롬프트 주입 → claude 가 events.log 에
      Monitor(persistent) 자율 무장 + fallback heartbeat 자동 설정
    - events.log append 발생 → Monitor 발화 → claude 깨어남
    - .review-cursor 로 증분·멱등 처리 (마지막 검토 오프셋 보존)
    - 약한 신호: scope(경로) 위반만 즉시 → review 파일 (기계적·확실, 사전 차단)
    - 강한 신호: done 라인 → 완성 산출물 의미 판정(의도/안티패턴/계획) → review 파일

[5] 메인 (orchestrator pane, /loop dynamic 모드로 상주):
    - bin/wait-worker.sh 로 done 수신 (+ events.log done 폴링 안전장치)
    - /loop 으로 review/ 디렉터리에 Monitor 무장 → 새 VIOLATION 파일 발화
    - review/<worker>-<id>.*.md 종합
    - 판단: 통과 → 다음 / VIOLATION → 워커 재지시 or 사용자 보고
```

**감시 메커니즘 (실측 검증됨)**: 리뷰어·메인 모두 단발 응답 모델이라 자체 무한 루프 불가. 이를 Claude Code 네이티브 기능으로 해결한다 — pane 기동 시 `send-keys`로 `/loop <감시 프롬프트>`(인터벌 생략 → dynamic 모드)를 주입하면, claude가 스스로 (a) 대상 파일에 `Monitor`(persistent, append 즉시 발화)를 무장하고 (b) ~25분 fallback heartbeat를 설정한다. 외부 셸 watcher 프로세스가 **불필요**함을 tmux pane 실측 프로브로 확인했다. claude 무상태성은 커서 파일(`.review-cursor`)로 보완 — 증분·멱등.

### 3.4 1차 토대 재사용 vs 신규

| 요소 | 상태 |
|---|---|
| `lib.sh`, `team-up.sh`, `dispatch.sh`, `wait-worker.sh`, `team-down.sh` | **재사용 + 확장** (window 1 지원·SESSION 일치·헬퍼 추가, §9) |
| 단일 윈도우 → 2윈도우 (team+review) | 확장 (team-up.sh) |
| `events.log` append (PostToolUse hook 결정적 기록) | 신규 |
| 리뷰어 `/loop`+Monitor 상주 감시 | 신규 (실측 검증됨) |
| task 파일 scope 헤더 + glob 매칭 | 신규 (tasks/ 관례 확장) |
| 메인 자연어 판단 + `/loop` 상주 | 신규 (프롬프트, 스크립트 아님) |

## 4. 컴포넌트·역할

세 컴포넌트는 파일(events.log/tasks/results/review) + tmux 시그널로만 결합한다 (느슨한 결합).

### 4.1 메인 (orchestrator pane) — 프로젝트 관리자

메인은 **단순 분배자가 아니라 프로젝트 관리자**다. 단발 명령을 워커에 던지는 게 아니라, 세션 전체의 진행·맥락·품질을 관리한다. 책임 9개:

| # | 책임 | 구체 행동 |
|---|---|---|
| 1 | 업무 분담 | 명령 분해 → 워커 카탈로그 보고 매칭 → scope 결정 → `tasks/<id>.md` 작성 → `dispatch.sh` 호출 |
| 2 | 완료 수신 | `wait-worker.sh`로 done 대기 + events.log done 라인 확인 |
| 3 | 리뷰 종합 | `review/*.md` 읽고 OK/VIOLATION·severity 종합 판단 |
| 4 | 개입 결정 | 위반 시 워커 pane에 send-keys로 중단/수정 주입·재지시 (**메인 독점**) |
| 5 | 산출물 연결 | 사용자가 "이 PRD로 Architecture" 지시 시, 이전 산출물(`results/`·`docs/`)을 다음 task 입력으로 명시 |
| 6 | 사용자 보고 | 진행·결과·에스컬레이션을 사용자에게 종합 보고 |
| 7 | 진도 추적 | 여러 task가 떠 있을 때 진행/완료/대기 상태 관리, 사용자 조회 시 현황 보고 |
| 8 | 품질 게이트 | 리뷰 미통과 산출물을 다음 단계 입력으로 쓰려는 명령 시 "이전 단계 미통과" 경고·사용자 확인 요구 (강제 차단 아님 — 사용자 판단 존중) |
| 9 | 전체 맥락 유지 | PRD→Arch→구현 단계의 결정·산출물 맥락을 세션 내내 보존, 뒤 단계에서 앞 단계 결정 참조 |

- **입력**: 사용자 자연어 (orchestrator pane stdin) + `/loop`이 무장한 `review/` Monitor 발화
- **출력/도구**: `tasks/<id>.md` 작성, `dispatch.sh`/`wait-worker.sh` 호출, `review/*.md` 읽기, 위반 시 워커 pane에 send-keys, `.harness-state` 갱신
- **워커 카탈로그**: 메인은 자기 팀을 알아야 매칭할 수 있다. `team-up.sh`가 기동 시 프로파일 `WORKERS` 목록 + 각 역할(`prompts/roles/<역할>.md`)의 한 줄 요약을 `orchestrator.md`에 주입한다(신규 만드는 게 아니라 기존 정의를 메인에게 보여주는 것).
- **단계 전이는 사용자 통제**: 메인은 단계를 **자동 전이하지 않는다**. "PRD 다 됐으니 이제 구현 시작" 같은 판단 금지 — 산출물 보고 후 사용자의 다음 명령을 대기한다. 단계 순서·전이 결정은 전적으로 사용자.
- **맥락 보존 = `.harness-state` 파일**: claude는 무상태이므로 진도·단계 결정·맥락을 컨텍스트가 아닌 `workspace/.harness-state`(§5.8)에 기록·갱신한다(리뷰어 커서와 같은 패턴). `/loop` 깨어남 사이 맥락이 파일로 보존됨.
- **상주 방식**: 기동 시 `/loop`(dynamic) 주입 — 사용자 명령 처리와 `review/` 디렉터리 Monitor 감시(VIOLATION 파일 발화 시 개입 판단)를 한 루프에서. claude의 단발 모델을 `/loop`으로 상주화 (실측 검증됨, §3.3).
- **단일 통제점**: 메인을 디스패처/코디네이터로 분리하지 않는다. 책임 9의 "전체 맥락 유지"가 맥락을 한 곳에 둘 것을 요구하므로(분리 시 맥락이 두 pane에 쪼개짐), 통합 메인이 A안 단일 통제점 철학과 정합한다.
- **역할 프롬프트**: `prompts/roles/orchestrator.md` (신규 — 책임 9개 + 워커 카탈로그 + 단계 전이 금지 + `.harness-state` 규약)

### 4.2 워커 (team 윈도우 pane)

- **책임**: task 파일을 읽고 자기 scope 안에서 작업, 파일 변경 시 events.log 통지, 완료 시 시그널+로그
- **입력**: `dispatch.sh`가 주입하는 `TASK <id>` → `tasks/<id>.md` 읽기
- **출력**: events.log append, `results/<id>.md`, `tmux wait-for -S done-<worker>-<id>`
- **역할 프롬프트**: `prompts/roles/{dev,tester,researcher,security}.md` (기존 확장: events.log append 규칙 + scope 밖 수정 금지), `prompts/_common.md` (events.log 규약 1줄 추가)

### 4.3 리뷰어 (review 윈도우 pane)

- **책임**: events.log 변경 감시 → **약한 신호: scope 위반만 즉시 감지·기록**(기계적·확실, 의미 판단 안 함) → **강한 신호: done 후 완성 산출물의 의미 판정**(task 의도 위배·안티패턴·계획 위배) → 위반을 review 파일에 기록. **워커 조종 안 함.** (§1의 2신호 분리 원칙: 진행 중 미완성 코드의 의미 판단은 거짓 양성/음성 불가피하므로 약한 신호에서 하지 않음)
- **입력**: `events.log` (Monitor 발화로 깨어나 `.review-cursor` 오프셋부터 증분 read — scope 매칭용 경로만), `tasks/<id>.md` (scope·완료기준 확인), `results/<id>.md` (done 후 결정적 의미 검사)
- **출력**: `review/<worker>-<id>.<reviewer>.md` 에만 기록 (메인만 읽음), `.review-cursor.<reviewer>` 갱신
- **상주 방식**: 기동 시 `/loop`(dynamic) 주입 → claude가 `events.log`에 Monitor(persistent) 자율 무장 + fallback heartbeat. append 발생 시 깨어나 커서 이후만 검토 (실측 검증됨, §3.3). 리뷰어마다 독립 커서 파일 → 리뷰어 간 진행 간섭 없음.
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

**glob 매칭 구현 수단** (이슈 8): bash `[[ $p == $pat ]]`는 `**` 재귀 글롭을 `==`에서 지원하지 않는다. `bash -O globstar`도 `==` 매칭엔 무효. 따라서 scope 매칭은 **case 문 + `*` 변환** 방식으로 구현한다: 패턴의 `**`를 `*`로 치환 후 `case "$path" in $pat) ... esac`. 정밀 재귀 의미가 필요하면 패턴을 정규식으로 변환(`**` → `.*`, `*` → `[^/]*`)해 `[[ $path =~ $re ]]`로 매칭. `lib.sh`에 `scope_match()` 헬퍼로 격리하고 `test-scope.sh`가 경계 케이스(`src/auth` vs `src/authx/y` 오매치 방지)를 검증한다.

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
- **기록 주체 구분 (F)**: `write`/`modify`/`delete`(파일 변경)는 **PostToolUse hook이 결정적 기록**(§5.6, 자기보고 탈피). `done`은 도구 사용이 아니라 워커의 "작업 끝" 선언이므로 hook으로 못 잡는다 → **워커가 명시적으로 기록**(완료 시그널 `tmux wait-for -S done-<w>-<id>`와 쌍). "자기보고 탈피" 원칙은 파일 변경 기록에만 적용되며, `done`은 시그널과 이중화되어 한쪽 누락 시 다른 쪽으로 복원되므로 자기보고여도 안전.
- append는 `>>` (한 줄이 PIPE_BUF 이하라 동시 append 원자적; 경로는 repo 상대경로로 기록해 길이 억제)
- `done` 라인은 시그널 유실 대비 안전장치 (§5.5, §6 시그널 유실 행)

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

수정 A로 약한 신호는 **scope 매칭만** 한다(파일 내용 검토 없음). 따라서 디바운스는 "내용 검사 헛수고 방지"가 아니라 "scope 매칭·기록 중복 방지"로 단순해진다.

- **claude 무상태 정합 (E)**: 리뷰어는 무상태이므로 디바운스 상태를 메모리에 유지할 수 없다(`/loop` 깨어남 사이 소실). 디바운스는 **Monitor 1회 깨어남의 처리 범위(`.review-cursor`~EOF) 내에서만** 적용 — 그 범위 안에 같은 `(worker, path)`가 여러 번이면 1회만 scope 판정. 범위를 넘는 상태는 커서로만 관리.
- **scope 위반은 디바운스 무관 즉시 기록** — `forbidden_paths`/`allowed_paths` 밖 매치는 처리 범위 내 첫 발견 즉시 review 기록(사전 차단). 같은 위반 경로 반복은 1회만 기록(중복 보고 방지).

강한 신호(의미 판정)의 확정 트리거는 워커 `done`. 병렬 워커 N개여도 리뷰어는 각 워커 done 시 1회 의미 검사 — 리소스가 워커 수에 비례 폭발하지 않음.

### 5.6 events.log 결정적 기록 — PostToolUse hook (이슈 6)

워커 claude에게 "파일 수정 후 events.log에 append하라"를 프롬프트로만 지시하면 자기보고 누락 위험이 있다(감시 신뢰성 훼손). 따라서 append를 **claude 자기보고가 아닌 Claude Code의 PostToolUse hook으로 결정적으로 기록**한다.

- 워크스페이스에 `.claude/settings.json` (프로젝트 단위) — `Edit`/`Write`/`MultiEdit` 도구의 PostToolUse hook 정의
- hook 스크립트(`bin/log-event.sh`): hook이 넘기는 도구 입력에서 수정 파일 경로를 추출, repo 상대경로로 변환, `events.log`에 5필드 라인 append. 워커명은 hook 실행 컨텍스트(pane 환경변수 `HARNESS_WORKER`, team-up.sh가 주입)에서 얻음
- 워커 프롬프트의 events.log 규칙은 **보조**로만 유지(hook 미적용 도구나 수동 변경 대비), 주 경로는 hook

**미검증 가정 (구현 1번째 태스크에서 실측 필수)**: tmux pane에서 `send-keys`로 기동한 claude 인스턴스에 프로젝트 `.claude/settings.json`의 PostToolUse hook이 실제 적용되는지, hook에 워커 식별 컨텍스트를 전달할 수 있는지는 `/loop`처럼 직접 실측해야 한다([[subagent-blocked-means-verify]] 원칙). 실측 실패 시 폴백: 워커 프롬프트 규칙 + 리뷰어가 `done` 시 결과물 diff로 변경 파일 역추적(약한 신호 즉시성 일부 상실 감수).

### 5.7 리뷰 커서 — `workspace/.review-cursor.<reviewer>`

생산자/소비자: 각 리뷰어 자신. claude는 무상태이므로 "events.log를 어디까지 검토했는가"를 파일로 보존해야 멱등·증분이 성립한다(실측 프로브에서 이 메커니즘으로 1차 3줄+2차 2줄=5줄 정확·중복0 확인). 리뷰어마다 별도 커서 → 리뷰어 간 진행 간섭 없음. `team-down.sh`가 events.log와 함께 정리.

### 5.8 메인 상태 — `workspace/.harness-state` (B-4)

생산자/소비자: 메인 자신. 메인 책임 7(진도 추적)·9(전체 맥락 유지)는 `/loop` 깨어남을 가로질러 상태가 보존돼야 성립한다. claude 무상태이므로 컨텍스트가 아닌 파일에 기록(리뷰어 `.review-cursor`와 동일 패턴). 내용:

```
---
phase: architecture          # 현재 단계 (사용자가 통제, 메인은 기록만)
tasks:
  101: {worker: arch, status: done, review: OK}
  102: {worker: dev, status: in_progress, review: pending}
artifacts:
  prd: docs/prd/auth.md       # 단계별 산출물 경로 (산출물 연결용)
  architecture: docs/arch/auth.md
decisions:
  - "JWT 검증 방식 채택 (PRD §3 근거)"   # 뒤 단계에서 앞 단계 결정 참조
---
```

- `phase`는 메인이 **기록만** 한다 — 단계 전이 판단은 사용자(§4.1 단계 전이 사용자 통제). 사용자가 "이제 구현" 명령 시 메인이 `phase: implementation`으로 갱신.
- 메인은 매 명령 처리 전 `.harness-state`를 읽어 맥락 복원, 처리 후 갱신.
- `team-down.sh`가 events.log·커서와 함께 정리(세션 일회용 철학).

## 6. 에러·엣지 처리

| 케이스 | 감지 | 대응 | 자동/사용자 |
|---|---|---|---|
| 워커 무응답 | wait-worker timeout (1차 기능) | capture-pane 덤프 → 연장 or 보고 | 사용자 |
| 시그널 유실 | events.log done 라인 폴링 | 로그로 완료 확정 (멱등) | 자동 |
| 리뷰어 다운 | done 후 review 파일 미생성 | 보고, **자동 통과 안 함** | 사용자 |
| 리뷰어 `/loop` 정지 | review 파일 미생성 + Monitor 무발화 | 메인이 capture-pane 확인 → 보고 (fallback heartbeat이 1차 방어) | 사용자 |
| 로그 파손 | 필드 수 ≠ 5 | 해당 줄 skip + 경고 | 자동 |
| scope 위반(high) | forbidden 매치 | **메인이** send-keys로 중단 주입 | 자동 |
| scope 위반(low) | forbidden 매치 | 기록, done 후 종합 | 자동 |
| task 분해 오류 | spec 리뷰어 이의 | 메인 재검토, **재지시 2회 초과 시 사용자 에스컬레이션** | 사용자 |
| 미통과 산출물로 다음 단계 시도 | 사용자 명령 시 메인이 `.harness-state`에서 이전 단계 review≠OK 확인 | **경고 + 사용자 확인 요구**(강제 차단 아님 — 사용자 판단 존중, B-5) | 사용자 |
| 메인이 단계 자동 전이 시도 | (설계 금지 사항) | orchestrator.md가 자동 전이 금지·다음 명령 대기 규정 (B-3) | 사용자 |

핵심 결정:
- **리뷰어 다운 시 자동 통과 금지** — 리뷰어는 best-effort가 아니라 게이트. 감시 누락은 사용자 판단.
- **위반 중단 주입은 메인만** — 리뷰어는 review 파일 기록까지만. 통제권 단일화([[subagent-blocked-means-verify]] 원칙: 개입은 검증된 단일 주체).
- **재지시 2회 초과 시 사용자 에스컬레이션 강제** — 메인↔리뷰어 무한 핑퐁 방지.
- **로그 무한 증가**: 세션 일회용이라 `team-down.sh`가 events.log 삭제. 롤오버는 YAGNI(초기 미구현, 단일 로그).
- **시그널 유실**: 메인은 wait-for 대기와 병행으로 events.log done 라인 폴링. 둘 중 먼저 충족 시 완료, 중복 처리 안 함(멱등).
- **진행 중 개입 트리거**: 메인이 scope 위반(high)에 done 전 개입하는 경로는 메인 `/loop`의 `review/` Monitor가 담당 — 새 VIOLATION 파일 생성 즉시 메인 깨어남(폴링 루프 불필요, 실측된 Monitor 메커니즘 재사용).

### 6.1 2윈도우 도입으로 인한 1차 스크립트 수정 (이슈 1·2·3)

1차 스크립트는 단일 윈도우(window 0) 전제로 작성되어, review 윈도우(window 1) 도입 시 다음을 반드시 수정해야 한다(미수정 시 디스패치·조회 깨짐):

- **이슈 2 (SESSION 불일치)**: `dispatch.sh:7`은 `SESSION="${SESSION_OVERRIDE:-$SESSION_DEFAULT}"`인데 `team-up.sh:21`은 `${SESSION_OVERRIDE:-$SESSION}`(프로파일 SESSION). 프로파일이 SESSION을 바꾸면 불일치로 깨진다. → `lib.sh`에 SESSION 결정 로직을 단일 함수(`resolve_session`)로 통일하고 dispatch/wait-worker가 이를 호출. 작업 성격별 프로파일 다수가 전제이므로 필수.
- **이슈 1·3 (window 하드코딩)**: `dispatch.sh:37`의 `tmux list-panes -t "$SESSION:0"`과 `lib.sh:15` `target_of()`의 `%s:0.%s`는 window 0 고정. 메인이 리뷰어(window 1)에게 지시를 보내거나 pane을 조회할 수 없다. → `target_of()`를 `(window, pane)` 인자로 확장하거나 `target_by_title()`이 양 윈도우를 조회하도록 수정. dispatch.sh가 워커(window 0)·리뷰어(window 1) 양쪽 pane title을 조회하도록 확장.

이 수정들은 §9 파일 표에 명시하며, 구현 계획에서 team-up.sh의 review 윈도우 생성보다 먼저(또는 동시에) 처리한다.

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

**codex는 워커로만, 리뷰어는 claude 전용 (C)**: 위 계약 4가지는 워커 전용이다. 리뷰어 계약은 `/loop`(dynamic) + `Monitor` 자율 무장 + fallback heartbeat에 의존하는데(§3.3, 실측 검증된 Claude Code 네이티브 기능), codex에 동등 기능이 있는지는 알 수 없다. 따라서 **codex 에이전트는 워커로만 편입 가능하며, 리뷰어는 claude 전용**이다. codex 리뷰어 대안(예: 외부 셸 watcher가 codex를 깨우는 구조)은 명시적으로 범위 밖 — 필요 시 별도 설계.

이번 범위: codex 본격 구현 **안 함**(YAGNI). 단 (1) 워커 계약 4가지 명문화, (2) `team-up.sh`의 엔진 분기점을 `AGENT_CMD` 파싱 한 곳으로 격리 — codex 추가가 국소 변경이 되도록 보장, (3) codex=워커 한정·리뷰어=claude 전용 제약 명문화.

## 8. 테스트 전략

1차 의존성 제로 셸 하네스(`tests/assert.sh`, `run-all.sh`) 확장. **claude를 띄우지 않고**(`AGENT_CMD`=`cat`/dummy) 메커니즘만 검증. 1차 8스위트(64 어서션)는 회귀로 유지.

| 스위트 | 검증 대상 |
|---|---|
| 기존 8개 | 1차 토대 (회귀 유지) |
| `test-events-log.sh` | 5필드 파싱, 파손 라인 skip, 동시 append 무손상 |
| `test-scope.sh` | `scope_match()` glob 매칭, 경계 오매치 방지(`src/auth` vs `src/authx/y`), `**`/`*` 의미 |
| `test-debounce.sh` | (worker,path) 접힘, forbidden 디바운스 예외, 다른 worker 별개 |
| `test-cursor.sh` | `.review-cursor.<reviewer>` 증분·멱등, 리뷰어별 독립 커서 |
| `test-harness-state.sh` | `.harness-state` read/갱신 멱등, phase는 기록만(메인 자동전이 안 함), 산출물 경로 연결 |
| `test-review-flow.sh` | 리뷰어 3 파일 덮어쓰기 없음, severity=high → 중단 종합, 전 OK → 통과 |
| `test-signal-fallback.sh` | wait-for 선발화 시 done 라인 폴링 완료, 중복 멱등 |
| `test-session-resolve.sh` | `resolve_session()` 단일화 — dispatch/wait-worker/team-up SESSION 일치(이슈 2) |
| `test-target.sh` | `target_*()` window 0/1 양쪽 pane 조회(이슈 1·3), title 기반 워커·리뷰어 해석 |
| `test-team-up-harness.sh` | 2윈도우 생성, `pane:역할:모델` 파싱, 모델 생략 기본값, review 윈도우 함정 회귀(base-index/allow-set-title/pane_id) |
| `test-profiles-harness.sh` | 확장 프로파일 형식 검증, 잘못된 포맷 명확 에러 |
| `test-log-event.sh` | `bin/log-event.sh`: 도구 입력→5필드 라인 변환, repo 상대경로화, HARNESS_WORKER 식별 |
| `test-e2e-harness.sh` | dummy로 디스패치→통지→감시→보고→종합 전 경로 + team-down 정리(results 보존) |

`run-all.sh`에 신규 스위트 등록(총 12 신규). 위 스위트는 전부 의존성 제로·claude 미기동(메커니즘 검증).

### 8.1 실측 프로브 (구현 착수 전 필수 — claude 기동 필요)

메커니즘 테스트와 별개로, claude 실제 동작에 의존하는 두 가정은 구현 1번째 태스크에서 격리 프로브로 검증한다([[subagent-blocked-means-verify]] 원칙):

- **probe-loop**: tmux pane 내 대화형 claude에 `/loop` 주입 → Monitor 자율 무장 + events.log append 시 증분 처리 + fallback heartbeat. **이미 v2 작성 중 1차 실측 PASS** — 구현 시 재현·회귀 확인용으로 스크립트화(`tests/probes/probe-loop.sh`, run-all 비포함, 수동 실행).
- **probe-hook**: tmux pane 기동 claude에 프로젝트 `.claude/settings.json`의 PostToolUse hook이 적용되는지 + 워커 식별 컨텍스트 전달 가능한지. **미검증** — 실패 시 §5.6 폴백 발동.

## 9. 신규/확장 파일 요약

| 파일 | 신규/확장 |
|---|---|
| `prompts/roles/orchestrator.md` | 신규 (책임 9개 + 워커 카탈로그 + 단계 전이 금지 + `.harness-state` 규약 + `/loop` 상주·`review/` Monitor) |
| `prompts/roles/reviewer-{spec,quality,arch}.md` | 신규 (reviewer.md 분화 + `/loop` 상주·커서 규약, 라인업은 프로파일별) |
| `prompts/roles/{dev,tester,researcher,security}.md` | 확장 (events.log·scope 규칙, hook 보조) |
| `prompts/_common.md` | 확장 (events.log append 보조 규약 1줄) |
| `prompts/loop/{orchestrator,reviewer}.md` | 신규 (`/loop`에 주입할 dynamic 감시 프롬프트 본문) |
| `profiles/*.sh` | 확장 (`REVIEWERS=(...)`, `pane:역할:모델`, `ORCHESTRATOR_MODEL`) |
| `bin/team-up.sh` | 확장 (review 윈도우 생성, 모델 파싱·`--model` 주입, `/loop` 프롬프트 주입, `HARNESS_WORKER` env 주입, **워커 카탈로그를 orchestrator.md에 주입[B-2]**, 엔진 분기점 격리) |
| `bin/dispatch.sh` | **확장 (이슈 1·2)** — window 0/1 양쪽 pane title 조회, `resolve_session` 사용 |
| `bin/wait-worker.sh` | **확장 (이슈 2)** — `resolve_session` 사용으로 SESSION 일치 |
| `bin/lib.sh` | 확장 (`resolve_session`, `target_*` window 0/1 지원[이슈 1·3], `scope_match` glob[이슈 8], events.log 파싱 헬퍼, review 윈도우 함정 적용 함수) |
| `bin/log-event.sh` | **신규 (이슈 6)** — PostToolUse hook 스크립트, events.log 5필드 결정적 기록 |
| `workspace/.claude/settings.json` | 신규 (PostToolUse hook 정의 — Edit/Write/MultiEdit) |
| `workspace/.harness-state` | 신규 (B-4 — 메인 진도·맥락·단계 상태, 런타임 생성, team-down 정리) |
| `tests/test-harness-state.sh` | 신규 (B-4 — `.harness-state` read/갱신 멱등, phase 사용자통제 기록만) |
| `tests/test-*.sh` (12 신규) | 신규 |
| `tests/probes/probe-{loop,hook}.sh` | 신규 (claude 기동 실측, run-all 비포함·수동) |

## 10. 범위 밖 (YAGNI)

- codex 본격 구현 (계약 명문화 + 분기점 격리만)
- events.log 롤오버 (단일 로그 유지)
- 동적 워커 spawn (프로파일 고정 편성)
- 계층형 디스패처 (단일 통제점)
