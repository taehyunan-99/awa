# 동적 팀 조합 인터뷰

목적: 사용자 작업을 **분석**해 역할 카탈로그에서 필요한 역할만 골라 팀을 **조립**하고, .awa/team.yaml 을 제안·승인·저장한다.

<!-- prev: "profiles/*.yaml 은 내부 참고용 시드일 뿐 통째로 던지지 않는다" → profiles/ 디렉토리 제거(2026-06-07, e654309). 시드 자체가 사라져 '정적 템플릿 금지' 원칙만 남김. -->
> **핵심 원칙 (2026-06-06)**: **고정 템플릿을 사용자에게 통째로 던지지 않는다.** AWA(Claude)가 작업을 읽고 역할 카탈로그(`prompts/roles/`)에서 필요한 것만 골라 조립하고 그 근거를 설명한다. "미리 정의된 프로파일 N개 중 하나 고르기"는 정적 템플릿과 다를 게 없으므로 금지.

## 역할 카탈로그 (조합의 원자 단위)

`prompts/roles/` 에서 글롭으로 확인. 현재 가용:

**워커** (`02-development/`, `04-security/`):
- `engineer` — 범용 구현 (단일 기능·소규모)
- `dev` — 개발 (다역할 협업 구현)
- `frontend` / `backend` / `infra` — 풀스택 3분업
- `researcher` — 조사·읽기 전용 (코드 변경 없는 탐색·비교)
- `tester` — 테스트 작성
- `security` — 보안 점검·코드 감사 워커

**리뷰어** (`03-quality/`):
- `reviewer-alignment` — plan 정합 검토
- `reviewer-quality` — 품질 검토
- `reviewer-security` — 보안 검토
- `reviewer-arch` — 아키텍처 검토
- `reviewer-spec` — 스펙 충족 검토
- `reviewer-alternative` — 대안 관점
- `review-manager` — 집계·드리프트 추적 (투표 리뷰어 ≥2 시 필수)

권한은 역할에서 자동 파생(generate_worker_settings): engineer/dev/frontend/backend/infra/security→dev쓰기, researcher/review-manager→readonly, tester→test, reviewer-*→reviewer.

## 절차

### Stage 1 — 작업 분석 → 자율 조립
1. 사용자 작업을 받는다 (작업종류 선택 또는 자유 프롬프트 — SKILL.md Step 1 참조).
2. **Claude(SKILL 자신)가 작업을 분석**해 어떤 역할이 필요한지 판단한다. 시드 yaml 은 *참고만* 한다(읽되 그대로 복사 금지).
   - 단일 기능 구현 → engineer 1 (+ 필요시 researcher)
   - 풀스택 웹 → frontend + backend + infra (전부 필요한지 작업 보고 판단 — API만이면 backend만 등)
   - 조사·비교 → researcher 1~3, 코드 변경 없으면 무리뷰 가능
   - 코드 감사·보안 → security 워커 + 다관점 리뷰어
   - 설계 비중 큼 → dev + tester + (arch 관점 리뷰어)
3. **조립 결과 + 근거를 사용자에게 제시**한다. 예: "메모 웹앱이라 frontend(폼/목록)·backend(저장 API)·infra(실행) 3명, plan 정합·품질 리뷰어를 붙였습니다. 인증/DB 불필요라 security 워커는 뺐습니다."
   - ★ **투표 리뷰어는 0명 또는 2명+ 만 제안한다 — 1명 조립은 절대 제안 금지**(불변식 위반·부팅 실패). 소규모라 리뷰를 가볍게 하려면 **무리뷰(0명)**를 제안하고, 리뷰를 둘 거면 **최소 2종**(예: quality+alignment)을 제안하라. "reviewer-quality 1명"은 금지.

### Stage 2 — 워커·리뷰어 가감
4. 사용자가 조립을 승인하거나 가감(역할 추가/제거/인원/모델)을 지시.
5. **리뷰 수위 확인**: full-vote(alignment+quality+security 투표 리뷰어 3 + review-mgr) / 무리뷰(투표 0).
   ★ 투표 리뷰어 **1명은 금지**(multi-reviewed 정체성 — 1명은 합의가 아닌 단독거부권). 2명+ 또는 0명만.
   2명+ 선택 시 review-mgr 자동 동반(불변식이 강제).

### Stage 3 — codex 다벤더 리뷰어 (후행 질문 — 기본 제외)
6. **기본은 claude 리뷰어만.** 조립 확정 후 별도로 묻는다:
   > "다벤더 교차 리뷰를 위해 codex 리뷰어(security 검토)도 추가할까요? codex CLI 설치가 필요합니다. (AWA 차별화 = 다벤더 리뷰지만, codex 없으면 부팅 실패하므로 기본 제외)"
   - yes → security 리뷰어에 `vendor: codex` 부여 (또는 codex security 리뷰어 1명 추가).
   - no → claude 리뷰어만으로 진행.
   - (선택) `command -v codex` 로 설치 감지해 안내 문구 보강 가능.
   - **조립 단계에서 codex 를 기본 포함하지 않는다 — vendor:codex 는 이 후행 질문 승인 시에만 team.yaml 에 들어간다.** (시드 yaml 은 참고용이라 codex 를 가질 수 있으나, 그대로 복사하지 말고 codex 는 빼고 조립한 뒤 여기서 물어 추가.)

## 불변식 (spec §4 — 반드시 강제)

**파서가 자동 거부하는 항목 (spec_parse_invariants → rc=1):**
- **투표 리뷰어(reviewer-alignment/quality/security)는 0 또는 2명+ 만 허용. 1명은 거부**(단독거부권 ≠ 합의, multi-reviewed 정체성). 인터뷰는 1명 조립을 *애초에 제안하지 말 것* — 저장 단계에서 막히면 사용자 경험이 나쁨.
- 투표 리뷰어 ≥2 이면 review-manager(name: review-mgr) 필수 — 없으면 자동 포함.
- 저장 전 `bash -c 'source "$HARNESS_ROOT/bin/spec-parse.sh" && spec_parse_invariants <path>'` 로 검증(rc=0 확인).

**인터뷰가 직접 판단해 사용자에게 경고·확인하는 항목:**
- 무리뷰(투표 0)는 "합의 게이트 없이 진행"을 사용자에게 명시 확인.

## 저장 (.awa/team.yaml = 누가, .awa/task.md = 무엇)

### team.yaml (누가 — 팀 구성)
- 대상 프로젝트 PROJECT_ROOT/.awa/team.yaml 작성.
- git 추적 여부 안내: 기본 추적되며, 개인 설정으로 끄려면 .gitignore 에 `.awa/` 한 줄 추가.
- plan 참조 시: 그 plan 이 git 미추적(docs/)이면 "로컬 전용, 공유 안 됨" 고지(plan 은 soft reference — 재호출 시 없으면 경고 후 plan 없이 진행).

### task.md (무엇 — 자연어 작업의 ORCH 전달)
**plan 없이 자유 프롬프트로 작업을 받은 경우에만** 작성한다(plan 경로는 plan 파일 자체가 작업 정의이므로 task.md 불필요 — 상호배타).

- 사용자가 자연어로 설명한 작업을 `PROJECT_ROOT/.awa/task.md` 로 Write 한다.
- 목적: tmux 가동 시 ORCH 가 이 파일을 읽어 **자동으로 작업을 시작**하게 한다. task.md 없이 부팅하면 ORCH 는 지시 없이 idle 대기한다.
- task.md 는 `--plan <PROJECT>/.awa/task.md` 로 launch 에 전달된다 — 기존 plan 주입 경로(`--append-system-prompt-file` 합본 + 자동 착수 트리거)를 그대로 재사용한다.
- **task.md 는 plan 4축 리뷰를 거치지 않는다** — 자연어 = 간단 작업 신호. 복잡한 작업이면 사용자에게 "plan/PRD 를 먼저 만들어 전달하길 권장"한다(소프트 가이드).
- git 추적: task.md 는 `.awa/` 안이라 team.yaml 과 동일하게 처리된다(SKILL.md 의 git init/gitignore 단계가 `.awa/` 통째로 커버 — 별도 처리 없음).

#### task.md 형식 (SKILL 이 작성)
ORCH 가 읽을 한국어 작업 설명. 첫 줄(H1 제목)을 `# 작업 지시 (자연어 입력 — 검증된 plan 아님)` 으로 두어, ORCH 가 plan 수준의 형식적 완결성을 기대하지 않게 한다. 본문은 사용자가 자연어로 설명한 작업 내용을 그대로 또는 정리해 기록한다.

## 스키마
layout / workers[].{name,role,vendor,model} / reviewers[].{name,role,vendor} / plan(경로 참조, 선택)
- name 컨벤션: 리뷰어 = `<역할>-rev` 접미사, review-manager = `review-mgr` 고정(REVIEW_MANAGER_PANE 의존).
