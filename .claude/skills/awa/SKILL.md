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
   - User picks none / no rows → continue to Step 1.

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
       - returns one recommended preset + reasoning.
   - If user skips plan → directly proceed to preset choice.
   - **Preset choice — 2-stage branch** (15th live finding [L-2], AskUserQuestion 4-option cap):
     - **Stage A — preset or custom?** AskUserQuestion: `preset (recommended) | custom (manual roles)`.
     - **Stage B-preset** (if user chose preset): AskUserQuestion with 4 options — `default | feature-team | research | code-review`. Recommended option is highlighted from heuristic output above.
     - **Stage B-custom** (if user chose custom): proceed to *Custom branch* below.
   - **Custom branch** (9th review [MAJOR-23]):
     - Worker roles inventory: `$HARNESS_ROOT/prompts/roles/02-development/*.md` (dev, researcher) and `$HARNESS_ROOT/prompts/roles/04-security/*.md` (security), plus `$HARNESS_ROOT/prompts/roles/03-quality/tester.md`.
     - Reviewer roles inventory: `$HARNESS_ROOT/prompts/roles/03-quality/reviewer-{spec,arch,quality}.md` (excluding `reviewer-common.md`).
     - AskUserQuestion: which worker roles (multi-select). For each chosen role ask count (1-3) and model (`opus|sonnet|haiku`, recommended default sonnet).
     - AskUserQuestion: which reviewer roles (multi-select, optional).
     - Assemble `--workers "name1:role1:model1,name2:role2:model2,..."` (matches awa-up.sh `WORKERS_ARG` format).
     - Validation: SKILL checks every role file exists via Bash test; reject with clear error if missing.

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
   ```
   bash "$HARNESS_ROOT/bin/awa-main.sh" launch \
     --project <resolved-path> \
     --mode-launch <single|multi> \
     [--preset <name>|--workers <spec>] \
     [--plan <path>]
   ```
   main.sh prints the awa-up.sh command + `# AWA_META: session=<n> mode=<m>` line.

   **AWA_META parsing** (10th review [CRIT-27]):
   ```bash
   meta=$(grep '^# AWA_META:' <main.sh-output>)
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
- spec: `docs/superpowers/specs/2026-05-27-awa-unified-entry-dashboard.md`
