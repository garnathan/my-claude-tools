---
name: feature-state
description: Flip a feature's lifecycle state in its idea.md frontmatter — pause it while waiting on a blocker, mark it replaced by a newer feature, abandon it, or resume it to active. Validates the companion field each non-active state requires (pausedReason / replacedBy / abandonedReason) and lets the edit hook regenerate the dashboard and sync replaces↔replacedBy. Use when a feature is blocked and on hold, superseded by another, dropped from scope, or ready to resume. Litmus: the feature's `state:` (and its companion field) reflect reality, and the dashboard moves it to the right section.
allowed-tools: Read, Edit, Bash
---

# feature-state — change a feature's state

The state overlay is orthogonal to lifecycle (backlog → in progress → completed). A feature is always in exactly one `state ∈ {active, paused, replaced, abandoned}`. This workflow flips that field and the companion field the new state requires, in `docs/features/<id>/idea.md`. Editing `idea.md` triggers the PostToolUse hook to regenerate the dashboard and to sync `replaces`↔`replacedBy` and `epic`↔`children`.

## Step 1 — Parse arguments

`$ARGUMENTS`: `<feature-id> <state> [--reason "..."] [--replaced-by <id>]`

Examples:
- `/feature-state user-roles paused --reason "Waiting on auth team"`
- `/feature-state old-export replaced --replaced-by new-export`
- `/feature-state nice-to-have abandoned --reason "Out of scope"`
- `/feature-state stuck-feature active` (resume from paused or a tombstone)

Extract `<feature-id>` (required), `<state>` (one of the four), `--reason` (used for `paused` → `pausedReason`, or `abandoned` → `abandonedReason`), and `--replaced-by <id>` (used for `replaced` → `replacedBy`). If anything is missing or malformed, show usage and stop.

## Step 2 — Load the feature

Read `docs/features/<feature-id>/idea.md`. If it doesn't exist:
> "No feature `<feature-id>`. Check `docs/features/` or run `/feature-search`."

If `shipped.md` exists AND the target state is `replaced` or `abandoned`, refuse:
> "`<feature-id>` is already shipped — tombstoning it makes no sense. To reverse it, revert the PR and remove `shipped.md` first."

## Step 3 — Validate the required companion

| Target state | Required argument | Frontmatter field written |
|---|---|---|
| `paused` | `--reason "..."` | `pausedReason` |
| `replaced` | `--replaced-by <id>` | `replacedBy` |
| `abandoned` | `--reason "..."` | `abandonedReason` |
| `active` | none | — |

If the required companion is missing, ask the user for it before proceeding. For `replaced`, also check the referenced ID has an `idea.md` on disk; if not, warn but allow it (forward reference — the new feature may not be captured yet).

## Step 4 — Update the frontmatter

Edit `docs/features/<feature-id>/idea.md`:

1. **Set `state:`** — replace the existing `state:` line, or insert one after `id:`.
2. **Set the companion field** — same insert-or-replace pattern.
3. **Clean up obsolete companions** when resuming to `active`:
   - from `paused` → remove `pausedReason`
   - from `replaced` → remove `replacedBy`
   - from `abandoned` → remove `abandonedReason`

Touch nothing else — the valid frontmatter keys are exactly: `id`, `name`, `type`, `priority`, `effort`, `impact`, `category`, `created`, `dependsOn`, `relatedTo`, `parallelSafe`, `assignee`, `epic`, `children`, `state`, `pausedReason`, `replacedBy`, `abandonedReason`, `replaces`, `review`. Do not introduce others.

## Step 5 — Confirm

The PostToolUse hook regenerates `DASHBOARD.md` and runs the `replaces`↔`replacedBy` / `epic`↔`children` sync automatically on the edit — no manual regen. Print a one-line confirmation:
> "✓ `<feature-id>` is now `<state>`. <companion field summary>"

## Step 6 — Suggest a follow-up

| New state | Suggest |
|---|---|
| paused | "When the blocker clears, run `/feature-state <id> active` to resume." |
| replaced | "If `<replaced-by-id>` isn't captured yet, run `/feature-capture` to create it." |
| abandoned | (none — terminal for now) |
| active (resumed) | "Resume with `/feature-implement <id>`." |

## Notes

- This is the only correct way to tombstone a feature. Never delete the directory — the history is the whole point.
- State changes are reversible; `paused → active → paused` is fine.
