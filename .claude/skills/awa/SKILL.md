---
name: awa
description: AWA harness entry point. /awa (no args) launches with 4-axis plan review + preset + mode. Subcommands: down/dash/bookmarks. User `!` required for launch/attach.
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
  # global install via symlink: ~/.claude/skills/awa → <repo>/.claude/skills/awa
  _link="$(readlink ~/.claude/skills/awa)"
  HARNESS_ROOT="$(cd "$(dirname "$_link")/../.." && pwd)"
elif [ -d ~/.claude/skills/awa ] && [ -f ~/.claude/skills/awa/SKILL.md ]; then
  # global install via copy: search up for repo root marker (bin/awa-main.sh)
  HARNESS_ROOT=""  # fallback to user prompt
else
  HARNESS_ROOT=""  # last resort — ask user for harness path
fi
```

**All Bash invocations MUST use `bash "$HARNESS_ROOT/bin/<script>.sh" ...` (absolute path).** Never use relative `bin/...` — cwd is unreliable across new terminal sessions. lib.sh's "not a git repo" warning is suppressed because `$HARNESS_ROOT` is always the repo root.

1. **Step 0 — Resume check (Bash):** `bash "$HARNESS_ROOT/bin/awa-main.sh" resume`
   - Parses TSV output (header line + 0+ rows). If rows exist, present them to user via chat. `_DASHBOARD` row is labeled `multi-view`.
   - User picks one → `bash "$HARNESS_ROOT/bin/awa-main.sh" attach --session <name>` → print attach cmd → END.
   - User picks none / no rows → continue to Step 0.5.

   - **Step 0.5 — team.yaml 재호출:** **이 체크는 Step 3(Project 결정) 직후 수행한다** — PROJECT 경로가 정해진 뒤라야 .awa/team.yaml 경로를 안다. Step 3(Project) 에서 PROJECT_ROOT 가 결정된 후,
     `bash -c "test -f <PROJECT>/.awa/team.yaml && echo found"` 실행.
     - `found` 출력 시 → 사용자에게 "이전 팀 구성을 찾았습니다. 이어서 띄울까요? (.awa/team.yaml)" 제시.
       - yes → Step 4 launch 로 직행 (`--spec <PROJECT>/.awa/team.yaml`).
       - no → Step 1 인터뷰 (새 조합).
     - 살아있는 세션과 team.yaml 둘 다 있으면: 세션 attach 가 우선, team.yaml 은 "새로 띄우기" 옵션.
     - team.yaml 없으면 → Step 1 인터뷰로 진행.
     - (PROJECT_ROOT 는 Step 3 에서 결정되므로, Step 0.5 체크는 Step 3 직후 Step 4 직전에 수행한다.)

2. **Step 1 — Plan (SKILL chat):**
   - **Auto-discover** (9th review [CRIT-22]): `bash -c "ls -t \"$HARNESS_ROOT/docs/superpowers/plans\"/*.md 2>/dev/null | head -1"`. If found, ask user "Use this plan? <path>" (y/n). User can also paste different path or skip.
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
   - **Preset suggestion** (9th review [MINOR-24]):
     - After APPROVED, *SKILL itself* (no subagent) applies heuristics in `references/presets.md` to the plan body:
       - keyword/path scan (Test:, tests/, "research", "security", Create:-count).
       - returns one recommended seed profile + reasoning (구현→default, 조사→research, 보안→code-review, 풀스택→web, 혼합→feature-team).
   - If user skips plan → directly proceed to 조합 인터뷰.
   - **조합 인터뷰** — 2-stage 구성 (`references/interview.md` 절차 수행):
     - **Stage 1**: 작업 종류 질문 → 시드 profile yaml(`profiles/<seed>.yaml`) 을 읽어 초안 제시.
     - **Stage 2**: 워커·리뷰어 가감 인터뷰 → 사용자 승인/수정.
     - 불변식 검증(`spec_parse_invariants`) → 위반 시 자동 교정(review-mgr 추가)/경고.
     - 결과를 `<PROJECT>/.awa/team.yaml` 작성(Write). git 추적 안내.
     - Step 4 launch 는 `--preset` 대신 `--spec <PROJECT>/.awa/team.yaml` 전달.

3. **Step 2 — Mode (SKILL chat, dynamic):**
   - Bash: `tmux list-sessions -F '#{session_name}' | grep -E '^(awa-|_DASHBOARD$)' | wc -l`
   - count ≥ 1 → ask user: Single vs Multi-view
   - count = 0 → mode=single auto, inform user

4. **Step 3 — Project (SKILL chat)** (15th live finding [L-3]):
   - Note: claude code Bash tool cwd cannot be trusted as the user's project root across new terminal sessions — therefore there is no separate "Current(cwd)" option. The user pastes their cwd via the *Custom path* option below.
   - Options (3, with clear labels):
     1. **Bookmarks** — pick from saved list
     2. **Custom path** — paste absolute path or alias (this is also the channel for "my current cwd": just paste it)
     3. **Harness root** — developer-only, runs against the harness repo itself
   - For Bookmarks: `bash "$HARNESS_ROOT/bin/awa-bookmarks.sh" list` → present rows to user → user picks number or alias
   - For Custom path: ask path/alias from user (label hints "absolute path or alias; if your terminal cwd, paste it here")
   - For Harness root: use `$HARNESS_ROOT` directly
   - **Resolve to absolute path:** `bash "$HARNESS_ROOT/bin/awa-main.sh" resolve-path --input <user-input>` → returns resolved path or exit 1.

5. **Step 4 — Launch command output (Bash, non-interactive):**
   (Step 3 직후 Step 0.5 team.yaml 체크 수행 — 위 Step 0.5 참조)
   ```
   bash "$HARNESS_ROOT/bin/awa-main.sh" launch \
     --project <resolved-path> \
     --mode-launch <single|multi> \
     [--spec <PROJECT>/.awa/team.yaml | --preset <name> | --workers <spec>] \
     [--plan <path>]
   ```
   - team.yaml 재호출 시: `--spec <PROJECT>/.awa/team.yaml`
   - 새 조합 인터뷰 완료 시: `--spec <PROJECT>/.awa/team.yaml` (Write 후)
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
- `references/presets.md` — preset suggestion heuristics
- `references/interview.md` — 동적 팀 조합 인터뷰 절차
- spec: `docs/superpowers/specs/2026-05-29-dashboard-pane-grid-design.md`
- spec: `docs/superpowers/specs/2026-06-04-dynamic-harness-composition-design.md`
