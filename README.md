# tmux 멀티 에이전트 팀

tmux 페인마다 Claude Code 인스턴스를 띄우고 역할/제약을 부여해, 1 오케스트레이터 + N 워커 멀티 에이전트 팀을 운영한다.

## 전제

- tmux 3.6+ (`send-keys -l`, `wait-for`, `capture-pane` 사용)
- `claude` CLI 설치 및 PATH 등록
- prefix는 tmux 기본값(C-b) 가정. `~/.tmux.conf`는 이 repo가 수정하지 않음.
- 사용자 전역 tmux 의 base-index/pane-base-index 설정과 무관하게 동작 (team-up 이 세션 로컬로 인덱스·title 옵션을 고정).

## 철학

세션은 일회용. git 으로 버전 관리되는 `profiles/` + `prompts/` 정의로부터 `team-up.sh` 가 매번 동일한 팀을 재생성한다. 세션 상태를 저장/복원하지 않는다.

## 사용법

```bash
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
```

## 프로파일

`profiles/*.sh` 로 팀 구성을 정의. `bin/team-up.sh <프로파일명>` 으로 선택.

- `default` — 워커: dev / test, 리뷰어: quality-rev
- `code-review` — 워커: security, 리뷰어: spec-rev / quality-rev / arch-rev
- `research` — 워커: researcher×3, 리뷰어: quality-rev
- `feature-team` — 워커: dev / test / arch, 리뷰어: spec-rev / quality-rev / arch-rev (모델 차등)

새 팀: `profiles/<name>.sh` 추가 (`SESSION`, `LAYOUT`, `WORKERS=("이름:역할[:모델]" ...)`, 선택 `REVIEWERS=(...)`, `ORCHESTRATOR_MODEL`), 필요 시 `prompts/roles/<역할>.md` 추가. `bin/` 은 수정 불필요.

## 통신 메커니즘

- 명령 주입: `tmux send-keys -l` (텍스트/Enter 분리)
- 완료 동기화: `tmux wait-for` (폴링 없는 블로킹, race-safe)
- 결과 전달: `workspace/results/<id>.md` 파일
- 디버그: `tmux capture-pane -p`
- 워커 식별: pane title=워커명 (team-up 이 split-window -P 의 pane_id 로 정확히 설정하고 `allow-set-title off` 로 셸 escape 로부터 보존)

## 테스트

```bash
bash tests/run-all.sh
```

외부 의존성 없음. 실제 tmux 세션을 띄우되 워커 명령을 `AGENT_CMD` 환경변수로 더미 치환해 검증한다.

## 디렉토리

- `bin/` — 고정 로직 (수정 거의 불필요)
- `profiles/` — 팀 구성 정의 (커스텀 지점)
- `prompts/` — 워커 규약 (커스텀 지점)
- `workspace/` — 런타임 산출물 (git 제외)
- `docs/` — 로컬 설계/계획 문서 (.gitignore, git 추적 안 함)

## 에이전트 하네스 (2차)

판단형 메인(프로젝트 관리자) + `/loop`·Monitor 상주 감시 리뷰어 + scope 사전차단 + 모델 차등.

- 가동: `bin/team-up.sh feature-team` (워커 + review 윈도우 + 모델 차등)
- 초회 가동 시 claude 가 폴더 신뢰를 1회 묻습니다 — team-up 이 자동 통과하나, 응답이 없으면 각 pane 에서 수동 Enter(트러스트 확인) 필요할 수 있습니다.
- 메인은 단계 자동 전이 안 함 — 사용자가 PRD→Arch→구현 단계를 수동 진행
- 감시: 약한 신호(scope, 즉시) / 강한 신호(done 후 의미 판정)
- 설계: `docs/superpowers/specs/2026-05-19-agent-harness-design.md`
- 실측 프로브(claude 기동): `tests/probes/probe-{loop,hook}.sh` (수동)
