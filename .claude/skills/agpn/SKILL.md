---
name: agpn
description: agenphony 하네스 진입점. plan(계획 위임)·stage(plan 검증+팀편성+발진명령)·list(세션 목록) 서브커맨드. /agpn <서브커맨드>.
---

# agpn — agenphony 하네스 진입점

첫 인자(서브커맨드)로 분기한다: `plan` / `stage` / `list`. 인자 없음·미지원 → usage.

**공통 규약 (토큰·보안):**
- 본 스킬 본체는 토큰0 작업(파싱·파일I/O·대화·스킬 위임). 4축 리뷰만 Agent subagent.
- 라이브 tmux(`agenphony-up`, `tmux attach`)는 **절대 직접 실행하지 말 것** — 완성된 명령을 출력하고 사용자가 `!` 로 실행하게 한다(claude `-p`·직접 실행 금지).

## 서브커맨드: plan
사용자 아이디어 → 계획 설계. superpowers 스킬로 위임:
1. `superpowers:brainstorming` 스킬을 Skill 도구로 호출(설계 대화).
2. 완료되면 `superpowers:writing-plans` 스킬을 호출(plan 작성).
산출물은 `docs/superpowers/plans/YYYY-MM-DD-<name>.md`. 완료 후 "이제 `/agpn stage` 로 검증·가동하세요" 안내.

## 서브커맨드: stage [plan]
plan 을 검증·팀편성해 발진 명령을 출력한다. 4단계:

### 단계 1 — plan 로드 & 점검 (토큰0)
- 인자 있으면 그 경로. 없으면 `docs/superpowers/plans/*.md` 중 최신(mtime) 1개 자동선택 → "이 plan 맞나요?" 확인. 여러 후보면 목록 제시. 0개면 "`agpn plan` 으로 먼저 작성하세요" 안내 후 종료.
- plan 을 읽어 task 구조(`### Task N:`) 파싱 가능 여부 가벼운 검사.

### 단계 2 — 4축 리뷰 (Agent subagent)
- `stage-review-prompt.md` 내용 + **plan 전문**을 prompt 로 Agent 1회 디스패치. **subagent_type = `general-purpose`**.
- subagent 는 plan 을 수정 않고 보고만. 반환의 종합이 CHANGES_NEEDED 면 결함별 수정안을 만들어 사용자에게 diff 제시 → 승인 → plan 파일 갱신. APPROVED 면 단계 3. (재리뷰 루프 없음.)

### 단계 3 — 팀 편성
- 갱신 plan 분석 → `references/profiles.md` 매핑으로 profile 추천(+근거).
- AskUserQuestion: 추천 채택 / 다른 profile / 커스텀.
- 커스텀: 워커역할 체크 → 리뷰어 체크 → 복수 가능 역할 개수 → 모델(권장 자동+변경여부). 역할 유효성(`prompts/roles/<역할>.md`) 검사. → `--workers "dev:dev:sonnet,..."` 조립.

### 단계 4 — 발진 명령 출력 (토큰0)
- profile 채택: `agenphony-up <profile> --plan <갱신plan> [--project <경로>]`
- 커스텀: `agenphony-up --workers "<조합>" --plan <갱신plan> [--project <경로>]`
- `--project`: agenphony-up 이 cwd git toplevel 로 자동도출. cwd 가 타깃 프로젝트가 맞는지 확인("이 프로젝트(`<cwd>`)에 띄울까요?"), 다르면 `--project` 명시.
- 명령을 출력하고 "`!` 로 실행하세요" 안내. **직접 실행 금지.**

## 서브커맨드: list
→ `list` 절(아래) 따름.

## usage
인자 없음·미지원 시:
```
agpn <서브커맨드>
  plan [아이디어]   계획 설계(brainstorming→writing-plans 위임)
  stage [plan]      plan 검증·팀편성·발진 명령 출력
  list              살아있는 agenphony 세션 목록
```
