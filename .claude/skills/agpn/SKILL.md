---
name: agpn
description: agenphony harness entry point. /agpn (no args) launches with 4-axis plan review + preset + mode. Subcommands: down/symphony/bookmarks. User `!` required for launch/attach.
---

# agpn — agenphony harness entry point (15th cycle)

Redefined as a single responsibility — *team execution and management*. Plan writing is external.

## Execution Model (§1.1)

**(A) User `!` required** — claude child process / stdin/stdout hijack risk
- `bash bin/agenphony-up.sh ...` (launch = spawns claude REPL per worker)
- `tmux attach -t <session>`

**(B) claude code auto-execute OK** — no risk above
- All tmux ops (move-window / kill-session / set-option / ...)
- `bash bin/agenphony-down.sh --project ...` (runtime cleanup only)
- `bash bin/agenphony-down-menu.sh`
- `bash bin/agenphony-symphony.sh <action>`
- `bash bin/agenphony-bookmarks.sh <action>`
- `bash bin/agenphony-main.sh ...` (non-interactive arg mode)

## Routing

### `/agpn` (no args) — launch flow

SKILL collects info via chat (AskUserQuestion or natural prompts), then dispatches main.sh non-interactively.

**All Bash calls in this routing run with `cwd=$HARNESS_ROOT`** (claude code Bash tool default). lib.sh's "not a git repo" warning is therefore not triggered. Do not change cwd in bash calls. (10th review [MAJOR-29])

1. **Step 0 — Resume check (Bash):** `bash bin/agenphony-main.sh resume`
   - Parses TSV output (header line + 0+ rows). If rows exist, present them to user via chat. `_SYMPHONY` row is labeled `multi-view`.
   - User picks one → `bash bin/agenphony-main.sh attach --session <name>` → print attach cmd → END.
   - User picks none / no rows → continue to Step 1.

2. **Step 1 — Plan (SKILL chat):**
   - **Auto-discover** (9th review [CRIT-22]): `bash -c "ls -t docs/superpowers/plans/*.md 2>/dev/null | head -1"`. If found, ask user "Use this plan? <path>" (y/n). User can also paste different path or skip.
   - If user provides plan → Agent tool 4-axis review:
     - prompt: `references/review-prompt.md` + plan body
     - subagent_type: `general-purpose`
     - returns 4 axis verdicts + `## 종합: APPROVED | CHANGES_NEEDED`
   - **CHANGES_NEEDED handling** (9th review [CRIT-21]):
     - SKILL parses each FAIL with location/reason from subagent output.
     - For each, SKILL drafts a fix proposal (diff or rewrite snippet) and presents to user via chat.
     - User approves each fix → SKILL writes back to plan file via Edit tool.
     - After all fixes applied, re-run review *once* (one retry max — avoid infinite loop). If still CHANGES_NEEDED, SKILL summarizes remaining gaps and asks user: "proceed despite gaps?" (yes → continue, no → abort).
   - **Preset suggestion** (9th review [MINOR-24]):
     - After APPROVED, *SKILL itself* (no subagent) applies heuristics in `references/presets.md` to the plan body:
       - keyword/path scan (Test:, tests/, "research", "security", Create:-count).
       - returns one recommended preset + reasoning.
   - If user skips plan → directly proceed to preset choice.
   - **Preset choice** (5 options): default / feature-team / research / code-review / custom.
   - **Custom branch** (9th review [MAJOR-23]):
     - Worker roles inventory: `prompts/roles/02-development/*.md` (dev, researcher) and `prompts/roles/04-security/*.md` (security), plus `prompts/roles/03-quality/tester.md`.
     - Reviewer roles inventory: `prompts/roles/03-quality/reviewer-{spec,arch,quality}.md` (excluding `reviewer-common.md`).
     - AskUserQuestion: which worker roles (multi-select). For each chosen role ask count (1-3) and model (`opus|sonnet|haiku`, recommended default sonnet).
     - AskUserQuestion: which reviewer roles (multi-select, optional).
     - Assemble `--workers "name1:role1:model1,name2:role2:model2,..."` (matches agenphony-up.sh `WORKERS_ARG` format).
     - Validation: SKILL checks every role file exists via Bash test; reject with clear error if missing.

3. **Step 2 — Mode (SKILL chat, dynamic):**
   - Bash: `tmux list-sessions -F '#{session_name}' | grep -E '^(agenphony-|_SYMPHONY$)' | wc -l`
   - count ≥ 1 → ask user: Single vs Multi-view
   - count = 0 → mode=single auto, inform user

4. **Step 3 — Project (SKILL chat):**
   - Options: Current(cwd) / Bookmarks / Custom
   - For Current: ask user their project root (SKILL cannot trust its own cwd — claude code Bash tool cwd is fixed to harness root). User pastes path or types alias.
   - For Bookmarks: `bash bin/agenphony-bookmarks.sh list` → present rows to user → user picks number or alias
   - For Custom: ask path/alias from user
   - **Resolve to absolute path:** `bash bin/agenphony-main.sh resolve-path --input <user-input>` → returns resolved path or exit 1.

5. **Step 4 — Launch command output (Bash, non-interactive):**
   ```
   bash bin/agenphony-main.sh launch \
     --project <resolved-path> \
     --mode-launch <single|multi> \
     [--preset <name>|--workers <spec>] \
     [--plan <path>]
   ```
   main.sh prints the agenphony-up.sh command + `# AGPN_META: session=<n> mode=<m>` line.

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
   - SKILL fetches current live agenphony-* sessions (Bash): `tmux list-sessions -F '#{session_name}' 2>/dev/null | grep '^agenphony-' || true`
   - **Excluding `launch_session`** from the result list, compute `existing[]`.
   - Branch:
     - `tmux has-session -t _SYMPHONY` → exit 0 → `bash bin/agenphony-symphony.sh add <launch_session>`
     - else → `bash bin/agenphony-symphony.sh compose <existing[]...> <launch_session>`
   - symphony.sh dedupes defensively, but SKILL should send a clean list.

8. **Step 6 — Attach guidance:** SKILL prints to user `tmux attach -t _SYMPHONY` (multi-view) or `tmux attach -t <launch_session>` (single) → user runs with `!`. SKILL turn ends.

### `/agpn down`
Bash: `bash bin/agenphony-down-menu.sh` — auto, menu + multi-select.

### `/agpn symphony [action]`
Bash: `bash bin/agenphony-symphony.sh <action> [args]` — auto.
actions: `compose <s1> [s2...]` | `add <s>` | `detach <w...>` | `disband` | `kill <w...>`

### `/agpn bookmarks [action]`
Bash: `bash bin/agenphony-bookmarks.sh <action>` — auto.
actions: `list` | `set-alias` | `remove` | `prune` | `menu` (default)

### Deprecated (notice + exit)
- `/agpn plan` → "write plan externally, then /agpn picks it up via --plan"
- `/agpn stage` → "merged into /agpn"
- `/agpn list` → "use /agpn (Step 0 resume) or /agpn bookmarks list"

## References

- `references/review-prompt.md` — 4-axis review subagent prompt
- `references/presets.md` — preset suggestion heuristics
- spec: `docs/superpowers/specs/2026-05-27-agpn-unified-entry-symphony.md`
