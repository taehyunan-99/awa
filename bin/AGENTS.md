# bin — 하니스 실행 스크립트

tmux 세션 생애주기(up/down)와 워커 dispatch·watcher·classify·permission-gate를 구현하는 bash 도구 모음. 워커는 `{{HARNESS_ROOT}}/bin/<name>.sh` 절대경로로 이 도구들을 호출한다.

**Tradeoff**: bash + tmux 의존을 받아들이는 대신, 별도 런타임 없이 PROJECT_ROOT 분리·세션 재생성 가능성을 얻는다.

## 1. WHAT

agenphony 하니스의 실행층 — tmux 페인 배치·워커 부트·작업 dispatch·완료 감지·권한 분류를 담당하는 bash 모듈들.

## 2. CONTENTS

- `agenphony-up.sh` — 프로파일 기반 tmux 세션 가동(워커 페인·부트 프롬프트 주입)
- `agenphony-down.sh` — 런타임 정리(tasks/results는 보존)
- `agenphony-list.sh` — 가동 중인 agenphony-* 세션 나열
- `dispatch.sh` — lead/외부가 `<role> <task-id>` 형식으로 워커에 작업 주입
- `watcher.sh` — events.log/pending-asks 폴링 데몬, lead/reviewer 페인을 깨움
- `classify.sh` — 명령어를 danger→matrix→auto→gray로 분류
- `danger-check.sh` — 위험 명령(`rm -rf`, `sudo`, `dd of=`, `curl|sh`, `git push --force` 등) 거부
- `matrix-lookup.sh` — `config/lead-auto-allow.yaml`의 카테고리 패턴 매칭(awk 파서)
- `permission-gate.sh` — PreToolUse hook 진입점, classify 결과로 allow/deny 결정
- `log-event.sh` — events.log 포맷 라인 append 헬퍼
- `lib.sh` — 공통 함수(`generate_worker_settings` 등), 다른 스크립트가 source

기술 스택: bash 4+/zsh, tmux 3.6+, awk, sed, claude CLI

## 3. HOW

_(update 스킬에서 채워질 자리. 작업 중 패턴이 정립되면 `/update`로 인터뷰 진행)_

## 4. ⛔ HOW NOT

_(update 스킬에서 채워질 자리. 사용자 결정 사항이므로 init은 비워둔다)_

## 5. WHERE

<!-- 모두 약결합(마크다운 링크) — 강결합 승격은 /update에서 판단 -->

- **의존**:
  - [`profiles/`](../profiles/) — `agenphony-up.sh`가 프로파일 셸 fragment를 source (`WORKERS`/`REVIEWERS`/`SESSION`/`LAYOUT`/`LEAD_MODEL`)
  - [`prompts/`](../prompts/) — `_common.md` + `roles/NN-part/<역할>.md` 글롭으로 자동 카탈로그, `{{HARNESS_ROOT}}` 토큰을 sed 치환 후 워커 stdin에 주입
  - [`templates/`](../templates/) — `lib.sh::generate_worker_settings`가 역할군에 맞는 `settings.<군>.json.tpl` 선택
  - [`config/lead-auto-allow.yaml`](../config/lead-auto-allow.yaml) — `matrix-lookup.sh`의 awk 파서가 카테고리 패턴 읽음 (`category:` + 2칸 들여쓰기 + `- "패턴"` 단순 형식만)
- **피의존**:
  - 워커(`prompts/roles/*`)가 `{{HARNESS_ROOT}}/bin/<도구>.sh` 절대경로로 호출
  - [`tests/`](../tests/) — `test-*.sh` 다수가 이 디렉토리의 함수/스크립트 단위 검증
- **경계 / 어댑터**:
  - tmux ↔ bash: `send-keys -l`(텍스트/Enter 분리), `wait-for`, `capture-pane`
  - claude CLI ↔ 워커: stdin 부트 프롬프트 주입, allow-set-title off로 pane title 보존

## 6. WHY

_(update 스킬에서 채워질 자리. 사용자 결정 사항이므로 init은 비워둔다)_

## 7. COMMANDS

```bash
# 정적 검사
shellcheck bin/*.sh                # 설치된 경우

# 단위 테스트 (이 디렉토리 변경 시)
bash tests/run-all.sh
RUN_INTEGRATION=1 bash tests/run-all.sh    # claude CLI 의존 probe 포함
```

_(영역 고유 가드는 update에서 추가)_

## 8. ⚠️ LEARNED CAUTIONS

@./LEARNED_CAUTIONS.md

자세한 내용은 [LEARNED_CAUTIONS.md](./LEARNED_CAUTIONS.md) 참조.
