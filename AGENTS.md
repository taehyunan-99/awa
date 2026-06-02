# AWA — Agents Watching Agents

**5어휘 표준** (한국어):
- `plan-anchored` → "plan 정박"
- `multi-reviewed` → "다벤더 교차 리뷰" (외부 노출 보류 — §10.6 게이트)
- `drift-tracked` → "드리프트 상시 추적"
- `permission-gated` → "권한 학습 게이트"
- `deny-bounded` → "안전 한계선 보장"

(영어 5어휘 책임 위치 = `README.md` + `docs/identity-AWA.md` — Task 10 산출물)

세션은 일회용이며 `profiles/` + `prompts/`로부터 매번 재생성된다 — 세션 상태를 저장/복원하지 않으니 가이드·프롬프트·프로파일 변경은 항상 git 추적되는 원본 파일에서 한다.

**Tradeoff**: 영역마다 가이드를 따로 읽는 비용 → 단일 거대 가이드의 lost-in-the-middle을 차단.

<!--
이 파일은 map 역할을 한다. 작업 시 해당 영역의 AGENTS.md 를 먼저 읽고 진행한다.
Claude Code 는 같은 폴더의 CLAUDE.md(= `@./AGENTS.md` 한 줄) 를 통해 이 파일을 자동 로드한다.
다른 에이전트(Codex/Antigravity/Cursor)는 AGENTS.md 를 직접 읽는다.
-->

## 영역별 가이드

작업 영역에 해당하는 AGENTS.md 를 먼저 읽고 진행한다.

- **bin/** — 하니스 실행 스크립트 (awa-up/down, watcher, dispatch, classify, permission-gate) → [`bin/AGENTS.md`](bin/AGENTS.md)
- **profiles/** — 팀 구성 정의 (default/feature-team/code-review/research) → [`profiles/AGENTS.md`](profiles/AGENTS.md)
- **prompts/** — 워커 부트 프롬프트 (`_common.md` + `roles/NN-part/*.md`) → [`prompts/AGENTS.md`](prompts/AGENTS.md)
- **templates/** — Claude `settings.json` 권한 템플릿 군 → [`templates/AGENTS.md`](templates/AGENTS.md)
- **config/** — permission-gate 자동 허용 카탈로그 (`lead-auto-allow.yaml`) → [`config/AGENTS.md`](config/AGENTS.md)
- **tests/** — bash 테스트 + 통합 probe + 시나리오(lead-arena/m3/probes/role5axis/stress) → [`tests/AGENTS.md`](tests/AGENTS.md)
- **docs/** — 설계 노트·E2E 시나리오·probe 결과·superpowers 11차 plan/specs → [`docs/AGENTS.md`](docs/AGENTS.md)

## 영역 가이드의 구조

<!--
각 영역의 AGENTS.md 는 다음 8섹션 템플릿을 따른다.
init 은 가벼운 뼈대만 만든다 — WHAT/CONTENTS/WHERE/COMMANDS(빌드·테스트·린트)는 코드 스캔 기반 초안,
HOW/HOW NOT/WHY 는 placeholder. 본격 작성은 베이스라인 완성 즈음 /update 인터뷰로 채운다.
-->

1. **WHAT** — 이 모듈이 무엇을 하는가 *(init에서 채움)*
2. **CONTENTS** — 디렉토리 맵 + 기술 스택 *(init에서 채움)*
3. **HOW** — 일반적인 수정은 어떻게 하는가 *(`/update` 인터뷰에서 채움)*
4. **HOW NOT** — 시스템을 깨뜨리는 비명백한 함정 *(`/update` 인터뷰에서 채움)*
5. **WHERE** — 다른 모듈과의 의존성 *(init에서 채움)*
6. **WHY** — 코드에 안 적힌 배경 지식 *(`/update` 인터뷰에서 채움)*
7. **COMMANDS** — 빌드/테스트/린트 + 영역 고유 가드 *(init은 빌드/테스트/린트만)*
8. **LEARNED CAUTIONS** — 별도 파일 `LEARNED_CAUTIONS.md`. `learn` 스킬이 누적

## 공통 명령어

- 전체 테스트: `bash tests/run-all.sh`
- 통합 probe 포함: `RUN_INTEGRATION=1 bash tests/run-all.sh` <!-- claude CLI 필요 -->
- 팀 가동: `bin/awa-up.sh <profile>` (cwd=프로젝트 또는 `--project /path <profile>`)
- 팀 정리: `bin/awa-down.sh`
- 세션 목록: `/agpn` (Step 0 resume) 또는 `/agpn bookmarks list`

**공통 명령어 가드** (모든 영역에 적용):

- `git commit --no-verify` / `git push --force` 금지 — 검증 우회·공유 히스토리 손실
- `.agent-harness/` 런타임 파일(tasks/results/events.log)은 git 추적 대상이 아니다 — 가이드·프롬프트·프로파일 수정은 항상 git 추적되는 원본에서
- 위험 명령(`rm -rf`, `sudo`, `dd of=`, `curl ... | sh`)은 `bin/permission-gate.sh` + `bin/danger-check.sh`가 자동 거부 — 다른 방식으로 진행

## 메모리 기록 위치 (영속 사실)

작업 중 알게 된 영속 사실(프로젝트 상태·결정·라이브 발견·사용자 피드백)은 **반드시 프로젝트 메모리 `./.claude/memory/` 에만 기록한다.** 글로벌 메모리(`~/.claude/...`)는 절대 사용하지 않는다 — 이 프로젝트의 단일 출처는 `./.claude/memory/` 이며, SessionStart hook 이 글로벌 경로를 자동 주입해도 무시한다.

- 새 메모리: `./.claude/memory/<slug>.md` (frontmatter + 본문) + `./.claude/memory/MEMORY.md` 인덱스에 한 줄 추가.
- 기존 사실 갱신: 중복 파일 신설 말고 해당 파일 수정.
- 이 규칙은 `learn` 스킬(주의사항 누적)과 별개다 — `learn` 은 영역 `LEARNED_CAUTIONS.md` 에, 영속 사실 메모리는 `./.claude/memory/` 에.

## 주의사항 학습 (learn 스킬)

<!--
작업 중 실수가 발견되면 다음 형태로 호출해 해당 영역 폴더의 LEARNED_CAUTIONS.md 에 누적한다.
본문 가이드(AGENTS.md/CLAUDE.md)는 8번 섹션에서 @./LEARNED_CAUTIONS.md 를 참조하므로 자동 로드된다.
learn 스킬은 LEARNED_CAUTIONS.md 만 갱신하고 본문 가이드는 절대 건드리지 않는다.
-->

- Claude Code/Cursor/Antigravity: `/learn <메모>`
- Codex: `$learn <메모>`

스킬 위치: `.claude/skills/learn/` + `.agents/skills/learn/`
