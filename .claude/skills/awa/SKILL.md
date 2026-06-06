---
name: awa
description: AWA harness entry point. /awa (no args) launches with 4-axis plan review + dynamic team composition + mode. Subcommands: down/dash/bookmarks. User `!` required for launch/attach.
---

# awa — AWA harness entry point (15th cycle)

Redefined as a single responsibility — *team execution and management*. Plan writing is external.

## Execution Model (§1.1)

**(A) User `!` required** — claude child process / stdin/stdout hijack risk
- `bash "$HARNESS_ROOT/bin/awa-up.sh" ...` (launch = spawns claude REPL per worker)
- `tmux attach -t <session>`

**(B) claude code auto-execute OK** — no risk above
- All tmux ops (move-window / kill-session / set-option / ...)
- `bash "$HARNESS_ROOT/bin/awa-down.sh" --project ...` (runtime cleanup only)
- `bash "$HARNESS_ROOT/bin/awa-down-menu.sh"`
- `bash "$HARNESS_ROOT/bin/awa-dashboard.sh" <action>`
- `bash "$HARNESS_ROOT/bin/awa-bookmarks.sh" <action>`
- `bash "$HARNESS_ROOT/bin/awa-main.sh" ...` (non-interactive arg mode)

## Routing

### `/awa` (no args) — launch flow

SKILL collects info via chat (AskUserQuestion or natural prompts), then dispatches main.sh non-interactively.

**HARNESS_ROOT discovery (MUST run before first Bash call)** — claude code Bash tool cwd is the user's *terminal cwd*, not the harness. Relative `bin/...` paths break when claude is started from outside the repo. (15th live finding [L-1])

```bash
if [ -n "${AWA_HARNESS_ROOT:-}" ]; then
  HARNESS_ROOT="$AWA_HARNESS_ROOT"
elif [ -L ~/.claude/skills/awa ]; then
  # 심링크 설치 — 상대/절대 심링크 모두 방어 후 harness/ 한 겹 추가.
  #   상대 readlink 는 *링크 디렉토리* 기준이므로, 먼저 링크 디렉토리(~/.claude/skills)로
  #   cd 한 뒤 readlink 결과를 그 기준으로 절대화한다 (cwd 기준 해석 시 상대 심링크가 깨짐).
  _raw=~/.claude/skills/awa
  _t="$(readlink "$_raw")"
  _link="$(cd "$(dirname "$_raw")" && cd "$(dirname "$_t")" && pwd -P)/$(basename "$_t")"
  HARNESS_ROOT="$(cd "$_link/harness" && pwd)"
elif [ -d ~/.claude/skills/awa ] && [ -f ~/.claude/skills/awa/harness/bin/lib.sh ]; then
  # 복사 설치 — 스킬 디렉토리 아래 harness/
  HARNESS_ROOT="$(cd ~/.claude/skills/awa/harness && pwd)"
else
  HARNESS_ROOT=""  # last resort — ask user for harness path
fi
```

**All Bash invocations MUST use `bash "$HARNESS_ROOT/bin/<script>.sh" ...` (absolute path).** Never use relative `bin/...` — cwd is unreliable across new terminal sessions. lib.sh's "not a git repo" warning is suppressed because `$HARNESS_ROOT` is always the repo root.

> **Step 순서 (2026-06-06 재배치 — 경로 먼저, 작업 나중):** Step 0(resume) → **Step 1(Project 경로)** → **Step 1.5(team.yaml 재호출)** → **Step 2(Plan/작업 + 조합 인터뷰)** → Step 3(Mode) → Step 4(launch). 경로를 먼저 정해야 team.yaml 재호출 체크를 조합 인터뷰 *전에* 할 수 있다(이전 구성 있으면 인터뷰 생략 가능). 이전 순서(작업→경로)는 인터뷰를 다 마친 뒤에야 team.yaml 존재를 알아 비효율이었음.

1. **Step 0 — Resume check (Bash):** `bash "$HARNESS_ROOT/bin/awa-main.sh" resume`
   - Parses TSV output (header line + 0+ rows). If rows exist, present them to user via chat. `_DASHBOARD` row is labeled `multi-view`.
   - User picks one → `bash "$HARNESS_ROOT/bin/awa-main.sh" attach --session <name>` → print attach cmd → END.
   - User picks none / no rows → continue to Step 1 (Project).

2. **Step 1 — Project (SKILL chat)** (15th live finding [L-3] · cwd 후보 추가 2026-06-06 · 순서 앞당김 2026-06-06):
   질문 문구(사용자에게 그대로): **"팀이 작업할 프로젝트 폴더를 골라주세요. (워커들이 이 폴더의 파일을 읽고 수정합니다)"**

   - **현재 폴더 후보 자동 감지 (MUST run first):** 사용자가 `claude` 를 띄운 터미널 폴더를 후보로 제시한다.
     `bash -c 'echo "$PWD"'` 로 읽는다. **주의: claude code Bash 도구의 `pwd`(=harness 경로)가 아니라 env `$PWD`(=사용자 터미널 cwd)를 써야 한다** — 이 둘은 다르며, Bash 도구 cwd 를 프로젝트로 쓰면 harness 자체에 팀이 뜨는 과거 결함(L-3) 재발. `$PWD` 가 비었거나 `$HARNESS_ROOT` 와 같으면 후보를 제시하지 않는다(신뢰 불가 케이스).
     - **자동 선택 금지 — 후보로만 제시하고 사용자 확인 필수.** `$PWD` 도 항상 정확하진 않다(루트에서 띄웠으나 하위 폴더가 진짜 대상인 경우). "Claude 가 감지 + 사용자가 눈으로 확인"의 결합이 자동선택보다 안전하다. (이전 결정 "cwd 옵션 없음"을 2026-06-06 뒤집음 — 자동선택이 아닌 후보+확인이라 L-3 위험 없음.)

   - **Options (사용자에게 보여줄 직관적 라벨):**
     1. **이 폴더에서 작업** — `현재 폴더: <$PWD>` (감지된 경우만 표시. 지금 터미널이 열린 곳)
     2. **다른 폴더 경로 입력** — 작업할 폴더의 전체 경로를 붙여넣기 (예: `/Users/you/projects/myapp`). 북마크에 저장한 별칭도 가능.
     3. **저장된 북마크에서 고르기** — 전에 등록해둔 프로젝트 목록에서 선택
     4. *(개발자 전용)* **AWA 하니스 자체** — AWA 코드를 직접 손볼 때만. 일반 작업이면 고르지 말 것.

     (1번은 `$PWD` 감지 실패 시 목록에서 빠진다. 그 경우 2번이 기본 안내.)

   - 각 분기 처리:
     - **이 폴더에서 작업:** `$PWD` 값을 그대로 사용 (이미 절대경로).
     - **다른 폴더 경로 입력:** 사용자에게 경로/별칭을 받는다.
     - **북마크:** `bash "$HARNESS_ROOT/bin/awa-bookmarks.sh" list` → 행을 사용자에게 제시 → 번호/별칭 선택.
     - **하니스 자체:** `$HARNESS_ROOT` 직접 사용.
   - **Resolve to absolute path:** (1·하니스 외 입력은) `bash "$HARNESS_ROOT/bin/awa-main.sh" resolve-path --input <user-input>` → 해석된 경로(=PROJECT_ROOT) 또는 exit 1.

   - **git 초기화 + .gitignore 처리 (2026-06-06 신설 — team.yaml 저장 전제):** PROJECT_ROOT 가 정해지면 git 상태를 확인하고 사용자 확인을 거친다.
     - `bash -c "git -C <PROJECT> rev-parse --is-inside-work-tree 2>/dev/null"` 로 git repo 여부 확인.
       - **git repo 아님** → 사용자에게 "이 폴더는 git 저장소가 아닙니다. `git init` 할까요? (team.yaml 버전 관리를 위해 권장)" 확인 → yes 시 `git -C <PROJECT> init`. no 면 그대로 진행(team.yaml 은 추적 안 됨 고지).
     - `.gitignore` 처리 (git repo 일 때만):
       - `.gitignore` **없으면** → "`.awa/` 를 git 으로 추적할까요, 무시할까요? 무시하려면 .gitignore 를 만들어 `.awa/` 를 추가합니다." 확인 → 무시 선택 시 `.gitignore` 생성 + `.awa/` 한 줄 추가. 추적 선택 시 아무것도 안 함(기본 추적).
       - `.gitignore` **있으면** → `.awa/` 가 이미 있는지 확인. 없으면 "`.awa/` 를 .gitignore 에 추가할까요?(무시)" 만 확인 → yes 시 append. (있으면 아무것도 안 함.)
     - **모든 단계는 사용자 확인 후 실행** — 임의 git init/파일 수정 금지([[feedback_gitignore_no_touch]] 정신).

2.5. **Step 1.5 — team.yaml 재호출 (SKILL chat):** PROJECT 경로가 정해진 직후(조합 인터뷰 *전*) 수행한다.
   `bash -c "test -f <PROJECT>/.awa/team.yaml && echo found"` 실행.
   - `found` 출력 시 → 사용자에게 "이전 팀 구성을 찾았습니다. 이어서 띄울까요? (.awa/team.yaml)" 제시.
     - yes → **Step 2(작업/조합 인터뷰) 생략**하고 Step 3(Mode)로 (`--spec <PROJECT>/.awa/team.yaml`).
     - no → Step 2 조합 인터뷰 (새 조합).
   - 살아있는 세션(Step 0)과 team.yaml 둘 다 있으면: 세션 attach 가 우선, team.yaml 은 "새로 띄우기" 옵션.
   - team.yaml 없으면 → Step 2 조합 인터뷰로 진행.

3. **Step 2 — Plan + 작업/조합 인터뷰 (SKILL chat):**
   - **Auto-discover** (9th review [CRIT-22]): plan 은 사용자 프로젝트 산출물이므로 PROJECT_ROOT(Step 1 에서 결정) 기준으로 검색한다 — `bash -c "ls -t \"$PROJECT_ROOT/docs/superpowers/plans\"/*.md 2>/dev/null | head -1"`. If found, ask user "Use this plan? <path>" (y/n). User can also paste different path or skip. plan 없으면 사용자에게 경로 입력을 요청한다.
   - If user provides plan → Agent tool 4-axis review:
     - prompt: `references/review-prompt.md` + plan body
     - subagent_type: `general-purpose`
     - returns 4 axis verdicts + `## 종합: APPROVED | CHANGES_NEEDED`
   - **CHANGES_NEEDED handling** (9th review [CRIT-21]):
     - SKILL parses each FAIL with location/reason from subagent output.
     - **NEW (§6.2 awa-rollout)** — 검증가능성 축 FAIL 분류:
       - 1차 리뷰에서 검증가능성 축 FAIL → **즉시 abort** (재리뷰 없이, 사용자 yes 불가)
       - 1차 PASS 후 재리뷰에서 검증가능성 FAIL 전환 → **즉시 abort** (3차 재리뷰 없음)
       - 다른 3축 (완결성·실행가능성·기술건전성) FAIL → 재리뷰 1회 종결 후 `proceed despite gaps?` 허용
     - For each FAIL (검증가능성 외), SKILL drafts a fix proposal (diff or rewrite snippet) and presents to user via chat.
     - User approves each fix → SKILL writes back to plan file via Edit tool.
     - After all fixes applied, re-run review *once* (one retry max — avoid infinite loop). If still CHANGES_NEEDED, SKILL summarizes remaining gaps and asks user: "proceed despite gaps?" (yes → continue, no → abort). 단, 재리뷰에서 검증가능성 FAIL 발생 시 위 분류대로 즉시 abort.
   - **작업 분석 → 자율 조립** (2026-06-06 재설계 — 정적 시드 던지기 폐기):
     - plan 이 있으면: SKILL 이 plan 본문을 직접 분석해 역할 카탈로그에서 조립한다. **시드 profile 을 통째로 사용자에게 던지지 않는다.**
     - plan 이 없으면: 아래 **작업 입력 질문**으로 작업을 받는다.
   - **작업 입력 질문 (plan skip 시 — AskUserQuestion):**
     - 질문: "어떤 작업을 하시나요?"
     - 선택지 (기초 3개 + 자유 입력):
       1. **기능 구현** — 코드를 새로 짜거나 기능 추가
       2. **코드 조사·분석** — 비교·탐색·리포트 (코드 변경 없음)
       3. **코드 점검·보안** — 기존 코드 감사·취약점 점검
       4. **작업 내용 직접 입력** — 자유 프롬프트로 무엇을 만들지 설명 (선택지에 안 맞으면 이걸로)
     - 4번(또는 1~3 선택 후 상세) → 사용자가 자연어로 작업을 설명하면 **SKILL 이 그 프롬프트를 분석**해 조립.
   - **조합 인터뷰** — `references/interview.md` 절차 수행:
     - **Stage 1 — 작업 분석·자율 조립**: SKILL(Claude) 이 작업을 분석해 **역할 카탈로그**(`prompts/roles/` — engineer/frontend/backend/infra/researcher/tester/security + reviewer-*)에서 필요한 역할만 골라 팀을 조립하고 **근거를 설명**한다.
     - **Stage 2 — 가감**: 워커·리뷰어 가감 + 리뷰 수위(full-vote=투표2+·무리뷰=투표0; **투표 1명은 금지** — 불변식 위반) → 사용자 승인/수정.
     - **Stage 3 — codex 후행 질문 (기본 제외)**: 조립 확정 후 "다벤더 교차 리뷰를 위해 codex 리뷰어도 추가할까요? (codex 설치 필요)" 물어 **승인 시에만** `vendor: codex` 부여. 기본은 claude 리뷰어만 — codex 미설치 사용자 부팅 실패 방지.
     - 불변식 검증(`spec_parse_invariants`) → 투표2+면 review-mgr 자동 추가, 투표1명이면 거부(2명+로 늘리거나 0명으로). 저장 전 rc=0 확인.
     - 결과를 `<PROJECT>/.awa/team.yaml` 작성(Write). git 추적 안내.
     - **자연어 작업(plan skip 분기)이면**: 그 자연어 작업을 `<PROJECT>/.awa/task.md` 로도 Write(무엇 — ORCH 자동 착수용). 형식·절차는 `references/interview.md` 저장 섹션 참조. plan 경로면 task.md 불필요(상호배타).
     - Step 4 launch 는 `--spec <PROJECT>/.awa/team.yaml` 전달. 자연어 작업이면 `--plan <PROJECT>/.awa/task.md` 동반.

4. **Step 3 — Mode (SKILL chat, dynamic):**
   - Bash: `tmux list-sessions -F '#{session_name}' | grep -E '^(awa-|_DASHBOARD$)' | wc -l`
   - count ≥ 1 → ask user: Single vs Multi-view
   - count = 0 → mode=single auto, inform user

5. **Step 4 — Launch command output (Bash, non-interactive):**
   ```
   bash "$HARNESS_ROOT/bin/awa-main.sh" launch \
     --project <resolved-path> \
     --mode-launch <single|multi> \
     [--spec <PROJECT>/.awa/team.yaml | --workers <spec>] \
     [--plan <path>]
   ```
   - team.yaml 재호출 시: `--spec <PROJECT>/.awa/team.yaml`
   - 새 조합 인터뷰 완료 시: `--spec <PROJECT>/.awa/team.yaml` (Write 후)
   - **자연어 작업(plan skip)이면**: 위에 더해 `--plan <PROJECT>/.awa/task.md` 동반 — ORCH 자동 착수. plan 파일 경로면 `--plan <plan-path>` (기존). 둘은 상호배타(같은 launch 에 함께 안 옴).
   main.sh prints the awa-up.sh command + `# AGPN_META: session=<n> mode=<m>` line.

   **AGPN_META parsing** (10th review [CRIT-27]):
   ```bash
   meta=$(grep '^# AGPN_META:' <main.sh-output>)
   launch_session=$(printf '%s' "$meta" | sed -n 's/.*session=\([^ ]*\).*/\1/p')
   launch_mode=$(printf '%s' "$meta" | sed -n 's/.*mode=\([^ ]*\).*/\1/p')
   ```
   SKILL remembers `launch_session` and `launch_mode` for Step 5 (Auto-follow).

6. **User executes the printed command with `!`** (10th review [CRIT-28]):
   - SKILL outputs the launch command to user with explicit guidance: "Please run this with `!` and tell me when it completes (or paste the result)."
   - **SKILL turn ends here** — control returns to user. User runs `!` in their next message. The Bash tool call result (exit code + output) arrives in the *next* SKILL turn.
   - SKILL checks `exit 0` from the launch result to confirm success. On failure, surface the error to user and ask for next action.

7. **Step 5 — Auto-follow for multi-view (10th review [CRIT-28]):**
   - **Only fires when** `launch_mode == "multi-view"` AND the launch result was exit 0.
   - SKILL fetches current live awa-* sessions (Bash): `tmux list-sessions -F '#{session_name}' 2>/dev/null | grep '^awa-' || true`
   - **Excluding `launch_session`** from the result list, compute `existing[]`.
   - Branch:
     - `tmux has-session -t _DASHBOARD` → exit 0 → `bash "$HARNESS_ROOT/bin/awa-dashboard.sh" add <launch_session>`
     - else → `bash "$HARNESS_ROOT/bin/awa-dashboard.sh" merge <existing[]...> <launch_session>`
   - awa-dashboard.sh dedupes defensively, but SKILL should send a clean list.

8. **Step 6 — Attach guidance:** SKILL prints to user `tmux attach -t _DASHBOARD` (multi-view) or `tmux attach -t <launch_session>` (single) → user runs with `!`. SKILL turn ends.

### `/awa down`
Bash: `bash "$HARNESS_ROOT/bin/awa-down-menu.sh"` — auto, menu + multi-select.

### `/awa dash [action]`
Bash: `bash "$HARNESS_ROOT/bin/awa-dashboard.sh" <action> [args]` — auto.
actions: `merge <s1> [s2...]` | `add <s>` | `detach <proj...>` | `split` | `kill <proj...>`

### `/awa bookmarks [action]`
Bash: `bash "$HARNESS_ROOT/bin/awa-bookmarks.sh" <action>` — auto.
actions: `list` | `set-alias` | `remove` | `prune` | `menu` (default)

## References

- `references/review-prompt.md` — 4-axis review subagent prompt
- `references/interview.md` — 동적 팀 조합 인터뷰 절차
- spec: `docs/superpowers/specs/2026-05-29-dashboard-pane-grid-design.md`
- spec: `docs/superpowers/specs/2026-06-04-dynamic-harness-composition-design.md`
